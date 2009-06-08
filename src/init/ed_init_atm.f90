
subroutine ed_init_atm_ar
  
  use misc_coms,     only: ied_init_mode,runtype
  use ed_state_vars, only: edtype,polygontype,sitetype,patchtype,edgrid_g
  use soil_coms,     only: soil_rough, isoilstateinit, soil, slmstr
  use consts_coms,    only: cliqvlme, cicevlme, t3ple, tsupercool
  use grid_coms,      only: nzs, nzg, ngrids
  use fuse_fiss_utils_ar, only: fuse_patches_ar,fuse_cohorts_ar
  use ed_node_coms, only: nnodetot,mynum,sendnum,recvnum
  use pft_coms,only : sla
  use ed_therm_lib,only : calc_hcapveg,ed_grndvap
  
  implicit none

  type(edtype)     ,pointer :: cgrid
  type(polygontype),pointer :: cpoly
  type(sitetype),pointer    :: csite
  type(patchtype),pointer   :: cpatch
  integer :: igr,ipy,isi,ipa,ico
  integer :: k
  integer :: nsoil
  integer :: nls
  integer :: nlsw1
  integer :: ncohorts
  real    :: site_area_i, poly_area_i
  real    :: poly_lai, poly_nplant
  real    :: surface_temp, surface_fliq
  integer, parameter :: harvard_override = 0
  include 'mpif.h'
  integer :: ping,ierr
  integer :: npatches
  ping = 6 ! Just any rubbish for MPI Send/Recv

  ! This subroutine fills the ED2 fields which depend on current 
  ! atmospheric conditions.

  do igr = 1,ngrids
     
     cgrid => edgrid_g(igr)
     
     ! First we need to update the meteorological fields.
     call update_met_drivers_array(cgrid)

     ! If this is a standard ED2 restart, we will read these fields in from 
     ! a history file and therefore not worry about setting them here.
     if(ied_init_mode == 4 .or. trim(runtype) == 'HISTORY' )return

     ! Loop over polygons, sites and patches
     
     do ipy = 1,cgrid%npolygons
        
        cpoly => cgrid%polygon(ipy)
        
        do isi = 1,cpoly%nsites
           
           csite => cpoly%site(isi)

           do ipa = 1,csite%npatches
              
              cpatch => csite%patch(ipa)

              csite%can_temp(ipa) =   cpoly%met(isi)%atm_tmp
              csite%can_shv(ipa)  =   cpoly%met(isi)%atm_shv
              csite%can_co2(ipa)  =   cpoly%met(isi)%atm_co2
              
              ! Initialize stars
              csite%tstar(ipa)  = 0.
              csite%ustar(ipa)  = 0.
              csite%qstar(ipa)  = 0.
              csite%cstar(ipa)  = 0.
              
              ! For now, choose heat/vapor capacities for stability
              csite%can_depth(ipa) = 30.0
              
              csite%rshort_g(ipa) = 0.0
              csite%rlong_g(ipa) = 0.0
              
              ! Initialize soil textural class.  Soil water, energy, etc. will
              ! be initialized in the next round of loops.
              do k = 1,nzg
                 csite%ntext_soil(k,ipa) = cpoly%ntext_soil(k,isi)
              enddo
              
              csite%rough(ipa) = soil_rough
              csite%soil_tempk(1,ipa) = -100.0 ! This value functions as a flag.  Do not 
              ! change it here. It will be changed below.

              csite%hcapveg(ipa) = 0.
              do ico = 1,cpatch%ncohorts

                 ! Initialize vegetation properties.
                 ! For now, set heat capacity for stability.

                 cpatch%veg_temp(ico)   = cpoly%met(isi)%atm_tmp
                 cpatch%veg_water(ico)  = 0.0
                 cpatch%veg_fliq(ico)   = 0.0
                 cpatch%hcapveg(ico)    = calc_hcapveg(cpatch%bleaf(ico),cpatch%bdead(ico)   &
                                                      ,cpatch%balive(ico),cpatch%nplant(ico) &
                                                      ,cpatch%hite(ico),cpatch%pft(ico)      &
                                                      ,cpatch%phenology_status(ico))
                 cpatch%veg_energy(ico) = cpatch%hcapveg(ico)*cpatch%veg_temp(ico)
                 csite%hcapveg(ipa) = csite%hcapveg(ipa) + cpatch%hcapveg(ico)
              end do
           end do
        end do
     end do
     ! Initialize remaining soil properties.
     if(isoilstateinit == 1)then
        ! Initialize soil moisture, temperature, etc. from file specified in 
        ! the ED_NL.
        if (nnodetot /= 1) call MPI_Barrier(MPI_COMM_WORLD,ierr)
        if (mynum    /= 1) call MPI_Recv(ping,1,MPI_INTEGER,recvnum,110,MPI_COMM_WORLD,MPI_STATUS_IGNORE,ierr)

        call read_soil_moist_temp_ar(cgrid)

        if (mynum     < nnodetot) call MPI_Send(ping,1,MPI_INTEGER,sendnum,110,MPI_COMM_WORLD,ierr)
        if (nnodetot /=        1) call MPI_Barrier(MPI_COMM_WORLD,ierr)

     end if

     ! Do a simple, uniform initialization or take care of 
     ! missing reanalysis points
     
     ! Loop over polygons, sites, patches.
     do ipy = 1,cgrid%npolygons
        
        cpoly => cgrid%polygon(ipy)
        
        do isi = 1,cpoly%nsites
    
           csite => cpoly%site(isi)

           do ipa = 1,csite%npatches
              
              cpatch => csite%patch(ipa)
              
              if(csite%soil_tempk(1,ipa) == -100.0 .or. isoilstateinit /= 1)then
                 
                 csite%soil_tempk(1:nzg,ipa) = csite%can_temp(ipa)
                 
                 if(csite%can_temp(ipa) > t3ple)then
                    do k = 1, nzg
                       nsoil=csite%ntext_soil(k,ipa)
                       csite%soil_fracliq(k,ipa) = 1.0
                       csite%soil_water(k,ipa)  = max(soil(nsoil)%soilcp                   &
                                                     ,slmstr(k) * soil(nsoil)%slmsts)
                       csite%soil_energy(k,ipa) = soil(nsoil)%slcpd                        &
                                                * csite%soil_tempk(k,ipa)                  &
                                                + csite%soil_water(k,ipa)  * cliqvlme      &
                                                * (csite%soil_tempk(k,ipa) - tsupercool)
                    end do
                 else
                    do k = 1, nzg
                       nsoil=csite%ntext_soil(k,ipa)
                       csite%soil_fracliq(k,ipa) = 0.0
                       csite%soil_water(k,ipa)   = max(soil(nsoil)%soilcp                  &
                                                      ,slmstr(k) * soil(nsoil)%slmsts)
                       csite%soil_energy(k,ipa) = soil(nsoil)%slcpd                        &
                                                * csite%soil_tempk(k,ipa)                  &
                                                + csite%soil_water(k,ipa)                  &
                                                * cicevlme * csite%soil_tempk(k,ipa)
                    end do
                 end if

                 !----- Initial condition is with no snow/pond. ---------------------------!
                 csite%nlev_sfcwater(ipa) = 0
                 do k=1,nzs
                    csite%sfcwater_energy (k,ipa) = 0.
                    csite%sfcwater_depth  (k,ipa) = 0.
                    csite%sfcwater_mass   (k,ipa) = 0.
                    csite%sfcwater_tempk  (k,ipa) = csite%soil_tempk(nzg,ipa)
                    csite%sfcwater_fracliq(k,ipa) = csite%soil_fracliq(nzg,ipa)
                 end do

                 nls   = csite%nlev_sfcwater(ipa)
                 nlsw1 = max(1,nls)
                 call ed_grndvap(nls,                    &
                      csite%ntext_soil       (nzg,ipa),  &
                      csite%soil_water       (nzg,ipa),  &
                      csite%soil_energy      (nzg,ipa),  &
                      csite%sfcwater_energy(nlsw1,ipa),  &
                      cpoly%met(isi)%rhos,  &
                      csite%can_shv(ipa),  &
                      csite%ground_shv(ipa),  &
                      csite%surface_ssh(ipa), surface_temp, surface_fliq)
              endif

              ! Compute patch-level LAI, vegetation height, and roughness
              call update_patch_derived_props_ar(csite, cpoly%lsl(isi), cpoly%met(isi)%rhos, ipa)
              

           enddo
           
           ! Compute basal area and AGB profiles.
           call update_site_derived_props_ar(cpoly, 0, isi)
           
        enddo
        
        
        
     enddo
     
     call update_polygon_derived_props_ar(cgrid)


     call fuse_patches_ar(cgrid, igr)

     do ipy = 1,cgrid%npolygons
        
        ncohorts = 0
        npatches = 0
        poly_lai = 0.0
        poly_nplant = 0.0

        cpoly => cgrid%polygon(ipy)
        poly_area_i = 1./sum(cpoly%area(:))

        do isi = 1,cpoly%nsites
           
           csite => cpoly%site(isi)
           site_area_i = 1./sum(csite%area(:))
           
           do ipa = 1,csite%npatches
              npatches = npatches + 1
              cpatch => csite%patch(ipa)

              call fuse_cohorts_ar(csite,ipa,cpoly%green_leaf_factor(:,isi),cpoly%lsl(isi))
              
              do ico = 1,cpatch%ncohorts
                 ncohorts=ncohorts+1
                 poly_lai    = poly_lai + cpatch%lai(ico) * csite%area(ipa)                &
                                        * cpoly%area(isi) * site_area_i * poly_area_i
                 poly_nplant = poly_nplant + cpatch%nplant(ico) * csite%area(ipa)          &
                                           * cpoly%area(isi) * site_area_i * poly_area_i
              end do
           end do
        end do
        write(unit=*,fmt='(2(a,1x,i4,1x),2(a,1x,f9.4,1x),2(a,1x,f7.2,1x),2(a,1x,i4,1x))')  &
            'Grid:',igr,'Poly:',ipy,'Lon:',cgrid%lon(ipy),'Lat: ',cgrid%lat(ipy)           &
           ,'Nplants:',poly_nplant,'Avg. LAI:',poly_lai                                    &
           ,'NPatches:',npatches,'NCohorts:',ncohorts
     end do
  end do

  return
