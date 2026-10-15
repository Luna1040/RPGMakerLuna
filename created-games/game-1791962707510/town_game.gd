extends "res://jianghu.gd"

const Saves = preload("res://character_saves.gd")
const Portraits = preload("res://portrait_art.gd")
const NPCS := [
	{"name":"泫渤派门主","pos":Vector2(640,355),"color":"b98952","style":0,"building":"泫渤大殿"},
	{"name":"金香玉","pos":Vector2(220,380),"color":"bd6b83","style":1,"building":"香玉客栈"},
	{"name":"韦大宝","pos":Vector2(410,590),"color":"9e8e50","style":2,"building":"大宝杂货"},
	{"name":"平十指","pos":Vector2(930,390),"color":"709e89","style":3,"building":"十指医馆"},
	{"name":"刀剑笑","pos":Vector2(180,590),"color":"a16d4a","style":4,"building":"刀剑铁坊"},
	{"name":"银娇龙","pos":Vector2(970,590),"color":"9b8cb8","style":5,"building":"银龙绸庄"}
]
var saves := Saves.new()
var active_slot := 0
var character: Dictionary = {}
var quest_accepted := false
var menu: Control
var name_input: LineEdit
var profession_input: OptionButton
var menu_status: Label
var slot_buttons: Array[Button] = []
var delete_buttons: Array[Button] = []
var delete_dialog: ConfirmationDialog
var pending_delete := 0
var pending_signature := ""
var profession_preview: TextureRect
var save_timer := 0.0

func _ready() -> void:
	super._ready()
	get_tree().auto_accept_quit = false
	build_menu()
	open_menu(false)

func reset_game() -> void:
	super.reset_game()
	player = Vector2(640,450)
	facing = Vector2.UP
	quest_accepted = false
	message = "初入江湖 · 面向泫渤派门主，按 E 拜见。"

