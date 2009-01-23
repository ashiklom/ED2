!==========================================================================================!
!==========================================================================================!
! Subroutine odeint_ar                                                                     !
!                                                                                          !
!     This subroutine will drive the integration of several ODEs that drive the fast-scale !
! state variables.                                                                         !
!------------------------------------------------------------------------------------------!
subroutine odeint_ar(h1,csite,ipa,isi,ipy,ifm,integration_buff,rhos,vels   &
                    ,atm_tmp,atm_shv,atm_co2,geoht,exner,pcpg,qpcpg,dpcpg,prss,lsl)

   use ed_state_vars  , only : integration_vars_ar & ! structure
                             , sitetype            & ! structure
                             , patchtype           ! ! structure
   use rk4_coms       , only : maxstp              & ! intent(in)
                             , tbeg                & ! intent(in)
                             , tend                & ! intent(in)
                             , dtrk4               & ! intent(in)
                             , dtrk4i              ! ! intent(in)
   use rk4_stepper_ar , only : rkqs_ar             ! ! subroutine
   use ed_misc_coms   , only : fast_diagnostics    ! ! intent(in)
   use hydrology_coms , only : useRUNOFF           ! ! intent(in)
   use grid_coms      , only : nzg                 ! ! intent(in)
   use soil_coms      , only : dslz                & ! intent(in)
                             , min_sfcwater_mass   & ! intent(in)
                             , runoff_time         ! ! intent(in)
   use consts_coms    , only : cliq                & ! intent(in)
                             , t3ple               & ! intent(in)
                             , tsupercool          & ! intent(in)
                             , wdnsi               ! ! intent(in)
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   type(integration_vars_ar) , target      :: integration_buff ! RK4 variables
   type(sitetype)            , target      :: csite            ! Current site
   integer                   , intent(in)  :: ipa              ! Current patch ID
   integer                   , intent(in)  :: isi              ! Current site ID
   integer                   , intent(in)  :: ipy              ! Current polygon ID
   integer                   , intent(in)  :: ifm              ! Current grid ID
   integer                   , intent(in)  :: lsl              ! Lowest soil point
   real                      , intent(in)  :: rhos             ! Air density
   real                      , intent(in)  :: vels             ! Air wind speed
   real                      , intent(in)  :: atm_tmp          ! Air temperature
   real                      , intent(in)  :: atm_shv          ! Air specific humidity
   real                      , intent(in)  :: atm_co2          ! Air CO2 mixing ratio
   real                      , intent(in)  :: geoht            ! Geopotential height
   real                      , intent(in)  :: exner            ! Exner function
   real                      , intent(in)  :: pcpg             ! Precipitation rate
   real                      , intent(in)  :: qpcpg            ! Precipitation heat rate
   real                      , intent(in)  :: dpcpg            ! Precipitation "depth flux"
   real                      , intent(in)  :: prss             ! Air pressure
   real                                    :: h1               ! First guess of delta-t
   !----- Local variables -----------------------------------------------------------------!
   type(patchtype)           , pointer     :: cpatch           ! Current patch
   integer                                 :: i                ! Step counter
   integer                                 :: ksn              ! # of snow/water layers
   real                                    :: x                ! Elapsed time
   real                                    :: h                ! Current delta-t attempt
   real                                    :: hnext            ! Next delta-t
   real                                    :: hdid             ! delta-t that worked (???)
   real                                    :: qwfree           ! Free water internal energy
   real                                    :: wfreeb           ! Free water 
   !----- Saved variables -----------------------------------------------------------------!
   logical, save    :: first_time=.true.
   logical, save    :: skiprunoff
   !---------------------------------------------------------------------------------------!
   
   !----- Checking whether we will use runoff or not, and saving this check to save time. -!
   if (first_time) then
      skiprunoff = .false. ! useRUNOFF == 0
      first_time = .false.
   end if


   !---------------------------------------------------------------------------------------!
   !    If top snow layer is too thin for computational stability, have it evolve in       !
   ! thermal equilibrium with top soil layer.                                              !
   !---------------------------------------------------------------------------------------!
   call stabilize_snow_layers_ar(integration_buff%initp, csite,ipa, 0.0, lsl)



   !---------------------------------------------------------------------------------------!
   !     Create temporary patches.                                                         !
   !---------------------------------------------------------------------------------------!
   cpatch => csite%patch(ipa)
   call copy_rk4_patch_ar(integration_buff%initp, integration_buff%y,cpatch,lsl)


   !---------------------------------------------------------------------------------------!
   ! Set initial time and stepsize.                                                        !
   !---------------------------------------------------------------------------------------!
   x = tbeg
   h = h1
   if (dtrk4 < 0.0) h = -h1

   !---------------------------------------------------------------------------------------!
   ! Begin timestep loop                                                                   !
   !---------------------------------------------------------------------------------------!
   timesteploop: do i=1,maxstp

      !----- Get initial derivatives ------------------------------------------------------!
      call leaf_derivs_ar(integration_buff%y,integration_buff%dydx,csite,ipa,isi,ipy,rhos  &
                         ,prss,pcpg,qpcpg,dpcpg,atm_tmp,exner,geoht,vels,atm_shv,atm_co2   &
                         ,lsl)

      !----- Get scalings used to determine stability -------------------------------------!
      call get_yscal_ar(integration_buff%y, integration_buff%dydx,h,integration_buff%yscal &
                       ,cpatch,lsl)

      !----- Be sure not to overstep ------------------------------------------------------!
      if((x+h-tend)*(x+h-tbeg) > 0.0) h=tend-x

      !----- Take the step ----------------------------------------------------------------!
      call rkqs_ar(integration_buff,x,h,hdid,hnext,csite,ipa,isi,ipy,ifm,rhos,vels,atm_tmp &
                  ,atm_shv,atm_co2,geoht,exner,pcpg,qpcpg,dpcpg,prss,lsl)

      !----- Re-calculate tempks, fracliqs, surface water flags. --------------------------!
      call stabilize_snow_layers_ar(integration_buff%y, csite,ipa, 0.0, lsl)

      !----- If the integration reached the next step, make some final adjustments --------!
      if((x-tend)*dtrk4 >= 0.0)then

         csite%wbudget_loss2runoff(ipa) = 0.0
         csite%ebudget_loss2runoff(ipa) = 0.0
         ksn = integration_buff%y%nlev_sfcwater

         !---------------------------------------------------------------------------------!
         !   Make temporary surface liquid water disappear.                                !
         !---------------------------------------------------------------------------------!
         !!!!!    Do we really want to get rid of these ponds? Especially thinking in a !!!!
         !!!!! coupled run, this causes mass violation. I can see this making sense in  !!!!
         !!!!! SOI runs, perhaps this should be the condition to apply this. Regional   !!!!
         !!!!! runs perhaps, because it is not really coupled to the atmosphere, but in !!!!
         !!!!! coupled runs this definitely looks like a problem...                     !!!!
         !---------------------------------------------------------------------------------!
         if (skiprunoff .and. ksn >= 1) then
         
            if (integration_buff%y%sfcwater_mass(ksn) > 0.0   .and.                        &
                integration_buff%y%sfcwater_fracliq(ksn) > 0.1) then

               wfreeb = integration_buff%y%sfcwater_mass(ksn)                              &
                      * (integration_buff%y%sfcwater_fracliq(ksn) - .1)                    &
                      / 0.9 * min(1.0,runoff_time*hdid) 
               qwfree = wfreeb                                                             &
                      * cliq * (integration_buff%y%sfcwater_tempk(ksn) - tsupercool )

               integration_buff%y%sfcwater_mass(ksn) =                                     &
                                   integration_buff%y%sfcwater_mass(ksn)                   &
                                 - wfreeb

               integration_buff%y%sfcwater_depth(ksn) =                                    &
                                   integration_buff%y%sfcwater_depth(ksn)                  &
                                 - wfreeb*wdnsi

               !----- Recompute the energy removing runoff --------------------------------!
               if (integration_buff%y%sfcwater_mass(ksn) >= min_sfcwater_mass) then
                  integration_buff%y%sfcwater_energy(ksn) =                                &
                                     integration_buff%y%sfcwater_energy(ksn) - qwfree
                                    
               else
                  integration_buff%y%sfcwater_energy(ksn) = 0.0
               end if
            
               call stabilize_snow_layers_ar(integration_buff%y,csite,ipa,0.0,lsl)

               !----- Compute runoff for output -------------------------------------------!
               if(fast_diagnostics) then
                  csite%runoff(ipa) = csite%runoff(ipa) + wfreeb * dtrk4i
                  csite%avg_runoff(ipa) = csite%avg_runoff(ipa) + wfreeb
                  csite%avg_runoff_heat(ipa) = csite%avg_runoff_heat(ipa) + qwfree
                  csite%wbudget_loss2runoff(ipa) = wfreeb
                  csite%ebudget_loss2runoff(ipa) = qwfree
               end if

            else
               csite%runoff(ipa)              = 0.0
               csite%avg_runoff(ipa)          = 0.0
               csite%avg_runoff_heat(ipa)     = 0.0
               csite%wbudget_loss2runoff(ipa) = 0.0
               csite%ebudget_loss2runoff(ipa) = 0.0
            end if
         else
            csite%runoff(ipa)              = 0.0
            csite%avg_runoff(ipa)          = 0.0
            csite%avg_runoff_heat(ipa)     = 0.0
            csite%wbudget_loss2runoff(ipa) = 0.0
            csite%ebudget_loss2runoff(ipa) = 0.0
         end if

         !------ Copying the temporary patch to the next intermediate step ----------------!
         call copy_rk4_patch_ar(integration_buff%y,integration_buff%initp, cpatch, lsl)
         !------ Updating the substep for next time and leave -----------------------------!
         csite%htry(ipa) = hnext

         return
      end if
      
      !----- Use hnext as the next substep ------------------------------------------------!
      h = hnext
   end do timesteploop

   !----- If it reached this point, that is really bad news... ----------------------------!
   print*,'Too many steps in routine odeint'
   call print_patch_ar(integration_buff%y, csite,ipa, lsl)
   call fatal_error('Too many steps, I give up!','odeint_ar','rk4_integ_utils.f90')

   return
