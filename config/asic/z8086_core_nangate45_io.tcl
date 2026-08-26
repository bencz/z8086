# Ordered routing-pin banks for the logic-only core. These are abstract metal
# terminals; package pads/ESD cells will be a separate foundry-specific ring.

proc z8086_core_indexed_pins {base width} {
  set pins {}
  for {set bit 0} {$bit < $width} {incr bit} {
    lappend pins [format {%s[%d]} $base $bit]
  }
  return $pins
}

proc z8086_core_pin_bank {edge begin end pins} {
  set count [llength $pins]
  if {$count == 0} {
    return
  }
  set pitch [expr {double($end - $begin) / $count}]
  for {set index 0} {$index < $count} {incr index} {
    set lo [expr {$begin + ($index + 0.20) * $pitch}]
    set hi [expr {$begin + ($index + 0.80) * $pitch}]
    set_io_pin_constraint -pin_names [list [lindex $pins $index]] \
      -region [format {%s:%.3f-%.3f} $edge $lo $hi]
  }
}

# Input data gets its own edge. Output address, data, and bus strobes are
# separated into ordered banks instead of competing for one right-edge slot.
z8086_core_pin_bank left 25 195 [z8086_core_indexed_pins din 16]
z8086_core_pin_bank right 22 96 [z8086_core_indexed_pins addr 20]
z8086_core_pin_bank right 103 166 [z8086_core_indexed_pins dout 16]
z8086_core_pin_bank right 174 198 {rd wr io word inta}
z8086_core_pin_bank top 82 138 {clk reset_n}
z8086_core_pin_bank bottom 70 150 {intr nmi ready}