end subroutine ed_init_atm_ar

!==========================================================================================!
!==========================================================================================!

subroutine update_derived_props(cgrid)
  ! Update some of the derived quantities (this may be redundant)
  use ed_state_vars, only: edtype,polygontype,sitetype
  implicit none
  type(edtype)      , target  :: cgrid
  type(polygontype) , pointer :: cpoly
  type(sitetype)    , pointer :: csite
  integer                     :: ipy, isi, ipa

   do ipy = 1,cgrid%npolygons
     
     cpoly => cgrid%polygon(ipy)
     
     do isi = 1,cpoly%nsites
        csite => cpoly%site(isi)
        do ipa = 1,csite%npatches
           call update_patch_derived_props_ar(csite, cpoly%lsl(isi), cpoly%met(isi)%rhos, ipa)
        enddo
        call update_site_derived_props_ar(cpoly, 0, isi)
     enddo
     call update_polygon_derived_props_ar(cgrid)
   enddo

   return
end subroutine update_derived_props
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine update_patch_derived_props_ar(csite, lsl, rhos, ipa)
  
  use ed_state_vars,only:sitetype,patchtype
  use allometry, only: ed_biomass
  use fusion_fission_coms , only: ff_ndbh     
  use fuse_fiss_utils_ar  , only: patch_pft_size_profile_ar
  implicit none
  integer         , intent(in) :: ipa
  real            , intent(in) :: rhos
  integer         , intent(in) :: lsl
  type(sitetype)  , target     :: csite
  type(patchtype) , pointer    :: cpatch

  real                         :: norm_fac, ba
  integer                      :: ico
  real            , external   :: compute_water_storage_ar
  real            , external   :: compute_energy_storage_ar
  real            , external   :: compute_co2_storage_ar
  real,parameter               :: veg_height_min = 1.0 !was 0.2

  ! call derived patch-level structural quantities.  These depend
  ! on the results from reproduction, which in turn depends on 
  ! structural growth results from all patches.


  ! Reset height
  csite%veg_height(ipa) = 0.0
  csite%lai(ipa)        = 0.0
  csite%wpa(ipa)        = 0.0
  csite%wai(ipa)        = 0.0
  norm_fac              = 0.0
  csite%plant_ag_biomass(ipa) = 0.0
  cpatch => csite%patch(ipa)

  ! Loop over cohorts
  do ico = 1,cpatch%ncohorts
     
     ! Compute contribution to height
     ba = cpatch%nplant(ico) * cpatch%dbh(ico)**2
     norm_fac = norm_fac + ba
     csite%veg_height(ipa) = csite%veg_height(ipa) + cpatch%hite(ico) * ba
     
     ! Update LAI, WPA, WAI,  and AGB
     csite%lai(ipa)  = csite%lai(ipa)  + cpatch%lai(ico)
     csite%wpa(ipa)  = csite%wpa(ipa)  + cpatch%wpa(ico)
     csite%wai(ipa)  = csite%wai(ipa)  + cpatch%wai(ico)
     csite%plant_ag_biomass(ipa)  = csite%plant_ag_biomass(ipa) +                          &
           ed_biomass(cpatch%bdead(ico),cpatch%balive(ico), cpatch%bleaf(ico)              &
                      ,cpatch%pft(ico), cpatch%hite(ico),cpatch%bstorage(ico))             &
           *cpatch%nplant(ico)           
  
  enddo
  
  call patch_pft_size_profile_ar(csite,ipa,ff_ndbh)

  if (csite%lai(ipa).lt.0.0) then
     print*,"STRANGE LAI, ncohorts:",cpatch%ncohorts,"dist type",csite%dist_type(ipa)
     do ico = 1,cpatch%ncohorts
        print*,cpatch%lai(ico),cpatch%bleaf(ico),cpatch%nplant(ico),&
             cpatch%pft(ico),cpatch%phenology_status(ico),cpatch%maintenance_costs(ico),&
             cpatch%bstorage(ico),cpatch%dbh(ico)
     enddo
     stop
  endif

  
  ! Update vegetation height
  if(norm_fac > tiny(1.0))then
     csite%veg_height(ipa) = max(veg_height_min,csite%veg_height(ipa) / norm_fac)
  else
     ! this branch if there aren't any cohorts
     csite%veg_height(ipa) = veg_height_min
  endif
  csite%veg_rough(ipa) = 0.13 * csite%veg_height(ipa)
  

  csite%wbudget_initialstorage(ipa) = compute_water_storage_ar(csite, lsl, rhos, ipa)
  csite%ebudget_initialstorage(ipa) = compute_energy_storage_ar(csite, lsl, rhos, ipa)
  csite%co2budget_initialstorage(ipa) = compute_co2_storage_ar(csite, rhos, ipa)

  csite%cohort_count(ipa) = cpatch%ncohorts

  return
