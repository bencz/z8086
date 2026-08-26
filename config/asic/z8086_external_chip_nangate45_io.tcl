proc z8086_chip_indexed_pins {base width} {
  set pins {}
  for {set bit 0} {$bit < $width} {incr bit} {
    lappend pins [format {%s[%d]} $base $bit]
  }
  return $pins
}

proc z8086_chip_pin_bank {edge begin end pins} {
  set count [llength $pins]
  if {$count == 0} {
    return
  }
  set pitch [expr {double($end - $begin) / $count}]
  for {set index 0} {$index < $count} {incr index} {
    set lo [expr {$begin + ($index + 0.25) * $pitch}]
    set hi [expr {$begin + ($index + 0.75) * $pitch}]
    set_io_pin_constraint -pin_names [list [lindex $pins $index]] \
      -region [format {%s:%.3f-%.3f} $edge $lo $hi]
  }
}

# The actual bidirectional AD pads combine these three core-facing banks.
# Keeping I/O/OE separate here is the standard foundry-pad integration model.
z8086_chip_pin_bank left 160 470 [z8086_chip_indexed_pins ad_in 16]
z8086_chip_pin_bank left 530 840 [z8086_chip_indexed_pins ad_out 16]
z8086_chip_pin_bank right 180 360 [z8086_chip_indexed_pins a19_16 4]
z8086_chip_pin_bank right 410 820 \
  {ad_oe bhe_n ale rd_n wr_n m_io inta_n den_n dt_r hlda}
z8086_chip_pin_bank top 380 620 {clk reset_n}
z8086_chip_pin_bank bottom 300 700 {ready intr nmi hold}
