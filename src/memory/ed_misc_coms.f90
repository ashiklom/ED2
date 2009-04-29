Module ed_misc_coms

  ! DO NOT INITIALIZE NON-PARAMETERS IN THERE MODULES - NOT ALL COMPILERS WILL ACTUALLY INITIALIZE THEM

  implicit none

  !! misc variables that are NOT shared with BRAMS and thus do not go in misc_coms

  integer :: burnin          !! number of years to ignore demography when starting a run

  integer :: outputMonth     !! month to output annual files

  integer :: restart_target_year    !! year to read when parsing pss/css with multiple years

  integer :: use_target_year        !! flag specifying whether to search for a target year in pss/css


  ! Logical Switches for various memory structures

  logical :: fast_diagnostics       !! If ifoutput,idoutput,and imoutput are zero, then
                                    !! there is no need to integrate fast flux diagnostics

  ! Namelist option to attach metadata to HDF5 output files 0=no, 1=yes

  integer :: attach_metadata
  
  integer :: icanturb


end Module ed_misc_coms
