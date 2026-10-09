extends CanvasLayer
## Map-owned UI: character remains usable without this training-room overlay.
const GOLD := Color("d9ba77")
const MUTED := Color("9aaec7")
var knight: CharacterBody2D
var arena: Node2D
var root: Control
var overlay: ColorRect
var hp: ProgressBar
var mp: ProgressBar
var hp_text: Label
var mp_text: Label
var state_text: Label
var skill_text: Label
var slot_buttons: Dictionary = {}
var item_buttons: Dictionary = {}
var detail_title: Label
var detail_info: Label
var detail_stats: Label
var comparison: Label
var message: Label
var equip_button: Button
var unequip_button: Button
var selected := "edge_sword"
var selected_slot := "weapon"
var opened := false
var previous_pause := false

func box_style(color: Color, border: Color = Color("304259")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func label(text: String, size := 18, color: Color = Color("e7edf5")) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result

func button(text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 48
	result.pressed.connect(callback)
	return result

func column(parent: Node, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", 10)
	panel.add_child(result)
	return result

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_stylebox("panel", "PanelContainer", box_style(Color("162236")))
	theme.set_stylebox("normal", "Button", box_style(Color("20324a")))
	theme.set_stylebox("hover", "Button", box_style(Color("304967"), GOLD))
	theme.set_stylebox("pressed", "Button", box_style(Color("405776"), GOLD))
	theme.set_stylebox("focus", "Button", box_style(Color(0,0,0,0), GOLD))
	theme.set_color("font_color", "Button", Color("e7edf5"))
	theme.set_color("font_disabled_color", "Button", MUTED)
	root.theme = theme
	add_child(root)
	build_hud()
	build_overlay()
	if not knight.equipment.owned.has(selected):
		selected = ""
	knight.equipment_changed.connect(refresh)
	refresh()

func build_hud() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(24,20)
	panel.size = Vector2(420,168)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	panel.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	var title := label("姬骑士  /  守誓者", 21, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var open_button := button("装备 [E]", toggle)
	open_button.custom_minimum_size.y = 32
	row.add_child(open_button)
	hp_text = label("", 15)
	v.add_child(hp_text)
	hp = make_bar(Color("dd7188"))
	v.add_child(hp)
	mp_text = label("", 15)
	v.add_child(mp_text)
	mp = make_bar(Color("69bee9"))
	v.add_child(mp)
	state_text = label("", 14, MUTED)
	v.add_child(state_text)
	var skill_panel := PanelContainer.new()
	skill_panel.position = Vector2(1000,688)
	skill_panel.size = Vector2(254,88)
	root.add_child(skill_panel)
	var skill_column := VBoxContainer.new()
	skill_panel.add_child(skill_column)
	skill_column.add_child(label("[J] 剑术连击    [K] 雷光", 17, GOLD))
	skill_text = label("", 15)
	skill_column.add_child(skill_text)

func make_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 12
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", box_style(Color("091322")))
	bar.add_theme_stylebox_override("fill", box_style(color, color))
	return bar

func build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0.025,0.045,0.08,0.92)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	overlay.hide()
	var panel := PanelContainer.new()
	panel.position = Vector2(80,78)
	panel.size = Vector2(1120,648)
	overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var header := HBoxContainer.new()
	v.add_child(header)
	var title := label("装备 · 骑士整备", 28, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(button("返回训练 [E / Esc]", toggle))
	v.add_child(label("训练已暂停  ·  装备自动保存  ·  当前角色外观已烘焙，穿戴只改变属性", 16, MUTED))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(columns)
	var slots := column(columns, 220)
	slots.add_child(label("已穿戴", 21, GOLD))
	for slot in knight.equipment.SLOTS:
		var b := button("", select_slot.bind(slot))
		b.custom_minimum_size.y = 73
		slots.add_child(b)
		slot_buttons[slot] = b
	unequip_button = button("卸下选中槽位", remove_selected)
	slots.add_child(unequip_button)
	slots.add_child(label("卸下保留物品\n换装不会恢复生命 / 法力", 14, MUTED))
	var inventory := column(columns, 300)
	inventory.add_child(label("背包  /  训练装备", 21, GOLD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)
	for id in knight.equipment.owned:
		var b := button("", select_item.bind(id))
		b.custom_minimum_size.y = 55
		list.add_child(b)
		item_buttons[id] = b
	var detail := column(columns, 520)
	detail_title = label("", 23, GOLD)
	detail.add_child(detail_title)
	detail_info = label("", 16, MUTED)
	detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(detail_info)
	detail_stats = label("", 17)
	detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(detail_stats)
	detail.add_child(HSeparator.new())
	detail.add_child(label("角色属性  /  穿戴后对比", 19, GOLD))
	comparison = label("", 17)
	detail.add_child(comparison)
	equip_button = button("穿戴选中装备", equip_selected)
	detail.add_child(equip_button)
	message = label("选择背包物品查看属性与对比。", 15, MUTED)
	v.add_child(message)

func select_item(id: String) -> void:
	selected = id
	selected_slot = knight.equipment.CATALOG[id]["slot"]
	refresh()

func select_slot(slot: String) -> void:
	selected_slot = slot
	selected = knight.equipment.equipped[slot]
	refresh()

func equip_selected() -> void:
	if knight.equipment.equip(selected):
		message.text = knight.equipment.save_error if knight.equipment.save_error != "" else "已穿戴「%s」，属性已生效并保存。" % knight.equipment.CATALOG[selected]["name"]
	refresh()

func remove_selected() -> void:
	if knight.equipment.unequip(selected_slot):
		message.text = knight.equipment.save_error if knight.equipment.save_error != "" else "已卸下，物品仍保留在背包中。"
	refresh()

func refresh() -> void:
	if slot_buttons.is_empty():
		return
	var model = knight.equipment
	for slot in model.SLOTS:
		var id: String = model.equipped[slot]
		slot_buttons[slot].text = "%s%s\n%s" % ["› " if selected_slot == slot else "", model.SLOT_NAMES[slot], model.CATALOG[id]["name"] if id != "" else "— 空槽 —"]
	unequip_button.disabled = model.equipped[selected_slot] == ""
	for id in item_buttons:
		var item: Dictionary = model.CATALOG[id]
		var worn: bool = model.equipped[item["slot"]] == id
		item_buttons[id].text = "%s%s  %s\n%s · %s" % ["› " if selected == id else "",item["symbol"],item["name"],item["quality"],"已穿戴" if worn else model.SLOT_NAMES[item["slot"]]]
	var current: Dictionary = knight.get_effective_stats()
	var after := current.duplicate()
	if model.CATALOG.has(selected):
		var item: Dictionary = model.CATALOG[selected]
		detail_title.text = item["name"]
		var old_id: String = model.equipped[item["slot"]]
		detail_info.text = "%s · %s\n%s\n替换：%s" % [item["quality"],model.SLOT_NAMES[item["slot"]],item["description"],model.CATALOG[old_id]["name"] if old_id != "" else "空槽"]
		var lines: Array[String] = []
		for stat in item["stats"]:
			lines.append("%s  %+.0f%s" % [model.STAT_NAMES[stat],item["stats"][stat]," / 秒" if stat == "regen" else ""])
		detail_stats.text = "  ·  ".join(lines) if not lines.is_empty() else "基础装备 · 无额外属性"
		var before_bonus: Dictionary = model.bonuses()
		var next_bonus: Dictionary = model.preview(selected)
		for stat in after:
			after[stat] += next_bonus[stat] - before_bonus[stat]
		equip_button.disabled = old_id == selected
		equip_button.text = "已穿戴" if old_id == selected else "穿戴选中装备"
	else:
		detail_title.text = model.SLOT_NAMES[selected_slot] + " · 空槽"
		detail_info.text = "选择背包中的装备查看穿戴效果。"
		detail_stats.text = ""
		equip_button.disabled = true
		equip_button.text = "请选择装备"
	var stat_lines: Array[String] = []
	for stat in model.STAT_NAMES:
		var diff: float = after[stat] - current[stat]
		stat_lines.append("%s   %.0f%s" % [model.STAT_NAMES[stat],current[stat],"  →  %.0f  (%+.0f)" % [after[stat],diff] if diff != 0 else ""])
	comparison.text = "\n".join(stat_lines)

func toggle() -> void:
	opened = not opened
	if opened:
		previous_pause = get_tree().paused
		get_tree().paused = true
		refresh()
		message.text = "选择背包物品查看属性与对比。"
		overlay.show()
	else:
		overlay.hide()
		get_tree().paused = previous_pause
		get_viewport().gui_release_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_E or (opened and event.keycode == KEY_ESCAPE):
			toggle()
			get_viewport().set_input_as_handled()
		elif opened:
			# Leave navigation/activation keys for focused Controls.
			if event.keycode in [KEY_J,KEY_K,KEY_H,KEY_R,KEY_T,KEY_B,KEY_F2]:
				get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	hp.max_value = knight.max_health
	hp.value = knight.health
	mp.max_value = knight.max_mana
	mp.value = knight.mana
	hp_text.text = "生命  %d / %d" % [ceil(knight.health),knight.max_health]
	mp_text.text = "法力  %d / %d" % [floor(knight.mana),knight.max_mana]
	state_text.text = "倒下 · 按 R 重置" if knight.defeated else "护甲 %.0f   近战 +%.0f   法术 +%.0f   移速 %.0f" % [knight.defense,knight.attack_bonus,knight.magic_bonus,knight.move_speed + knight.equipment_speed_bonus]
	skill_text.text = "雷光冷却  %.1f 秒" % knight.cast_cooldown if knight.cast_cooldown > 0 else ("法力不足 · 需要 25 MP" if knight.mana < 25 else "雷光就绪 · 消耗 25 MP")
