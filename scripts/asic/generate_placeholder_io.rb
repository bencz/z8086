include RBA

gds_output = $gds_output
lef_output = $lef_output
raise "missing gds_output" unless gds_output && !gds_output.empty?
raise "missing lef_output" unless lef_output && !lef_output.empty?

layout = Layout.new
layout.dbu = 0.001

active = layout.layer(1, 0)
poly = layout.layer(9, 0)
metal1 = layout.layer(11, 0)
metal7 = layout.layer(23, 0)
metal8 = layout.layer(25, 0)
outline = layout.layer(235, 0)

pad = layout.create_cell("Z8086_PAD_PLACEHOLDER")
pad.shapes(outline).insert(Box.new(0, 0, 60_000, 80_000))
pad.shapes(active).insert(Box.new(8_000, 8_000, 52_000, 55_000))
(12_000..48_000).step(4_000) do |x|
  pad.shapes(poly).insert(Box.new(x, 8_000, x + 800, 55_000))
end
pad.shapes(metal1).insert(Box.new(6_000, 6_000, 54_000, 58_000))
pad.shapes(metal7).insert(Box.new(5_000, 57_000, 55_000, 62_000))
pad.shapes(metal8).insert(Box.new(7_000, 60_000, 53_000, 76_000))

corner = layout.create_cell("Z8086_CORNER_PLACEHOLDER")
corner.shapes(outline).insert(Box.new(0, 0, 90_000, 90_000))
corner.shapes(active).insert(Box.new(10_000, 10_000, 80_000, 80_000))
corner.shapes(metal1).insert(Box.new(6_000, 6_000, 84_000, 84_000))
corner.shapes(metal7).insert(Box.new(4_000, 4_000, 86_000, 86_000))
corner.shapes(metal8).insert(Box.new(10_000, 10_000, 80_000, 80_000))

layout.write(gds_output)

lef = <<~LEF
  VERSION 5.8 ;
  BUSBITCHARS "[]" ;
  DIVIDERCHAR "/" ;
  UNITS
    DATABASE MICRONS 2000 ;
  END UNITS

  MACRO Z8086_PAD_PLACEHOLDER
    CLASS PAD SPACER ;
    FOREIGN Z8086_PAD_PLACEHOLDER 0 0 ;
    ORIGIN 0 0 ;
    SIZE 60 BY 80 ;
    SYMMETRY X Y R90 ;
  END Z8086_PAD_PLACEHOLDER

  MACRO Z8086_CORNER_PLACEHOLDER
    CLASS PAD SPACER ;
    FOREIGN Z8086_CORNER_PLACEHOLDER 0 0 ;
    ORIGIN 0 0 ;
    SIZE 90 BY 90 ;
    SYMMETRY X Y R90 ;
  END Z8086_CORNER_PLACEHOLDER

  END LIBRARY
LEF

File.write(lef_output, lef)