end subroutine update_patch_derived_props_ar
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine update_site_derived_props_ar(cpoly, census_flag, isi)
  
  use ed_state_vars,only: polygontype,sitetype,patchtype
  use allometry, only: ed_biomass
  use consts_coms,    only : pi1
  implicit none
  
  type(polygontype),target :: cpoly
  type(sitetype), pointer :: csite
  type(patchtype), pointer :: cpatch
  integer :: isi,ipa,ico,ilu
  real :: ba
  integer :: bdbh
  integer, intent(in) :: census_flag

  cpoly%basal_area(:,:,isi) = 0.0
  cpoly%agb(:,:,isi) = 0.0
  cpoly%agb_lu(:,isi) = 0.0
  
  csite => cpoly%site(isi)

  do ipa = 1,csite%npatches
     ilu = csite%dist_type(ipa)
     cpatch => csite%patch(ipa)

     do ico = 1,cpatch%ncohorts

        ! Update basal area, agb
        if(census_flag == 0 .or. cpatch%first_census(ico) == 1)then
           bdbh = max(0,min( int(cpatch%dbh(ico) * 0.1), 10)) + 1
           ba = cpatch%nplant(ico) * max(0.0,cpatch%dbh(ico))**2
           cpoly%basal_area(cpatch%pft(ico), bdbh,isi) = cpoly%basal_area(cpatch%pft(ico), bdbh,isi) &
                +  csite%area(ipa) * ba * pi1 * 0.25
           cpoly%agb(cpatch%pft(ico), bdbh,isi) = cpoly%agb(cpatch%pft(ico), bdbh,isi) +  &
                ed_biomass(cpatch%bdead(ico), cpatch%balive(ico), cpatch%bleaf(ico), &
                cpatch%pft(ico), cpatch%hite(ico),cpatch%bstorage(ico)) &
                * cpatch%nplant(ico) * 10.0 * csite%area(ipa)
           cpoly%agb_lu(ilu,isi) = cpoly%agb_lu(ilu,isi) +  &
                ed_biomass(cpatch%bdead(ico), cpatch%balive(ico), cpatch%bleaf(ico), &
                cpatch%pft(ico), cpatch%hite(ico),cpatch%bstorage(ico)) &
                * cpatch%nplant(ico) * 10.0 * csite%area(ipa)
        endif
        
     end do
     
  end do
  
  return
