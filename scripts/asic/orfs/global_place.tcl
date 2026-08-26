utl::set_metrics_stage "globalplace__{}"
source $::env(SCRIPTS_DIR)/load.tcl
erase_non_stage_variables place
load_design 3_2_place_iop.odb 2_floorplan.sdc
source_step_tcl PRE GLOBAL_PLACE

set_dont_use $::env(DONT_USE_CELLS)

# The external-chip flow uses a non-timing-driven guided first pass, releases
# those guides in PRE_GLOBAL_PLACE, then asks this IO-aware pass for a genuine
# unconstrained timing refinement.  This avoids unsupported timing-driven
# resizing inside OpenDB regions while still shortening critical boundary
# connections after the architecture has shaped the placement.
set z8086_timing_driven [expr {
  $::env(GPL_TIMING_DRIVEN)
  || ([info exists ::env(Z8086_TIMING_REFINEMENT)]
      && $::env(Z8086_TIMING_REFINEMENT))
}]

if { $z8086_timing_driven } {
  remove_buffers
}

# Do not buffer chip-level designs
# by default, IO ports will be buffered
# to not buffer IO ports, set environment variable
# DONT_BUFFER_PORT = 1
if { ![env_var_exists_and_non_empty FOOTPRINT] } {
  if { !$::env(DONT_BUFFER_PORTS) } {
    puts "Perform port buffering..."
    buffer_ports {*}[env_var_or_empty BUFFER_PORTS_ARGS]
  }
}

set global_placement_args {}

# Parameters for routability mode in global placement
append_env_var global_placement_args GPL_ROUTABILITY_DRIVEN -routability_driven 0

append_env_var global_placement_args GPL_RANDOM_SEED -random_seed 1

# Parameters for timing driven mode in global placement
if { $z8086_timing_driven } {
  lappend global_placement_args {-timing_driven}
  if {
    [info exists ::env(Z8086_TIMING_REFINEMENT)]
    && $::env(Z8086_TIMING_REFINEMENT)
  } {
    # The guided seed is already below RePlAce's default 10% overflow exit
    # threshold. Continue far enough to perform real timing/wirelength
    # refinement instead of accepting iteration zero.
    lappend global_placement_args -overflow 0.03
  }
  if { [info exists ::env(GPL_KEEP_OVERFLOW)] } {
    lappend global_placement_args -keep_resize_below_overflow $::env(GPL_KEEP_OVERFLOW)
  }
}

# Parameters for phi coefficients in global placement
set min_phi $::env(MIN_PLACE_STEP_COEF)
set max_phi $::env(MAX_PLACE_STEP_COEF)

if { $min_phi > $max_phi } {
  utl::error GPL 200 \
    "MIN_PLACE_STEP_COEF ($min_phi) cannot be greater than \
MAX_PLACE_STEP_COEF ($max_phi)"
}

# ORFS normally forces every cell back to the die centre.  That conflicts with
# an explicit -skip_initial_place request and discards an architectural seed.
# Preserve upstream behavior for every design that did not request the flag.
set user_global_placement_args [env_var_or_empty GLOBAL_PLACEMENT_ARGS]
if {[lsearch -exact $user_global_placement_args -skip_initial_place] < 0} {
  lappend global_placement_args -force_center_initial_place
}

lappend global_placement_args -min_phi_coef $::env(MIN_PLACE_STEP_COEF)
lappend global_placement_args -max_phi_coef $::env(MAX_PLACE_STEP_COEF)

# The on-die SRAM floorplan already has a connectivity- and architecture-aware
# pin-independent placement.  Incremental IO placement preserves that result
# while accommodating port buffers and physical pin locations.
if {
  [info exists ::env(Z8086_INCREMENTAL_IO_PLACE)]
  && $::env(Z8086_INCREMENTAL_IO_PLACE)
} {
  lappend global_placement_args -incremental
}

proc do_placement { global_placement_args } {
  set all_args [concat [list -density [place_density_with_lb_addon] \
    -pad_left $::env(CELL_PAD_IN_SITES_GLOBAL_PLACEMENT) \
    -pad_right $::env(CELL_PAD_IN_SITES_GLOBAL_PLACEMENT)] \
    $global_placement_args]

  lappend all_args {*}[env_var_or_empty GLOBAL_PLACEMENT_ARGS]

  log_cmd global_placement {*}$all_args
}

set result [catch { do_placement $global_placement_args } errMsg]
if { $result != 0 } {
  orfs_write_db $::env(RESULTS_DIR)/3_3_place_gp-failed.odb
  error $errMsg
}

log_cmd estimate_parasitics -placement

if { $::env(CLUSTER_FLOPS) } {
  log_cmd cluster_flops {*}[env_var_or_empty CLUSTER_FLOPS_ARGS]
  log_cmd estimate_parasitics -placement
}

report_metrics 3 "global place" false false

source_step_tcl POST GLOBAL_PLACE

orfs_write_db $::env(RESULTS_DIR)/3_3_place_gp.odb
