extends CanvasLayer
## Compact mouse/keyboard skill HUD. Hide the layer while a modal is open.
signal skill_pressed(id: String)
signal spell_pressed

const ENTRIES := [
	{"id":"crescent", "name":"月弧斩", "key":"1", "cost":18, "cooldown":4.0, "color":Color("8fdafa")},
	{"id":"rising", "name":"破晓升龙", "key":"2", "cost":24, "cooldown":6.0, "color":Color("ffd887")},
	{"id":"trinity", "name":"幻影三连", "key":"3", "cost":32, "cooldown":9.0, "color":Color("c8a9ff")},
	{"id":"spell", "name":"雷光", "key":"K", "cost":25, "cooldown":2.4, "color":Color("81adff")}
]
var actor
var bar: SkillPanel

func _ready() -> void:
	layer = 9
	bar = SkillPanel.new()
	bar.host = self
	bar.position = Vector2(350, 687)
	bar.size = Vector2(580, 108)
	add_child(bar)

func setup(knight) -> void:
	actor = knight

func entry_at(index: int) -> Dictionary:
	var entry: Dictionary = ENTRIES[index].duplicate()
	if is_instance_valid(actor) and entry.id != "spell":
		entry.merge(actor.SKILLS.get(entry.id, {}), true)
	return entry

func _process(_delta: float) -> void:
	if is_instance_valid(bar) and visible:
		bar.queue_redraw()

func remaining(id: String) -> float:
	if not is_instance_valid(actor):
		return 0.0
	if id == "spell":
		return maxf(0.0, float(actor.cast_cooldown))
	return maxf(0.0, float(actor.skill_cooldowns.get(id, 0.0)))

func activate(index: int) -> void:
	if not visible or not is_instance_valid(actor):
		return
	var entry: Dictionary = entry_at(index)
	if remaining(entry.id) > 0.0 or actor.mana < entry.cost:
		return
	if entry.id == "spell":
		spell_pressed.emit()
	else:
		skill_pressed.emit(entry.id)

class SkillPanel extends Control:
	var host
	var hover_index := -1
	var font: Font = ThemeDB.fallback_font

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(func(): hover_index = -1; queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			hover_index = -1
			for i in range(4):
				if card(i).has_point(event.position):
					hover_index = i
			tooltip_text = ""
			if hover_index >= 0:
				var entry: Dictionary = host.entry_at(hover_index)
				tooltip_text = "%s [%s]\n%s\n消耗 %d MP · 冷却 %.1f 秒" % [entry.name, entry.key, entry.get("description", "释放雷光，对命中目标施加感电"), entry.cost, entry.cooldown]
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in range(4):
				if card(i).has_point(event.position):
					host.activate(i)
					accept_event()
					return

	func card(index: int) -> Rect2:
		return Rect2(8 + index * 142, 27, 138, 75)

	func label_at(pos: Vector2, text: String, color: Color, font_size: int = 15) -> void:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _draw() -> void:
		draw_style_box(box(Color("0c1626"), Color("516176")), Rect2(Vector2.ZERO, size))
		if not is_instance_valid(host.actor):
			return
		var actor = host.actor
		var hp_ratio := clampf(float(actor.health) / maxf(1.0, float(actor.max_health)), 0.0, 1.0)
		var mp_ratio := clampf(float(actor.mana) / maxf(1.0, float(actor.max_mana)), 0.0, 1.0)
		for i in range(2):
			var rect := Rect2(10 + i * 285, 7, 275, 12)
			draw_rect(rect, Color("263247"))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x * (hp_ratio if i == 0 else mp_ratio), rect.size.y)), Color("a24958") if i == 0 else Color("397bc1"))
			var value := "HP  %d / %d" % [actor.health, actor.max_health] if i == 0 else "MP  %d / %d" % [actor.mana, actor.max_mana]
			label_at(rect.position + Vector2(5, 11), value, Color.WHITE, 12)
		for i in range(4):
			var entry: Dictionary = host.entry_at(i)
			var rect := card(i)
			var cd: float = host.remaining(entry.id)
			var low_mana: bool = actor.mana < entry.cost
			var accent: Color = entry.color
			draw_style_box(box(Color("1b2b40") if i == hover_index else Color("121e30"), accent if i == hover_index else Color("35465b")), rect)
			var center := rect.position + Vector2(29, 31)
			draw_circle(center, 23, Color("0a1322"))
			draw_arc(center, 23, 0, TAU, 32, Color(accent, 0.3), 1.0, true)
			icon(i, center, Color("707d8d") if low_mana else accent)
			label_at(rect.position + Vector2(58, 29), entry.name, Color("d8e2ee") if not low_mana else Color("7f8c9d"), 15)
			label_at(rect.position + Vector2(58, 50), "%d MP" % entry.cost, Color("92abc9"), 12)
			label_at(rect.position + Vector2(11, 68), "[%s]" % entry.key, accent, 13)
			if low_mana:
				label_at(rect.position + Vector2(70, 67), "魔力不足", Color("b57f90"), 11)
			if cd > 0.0:
				var ratio := clampf(cd / float(entry.cooldown), 0.0, 1.0)
				draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * (1.0 - ratio)), Vector2(rect.size.x, rect.size.y * ratio)), Color(0.01, 0.02, 0.05, 0.73))
				label_at(rect.position + Vector2(61, 47), "%.1f" % cd, Color.WHITE, 23)
				label_at(rect.position + Vector2(11, 68), "[%s]" % entry.key, accent, 13)

	func box(bg: Color, border: Color) -> StyleBoxFlat:
		var result := StyleBoxFlat.new()
		result.bg_color = bg
		result.border_color = border
		result.set_border_width_all(1)
		result.set_corner_radius_all(7)
		return result

	func icon(index: int, center: Vector2, color: Color) -> void:
		match index:
			0:
				draw_arc(center + Vector2(-3, 0), 17, -1.2, 1.3, 22, color, 5.0, true)
				draw_arc(center + Vector2(-3, 0), 21, -0.9, 0.7, 22, Color(color, 0.45), 2.0, true)
				draw_line(center + Vector2(-16, 13), center + Vector2(16, -14), Color.WHITE, 2.0, true)
			1:
				draw_colored_polygon(PackedVector2Array([center + Vector2(0,-22),center+Vector2(5,-9),center+Vector2(2,12),center+Vector2(-2,12),center+Vector2(-5,-9)]),color)
				draw_line(center+Vector2(-9,10),center+Vector2(9,10),color,3,true)
				draw_line(center+Vector2(0,10),center+Vector2(0,19),Color.WHITE,3,true)
				draw_arc(center+Vector2(3,3),18,0.1,2.7,20,Color(color,0.65),2,true)
			2:
				for j in range(3):
					var origin := center+Vector2(-12+j*9,5-j*4)
					draw_line(origin+Vector2(-5,12),origin+Vector2(7,-17),Color(color,0.45+j*0.25),3,true)
					draw_line(origin+Vector2(-6,6),origin+Vector2(3,10),color,2,true)
			3:
				draw_colored_polygon(PackedVector2Array([center+Vector2(3,-22),center+Vector2(-12,3),center+Vector2(-2,1),center+Vector2(-5,22),center+Vector2(13,-5),center+Vector2(3,-2)]),color)
				draw_line(center+Vector2(3,-16),center+Vector2(-5,1),Color.WHITE,2,true)
