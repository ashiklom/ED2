subroutine phenology_driver_ar(cgrid, doy, month, tfact)

  use ed_state_vars,only:edtype,polygontype,sitetype
  use phenology_coms, only: iphen_scheme
  use misc_coms, only: current_time

  implicit none

  type(edtype),target       :: cgrid
  type(polygontype),pointer :: cpoly
  type(sitetype),pointer    :: csite
  integer :: ipy,isi,ipa
  integer, intent(in) :: doy
  integer, intent(in) :: month
  real, intent(in) :: tfact

  do ipy = 1,cgrid%npolygons

     cpoly => cgrid%polygon(ipy)

     do isi = 1,cpoly%nsites

        csite => cpoly%site(isi)

        ! Get the patch-level average daily temperature, which is needed for 
        ! mortality, recruitment and some phenology schemes
        
        do ipa = 1,csite%npatches
           csite%avg_daily_temp(ipa) = csite%avg_daily_temp(ipa) * tfact
        enddo
        
        if(iphen_scheme == 0)then
     
           !  Default predictive scheme (Botta et al.)
           
           call update_thermal_sums_ar(month, cpoly, isi, cgrid%lat(ipy))

           call update_phenology_ar(doy,cpoly,isi,cgrid%lat(ipy))
           
        elseif(iphen_scheme == 1)then
           
           call prescribed_leaf_state(cgrid%lat(ipy), current_time%month,  &
                current_time%year, doy, cpoly%green_leaf_factor(:,isi),   &
                cpoly%leaf_aging_factor(:,isi), cpoly%phen_pars(isi)) 

           call update_phenology_ar(doy,cpoly,isi,cgrid%lat(ipy))


        elseif(iphen_scheme == 2)then
           
           !-KIM light-controlled predictive phenology scheme 
           
           call update_turnover(cpoly,isi)
           call update_phenology_tropics(cpoly,isi)
           
        endif

     enddo
  enddo

  return
end subroutine phenology_driver_ar

!==================================================================

