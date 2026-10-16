extends CanvasLayer
var runtime
var panel := PanelContainer.new()
var text := Label.new()
var clock := 0.0

func setup(service) -> void:
	runtime = service
	layer = 12
	panel.position = Vector2(972,290)
	panel.custom_minimum_size = Vector2(286,0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.035,.075,.12,.90)
	style.border_color = Color("b69a65")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var open := Button.new()
	open.text = "任务日志  [L]"
	open.focus_mode = Control.FOCUS_NONE
	open.pressed.connect(func(): runtime.panel.open("journal"))
	box.add_child(open)
	text.custom_minimum_size = Vector2(256,0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size",16)
	text.add_theme_color_override("font_color",Color("e4d9be"))
	box.add_child(text)
	refresh()

func _process(delta: float) -> void:
	if runtime == null: return
	panel.visible = not runtime.panel.is_open() and not runtime.stage.interface.is_modal()
	clock += delta
	if clock >= .3:
		clock = 0
		refresh()

func refresh() -> void:
	var lines: Array[String] = []
	var rows: Array = runtime.adventure.quest_rows()
	if not runtime.tracked_quest.is_empty():
		for i in rows.size():
			if rows[i].id == runtime.tracked_quest:
				var selected = rows.pop_at(i)
				rows.push_front(selected)
				break
	var shown := 0
	for quest in rows:
		if quest.status not in ["active","ready"]: continue
		if shown >= 2: break
		shown += 1
		lines.append(("◆ 可交付 · " if quest.status == "ready" else "◇ ")+str(quest.title))
		for objective in quest.get("objectives",[]):
			lines.append("%s  %s/%s" % [objective.get("label","目标"),objective.get("current",0),objective.get("target",1)])
		if quest.status == "ready": lines.append("回城打开任务日志领取奖励")
		lines.append("")
	if shown == 0:
		lines.append("与雷恩交谈接取委托。\n晨钟城新增：霜钟隘口 / 余烬圣堂。\n两条支线完成后开启终章。")
	text.text = "\n".join(lines)
