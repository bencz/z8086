# Compatibility copy of the pinned ORFS final_outputs.tcl.
# OpenROAD 26Q3 deprecates extract_parasitics -ext_model_file; register the
# rules first and invoke extraction without the obsolete option.
# Delete routing obstructions from the tapeout DEF and emit the logical
# netlist. These outputs are consumed by the KLayout GDS merge.
source $::env(SCRIPTS_DIR)/deleteRoutingObstructions.tcl
deleteRoutingObstructions

write_def $::env(RESULTS_DIR)/6_final.def
write_verilog $::env(RESULTS_DIR)/6_final.v \
  -remove_cells [find_physical_only_masters]

if {
  [env_var_exists_and_non_empty RCX_RULES]
  && !$::env(SKIP_DETAILED_ROUTE)
} {
  define_process_corner -ext_model_index 0 X
  set_extraction_rules_file $::env(RCX_RULES)
  extract_parasitics

  write_spef $::env(RESULTS_DIR)/6_final.spef
  file delete $::env(DESIGN_NAME).totCap
  read_spef $::env(RESULTS_DIR)/6_final.spef

  if { [env_var_exists_and_non_empty PWR_NETS_VOLTAGES] } {
    dict for {pwrNetName pwrNetVoltage} $::env(PWR_NETS_VOLTAGES) {
      set_pdnsim_net_voltage -net ${pwrNetName} -voltage ${pwrNetVoltage}
      analyze_power_grid -net ${pwrNetName} \
        -error_file $::env(REPORTS_DIR)/${pwrNetName}.rpt
    }
  } else {
    puts "IR drop analysis for power nets is skipped because PWR_NETS_VOLTAGES is undefined"
  }
  if { [env_var_exists_and_non_empty GND_NETS_VOLTAGES] } {
    dict for {gndNetName gndNetVoltage} $::env(GND_NETS_VOLTAGES) {
      set_pdnsim_net_voltage -net ${gndNetName} -voltage ${gndNetVoltage}
      analyze_power_grid -net ${gndNetName} \
        -error_file $::env(REPORTS_DIR)/${gndNetName}.rpt
    }
  } else {
    puts "IR drop analysis for ground nets is skipped because GND_NETS_VOLTAGES is undefined"
  }
} else {
  puts "OpenRCX is not enabled for this platform."
  puts "Falling back to global route-based estimates."
  log_cmd estimate_parasitics -global_routing
}

report_cell_usage
report_metrics 6 "finish"

source_step_tcl POST FINAL_REPORT

if { [ord::openroad_gui_compiled] } {
  gui::show "source $::env(SCRIPTS_DIR)/save_images.tcl" false
  gui::show "source /work/scripts/asic/orfs/save_cpu_architecture.tcl" false
}
