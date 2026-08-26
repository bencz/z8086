# Architectural GUIDE regions have completed their job after the IO-aware
# global placement.  Remove only the six z8086 groups before resize and detail
# placement so newly inserted buffers may be legalized at partition edges.

set release_block [ord::get_db_block]
set released_guides 0
foreach cluster {
  cpu_microcode cpu_frontend cpu_control cpu_bus cpu_registers cpu_datapath
} {
  set region [$release_block findRegion [format {%s_guide} $cluster]]
  if {$region == "NULL"} {
    error "missing architectural guide to release: $cluster"
  }
  foreach group [$region getGroups] {
    odb::dbGroup_destroy $group
  }
  odb::dbRegion_destroy $region
  incr released_guides
}
if {$released_guides != 6} {
  error "released $released_guides architectural guides instead of 6"
}
puts "CPU architectural placement: released 6 global-placement guides before resize/legalization"
