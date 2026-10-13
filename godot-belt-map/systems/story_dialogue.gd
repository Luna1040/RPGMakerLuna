extends Control
## Presentation owns pacing; adventure service remains the only quest authority.
var panel
var left:=TextureRect.new()
var right:=TextureRect.new()
var speaker:=Label.new()
var speech:=Label.new()
var counter:=Label.new()
var next:=Button.new()
var choices:=VBoxContainer.new()
var choice_scroll:=ScrollContainer.new()
var lines: Array = []
var index:=0
var reveal:=0.0
var pending_choice:=""
var at_choices:=false
var npc_name:=""
var selected_choice:=0

func setup(owner_panel) -> void:
	panel=owner_panel
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for entry in [[left,Vector2(45,72)],[right,Vector2(855,72)]]:
		var portrait:TextureRect=entry[0]
		portrait.position=entry[1]
		portrait.size=Vector2(380,540)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(portrait)
	var card:=Panel.new()
	card.position=Vector2(55,545)
	card.size=Vector2(1170,220)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("101e2df5")
	style.border_color=Color("bda575")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel",style)
	add_child(card)
	speaker.position=Vector2(85,558)
	speaker.add_theme_font_size_override("font_size",26)
	speaker.add_theme_color_override("font_color",Color("f3d398"))
	add_child(speaker)
	speech.position=Vector2(85,606)
	speech.size=Vector2(1060,102)
	speech.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	speech.add_theme_font_size_override("font_size",23)
	add_child(speech)
	counter.position=Vector2(85,727)
	counter.add_theme_font_size_override("font_size",16)
	add_child(counter)
	next.position=Vector2(950,715)
	next.size=Vector2(245,38)
	next.text="空格 · 继续"
	next.pressed.connect(advance)
	add_child(next)
	choice_scroll.position=Vector2(430,190)
	choice_scroll.size=Vector2(410,345)
	choice_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation",7)
	choice_scroll.add_child(choices)
	add_child(choice_scroll)
	var close_button:=Button.new()
	close_button.position=Vector2(1060,35)
	close_button.text="Esc · 结束交谈"
	close_button.pressed.connect(panel.close)
	add_child(close_button)
	hide()

func begin() -> void:
	var data:Dictionary=panel.runtime.adventure.dialogue_for(panel.npc_id)
	npc_name=str(data.name)
	var original:Texture2D=load("res://characters/first_knight/assets/stand/000.png")
	var portrait:=AtlasTexture.new()
	portrait.atlas=original
	portrait.region=original.get_image().get_used_rect()
	left.texture=portrait
	var path:String="res://assets/npcs/"+panel.npc_id+".png"
	right.texture=load(path) if ResourceLoader.exists(path) else panel.npc_portrait
	pending_choice=""
	show()
	var guide:="找雷恩接下清敌委托，从庭院西门进入旧林道。完成后回来交付，东南关口就会放行，沿路可到晨钟城。东门的古塔更危险，可以稍后再挑战。"
	if panel.runtime.adventure._status("courtyard_menace")=="claimed":
		guide="晨钟城的道路已经开放。庭院东南关口和晨钟城西门相连；两座城镇的东门都能进入古塔，撤退时会回到出发的城镇。"
	elif panel.npc_id=="smith":
		guide="先接下我的试炼，从庭院西门的蓝色传送门进入旧林道。清理三名敌人后从出口回来找我交付，我就给你晨钟城的通行凭证。"
	if panel.runtime.zone=="city":
		guide="在米拉处补给，向奥伦接下古塔委托。东门进入古塔，清理当前房间后穿过亮起的门，王座间有首领。胜利后回到奥伦这里领取奖励。"
	play([
		{"who":"npc","text":str(data.text)},
		{"who":"hero","text":"我想先熟悉这里的道路。有什么需要我做的？"},
		{"who":"npc","text":guide}
	])

func play(sequence: Array) -> void:
	lines=sequence
	index=0
	at_choices=false
	choice_scroll.hide()
	next.show()
	display_line()

func display_line() -> void:
	var line:Dictionary=lines[index]
	var hero:=str(line.who)=="hero"
	speaker.text="姬骑士" if hero else npc_name
	left.modulate=Color.WHITE if hero else Color(.36,.4,.48,.85)
	right.modulate=Color(.36,.4,.48,.85) if hero else Color.WHITE
	speech.text=str(line.text)
	speech.visible_characters=0
	reveal=0
	counter.text="%d / %d   ·   空格逐句继续，Esc 离开" % [index+1,lines.size()]

