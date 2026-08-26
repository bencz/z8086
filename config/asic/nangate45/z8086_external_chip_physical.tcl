# Central timing island plus a physical-only IO/ESD envelope.

set ::chip_block [ord::get_db_block]
set ::chip_dbu [$::chip_block getDbUnitsPerMicron]

proc chip_find_master {master_name} {
  set database [ord::get_db]
  foreach library [$database getLibs] {
    set master [$library findMaster $master_name]
    if {$master != "NULL"} {
      return $master
    }
  }
  error "missing physical placeholder master $master_name"
}

proc chip_place_physical {name master_name x y orient} {
  global chip_block chip_dbu
  set inst [$chip_block findInst $name]
  if {$inst == "NULL"} {
    set inst [odb::dbInst_create $chip_block [chip_find_master $master_name] $name]
  }
  $inst setOrient $orient
  $inst setLocation [expr {round($x * $chip_dbu)}] [expr {round($y * $chip_dbu)}]
  $inst setPlacementStatus LOCKED
}

if {[$::chip_block findInst PAD_S_00] == "NULL"} {
  # Twelve pad envelopes per edge.  Names encode physical position, while the
  # logical ports remain process-neutral routing terminals.
  for {set index 0} {$index < 12} {incr index} {
    set offset [expr {100.0 + 68.0 * $index}]
    chip_place_physical [format {PAD_S_%02d} $index] Z8086_PAD_PLACEHOLDER $offset 18.0 R0
    chip_place_physical [format {PAD_N_%02d} $index] Z8086_PAD_PLACEHOLDER $offset 902.0 R180
    chip_place_physical [format {PAD_W_%02d} $index] Z8086_PAD_PLACEHOLDER 18.0 $offset R270
    chip_place_physical [format {PAD_E_%02d} $index] Z8086_PAD_PLACEHOLDER 902.0 $offset R90
  }

  chip_place_physical CORNER_SW Z8086_CORNER_PLACEHOLDER 10.0 10.0 R0
  chip_place_physical CORNER_SE Z8086_CORNER_PLACEHOLDER 900.0 10.0 R90
  chip_place_physical CORNER_NE Z8086_CORNER_PLACEHOLDER 900.0 900.0 R180
  chip_place_physical CORNER_NW Z8086_CORNER_PLACEHOLDER 10.0 900.0 R270
}

# Reuse the architectural classifier inside the central island.  The ROM cells
# remain a separate preserved hierarchy and receive a compact control-side seed.
set ::physical_block $::chip_block
set ::physical_dbu $::chip_dbu
set ::physical_assigned [dict create]
set ::physical_clusters [dict create]
# The pin-independent pass creates architectural guides.  When the hook is
# sourced again for the IO-aware pass, retain those guides through both global
# placements: they are the real physical partition contract, not disposable
# drawing boxes.  A POST_GLOBAL_PLACE hook releases the constraints before
# resizer-created buffers and detailed legalization are introduced.
set ::physical_materialize_guides [expr {
  [$::physical_block findRegion cpu_microcode_guide] == "NULL"
}]

proc physical_is_macro {inst} {
  set master_type [[$inst getMaster] getType]
  set placement_status [$inst getPlacementStatus]
  # Only ordinary CORE logic may be used as an architectural seed.  Tapcells,
  # endcaps, spacers, physical pads and macros have process-defined placement
  # and must never be moved by this script.
  return [expr {$master_type != "CORE" || $placement_status == "LOCKED"}]
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
  global physical_block physical_clusters physical_dbu physical_materialize_guides
  if {!$physical_materialize_guides} {
    return
  }
  set names [dict get $physical_clusters $cluster]
  set count [llength $names]
  lassign [lindex $rectangles 0] xlo ylo xhi yhi
  set columns [expr {int(ceil(sqrt($count * ($xhi - $xlo) / ($yhi - $ylo))))}]
  set rows [expr {int(ceil(double($count) / $columns))}]
  for {set index 0} {$index < $count} {incr index} {
    set inst [$physical_block findInst [lindex $names $index]]
    set x [expr {round(($xlo + (($index % $columns) + 0.5) * ($xhi - $xlo) / $columns) * $physical_dbu)}]
    set y [expr {round(($ylo + (($index / $columns) + 0.5) * ($yhi - $ylo) / $rows) * $physical_dbu)}]
    $inst setLocation $x $y
    $inst setPlacementStatus PLACED
  }
}

