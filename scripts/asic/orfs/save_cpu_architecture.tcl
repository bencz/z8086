# Render the signed-off CPU island with the same connectivity-derived
# architectural classification used to seed physical placement.  The helper
# below deliberately does not move cells: it only rebuilds membership lists
# and assigns GUI highlight groups to their final routed coordinates.

set ::physical_block [ord::get_db_block]
set ::physical_clusters [dict create]
set ::physical_assigned [dict create]

proc physical_is_macro {inst} {
  set master_type [[$inst getMaster] getType]
  set master_name [[$inst getMaster] getName]
  set placement_status [$inst getPlacementStatus]
  # Density fill has no architectural meaning and would otherwise dominate
  # the top-level core, where there is no cpu.* hierarchy to scope the walk.
  return [expr {$master_type == "BLOCK" || $placement_status == "LOCKED"
    || [regexp {^(FILL|DECAP)} $master_name]}]
}

proc physical_is_sequential {inst} {
  return [regexp {(^|_)(S?DFF|LATCH)} [[$inst getMaster] getName]]
}

proc physical_add_inst {cluster inst} {
  global physical_assigned physical_clusters
  set name [$inst getName]
  if {[physical_is_macro $inst] || [dict exists $physical_assigned $name]} {
    return 0
  }
  dict lappend physical_clusters $cluster $name
  dict set physical_assigned $name 1
  return 1
}

proc physical_seed_cluster {cluster rectangles} {
  # Rendering must never alter the signed-off placement.
}

source /work/config/asic/nangate45/z8086_cpu_architecture.tcl
set empty_regions [dict create \
  cpu_microcode {} cpu_frontend {} cpu_control {} cpu_registers {} cpu_datapath {} \
  cpu_bus {} cpu_shared {}]

# The SoC instantiates the processor as cpu.*, while the logic-only ASIC uses
# z8086 itself as the top level.  Discover that hierarchy here so this report
# always describes the same CPU architecture in both physical variants.
set cpu_prefix ""
foreach inst [$::physical_block getInsts] {
  if {[string match "cpu.*" [$inst getName]]} {
    set cpu_prefix "cpu."
    break
  }
}
if {$cpu_prefix eq "cpu." && $::env(DESIGN_NAME) eq "z8086_external_chip_core"} {
  # Synthesis flattens most CPU logic into generated top-level names. Include
  # those cells in the same connectivity walk used by physical placement so
  # the final colour map describes the entire island, not only preserved
  # hierarchical names.
  set ::physical_include_unscoped_cpu_cells 1
  z8086_seed_cpu_architecture $cpu_prefix $empty_regions
  unset ::physical_include_unscoped_cpu_cells
} else {
  z8086_seed_cpu_architecture $cpu_prefix $empty_regions
}

set count_file [open "$::env(REPORTS_DIR)/final_cpu_architecture_counts.txt" w]
puts $count_file "microcode_rom [llength [dict get $::physical_clusters cpu_microcode]]"
puts $count_file "decode_control [expr {
  [llength [dict get $::physical_clusters cpu_frontend]] +
  [llength [dict get $::physical_clusters cpu_control]]}]"
puts $count_file "register_bank [llength [dict get $::physical_clusters cpu_registers]]"
puts $count_file "alu_datapath [llength [dict get $::physical_clusters cpu_datapath]]"
puts $count_file "biu_shared [expr {
  [llength [dict get $::physical_clusters cpu_bus]] +
  [llength [dict get $::physical_clusters cpu_shared]]}]"
close $count_file

gui::save_display_controls
gui::clear_highlights -1
gui::clear_selections
gui::set_display_controls "*" visible false
gui::set_display_controls "Instances/*" visible true
gui::set_display_controls "Instances/Physical/*" visible false
gui::set_display_controls "Misc/Instances/Pins" visible true
gui::set_display_controls "Misc/Highlight selected" visible true
gui::set_display_controls "Misc/Detailed view" visible true

# Highlight groups: 0 green, 1 yellow, 2 cyan, 3 magenta, 4 red and
# 5 dark green. Shared exchange logic remains neutral gray/white so it cannot
# be confused with the magenta datapath.
foreach name [dict get $::physical_clusters cpu_microcode] {
  gui::highlight_inst $name 2
}
foreach name [dict get $::physical_clusters cpu_frontend] {
  gui::highlight_inst $name 0
}
foreach name [dict get $::physical_clusters cpu_control] {
  gui::highlight_inst $name 5
}
foreach name [dict get $::physical_clusters cpu_registers] {
  gui::highlight_inst $name 1
}
foreach name [dict get $::physical_clusters cpu_datapath] {
  gui::highlight_inst $name 3
}
foreach name [dict get $::physical_clusters cpu_bus] {
  gui::highlight_inst $name 4
}

if {$cpu_prefix eq "cpu." && $::env(DESIGN_NAME) eq "z8086_external_chip_core"} {
  # The pad-frame experiment places its complete standard-cell island in the
  # middle of a 1 mm die.  Do not reuse the much larger SRAM-chip coordinates.
  set architecture_area {350 350 650 650}
} elseif {$cpu_prefix eq "cpu."} {
  # Include the small amount of intentional BIU spill toward the external IO
  # while keeping enough context to show the four central partitions.
  set architecture_area {1450 1160 2010 1540}
} else {
  # Logic-only die: the CPU occupies nearly the complete 220 x 220 um die.
  set architecture_area {0 0 220 220}
}
save_image -area $architecture_area -width 1600 \
  $::env(REPORTS_DIR)/final_cpu_architecture.webp

gui::clear_highlights -1
gui::clear_selections
gui::restore_display_controls
