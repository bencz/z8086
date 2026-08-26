# Architectural placement seed shared by the logic-only and 1 MiB variants.
#
# The regions are deliberately guides, not fences: registers and a bounded
# local logic neighbourhood receive deterministic initial coordinates, then
# timing-driven global placement may move individual cells across boundaries.
# This exposes the 8086 structure without sacrificing a faster placement.

proc z8086_cpu_in_scope {name prefix} {
  if {$prefix == ""} {
    return 1
  }
  if {[string match "${prefix}*" $name]} {
    return 1
  }
  # The external-chip synthesis keeps architectural register names and the
  # ROM hierarchy, but necessarily gives many flattened CPU gates generic
  # names. In that top only, allow the connectivity walk to recover those
  # cells instead of misclassifying them as package glue.
  return [expr {
    [info exists ::physical_include_unscoped_cpu_cells] &&
    $::physical_include_unscoped_cpu_cells
  }]
}

proc z8086_cpu_local_name {name prefix} {
  if {$prefix != ""} {
    set name [string range $name [string length $prefix] end]
  }
  # OpenDB retains backslashes used to quote brackets in identifiers.
  return [string map [list "\\" ""] $name]
}

proc z8086_cpu_classify_anchor {name prefix} {
  set local_name [z8086_cpu_local_name $name $prefix]
  if {[regexp {^microcode_rom_i[./]} $local_name]} {
    return cpu_microcode
  }
  if {[regexp {^(IP|IR|q_word|q_count|q_rptr|q_wptr|q_hl|q_suspended|loader_)} $local_name]} {
    return cpu_frontend
  }
  if {[regexp {^(uc|AR|CR|M\[|N\[|X\[|SR|CNT|nmi_|intr_|BPE|BPH|BPL)} $local_name]} {
    return cpu_control
  }
  if {[regexp {^(AX|BX|CX|DX|SP|BP|SI|DI|CS|DS|ES|SS)\[} $local_name]} {
    return cpu_registers
  }
  if {[regexp {^(ALUOPC|F\[|IND|OPR|TMPA|TMPB|TMPC|alu_src)} $local_name]} {
    return cpu_datapath
  }
  if {[regexp {^(addr|dout|bus_|rd(\$|_)|wr(\$|_)|io(\$|_)|word(\$|_)|inta(\$|_)|writes_memory)} $local_name]} {
    return cpu_bus
  }
  return ""
}

# Pull only bounded, low-fanout combinational neighbourhoods toward their
# architectural registers. Sequential anchors belonging to another block are
# already claimed before this walk and therefore cannot be stolen.
proc z8086_cpu_add_neighbourhood {cluster anchors prefix max_depth} {
  set frontier $anchors
  set visited [dict create]
  set added 0
  for {set depth 0} {$depth < $max_depth} {incr depth} {
    set next_frontier {}
    foreach inst $frontier {
      set inst_name [$inst getName]
      if {[dict exists $visited $inst_name]} {
        continue
      }
      dict set visited $inst_name 1
      foreach term [$inst getITerms] {
        set net [$term getNet]
        if {$net == "NULL" || [$net getSigType] != "SIGNAL"} {
          continue
        }
        set net_terms [$net getITerms]
        if {[llength $net_terms] > 12} {
          continue
        }
        foreach neighbour_term $net_terms {
          set neighbour [$neighbour_term getInst]
          set neighbour_name [$neighbour getName]
          if {![z8086_cpu_in_scope $neighbour_name $prefix] || [physical_is_macro $neighbour]} {
            continue
          }
          incr added [physical_add_inst $cluster $neighbour]
          if {![physical_is_sequential $neighbour]} {
            lappend next_frontier $neighbour
          }
        }
      }
    }
    set frontier $next_frontier
  }
  return $added
}

proc z8086_seed_cpu_architecture {prefix regions} {
  global physical_block physical_clusters
  set anchors [dict create]
  foreach cluster {cpu_microcode cpu_frontend cpu_control cpu_registers cpu_datapath cpu_bus} {
    dict set anchors $cluster {}
  }

  set scoped_count 0
  foreach inst [$physical_block getInsts] {
    set name [$inst getName]
    if {![z8086_cpu_in_scope $name $prefix] || [physical_is_macro $inst]} {
      continue
    }
    incr scoped_count
    set cluster [z8086_cpu_classify_anchor $name $prefix]
    # The synthesized mask-ROM boundary is combinational. Claim every cell in
    # that preserved hierarchy directly; the other blocks continue to use
    # sequential architectural anchors followed by bounded cone growth.
    if {$cluster == "cpu_microcode"} {
      physical_add_inst $cluster $inst
    } elseif {$cluster != "" && [physical_is_sequential $inst]} {
      physical_add_inst $cluster $inst
      dict lappend anchors $cluster $inst
    }
  }

  # Claim every named register bank first, then grow deliberately bounded
  # cones.  Arithmetic anchors get first choice of their nearby mux/carry
  # logic; shallow walks prevent the decoder from swallowing most of the
  # flattened design merely because it has very high architectural reach.
  set neighbourhood_depth [dict create \
    cpu_datapath 2 \
    cpu_registers 2 \
    cpu_bus 2 \
    cpu_control 2 \
    cpu_frontend 2]
  foreach cluster {
    cpu_datapath cpu_registers cpu_bus cpu_control cpu_frontend
  } {
    set anchor_count [llength [dict get $anchors $cluster]]
    set added [z8086_cpu_add_neighbourhood $cluster \
      [dict get $anchors $cluster] $prefix \
      [dict get $neighbourhood_depth $cluster]]
    puts [format {CPU cluster audit %-16s anchors=%4d cone_cells=%4d depth=%d} \
      $cluster $anchor_count $added [dict get $neighbourhood_depth $cluster]]
  }

  # Generic decoded logic that cannot be attributed unambiguously occupies a
  # central exchange area. It remains movable during global placement.
  foreach inst [$physical_block getInsts] {
    set name [$inst getName]
    if {[z8086_cpu_in_scope $name $prefix] && ![physical_is_macro $inst]} {
      physical_add_inst cpu_shared $inst
    }
  }

  foreach cluster {cpu_microcode cpu_frontend cpu_control cpu_registers cpu_datapath cpu_bus cpu_shared} {
    if {![dict exists $physical_clusters $cluster]} {
      error "architectural placement cluster $cluster is empty"
    }
    physical_seed_cluster $cluster [dict get $regions $cluster]
  }

  set summary {}
  foreach cluster {cpu_microcode cpu_frontend cpu_control cpu_registers cpu_datapath cpu_bus cpu_shared} {
    lappend summary "$cluster=[llength [dict get $physical_clusters $cluster]]"
  }
  puts "CPU architectural seed: scoped=$scoped_count [join $summary {, }]"
}
