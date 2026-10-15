extends CanvasLayer

const TITLES := ["人物", "背包", "任务", "武功", "系统"]
const KEYS := [KEY_C, KEY_TAB, KEY_Q, KEY_K, KEY_ESCAPE]
const HINTS := ["C", "Tab", "Q", "K", "Esc"]
var game: Node
var footer: PanelContainer
var bar: HBoxContainer
var window: PanelContainer
var content: VBoxContainer
var current := -1
var prior_pause := false
var bag_slots: Array[Button] = []
var quest_tab := 0
var skill_category := 0
var skill_ui: CanvasLayer

class MenuIcon extends Control:
	var kind := 0
	func _draw() -> void:
		var gold := Color("efd294")
		match kind:
			0:
				draw_circle(Vector2(24,12),7,gold)
				draw_arc(Vector2(24,37),16,PI,TAU,24,gold,4,true)
				draw_line(Vector2(8,37),Vector2(40,37),gold,3,true)
			1:
				draw_style_box(_box(),Rect2(9,14,30,26))
				draw_arc(Vector2(24,15),9,PI,TAU,20,gold,3,true)
				draw_line(Vector2(10,24),Vector2(38,24),gold,2,true)
				draw_circle(Vector2(24,25),3,gold)
			2:
				draw_style_box(_box(),Rect2(11,5,26,36))
				for y in [15,23,31]: draw_line(Vector2(17,y),Vector2(31,y),gold,2,true)
			3:
				for x in [13,22,31]: draw_line(Vector2(x,35),Vector2(x+9,9),gold,3,true)
				draw_arc(Vector2(23,27),14,0,PI,20,gold,2,true)
			4:
				draw_arc(Vector2(24,23),13,0,TAU,32,gold,4,true)
				for i in range(8):
					var d := Vector2.from_angle(i*TAU/8)
					draw_line(Vector2(24,23)+d*13,Vector2(24,23)+d*20,gold,4,true)
				draw_circle(Vector2(24,23),4,gold)
	func _box() -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color=Color("315351")
		s.border_color=Color("efd294")
		s.set_border_width_all(2)
		s.set_corner_radius_all(4)
		return s

func _ready() -> void:
	game=get_parent()
	layer=28
	footer=PanelContainer.new()
	footer.position=Vector2(25,685)
	footer.size=Vector2(1230,100)
	footer.mouse_filter=Control.MOUSE_FILTER_STOP
	footer.add_theme_stylebox_override("panel",game.make_style(Color("132930")))
	add_child(footer)
	var help := Label.new()
	help.text="左键 寻路 / 选中 / 再点攻击\n右键旋转 · 滚轮缩放 · Ctrl+C 打坐\nShift 轻功（5级） · F5 保存 · F6 名册"
	help.position=Vector2(20,12)
	help.add_theme_font_size_override("font_size",18)
	footer.add_child(help)
	bar=HBoxContainer.new()
	bar.position=Vector2(710,688)
	bar.add_theme_constant_override("separation",8)
	add_child(bar)
	for i in range(5):
		var button := Button.new()
		button.custom_minimum_size=Vector2(100,92)
		button.tooltip_text=TITLES[i]+"（"+HINTS[i]+"）"
		button.pressed.connect(toggle.bind(i))
		button.focus_mode=Control.FOCUS_NONE
		bar.add_child(button)
		var icon := MenuIcon.new()
		icon.kind=i
		icon.position=Vector2(26,5)
		icon.size=Vector2(48,45)
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var label := Label.new()
		label.text=TITLES[i]+" "+HINTS[i]
		label.position=Vector2(0,55)
		label.size=Vector2(100,30)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
	window=PanelContainer.new()
	window.position=Vector2(265,125)
	window.custom_minimum_size=Vector2(730,460)
	var style: StyleBoxFlat=game.make_style(Color("132930"))
	style.content_margin_left=18
	style.content_margin_right=18
	style.content_margin_top=12
	style.content_margin_bottom=12
	window.add_theme_stylebox_override("panel",style)
	add_child(window)
	content=VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	window.add_child(content)
	window.hide()
	skill_ui=preload("res://skill_ui.gd").new()
	skill_ui.name="SkillUI"
	skill_ui.game=game
	add_child(skill_ui)