end subroutine odeint_ar
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This subroutine copies that variables that are integrated by the Runge-Kutta solver   !
! to a buffer structure.                                                                   !
!------------------------------------------------------------------------------------------!
subroutine copy_patch_init_ar(sourcesite,ipa, targetp, lsl)
   use ed_state_vars , only :  sitetype           & ! structure
                            ,  rk4patchtype       & ! structure
                            ,  patchtype          ! ! structure
   use grid_coms     , only :  nzg                & ! integer(in)
                            ,  nzs                ! ! integer(in) 
   use soil_coms     , only :  water_stab_thresh  & ! integer(in)
                            , min_sfcwater_mass   ! ! integer(in)
   use ed_misc_coms  , only :  fast_diagnostics   ! ! integer(in)
   implicit none

   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype) , target     :: targetp
   type(sitetype)     , target     :: sourcesite
   integer            , intent(in) :: lsl
   integer            , intent(in) :: ipa
   !----- Local variables -----------------------------------------------------------------!
   type(patchtype)    , pointer    :: cpatch
   integer                         :: ico
   integer                         :: k
   !---------------------------------------------------------------------------------------!



   targetp%can_temp  = sourcesite%can_temp(ipa)
   targetp%can_shv   = sourcesite%can_shv(ipa)
   targetp%can_co2   = sourcesite%can_co2(ipa)

   do k = lsl, nzg
      targetp%soil_water(k)   = sourcesite%soil_water(k,ipa)
      targetp%soil_energy(k)  = sourcesite%soil_energy(k,ipa)
      targetp%soil_tempk(k)   = sourcesite%soil_tempk(k,ipa)
      targetp%soil_fracliq(k) = sourcesite%soil_fracliq(k,ipa)
   end do

   do k = 1, nzs
      targetp%sfcwater_mass(k)    = sourcesite%sfcwater_mass(k,ipa)
      targetp%sfcwater_depth(k)   = sourcesite%sfcwater_depth(k,ipa)
      !----- Converting sfcwater_energy to J/m� inside the Runge-Kutta integrator. --------!
      targetp%sfcwater_energy(k)  = sourcesite%sfcwater_energy(k,ipa)                      &
                                  * sourcesite%sfcwater_mass(k,ipa)
      targetp%sfcwater_tempk(k)   = sourcesite%sfcwater_tempk(k,ipa)
      targetp%sfcwater_fracliq(k) = sourcesite%sfcwater_fracliq(k,ipa)
   end do


   targetp%ustar = sourcesite%ustar(ipa)
   targetp%cstar = sourcesite%cstar(ipa)
   targetp%tstar = sourcesite%tstar(ipa)
   targetp%rstar = sourcesite%rstar(ipa)


   targetp%upwp = sourcesite%upwp(ipa)
   targetp%wpwp = sourcesite%wpwp(ipa)
   targetp%tpwp = sourcesite%tpwp(ipa)
   targetp%rpwp = sourcesite%rpwp(ipa)

  
   targetp%nlev_sfcwater = sourcesite%nlev_sfcwater(ipa)


   !----- The virtual pools should be always zero, they are temporary entities ------------!
   targetp%virtual_water = 0.0
   targetp%virtual_heat  = 0.0
   targetp%virtual_depth = 0.0

   if (targetp%nlev_sfcwater == 0) then
      targetp%virtual_flag = 2
   else
      if (targetp%sfcwater_mass(1) < min_sfcwater_mass) then
         targetp%virtual_flag = 2
      elseif (targetp%sfcwater_mass(1) < water_stab_thresh) then
         targetp%virtual_flag = 1
      else
         targetp%virtual_flag = 0
      end if
   end if

   cpatch => sourcesite%patch(ipa)
   do ico = 1,cpatch%ncohorts
      targetp%veg_water(ico)     = cpatch%veg_water(ico)
      targetp%veg_energy(ico)    = cpatch%veg_energy(ico)
   enddo

   !----- Diagnostics variables -----------------------------------------------------------!
   if(fast_diagnostics) then

      targetp%wbudget_loss2atm   = sourcesite%wbudget_loss2atm(ipa)
      targetp%ebudget_loss2atm   = sourcesite%ebudget_loss2atm(ipa)
      targetp%co2budget_loss2atm = sourcesite%co2budget_loss2atm(ipa)
      targetp%ebudget_latent     = sourcesite%ebudget_latent(ipa)
      targetp%avg_carbon_ac      = sourcesite%avg_carbon_ac(ipa)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!! WHY IS THIS COMMENTED OUT? RGK                                             !!!!!
      !   targetp%avg_gpp = sourcesite%avg_gpp(ipa)
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      targetp%avg_vapor_vc       = sourcesite%avg_vapor_vc(ipa)
      targetp%avg_dew_cg         = sourcesite%avg_dew_cg(ipa)
      targetp%avg_vapor_gc       = sourcesite%avg_vapor_gc(ipa)
      targetp%avg_wshed_vg       = sourcesite%avg_wshed_vg(ipa)
      targetp%avg_vapor_ac       = sourcesite%avg_vapor_ac(ipa)
      targetp%avg_transp         = sourcesite%avg_transp(ipa)
      targetp%avg_evap           = sourcesite%avg_evap(ipa)
      targetp%avg_netrad         = sourcesite%avg_netrad(ipa)
      targetp%aux                = sourcesite%aux(ipa)
      targetp%avg_sensible_vc    = sourcesite%avg_sensible_vc(ipa)
      targetp%avg_sensible_2cas  = sourcesite%avg_sensible_2cas(ipa)
      targetp%avg_qwshed_vg      = sourcesite%avg_qwshed_vg(ipa)
      targetp%avg_sensible_gc    = sourcesite%avg_sensible_gc(ipa)
      targetp%avg_sensible_ac    = sourcesite%avg_sensible_ac(ipa)
      targetp%avg_sensible_tot   = sourcesite%avg_sensible_tot(ipa)

      do k = lsl, nzg
         targetp%avg_sensible_gg(k) = sourcesite%avg_sensible_gg(k,ipa)
         targetp%avg_smoist_gg(k)   = sourcesite%avg_smoist_gg(k,ipa)
         targetp%avg_smoist_gc(k)   = sourcesite%avg_smoist_gc(k,ipa)
         targetp%aux_s(k)           = sourcesite%aux_s(k,ipa)
      end do
   end if

   return
