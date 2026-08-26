# OpenROAD's RSZ-3310 repair-design guard is hard-coded at max(5000, 5% of
# the driver count).  Four SRAM write-mask trees have 2050 loads each and the
# remaining address/data trees have about 258 loads each.  Repair those real
# extreme-fanout signal nets individually before the whole-design pass.  The
# same electrical checks and buffer-tree implementation are used; only the
# work is partitioned so no valid repair is abandoned at the safety ceiling.
set block [ord::get_db_block]
set extreme_fanout_nets {}
foreach db_net [$block getNets] {
  set load_count \
    [expr {[llength [$db_net getITerms]] + [llength [$db_net getBTerms]]}]
  if {[$db_net getSigType] eq "SIGNAL" && $load_count >= 200} {
    lappend extreme_fanout_nets [$db_net getName]
  }
}

puts "Selective electrical pre-repair: [llength $extreme_fanout_nets] extreme-fanout nets"
estimate_parasitics -placement
set repaired_extreme_fanout_nets 0
foreach net_name $extreme_fanout_nets {
  set sta_net [get_nets -quiet $net_name]
  if {[llength $sta_net] == 1} {
    rsz::repair_net_cmd [lindex $sta_net 0] 0.0 0.0 0.0
    incr repaired_extreme_fanout_nets
  }
}
if {$repaired_extreme_fanout_nets != [llength $extreme_fanout_nets]} {
  utl::error FLW 99 "Failed to resolve every extreme-fanout net for selective repair."
}
puts "Selective electrical pre-repair completed: $repaired_extreme_fanout_nets nets"

foreach margin {0 15 30} {
  puts "Staged SRAM electrical/length repair: slew/capacitance margin ${margin}%"
  estimate_parasitics -placement
  repair_design -verbose -slew_margin $margin -cap_margin $margin
}