func _process(_dt: float) -> void:
	bar.visible=game.active_slot>0 and not game.menu.visible
	footer.visible=bar.visible
	if window.visible and game.menu.visible: close()

func _input(event: InputEvent) -> void:
	if game.menu.visible or game.active_slot==0: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed or event.alt_pressed: return
		var index := KEYS.find(event.keycode)
		if index>=0:
			if event.keycode==KEY_ESCAPE and current>=0: close()
			else: toggle(index)
			get_viewport().set_input_as_handled()
		elif window.visible:
			get_viewport().set_input_as_handled()
	elif window.visible and event is InputEventMouseButton:
		# Controls still receive GUI events; the world receives none.
		game.dragging=false

func close() -> void:
	window.hide()
	current=-1
	game.paused=prior_pause or game.menu.visible

func toggle(index: int) -> void:
	if game.active_slot==0 or game.menu.visible: return
	if current==index:
		close()
		return
	if current<0: prior_pause=game.paused
	game.paused=true
	game.dragging=false
	game.hero.velocity=Vector3.ZERO
	current=index
	rebuild()
	window.show()

func text(value: String, font_size: int=20) -> Label:
	var label := Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",font_size)
	content.add_child(label)
	return label

func action(title: String, callback: Callable, disabled: bool=false) -> Button:
	var button := Button.new()
	button.text=title
	button.custom_minimum_size.y=34
	button.disabled=disabled
	button.pressed.connect(callback)
	content.add_child(button)
	return button

func rebuild() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	bag_slots.clear()
	text(TITLES[current]+" · "+HINTS[current],27)
	match current:
		0: build_character()
		1: build_bag()
		2: build_quests()
		3: build_skills()
		4: build_settings()
	action("关闭 · Esc / 再按当前快捷键",close)

func build_character() -> void:
	text("%s  ·  %s  ·  等级 %d" % [game.character.get("name","侠客"),game.Saves.display_profession(game.character.get("profession","刀客")),game.level],23)
	text("生命 %d / %d       真气 %d / 100" % [game.hp,game.max_hp(),game.qi])
	text("攻击 %d     防御 %d     经验 %d / %d" % [game.attack_power(),game.defense_power(),game.exp_points,game.xp_needed()])
	text("装备栏",23)
	var grid := GridContainer.new()
	grid.columns=2
	content.add_child(grid)
	for item in ["武器 · 入门兵器（外观）","衣服 · 初行江湖衣（外观）","头部 · 未装备","护腕 · 未装备","鞋履 · 未装备","饰品 · 未装备"]:
		var label := Label.new()
		label.text=item
		label.custom_minimum_size=Vector2(340,42)
		grid.add_child(label)
	text("当前攻防来自职业与等级；装备栏暂展示已有外观及空槽。",16)

func build_bag() -> void:
	text("随身行囊 · 40 格（8 × 5）",21)
	var grid := GridContainer.new()
	grid.columns=8
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	content.add_child(grid)
	for i in range(40):
		var slot: Button = skill_ui.create_source("potion") if i==0 else Button.new()
		slot.custom_minimum_size=Vector2(80,42)
		if i==0: slot.add_theme_constant_override("icon_max_width",30)
		slot.text=""
		slot.tooltip_text="小金创药：点击恢复 60 生命；可拖到技能栏" if i==0 and game.potions>0 else "空背包格"
		if i==0 and game.potions<=0:
			slot.icon=null
			slot.get_node("StackCount").text=""
		if i==0: slot.pressed.connect(use_potion)
		grid.add_child(slot)
		bag_slots.append(slot)
	text("人物资产       银两：%d 两" % game.coins,23)

