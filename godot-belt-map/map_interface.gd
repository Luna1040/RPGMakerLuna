extends CanvasLayer
## The courtyard UI owns focus; opening a panel stops movement and combat input.
signal conversation_closed
var actor
var loot
var inventory := PanelContainer.new()
var atlas := preload("atlas_panel.gd").new()
var inventory_content := preload("inventory_panel.gd").new()
var dialogue := PanelContainer.new()
var portrait := TextureRect.new()
var speaker := Label.new()
var speech := Label.new()
var prompt_label := Label.new()
var conversation: Dictionary = {}
var line_index := 0
var external_modal: Callable
var close_external: Callable

func _ready() -> void:
	layer = 10
	add_child(atlas)
	atlas.hide()
	prompt_label.position = Vector2(310, 742)
	prompt_label.size = Vector2(660, 42)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 21)
	prompt_label.add_theme_color_override("font_color", Color("fff2c0"))
	prompt_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt_label.add_theme_constant_override("shadow_offset_x", 2)
	prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(prompt_label)
	inventory.position = Vector2(110, 90)
	inventory.size = Vector2(1060, 630)
	inventory.add_theme_stylebox_override("panel", panel_style())
	add_child(inventory)
	inventory.add_child(inventory_content)
	inventory.hide()
	dialogue.position = Vector2(140, 548)
	dialogue.size = Vector2(1000, 182)
	dialogue.add_theme_stylebox_override("panel", panel_style())
	add_child(dialogue)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	dialogue.add_child(row)
	portrait.custom_minimum_size = Vector2(130, 145)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(portrait)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	speaker.add_theme_font_size_override("font_size", 24)
	speaker.add_theme_color_override("font_color", Color("e6c779"))
	words.add_child(speaker)
	speech.add_theme_font_size_override("font_size", 21)
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.size_flags_vertical = Control.SIZE_EXPAND_FILL
	words.add_child(speech)
	var hint := Label.new()
	hint.text = "E / 空格 继续    Esc 结束交谈"
	hint.add_theme_color_override("font_color", Color("98abb9"))
	words.add_child(hint)
	dialogue.hide()

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.062, 0.09, 0.97)
	style.border_color = Color("a38d5d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func setup(character, world_loot) -> void:
	actor = character
	loot = world_loot
	inventory_content.setup(actor, loot)
	actor.equipment.changed.connect(refresh_inventory)

func is_modal() -> bool:
	return inventory.visible or dialogue.visible or (atlas.is_inside_tree() and atlas.visible) or (external_modal.is_valid() and external_modal.call())

func setup_atlas(stage) -> void:
	atlas.setup(stage)

func toggle_atlas() -> void:
	if atlas.visible:
		atlas.hide()
	else:
		close_panels()
		atlas.show()

func set_prompt(text: String) -> void:
	prompt_label.text = "" if is_modal() else text

func toggle_inventory() -> void:
	if dialogue.visible:
		return
	inventory.visible = not inventory.visible
	if inventory.visible:
		refresh_inventory()

func refresh_inventory() -> void:
	if actor != null and inventory.visible:
		inventory_content.refresh()

func begin_conversation(data: Dictionary) -> void:
	if data.is_empty():
		return
	conversation = data.duplicate()
	line_index = 0
	var image = data.get("portrait")
	portrait.texture = load(image) if image is String and not image.is_empty() else (image if image is Texture2D else null)
	speaker.text = str(data.get("name", "镇民"))
	dialogue.show()
	show_line()

func show_line() -> void:
	var lines: Array = conversation.get("lines", [])
	if line_index >= lines.size():
		close_panels()
	else:
		speech.text = str(lines[line_index])

func advance_conversation() -> void:
	line_index += 1
	show_line()

func close_panels() -> void:
	if close_external.is_valid(): close_external.call()
	atlas.hide()
	inventory.hide()
	dialogue.hide()
	conversation = {}
	conversation_closed.emit()