end subroutine copy_patch_init_ar
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This subroutines increment the derivative into the previous guess to create the new   !
! guess.                                                                                   !
!------------------------------------------------------------------------------------------!
subroutine inc_rk4_patch_ar(rkp, inc, fac, cpatch, lsl)
   use ed_state_vars , only : sitetype          & ! structure
                            , patchtype         & ! structure
                            , rk4patchtype      ! ! structure
   use grid_coms     , only : nzg               & ! intent(in)
                            , nzs               ! ! intent(in)
   use ed_misc_coms  , only : fast_diagnostics  ! ! intent(in)
  
   implicit none

   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype) , target     :: rkp    ! Temporary patch with previous state
   type(rk4patchtype) , target     :: inc    ! Temporary patch with its derivatives
   type(patchtype)    , target     :: cpatch ! Current patch (for characteristics)
   real               , intent(in) :: fac    ! Increment factor
   integer            , intent(in) :: lsl    ! Lowest soil level
   !----- Local variables -----------------------------------------------------------------!
   integer                         :: ico    ! Cohort ID
   integer                         :: k      ! Counter
   !---------------------------------------------------------------------------------------!


   rkp%can_temp = rkp%can_temp  + fac * inc%can_temp
   rkp%can_shv  = rkp%can_shv   + fac * inc%can_shv
   rkp%can_co2  = rkp%can_co2   + fac * inc%can_co2

   do k=lsl,nzg
      rkp%soil_water(k)       = rkp%soil_water(k)  + dble(fac) * inc%soil_water(k)
      rkp%soil_energy(k)      = rkp%soil_energy(k) + fac * inc%soil_energy(k)
   end do

   do k=1,rkp%nlev_sfcwater
      rkp%sfcwater_mass(k)   = max(0.0,rkp%sfcwater_mass(k)   + fac * inc%sfcwater_mass(k))
      rkp%sfcwater_energy(k) = rkp%sfcwater_energy(k) + fac * inc%sfcwater_energy(k)
      rkp%sfcwater_depth(k)  = rkp%sfcwater_depth(k)  + fac * inc%sfcwater_depth(k)
   end do

   rkp%virtual_heat  = rkp%virtual_heat  + fac * inc%virtual_heat
   rkp%virtual_water = rkp%virtual_water + fac * inc%virtual_water
   rkp%virtual_depth = rkp%virtual_depth + fac * inc%virtual_depth

  
   rkp%upwp = rkp%upwp + fac * inc%upwp
   rkp%wpwp = rkp%wpwp + fac * inc%wpwp
   rkp%tpwp = rkp%tpwp + fac * inc%tpwp
   rkp%rpwp = rkp%rpwp + fac * inc%rpwp

  
   do ico = 1,cpatch%ncohorts
      rkp%veg_water(ico)     = max(0.0,rkp%veg_water(ico) + fac * inc%veg_water(ico))
      rkp%veg_energy(ico)    = rkp%veg_energy(ico) + fac * inc%veg_energy(ico)
   enddo

   if(fast_diagnostics) then

      rkp%wbudget_loss2atm   = rkp%wbudget_loss2atm   + fac * inc%wbudget_loss2atm
      rkp%ebudget_loss2atm   = rkp%ebudget_loss2atm   + fac * inc%ebudget_loss2atm
      rkp%co2budget_loss2atm = rkp%co2budget_loss2atm + fac * inc%co2budget_loss2atm
      rkp%ebudget_latent     = rkp%ebudget_latent     + fac * inc%ebudget_latent

      rkp%avg_carbon_ac      = rkp%avg_carbon_ac      + fac * inc%avg_carbon_ac
      rkp%avg_gpp            = rkp%avg_gpp            + fac * inc%avg_gpp
      
      rkp%avg_vapor_vc       = rkp%avg_vapor_vc       + fac * inc%avg_vapor_vc
      rkp%avg_dew_cg         = rkp%avg_dew_cg         + fac * inc%avg_dew_cg  
      rkp%avg_vapor_gc       = rkp%avg_vapor_gc       + fac * inc%avg_vapor_gc
      rkp%avg_wshed_vg       = rkp%avg_wshed_vg       + fac * inc%avg_wshed_vg
      rkp%avg_vapor_ac       = rkp%avg_vapor_ac       + fac * inc%avg_vapor_ac
      rkp%avg_transp         = rkp%avg_transp         + fac * inc%avg_transp  
      rkp%avg_evap           = rkp%avg_evap           + fac * inc%avg_evap  
      rkp%avg_netrad         = rkp%avg_netrad         + fac * inc%avg_netrad      
      rkp%aux                = rkp%aux                + fac * inc%aux
      rkp%avg_sensible_vc    = rkp%avg_sensible_vc    + fac * inc%avg_sensible_vc  
      rkp%avg_sensible_2cas  = rkp%avg_sensible_2cas  + fac * inc%avg_sensible_2cas
      rkp%avg_qwshed_vg      = rkp%avg_qwshed_vg      + fac * inc%avg_qwshed_vg    
      rkp%avg_sensible_gc    = rkp%avg_sensible_gc    + fac * inc%avg_sensible_gc  
      rkp%avg_sensible_ac    = rkp%avg_sensible_ac    + fac * inc%avg_sensible_ac  
      rkp%avg_sensible_tot   = rkp%avg_sensible_tot   + fac * inc%avg_sensible_tot 

      do k=lsl,nzg
         rkp%avg_sensible_gg(k)  = rkp%avg_sensible_gg(k)  + fac * inc%avg_sensible_gg(k)
         rkp%avg_smoist_gg(k)    = rkp%avg_smoist_gg(k)    + fac * inc%avg_smoist_gg(k)  
         rkp%avg_smoist_gc(k)    = rkp%avg_smoist_gc(k)    + fac * inc%avg_smoist_gc(k)  
         rkp%aux_s(k)            = rkp%aux_s(k)            + fac * inc%aux_s(k)
      end do

   end if

   return
end subroutine inc_rk4_patch_ar

!==============================================================

subroutine get_yscal_ar(y, dy, htry, yscal, cpatch, lsl)
  
  use ed_state_vars,only : patchtype,rk4patchtype
  use rk4_coms, only : tiny_offset
  use grid_coms, only: nzg, nzs
  use soil_coms, only: min_sfcwater_mass
  use consts_coms, only: cliq,cicet3
  use canopy_radiation_coms, only: lai_min
  use pft_coms, only: sla

  implicit none

  type(patchtype),target :: cpatch
  type(rk4patchtype),target :: y,dy,yscal
  integer :: ico
  integer, intent(in) :: lsl
  real :: htry
  integer :: k
  real, parameter :: sfc_min = 1.0
  
  yscal%can_temp = abs(y%can_temp) + abs(dy%can_temp*htry) + tiny_offset
  yscal%can_shv  = abs(y%can_shv)  + abs(dy%can_shv*htry)  + tiny_offset
  yscal%can_co2  = abs(y%can_co2)  + abs(dy%can_co2*htry)  + tiny_offset
  
  yscal%upwp = max(abs(y%upwp) + abs(dy%upwp*htry),1.0)
  yscal%wpwp = max(abs(y%wpwp) + abs(dy%wpwp*htry),1.0)


  
  do k=lsl,nzg
     yscal%soil_water(k) = abs(y%soil_water(k)) + abs(dy%soil_water(k)*htry) + tiny_offset
     yscal%soil_energy(k) = abs(y%soil_energy(k)) + abs(dy%soil_energy(k)*htry)
  end do

  if(y%sfcwater_mass(1) > 0.1 .or. y%nlev_sfcwater > 1)then
     ! Either frozen or computationally stable layer
     do k=1,nzs
        yscal%sfcwater_mass(k) = abs(y%sfcwater_mass(k))  &
             + abs(dy%sfcwater_mass(k)*htry) + tiny_offset
        yscal%sfcwater_energy(k) = abs(y%sfcwater_energy(k))  &
             + abs(dy%sfcwater_energy(k)*htry) + tiny_offset
        yscal%sfcwater_depth(k) = abs(y%sfcwater_depth(k))  &
             + abs(dy%sfcwater_depth(k)*htry) + tiny_offset
     enddo
  else
     ! Low stability threshold
     do k=1,nzs
        yscal%sfcwater_mass(k) = 0.1
        if(y%sfcwater_mass(k) > min_sfcwater_mass)then
           yscal%sfcwater_energy(k) = ( yscal%sfcwater_mass(k) / y%sfcwater_mass(k))       &
                                    * ( abs( y%sfcwater_energy(k))                         &
                                      + abs(dy%sfcwater_energy(k)))
        else
           yscal%sfcwater_energy(k) = 1.0e30
        endif
     enddo
  endif
  
  yscal%virtual_water = 0.1
  yscal%virtual_heat = cliq * 110.0 * yscal%virtual_water
  

  do ico = 1,cpatch%ncohorts
     if (cpatch%lai(ico) > lai_min) then
        yscal%veg_water(ico) = 0.22
        yscal%veg_energy(ico) = abs(y%veg_energy(ico)) + abs(dy%veg_energy(ico)*htry)
     else
        yscal%veg_water(ico) = 1.e30
        yscal%veg_energy(ico) = 1.e30
     end if

  end do


  return
end subroutine get_yscal_ar

!=================================================================

subroutine get_errmax_ar(errmax, yerr, yscal, cpatch, lsl, y, ytemp)

  use ed_state_vars,only:patchtype,rk4patchtype
  use rk4_coms, only: rk4eps

  use grid_coms, only: nzg
  use canopy_radiation_coms, only: lai_min
  use misc_coms, only: integ_err, record_err

  implicit none
  
  integer, intent(in) :: lsl
  type(patchtype),target :: cpatch
  type(rk4patchtype),target :: yerr,yscal,y,ytemp
  integer :: ico
  real :: errmax,errh2o,errene,err,errh2oMAX,erreneMAX
  integer :: k
!  integer,save:: count
!  real,save ::   errctemp
!  real,save ::  errcvap
!  real,save ::  errcco2
!  real,save ::  errswat(12)
!  real,save ::  errseng(12)
!  real,save ::  errvh
!  real,save ::  errvw
!  real,save ::  errvegw(50)
!  real,save ::  errvege(50)

  errmax = 0.0

  err = abs(yerr%can_temp/yscal%can_temp)
  errmax = max(errmax,err)
  if(record_err .and. err .gt. rk4eps) integ_err(1,1) = integ_err(1,1) + 1_8 

  err = abs(yerr%can_shv/yscal%can_shv)
  errmax = max(errmax,err)
  if(record_err .and. err .gt. rk4eps) integ_err(2,1) = integ_err(2,1) + 1_8 

  err = abs(yerr%can_co2/yscal%can_co2)
  errmax = max(errmax,err)
  if(record_err .and. err .gt. rk4eps) integ_err(3,1) = integ_err(3,1) + 1_8 
  
  do k=lsl,nzg
     err = real(abs(yerr%soil_water(k)/yscal%soil_water(k)))
     errmax = max(errmax,err)
     if(record_err .and. err .gt. rk4eps) integ_err(3+k,1) = integ_err(3+k,1) + 1_8 
  end do

  do k=lsl,nzg
     err = abs(yerr%soil_energy(k)/yscal%soil_energy(k))
     errmax = max(errmax,err)
     if(record_err .and. err .gt. rk4eps) integ_err(15+k,1) = integ_err(15+k,1) + 1_8      
  enddo

  do k=1,ytemp%nlev_sfcwater
     err = abs(yerr%sfcwater_energy(k) / yscal%sfcwater_energy(k))
     errmax = max(errmax,err)
     if(record_err .and. err .gt. rk4eps) integ_err(27+k,1) = integ_err(27+k,1) + 1_8      
  enddo

  do k=1,ytemp%nlev_sfcwater
     err = abs(yerr%sfcwater_mass(k) / yscal%sfcwater_mass(k))
     errmax = max(errmax,err)
     if(record_err .and. err .gt. rk4eps) integ_err(32+k,1) = integ_err(32+k,1) + 1_8      
  enddo

  err = abs(yerr%virtual_heat/yscal%virtual_heat)
  errmax = max(errmax,err)
  if(record_err .and. err .gt. rk4eps) integ_err(38,1) = integ_err(38,1) + 1_8      

  err = abs(yerr%virtual_water/yscal%virtual_water)
  errmax = max(errmax,err)
  if(record_err .and. err .gt. rk4eps) integ_err(39,1) = integ_err(39,1) + 1_8      