end subroutine update_site_derived_props_ar

!==========================================================================!


subroutine read_soil_moist_temp_ar(cgrid)

  use ed_state_vars, only: edtype, polygontype, sitetype, patchtype
  use soil_coms, only: soilstate_db, soil,slz
  use consts_coms, only: cliqvlme, cicevlme, t3ple, tsupercool
  use grid_coms, only: nzg, nzs, ngrids
  use ed_therm_lib,only:ed_grndvap

  implicit none

  type(edtype)      , target  :: cgrid  ! Alias for current ED grid
  type(polygontype) , pointer :: cpoly  ! Alias for current polygon
  type(sitetype)    , pointer :: csite  ! Alias for current site
  type(patchtype)   , pointer :: cpatch ! Alias for current patch
  integer :: ntext
  real :: glat
  real :: glon
  integer :: ilat
  integer :: ilon
  integer :: ilatf
  integer :: ilonf
  integer :: nls
  integer :: nlsw1
  real :: soil_tempaux
  integer :: k
  real :: tmp1
  real :: tmp2
  real :: soilw1
  real :: soilw2
  logical :: l1
  integer :: ipy, isi, ipa !Counters for all structures
  integer, parameter :: harvard_override = 0
  real    :: surface_temp, surface_fliq
! Putting these numbers as parameters, but we should think in a way to provide this info so we can make it more general.
  integer , parameter :: nlon=144, nlat=73
  real    , parameter :: dlon=2.5, dlat=2.5
  

  inquire(file=trim(soilstate_db),exist=l1)
  if(.not.l1)then
     print*,'You have ISOILSTATEINIT = 1, which means you read initial'
     print*,'soil moisture and temperature from file.  However, the '
     print*,'file you specified for SOILSTATE_DB,'
     print*
     print*,trim(soilstate_db)
     print*
     print*,'does not exist.'
     stop
  endif

  open(unit=12,file=trim(soilstate_db),form='formatted',status='old',position='rewind')
  latloop: do ilatf = 1,nlat  ! Reanalysis has 73 latitude points
     ! 1 corresponds to 90N
     lonloop: do ilonf = 1,nlon  ! Reanalysis has 144 longitude points
        ! 1 corresponds to 0E
        ! Read in reanalysis: two temperatures and moistures, corresponding to different depths
        read(unit=12,fmt=*)tmp1,tmp2,soilw1,soilw2
        ! soilw1, soilw2 are relative porosities and thus range from [0-1]
        ! tmp1, tmp2 are temperature in kelvin.

        ! Make sure it is not buggy
        if(tmp1 > 0.0 .and. tmp2 > 0.0 .and.   &
             soilw1 > 0.0 .and. soilw2 > 0.0)then

           ! Loop over land points
           polyloop: do ipy=1,cgrid%npolygons
              cpoly => cgrid%polygon(ipy)
              
              ! Land point lat, lon
              glat = cgrid%lat(ipy)
              glon = cgrid%lon(ipy)
              
              if(glon < 0.0) glon = glon + 360.0
              
              ! Find reanalysis point corresponding to this land point
              if(glat >= 0.0)then
                 ilat = nint((90.0 - glat)/dlat) + 1
              else
                 ilat = nlat - nint((90.0 - abs(glat))/dlat)
              endif
              ilon = int(glon/dlon) + 1
              
              ! If we are at the right point, fill the array
              if(ilat == ilatf .and. ilon == ilonf)then

                 ! Loop over sites and patches
                 siteloop: do isi=1,cpoly%nsites
                    csite => cpoly%site(isi)
                    
                    patchloop: do ipa=1,csite%npatches
                       cpatch => csite%patch(ipa)

                       do k=1,nzg
                          ntext = csite%ntext_soil(k,ipa)

                          if(abs(slz(k)) < 0.1)then
                             csite%soil_tempk(k,ipa) = tmp1
                             csite%soil_water(k,ipa) = max(soil(ntext)%soilcp              &
                                                          ,soilw1 * soil(ntext)%slmsts)
                          else
                             csite%soil_tempk(k,ipa) = tmp2
                             csite%soil_water(k,ipa) = max(soil(ntext)%soilcp   &
                                                          ,soilw2 * soil(ntext)%slmsts)
                          endif
                          if(csite%soil_tempk(k,ipa) > t3ple)then
                             csite%soil_energy(k,ipa) = soil(ntext)%slcpd                  &
                                                      * csite%soil_tempk(k,ipa)            &
                                                      + csite%soil_water(k,ipa)            &
                                                      * cliqvlme *(csite%soil_tempk(k,ipa) &
                                                                 - tsupercool)
                             csite%soil_fracliq(k,ipa) = 1.0
                          else
                             csite%soil_energy(k,ipa) = soil(ntext)%slcpd                  &
                                                      * csite%soil_tempk(k,ipa)            &
                                                      + csite%soil_water(k,ipa)            &
                                                      * cicevlme * csite%soil_tempk(k,ipa)
                             csite%soil_fracliq(k,ipa) = 0.0
                          end if
                       end do


                      !----- Initial condition is with no snow/pond. ----------------------!
                      csite%nlev_sfcwater(ipa) = 0
                      do k=1,nzs
                         csite%sfcwater_energy (k,ipa) = 0.
                         csite%sfcwater_depth  (k,ipa) = 0.
                         csite%sfcwater_mass   (k,ipa) = 0.
                         csite%sfcwater_tempk  (k,ipa) = csite%soil_tempk(nzg,ipa)
                         csite%sfcwater_fracliq(k,ipa) = csite%sfcwater_fracliq(nzg,ipa)
                       end do

                       if(harvard_override == 1)then
                          csite%soil_tempk(1,ipa)     = 277.6
                          csite%soil_tempk(2:4,ipa)   = 276.0
                          csite%soil_energy(1,ipa)    =   1.5293664e8
                          csite%soil_energy(2,ipa)    =   1.4789957e8
                          csite%soil_energy(3:4,ipa)  =   1.4772002e8
                          csite%soil_water(1:4,ipa)   =   0.41595e+0
                          csite%soil_fracliq(1:4,ipa) =   1.0
                       endif
                       
                       nls = 1
                       call ed_grndvap(nls,                                &
                            csite%ntext_soil       (nzg,ipa),  &
                            csite%soil_water       (nzg,ipa),  &
                            csite%soil_energy      (nzg,ipa),  &
                            csite%sfcwater_energy(nlsw1,ipa),  &
                            cpoly%met(isi)%rhos,  &
                            csite%can_shv(ipa),  &
                            csite%ground_shv(ipa),  &
                            csite%surface_ssh(ipa), &
                            surface_temp, surface_fliq)

                    end do patchloop
                 end do siteloop
                 
              end if
           end do polyloop
        end if
     end do lonloop
  end do latloop
  close(unit=12,status='keep')

  return
end subroutine read_soil_moist_temp_ar
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine update_polygon_derived_props_ar(cgrid)

  use ed_state_vars,only : edtype,polygontype

  implicit none
  integer :: ipy,isi
  type(edtype), target :: cgrid
  type(polygontype), pointer :: cpoly
  

  do ipy=1,cgrid%npolygons
     
     cgrid%agb(:,:,ipy) = 0.0
     cgrid%basal_area(:,:,ipy) = 0.0
     
     cpoly => cgrid%polygon(ipy)
     
     do isi = 1,cpoly%nsites
        cgrid%agb(:,:,ipy) = cgrid%agb(:,:,ipy) + cpoly%area(isi) * cpoly%agb(:,:,isi)
        cgrid%basal_area(:,:,ipy) = cgrid%basal_area(:,:,ipy) + cpoly%area(isi) * cpoly%basal_area(:,:,isi)
     enddo

  enddo

  return
end subroutine update_polygon_derived_props_ar
!==========================================================================================!
!==========================================================================================!