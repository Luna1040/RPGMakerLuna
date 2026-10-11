extends PanelContainer
var canvas := preload("atlas_canvas.gd").new()
var footer := Label.new()
func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:
		# Standalone inventory users may never call setup_atlas().
		for node in [canvas,footer]:
			if is_instance_valid(node) and node.get_parent()==null: node.free()
func setup(stage) -> void:
	position=Vector2(100,75)
	size=Vector2(1080,650)
	var style := StyleBoxFlat.new()
	style.bg_color=Color("10232b")
	style.border_color=Color("a3956a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=16
	style.content_margin_bottom=16
	add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := Label.new()
	title.text="苍石庭院  /  地图集"
	title.add_theme_font_size_override("font_size",24)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var local := Button.new()
	local.text="当前区域"
	row.add_child(local)
	var world_button := Button.new()
	world_button.text="世界地图"
	row.add_child(world_button)
	var close := Button.new()
	close.text="关闭  M / Esc"
	row.add_child(close)
	close.pressed.connect(hide)
	canvas.custom_minimum_size=Vector2(1000,505)
	canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(canvas)
	canvas.setup(stage)
	footer.add_theme_font_size_override("font_size",16)
	footer.add_theme_color_override("font_color",Color("b8cbb9"))
	column.add_child(footer)
	local.pressed.connect(func(): set_world(false))
	world_button.pressed.connect(func(): set_world(true))
	set_world(false)
	hide()
func set_world(value: bool) -> void:
	canvas.world_view=value
	footer.text="世界地图 · 工坊数据快照  |  苍石庭院关联「古塔遗址」  |  地点仅供查看" if value else "金色箭头：玩家   碧绿圆点：NPC   金色箱子：未开宝箱   灰色箱子：已开启"
	canvas.queue_redraw()