!  write (unit=40,fmt='(132a)') ('-',k=1,132)
!  write (unit=40,fmt='(2(a5,1x),8(a14,1x))') &
!    '  COH','  PFT','           LAI','        ERRH2O','        ERRENE','        ERRMAX'    &
!                   ,'  YERR%VEG_H2O',' YSCAL%VEG_H2O',' YERR%VEG_ENER','YSCAL%VEG_ENER'
  do ico = 1,cpatch%ncohorts
     
     errh2oMAX = 0.0
     erreneMAX = 0.0
     if(cpatch%lai(ico).gt.lai_min)then
        errh2o = abs(yerr%veg_water(ico)/yscal%veg_water(ico))
        errene = abs(yerr%veg_energy(ico)/yscal%veg_energy(ico))
!        write (unit=40,fmt='(2(i5,1x),8(es14.7,1x))') &
!            ico,cpatch%pft(ico),cpatch%lai(ico),errh2o,errene,errmax &
!           ,yerr%veg_water(ico),yscal%veg_water(ico)                 &
!           ,yerr%veg_energy(ico),yscal%veg_energy(ico)
        errmax = max(errmax,errh2o,errene)
        errh2oMAX = max(errh2oMAX,errh2o)
        erreneMAX = max(erreneMAX,errene)
     endif
  end do
  if(cpatch%ncohorts > 0 .and. record_err) then
     if(errh2oMAX > rk4eps) integ_err(40,1) = integ_err(40,1) + 1_8      
     if(erreneMAX > rk4eps) integ_err(41,1) = integ_err(41,1) + 1_8      
  endif

!  write (unit=40,fmt='(132a)') ('-',k=1,132)
!  write (unit=40,fmt='(a)') ' '

  ! If the errror was high, lets log what was the bad egg slowing everyone down
!  if (errmax/(1.0e-2)>1.0) then
!     print*,""
!     print*,"============================================="
!     print*,"CANTEMP:", errctemp
!     errctemp=errctemp+abs(yerr%can_temp/yscal%can_temp)
!     print*,"CANSHV:", errcvap
!     errcvap=errcvap+abs(yerr%can_shv/yscal%can_shv)
!     print*,"CANCO2:",errcco2
!     errcco2=errcco2+abs(yerr%can_co2/yscal%can_co2)
!     do k=lsl,nzg
!        print*,"SOILWAT(",k,"):",errswat(k)
!        errswat(k)=errswat(k) + real(dabs(yerr%soil_water(k)/yscal%soil_water(k)))
!        print*,"SOILENG(",k,"):",errseng(k)
!        errseng(k)=errseng(k) + abs(yerr%soil_energy(k)/yscal%soil_energy(k))
!     enddo
!     print*,"VIRTUAL HEAT:",errvh
!     errvh = errvh + abs(yerr%virtual_heat/yscal%virtual_heat)
!     print*,"VIRTUAL WATER:",errvw
!     errvw = errvw + abs(yerr%virtual_water/yscal%virtual_water)
!     do ico = 1,cpatch%ncohorts
!        if(cpatch%lai(ico).gt.lai_min)then
!           print*,"VEGWAT:(",ico,"):",errvegw(ico)
!           errvegw(ico) = errvegw(ico) + abs(yerr%veg_water(ico)/yscal%veg_water(ico))
!           print*,"VEGENG:(",ico,"):",errvege(ico)
!           errvege(ico) = errvege(ico) + abs(yerr%veg_energy(ico)/yscal%veg_energy(ico))
!        endif
!     end do
!    print*,"============================================="

!    count=count+1
!    if(count==500)stop
!  endif







  return
end subroutine get_errmax_ar

!==================================================================
subroutine print_errmax_ar(errmax, yerr, yscal, cpatch, lsl, y, ytemp)
      
  use ed_state_vars,only:patchtype,rk4patchtype
  use rk4_coms, only: rk4eps
  use grid_coms, only: nzg, nzs
  use canopy_radiation_coms, only: lai_min
  implicit none

  integer, intent(in) :: lsl
  type(patchtype), target :: cpatch
  integer :: ico
  type(rk4patchtype), target :: yerr,yscal,y,ytemp
  real :: errmax
  integer :: k
  real :: error_soil_water,scale_soil_water

  print*,'------------------------------------------------'
  print*,'----   PRINTING ERRMAX INFO --------------------'
  print*,'name     errmax      yerr       yscal'

  errmax = max(0.0,abs(yerr%can_temp/yscal%can_temp))
  print*,'can_temp',errmax,yerr%can_temp,yscal%can_temp
  call print_errmax_flag(yerr%can_temp,yscal%can_temp)

  errmax = max(errmax,abs(yerr%can_shv/yscal%can_shv))
  print*,'can_shv',errmax,yerr%can_shv  &
       ,yscal%can_shv
  call print_errmax_flag(yerr%can_shv,yscal%can_shv)

  errmax = max(errmax,abs(yerr%can_co2/yscal%can_co2))
  print*,'can_co2',errmax,yerr%can_co2,yscal%can_co2
  call print_errmax_flag(yerr%can_co2,yscal%can_co2)

  do k=lsl,nzg
     errmax = sngl(dmax1(dble(errmax),dabs(yerr%soil_water(k)/yscal%soil_water(k))))
     print*,'soil water, level',k,errmax,yerr%soil_water(k),yscal%soil_water(k)
     error_soil_water = sngl(yerr%soil_water(k))
     scale_soil_water = sngl(yscal%soil_water(k))
     call print_errmax_flag(error_soil_water,scale_soil_water)

     errmax = max(errmax,abs(yerr%soil_energy(k)/yscal%soil_energy(k)))
     print*,'soil energy, level',k,errmax,yerr%soil_energy(k),yscal%soil_energy(k)
     call print_errmax_flag(yerr%soil_energy(k),yscal%soil_energy(k))
  enddo
  
  do k=1,yerr%nlev_sfcwater
     errmax = max(errmax,abs(yerr%sfcwater_energy(k)/yscal%sfcwater_energy(k)))
     print*,'sfcwater_energy, level',k,errmax,yerr%sfcwater_energy(k),yscal%sfcwater_energy(k)
     call print_errmax_flag(yerr%sfcwater_energy(k),yscal%sfcwater_energy(k))

     errmax = max(errmax,abs(yerr%sfcwater_mass(k)  &
          /yscal%sfcwater_mass(k)))
     print*,'sfcwater_mass, level',k,errmax,yerr%sfcwater_mass(k),yscal%sfcwater_mass(k), &
          y%sfcwater_mass(k),ytemp%sfcwater_mass(k),ytemp%nlev_sfcwater
     call print_errmax_flag(yerr%sfcwater_mass(k),yscal%sfcwater_mass(k))
  enddo
  
  errmax = max(errmax,abs(yerr%virtual_heat/yscal%virtual_heat))
  print*,'virtual heat',errmax,yerr%virtual_heat,yscal%virtual_heat
  call print_errmax_flag(yerr%virtual_heat,yscal%virtual_heat)

  errmax = max(errmax,abs(yerr%virtual_water/yscal%virtual_water))
  print*,'virtual heat',errmax,yerr%virtual_water,yscal%virtual_water
  call print_errmax_flag(yerr%virtual_water,yscal%virtual_water)
  
  !  errmax = max(errmax,abs(yerr%fast_soil_C/yscal%fast_soil_C))
  !  print*,'fast C',errmax,yerr%fast_soil_C,yscal%fast_soil_C
  !  errmax = max(errmax,abs(yerr%slow_soil_C/yscal%slow_soil_C))
  !  print*,'slow C',errmax,yerr%slow_soil_C,yscal%slow_soil_C
  !  errmax = max(errmax,abs(yerr%structural_soil_C/yscal%structural_soil_C))
  !  print*,'struct C',errmax,yerr%structural_soil_C,yscal%structural_soil_C
  !  errmax = max(errmax,abs(yerr%structural_soil_L/yscal%structural_soil_L))
  !  print*,'struct L',errmax,yerr%structural_soil_L,yscal%structural_soil_L

  do ico = 1,cpatch%ncohorts
     if(cpatch%lai(ico).gt.lai_min)then
        errmax = max(errmax,abs(yerr%veg_water(ico)/yscal%veg_water(ico)))
        print*,'veg_water',errmax,yerr%veg_water(ico),yscal%veg_water(ico), &
             cpatch%lai(ico),cpatch%pft(ico)
        call print_errmax_flag(yerr%veg_water(ico),yscal%veg_water(ico))

        errmax = max(errmax,abs(yerr%veg_energy(ico)/yscal%veg_energy(ico)))
        print*,'veg_energy',errmax,yerr%veg_energy(ico),yscal%veg_energy(ico), &
             cpatch%lai(ico),cpatch%pft(ico)
        call print_errmax_flag(yerr%veg_energy(ico),yscal%veg_energy(ico))
     endif
  enddo

  return
end subroutine print_errmax_ar

subroutine print_errmax_flag(err,scal)
  use rk4_coms, only: rk4eps
  implicit none
  real, intent(in)::err,scal
  if(scal > 0.0) then
     if(abs(err/scal)/rk4eps > 1.0) then
        print*,"*******"
     endif
  endif
  return
end subroutine print_errmax_flag

!==================================================================