subroutine update_phenology_ar(day, cpoly, isi, lat)

  use ed_state_vars,only:polygontype,sitetype,patchtype
  use grid_coms, only: nzg
  use pft_coms, only: phenology, sla, c2n_leaf, q, qsw, l2n_stem, c2n_stem, &
       c2n_storage
  use decomp_coms, only: f_labile
  use phenology_coms, only: retained_carbon_fraction, theta_crit, iphen_scheme
  use consts_coms, only: t3ple,cice,cliq,alli
  use ed_therm_lib,only:calc_hcapveg,update_veg_energy_cweh
  use max_dims, only : n_pft
  use misc_coms, only : current_time
  use allometry, only : area_indices

  implicit none
  
  real :: delta_bleaf
  real, intent(in) :: lat
  integer, intent(in) :: day
  type(polygontype),target :: cpoly
  type(sitetype),pointer   :: csite
  type(patchtype),pointer  :: cpatch
  integer :: isi,ipa,ico
  integer :: isoil_lev
  real :: daylight
  real, external :: daylength

  integer :: drop_cold
  integer :: leaf_out_cold
  real, dimension(nzg) :: theta
  real :: leaf_litter
  real :: bl_max
  real :: old_hcapveg
  logical, dimension(n_pft), save :: first_time=.true.
  integer :: ipft

  ! Level to evaluate the soil temperature

  isoil_lev = nzg 

  ! Calculate daylength for this gridcell

  daylight = daylength(lat, day)  ! day (= the Julian day) is input

  ! Loop over patches

  csite => cpoly%site(isi)

  patchloop: do ipa = 1,csite%npatches

     cpatch => csite%patch(ipa)

     ! Re-initialize litter inputs
     csite%fsc_in(ipa) = 0.0
     csite%fsn_in(ipa) = 0.0
     csite%ssc_in(ipa) = 0.0
     csite%ssl_in(ipa) = 0.0

     ! Determine what phenology thresholds have been crossed
     call phenology_thresholds(daylight, csite%soil_tempk(isoil_lev,ipa),   &
          csite%soil_water(:,ipa), csite%ntext_soil(:,ipa), csite%sum_chd(ipa), &
          csite%sum_dgd(ipa), drop_cold,leaf_out_cold, theta, cpoly%lsl(isi))


     cohortloop: do ico = 1,cpatch%ncohorts
        ipft = cpatch%pft(ico)
        

        ! Find cohort-specific thresholds.
        if(iphen_scheme == 0)then
           ! drop_cold is computed in phenology_thresholds for Botta scheme.
           if(drop_cold == 1)bl_max = 0.0
        elseif(iphen_scheme == 1)then
           ! Get cohort-specific thresholds for prescribed phenology.
           call cohort_phen_thresholds(cpoly%green_leaf_factor(ipft,isi),  &
                cpoly%leaf_aging_factor(ipft,isi), cpatch%dbh(ico), ipft,   &
                drop_cold, leaf_out_cold, bl_max)
        endif

        ! Is this a cold deciduous with leaves?
        if(cpatch%phenology_status(ico) < 2 .and. phenology(ipft) == 2 .and.   &
             drop_cold == 1)then
           !             day >= 210)then
           !print*,'dropping ',cs%green_leaf_factor(ipft),cs%leaf_aging_factor(ipft)           
           ! If dropping, compute litter inputs.
           delta_bleaf = cpatch%bleaf(ico) - bl_max
           if(delta_bleaf > 0.0)then
              
              !THIS IS INCORRECT - PHEN_STATUS 0 INDICATES LEAVES ARE FULLY FLUSHED
              !BUT IN THIS CASE, LEAVES WERE JUST DROPPED, SHOULD BE 1 OR 2
              !UNLESS IT IS EXCESS LEAF TRIMMING - AND THE RESULTING LEAF BIOMASS IS 
              !JUST THE CARRYING CAPACITY OF THE TREE
              cpatch%phenology_status(ico) = 0
              leaf_litter = (1.0 - retained_carbon_fraction)  &
                   * delta_bleaf * cpatch%nplant(ico)
              csite%fsc_in(ipa) = csite%fsc_in(ipa) + leaf_litter * f_labile(ipft)
              csite%fsn_in(ipa) = csite%fsn_in(ipa) + leaf_litter * f_labile(ipft) /   &
                   c2n_leaf(ipft)
              csite%ssc_in(ipa) = csite%ssc_in(ipa) + leaf_litter * (1.0 - f_labile(ipft))
              csite%ssl_in(ipa) = csite%ssl_in(ipa) + leaf_litter *   &
                   (1.0 - f_labile(ipft)) * l2n_stem / c2n_stem
              
              ! adjust plant carbon pools
              cpatch%balive(ico) = cpatch%balive(ico) - delta_bleaf
              cpatch%bstorage(ico) = cpatch%bstorage(ico) + retained_carbon_fraction *   &
                   delta_bleaf
              ! Contribution due to the fact that c2n_leaf and c2n_storage 
              ! may be different
              csite%fsn_in(ipa) = csite%fsn_in(ipa) + delta_bleaf * cpatch%nplant(ico) *  &
                   retained_carbon_fraction *  &
                   (1.0 / c2n_leaf(ipft) - 1.0/c2n_storage)
              
              cpatch%bleaf(ico) = bl_max
              cpatch%cb(13,ico) = cpatch%cb(13,ico) - leaf_litter / cpatch%nplant(ico)
              cpatch%cb_max(13,ico) = cpatch%cb_max(13,ico) - leaf_litter / cpatch%nplant(ico)
           endif

           ! Set status flag
           if(bl_max == 0.0 .or. cpoly%green_leaf_factor(ipft,isi) < 0.02)then
              cpatch%phenology_status(ico) = 2 
              cpatch%bleaf(ico)      = 0.0
           end if

        elseif(cpatch%phenology_status(ico) == 2 .and. phenology(ipft) == 2 .and.  &
             leaf_out_cold == 1)then 
