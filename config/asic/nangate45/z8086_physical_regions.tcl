# Connectivity-derived placement seed for the 1 MiB SRAM chip.
#
# Yosys is intentionally free to optimize and flatten logic.  Instead of
# depending on fragile generated cell names, each SRAM tile is discovered from
# the nets attached to its four hard macros.  The local request registers and
# registered read-mux cone are seeded per tile.  CPU and central SRAM logic get
# their own initial locations.  There are no dbRegion/dbGroup fences and no
# placement_cluster pseudo-macros: after this deterministic seed, timing-driven
# placement is free to refine every individual standard cell.  The temporary
# Architectural guides shape the pin-independent global-placement pass, then
# are released for IO-aware timing/electrical optimization and legalization.

set ::physical_block [ord::get_db_block]
set ::physical_dbu [$::physical_block getDbUnitsPerMicron]
set ::physical_assigned [dict create]
set ::physical_clusters [dict create]
# The first invocation creates temporary guides for the pin-independent global
# placement.  The second invocation loads that placement from OpenDB and keeps
# the resulting coordinates but releases every guide before the IO-aware pass.
set ::physical_materialize_guides [expr {
  [$::physical_block findRegion sram_tile_00_guide] == "NULL"
}]

proc physical_is_macro {inst} {
  set master_type [[$inst getMaster] getType]
  set placement_status [$inst getPlacementStatus]
  return [expr {$master_type == "BLOCK" || $placement_status == "LOCKED"}]
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
  if {![dict exists $physical_clusters $cluster]} {
    error "physical cluster $cluster is empty"
  }
  if {!$physical_materialize_guides} {
    return
  }
  set instance_names [dict get $physical_clusters $cluster]
  set instance_count [llength $instance_names]

  set total_area 0.0
  foreach rectangle $rectangles {
    lassign $rectangle xlo ylo xhi yhi
    set total_area [expr {$total_area + ($xhi - $xlo) * ($yhi - $ylo)}]
  }
  if {$total_area <= 0.0} {
    error "physical cluster $cluster has no seed area"
  }

  set instance_index 0
  set rectangle_index 0
  set rectangle_count [llength $rectangles]
  foreach rectangle $rectangles {
    incr rectangle_index
    lassign $rectangle xlo ylo xhi yhi
    set width [expr {$xhi - $xlo}]
    set height [expr {$yhi - $ylo}]
    if {$rectangle_index == $rectangle_count} {
      set count [expr {$instance_count - $instance_index}]
    } else {
      set area [expr {$width * $height}]
      set count [expr {round($instance_count * $area / $total_area)}]
    }
    if {$count <= 0} {
      continue
    }

    set columns [expr {int(ceil(sqrt($count * $width / $height)))}]
    set rows [expr {int(ceil(double($count) / $columns))}]
    for {set local_index 0} {$local_index < $count} {incr local_index} {
      set name [lindex $instance_names $instance_index]
      incr instance_index
      set inst [$physical_block findInst $name]
      if {$inst == "NULL"} {
        error "physical seed could not find $name"
      }
      set column [expr {$local_index % $columns}]
      set row [expr {$local_index / $columns}]
      set x [expr {round(($xlo + ($column + 0.5) * $width / $columns) * $physical_dbu)}]
      set y [expr {round(($ylo + ($row + 0.5) * $height / $rows) * $physical_dbu)}]
      $inst setLocation $x $y
      $inst setPlacementStatus PLACED
    }
  }
  if {$instance_index != $instance_count} {
    error "physical cluster $cluster seeded $instance_index of $instance_count cells"
  }
}