subroutine stabilize_snow_layers_ar(initp, csite,ipa, step, lsl)
  
  use ed_state_vars,only:sitetype,patchtype,rk4patchtype
  use soil_coms, only: soil, min_sfcwater_mass
  use grid_coms, only: nzg, nzs
  use therm_lib, only: qwtk8, qtk
  use consts_coms, only: wdns
  implicit none

  integer, intent(in) :: lsl
  type(sitetype),target :: csite
  type(rk4patchtype), target :: initp
  integer :: ipa
  integer :: k
  real :: soilhcap,step
  
  do k = lsl, nzg - 1
     soilhcap = soil(csite%ntext_soil(k,ipa))%slcpd
     call qwtk8(initp%soil_energy(k),initp%soil_water(k)*dble(wdns)   &
          ,soilhcap,initp%soil_tempk(k),initp%soil_fracliq(k))
  end do

  do k = 2, nzs
     if(initp%sfcwater_mass(k) > min_sfcwater_mass)  then
          call qtk(initp%sfcwater_energy(k)/initp%sfcwater_mass(k),  &
          initp%sfcwater_tempk(k),initp%sfcwater_fracliq(k))
      else
         initp%sfcwater_energy(k)  = 0.
      end if
  end do
  
  call redistribute_snow_ar(initp,csite,ipa,step)
  
  return
end subroutine stabilize_snow_layers_ar
!====================================================================

subroutine copy_rk4_patch_ar(sourcep, targetp, cpatch, lsl)

  use ed_state_vars,only:sitetype,patchtype,rk4patchtype
  use grid_coms, only: nzg, nzs
  use max_dims, only: n_pft
  use ed_misc_coms,only:fast_diagnostics

  implicit none

  integer, intent(in) :: lsl
  integer,pointer :: nco
  type(patchtype),target :: cpatch
  type(rk4patchtype), target :: sourcep
  type(rk4patchtype), target :: targetp
  integer :: k

  targetp%can_temp = sourcep%can_temp
  targetp%can_shv = sourcep%can_shv
  targetp%can_co2 = sourcep%can_co2

  do k=lsl,nzg
     
     targetp%soil_water(k) = sourcep%soil_water(k)
     targetp%soil_energy(k) = sourcep%soil_energy(k)
     targetp%soil_tempk(k) = sourcep%soil_tempk(k)
     targetp%soil_fracliq(k) = sourcep%soil_fracliq(k)
     targetp%available_liquid_water(k) = sourcep%available_liquid_water(k)
     targetp%extracted_water(k) = sourcep%extracted_water(k)

  enddo

  do k=1,nzs
     targetp%sfcwater_mass(k) = sourcep%sfcwater_mass(k)
     targetp%sfcwater_energy(k) = sourcep%sfcwater_energy(k)
     targetp%sfcwater_depth(k) = sourcep%sfcwater_depth(k)
     targetp%sfcwater_tempk(k) = sourcep%sfcwater_tempk(k)
     targetp%sfcwater_fracliq(k) = sourcep%sfcwater_fracliq(k)
  end do

  targetp%virtual_water = sourcep%virtual_water
  targetp%virtual_heat = sourcep%virtual_heat
  targetp%virtual_depth = sourcep%virtual_depth


  targetp%rough = sourcep%rough
 
  targetp%upwp = sourcep%upwp
  targetp%wpwp = sourcep%wpwp
  targetp%tpwp = sourcep%tpwp
  targetp%rpwp = sourcep%rpwp

  targetp%ground_shv = sourcep%ground_shv
  targetp%surface_ssh = sourcep%surface_ssh

  do k = 1, n_pft
     targetp%a_o_max(k) = sourcep%a_o_max(k)
     targetp%a_c_max(k) = sourcep%a_c_max(k)
  enddo

  targetp%nlev_sfcwater = sourcep%nlev_sfcwater
  targetp%ustar = sourcep%ustar
  targetp%cstar = sourcep%cstar
  targetp%tstar = sourcep%tstar
  targetp%rstar = sourcep%rstar
  targetp%virtual_flag = sourcep%virtual_flag
  targetp%rasveg = sourcep%rasveg
  targetp%root_res_fac = sourcep%root_res_fac
    
  nco => cpatch%ncohorts
  
  do k=1,nco

     targetp%veg_water(k) = sourcep%veg_water(k)
     targetp%veg_energy(k)  = sourcep%veg_energy(k)
  
  enddo

  if (fast_diagnostics) then
     
     targetp%wbudget_loss2atm = sourcep%wbudget_loss2atm
     targetp%co2budget_loss2atm = sourcep%co2budget_loss2atm
     targetp%ebudget_loss2atm = sourcep%ebudget_loss2atm
     targetp%ebudget_latent = sourcep%ebudget_latent
     targetp%avg_carbon_ac = sourcep%avg_carbon_ac
     targetp%avg_vapor_vc       = sourcep%avg_vapor_vc
     targetp%avg_dew_cg         = sourcep%avg_dew_cg  
     targetp%avg_vapor_gc       = sourcep%avg_vapor_gc
     targetp%avg_wshed_vg       = sourcep%avg_wshed_vg
     targetp%avg_vapor_ac       = sourcep%avg_vapor_ac
     targetp%avg_transp         = sourcep%avg_transp  
     targetp%avg_evap           = sourcep%avg_evap   
     targetp%avg_netrad         = sourcep%avg_netrad   
     targetp%avg_sensible_vc    = sourcep%avg_sensible_vc  
     targetp%avg_sensible_2cas  = sourcep%avg_sensible_2cas
     targetp%avg_qwshed_vg      = sourcep%avg_qwshed_vg    
     targetp%avg_sensible_gc    = sourcep%avg_sensible_gc  
     targetp%avg_sensible_ac    = sourcep%avg_sensible_ac  
     targetp%avg_sensible_tot   = sourcep%avg_sensible_tot 
     
     !  WHY IS THIS COMMENTED OUT? IS IT NOT INTEGRATED? REMEMBER
     !  TO DOUBLE CHECK AND THEN REMOVE THESE COMMENTS IF SO.
     !    targetp%avg_gpp = sourcep%avg_gpp
     
     do k=lsl,nzg
        ! Diagnostics
        targetp%avg_sensible_gg(k) = sourcep%avg_sensible_gg(k)
        targetp%avg_smoist_gg(k)   = sourcep%avg_smoist_gg(k)  
        targetp%avg_smoist_gc(k)   = sourcep%avg_smoist_gc(k)  
        targetp%aux_s(k) = sourcep%aux_s(k)
     enddo
  endif



  return
end subroutine copy_rk4_patch_ar

!===================================================================

subroutine print_patch_pss_ar(csite, ipa, lsl)

  use ed_state_vars,only:sitetype,patchtype
  use misc_coms, only: current_time
  use grid_coms, only: nzg
  use canopy_radiation_coms, only: lai_min

  implicit none

  type(sitetype),target :: csite
  type(patchtype),pointer :: cpatch
  integer :: ipa,ico
  integer, intent(in) :: lsl
  integer :: k

  print*,'Time'
  print*,current_time%time, current_time%date, current_time%month, &
       current_time%year
  print*,''

  print*,'soil class'
  do k=lsl,nzg
     print*,k, csite%ntext_soil(k,ipa)
  enddo

  print*,'attempted step size'
  print*,csite%htry(ipa)

  print*,'cohorts'
  print*,'pft,krdepth,dbh'
  print*,'bdead,balive,nplant,veg_temp'
  print*,'veg_water'
  print*,'fs_open,fsw,fsn,lai'

  cpatch => csite%patch(ipa)

  do ico = 1,cpatch%ncohorts
     if(cpatch%lai(ico).gt.lai_min)then
        print*,4,cpatch%pft(ico),cpatch%krdepth(ico),cpatch%dbh(ico)
        print*,5,cpatch%bdead(ico),cpatch%balive(ico),cpatch%nplant(ico),cpatch%veg_temp(ico)
        print*,6,cpatch%veg_water(ico)
        print*,7,cpatch%fs_open(ico),cpatch%fsw(ico),cpatch%fsn(ico),cpatch%lai(ico)
     endif
  enddo

  print*,'Patch PSS'
  print*,'area  age  dist_type  cohort_count'
  print*,1,csite%area(ipa),csite%age(ipa),csite%dist_type(ipa),csite%cohort_count(ipa)
  print*,'rh  avg_daily_temp  sum_chd  sum_dgd'
  print*,2,csite%rh(ipa),csite%avg_daily_temp(ipa),csite%sum_chd(ipa),csite%sum_dgd(ipa)
  print*,'veg_height  veg_rough  lai '
  print*,4,csite%veg_height(ipa),csite%veg_rough(ipa),csite%lai(ipa)
  print*,'repro1  repro2  repro3  repro4' 
  print*,5,csite%repro(1:4,ipa)
  print*,'repro5  repro6  repro7  repro8' 
  print*,6,csite%repro(5:8,ipa)
  print*,'cstar  can_co2  can_temp  can_shv'
  print*,8,csite%cstar(ipa),csite%can_co2(ipa),csite%can_temp(ipa),csite%can_shv(ipa)
  print*,'soil class'
  print*,9,csite%ntext_soil(:,ipa)
  print*,'soil heat'
  print*,10,csite%soil_energy(:,ipa)
  print*,'soil tempk'
  print*,101,csite%soil_tempk(:,ipa)
  print*,'soil fracliq'
  print*,102,csite%soil_fracliq(:,ipa)
  print*,'soil water'
  print*,11,csite%soil_water(:,ipa)
  print*,'sfcwater_energy  rlong_g  rshort_g  rlong_s'
  print*,13,csite%sfcwater_energy(:,ipa),csite%rlong_g(ipa),csite%rshort_g(ipa),csite%rlong_s(ipa)
  print*,'rshort_s  htry'
  print*,14,csite%rshort_s(:,ipa),csite%htry(ipa)

  return
