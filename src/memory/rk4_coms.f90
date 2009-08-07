!==========================================================================================!
!==========================================================================================!
!    This module contains several parameters used by the Runge-Kutta integrator scheme.    !
! This module is intended to host the numerical method variables only, variables related   !
! to physical, hydrological or ecological properties should be stored somewhere else.      !
!                                                                                          !
!   MLO. I attempted to describe some variables, not sure about all of them, if the        !
!        definition is wrong, please correct it. Thanks!                                   !
!------------------------------------------------------------------------------------------!
module rk4_coms

   implicit none

   !=======================================================================================!
   !=======================================================================================!
   !     Structure used for the integration using the RK4 method.  Real variables are      !
   ! stored in double precision, so we can solve pools whose order of magnitude are very   !
   ! different.                                                                            !
   !---------------------------------------------------------------------------------------!
   type rk4patchtype

      !----- Canopy air variables. --------------------------------------------------------!
      real(kind=8)                        :: can_temp     ! Temperature          [       K]
      real(kind=8)                        :: can_shv      ! Specific humidity    [   kg/kg]
      real(kind=8)                        :: can_co2      ! CO_2                 [�mol/mol]
      real(kind=8)                        :: can_depth    ! Canopy depth         [       m]
      real(kind=8)                        :: can_mass     ! Canopy total mass    [   kg/m2]
      
      !----- Soil variables. --------------------------------------------------------------!
      real(kind=8), dimension(:), pointer :: soil_energy  ! Internal energy       [   J/m�]
      real(kind=8), dimension(:), pointer :: soil_tempk   ! Specific humidity     [      K]
      real(kind=8), dimension(:), pointer :: soil_fracliq ! Liquid fraction       [   ----]
      real(kind=8), dimension(:), pointer :: soil_water   ! Water content         [  m�/m�]
      real(kind=8), dimension(:), pointer :: psiplusz     ! Water potential       [      m]
      real(kind=8), dimension(:), pointer :: soilair99    ! 99% of field capacity [  m�/m�]
      real(kind=8), dimension(:), pointer :: soilair01    !  1% above wilting pt. [  m�/m�]
      real(kind=8), dimension(:), pointer :: soil_liq     ! Liquid fraction       [  kg/m�]
      real(kind=8), dimension(:), pointer :: available_liquid_water !             [  kg/m�]
      real(kind=8), dimension(:), pointer :: extracted_water        !             [  kg/m�]

      !----- Temporary surface water variables. -------------------------------------------!
      integer                             :: nlev_sfcwater    ! # of layers       [   ----]
      real(kind=8), dimension(:), pointer :: sfcwater_depth   ! Depth             [      m]
      real(kind=8), dimension(:), pointer :: sfcwater_mass    ! Mass              [  kg/m�]
      real(kind=8), dimension(:), pointer :: sfcwater_energy  ! Internal energy   [   J/m�]
      real(kind=8), dimension(:), pointer :: sfcwater_tempk   ! Temperature       [      K]
      real(kind=8), dimension(:), pointer :: sfcwater_fracliq ! Liquid fraction   [   ----]

      !----- Virtual layer variables. -----------------------------------------------------!
      integer                             :: virtual_flag     ! Status flag       [  -----]
      real(kind=8)                        :: virtual_water    ! Mass              [  kg/m�]
      real(kind=8)                        :: virtual_heat     ! Internal energy   [  kg/m�]
      real(kind=8)                        :: virtual_depth    ! Depth             [      m]

      !----- Surface variables. -----------------------------------------------------------!
      real(kind=8)                        :: ground_shv   ! Ground sp. humidity   [  kg/kg]
      real(kind=8)                        :: surface_ssh  ! Surface sp. humidity  [  kg/kg]
      real(kind=8)                        :: surface_temp ! Surface sp. humidity  [  kg/kg]
      real(kind=8)                        :: surface_fliq ! Surface sp. humidity  [  kg/kg]
      real(kind=8)                        :: rough        ! Roughness             [      m]

      !----- Characteristic scale. --------------------------------------------------------!
      real(kind=8)                        :: ustar ! Momentum                     [    m/s]
      real(kind=8)                        :: cstar ! Carbon mixing ratio          [�mol/m�]
      real(kind=8)                        :: tstar ! Temperature                  [      K]
      real(kind=8)                        :: qstar ! Water vapour spec. humidity  [  kg/kg]

      !----- Vertical fluxes. -------------------------------------------------------------!
      real(kind=8)                        :: upwp 
      real(kind=8)                        :: qpwp
      real(kind=8)                        :: cpwp
      real(kind=8)                        :: tpwp
      real(kind=8)                        :: wpwp

      
      !----- Resistance variables. --------------------------------------------------------!
      real(kind=8)                        :: rasveg
      real(kind=8)                        :: root_res_fac
      
      !----- Leaf (cohort-level) variables. -----------------------------------------------!
      real(kind=8), pointer, dimension(:) :: veg_energy ! Internal energy         [   J/m�]
      real(kind=8), pointer, dimension(:) :: veg_water  ! Surface water mass      [  kg/m�]
      real(kind=8), pointer, dimension(:) :: veg_temp   ! Temperature             [      K]
      real(kind=8), pointer, dimension(:) :: veg_fliq   ! Liquid fraction         [    ---]
      real(kind=8), pointer, dimension(:) :: hcapveg    ! Heat capacity           [ J/m�/K]
      real(kind=8), pointer, dimension(:) :: lai        ! Leaf area index         [  m�/m�]
      real(kind=8), pointer, dimension(:) :: wpa        ! Wood projected area     [  m�/m�]
      real(kind=8), pointer, dimension(:) :: tai        ! Tree area index         [  m�/m�]
      real(kind=8), pointer, dimension(:) :: rb         ! Aerodynamic resistance  [    s/m]
      logical     , pointer, dimension(:) :: solvable   ! Can I solve this cohort [    T|F]
      !------------------------------------------------------------------------------------!

      !------------------------------------------------------------------------------------!
      !     Fast time flux diagnostic variables.  These variables may be turned off under  !
      ! different conditions.                                                              !
      !------------------------------------------------------------------------------------!
      real(kind=8) :: avg_netrad        ! Net radiation
      !----- Water fluxes -----------------------------------------------------------------!
      real(kind=8) :: avg_vapor_vc ! Leaf       -> canopy air:  evap./cond. flux
      real(kind=8) :: avg_dew_cg   ! Canopy     -> ground    :  condensation flux
      real(kind=8) :: avg_vapor_gc ! Ground     -> canopy air:  evaporation flux
      real(kind=8) :: avg_vapor_ac ! Free atm.  -> canopy air:  vapour flux
      real(kind=8) :: avg_transp   ! Transpiration
      real(kind=8) :: avg_evap     ! Evaporation
      !----- Mass and energy fluxes due to water shedding. --------------------------------!
      real(kind=8) :: avg_wshed_vg      ! Mass flux
      real(kind=8) :: avg_qwshed_vg     ! Energy flux
      !----- Sensible heat flux -----------------------------------------------------------!
      real(kind=8) :: avg_sensible_vc   ! Leaf      -> canopy air
      real(kind=8) :: avg_sensible_gc   ! Ground    -> canopy air
      real(kind=8) :: avg_sensible_ac   ! Free atm. -> canopy air
      real(kind=8) :: avg_heatstor_veg  ! Heat storage in vegetation
      real(kind=8) :: avg_sensible_tot  ! Sensible heat flux
      real(kind=8) :: avg_sensible_2cas ! Sensible heat flux to canopy air space
      !----- Carbon flux ------------------------------------------------------------------!
      real(kind=8) :: avg_carbon_ac     ! Free atm. -> canopy air
      !----- Soil fluxes ------------------------------------------------------------------!
      real(kind=8),pointer,dimension(:) :: avg_smoist_gg   ! Moisture flux between layers
      real(kind=8),pointer,dimension(:) :: avg_smoist_gc   ! Trabspired soil moisture sink
      real(kind=8),pointer,dimension(:) :: avg_sensible_gg ! Soil heat flux between layers
      real(kind=8)                      :: avg_drainage    ! Drainage at the bottom.
      !----- Full budget variables --------------------------------------------------------!
      real(kind=8) :: co2budget_loss2atm
      real(kind=8) :: ebudget_loss2atm
      real(kind=8) :: ebudget_loss2drainage
      real(kind=8) :: ebudget_loss2runoff
      real(kind=8) :: ebudget_latent
      real(kind=8) :: wbudget_loss2atm
      real(kind=8) :: wbudget_loss2drainage
      real(kind=8) :: wbudget_loss2runoff
   end type rk4patchtype
   !---------------------------------------------------------------------------------------!


   !----- Structure with atmospheric data -------------------------------------------------!
   type rk4mettype
      integer      :: lsl
      real(kind=8) :: rhos
      real(kind=8) :: vels
      real(kind=8) :: atm_tmp
      real(kind=8) :: atm_theta
      real(kind=8) :: atm_shv
      real(kind=8) :: atm_co2
      real(kind=8) :: zoff
      real(kind=8) :: exner
      real(kind=8) :: pcpg
      real(kind=8) :: qpcpg
      real(kind=8) :: dpcpg
      real(kind=8) :: prss
      real(kind=8) :: geoht
      real(kind=8) :: lon
      real(kind=8) :: lat
   end type rk4mettype
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   ! Structure with all the necessary buffers.                                             !
   !---------------------------------------------------------------------------------------!
   type integration_vars
      type(rk4patchtype) :: initp   ! The current state
      type(rk4patchtype) :: dinitp  ! The derivatives
      type(rk4patchtype) :: yscal   ! The scale for prognostic variables
      type(rk4patchtype) :: y       ! 
      type(rk4patchtype) :: dydx    ! 
      type(rk4patchtype) :: yerr    ! The error for the current guess
      type(rk4patchtype) :: ytemp   ! Temporary
      type(rk4patchtype) :: ak2     ! 
      type(rk4patchtype) :: ak3     !
      type(rk4patchtype) :: ak4     ! 
      type(rk4patchtype) :: ak5     ! 
      type(rk4patchtype) :: ak6     ! 
      type(rk4patchtype) :: ak7     ! 
   end type integration_vars
   !---------------------------------------------------------------------------------------!


   !----- This is the actual integration buffer structure. --------------------------------!
   type(integration_vars) :: integration_buff
   type(rk4mettype)          :: rk4met
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !    The following variable will be loaded from the user's namelist.                    !
   !---------------------------------------------------------------------------------------!
   integer                   :: ibranch_thermo ! This flag tells whether we consider the 
                                               !    branch actively affecting heat capacity
                                               !    and radiation interception. 
                                               ! 0 - no (default);
                                               ! 1 - yes (under development/test);
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !    The following variables are parameters that do not depend on the specific run.     !
   !---------------------------------------------------------------------------------------!

   !----- Small number, to avoid singularities. -------------------------------------------!
   real(kind=8), parameter :: tiny_offset = 1.d-20
   !----- Huge number, to bypass errmax checks. -------------------------------------------!
   real(kind=8), parameter :: huge_offset = 1.d30
   !---------------------------------------------------------------------------------------!

   !---------------------------------------------------------------------------------------!
   !     These are all RK4 integrator factors.  These should never be changed, so they are !
   ! declared as parameters and will not be initialised at init_rk4_coms (ed_params.f90)   !
   !---------------------------------------------------------------------------------------!
   real(kind=8), parameter :: a2  = 2.d-1
   real(kind=8), parameter :: a3  = 3.d-1
   real(kind=8), parameter :: a4  = 6.d-1
   real(kind=8), parameter :: a5  = 1.d0
   real(kind=8), parameter :: a6  = 8.75d-1
   real(kind=8), parameter :: b21 = 2.d-1
   real(kind=8), parameter :: b31 = 3.d0/4.d1
   real(kind=8), parameter :: b32 = 9.d0/4.d1
   real(kind=8), parameter :: b41 = 3.d-1
   real(kind=8), parameter :: b42 = -9.d-1
   real(kind=8), parameter :: b43 = 1.2d0  
   real(kind=8), parameter :: b51 = -1.1d1/5.4d1
   real(kind=8), parameter :: b52 = 2.5d0
   real(kind=8), parameter :: b53 = -7.d1/2.7d1
   real(kind=8), parameter :: b54 = 3.5d1/2.7d1
   real(kind=8), parameter :: b61 = 1.631d3/5.52960d4
   real(kind=8), parameter :: b62 = 1.750d2/5.120d2
   real(kind=8), parameter :: b63 = 5.750d2/1.38240d4
   real(kind=8), parameter :: b64 = 4.42750d4/1.105920d5
   real(kind=8), parameter :: b65 = 2.530d2/4.0960d3
   real(kind=8), parameter :: c1  = 3.70d1/3.780d2
   real(kind=8), parameter :: c3  = 2.500d2/6.210d2
   real(kind=8), parameter :: c4  = 1.250d2/5.940d2
   real(kind=8), parameter :: c6  = 5.120d2/1.7710d3
   real(kind=8), parameter :: dc5 = -2.770d2/1.43360d4
   real(kind=8), parameter :: dc1 = c1-2.8250d3/2.76480d4
   real(kind=8), parameter :: dc3 = c3-1.85750d4/4.83840d4
   real(kind=8), parameter :: dc4 = c4-1.35250d4/5.52960d4
   real(kind=8), parameter :: dc6 = c6-2.5d-1
   !---------------------------------------------------------------------------------------!

   !---------------------------------------------------------------------------------------!
   !     Maybe these could go to ed_params.f90 initialization.  Leaving them here for the  !
   ! time being.                                                                           !
   !---------------------------------------------------------------------------------------!
   real(kind=8), parameter :: safety =  9.d-1
   real(kind=8), parameter :: pgrow =  -2.d-1
   real(kind=8), parameter :: pshrnk = -2.5d-1
   real(kind=8), parameter :: errcon =  1.89d-4
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !     The following variables are assigned at init_rk4_params (ed_params.f90).          !
   !---------------------------------------------------------------------------------------!

   !----- The following variables control the Runge-Kutta performance. --------------------!
   integer      :: maxstp      ! Maximum number of intermediate steps.
   real(kind=8) :: rk4eps      ! Desired relative accuracy
   real(kind=8) :: rk4epsi     ! Inverse of rk4eps
   real(kind=8) :: hmin        ! Minimum step size
   logical      :: print_diags ! Flag to print the diagnostic check.
   logical      :: checkbudget ! Flag to decide whether we will check whether the budgets 
                               !    close every time step (and stop the run if they don't)
                               !    or if we will skip this part.
   !---------------------------------------------------------------------------------------!



   !----- Constants used in rk4_derivs ----------------------------------------------------!
   logical      :: debug         ! Verbose output for debug                        [   T|F]
   real(kind=8) :: toocold       ! Minimum temperature for saturation spec. hum.   [     K]
   real(kind=8) :: toohot        ! Maximum temperature for saturation spec. hum.   [     K]
   real(kind=8) :: lai_to_cover  ! Canopies with LAI less than this number are assumed to
                                 !     be open, ie, some fraction of the rain-drops can 
                                 !     reach the soil/litter layer unimpeded.
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !    These two parameter will scale the cohort heat capacity inside the RK4 integrator, !
   ! to avoid having patches with heat capacity that is way too small to be computational- !
   ! ly stable and solvable in a fast way.                                                 !
   !---------------------------------------------------------------------------------------!
   real(kind=8) :: hcapveg_ref         ! Reference value                          [ J/m�/K]
   real(kind=8) :: min_height          ! Minimum vegetation height                [      m]
   real(kind=8) :: hcapveg_stab_thresh ! Minimum stable patch-level heat capacity [ J/m�/K]
   !----- This is compared with the original heat capacity, leave it single precision. ----!
   real         :: hcapveg_coh_min     ! Minimum solvable cohort-level heat cap.  [ J/m�/K]
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !    The following variables are the bounds of what we could consider barely reasonable !
   ! during the integration process. If values go beyond these limits, reject the step     !
   ! right away.  These numbers are filled in init_rk4_params (ed_params.f90).  Most of    !
   ! them are in the same units we are used to, but note that the last ones have different !
   ! units to make it scalable.                                                            !
   !---------------------------------------------------------------------------------------!
   real(kind=8) :: rk4min_can_temp      ! Minimum canopy    temperature         [        K]
   real(kind=8) :: rk4max_can_temp      ! Maximum canopy    temperature         [        K]
   real(kind=8) :: rk4min_can_shv       ! Minimum canopy    specific humidity   [kg/kg_air]
   real(kind=8) :: rk4max_can_shv       ! Maximum canopy    specific humidity   [kg/kg_air]
   real(kind=8) :: rk4max_can_rhv       ! Maximum canopy    relative humidity   [      ---]
   real(kind=8) :: rk4min_can_co2       ! Minimum canopy    CO2 mixing ratio    [ �mol/mol]
   real(kind=8) :: rk4max_can_co2       ! Maximum canopy    CO2 mixing ratio    [ �mol/mol]
   real(kind=8) :: rk4min_soil_temp     ! Minimum soil      temperature         [        K]
   real(kind=8) :: rk4max_soil_temp     ! Maximum soil      temperature         [        K]
   real(kind=8) :: rk4min_veg_temp      ! Minimum leaf      temperature         [        K]
   real(kind=8) :: rk4max_veg_temp      ! Maximum leaf      temperature         [        K]
   real(kind=8) :: rk4min_sfcw_temp     ! Minimum snow/pond temperature         [        K]
   real(kind=8) :: rk4max_sfcw_temp     ! Maximum snow/pond temperature         [        K]
   !----- The following variables have units different from the actual value. -------------!
   real(kind=8) :: rk4min_veg_lwater    ! Maximum leaf      surface water mass  [kg/m�leaf]
   real(kind=8) :: rk4min_sfcw_moist    ! Maximum snow/pond water mass          [m�/m�soil]
   real(kind=8) :: rk4min_virt_moist    ! Minimum virtual pool mass             [m�/m�soil]
   !----- The following variables will be defined in sfcdata_ed (ed_init.f90). ------------!
   real(kind=8) :: rk4min_sfcw_mass     ! Minimum snow/pond    mass             [    kg/m�]
   real(kind=8) :: rk4min_virt_water    ! Minimum virtual pool mass             [    kg/m�]
   !---------------------------------------------------------------------------------------!


   !----- The following variables are double precision version of some bounds. ------------!
   real(kind=8) :: rk4min_sfcwater_mass ! Min. non-negligible snow/pond mass    [    kg/m�]
   real(kind=8) :: rk4water_stab_thresh ! Min. mass for a layer to be stable    [    kg/m�]
   real(kind=8) :: rk4snowmin           ! Min. snow mass required for a new lyr [    kg/m�]
   real(kind=8) :: rk4dry_veg_lwater    ! Min. non-negligible leaf water mass   [kg/m�leaf]
   real(kind=8) :: rk4fullveg_lwater    ! Max. leaf water mass possible         [kg/m�leaf]
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !     These variables are assigned during the integration process. They are not set at  !
   ! ed_params.f90, and their values may change during the simulation.                     !
   !---------------------------------------------------------------------------------------!

   !---------------------------------------------------------------------------------------!
   !     Integration limits for time. Since 'derivs' do not explicitly depend on time it   !
   ! doesn't really matter what this is as long as tend-tbeg makes sense.                  !
   !---------------------------------------------------------------------------------------!
   real(kind=8)   :: tbeg
   real(kind=8)   :: tend
   real(kind=8)   :: dtrk4
   real(kind=8)   :: dtrk4i
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !     These two variables are assigned in rk4_driver.f90, together with the time vari-  !
   ! ables.  This is because their number will be different depending on whether branches  !
   ! and twigs area are explicitly computed or just estimated as 20% of LAI for heat and   !
   ! water exchange between the vegetation and the canopy air.                             !
   !---------------------------------------------------------------------------------------!
   real(kind=8) :: effarea_water ! Evaporation area: related to LAI
   real(kind=8) :: effarea_heat  ! Heat area: related to 2*LAI
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !     Flag to determine whether the patch is too sparsely populated to be computed at   !
   ! the cohort level.  The decision is made based on the difference in order of magnitude !
   ! between the patch "natural" leaf heat capacity and the minimum heat capacity for the  !
   ! Runge-Kutta solver (checked at copy_patch_init).                                   !
   !---------------------------------------------------------------------------------------!
   logical :: toosparse
   
   !----- Flag to tell whether there is at least one "solvable" cohort in this patch ------!
   logical :: any_solvable

   !----- Canopy water and heat capacity variables. ---------------------------------------!
   real(kind=8)    :: zoveg
   real(kind=8)    :: zveg
   real(kind=8)    :: wcapcan
   real(kind=8)    :: wcapcani
   real(kind=8)    :: ccapcani
   real(kind=8)    :: hcapcani
   !=======================================================================================!
   !=======================================================================================!





   contains
   !=======================================================================================!
   !=======================================================================================!
   !     This subroutine will perform the temporary patch allocation for the RK4           !
   ! integration.                                                                          !
   !---------------------------------------------------------------------------------------!
   subroutine allocate_rk4_patch(y)
      use grid_coms     , only : nzg          & ! intent(in)
                               , nzs          ! ! intent(in)
      implicit none
      !----- Argument ---------------------------------------------------------------------!
      type(rk4patchtype) :: y
      !------------------------------------------------------------------------------------!

      call nullify_rk4_patch(y)

      allocate(y%soil_energy(nzg))
      allocate(y%soil_water(nzg))
      allocate(y%soil_fracliq(nzg))
      allocate(y%soil_tempk(nzg))
      allocate(y%available_liquid_water(nzg))
      allocate(y%extracted_water(nzg))
      allocate(y%psiplusz(nzg))
      allocate(y%soilair99(nzg))
      allocate(y%soilair01(nzg))
      allocate(y%soil_liq(nzg))

      allocate(y%sfcwater_energy(nzs))
      allocate(y%sfcwater_mass(nzs))
      allocate(y%sfcwater_depth(nzs))
      allocate(y%sfcwater_fracliq(nzs))
      allocate(y%sfcwater_tempk(nzs))

      !------------------------------------------------------------------------------------!
      !     Diagnostics - for now we will always allocate the diagnostics, even if they    !
      !                   aren't used.                                                     !
      !------------------------------------------------------------------------------------!
      allocate(y%avg_sensible_gg(nzg))
      allocate(y%avg_smoist_gg(nzg))
      allocate(y%avg_smoist_gc(nzg))

      call zero_rk4_patch(y)

      return
   end subroutine allocate_rk4_patch
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !     This subroutine will nullify all pointers, to make a safe allocation.             !
   !---------------------------------------------------------------------------------------!
   subroutine nullify_rk4_patch(y)
      implicit none
      !----- Argument ---------------------------------------------------------------------!
      type(rk4patchtype) :: y
      !------------------------------------------------------------------------------------!

      nullify(y%soil_energy)
      nullify(y%soil_water)
      nullify(y%soil_fracliq)
      nullify(y%soil_tempk)
      nullify(y%available_liquid_water)
      nullify(y%extracted_water)
      nullify(y%psiplusz)
      nullify(y%soilair99)
      nullify(y%soilair01)
      nullify(y%soil_liq)

      nullify(y%sfcwater_energy)
      nullify(y%sfcwater_mass)
      nullify(y%sfcwater_depth)
      nullify(y%sfcwater_fracliq)
      nullify(y%sfcwater_tempk)

      !------------------------------------------------------------------------------------!
      !     Diagnostics - for now we will always allocate the diagnostics, even if they    !
      !                   aren't used.                                                     !
      !------------------------------------------------------------------------------------!
      nullify(y%avg_smoist_gg)
      nullify(y%avg_smoist_gc)
      nullify(y%avg_sensible_gg)

      return
   end subroutine nullify_rk4_patch
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !    Forcing all variables to be zero.                                                  !
   !---------------------------------------------------------------------------------------!
   subroutine zero_rk4_patch(y)
      use grid_coms     , only : nzg          & ! intent(in)
                               , nzs          ! ! intent(in)
      implicit none
      !----- Argument ---------------------------------------------------------------------!
      type(rk4patchtype) :: y
      !------------------------------------------------------------------------------------!

      y%co2budget_loss2atm             = 0.d0
      y%ebudget_loss2atm               = 0.d0
      y%ebudget_latent                 = 0.d0
      y%ebudget_loss2drainage          = 0.d0
      y%ebudget_loss2runoff            = 0.d0
      y%wbudget_loss2atm               = 0.d0
      y%wbudget_loss2drainage          = 0.d0
      y%wbudget_loss2runoff            = 0.d0
     
      y%can_temp                       = 0.d0
      y%can_shv                        = 0.d0
      y%can_co2                        = 0.d0
      y%can_depth                      = 0.d0
      y%can_mass                      = 0.d0
      y%virtual_water                  = 0.d0
      y%virtual_heat                   = 0.d0
      y%virtual_depth                  = 0.d0
     
      y%ground_shv                     = 0.d0
      y%surface_ssh                    = 0.d0
      y%surface_temp                   = 0.d0
      y%surface_fliq                   = 0.d0
      y%nlev_sfcwater                  = 0
     
      y%rough                          = 0.d0
     
      y%ustar                          = 0.d0
      y%cstar                          = 0.d0
      y%tstar                          = 0.d0
      y%qstar                          = 0.d0
      y%virtual_flag                   = 0
      y%avg_carbon_ac                  = 0.d0
     
      y%upwp                           = 0.d0
      y%wpwp                           = 0.d0
      y%tpwp                           = 0.d0
      y%qpwp                           = 0.d0
      y%cpwp                           = 0.d0
      
      y%rasveg                         = 0.d0
     

      y%avg_vapor_vc                   = 0.d0
      y%avg_dew_cg                     = 0.d0
      y%avg_vapor_gc                   = 0.d0
      y%avg_wshed_vg                   = 0.d0
      y%avg_vapor_ac                   = 0.d0
      y%avg_transp                     = 0.d0
      y%avg_evap                       = 0.d0
      y%avg_netrad                     = 0.d0
      y%avg_sensible_vc                = 0.d0
      y%avg_sensible_2cas              = 0.d0
      y%avg_qwshed_vg                  = 0.d0
      y%avg_sensible_gc                = 0.d0
      y%avg_sensible_ac                = 0.d0
      y%avg_sensible_tot               = 0.d0
      y%avg_heatstor_veg               = 0.d0

      y%avg_drainage                   = 0.d0

      !----- The following variables are pointers, check whether they are linked or not. --!
      if(associated(y%soil_energy           ))   y%soil_energy(:)                 = 0.d0
      if(associated(y%soil_tempk            ))   y%soil_tempk(:)                  = 0.d0
      if(associated(y%soil_fracliq          ))   y%soil_fracliq(:)                = 0.d0
      if(associated(y%soil_water            ))   y%soil_water(:)                  = 0.d0
      if(associated(y%available_liquid_water))   y%available_liquid_water(:)      = 0.d0
      if(associated(y%extracted_water       ))   y%extracted_water(:)             = 0.d0
      if(associated(y%psiplusz              ))   y%psiplusz(:)                    = 0.d0
      if(associated(y%soilair99             ))   y%soilair99(:)                   = 0.d0
      if(associated(y%soilair01             ))   y%soilair01(:)                   = 0.d0
      if(associated(y%soil_liq              ))   y%soil_liq(:)                    = 0.d0
     
      if(associated(y%sfcwater_depth        ))   y%sfcwater_depth(:)              = 0.d0
      if(associated(y%sfcwater_mass         ))   y%sfcwater_mass(:)               = 0.d0
      if(associated(y%sfcwater_energy       ))   y%sfcwater_energy(:)             = 0.d0
      if(associated(y%sfcwater_tempk        ))   y%sfcwater_tempk(:)              = 0.d0
      if(associated(y%sfcwater_fracliq      ))   y%sfcwater_fracliq(:)            = 0.d0

      if(associated(y%avg_smoist_gg         ))   y%avg_smoist_gg(:)               = 0.d0
      if(associated(y%avg_smoist_gc         ))   y%avg_smoist_gc(:)               = 0.d0
      if(associated(y%avg_sensible_gg       ))   y%avg_sensible_gg(:)             = 0.d0

      return
   end subroutine zero_rk4_patch
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !    This subroutine will perform the temporary patch deallocation.                     !
   !---------------------------------------------------------------------------------------!
   subroutine deallocate_rk4_patch(y)
      implicit none
      !----- Argument ---------------------------------------------------------------------!
      type(rk4patchtype) :: y
      !------------------------------------------------------------------------------------!

      if (associated(y%soil_energy))             deallocate(y%soil_energy)
      if (associated(y%soil_water))              deallocate(y%soil_water)
      if (associated(y%soil_fracliq))            deallocate(y%soil_fracliq)
      if (associated(y%soil_tempk))              deallocate(y%soil_tempk)
      if (associated(y%available_liquid_water))  deallocate(y%available_liquid_water)
      if (associated(y%extracted_water))         deallocate(y%extracted_water)
      if (associated(y%psiplusz))                deallocate(y%psiplusz)
      if (associated(y%soilair99))               deallocate(y%soilair99)
      if (associated(y%soilair01))               deallocate(y%soilair01)
      if (associated(y%soil_liq))                deallocate(y%soil_liq)

      if (associated(y%sfcwater_energy))         deallocate(y%sfcwater_energy)
      if (associated(y%sfcwater_mass))           deallocate(y%sfcwater_mass)
      if (associated(y%sfcwater_depth))          deallocate(y%sfcwater_depth)
      if (associated(y%sfcwater_fracliq))        deallocate(y%sfcwater_fracliq)
      if (associated(y%sfcwater_tempk))          deallocate(y%sfcwater_tempk)
      
      ! Diagnostics
      if (associated(y%avg_smoist_gg))           deallocate(y%avg_smoist_gg)
      if (associated(y%avg_smoist_gc))           deallocate(y%avg_smoist_gc)
      if (associated(y%avg_sensible_gg))         deallocate(y%avg_sensible_gg)

      return
   end subroutine deallocate_rk4_patch
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !    This subroutine will allocate the cohorts of the temporary patch.                  !
   !---------------------------------------------------------------------------------------!

   subroutine allocate_rk4_coh(maxcohort,y)
      implicit none
      !----- Arguments --------------------------------------------------------------------!
      type(rk4patchtype)              :: y
      integer            , intent(in) :: maxcohort
      !------------------------------------------------------------------------------------!
      
      call nullify_rk4_cohort(y)

      allocate(y%veg_energy(maxcohort))
      allocate(y%veg_water(maxcohort))
      allocate(y%veg_temp(maxcohort))
      allocate(y%veg_fliq(maxcohort))
      allocate(y%hcapveg(maxcohort))
      allocate(y%lai(maxcohort))
      allocate(y%wpa(maxcohort))
      allocate(y%tai(maxcohort))
      allocate(y%rb(maxcohort))
      allocate(y%solvable(maxcohort))

      call zero_rk4_cohort(y)

      return
   end subroutine allocate_rk4_coh
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !    This subroutine will nullify the cohort pointers for a safe allocation.            !
   !---------------------------------------------------------------------------------------!
   subroutine nullify_rk4_cohort(y)
      implicit none
      !----- Arguments --------------------------------------------------------------------!
      type(rk4patchtype) :: y
      !------------------------------------------------------------------------------------!
          
      nullify(y%veg_energy)
      nullify(y%veg_water)
      nullify(y%veg_temp)
      nullify(y%veg_fliq)
      nullify(y%hcapveg)
      nullify(y%lai)
      nullify(y%wpa)
      nullify(y%tai)
      nullify(y%rb)
      nullify(y%solvable)

      return
   end subroutine nullify_rk4_cohort
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !    This subroutine will initialize the cohort variables with zeroes.                  !
   !---------------------------------------------------------------------------------------!
   subroutine zero_rk4_cohort(y)
      implicit none
      !----- Arguments --------------------------------------------------------------------!
      type(rk4patchtype) :: y
      !------------------------------------------------------------------------------------!

      if(associated(y%veg_energy    ))  y%veg_energy    = 0.d0
      if(associated(y%veg_water     ))  y%veg_water     = 0.d0
      if(associated(y%veg_temp      ))  y%veg_temp      = 0.d0
      if(associated(y%veg_fliq      ))  y%veg_fliq      = 0.d0
      if(associated(y%hcapveg       ))  y%hcapveg       = 0.d0
      if(associated(y%lai           ))  y%lai           = 0.d0
      if(associated(y%wpa           ))  y%wpa           = 0.d0
      if(associated(y%tai           ))  y%tai           = 0.d0
      if(associated(y%rb            ))  y%rb            = 0.d0
      if(associated(y%solvable      ))  y%solvable      = .false.

      return
   end subroutine zero_rk4_cohort
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !    This subroutine will deallocate the cohorts of the temporary patch.                !
   !---------------------------------------------------------------------------------------!
   subroutine deallocate_rk4_coh(y)
      implicit none
      !----- Arguments --------------------------------------------------------------------!
      type(rk4patchtype) :: y
      !------------------------------------------------------------------------------------!

      if(associated(y%veg_energy    ))  deallocate(y%veg_energy)
      if(associated(y%veg_water     ))  deallocate(y%veg_water )
      if(associated(y%veg_temp      ))  deallocate(y%veg_temp  )
      if(associated(y%veg_fliq      ))  deallocate(y%veg_fliq  )
      if(associated(y%hcapveg       ))  deallocate(y%hcapveg   )
      if(associated(y%lai           ))  deallocate(y%lai       )
      if(associated(y%wpa           ))  deallocate(y%wpa       )
      if(associated(y%tai           ))  deallocate(y%tai       )
      if(associated(y%rb            ))  deallocate(y%rb        )
      if(associated(y%solvable      ))  deallocate(y%solvable  )

      return
   end subroutine deallocate_rk4_coh
   !=======================================================================================!
   !=======================================================================================!
end module rk4_coms
!==========================================================================================!
!==========================================================================================!