func _process(delta: float) -> void:
	if not is_visible_in_tree() or at_choices: return
	reveal+=delta*36
	speech.visible_characters=mini(int(reveal),speech.text.length())

func advance() -> void:
	if at_choices:
		activate_choice()
		return
	if speech.visible_characters>=0 and speech.visible_characters<speech.text.length():
		reveal=speech.text.length()
		speech.visible_characters=-1
		return
	index+=1
	if index<lines.size(): display_line()
	else: show_choices()

func show_choices() -> void:
	at_choices=true
	speech.visible_characters=-1
	speech.text="选择一项事项。任务与分支只有确认后才会生效。"
	counter.text="↑ ↓ 选择 · 空格确认 · Esc 结束交谈"
	next.hide()
	left.modulate=Color(.55,.58,.65)
	right.modulate=Color.WHITE
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	choice_scroll.show()
	choice_scroll.scroll_vertical=0
	if not pending_choice.is_empty():
		var id:=pending_choice
		panel.button(choices,"确认 · "+choice_label(id),func(): panel.runtime.choose_dialogue(id))
		panel.button(choices,"返回话题",func(): pending_choice=""; show_choices())
		prepare_choices()
		return
	var data:Dictionary=panel.runtime.adventure.dialogue_for(panel.npc_id)
	for choice in data.get("choices",[]):
		var id:String=choice.id
		var title:=str(choice.label)
		if not choice.get("enabled",true): title+=" · "+str(choice.get("reason",""))
		var button:Button=panel.button(choices,title,func(): select_topic(id),bool(choice.get("enabled",true)))
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.x=380
	panel.button(choices,"没别的事了 · 结束交谈",panel.close)
	prepare_choices()

func choice_label(id: String) -> String:
	for choice in panel.runtime.adventure.catalog.npcs[panel.npc_id].choices:
		if choice.id==id: return str(choice.label)
	return id

func select_topic(id: String) -> void:
	pending_choice=id
	var detail:=""
	for choice in panel.runtime.adventure.catalog.npcs[panel.npc_id].choices:
		if choice.id!=id: continue
		if choice.has("quest"):
			for quest in panel.runtime.adventure.catalog.quests:
				if quest.id==choice.quest: detail=str(quest.description)
		else: detail=str(choice.get("text",choice.label))
	play([{"who":"hero","text":choice_label(id)},{"who":"npc","text":detail}])

func result(text: String) -> void:
	pending_choice=""
	play([{"who":"npc","text":text}])


func prepare_choices() -> void:
	selected_choice=0
	for i in choices.get_child_count():
		var button: Button=choices.get_child(i)
		button.focus_mode=Control.FOCUS_NONE
		button.mouse_entered.connect(func(): select_choice(i))
	select_choice(0)

func select_choice(index_value: int) -> void:
	var count:=choices.get_child_count()
	if count==0: return
	selected_choice=posmod(index_value,count)
	for attempt in count:
		if not choices.get_child(selected_choice).disabled: break
		selected_choice=(selected_choice+1)%count
	for i in count:
		var button: Button=choices.get_child(i)
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("665333") if i==selected_choice else Color("162735")
		style.border_color=Color("f5cf7e") if i==selected_choice else Color("3c5260")
		style.set_border_width_all(2 if i==selected_choice else 1)
		style.content_margin_left=16
		style.content_margin_right=16
		style.content_margin_top=8
		style.content_margin_bottom=8
		button.add_theme_stylebox_override("normal",style)
		button.add_theme_stylebox_override("hover",style)
	choice_scroll.ensure_control_visible(choices.get_child(selected_choice))

func activate_choice() -> void:
	if not at_choices or choices.get_child_count()==0: return
	var button:Button=choices.get_child(selected_choice)
	if not button.disabled: button.pressed.emit()

func keyboard(code: int) -> void:
	if code in [KEY_SPACE,KEY_ENTER]: advance()
	elif at_choices:
		var direction: int=-1 if code in [KEY_UP,KEY_LEFT] else 1
		var candidate:=selected_choice
		for attempt in choices.get_child_count():
			candidate=posmod(candidate+direction,choices.get_child_count())
			if not choices.get_child(candidate).disabled: break
		select_choice(candidate)