end subroutine print_patch_pss_ar


!=======================================================
subroutine print_patch_ar(y, csite,ipa, lsl)

  use grid_coms, only: nzg, nzs
  use canopy_radiation_coms, only: lai_min
  use misc_coms, only: current_time
  use ed_state_vars,only:sitetype,patchtype,rk4patchtype

  implicit none

  integer, intent(in) :: lsl
  type(sitetype),target :: csite
  type(patchtype),pointer :: cpatch
  type(rk4patchtype), target :: y
  integer :: k,ipa,ico

  cpatch => csite%patch(ipa)

  print*
  print*,'IN SUBROUTINE PRINT_PATCH'
  print*

  print*,'Time'
  print*,current_time%time,current_time%date,current_time%month,current_time%year

  print*,''
  print*,'canopy state'
  print*,'canopy tempk',y%can_temp
  print*,'canopy water vapor',y%can_shv
  print*,'canopy co2',y%can_co2

  
  print*,"LSL",lsl,"NZG",nzg
  

  print*,''
  print*,'soil state'
  print*,'level  soil_energy  soil_water  soil_tempk  soil_fracliq  ntext_soil'
  do k=lsl,nzg
     print*,k,y%soil_energy(k),y%soil_water(k),y%soil_tempk(k),y%soil_fracliq(k)  &
          ,csite%ntext_soil(k,ipa)
  enddo

  print*,''
  print*,'sfcwater state'
  print*,'level  sfcwater_mass  sfcwater_energy[J/m2]'
  do k=1,nzs
     print*,k,y%sfcwater_mass(k),y%sfcwater_energy(k)
  enddo

  print*,'virtual pools'
  print*,y%virtual_water,y%virtual_heat

  print*,'ground shv, surface ssh'
  print*,y%ground_shv, y%surface_ssh

  if(y%nlev_sfcwater > 0)print*,'k, tempk, fracliq'
  do k=1,y%nlev_sfcwater
     print*,k,y%sfcwater_tempk(k),y%sfcwater_fracliq(k)
  enddo

  print*,'nlev_sfcwater'
  print*,y%nlev_sfcwater

  print*,'virtual flag'
  print*,y%virtual_flag

  print*,'attempted step size'
  print*,csite%htry(ipa)

  print*,'cohorts'
  print*,1,"y%veg_water,y%veg_energy"
  print*,2,"ccp%lai"
  print*,3,"ccp%hite"
  print*,4,"pft,krdepth,dbh"
  print*,5,"bdead,balive,nplant,veg_temp"
  print*,6,"veg_water,par_v,rshort_v,rlong_v"
  print*,7,"fs_open,fsw,fsn"

  do ico=1,cpatch%ncohorts
     if(cpatch%lai(ico).gt.lai_min)then
        print*,1,y%veg_water(ico),y%veg_energy(ico)
        print*,2,cpatch%lai(ico)!,y%a_op(ico),y%a_cl(ico)
        !print*,3,y%p_op(ico),y%p_cl(ico),y%rb(ico),
        print*,3,cpatch%hite(ico)
        print*,4,cpatch%pft(ico),cpatch%krdepth(ico),cpatch%dbh(ico)
        print*,5,cpatch%bdead(ico),cpatch%balive(ico),cpatch%nplant(ico),cpatch%veg_temp(ico)
        print*,6,cpatch%veg_water(ico),cpatch%par_v(ico),cpatch%rshort_v(ico),cpatch%rlong_v(ico)
        print*,7,cpatch%fs_open(ico),cpatch%fsw(ico),cpatch%fsn(ico)
        write(*,*)
     endif
  enddo

  print*,'Patch PSS'
  print*,'area  age  dist_type  cohort_count'
  print*,1,csite%area(ipa),csite%age(ipa),csite%dist_type(ipa),csite%cohort_count(ipa)
  print*,'rh  avg_daily_temp  sum_chd  sum_dgd'
  print*,2,csite%rh(ipa),csite%avg_daily_temp(ipa),csite%sum_chd(ipa),csite%sum_dgd(ipa)
  print*,'veg_height  veg_rough  lai  '
  print*,4,csite%veg_height(ipa),csite%veg_rough(ipa),csite%lai(ipa)
  print*,'repro1  repro2  repro3  repro4' 
  print*,5,csite%repro(1:4,ipa)
  print*,'repro5  repro6  repro7  repro8' 
  print*,6,csite%repro(5:8,ipa)
  print*,' rstar  ustar  tstar'
  print*,7,csite%rstar(ipa),csite%ustar(ipa),csite%tstar(ipa)
  print*,'cstar  can_co2  can_temp  can_shv'
  print*,8,csite%cstar(ipa),csite%can_co2(ipa),csite%can_temp(ipa),csite%can_shv(ipa)

  print*,' irstar iustar itstar icstar'
  print*,81,y%rstar,y%ustar,y%tstar,y%cstar


  print*,'soil class'
  print*,9,csite%ntext_soil(:,ipa)
  print*,'soil heat'
  print*,10,csite%soil_energy(:,ipa)
  print*,'soil tempk'
  print*,101,csite%soil_tempk(:,ipa)
  print*,'soil fracliq'
  print*,102,csite%soil_fracliq(:,ipa)
  print*,'soil water'
  print*,11,csite%soil_water(:,ipa)
  print*,'nlev_sfcwater  sfcwater_mass'
  print*,12,csite%nlev_sfcwater(ipa),csite%sfcwater_mass(:,ipa)
  print*,'sfcwater_energy[J/kg]  rlong_g  rshort_g  rlong_s'
  print*,13,csite%sfcwater_energy(:,ipa),csite%rlong_g(ipa),csite%rshort_g(ipa),csite%rlong_s(ipa)
  print*,'rshort_s  htry'
  print*,14,csite%rshort_s(:,ipa),csite%htry(ipa)

  return
end subroutine print_patch_ar

!===============================================================

