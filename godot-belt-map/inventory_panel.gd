extends VBoxContainer
## Read-only previews share the equipment model used by combat.
var actor
var loot
var selected_id := ""
var stat_text := RichTextLabel.new()
var detail_text := RichTextLabel.new()
var item_list := VBoxContainer.new()
var material_text := Label.new()
var buttons: Dictionary = {}
const ORDER := ["attack", "magic", "health", "mana", "defense", "speed", "regen"]
const NAMES := {"attack":"物理伤害加成", "magic":"魔法伤害加成", "health":"生命上限", "mana":"法力上限", "defense":"护甲", "speed":"移动速度", "regen":"法力回复 / 秒"}

func setup(character, world_loot) -> void:
	actor = character
	loot = world_loot
	add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "角色与行囊                                      I / Esc 关闭"
	title.add_theme_font_size_override("font_size", 25)
	add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	columns.add_child(left)
	add_heading(left, "姬骑士 · 当前属性")
	configure_rich(stat_text, 250)
	left.add_child(stat_text)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size.x = 390
	columns.add_child(middle)
	add_heading(middle, "装备 · 悬停查看 / 点击穿戴")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(scroll)
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 7)
	scroll.add_child(item_list)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 338
	columns.add_child(right)
	add_heading(right, "装备详情 · 替换对比")
	configure_rich(detail_text, 338)
	right.add_child(detail_text)
	material_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	material_text.add_theme_color_override("font_color", Color("d7bd80"))
	add_child(material_text)
	actor.stats_changed.connect(func(_hp, _mp): update_stats())
	refresh()

func add_heading(parent: Control, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color("e6c779"))
	parent.add_child(label)
	parent.add_child(HSeparator.new())

func configure_rich(label: RichTextLabel, width: float) -> void:
	label.bbcode_enabled = true
	label.custom_minimum_size.x = width
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 18)
	label.add_theme_font_size_override("bold_font_size", 18)
	label.add_theme_constant_override("line_separation", 1)

func number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value

func signed(value: float) -> String:
	return ("+" if value > 0 else "") + number(value)

func update_stats() -> void:
	var s: Dictionary = actor.get_effective_stats()
	stat_text.text = "生命  [color=#8de1b0]%s / %s[/color]\n法力  [color=#82caff]%s / %s[/color]\n\n攻击力  %s\n魔法攻击力  %s\n护甲  %s\n移动速度  %s\n法力回复  %s / 秒\n\n[color=#a6b5c7]物理加成  %s\n魔法加成  %s\n攻击力：普攻首击伤害\n魔法攻击力：雷光直接伤害\n其他招式：基础伤害＋总加成。[/color]" % [number(actor.health), number(s.health), number(actor.mana), number(s.mana), number(actor.get_attack_damage("attack1")), number(actor.get_spell_damage()), number(s.defense), number(s.speed), number(s.regen), signed(s.attack), signed(s.magic)]

func refresh() -> void:
	update_stats()
	for child in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()
	buttons.clear()
	var items: Array = actor.equipment.owned.duplicate()
	items.sort_custom(func(a, b): return str(a).begins_with("courtyard_") and not str(b).begins_with("courtyard_"))
	for id in items:
		var item: Dictionary = actor.equipment.CATALOG[id]
		var equipped: bool = actor.equipment.equipped.get(item.slot, "") == id
		var button := Button.new()
		button.text = ("● " if equipped else "    ") + item.name + " · " + item.quality
		button.custom_minimum_size.y = 42
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		if equipped:
			button.add_theme_color_override("font_color", Color("8de1b0"))
		button.mouse_entered.connect(func(): show_item(id))
		button.focus_entered.connect(func(): show_item(id))
		button.pressed.connect(func():
			selected_id = id
			actor.equipment.equip(id)
		)
		item_list.add_child(button)
		buttons[id] = button
	if not items.has(selected_id):
		selected_id = str(items[0]) if not items.is_empty() else ""
	show_item(selected_id)
	material_text.text = "● 已装备    ·    悬停或键盘选中查看对比    ·    当前换装仅改变属性\n"
	if loot != null:
		material_text.text += "木料 ×%d    碎布 ×%d    旧铜币 ×%d    秘银碎屑 ×%d" % [loot.materials["木料"], loot.materials["碎布"], loot.materials["旧铜币"], loot.materials["秘银碎屑"]]

func show_item(id: String) -> void:
	selected_id = id
	if not actor.equipment.CATALOG.has(id):
		detail_text.text = "尚未获得装备。"
		return
	var item: Dictionary = actor.equipment.CATALOG[id]
	var current_id: String = actor.equipment.equipped.get(item.slot, "")
	var current: Dictionary = actor.equipment.bonuses()
	var preview: Dictionary = actor.equipment.preview(id)
	var text := "[color=#e6c779]%s[/color]\n%s · %s%s\n\n%s\n\n装备属性\n" % [item.name, item.quality, actor.equipment.SLOT_NAMES[item.slot], " · 已装备" if id == current_id else "", item.description]
	if item.stats.is_empty():
		text += "无额外属性\n"
	for stat in ORDER:
		if item.stats.has(stat):
			text += "%s  %s\n" % [NAMES[stat], signed(float(item.stats[stat]))]
	text += "\n替换当前装备后\n"
	if id == current_id:
		text += "当前已装备此物品。"
	else:
		text += "对比：%s\n" % (actor.equipment.CATALOG[current_id].name if not current_id.is_empty() else "空槽位")
		var differences := 0
		for stat in ORDER:
			var delta: float = preview[stat] - current[stat]
			if is_zero_approx(delta):
				continue
			differences += 1
			var total: float = actor.get_effective_stats()[stat] + delta
			var label: String = NAMES[stat]
			if stat == "attack":
				total = actor.get_attack_damage("attack1") + delta
				label = "攻击力"
			elif stat == "magic":
				total = actor.get_spell_damage() + delta
				label = "魔法攻击力"
			text += "%s  %s  [color=%s](%s)[/color]\n" % [label, number(total), "#8de1b0" if delta > 0 else "#ff9292", signed(delta)]
		if differences == 0:
			text += "属性无变化。\n"
		text += "\n[color=#a6b5c7]点击左侧此装备即可穿戴。[/color]"
	detail_text.text = text
