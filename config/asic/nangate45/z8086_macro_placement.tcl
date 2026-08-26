# 256 1024x32 macros form four 8x8 quadrants around a central logic island.
# A bank's upper nibble selects a physical row; its lower nibble selects the
# column captured by the first level of the registered read mux.
#
# Every signal pin is a metal3 rectangle whose first centre is at local
# y=2.835 um and whose pitch is 0.84 um.  Nangate45 metal3 tracks are
# y=0.07+n*0.14 um, so every macro origin must be y=0.035+n*0.14 um.  The
# 128.10 um row pitch preserves that phase for every row.  Do not round these
# values: an off-grid SRAM origin makes detailed routing reject its pins.
proc place_ram_macro {name x y} {
  place_macro -macro_name $name -location [list $x $y] -orientation R0 -exact
}

for {set row 0} {$row < 16} {incr row} {
  if {$row < 8} {
    set y [expr {40.075 + $row * 128.10}]
  } else {
    set y [expr {1590.015 + ($row - 8) * 128.10}]
  }

  for {set column 0} {$column < 16} {incr column} {
    if {$column < 8} {
      set x [expr {40 + $column * 172}]
    } else {
      set x [expr {1904 + ($column - 8) * 172}]
    }
    set bank [expr {$row * 16 + $column}]
    set instance_name [format {ram.memory_bank\[%d\].mem} $bank]
    place_ram_macro $instance_name $x $y
  }
}