subroutine redistribute_snow_ar(initp,csite,ipa,step)

  use ed_state_vars,only:sitetype,patchtype,rk4patchtype
  use grid_coms, only: nzs, nzg
  use soil_coms, only: soil, water_stab_thresh, dslz, dslzi, &
       min_sfcwater_mass
  use consts_coms, only: cice, cliq, alli,t3ple,wdns,tsupercool,cicet3, wdnsi
  use therm_lib, only : qtk,qwtk,qwtk8

  implicit none
  integer :: ipa
  real :: step
  real :: stretch
  integer :: kzs
  real :: thik
  real, save, dimension(20) :: thicknet
  integer :: k
  real, save, dimension(20,20) :: thick
  integer :: kold
  integer :: newlayers
  real :: wtold
  real :: wtnew
  real :: snowmin
  real, dimension(nzs) :: vctr14
  real, dimension(nzs) :: vctr16
  real, dimension(nzs) :: vctr18
  real :: wdiff
  real :: totsnow
  real :: depthgain
  real :: wfree
  real :: qwfree
  type(rk4patchtype), target :: initp
  real :: qw
  real :: w
  real :: wfreeb
  real :: depthloss
  real :: snden
  real :: sndenmin
  real :: sndenmax
  integer :: nlayers
  integer :: ksn
  integer :: ksnnew
  real :: qwt
  real(kind=8) :: wt
  real :: soilhcap
  type(sitetype),target :: csite
  real :: free_surface_water_demand
  integer :: nsoil
  logical, parameter :: debug = .false.
  logical, save :: first_call = .true.

  !! run once at start
  if (first_call) then
     first_call = .false.

     stretch = 2.0
     do kzs = 1,nzs
        thik = 1.0
        thicknet(kzs) = 0.0
        do k = 1,(kzs+1)/2
           thick(k,kzs) = thik
           thick(kzs+1-k,kzs) = thik
           thicknet(kzs) = thicknet(kzs) + 2. * thik
           thik = thik * stretch
        enddo
        if ((kzs+1)/2 .ne. kzs/2)  &
             thicknet(kzs) = thicknet(kzs) - thik/stretch
        do k = 1,kzs
           thick(k,kzs) = thick(k,kzs) / thicknet(kzs)
        enddo
     enddo
  endif

  ! Bookkeeping variable
  totsnow = 0.0
  ksn = initp%nlev_sfcwater
  
  ! Input to top layer
  if(initp%nlev_sfcwater >= 1)then
     if(sum(initp%sfcwater_mass) < min_sfcwater_mass)then
        initp%nlev_sfcwater = 0
        ksnnew = 0
     else
        wfree = 0.0
        qwfree = 0.0
        depthgain = 0.0
        ksnnew = ksn
     endif
  else
     if((initp%virtual_water) < min_sfcwater_mass)then
        ksnnew = 0
     else
        wfree = initp%virtual_water
        qwfree = initp%virtual_heat
        depthgain = initp%virtual_depth
        initp%virtual_water = 0.0
        initp%virtual_heat = 0.0
        ksnnew = 1
     endif
  endif
  ! Loop over layers
  do k = ksnnew,1,-1

     ! Update current state
     qw = initp%sfcwater_energy(k) + qwfree
     w = initp%sfcwater_mass(k) + wfree
     if( ksnnew == 1 .and. initp%sfcwater_mass(k) < water_stab_thresh )then
        qwt = qw + initp%soil_energy(nzg) * dslz(nzg)
        wt = dble(w) + initp%soil_water(nzg) * dble(dslz(nzg)) * dble(wdns)

        soilhcap = soil(csite%ntext_soil(nzg,ipa))%slcpd * dslz(nzg)
        call qwtk8(qwt,wt,soilhcap  &
             ,initp%sfcwater_tempk(k),initp%sfcwater_fracliq(k))
        ! portion out the heat to the snow
        qw = w * (     initp%sfcwater_fracliq(k)  * cliq *(initp%sfcwater_tempk(k) - tsupercool) &
                 + (1.-initp%sfcwater_fracliq(k)) * cice * initp%sfcwater_tempk(k)              )
        ! set the properties of top soil layer.
        initp%soil_tempk(nzg) = initp%sfcwater_tempk(k)
        initp%soil_fracliq(nzg) = initp%sfcwater_fracliq(k)
        initp%soil_energy(nzg) = (qwt - qw) * dslzi(nzg)
     else
        call qwtk8(initp%soil_energy(nzg)  &
             ,initp%soil_water(nzg)*dble(wdns) &
             ,soil(csite%ntext_soil(nzg,ipa))%slcpd,  &
             initp%soil_tempk(nzg),initp%soil_fracliq(nzg))
        call qtk(qw/w,initp%sfcwater_tempk(k),  &
             initp%sfcwater_fracliq(k))
     endif
     ! This percolates downwards
     if(initp%sfcwater_fracliq(k) == 1.0)then
        wfreeb = w
     else
        wfreeb = max(0.0,w*(initp%sfcwater_fracliq(k)-0.1)/0.9)
     endif
    if(k == 1)then
       !! infiltration
       !! if(infiltration_method .eq. 0 .or. step .eq. 0.0) then
       if(.true.) then
          !! do "greedy" infiltration
          nsoil = csite%ntext_soil(nzg,ipa)

          free_surface_water_demand = real(dmax1(dble(0.0), &
               & dble(soil(nsoil)%slmsts) - initp%soil_water(nzg)) * dble(wdns) * dble(dslz(nzg)))

          wfreeb = min(wfreeb,free_surface_water_demand)

          qwfree = wfreeb * cliq * (initp%sfcwater_tempk(k)-tsupercool)
          initp%soil_water(nzg) = initp%soil_water(nzg)   &
               + dble(wfreeb * 0.001 * dslzi(nzg)) 
          initp%soil_energy(nzg) = initp%soil_energy(nzg) + qwfree   &
               * dslzi(nzg)
         call qwtk8(initp%soil_energy(nzg)  &
               ,initp%soil_water(nzg)*dble(wdns)  &
               ,soil(csite%ntext_soil(nzg,ipa))%slcpd,  &
               initp%soil_tempk(nzg),initp%soil_fracliq(nzg))
       else
          !! do infiltration in integrator, let temporary water accumulate at the surface
          wfreeb = 0.0
          qwfree = 0.0
       endif

     else
        qwfree = wfreeb * cliq * (initp%sfcwater_tempk(k)-tsupercool)
     endif
     depthloss = wfreeb * wdnsi
     
     ! Remove percolation
     initp%sfcwater_mass(k) = w - wfreeb
     initp%sfcwater_depth(k) = initp%sfcwater_depth(k) +   &
          depthgain - depthloss
     if(initp%sfcwater_mass(k) >= min_sfcwater_mass)then
        initp%sfcwater_energy(k) = qw - qwfree
        call qtk(initp%sfcwater_energy(k)/initp%sfcwater_mass(k),initp%sfcwater_tempk(k)  &
                ,initp%sfcwater_fracliq(k))
     else
        initp%sfcwater_energy(k) = 0.0
        
     endif
     totsnow = totsnow + initp%sfcwater_mass(k)
     ! Calculate density, depth of snow
     snden = initp%sfcwater_mass(k) / max(1.0e-6,initp%sfcwater_depth(k))
     sndenmax = wdns
     sndenmin = max(30.0, 200.0 * (wfree + wfreeb) / &
          max(1.0e-12,initp%sfcwater_mass(k)))
     snden = min(sndenmax, max(sndenmin,snden))
     initp%sfcwater_depth(k) = initp%sfcwater_mass(k) / snden

     ! Set up input to next layer
     wfree = wfreeb
     depthgain = depthloss
  enddo

  ! Re-distribute snow layers to maintain prescribed distribution of mass
  if(totsnow < min_sfcwater_mass .or. ksnnew == 0)then
     initp%nlev_sfcwater = 0
     call qwtk8(initp%soil_energy(nzg),  &
          initp%soil_water(nzg) * dble(wdns), &
          soil(csite%ntext_soil(nzg,ipa))%slcpd,  &
          initp%soil_tempk(nzg),initp%soil_fracliq(nzg))
  else
     nlayers = ksnnew
     snowmin = 3.0
     newlayers = 1
     do k = 1,nzs
        if(initp%sfcwater_mass(k) >= min_sfcwater_mass)then
           if(snowmin * thicknet(k) <= totsnow .and.  &
                initp%sfcwater_energy(k) < initp%sfcwater_mass(k)*(cicet3+alli))then
              newlayers = newlayers + 1
           endif
        endif
     enddo
     newlayers = min(newlayers, nzs, nlayers + 1)
if(debug) print*,"A",newlayers     
     initp%nlev_sfcwater = newlayers
     kold = 1
     wtnew = 1.0
     wtold = 1.0
     do k = 1,newlayers
if(debug) print*,"k=",k
        vctr14(k) = totsnow * thick(k,newlayers) !!mass?
        vctr16(k) = 0.0                          !!energy?
        vctr18(k) = 0.0                          !!depth?
        find_layer: do
           wdiff = wtnew * vctr14(k) - wtold * initp%sfcwater_mass(kold)  
           !!difference between old and new snow
if(debug) print*,"wdiff=",wdiff,wtnew,wtold,kold
if(debug) print*,"old=",initp%sfcwater_energy(kold), initp%sfcwater_depth(kold),initp%sfcwater_mass(kold)
if(debug) print*,"new=",vctr14(k),vctr16(k),vctr18(k)
           if (wdiff > 0.0) then
              vctr16(k) = vctr16(k) + wtold * initp%sfcwater_energy(kold)
              vctr18(k) = vctr18(k) + wtold * initp%sfcwater_depth(kold)
              wtnew = wtnew - wtold * initp%sfcwater_mass(kold) &
                   / vctr14(k)
              kold = kold + 1
              wtold = 1.0
              if (kold > nlayers) exit find_layer
           else
              vctr16(k) = vctr16(k) + wtnew * initp%sfcwater_energy(kold)
if(debug) print*,"."
              vctr18(k) = vctr18(k) + wtnew * vctr14(k)  &
                   * initp%sfcwater_depth(kold) / max(1.0e-12,  &
                   initp%sfcwater_mass(kold))
if(debug) print*,"."
              wtold = wtold - wtnew * vctr14(k) /   &
                  max(min_sfcwater_mass,initp%sfcwater_mass(kold))
!!                   initp%sfcwater_mass(kold)
              wtnew = 1.
              exit find_layer
           endif
        enddo find_layer
     enddo

if(debug) print*,"B"

     do k = 1,newlayers
        initp%sfcwater_mass(k) = vctr14(k)
        initp%sfcwater_energy(k) = vctr16(k)
        if(vctr14(k) >= min_sfcwater_mass)then
        call qtk(initp%sfcwater_energy(k)/initp%sfcwater_mass(k),initp%sfcwater_tempk(k)  &
                ,initp%sfcwater_fracliq(k))
        else
           initp%sfcwater_tempk(k) = t3ple
           initp%sfcwater_fracliq(k) = 0.
        end if
        initp%sfcwater_depth(k) = vctr18(k)
     enddo

     do k = newlayers + 1, nzs
        initp%sfcwater_mass(k) = 0.0
        initp%sfcwater_energy(k) = 0.0
        initp%sfcwater_depth(k) = 0.0
     enddo

  endif

  return
end subroutine redistribute_snow_ar

! =================================================

subroutine initialize_rk4patches_ar(init)

  use ed_state_vars,only:edgrid_g,edtype,polygontype, &
       sitetype,integration_buff_g
  use grid_coms, only: ngrids
  
  implicit none
  
  integer, intent(in) :: init
  
  type(edtype),pointer :: cgrid
  type(polygontype),pointer :: cpoly
  type(sitetype),pointer :: csite

  integer :: maxcohort
  integer :: igr,ipy,isi,ipa

  if(init == 0)then
     ! If this is not initialization, deallocate cohort memory from
     ! integration patches.

     call deallocate_rk4_coh_ar(integration_buff_g%initp)
     call deallocate_rk4_coh_ar(integration_buff_g%yscal)
     call deallocate_rk4_coh_ar(integration_buff_g%y)
     call deallocate_rk4_coh_ar(integration_buff_g%dydx)
     call deallocate_rk4_coh_ar(integration_buff_g%yerr)
     call deallocate_rk4_coh_ar(integration_buff_g%ytemp)
     call deallocate_rk4_coh_ar(integration_buff_g%ak2)
     call deallocate_rk4_coh_ar(integration_buff_g%ak3)
     call deallocate_rk4_coh_ar(integration_buff_g%ak4)
     call deallocate_rk4_coh_ar(integration_buff_g%ak5)
     call deallocate_rk4_coh_ar(integration_buff_g%ak6)
     call deallocate_rk4_coh_ar(integration_buff_g%ak7)
  else
     ! If this is initialization, make sure soil and sfcwater arrays
     ! are allocated.
     call allocate_rk4_patch(integration_buff_g%initp)
     call allocate_rk4_patch(integration_buff_g%yscal)
     call allocate_rk4_patch(integration_buff_g%y)
     call allocate_rk4_patch(integration_buff_g%dydx)
     call allocate_rk4_patch(integration_buff_g%yerr)
     call allocate_rk4_patch(integration_buff_g%ytemp)
     call allocate_rk4_patch(integration_buff_g%ak2)
     call allocate_rk4_patch(integration_buff_g%ak3)
     call allocate_rk4_patch(integration_buff_g%ak4)
     call allocate_rk4_patch(integration_buff_g%ak5)
     call allocate_rk4_patch(integration_buff_g%ak6)
     call allocate_rk4_patch(integration_buff_g%ak7)
  endif

  ! Find maximum number of cohorts in any patch.

  maxcohort = 1
  do igr = 1,ngrids
     cgrid => edgrid_g(igr)
     do ipy = 1,cgrid%npolygons
        cpoly => cgrid%polygon(ipy)
        do isi = 1,cpoly%nsites
           csite => cpoly%site(isi)
           do ipa = 1,csite%npatches
              if (csite%paco_n(ipa)>maxcohort) then
                 maxcohort = csite%paco_n(ipa)
              endif
           enddo
        enddo
     enddo
  enddo
