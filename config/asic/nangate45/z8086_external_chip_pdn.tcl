add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
global_connect

set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}
define_pdn_grid -name {chip_core_grid} -voltage_domains {CORE} -pins {metal7}
add_pdn_stripe -grid {chip_core_grid} -layer {metal1} -width {0.17} -pitch {2.4} -offset {0} -followpins
add_pdn_stripe -grid {chip_core_grid} -layer {metal4} -width {0.48} -pitch {56.0} -offset {2}
add_pdn_stripe -grid {chip_core_grid} -layer {metal7} -width {1.40} -pitch {36.0} -offset {12}
add_pdn_connect -grid {chip_core_grid} -layers {metal1 metal4} -max_rows 1 -max_columns 1
add_pdn_connect -grid {chip_core_grid} -layers {metal4 metal7} -max_rows 1 -max_columns 1