!             cs%green_leaf_factor(cpatch%pft) > 0.02 .and. day < 210)then 
           
           ! Cold deciduous flushing? 
           !print*,'flushing ',cs%green_leaf_factor(cpatch%pft),cs%leaf_aging_factor(cpatch%pft)                      

           ! Update plant carbon pools
           cpatch%phenology_status(ico) = 1 ! 1 indicates leaves are growing
           cpatch%bleaf(ico) = cpoly%green_leaf_factor(ipft,isi) * cpatch%balive(ico)   &
                / (1.0 + qsw(ipft) * cpatch%hite(ico) + q(ipft))

        elseif(phenology(ipft) == 1)then 

           ! Drought deciduous?
           
           if(theta(cpatch%krdepth(ico)) < theta_crit)then
              
              !  it is time to drop leaves
              
              if(cpatch%phenology_status(ico) < 2)then
                 
                 ! update litter pools
                 leaf_litter = (1.0 - retained_carbon_fraction) * cpatch%lai(ico) /   &
                      sla(ipft)
                 csite%fsc_in(ipa) = csite%fsc_in(ipa) + leaf_litter * f_labile(ipft)
                 csite%fsn_in(ipa) = csite%fsn_in(ipa) + leaf_litter * f_labile(ipft) /   &
                      c2n_leaf(ipft)
                 csite%ssc_in(ipa) = csite%ssc_in(ipa) + leaf_litter * (1.0 - f_labile(ipft))
                 csite%ssl_in(ipa) = csite%ssl_in(ipa) + leaf_litter *   &
                      (1.0 - f_labile(ipft)) * l2n_stem / c2n_stem
                 
                 ! update plant carbon pools
                 cpatch%balive(ico) = cpatch%balive(ico) - cpatch%bleaf(ico)
                 cpatch%bstorage(ico) = cpatch%bstorage(ico) + cpatch%bleaf(ico) *   &
                      retained_carbon_fraction
                 ! Contribution due to the fact that c2n_leaf and c2n_storage 
                 ! may be different
                 csite%fsn_in(ipa) = csite%fsn_in(ipa) + cpatch%bleaf(ico) * cpatch%nplant(ico) *  &
                      retained_carbon_fraction *  &
                      (1.0 / c2n_leaf(ipft) - 1.0 / c2n_storage)
                 cpatch%bleaf(ico) = 0.0
                 cpatch%phenology_status(ico) = 2
                 cpatch%cb(13,ico) = cpatch%cb(13,ico) - leaf_litter / cpatch%nplant(ico)
                 cpatch%cb_max(13,ico) = cpatch%cb_max(13,ico) - leaf_litter/cpatch%nplant(ico)

                 
              endif
              
           elseif(theta(cpatch%krdepth(ico)) > theta_crit .and.   &
                cpatch%phenology_status(ico) == 2)then
              
              ! it is time to flush
                 
              ! update carbon pools
              cpatch%phenology_status(ico) = 1
              cpatch%bleaf(ico) = cpatch%balive(ico) / (1.0 + qsw(ipft) * &
                   cpatch%hite(ico) + q(ipft))
              
           endif  ! critical moisture
           
        endif  ! phenology type

        !----- Update LAI, WPA, and WAI accordingly. --------------------------------------!
        call area_indices(cpatch%nplant(ico),cpatch%bleaf(ico),cpatch%bdead(ico)           &
                         ,cpatch%balive(ico),cpatch%dbh(ico), cpatch%hite(ico)             &
                         ,cpatch%pft(ico),cpatch%sla(ico), cpatch%lai(ico)                    &
                         ,cpatch%wpa(ico),cpatch%wai(ico))

        ! Added RGK 10-26-2008
        ! The leaf biomass of the cohort has changed, update the vegetation
        ! energy - using a constant temperature assumption
        old_hcapveg = cpatch%hcapveg(ico)
        cpatch%hcapveg(ico) = calc_hcapveg(cpatch%bleaf(ico),cpatch%bdead(ico)       &
                                          ,cpatch%balive(ico),cpatch%nplant(ico)     &
                                          ,cpatch%hite(ico),cpatch%pft(ico)          &
                                          ,cpatch%phenology_status(ico))
        call update_veg_energy_cweh(csite,ipa,ico,old_hcapveg)
        !---- Likewise, update the patch level one. ---------------------------------!
        csite%hcapveg(ipa) = csite%hcapveg(ipa) + cpatch%hcapveg(ico) - old_hcapveg

        !ipft=cpatch%pft(ico)
        !if (first_time(ipft)) then
        !   first_time(ipft) = .false.
        !   write (unit=40+ipft,fmt='(a10,6(1x,a12))')                                      &
        !      &'      TIME','       PATCH','      COHORT','      NPLANT',' LEAF_LITTER'    &
        !      &            ,'       THETA','  THETA_CRIT'
        !end if
        !
        !write (unit=40+ipft,fmt='(2(i2.2,a1),i4.4,2(1x,i12),4(1x,es12.5))')                &
        !     current_time%month,'/',current_time%date,'/',current_time%year,ipa,ico        &
        !    ,cpatch%nplant(ico),leaf_litter,theta(cpatch%krdepth(ico)),theta_crit

     end do cohortloop ! cohorts

  end do patchloop  ! patches
  return
