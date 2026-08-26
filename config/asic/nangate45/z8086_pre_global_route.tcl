# Multi-output Nangate45 cells expose complementary or carry/sum outputs even
# when synthesis uses only one of them.  The unused output is represented in
# ODB as a one-pin net; it has no load and must not consume routing resources.
# Remove only proven output-only nets.  An undriven input-only net is a design
# error and is deliberately left in place so the strict log check catches it.
set unused_output_nets {}

foreach net [get_nets -hierarchical *] {
  set pins [get_pins -quiet -of_objects $net]
  set ports [get_ports -quiet -of_objects $net]

  if {[llength $pins] == 1 && [llength $ports] == 0} {
    set pin [lindex $pins 0]
    if {[get_property $pin direction] eq "output"} {
      lappend unused_output_nets $net
    }
  }
}

foreach net $unused_output_nets {
  delete_net $net
}

puts "Removed [llength $unused_output_nets] unused output-only nets before global routing."
