# Keep package interfaces on dedicated edges, but do not let the HPWL
# optimizer collapse an entire bus into a small part of an edge.  Every pin
# gets an ordered sub-window inside its functional bank.  This preserves bus
# order, leaves routing gaps between banks, and remains independent of the
# routing-track pitch used by the platform.

proc z8086_indexed_pins {base width} {
    set pins {}
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend pins [format {%s[%d]} $base $bit]
    }
    return $pins
}

proc z8086_place_pin_bank {edge begin end pins} {
    set pin_count [llength $pins]
    if {$pin_count == 0} {
        return
    }

    set pitch [expr {double($end - $begin) / $pin_count}]
    for {set index 0} {$index < $pin_count} {incr index} {
        # Reserve 20% of each slot on both sides.  Adjacent pins therefore
        # cannot collapse onto consecutive tracks even after HPWL refinement.
        set slot_begin [expr {$begin + ($index + 0.20) * $pitch}]
        set slot_end   [expr {$begin + ($index + 0.80) * $pitch}]
        set region [format {%s:%.3f-%.3f} $edge $slot_begin $slot_end]
        set_io_pin_constraint -pin_names [list [lindex $pins $index]] \
            -region $region
    }
}

# Left edge: boot/debug loader, ordered from bottom to top.
z8086_place_pin_bank left 120 600 \
    [z8086_indexed_pins loader_addr 20]
z8086_place_pin_bank left 720 1280 \
    [z8086_indexed_pins loader_wdata 32]
z8086_place_pin_bank left 1400 1650 \
    [concat [z8086_indexed_pins loader_wstrb 4] \
        {loader_enable loader_req loader_write}]
z8086_place_pin_bank left 1780 2580 \
    [concat [z8086_indexed_pins loader_rdata 32] {loader_ready}]

# Right edge: external I/O bus.  Address, write data, read data, and controls
# use separate banks so bidirectional traffic does not create one hotspot.
z8086_place_pin_bank right 120 800 \
    [z8086_indexed_pins io_addr 20]
z8086_place_pin_bank right 920 1460 \
    [z8086_indexed_pins io_dout 16]
z8086_place_pin_bank right 1580 2120 \
    [z8086_indexed_pins io_din 16]
z8086_place_pin_bank right 2280 2580 \
    {io_rd io_wr io_word io_ready}

# Put global control pins near the central CPU corridor, on quiet edge banks.
z8086_place_pin_bank top 1500 1800 {clk reset_n}
z8086_place_pin_bank bottom 1420 1880 {intr nmi inta}