# Materialize a placement guide in OpenDB. SUGGESTED regions are exported as
# DEF GUIDE constraints: global placement tries to keep the group inside its
# boxes but may cross a boundary to resolve timing or congestion.  When this
# hook is sourced for the second pass, release the guide while preserving the
# placed coordinates. Destroying each owning dbGroup before its region is
# required by OpenDB; reversing that order leaves a dangling group.
proc physical_create_guide {cluster rectangles {keep_for_io_pass 0}} {
  global physical_block physical_clusters physical_dbu physical_materialize_guides
  set region_name [format {%s_guide} $cluster]
  set region [$physical_block findRegion $region_name]
  if {$region != "NULL"} {
    if {$keep_for_io_pass} {
      return
    }
    foreach group [$region getGroups] {
      odb::dbGroup_destroy $group
    }
    odb::dbRegion_destroy $region
    return
  }
  if {!$physical_materialize_guides} {
    error "physical guide $cluster was not present in the intermediate database"
  }

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

proc physical_is_sequential {inst} {
  set master_name [[$inst getMaster] getName]
  return [regexp {(^|_)(S?DFF|LATCH)} $master_name]
}

proc physical_add_small_net_neighbors {cluster net} {
  if {$net == "NULL" || [$net getSigType] != "SIGNAL"} {
    return 0
  }
  set terms [$net getITerms]
  if {[llength $terms] > 8} {
    return 0
  }
  set count 0
  foreach term $terms {
    incr count [physical_add_inst $cluster [$term getInst]]
  }
  return $count
}

# Walk a few gates forward from each macro read pin so the complete local
# four-to-one read cone, including its capture register, follows the tile.
proc physical_add_read_cone {cluster initial_net} {
  set frontier [list $initial_net]
  set visited [dict create]
  set count 0
  for {set depth 0} {$depth < 5} {incr depth} {
    set next_frontier {}
    foreach net $frontier {
      if {$net == "NULL" || [dict exists $visited $net]} {
        continue
      }
      dict set visited $net 1
      if {[$net getSigType] != "SIGNAL" || [llength [$net getITerms]] > 8} {
        continue
      }
      foreach term [$net getITerms] {
        set inst [$term getInst]
        if {[physical_is_macro $inst]} {
          continue
        }
        incr count [physical_add_inst $cluster $inst]
        if {![physical_is_sequential $inst]} {
          foreach output_term [$inst getITerms] {
            if {[$output_term getIoType] == "OUTPUT"} {
              lappend next_frontier [$output_term getNet]
            }
          }
        }
      }
    }
    set frontier $next_frontier
  }
  return $count
}

set physical_macro_count 0
set physical_tile_logic_count 0
for {set tile 0} {$tile < 64} {incr tile} {
  set row [expr {$tile / 4}]
  set tile_column [expr {$tile % 4}]
  set tile_cluster [format {sram_tile_%02d} $tile]
  if {$row < 8} {
    set macro_y [expr {40.075 + $row * 128.10}]
  } else {
    set macro_y [expr {1590.015 + ($row - 8) * 128.10}]
  }
  set tile_x [lindex {40 728 1904 2592} $tile_column]

  set tile_local_count 0
  for {set local_column 0} {$local_column < 4} {incr local_column} {
    set bank [expr {$row * 16 + $tile_column * 4 + $local_column}]
    set macro_name [format {ram.memory_bank\[%d\].mem} $bank]
    set macro [$::physical_block findInst $macro_name]
    if {$macro == "NULL"} {
      error "physical grouping could not find $macro_name"
    }
    incr physical_macro_count

    foreach term [$macro getITerms] {
      set net [$term getNet]
      if {[$term getIoType] == "OUTPUT"} {
        incr tile_local_count [physical_add_read_cone $tile_cluster $net]
      } elseif {[$term getIoType] == "INPUT"} {
        incr tile_local_count [physical_add_small_net_neighbors $tile_cluster $net]
      }
    }
  }
  set tile_rectangles [list \
    [list [expr {$tile_x + 4.0}] [expr {$macro_y + 112.0}] \
          [expr {$tile_x + 664.0}] [expr {$macro_y + 124.0}]]]
  physical_seed_cluster $tile_cluster $tile_rectangles
  physical_create_guide $tile_cluster $tile_rectangles
  incr physical_tile_logic_count $tile_local_count
}

if {$physical_macro_count != 256} {
  error "physical grouping found $physical_macro_count SRAM macros, expected 256"
}
if {$physical_tile_logic_count < 4096} {
  error "physical grouping found only $physical_tile_logic_count tile-local cells"
}

# Classify the CPU into architectural cones, then compose four non-overlapping
# physical partitions.  Four moderately sized regions are substantially more
# stable in RePlAce than many tiny regions, while still exposing the classical
# 8086 organization: frontend/control, register bank, ALU/datapath, and BIU.
# The pin-independent pass uses these regions.  They are released before the
# IO-aware incremental pass, which preserves their converged coordinates while
# accommodating the newly placed pins and port buffers.
source /work/config/asic/nangate45/z8086_cpu_architecture.tcl
set physical_cpu_regions [dict create \
  cpu_microcode {{1500.0 1360.0 1600.0 1510.0}} \
  cpu_frontend  {{1610.0 1360.0 1645.0 1510.0}} \
  cpu_control   {{1655.0 1360.0 1720.0 1510.0}} \
  cpu_registers {{1500.0 1190.0 1645.0 1340.0}} \
  cpu_datapath  {{1655.0 1190.0 1810.0 1340.0}} \
  cpu_bus       {{1730.0 1360.0 1810.0 1510.0}} \
  cpu_shared    {{1580.0 1300.0 1730.0 1400.0}}]
z8086_seed_cpu_architecture "cpu." $physical_cpu_regions

proc physical_inst_touches_port {inst} {
  foreach term [$inst getITerms] {
    if {[$term getIoType] != "OUTPUT"} {
      continue
    }
    set net [$term getNet]
    if {$net != "NULL" && [llength [$net getBTerms]] != 0} {
      return 1
    }
  }
  return 0
}

proc physical_compose_cpu_partition {partition source_clusters} {
  global physical_clusters
  set members {}
  foreach source_cluster $source_clusters {
    foreach name [dict get $physical_clusters $source_cluster] {
      set inst [$::physical_block findInst $name]
      if {$inst == "NULL"} {
        error "CPU partition $partition could not find $name"
      }
      # A register directly terminating at a die pin belongs beside that pin;
      # forcing it into the central island would manufacture a long IO path.
      if {![physical_inst_touches_port $inst]} {
        lappend members $name
      }
    }
  }
  if {[llength $members] == 0} {
    error "CPU partition $partition is empty"
  }
  dict set physical_clusters $partition $members
}

physical_compose_cpu_partition cpu_decode_partition {cpu_microcode cpu_frontend cpu_control}
physical_compose_cpu_partition cpu_register_partition {cpu_registers}
physical_compose_cpu_partition cpu_alu_partition {cpu_datapath}
physical_compose_cpu_partition cpu_biu_partition {cpu_bus cpu_shared}

set physical_cpu_partitions [dict create \
  cpu_decode_partition   {{1550.0 1370.0 1640.0 1460.0}} \
  cpu_register_partition {{1550.0 1260.0 1650.0 1350.0}} \
  cpu_alu_partition      {{1660.0 1260.0 1740.0 1350.0}} \
  cpu_biu_partition      {{1660.0 1370.0 1740.0 1460.0}}]
foreach cluster {
  cpu_decode_partition cpu_register_partition cpu_alu_partition
  cpu_biu_partition
} {
  physical_create_guide $cluster [dict get $physical_cpu_partitions $cluster]
}
puts "CPU physical partitions: decode/control=[llength [dict get $::physical_clusters cpu_decode_partition]], registers=[llength [dict get $::physical_clusters cpu_register_partition]], ALU/datapath=[llength [dict get $::physical_clusters cpu_alu_partition]], BIU/shared=[llength [dict get $::physical_clusters cpu_biu_partition]]"

# The remaining SRAM controller and row-reduction registers form a second
# central cluster around the CPU.
set physical_ram_central_count 0
foreach inst [$::physical_block getInsts] {
  set name [$inst getName]
  if {[string match {ram.*} $name] && ![physical_is_macro $inst]} {
    incr physical_ram_central_count [physical_add_inst ram_central $inst]
  }
}
set physical_ram_central_regions {
  {1408.0 1060.0 1490.0 1570.0}
  {1810.0 1060.0 1892.0 1570.0}
  {1490.0 1060.0 1810.0 1180.0}
  {1490.0 1520.0 1810.0 1570.0}
}
physical_seed_cluster ram_central $physical_ram_central_regions
physical_create_guide ram_central $physical_ram_central_regions

puts "Physical placement seed: 256 SRAM macros, $physical_tile_logic_count tile-local cells, $physical_ram_central_count central RAM cells"
