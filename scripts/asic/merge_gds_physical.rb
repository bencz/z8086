include RBA

tech_file = $tech_file
def_file = $def_file
design_name = $design_name
input_files = $input_files.to_s.split
output_file = $output_file
expected_die_size = $expected_die_size.to_f

raise "missing KLayout technology file" unless tech_file && File.file?(tech_file)
raise "missing final DEF" unless def_file && File.file?(def_file)
raise "missing design name" unless design_name && !design_name.empty?
raise "missing physical-library stream files" if input_files.empty?
raise "missing output GDS path" unless output_file && !output_file.empty?
raise "missing expected die size" unless expected_die_size > 0.0
input_files.each do |input_file|
  raise "missing physical-library stream file: #{input_file}" unless File.file?(input_file)
end

technology = Technology.new
technology.load(tech_file)
layout_options = technology.load_layout_options

# Read the DEF at its declared 2000 database units per micron.  KLayout's
# generic def2stream utility later imports 0.1 nm Nangate GDS cells directly
# into this 0.5 nm layout and retains their integer coordinates, which scales
# library geometry by five.  Its default GDS writer then adds another factor
# of two.  Importing every shape through its physical D* representation keeps
# the dimensions in microns independent of both source and destination DBU.
main_layout = Layout.new
main_layout.read(def_file, layout_options)
expected_dbu = 0.0005
raise "unexpected DEF DBU #{main_layout.dbu}" unless (main_layout.dbu - expected_dbu).abs < 1.0e-12

top_cell = main_layout.cell(design_name)
raise "DEF does not contain top cell #{design_name}" unless top_cell
top_cell_index = top_cell.cell_index

main_layout.each_cell.to_a.each do |cell|
  next if cell.cell_index == top_cell_index
  next if cell.name.start_with?("VIA_") || cell.name.end_with?("_DEF_FILL")
  cell.clear
end

def copy_physical_shapes(source_layout, source_cell, target_layout, target_cell)
  unless source_cell.each_inst.to_a.empty?
    raise "physical library cell #{source_cell.name} is hierarchical"
  end

  source_layout.layer_indices.each do |source_layer|
    target_layer = target_layout.layer(source_layout.get_info(source_layer))
    source_cell.each_shape(source_layer) do |shape|
      target_shapes = target_cell.shapes(target_layer)
      if shape.is_box?
        target_shapes.insert(shape.dbox)
      elsif shape.is_polygon?
        target_shapes.insert(shape.dpolygon)
      elsif shape.is_simple_polygon?
        target_shapes.insert(shape.dsimple_polygon)
      elsif shape.is_path?
        target_shapes.insert(shape.dpath)
      elsif shape.is_text?
        target_shapes.insert(shape.dtext)
      else
        raise "unsupported geometry in #{source_cell.name}"
      end
    end
  end
end

input_files.each do |input_file|
  source_layout = Layout.new
  source_layout.read(input_file)
  source_layout.each_cell do |source_cell|
    target_cell = main_layout.cell(source_cell.name)
    target_cell = main_layout.create_cell(source_cell.name) unless target_cell
    target_cell.clear
    copy_physical_shapes(source_layout, source_cell, main_layout, target_cell)
  end
end

# Keep only the hierarchy reachable from the chip top, matching the upstream
# orphan-free contract, while preserving the now-normalized physical shapes.
final_layout = Layout.new
final_layout.dbu = expected_dbu
final_top = final_layout.create_cell(design_name)
final_top.copy_tree(top_cell)

final_layout.each_cell do |cell|
  next if cell == final_top
  raise "referenced physical cell #{cell.name} is empty" if cell.is_empty?
end

save_options = SaveLayoutOptions.new
save_options.set_format_from_filename(output_file)
save_options.dbu = expected_dbu
final_layout.write(output_file, save_options)
raise "physical GDS was not written" unless File.file?(output_file)

# Read the stream back instead of trusting writer state.  The DEF die and a
# representative standard-cell master must retain their physical dimensions.
check_layout = Layout.new
check_layout.read(output_file)
check_top = check_layout.cell(design_name)
check_dff = check_layout.cell("DFF_X1")
raise "written GDS lost its top cell" unless check_top
raise "written GDS lost DFF_X1" unless check_dff
top_box = check_top.dbbox
dff_box = check_dff.dbbox
die_tolerance = 1.0
unless top_box.width > expected_die_size - die_tolerance &&
       top_box.width < expected_die_size + die_tolerance &&
       top_box.height > expected_die_size - die_tolerance &&
       top_box.height < expected_die_size + die_tolerance
  raise "written GDS die is #{top_box.width} x #{top_box.height} um, expected #{expected_die_size} x #{expected_die_size} um"
end
unless dff_box.width > 3.4 && dff_box.width < 3.5 &&
       dff_box.height > 1.6 && dff_box.height < 1.7
  raise "written GDS DFF_X1 is #{dff_box.width} x #{dff_box.height} um"
end

puts "PASS: physical GDS dimensions preserved (die #{expected_die_size}x#{expected_die_size} um, DFF_X1 #{dff_box.width}x#{dff_box.height} um)"
