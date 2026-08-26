include RBA

input_file = $input
output_directory = $output_directory
overall_properties = $overall_properties
device_properties = $device_properties
routing_properties = $routing_properties
image_size = ($image_size || "2400").to_i

raise "missing GDS input: #{input_file}" unless input_file && File.file?(input_file)
raise "missing output directory" unless output_directory && Dir.exist?(output_directory)
[overall_properties, device_properties, routing_properties].each do |properties|
  raise "missing layer properties: #{properties}" unless properties && File.file?(properties)
end
raise "image_size must be at least 1600" if image_size < 1600

layout = Layout.new(true)
layout.read(input_file)
top_cell = layout.top_cell
raise "GDS has no active top cell" unless top_cell

# Work on an in-memory visualization copy.  Fillers are essential in the GDS,
# but at whole-die scale they hide the functional cell texture completely.
hidden_fillers = 0
top_cell.each_inst.to_a.each do |instance|
  if instance.cell.name.start_with?("FILLCELL")
    instance.delete
    hidden_fillers += 1
  end
end
raise "no FILLCELL instances found in final GDS" if hidden_fillers == 0

view = LayoutView.new
cell_view_index = view.show_layout(layout, true)
cell_view = view.cellview(cell_view_index)
cell_view.cell = top_cell
raise "KLayout did not create an active cell view" unless cell_view && cell_view.is_valid?

view.max_hier
view.set_config("background-color", "#101727")
view.set_config("grid-visible", "false")
view.set_config("text-visible", "false")
view.set_config("cell-box-visible", "false")
view.set_config("cell-boxes-visible", "false")
view.set_config("cell-names-visible", "false")
view.set_config("ghost-cells-visible", "false")
view.set_config("child-context-enabled", "false")

def capture_view(view, properties, area, output, image_size)
  view.load_layer_props(properties)
  if area
    view.zoom_box(DBox.new(*area))
  else
    view.zoom_fit
  end
  view.save_image(output, image_size, image_size)
  raise "KLayout did not produce #{output}" unless File.file?(output)
end

capture_view(
  view,
  overall_properties,
  nil,
  File.join(output_directory, "die_full_gds.png"),
  image_size
)

# The seven architectural partitions occupy 365,375 to 635,625 um.  A 15-25
# um margin retains boundary legalization and clock/buffer spill while making
# individual functional regions readable at README scale.
core_area = [350.0, 350.0, 650.0, 650.0]
capture_view(
  view,
  device_properties,
  core_area,
  File.join(output_directory, "core_devices_gds.png"),
  image_size
)
capture_view(
  view,
  routing_properties,
  core_area,
  File.join(output_directory, "core_routing_gds.png"),
  image_size
)
