include RBA

input_file = $input
output_file = $output
layer_properties = $layer_properties
image_size = ($image_size || "1800").to_i

raise "missing GDS input: #{input_file}" unless input_file && File.file?(input_file)
raise "missing PNG output" unless output_file && !output_file.empty?
raise "missing layer properties: #{layer_properties}" unless layer_properties && File.file?(layer_properties)

layout = Layout.new(true)
layout.read(input_file)
top_cell = layout.top_cell
raise "GDS has no active top cell" unless top_cell

# Filler cells intentionally make a manufactured row continuous, but they
# obscure the functional standard-cell placement in a whole-die screenshot.
# Delete only those top-level instances in this editable in-memory copy; the
# signed-off GDS on disk is never modified.
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

view.load_layer_props(layer_properties)
view.max_hier
view.set_config("background-color", "#27134f")
view.set_config("grid-visible", "false")
view.set_config("text-visible", "false")
view.set_config("cell-box-visible", "false")
view.set_config("cell-boxes-visible", "false")
view.set_config("cell-names-visible", "false")
view.set_config("ghost-cells-visible", "false")
view.set_config("child-context-enabled", "false")
view.zoom_fit
view.save_image(output_file, image_size, image_size)

raise "KLayout did not produce #{output_file}" unless File.file?(output_file)
