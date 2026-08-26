add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDPE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDCE$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSSE$}
global_connect

set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

# Logic-only PDN for the external-memory variant. Keeping this separate from
# the SRAM chip avoids creating macro grids when there are no macro instances.
define_pdn_grid -name {logic_grid} -voltage_domains {CORE} -pins {metal7}
add_pdn_stripe -grid {logic_grid} -layer {metal1} -width {0.17} -pitch {2.4} -offset {0} -followpins
add_pdn_stripe -grid {logic_grid} -layer {metal4} -width {0.48} -pitch {56.0} -offset {2}
add_pdn_stripe -grid {logic_grid} -layer {metal7} -width {1.40} -pitch {30.0} -offset {10}
add_pdn_connect -grid {logic_grid} -layers {metal1 metal4} -max_rows 1 -max_columns 1
add_pdn_connect -grid {logic_grid} -layers {metal4 metal7} -max_rows 1 -max_columns 1
