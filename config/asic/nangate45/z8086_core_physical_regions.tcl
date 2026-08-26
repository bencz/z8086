# Deterministic architectural seed for the logic-only z8086 core.

set ::physical_block [ord::get_db_block]
set ::physical_dbu [$::physical_block getDbUnitsPerMicron]
set ::physical_assigned [dict create]
set ::physical_clusters [dict create]

proc physical_is_macro {inst} {
  set master_type [[$inst getMaster] getType]
  set placement_status [$inst getPlacementStatus]
  return [expr {$master_type == "BLOCK" || $placement_status == "LOCKED"}]
}

proc physical_is_sequential {inst} {
  set master_name [[$inst getMaster] getName]
  return [regexp {(^|_)(S?DFF|LATCH)} $master_name]
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
  global physical_block physical_clusters physical_dbu
  set instance_names [dict get $physical_clusters $cluster]
  set instance_count [llength $instance_names]
  set total_area 0.0
  foreach rectangle $rectangles {
    lassign $rectangle xlo ylo xhi yhi
    set total_area [expr {$total_area + ($xhi - $xlo) * ($yhi - $ylo)}]
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
      set count [expr {round($instance_count * $width * $height / $total_area)}]
    }
    if {$count <= 0} {
      continue
    }
    set columns [expr {int(ceil(sqrt($count * $width / $height)))}]
    set rows [expr {int(ceil(double($count) / $columns))}]
    for {set local_index 0} {$local_index < $count} {incr local_index} {
      set inst [$physical_block findInst [lindex $instance_names $instance_index]]
      incr instance_index
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

source /work/config/asic/nangate45/z8086_cpu_architecture.tcl

z8086_seed_cpu_architecture "" [dict create \
  cpu_microcode {{25.0 116.0 87.0 195.0}} \
  cpu_frontend  {{88.0 116.0 115.0 195.0}} \
  cpu_control   {{116.0 116.0 150.0 195.0}} \
  cpu_registers {{25.0 25.0 95.0 112.0}} \
  cpu_datapath  {{96.0 25.0 195.0 112.0}} \
  cpu_bus       {{151.0 113.0 195.0 195.0}} \
  cpu_shared    {{72.0 82.0 168.0 145.0}}]