end subroutine update_phenology_ar


!=======================================================================

subroutine phenology_thresholds(daylight, soil_temp, soil_water, soil_class,  &
     sum_chd, sum_dgd, drop_cold, leaf_out_cold, theta, lsl)

  use grid_coms, only: nzg
  use soil_coms, only: soil, slz
  use phenology_coms, only: dl_tr, st_tr1, st_tr2, phen_a, phen_b, phen_c, &
       iphen_scheme

  implicit none

  real, intent(in) :: daylight
  real, intent(in) :: soil_temp
  real, dimension(nzg), intent(in) :: soil_water
  integer, dimension(nzg), intent(in) :: soil_class
  real, intent(inout) :: sum_dgd
  real, intent(inout) :: sum_chd
  integer, intent(out) :: drop_cold
  integer, intent(out) :: leaf_out_cold
  real, dimension(nzg), intent(out) :: theta
  real :: gdd_threshold
  integer :: k1
  integer :: k2
  integer, intent(in) :: lsl

  ! initialize
  drop_cold = 0
  leaf_out_cold = 0
  theta(1:nzg) = 0.0

  ! This is the Botta et al. scheme.
  if(iphen_scheme == 0)then

     !  determine whether or not we have cold deciduous leaf drop
     if( (daylight <= dl_tr .and. soil_temp < st_tr1) .or.   &
          soil_temp < st_tr2 )then 
        
        ! there is leaf drop
        
        drop_cold = 1
        
     endif

     ! do we have cold deciduous leaf-out?
     
     gdd_threshold = phen_a + phen_b * exp(phen_c * sum_chd)
     if(sum_dgd >= gdd_threshold) leaf_out_cold = 1
     
  endif

  ! calculate average theta for drought deciduous PFTs.  The different
  ! k1's represent different rooting depths.
  
  theta(1:nzg) = 0.0
  do k1 = lsl, nzg
     do k2 = k1,nzg-1
        theta(k1) = theta(k1) + soil_water(k2) *   &
             (slz(k2+1)-slz(k2)) / soil(soil_class(k2))%slmsts
     enddo
     theta(k1) = theta(k1) - soil_water(nzg) * slz(nzg) /  &
          soil(soil_class(nzg))%slmsts
     theta(k1) = - theta(k1) / slz(k1)
  enddo  !! added real() to eliminate implict type casting (MCD)

  return
end subroutine phenology_thresholds

!==============================================================

subroutine cohort_phen_thresholds(green_leaf_factor, leaf_aging_factor,   &
     dbh, pft, drop_cold, leaf_out_cold, bl_max)
  
  use allometry, only: dbh2bl
  implicit none

  integer, intent(out) :: drop_cold
  integer, intent(out) :: leaf_out_cold
  real, intent(out) :: bl_max
  real, intent(in) :: green_leaf_factor
  real, intent(in) :: leaf_aging_factor
  real, intent(in) :: dbh
  integer, intent(in) :: pft

  if(green_leaf_factor /= leaf_aging_factor)then
     drop_cold = 1
  else
     drop_cold = 0
  endif

  if(green_leaf_factor > 0.02 .and. drop_cold == 0)then
     leaf_out_cold = 1
  else
     leaf_out_cold = 0
  endif

  bl_max = green_leaf_factor * dbh2bl(dbh, pft)

  return
end subroutine cohort_phen_thresholds
!==================================================================