func use_potion() -> void:
	if game.potions<=0 or game.hp>=game.max_hp(): return
	game.use_skill("potion")
	rebuild()

func build_quests() -> void:
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	for i in range(3):
		var button := Button.new()
		button.text=["可接任务","已接任务","已完成任务"][i]
		button.custom_minimum_size=Vector2(225,40)
		button.toggle_mode=true
		button.button_pressed=quest_tab==i
		button.pressed.connect(func(): quest_tab=i; rebuild())
		tabs.add_child(button)
	var status: int=2 if game.training_rewarded else (1 if game.training_state>0 else 0)
	if quest_tab==status:
		text("初入江湖 · 门主切磋",23)
		text(["前往泫渤派门主处对话，接受切磋历练。","击败练习刀客，再返回门主处交差。","切磋已完成，奖励已领取。"][status])
		text("奖励：银两 50 两")
		if status==1: text("进度："+("已击败刀客 · 待交差" if game.training_state>=2 else "正在切磋"))
	else: text("此分类暂无任务。")
	if quest_tab==status and status<2:
		action("自动寻路 · "+("练习刀客" if status==1 and game.training_state<2 else "泫渤派门主"),guide_quest)
	text("点击指导后自动走到任务人物旁边。",17)

func guide_quest() -> void:
	close()
	if game.training_state==1 and game.enemy_health>0:
		game.navigate_to_actor(game.practice,"")
	else: game.navigate_to_actor(game.master,"master")

func build_skills() -> void:
	text("拖动已学武功图标到左侧 1–9 技能格",20)
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	for category in range(2):
		var button := Button.new()
		button.text=["攻击性武功","辅助性武功"][category]
		button.custom_minimum_size=Vector2(330,38)
		button.toggle_mode=true
		button.button_pressed=skill_category==category
		button.pressed.connect(func(): skill_category=category; rebuild())
		tabs.add_child(button)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	content.add_child(row)
	for id in ["attack","lightness","cloud_step"]:
		if (id=="attack") != (skill_category==0): continue
		var info: Dictionary=preload("res://kungfu_data.gd").DATA[id]
		var card := VBoxContainer.new()
		card.custom_minimum_size=Vector2(215,190)
		row.add_child(card)
		card.add_child(skill_ui.create_source(id))
		var title := Label.new()
		title.text="%s · %d 级\n%s" % [info.name,info.level,"攻击性武功" if id=="attack" else "辅助性武功"]
		card.add_child(title)
		var learn := Button.new()
		learn.text="已学会 · 可拖动" if id in game.learned_skills else "修习武功"
		learn.disabled=id in game.learned_skills or game.level<int(info.level)
		learn.pressed.connect(func(): game.learn_skill(id); rebuild())
		card.add_child(learn)
		if id!="attack":
			var use := Button.new()
			use.text="施展 · 两段滑翔" if id=="cloud_step" else "施展 · 持续 60 秒"
			use.disabled=not id in game.learned_skills
			use.pressed.connect(func(): close(); game.use_skill(id))
			card.add_child(use)
	text("轻功提纵术：60 秒双倍移速；梯云纵：两段滑翔，无冷却。",17)
	text("技能格支持点击与数字键；右键清空。Shift 快捷施展 / 关闭轻功。",17)

func build_settings() -> void:
	var full := CheckButton.new()
	full.text="全屏显示"
	full.button_pressed=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
	full.toggled.connect(func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	content.add_child(full)
	text("相机距离（滚轮也可调整）",18)
	var zoom := HSlider.new()
	zoom.min_value=6
	zoom.max_value=48
	zoom.value=game.zoom
	zoom.value_changed.connect(func(value): game.zoom=value)
	content.add_child(zoom)
	action("保存当前角色",func():
		var ok: bool=game.save_character()
		text("保存成功" if ok else game.saves.error,16))
	action("选择其它角色 · 保存并返回江湖名册",func(): close(); game.open_menu())
	action("退出游戏 · 保存后退出",func(): game._notification(NOTIFICATION_WM_CLOSE_REQUEST))