proc physical_create_guide {cluster rectangles} {
  global physical_block physical_clusters physical_dbu physical_materialize_guides
  set region_name [format {%s_guide} $cluster]
  set existing_region [$physical_block findRegion $region_name]
  if {$existing_region != "NULL"} {
    return
  }
  if {!$physical_materialize_guides} {
    error "physical guide $cluster was not present in the intermediate database"
  }

  set cell_area 0.0
  foreach name [dict get $physical_clusters $cluster] {
    set inst [$physical_block findInst $name]
    set master [$inst getMaster]
    set cell_area [expr {
      $cell_area + double([$master getWidth]) * [$master getHeight] /
      ($physical_dbu * $physical_dbu)
    }]
  }
  set region_area 0.0
  foreach rectangle $rectangles {
    lassign $rectangle xlo ylo xhi yhi
    set region_area [expr {$region_area + ($xhi - $xlo) * ($yhi - $ylo)}]
  }
  set utilization [expr {$cell_area / $region_area}]
  if {$utilization > 0.60} {
    error [format {physical guide %s is over capacity: %.1f%%} \
      $cluster [expr {100.0 * $utilization}]]
  }
  puts [format {Physical guide %-16s cells=%4d area=%8.2f um2 capacity=%8.2f um2 utilization=%5.1f%%} \
    $cluster [llength [dict get $physical_clusters $cluster]] $cell_area \
    $region_area [expr {100.0 * $utilization}]]

  set region [odb::dbRegion_create $physical_block $region_name]
  odb::dbRegion_setRegionType $region SUGGESTED
  foreach rectangle $rectangles {
    lassign $rectangle xlo ylo xhi yhi
    odb::dbBox_create $region \
      [expr {round($xlo * $physical_dbu)}] \
      [expr {round($ylo * $physical_dbu)}] \
      [expr {round($xhi * $physical_dbu)}] \
      [expr {round($yhi * $physical_dbu)}]
  }

  set group [odb::dbGroup_create $region [format {%s_group} $cluster]]
  foreach name [dict get $physical_clusters $cluster] {
    set inst [$physical_block findInst $name]
    if {$inst == "NULL"} {
      error "physical guide $cluster could not find $name"
    }
    odb::dbGroup_addInst $group $inst
  }
}

proc physical_compose_cluster {target sources} {
  global physical_clusters
  set members {}
  foreach source $sources {
    foreach name [dict get $physical_clusters $source] {
      lappend members $name
    }
  }
  if {[llength $members] == 0} {
    error "composed physical cluster $target is empty"
  }
  dict set physical_clusters $target $members
}

source /work/config/asic/nangate45/z8086_cpu_architecture.tcl
set ::physical_include_unscoped_cpu_cells 1
set chip_cpu_regions [dict create \
  cpu_microcode {{365.0 500.0 435.0 625.0}} \
  cpu_frontend  {{445.0 500.0 500.0 625.0}} \
  cpu_control   {{510.0 500.0 555.0 625.0}} \
  cpu_registers {{365.0 375.0 440.0 490.0}} \
  cpu_datapath  {{525.0 375.0 635.0 490.0}} \
  cpu_bus       {{565.0 500.0 635.0 625.0}} \
  cpu_shared    {{450.0 375.0 515.0 490.0}}]
z8086_seed_cpu_architecture "cpu." $chip_cpu_regions
unset ::physical_include_unscoped_cpu_cells

# Use six non-overlapping OpenDB GUIDE regions throughout global placement.
# Shared/exchange logic is still seeded into its central rectangle, but remains
# the ungrouped population needed by RePlAce's base-density domain and may move
# locally across functional boundaries.
set chip_cpu_guides [dict create \
  cpu_microcode {{365.0 500.0 435.0 625.0}} \
  cpu_frontend  {{445.0 500.0 500.0 625.0}} \
  cpu_control   {{510.0 500.0 555.0 625.0}} \
  cpu_bus       {{565.0 500.0 635.0 625.0}} \
  cpu_registers {{365.0 375.0 440.0 490.0}} \
  cpu_shared    {{450.0 375.0 515.0 490.0}} \
  cpu_datapath  {{525.0 375.0 635.0 490.0}}]
foreach cluster {
  cpu_microcode cpu_frontend cpu_control cpu_bus cpu_registers cpu_datapath
} {
  physical_create_guide $cluster [dict get $chip_cpu_guides $cluster]
}
puts "CPU architectural placement: ROM=[llength [dict get $::physical_clusters cpu_microcode]], fetch/decode=[llength [dict get $::physical_clusters cpu_frontend]], control=[llength [dict get $::physical_clusters cpu_control]], registers=[llength [dict get $::physical_clusters cpu_registers]], ALU/datapath=[llength [dict get $::physical_clusters cpu_datapath]], BIU=[llength [dict get $::physical_clusters cpu_bus]], shared=[llength [dict get $::physical_clusters cpu_shared]], guides_active=1"