func build_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	menu = PanelContainer.new()
	menu.position = Vector2(100,38)
	menu.size = Vector2(1080,724)
	menu.add_theme_stylebox_override("panel",make_style(Color("132930")))
	layer.add_child(menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	menu.add_child(box)
	var title := Label.new()
	title.text = "江湖名册 · 最多六位角色"
	title.add_theme_font_size_override("font_size",30)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "空槽创建 / 已有角色继续 · 时间固定 UTC+8 · UTF-8 存储 · 不覆盖已有角色"
	box.add_child(hint)
	var row := HBoxContainer.new()
	box.add_child(row)
	profession_preview=TextureRect.new()
	profession_preview.custom_minimum_size=Vector2(74,92)
	profession_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	profession_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(profession_preview)
	name_input = LineEdit.new()
	name_input.placeholder_text = "输入角色名（1—12 字）"
	name_input.max_length = 12
	name_input.custom_minimum_size = Vector2(400,44)
	row.add_child(name_input)
	profession_input = OptionButton.new()
	profession_input.custom_minimum_size = Vector2(160,44)
	for profession in Saves.PROFESSIONS: profession_input.add_item(profession)
	profession_input.item_selected.connect(func(index): profession_preview.texture=Portraits.profession(Saves.PROFESSIONS[index]))
	profession_preview.texture=Portraits.profession(Saves.PROFESSIONS[0])
	row.add_child(profession_input)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	box.add_child(grid)
	for i in range(1,7):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation",4)
		grid.add_child(cell)
		var button := Button.new()
		button.custom_minimum_size = Vector2(520,99)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size",17)
		button.pressed.connect(select_slot.bind(i))
		cell.add_child(button)
		slot_buttons.append(button)
		var remove := Button.new()
		remove.text = "删除此角色…"
		remove.custom_minimum_size = Vector2(520,28)
		remove.pressed.connect(ask_delete.bind(i))
		cell.add_child(remove)
		delete_buttons.append(remove)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "确认删除角色"
	delete_dialog.get_ok_button().text = "确认删除"
	delete_dialog.get_cancel_button().text = "取消"
	delete_dialog.confirmed.connect(confirm_delete)
	delete_dialog.canceled.connect(func(): pending_delete=0; pending_signature="")
	get_viewport().gui_embed_subwindows = true
	layer.add_child(delete_dialog)
	menu_status = Label.new()
	box.add_child(menu_status)
	var back := Button.new()
	back.text = "返回当前角色（Esc）"
	back.pressed.connect(func():
		if active_slot > 0:
			menu.hide()
			paused = false
	)
	box.add_child(back)

func open_menu(logout: bool = true) -> void:
	if logout and active_slot > 0 and not save_character(true): return
	paused = true
	menu.show()
	for i in range(1,7):
		var data := saves.read_slot(i)
		var problem := saves.error
		var button := slot_buttons[i-1]
		delete_buttons[i-1].disabled = not (FileAccess.file_exists(saves.path_for(i)) or FileAccess.file_exists(saves.path_for(i)+".bak") or FileAccess.file_exists(saves.path_for(i)+".tmp"))
		button.disabled = data.is_empty() and not problem.is_empty()
		if data.is_empty():
			button.text = "  %d / 空槽 · 创建新角色" % i if problem.is_empty() else "  %d / %s" % [i,problem]
		else:
			button.text = "  %d / %s · %s · Lv.%d\n  创建 %s\n  下线 %s\n  点击继续江湖" % [i,data.name,Saves.display_profession(data.profession),data.level,data.created_at.replace("T"," "),"尚未下线" if data.last_offline_at.is_empty() else data.last_offline_at.replace("T"," ")]
	menu_status.text = "填写姓名与职业后点击空槽。F5 保存；F6 保存下线并打开名册。"

func ask_delete(slot: int) -> void:
	if not menu.visible or slot<1 or slot>6: return
	var data := saves.read_slot(slot)
	pending_delete=slot
	pending_signature=saves.deletion_signature(slot)
	var name := str(data.get("name","损坏的存档"))
	delete_dialog.dialog_text="确定删除槽位 %d 的角色「%s」吗？\n角色将从名册移除，删除后该槽位可以重新创建。\n取消不会更改存档。" % [slot,name]
	delete_dialog.popup_centered(Vector2i(600,220))
	delete_dialog.get_cancel_button().grab_focus()

func confirm_delete() -> void:
	if pending_delete==0: return
	var slot := pending_delete
	pending_delete=0
	if saves.deletion_signature(slot)!=pending_signature:
		menu_status.text="存档在确认期间发生变化，请重新确认。"
		return
	if not saves.delete_slot(slot):
		menu_status.text=saves.error
		return
	if active_slot==slot:
		active_slot=0
		character={}
		reset_game()
		paused=true
	open_menu(false)
	menu_status.text="槽位 %d 已删除，可以创建新角色。" % slot

func select_slot(slot: int) -> void:
	var data := saves.read_slot(slot)
	if data.is_empty() and not saves.error.is_empty():
		menu_status.text = saves.error
		return
	if data.is_empty():
		# Validate before resetting the currently selected character.
		var clean := name_input.text.strip_edges()
		if clean.is_empty():
			menu_status.text = "请先输入角色名。"
			return
		var old_progress := snapshot()
		reset_game()
		data = saves.create(slot,clean,profession_input.get_item_text(profession_input.selected),snapshot())
		if data.is_empty():
			restore(old_progress)
			menu_status.text = saves.error
			return
	character = data
	active_slot = slot
	restore(data.progress)
	level = int(data.level)
	menu.hide()
	paused = false
	save_timer = 0
	queue_redraw()

func snapshot() -> Dictionary:
	var saved_enemies: Array = []
	for enemy in enemies:
		var copy := enemy.duplicate(true)
		copy.pos = [enemy.pos.x,enemy.pos.y]
		copy.target = [enemy.target.x,enemy.target.y]
		saved_enemies.append(copy)
	var saved_drops: Array = []
	for drop in drops: saved_drops.append({"pos":[drop.pos.x,drop.pos.y],"value":drop.value})
	return {"player":[player.x,player.y],"facing":[facing.x,facing.y],"hp":hp,"qi":qi,"level":level,"exp":exp_points,"coins":coins,"potions":potions,"stage":stage,"state":state,"kills":kills,"elapsed":elapsed,"quest":quest_accepted,"message":message,"enemies":saved_enemies,"drops":saved_drops,"attack_cd":attack_cd,"skill_cd":skill_cd,"dash_cd":dash_cd,"invincible":invincible}

func restore(data: Dictionary) -> void:
	reset_game()
	player = Vector2(data.player[0],data.player[1])
	facing = Vector2(data.facing[0],data.facing[1])
	hp = float(data.hp)
	qi = float(data.qi)
	level = int(data.level)
	exp_points = int(data.exp)
	coins = int(data.coins)
	potions = int(data.potions)
	stage = int(data.stage)
	state = str(data.state)
	kills = int(data.kills)
	elapsed = float(data.elapsed)
	quest_accepted = bool(data.quest)
	message = str(data.message)
	attack_cd = float(data.get("attack_cd",0))
	skill_cd = float(data.get("skill_cd",0))
	dash_cd = float(data.get("dash_cd",0))
	invincible = float(data.get("invincible",0))
	for source in data.enemies:
		var enemy: Dictionary = source.duplicate(true)
		enemy.pos = Vector2(source.pos[0],source.pos[1])
		enemy.target = Vector2(source.target[0],source.target[1])
		enemies.append(enemy)
	for drop in data.drops: drops.append({"pos":Vector2(drop.pos[0],drop.pos[1]),"value":drop.value})

func save_character(logout: bool = false) -> bool:
	if active_slot == 0: return false
	var stamp := Saves.utc_plus_8(int(Time.get_unix_time_from_system()))
	character.level = level
	character.progress = snapshot()
	character.saved_at = stamp
	if logout: character.last_offline_at = stamp
	var success := saves.write_slot(active_slot,character)
	if not success: message = saves.error
	elif not logout: message = "角色已保存 · 槽位 %d · %s" % [active_slot,stamp]
	return success

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if active_slot == 0 or save_character(true): get_tree().quit()

func _exit_tree() -> void:
	if active_slot > 0: save_character(true)

func _unhandled_input(event: InputEvent) -> void:
	if delete_dialog!=null and delete_dialog.visible: return
	if menu != null and menu.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and active_slot > 0:
			menu.hide()
			paused = false
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			save_character()
			return
		if event.keycode == KEY_F6:
			open_menu()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point := get_global_mouse_position()
		if Rect2(830,25,180,38).has_point(point):
			open_menu()
			return
		if Rect2(830,70,180,38).has_point(point):
			save_character()
			return
		if Rect2(830,115,180,38).has_point(point):
			paused = not paused
			return
		if Rect2(1080,25,155,42).has_point(point): return
	super._unhandled_input(event)

func interact() -> void:
	if stage != 0:
		super.interact()
		return
	var nearest: Dictionary = {}
	var distance := 100.0
	for npc in NPCS:
		var d := player.distance_to(npc.pos)
		if d < distance:
			distance = d
			nearest = npc
	if not nearest.is_empty():
		match nearest.name:
			"泫渤派门主":
				quest_accepted = true
				message = "门主：欢迎入派！拜访城中诸位后，从右侧城门出城剿匪。"
			"金香玉": message = "金香玉：客栈歇息，恢复生命与内力。"; hp = max_hp(); qi = 100
			"韦大宝":
				if coins >= 15: coins -= 15; potions += 1; message = "韦大宝：15 镖银购得一瓶金创药。"
				else: message = "韦大宝：金创药每瓶 15 镖银，出城挣些盘缠吧。"
			"平十指": hp = max_hp(); message = "平十指：伤势已经治好，初入江湖免费问诊。"
			"刀剑笑": message = "刀剑笑：J 挥刀，Q 气功；升级提升伤害。各职业目前共用试炼招式。"
			"银娇龙": message = "银娇龙：F5 保存角色，F6 保存下线并切换角色，最多六位。"
	elif player.x > 1100 and quest_accepted:
		stage = 1
		player = Vector2(160,470)
		spawn_wave()
	else: message = "靠近 NPC 按 E；先拜见门主，随后从右侧城门出发。"

func strike(skill: bool) -> void:
	if stage == 0:
		message = "城中为安全区，请出城后切磋。"
		return
	super.strike(skill)

func clamp_position(p: Vector2) -> Vector2:
	var result := super.clamp_position(p)
	if stage != 0: return result
	for npc in NPCS:
		var body := Rect2(npc.pos+Vector2(-70,-125),Vector2(140,92))
		if body.grow(14).has_point(result): return player
	return result

func _process(dt: float) -> void:
	super._process(dt)
	if state == "play" and not paused and active_slot > 0:
		save_timer += dt
		if save_timer >= 30:
			save_timer = 0
			save_character()

func minimap_point(p: Vector2) -> Vector2:
	return Vector2(1057,63) + (p-FIELD.position)/FIELD.size*Vector2(178,115)

func draw_minimap() -> void:
	panel(Rect2(1040,20,205,192))
	label_at(Vector2(1055,47),"泫渤派城" if stage == 0 else ["","泫渤山道","竹林险路","赤风山寨"][stage],19,Color("f4d08d"))
	draw_rect(Rect2(1057,63,178,115),Color("455d58"))
	if stage == 0:
		for npc in NPCS:
			var at := minimap_point(npc.pos)
			draw_circle(at,3,Color("f1ca7a"))
			label_at(at+Vector2(4,-3),"门主" if npc.style==0 else npc.name.left(1),12)
	else:
		for enemy in enemies: draw_circle(minimap_point(enemy.pos),3,Color("e78772"))
	draw_circle(minimap_point(player),5,Color("80eff6"))
	draw_line(minimap_point(player),minimap_point(player)+facing*9,Color.WHITE,2)
	label_at(Vector2(1057,199),"蓝:自己  金:NPC  红:敌",13)

func draw_building(npc: Dictionary) -> void:
	var p: Vector2 = npc.pos
	var style: int = npc.style
	var roof_color: Color = [Color("647768"),Color("a77763"),Color("7c7353"),Color("647b87"),Color("555b60"),Color("78749a")][style]
	draw_rect(Rect2(p+Vector2(-66,-120),Vector2(132,79)),Color("b7a17f"))
	for x in [-48,48]: draw_line(p+Vector2(x,-119),p+Vector2(x,-40),Color("593e32"),7)
	draw_rect(Rect2(p+Vector2(-16,-89),Vector2(32,48)),Color("48342e"))
	for x in [-43,30]:
		draw_rect(Rect2(p+Vector2(x,-99),Vector2(17,25)),Color("4e665f"))
		draw_line(p+Vector2(x+8,-99),p+Vector2(x+8,-74),Color("bfaa82"),2)
	var peak := -177 if style == 0 else (-150 if style in [1,5] else -140)
	draw_colored_polygon(PackedVector2Array([p+Vector2(-84,-115),p+Vector2(-60,-143),p+Vector2(0,peak),p+Vector2(60,-143),p+Vector2(84,-115)]),roof_color)
	draw_polyline(PackedVector2Array([p+Vector2(-84,-122),p+Vector2(-72,-113),p+Vector2(72,-113),p+Vector2(84,-122)]),Color("d2b788"),3)
	for x in range(-60,61,15): draw_line(p+Vector2(x,-135),p+Vector2(x+6,-115),roof_color.lightened(0.15),2)
	if style == 0:
		draw_colored_polygon(PackedVector2Array([p+Vector2(-62,-151),p+Vector2(0,-195),p+Vector2(62,-151)]),roof_color)
	if style == 1: # Inn lanterns.
		for x in [-65,65]: draw_circle(p+Vector2(x,-88),9,Color("dc7860"))
	if style == 2:
		for x in [-57,39]: draw_rect(Rect2(p+Vector2(x,-41),Vector2(20,18)),Color("92734d"))
	if style == 3: label_at(p+Vector2(-56,-64),"药",22,Color("315c42"))
	if style == 4:
		draw_rect(Rect2(p+Vector2(49,-60),Vector2(18,26)),Color("4c4240"))
		draw_circle(p+Vector2(58,-52),5,Color("df9157"))
	if style == 5:
		for x in [-61,-45]: draw_rect(Rect2(p+Vector2(x,-68),Vector2(10,30)),Color("b18ca3"))
	label_at(p+Vector2(-55,-107),npc.building,17,Color("fff0ca"))

func _draw() -> void:
	if stage != 0:
		super._draw()
		draw_rect(Rect2(50,59,395,32),Color("152b31"))
		label_at(Vector2(55,81),"%s · %s · Lv.%d  镖银 %d" % [character.get("name","侠客"),character.get("profession","刀客"),level,coins],17)
	else:
		draw_rect(Rect2(0,0,1280,800),Color("0c1b23"))
		draw_rect(FIELD,Color("85877b"))
		for row in range(12):
			for col in range(20):
				var offset := 29 if row%2 else 0
				draw_rect(Rect2(55+col*60+offset,220+row*38,57,35),Color("939488") if (row+col)%3 else Color("a3a18e"))
		var objects: Array[Dictionary] = []
		for npc in NPCS: objects.append({"type":"building","y":npc.pos.y-33,"npc":npc})
		for npc in NPCS: objects.append({"type":"npc","y":npc.pos.y,"npc":npc})
		objects.append({"type":"player","y":player.y})
		objects.sort_custom(func(a,b): return a.y < b.y)
		for item in objects:
			if item.type == "building": draw_building(item.npc)
			elif item.type == "npc":
				var npc: Dictionary = item.npc
				fighter(npc.pos,Color(npc.color),false)
				label_at(npc.pos+Vector2(-55,22),npc.name,18,Color("fff0c3"))
				if player.distance_to(npc.pos)<100: label_at(npc.pos+Vector2(-18,43),"E 对话",16,Color("173e38"))
			else:
				fighter(player,Color("3c9baf"),true)
				label_at(player+Vector2(-35,22),str(character.get("name","侠客")),18,Color("e5ffff"))
		label_at(Vector2(1090,446),"东城门",22,Color("332b24"))
		label_at(Vector2(1060,476),"E · 出城剿匪",18,Color("332b24"))
		panel(Rect2(35,20,780,78))
		label_at(Vector2(55,53),"热血江湖 / 泫渤派",27,Color("f3cf88"))
		label_at(Vector2(55,81),"%s · %s · Lv.%d   镖银 %d" % [character.get("name","侠客"),character.get("profession","刀客"),level,coins],18)
		bar(Vector2(460,40),Vector2(210,14),hp/max_hp(),Color("d66b62"))
		bar(Vector2(460,67),Vector2(210,10),qi/100,Color("58bdc6"))
		label_at(Vector2(680,52),"生命 %d" % hp,16)
		label_at(Vector2(680,79),"内力 %d" % qi,16)
		panel(Rect2(35,115,780,85))
		label_at(Vector2(55,147),"初入江湖 · 石板长街",23,Color("f3cf88"))
		label_at(Vector2(55,180),message,17)
		panel(Rect2(35,690,1210,90))
		label_at(Vector2(55,724),"WASD / 方向键 移动   E 对话 / 出城   F5 保存   F6 名册 / 下线   Esc 暂停",21)
		label_at(Vector2(55,756),"2.5D 斜俯视 · 按脚底深度遮挡 · 建筑有碰撞 · 美术仍为临时绘制",18,Color("a6c4bf"))
		if paused and (menu == null or not menu.visible):
			draw_rect(FIELD,Color(0.02,0.06,0.09,0.8))
			label_at(Vector2(460,410),"已暂停 · Esc 继续",30)
	# Cover old top-right controls in the retained battle HUD.
	draw_rect(Rect2(820,15,430,198),Color("0c1b23"))
	for i in range(3): panel(Rect2(830,25+i*45,180,38))
	label_at(Vector2(841,50),"F6 · 名册 / 下线",18)
	label_at(Vector2(841,95),"F5 · 保存角色",18)
	label_at(Vector2(841,140),"Esc · 继续" if paused else "Esc · 暂停",18)
	draw_minimap()