print*,"maxcohort = ",maxcohort
  ! Create new memory in each of the integration patches.
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%initp)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%yscal)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%y)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%dydx)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%yerr)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%ytemp)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%ak2)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%ak3)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%ak4)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%ak5)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%ak6)
  call allocate_rk4_coh_ar(maxcohort,integration_buff_g%ak7)
  
  return
end subroutine initialize_rk4patches_ar
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine allocate_rk4_patch(y)

  use ed_state_vars,only:rk4patchtype
  use grid_coms, only: nzg, nzs

  implicit none
  
  type(rk4patchtype) :: y

  call nullify_rk4_patch(y)

  allocate(y%soil_energy(nzg))
  allocate(y%soil_water(nzg))
  allocate(y%soil_fracliq(nzg))
  allocate(y%soil_tempk(nzg))
  allocate(y%available_liquid_water(nzg))
  allocate(y%extracted_water(nzg))

  allocate(y%sfcwater_energy(nzs))
  allocate(y%sfcwater_mass(nzs))
  allocate(y%sfcwater_depth(nzs))
  allocate(y%sfcwater_fracliq(nzs))
  allocate(y%sfcwater_tempk(nzs))

  ! Diagnostics - for now we will always allocate the diagnostics, even if they arent used
  allocate(y%avg_smoist_gg(nzg))
  allocate(y%avg_smoist_gc(nzg))
  allocate(y%aux_s(nzg))
  allocate(y%avg_sensible_gg(nzg))

  call zero_rk4_patch(y)

  return
end subroutine allocate_rk4_patch
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine nullify_rk4_patch(y)

  use ed_state_vars,only:rk4patchtype
  use grid_coms, only: nzg, nzs

  implicit none
  
  type(rk4patchtype) :: y

  nullify(y%soil_energy)
  nullify(y%soil_water)
  nullify(y%soil_fracliq)
  nullify(y%soil_tempk)
  nullify(y%available_liquid_water)
  nullify(y%extracted_water)

  nullify(y%sfcwater_energy)
  nullify(y%sfcwater_mass)
  nullify(y%sfcwater_depth)
  nullify(y%sfcwater_fracliq)
  nullify(y%sfcwater_tempk)
  
  ! Diagnostics- for now we will always allocate the diagnostics, even if they arent used
  nullify(y%avg_smoist_gg)
  nullify(y%avg_smoist_gc)
  nullify(y%aux_s)
  nullify(y%avg_sensible_gg)

  return
end subroutine nullify_rk4_patch
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine zero_rk4_patch(y)

  use ed_state_vars,only:rk4patchtype
  use grid_coms, only: nzg, nzs

  implicit none
  
  type(rk4patchtype) :: y


  y%wbudget_loss2atm               = 0.
  y%ebudget_loss2atm               = 0.
  y%ebudget_latent                 = 0.
  y%co2budget_loss2atm             = 0.

  y%can_temp                       = 0.
  y%can_shv                        = 0.
  y%can_co2                        = 0.

  y%soil_energy(:)                 = 0.
  y%soil_tempk(:)                  = 0.
  y%soil_fracliq(:)                = 0.
  y%soil_water(:)                  = 0.d0

  y%sfcwater_depth(:)              = 0.
  y%sfcwater_mass(:)               = 0.
  y%sfcwater_energy(:)             = 0.

  y%virtual_water                  = 0.
  y%virtual_heat                   = 0.
  y%virtual_depth                  = 0.

  y%ground_shv                     = 0.
  y%surface_ssh                    = 0.
  y%sfcwater_tempk(:)              = 0.
  y%sfcwater_fracliq(:)            = 0.
  y%nlev_sfcwater                  = 0
  y%net_rough_length               = 0.

  y%rough                          = 0.

  y%ustar                          = 0.
  y%cstar                          = 0.
  y%tstar                          = 0.
  y%rstar                          = 0.
  y%virtual_flag                   = 0
  y%avg_carbon_ac                  = 0.

  y%upwp                           = 0.
  y%wpwp                           = 0.
  y%tpwp                           = 0.
  y%rpwp                           = 0.

  y%avg_gpp                        = 0.

  y%a_o_max                        = 0.
  y%a_c_max                        = 0.
  y%rasveg                         = 0.
  y%root_res_fac                   = 0.
  y%available_liquid_water(:)      = 0.
  y%extracted_water(:)             = 0.


  y%avg_vapor_vc                   = 0.
  y%avg_dew_cg                     = 0.
  y%avg_vapor_gc                   = 0.
  y%avg_wshed_vg                   = 0.
  y%avg_vapor_ac                   = 0.
  y%avg_transp                     = 0.
  y%avg_evap                       = 0.
  y%avg_netrad                     = 0.
  y%avg_smoist_gg                  = 0.
  y%avg_smoist_gc                  = 0.
  y%aux                            = 0.
  y%aux_s                          = 0.
  y%avg_sensible_vc                = 0.
  y%avg_sensible_2cas              = 0.
  y%avg_qwshed_vg                  = 0.
  y%avg_sensible_gc                = 0.
  y%avg_sensible_ac                = 0.
  y%avg_sensible_tot               = 0.
  y%avg_sensible_gg                = 0.
  y%avg_heatstor_veg               = 0.

  return
end subroutine zero_rk4_patch
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine deallocate_rk4_patch(y)

  use ed_state_vars,only:rk4patchtype
  use grid_coms, only: nzg, nzs

  implicit none
  
  type(rk4patchtype) :: y

  if (associated(y%soil_energy))             deallocate(y%soil_energy)
  if (associated(y%soil_water))              deallocate(y%soil_water)
  if (associated(y%soil_fracliq))            deallocate(y%soil_fracliq)
  if (associated(y%soil_tempk))              deallocate(y%soil_tempk)
  if (associated(y%available_liquid_water))  deallocate(y%available_liquid_water)
  if (associated(y%extracted_water))         deallocate(y%extracted_water)

  if (associated(y%sfcwater_energy))         deallocate(y%sfcwater_energy)
  if (associated(y%sfcwater_mass))           deallocate(y%sfcwater_mass)
  if (associated(y%sfcwater_depth))          deallocate(y%sfcwater_depth)
  if (associated(y%sfcwater_fracliq))        deallocate(y%sfcwater_fracliq)
  if (associated(y%sfcwater_tempk))          deallocate(y%sfcwater_tempk)
  
  ! Diagnostics
  if (associated(y%avg_smoist_gg))           deallocate(y%avg_smoist_gg)
  if (associated(y%avg_smoist_gc))           deallocate(y%avg_smoist_gc)
  if (associated(y%aux_s))                   deallocate(y%aux_s)
  if (associated(y%avg_sensible_gg))         deallocate(y%avg_sensible_gg)

  return
end subroutine deallocate_rk4_patch
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine allocate_rk4_coh_ar(maxcohort,y)
  
  use ed_state_vars,only:rk4patchtype

  implicit none
  
  type(rk4patchtype) :: y
  integer,intent(in) :: maxcohort

  call nullify_rk4_cohort(y)

  allocate(y%veg_energy(maxcohort))
  allocate(y%veg_water(maxcohort))

  call zero_rk4_cohort(y)

  return
end subroutine allocate_rk4_coh_ar
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine nullify_rk4_cohort(y)
  
  use ed_state_vars,only:rk4patchtype
  
  implicit none
  
  type(rk4patchtype) :: y
      
  nullify(y%veg_energy)
  nullify(y%veg_water)

  return
end subroutine nullify_rk4_cohort
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine zero_rk4_cohort(y)
  
  use ed_state_vars,only:rk4patchtype

  implicit none
  
  type(rk4patchtype) :: y

  if(associated(y%veg_energy    ))  y%veg_energy    = 0.
  if(associated(y%veg_water     ))  y%veg_water     = 0.

  return
end subroutine zero_rk4_cohort
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine deallocate_rk4_coh_ar(y)
  
  use ed_state_vars,only:rk4patchtype
  
  implicit none
  
  type(rk4patchtype) :: y
      
  if(associated(y%veg_energy))     deallocate(y%veg_energy)
  if(associated(y%veg_water))      deallocate(y%veg_water)
  
  return
end subroutine deallocate_rk4_coh_ar
!==========================================================================================!
!==========================================================================================!
