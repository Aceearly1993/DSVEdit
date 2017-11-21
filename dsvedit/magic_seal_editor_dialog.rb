
require_relative 'ui_magic_seal_editor'

class MagicSealEditorDialog < Qt::Dialog
  attr_reader :game
  
  slots "magic_seal_changed(int)"
  slots "magic_seal_properties_changed()"
  slots "button_box_clicked(QAbstractButton*)"
  slots "delete_entity()"
  
  def initialize(main_window, renderer)
    super(main_window, Qt::WindowTitleHint | Qt::WindowSystemMenuHint)
    @ui = Ui_MagicSealEditor.new
    @ui.setup_ui(self)
    
    @game = main_window.game
    @renderer = renderer
    
    @magic_seal_graphics_scene = Qt::GraphicsScene.new
    @magic_seal_graphics_scene.setSceneRect(0, 0, 192, 192)
    @ui.magic_seal_graphics_view.setScene(@magic_seal_graphics_scene)
    
    connect(@ui.magic_seal_index, SIGNAL("activated(int)"), self, SLOT("magic_seal_changed(int)"))
    connect(@ui.num_points, SIGNAL("editingFinished()"), self, SLOT("magic_seal_properties_changed()"))
    connect(@ui.radius, SIGNAL("editingFinished()"), self, SLOT("magic_seal_properties_changed()"))
    connect(@ui.rotation, SIGNAL("editingFinished()"), self, SLOT("magic_seal_properties_changed()"))
    connect(@ui.buttonBox, SIGNAL("clicked(QAbstractButton*)"), self, SLOT("button_box_clicked(QAbstractButton*)"))
    
    @magic_seals = []
    MAGIC_SEAL_COUNT.times do |i|
      @magic_seals << MagicSeal.new(i, @game.fs)
      @ui.magic_seal_index.addItem("%02X" % i)
    end
    
    magic_seal_changed(0)
    
    self.show()
  end
  
  def magic_seal_changed(seal_index)
    @magic_seal = @magic_seals[seal_index]
    
    @ui.num_points.text = "%04X" % @magic_seal.num_points
    @ui.radius.text = "%04X" % @magic_seal.radius
    @ui.rotation.text = "%04X" % @magic_seal.rotation
    @ui.time_limit.text = "%04X" % @magic_seal.time_limit
    
    render_magic_seal()
    
    @ui.magic_seal_index.setCurrentIndex(seal_index)
  end
  
  def magic_seal_properties_changed
    @magic_seal.num_points = @ui.num_points.text.to_i(16)
    @magic_seal.radius = @ui.radius.text.to_i(16)
    @magic_seal.rotation = @ui.rotation.text.to_i(16)
    @magic_seal.time_limit = @ui.time_limit.text.to_i(16)
    
    @ui.num_points.text = "%04X" % @magic_seal.num_points
    @ui.radius.text = "%04X" % @magic_seal.radius
    @ui.rotation.text = "%04X" % @magic_seal.rotation
    @ui.time_limit.text = "%04X" % @magic_seal.time_limit
    
    render_magic_seal()
  end
  
  def render_magic_seal
    @magic_seal_graphics_scene.clear()
    
    other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Magic seal"}
    sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:pointer], @game.fs, other_sprite[:overlay], other_sprite)
    frames, min_x, min_y = @renderer.render_sprite(sprite_info, frame_to_render: :all)
    line_frame = frames[3].trim
    point_frame = frames[4].trim
    outer_ring_frame = frames[9]
    inner_ring_frame = frames[0xA]
    
    image_width = outer_ring_frame.width
    image_height = outer_ring_frame.height
    
    # Add rings.
    outer_ring_item = GraphicsChunkyItem.new(outer_ring_frame)
    @magic_seal_graphics_scene.addItem(outer_ring_item)
    inner_ring_item = GraphicsChunkyItem.new(inner_ring_frame)
    @magic_seal_graphics_scene.addItem(inner_ring_item)
    
    # Calculate point positions.
    degrees_between_points = 2*Math::PI/@magic_seal.num_points
    angle = @magic_seal.rotation/182.0/180.0*Math::PI
    positions = []
    @magic_seal.num_points.times do |point_i|
      x = Math.cos(angle) * @magic_seal.radius
      y = Math.sin(angle) * @magic_seal.radius
      x = x.to_i
      y = y.to_i
      x += image_width/2
      y += image_height/2
      positions << {x: x, y: y}
      angle += degrees_between_points
    end
    
    # Add points.
    positions.each do |pos|
      point_item = GraphicsChunkyItem.new(point_frame)
      point_item.setPos(pos[:x]-point_frame.width/2, pos[:y]-point_frame.height/2)
      @magic_seal_graphics_scene.addItem(point_item)
    end
    
    # Add lines.
    (@magic_seal.point_order_list.length-1).times do |line_index|
      point_1_index = @magic_seal.point_order_list[line_index]
      point_2_index = @magic_seal.point_order_list[line_index+1]
      point_1_pos = positions[point_1_index]
      point_2_pos = positions[point_2_index]
      
      xdiff = point_2_pos[:x] - point_1_pos[:x]
      ydiff = point_2_pos[:y] - point_1_pos[:y]
      angle_rads = Math.atan2(ydiff, xdiff)
      angle = angle_rads * 180 / Math::PI
      
      length_in_pixels = Math.sqrt(xdiff**2 + ydiff**2)
      
      line_item = GraphicsChunkyItem.new(line_frame)
      line_item.setPos(point_1_pos[:x], point_1_pos[:y])
      # We need to use Qt::Transform to make sure it applies the rotation before the scaling.
      transform = Qt::Transform.new
      transform.rotate(angle)
      transform.scale(length_in_pixels/16, 1) # The line frame is 16 pixels wide already, so only scale it by 1/16 the length in pixels.
      line_item.setTransform(transform)
      @magic_seal_graphics_scene.addItem(line_item)
    end
  end
  
  def save_magic_seal
    @magic_seal.num_points = @ui.num_points.text.to_i(16)
    @magic_seal.radius = @ui.radius.text.to_i(16)
    @magic_seal.rotation = @ui.rotation.text.to_i(16)
    @magic_seal.time_limit = @ui.time_limit.text.to_i(16)
    
    @magic_seal.write_to_rom()
  end
  
  def button_box_clicked(button)
    if @ui.buttonBox.standardButton(button) == Qt::DialogButtonBox::Ok
      save_magic_seal()
      self.close()
    elsif @ui.buttonBox.standardButton(button) == Qt::DialogButtonBox::Cancel
      self.close()
    elsif @ui.buttonBox.standardButton(button) == Qt::DialogButtonBox::Apply
      save_magic_seal()
    end
  end
end