subroutine update_phenology_tropics(cpoly, isi)

  use ed_state_vars,only:polygontype,sitetype,patchtype
  use pft_coms, only: phenology, sla, c2n_leaf, q, qsw, l2n_stem, c2n_stem, &
       c2n_storage, leaf_turnover_rate
  use decomp_coms, only: f_labile
  use phenology_coms, only: retained_carbon_fraction, theta_crit
  use allometry, only: dbh2bl
  use ed_therm_lib,only:calc_hcapveg,update_veg_energy_cweh
  use allometry, only : area_indices

  implicit none
  
  real :: delta_bleaf
  type(polygontype),target :: cpoly
  type(sitetype),pointer   :: csite
  type(patchtype),pointer  :: cpatch
  integer :: isi,ipa,ico,ipft
  real :: leaf_litter
  real :: bl_max
  real :: elongf
  real :: old_hcapveg

  ! Loop over patches

  csite => cpoly%site(isi)

  patchloop: do ipa = 1,csite%npatches

     cpatch => csite%patch(ipa)

     ! Re-initialize litter inputs
     csite%fsc_in(ipa) = 0.0
     csite%fsn_in(ipa) = 0.0
     csite%ssc_in(ipa) = 0.0
     csite%ssl_in(ipa) = 0.0

     cohortloop: do ico = 1,cpatch%ncohorts
        ipft = cpatch%pft(ico)
        ! light-controlled
        if(phenology(ipft) == 3)then !tropical evergreen 

        ! water-controlled   
        elseif (phenology(ipft) == 4)then !tropical tropical drought deciduous 
           elongf = min (1.0, cpatch%paw_avg(ico)/theta_crit)
           bl_max = elongf * dbh2bl(cpatch%dbh(ico),ipft)
           delta_bleaf = cpatch%bleaf(ico) - bl_max
           if(delta_bleaf > 0.0)then
              cpatch%phenology_status(ico) = 0 
              leaf_litter = (1.0 - retained_carbon_fraction)  &
                   * delta_bleaf * cpatch%nplant(ico)
              csite%fsc_in(ipa) = csite%fsc_in(ipa) + leaf_litter * f_labile(ipft)
              csite%fsn_in(ipa) = csite%fsn_in(ipa) + leaf_litter * f_labile(ipft) /   &
                   c2n_leaf(ipft)
              csite%ssc_in(ipa) = csite%ssc_in(ipa) + leaf_litter * (1.0 - f_labile(ipft))
              csite%ssl_in(ipa) = csite%ssl_in(ipa) + leaf_litter *   &
                   (1.0 - f_labile(ipft)) * l2n_stem / c2n_stem
              
              ! adjust plant carbon pools
              cpatch%balive(ico) = cpatch%balive(ico) - delta_bleaf
              cpatch%bstorage(ico) = cpatch%bstorage(ico) + retained_carbon_fraction *   &
                   delta_bleaf
              ! Contribution due to the fact that c2n_leaf and c2n_storage 
              ! may be different
              csite%fsn_in(ipa) = csite%fsn_in(ipa) + delta_bleaf * cpatch%nplant(ico) *  &
                   retained_carbon_fraction *  &
                   (1.0 / c2n_leaf(ipft) - 1.0/c2n_storage)
              
              cpatch%bleaf(ico) = bl_max
              cpatch%cb(13,ico) = cpatch%cb(13,ico) - leaf_litter / cpatch%nplant(ico)
              cpatch%cb_max(13,ico) = cpatch%cb_max(13,ico) - leaf_litter / cpatch%nplant(ico)
           elseif (elongf > 0.02) then
              cpatch%phenology_status(ico) = 1 
              cpatch%bleaf(ico) = elongf * cpatch%balive(ico)   &
                / (1.0 + qsw(ipft) * cpatch%hite(ico) + q(ipft))
            endif
           if (elongf < 0.02)then
              cpatch%phenology_status(ico) = 2
              cpatch%bleaf(ico) = 0.0
           endif

         endif  ! phenology type

        !----- Update LAI, SAI, and BAI accordingly. --------------------------------------!
        call area_indices(cpatch%nplant(ico),cpatch%bleaf(ico),cpatch%bdead(ico)           &
                         ,cpatch%balive(ico),cpatch%dbh(ico), cpatch%hite(ico)             &
                         ,cpatch%pft(ico),cpatch%sla(ico), cpatch%lai(ico)                    &
                         ,cpatch%wpa(ico),cpatch%wai(ico))

        ! The leaf biomass of the cohort has changed, update the vegetation
        ! energy - using a constant temperature assumption
        old_hcapveg = cpatch%hcapveg(ico)
        cpatch%hcapveg(ico) = calc_hcapveg(cpatch%bleaf(ico),cpatch%bdead(ico)       &
                                          ,cpatch%balive(ico),cpatch%nplant(ico)     &
                                          ,cpatch%hite(ico),cpatch%pft(ico)          &
                                          ,cpatch%phenology_status(ico))
        call update_veg_energy_cweh(csite,ipa,ico,old_hcapveg)
        !---- Likewise, update the patch level one. ---------------------------------!
        csite%hcapveg(ipa) = csite%hcapveg(ipa) + cpatch%hcapveg(ico) - old_hcapveg


     end do cohortloop ! cohorts

     
  end do patchloop  ! patches
  return
end subroutine update_phenology_tropics


!=======================================================================