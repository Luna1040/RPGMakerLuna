extends Node2D
const ClassProfile=preload("res://class_profile.gd")
const Spells=preload("res://spell_system.gd")
var spell_ui=preload("res://spell_ui.gd").new()
const SlotIcon=preload("res://slot_icon.gd")
const Progress=preload("res://progression_system.gd")
const Dungeon=preload("res://dungeon_system.gd")
var dungeon_world=preload("res://dungeon_world.gd").new()
var next_encounter: Dictionary={}
var battle_spec: Dictionary={}
const Wild=preload("res://wild_spawns.gd")
var respawn_clock:=0.0
const Retainers=preload("res://retainer_system.gd")
var retainer_ui=preload("res://retainer_ui.gd").new()
var battle_retainer_units: Array=[]
var battle_retainer_nodes: Array=[]
var map_retainer_nodes: Array=[]
const Estate = preload("res://estate_system.gd")
var estate_ui = preload("res://estate_ui.gd").new()
var bag_page:=0

const Store = preload("res://save_store.gd")
const Gear = preload("res://equipment_system.gd")
const PROFESSIONS := ["剑仙", "阴阳", "魅影", "天师"]
const REALMS := ["炼气", "筑基", "金丹", "元婴"]
var store := Store.new()
var character: Dictionary = {}
var slot := -1
var screen: Control
var name_input: LineEdit
var profession_input: OptionButton
var details: Label
var journal: RichTextLabel
var enemy_hp := 0
var max_enemy_hp := 0
var save_status: Label
var attack_button: Button
var skill_button: Button
var trial_button: Button
var cultivate_button: Button
var cooldown := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	RenderingServer.set_default_clear_color(Color("18232b"))
	get_viewport().size_changed.connect(func():
		if is_instance_valid(screen): screen.size = get_viewport_rect().size
	)
	show_slots()

func label_text(parent: Node, value: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func button(parent: Node, value: String, callback: Callable) -> Button:
	var control := Button.new()
	control.text = value
	control.custom_minimum_size = Vector2(0, 44)
	control.pressed.connect(callback)
	parent.add_child(control)
	return control

func new_screen(title: String) -> VBoxContainer:
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	screen.size = get_viewport_rect().size
	add_child(screen)
	var background := TextureRect.new()
	background.texture = load("res://assets/city.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.modulate = Color(0.42, 0.52, 0.57)
	screen.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	screen.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	label_text(box, title, 32)
	return box

func show_slots() -> void:
	close_menu()
	mode="slots"
	var box := new_screen("凡人修真 · 角色")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	box.add_child(grid)
	for index in range(Store.SLOT_COUNT):
		var data: Dictionary = store.load_slot(index)
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(395, 270)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		panel.add_child(inner)
		label_text(inner, "角色 %d" % (index + 1), 18)
		if data.is_empty():
			label_text(inner, "空位", 26)
			button(inner, "创建角色", create_character.bind(index))
		elif data.get("corrupt", false):
			label_text(inner, "存档无法读取")
			button(inner, "删除损坏存档", confirm_delete.bind(index))
		else:
			label_text(inner, "%s · %s\n等级 %d" % [data.name, profession_name(str(data.profession)), data.level], 24)
			label_text(inner, "创建：%s\n下线：%s" % [data.created_at, data.logged_out_at if data.logged_out_at else "尚未下线"], 15)
			button(inner, "进入修真界", enter_character.bind(index))
			button(inner, "删除角色", confirm_delete.bind(index))
	label_text(box, "UTC+8", 15)

func confirm_delete(index: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "确定删除角色 %d？此操作无法撤销。" % (index + 1)
	dialog.confirmed.connect(func():
		if store.delete_slot(index): show_slots()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func create_character(index: int) -> void:
	slot = index
	var box := new_screen("凡人修真 · 初入仙途")
	label_text(box, "道号")
	name_input = LineEdit.new()
	name_input.max_length = 12
	name_input.placeholder_text = "请输入角色名"
	name_input.custom_minimum_size = Vector2(0, 48)
	box.add_child(name_input)
	label_text(box, "职业")
	profession_input = OptionButton.new()
	profession_input.custom_minimum_size = Vector2(0, 48)
	for profession in PROFESSIONS: profession_input.add_item(profession)
	box.add_child(profession_input)
	save_status = label_text(box, "")
	button(box, "踏入仙途", finish_creation)
	button(box, "返回", show_slots)
	name_input.grab_focus()

func finish_creation() -> void:
	var name_value := name_input.text.strip_edges()
	if name_value.is_empty():
		save_status.text = "请先填写道号"
		return
	player_pos=Vector2(620,610)
	character = {"name": name_value, "profession": PROFESSIONS[profession_input.selected], "level": 1,
		"created_at": store.timestamp(), "logged_out_at": "", "xp": 0, "stones": 0, "hp": 100, "victories": 0}
	migrate()
	if persist(): show_world()

func enter_character(index: int) -> void:
	slot = index
	character = store.load_slot(index)
	if character.is_empty() or character.get("corrupt", false): return
	if not character.has("stones"): character.stones=int(character.get("gold",0))
	for key in {"xp": 0, "stones": 0, "hp": 100, "victories": 0}:
		if not character.has(key): character[key] = {"xp": 0, "stones": 0, "hp": 100, "victories": 0}[key]
	migrate()
	apply_settings()
	player_pos=Vector2(character.position[0],character.position[1])
	show_world()

func migrate() -> void:
	if character.has("profession"): character.profession=profession_name(str(character.profession))
	if not character.has("stones"): character.stones=int(character.get("gold",0))
	character.erase("gold")
	if not character.has("equipment"): character.equipment=["","","","","","","",""]
	if not character.has("inventory"):
		character.inventory=[]
		for i in range(500): character.inventory.append({})
	Gear.normalize(character)
	Estate.normalize(character)
	Spells.normalize(character)
	var new_retainer_offers: bool=int(character.get("level",1))>=10 and not character.get("retainers",{}).get("initialized",false)
	Retainers.normalize(character)
	if not character.has("accepted_tasks"): character.accepted_tasks=[]
	if not character.has("settings"): character.settings={"volume":0.8,"mute":false,"fullscreen":false}
	for key in {"quest":0,"zone":"town","field_quest":0,"cleared":[],"position":[620,610],"sect_quest":0,"realm":"凡人"}:
		if not character.has(key): character[key] = {"quest":0,"zone":"town","field_quest":0,"cleared":[],"position":[620,610],"sect_quest":0,"realm":"凡人"}[key]
	if int(character.get("progression_version",0))<2:
		# Recalculate only the old tutorial/field progression, once per save.
		var base: int=[1,2,3,4,4,5][mini(int(character.quest),5)]
		var earned:=0
		for group in character.cleared:
			if int(group)>=0 and int(group)<3: earned+=MONSTER_XP[int(group)]
		if int(character.field_quest)==4: earned+=FIELD_COMPLETION_XP
		character.level=base+earned/100
		character.xp=earned%100
		character.hp=max_hp()
		character.progression_version=2
	var new_respawn_state:=not character.has("monster_respawns")
	Wild.normalize(character,int(Time.get_unix_time_from_system()))
	Dungeon.normalize(character,int(Time.get_unix_time_from_system()))
	var new_balance_state:=Progress.normalize(character)
	if new_balance_state: character.hp=mini(int(character.hp),max_hp())
	if character.get("zone","")=="cavern" and character.dungeon.run.is_empty(): character.zone="wilds"
	var gifted:=Gear.grant_gifts(character)
	if (gifted or new_retainer_offers or new_respawn_state or new_balance_state) and slot>=0 and character.has_all(["name","profession","created_at","logged_out_at"]): store.save_slot(slot,character)

const MONSTER_LEVELS := [5,7,9]
const MONSTER_XP := [60,84,108]
const FIELD_COMPLETION_XP := 248
const DUNGEON_REWARD_MULTIPLIER := 5
const SECT_POS := [Vector2(570,535),Vector2(780,590),Vector2(960,410)]
const ZONES := {
	"town":{"title":"青牛镇 · 山村初识","background":"res://assets/town.png","names":TOWN_NAMES,"positions":TOWN_POS,"portraits":[1,2,3,4,5]},
	"field":{"title":"云雾山 · 初试锋芒","background":"res://assets/field.png","names":["林守卫","云游道长"],"positions":FIELD_POS,"portraits":[6,5]},
	"sect":{"title":"青云宗 · 修仙之始","background":"res://assets/sect.png","names":["接引长老","传功师姐","散修执事"],"positions":SECT_POS,"portraits":[5,2,6]},
	"wilds":{"title":"镇妖谷 · 万妖窟外","background":"res://assets/demon-valley.png","names":["镇妖使"],"positions":[Vector2(320,480)],"portraits":[6]},
	"cavern":{"title":"万妖窟 · 三层试炼","background":"res://assets/demon-cavern.png","names":[],"positions":[],"portraits":[]}
}
# New maps declare their gates here and share arrival-triggered transport.
const PORTALS := {
	"town":[{"id":"town_field","position":Vector2(95,535),"target":"field","spawn":Vector2(210,590),"label":"云雾山","level":5,"tutorial":true}],
	"field":[{"id":"field_town","position":Vector2(160,590),"target":"town","spawn":Vector2(155,555),"label":"青牛镇","level":1}, {"id":"field_sect","position":Vector2(1130,595),"target":"sect","spawn":Vector2(250,590),"label":"青云宗 · 10级","level":10}],
	"sect":[{"id":"sect_field","position":Vector2(160,590),"target":"field","spawn":Vector2(1070,595),"label":"云雾山","level":1},{"id":"sect_wilds","position":Vector2(1125,555),"target":"wilds","spawn":Vector2(180,560),"label":"镇妖谷 · 10级","level":10}],
	"wilds":[{"id":"wilds_sect","position":Vector2(125,560),"target":"sect","spawn":Vector2(1020,550),"label":"青云宗","level":10}]
}

func add_experience(amount: int) -> void:
	if Progress.add(character,amount): character.hp=max_hp()

func npc_has_task(index: int) -> bool:
	if character.zone in ["wilds","cavern"]: return false
	if character.zone=="town": return index==int(character.quest) and int(character.quest)<5
	if character.zone=="field":
		return (index==0 and int(character.field_quest) in [0,3]) or (index==1 and int(character.field_quest)==1 and 0 in character.cleared)
	return int(character.level)>=10 and ((index==0 and int(character.sect_quest)>=2 and foundation_task_ready()) or (index==2 and not character.retainers.introduced) or (index==0 and int(character.sect_quest)==0) or (index==1 and int(character.sect_quest)==1))

func click_area(parent: Node, rect: Rect2, action: Callable, title: String) -> Button:
	var hit:=Button.new()
	hit.name="ClickArea"
	hit.position=rect.position
	hit.size=rect.size
	hit.flat=true
	hit.tooltip_text=title
	hit.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	hit.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","focus"]: hit.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	hit.pressed.connect(action)
	parent.add_child(hit)
	return hit

func add_portal(data: Dictionary) -> void:
	var holder:=Control.new()
	holder.position=data.position
	holder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(holder)
	var vortex:=Sprite2D.new()
	vortex.texture=texture_file("res://assets/portal.png")
	vortex.scale=Vector2(88,100)/vortex.texture.get_size()
	vortex.position=Vector2(0,-40)
	var glow:=CanvasItemMaterial.new()
	glow.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	vortex.material=glow
	holder.add_child(vortex)
	var caption:=Label.new()
	caption.text=data.label
	caption.position=Vector2(-90,12)
	caption.size=Vector2(180,28)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",16)
	caption.add_theme_color_override("font_color",Color("baf5ff"))
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",2)
	caption.add_theme_constant_override("shadow_offset_y",2)
	caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	holder.add_child(caption)
	click_area(holder,Rect2(-90,-90,180,135),travel.bind(data.position,"portal:"+data.id),"前往"+data.label)

func use_portal(id: String) -> void:
	if id.begins_with("extra_"):
		dungeon_world.handle(id.trim_prefix("extra_")); return
	for data in PORTALS.get(character.zone,[]):
		if data.id!=id: continue
		if player_pos.distance_to(data.position)>8:
			travel(data.position,"portal:"+id)
			return
		if int(character.level)<int(data.level) or (data.get("tutorial",false) and int(character.quest)<5):
			dialog("传送尚未开放","完成当前地图历练，达到%d级后可前往%s。" % [data.level,data.label],"继续历练",close_dialog)
			return
		character.zone=data.target
		player_pos=data.spawn
		character.hp=max_hp()
		persist()
		show_world()
		return

var map_layer: Control
var avatar: Control
var player_pos := Vector2(620,610)
var destination := Vector2(620,610)
var pending := ""
var modal: PanelContainer
var quest_label: Label
var status_label: Label
var mode := "slots"
var battle_group := -1
var round_number := 0
var battle_clock := 0.0
var combat_hp := 0
var battle_log: RichTextLabel
var combat_status: Label
var return_pos := Vector2.ZERO
var settled := false
const TOWN_NAMES := ["韩村长", "柳药师", "张铁匠", "阿绣", "墨先生"]
const TOWN_POS := [Vector2(315,415),Vector2(520,350),Vector2(995,485),Vector2(400,580),Vector2(705,315)]
const FIELD_POS := [Vector2(280,360),Vector2(1005,345)]
const NPC_APPROACH := Vector2(0,38)
const NPC_DIALOG_RADIUS := 48.0
const MAP_ACTOR_SIZE := Vector2(48,72)
const GROUP_POS := [Vector2(375,460),Vector2(650,620),Vector2(1040,495)]
const MONSTERS := ["山林灰狼", "侵山妖狼", "狼王与群狼"]
const QUESTS := ["拜访韩村长，领取入门介绍信", "把介绍信交给柳药师，领取药包", "将药包送给张铁匠，领取练习剑", "携练习剑找阿绣，领取山路地图", "把地图交给墨先生，完成引气入体", "新手任务已完成（5级），点击左下桥头云雾漩涡前往云雾山"]

func panel_at(parent: Node, pos: Vector2, dimensions: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.size = dimensions
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.09,0.12,0.94)
	style.border_color = Color("b69a5b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left=16
	style.content_margin_right=16
	style.content_margin_top=12
	style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	return panel

func texture_file(path: String) -> Texture2D:
	return ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path)))

func background(path: String) -> void:
	close_menu()
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen=Control.new()
	screen.size=Vector2(1280,800)
	add_child(screen)
	var image:=TextureRect.new()
	image.texture=texture_file(path) if FileAccess.file_exists(path) else load("res://assets/city.png")
	image.size=Vector2(1280,800)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	screen.add_child(image)
	modal=null

func actor(parent: Node, index: int, pos: Vector2, title: String, scale_value: float=1.0) -> Control:
	var holder:=Control.new()
	holder.position=pos
	holder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var portrait_path: String="res://assets/characters/%d.png" % index
	if FileAccess.file_exists(portrait_path):
		var source: Texture2D=texture_file(portrait_path)
		var portrait:=Sprite2D.new()
		portrait.name="Portrait"
		portrait.texture=source
		var display_size:=Vector2(76,50) if index==7 else MAP_ACTOR_SIZE
		portrait.scale=display_size*scale_value/source.get_size()
		portrait.position=Vector2(0,-display_size.y*scale_value/2.0)
		holder.add_child(portrait)
	var nameplate:=Label.new()
	nameplate.text=title
	nameplate.position=Vector2(-70,3)
	nameplate.mouse_filter=Control.MOUSE_FILTER_IGNORE
	nameplate.add_theme_font_size_override("font_size",14)
	nameplate.size=Vector2(140,30)
	nameplate.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	nameplate.add_theme_color_override("font_color",Color("fff2b5"))
	nameplate.add_theme_color_override("font_shadow_color",Color.BLACK)
	nameplate.add_theme_constant_override("shadow_offset_x",2)
	nameplate.add_theme_constant_override("shadow_offset_y",2)
	holder.add_child(nameplate)
	return holder

func show_world() -> void:
	migrate()
	mode="map"
	pending=""
	destination=player_pos
	var zone: Dictionary=ZONES[character.zone]
	background(zone.background)
	map_layer=Control.new()
	map_layer.size=Vector2(1280,800)
	map_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	screen.add_child(map_layer)
	map_retainer_nodes=[]
	for i in range(character.retainers.following.size()):
		var unit: Dictionary=character.retainers.following[i]
		map_retainer_nodes.append(actor(map_layer,int(unit.portrait),player_pos+Vector2(-45-i*32,16),unit.name,0.85))
	var town: bool=character.zone=="town"
	var names: Array=zone.names
	var locations: Array=zone.positions
	for i in range(names.size()):
		var npc:=actor(map_layer,int(zone.portraits[i]),locations[i],names[i])
		if npc_has_task(i):
			var mark:=Label.new()
			mark.text="?"
			mark.name="QuestMarker"
			mark.position=Vector2(-20,-110)
			mark.size=Vector2(40,32)
			mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			mark.add_theme_font_size_override("font_size",26)
			mark.add_theme_color_override("font_color",Color("ffe300"))
			mark.add_theme_color_override("font_shadow_color",Color.BLACK)
			mark.add_theme_constant_override("shadow_offset_x",2)
			mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
			npc.add_child(mark)
		click_area(npc,Rect2(-70,-76,140,106),travel.bind(locations[i]+NPC_APPROACH,"npc:"+str(i)),names[i])
	for data in PORTALS.get(character.zone,[]): add_portal(data)
	if character.zone=="field":
		for i in range(3):
			var cleared: bool=monster_dead(i)
			var monster:=actor(map_layer,7,GROUP_POS[i],MONSTERS[i]+" Lv.%d" % MONSTER_LEVELS[i]+(" · 已击杀" if cleared else " ×3"))
			monster.name="Monster%d" % i
			if cleared:
				var shader:=Shader.new()
				shader.code="shader_type canvas_item; void fragment(){ vec4 c = texture(TEXTURE, UV); float gray = dot(c.rgb, vec3(0.299,0.587,0.114)); COLOR = vec4(vec3(gray * 0.65), c.a); }"
				var material:=ShaderMaterial.new()
				material.shader=shader
				monster.get_node("Portrait").material=material
			click_area(monster,Rect2(-85,-54,170,84),travel.bind(GROUP_POS[i]+Vector2(-55,35),"monster:"+str(i)),MONSTERS[i])
	dungeon_world.draw(self)
	avatar=player_actor(map_layer,player_pos,character.name)
	var top:=panel_at(screen,Vector2(20,18),Vector2(920,70))
	var topbox:=VBoxContainer.new()
	top.add_child(topbox)
	label_text(topbox,"凡人修真  /  "+str(zone.title),25)
	status_label=label_text(topbox,"",16)
	var taskpanel:=panel_at(screen,Vector2(20,650),Vector2(1240,60))
	var taskbox:=VBoxContainer.new()
	taskpanel.add_child(taskbox)
	quest_label=label_text(taskbox,"",18)
	label_text(taskbox,"点击NPC或名字靠近对话 · 点击地图漩涡传送 · 菜单快捷键见下方",14)
	add_menu_bar()
	refresh_map()

func refresh_map() -> void:
	status_label.text="%s · %s   等级 %d   经验 %d/100   %s   气血 %d   灵石 %d" % [character.name,character.profession,character.level,character.xp,character.realm,character.hp,character.stones]
	if int(character.level)==20 and not Progress.foundation(character): status_label.text+=" · 瓶颈：请到洞府突破"
	if character.zone=="town":
		quest_label.text="主线 · "+QUESTS[mini(int(character.quest),5)]
	elif character.zone=="field":
		var stage:=int(character.field_quest)
		var text: String="拜访林守卫，领取山林除妖任务"
		if stage==1: text="击败第一堆灰狼，再向云游道长复命"
		elif stage==2: text="听从道长指引，击败其余两堆妖狼（%d/3）" % character.cleared.size()
		elif stage==3: text="三堆怪物已平定，向林守卫领取奖励"
		elif stage==4: text="云雾山任务完成！点击东北漩涡前往青云宗，接取练气入门任务"
		quest_label.text="历练 · "+text
	elif character.zone in ["wilds","cavern"]:
		quest_label.text=dungeon_world.status()
	else:
		quest_label.text=["仙途 · 达到10级，拜访接引长老","仙途 · 已入练气期，拜访传功师姐学习周天功法","仙途 · 入门功法已掌握，修仙之路正式开启"][mini(int(character.sect_quest),2)]
		if int(character.sect_quest)>=2: quest_label.text=["筑基之约 · 拜访接引长老接取二十级筑基指引","筑基之约 · 将修为提升至20级后拜访接引长老","三灵归元 · 通关万妖窟收种，种药炼筑基丹，再找长老","洞府筑基 · 到仙园洞府突破，筑基成功后向长老复命","仙途 · 筑基任务完成，继续研习本职业筑基仙法"][clampi(int(character.foundation_quest),0,4)]

func travel(pos: Vector2, interaction: String) -> void:
	if mode!="map" or is_instance_valid(modal) or is_instance_valid(menu_layer): return
	destination=pos
	pending=interaction

func _unhandled_input(event: InputEvent) -> void:
	if mode!="map" or is_instance_valid(modal) or is_instance_valid(menu_layer): return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point:=get_global_mouse_position()
		if point.y>130 and point.y<640:
			destination=Vector2(clampf(point.x,100,1170),clampf(point.y,220,640))
			pending=""

func _process(delta: float) -> void:
	estate_ui.tick(delta)
	retainer_ui.update_cooldown()
	respawn_clock+=delta
	if respawn_clock>=1 and mode=="map" and not character.is_empty() and not is_instance_valid(menu_layer) and not is_instance_valid(modal):
		respawn_clock=0
		if Wild.expire(character,int(Time.get_unix_time_from_system())):
			var previous_destination:=destination
			var previous_pending:=pending
			persist()
			show_world()
			destination=previous_destination
			pending=previous_pending
	if mode=="map" and is_instance_valid(avatar) and not is_instance_valid(modal) and not is_instance_valid(menu_layer):
		player_pos=player_pos.move_toward(destination,260*delta)
		avatar.position=player_pos+Vector2(0,sin(Time.get_ticks_msec()/240.0)*3)
		for i in range(map_retainer_nodes.size()):
			if is_instance_valid(map_retainer_nodes[i]): map_retainer_nodes[i].position=map_retainer_nodes[i].position.move_toward(player_pos+Vector2(-45-i*32,16),220*delta)
		if player_pos.distance_to(destination)<2 and not pending.is_empty():
			var action:=pending
			pending=""
			interact(action)
	elif mode=="battle":
		advance_battle(delta)

func close_dialog() -> void:
	if is_instance_valid(modal):
		screen.remove_child(modal)
		modal.queue_free()
	modal=null

func dialog(title: String, text: String, action_text: String, callback: Callable) -> void:
	close_dialog()
	modal=panel_at(screen,Vector2(320,220),Vector2(640,310))
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",18)
	modal.add_child(box)
	label_text(box,title,28)
	label_text(box,text,21)
	button(box,action_text,callback)
	button(box,"暂时离开",close_dialog)

func interact(action: String) -> void:
	if action.begins_with("extra:"):
		dungeon_world.handle(action.trim_prefix("extra:")); return
	if action.begins_with("portal:"):
		use_portal(action.get_slice(":",1))
	elif action=="exit":
		# Legacy action routes through the shared approach/arrival logic.
		var gates: Array=PORTALS.get(character.zone,[])
		if not gates.is_empty(): use_portal(gates[0].id)
	elif action.begins_with("npc:"):
		talk(int(action.get_slice(":",1)))
	elif action.begins_with("monster:"):
		var group:=int(action.get_slice(":",1))
		if group<0 or group>=MONSTERS.size() or character.zone!="field": return
		if monster_dead(group):
			dialog("已经击杀",MONSTERS[group]+"已经击杀，无法再次战斗。","知道了",close_dialog)
			return
		if int(character.field_quest)==0 or (group>0 and int(character.field_quest)<2):
			dialog("尚未领取任务","先听取"+("林守卫" if int(character.field_quest)==0 else "云游道长")+"的指引。","明白了",close_dialog)
		else:
			start_battle(group)

func talk(index: int) -> void:
	var locations: Array=ZONES[character.zone].positions
	if index<0 or index>=locations.size(): return
	if player_pos.distance_to(locations[index])>NPC_DIALOG_RADIUS:
		travel(locations[index]+NPC_APPROACH,"npc:"+str(index))
		return
	if character.zone=="wilds":
		dialog("镇妖使","万妖窟每日基础五次挑战，UTC+8零点重置。可花3000灵石增加一次当日挑战；完整通关后可花1000灵石速刷，仍消耗一次挑战。三层均需击败四堆小怪，再击败妖王。逍遥套装含头冠、护腕、腰带、鞋履；均为蓝色、10级可装备。暂离可继续原进度，不再扣次。完整通关得200经验，十级起五次升到二十级。三层BOSS各掉一种筑基药种，种植炼丹后，到仙园洞府突破筑基。","明白了",close_dialog)
		return
	if character.zone=="sect":
		if index==2:
			dialog("散修执事","十级后可招募散修。招募后先进入备战，再设为随行。练气可带1位，筑基2位，金丹3位，元婴及以上4位。随行散修一同战斗，获得双倍战斗经验。","了解 · 打开散修",open_retainer_guide)
		elif int(character.level)<10:
			dialog("接引长老","需达到10级才能拜入仙门。","继续历练",close_dialog)
		elif index==0 and int(character.sect_quest)==0:
			dialog("接引长老","凡尘历练已满。拜入青云宗，纳天地灵气，自此进入练气期。再向传功师姐学习周天功法。","接取 · 修仙之路",advance_sect.bind(1))
		elif index==0 and int(character.sect_quest)>=2:
			foundation_dialog()
		elif index==1 and int(character.sect_quest)==1:
			accept_task("sect_lesson")
			dialog("传功师姐","周天运气是修炼的根基。战斗仙法需从野怪获取本职业玉简，按K学习。同名玉简可继续升级；筑基后再研习筑基仙法。","完成 · 领悟周天功法",advance_sect.bind(2))
		else: dialog(str(ZONES.sect.names[index]),"静心修炼，仙途漫漫。", "继续",close_dialog)
		return
	if character.zone=="town":
		var q:=int(character.quest)
		if q==index:
			var lines: Array=["山路妖气渐浓。拿着我的介绍信，去找柳药师。","村长托你来得正好。把这包疗伤药送给张铁匠。","有了药包，我便可继续锻剑。这柄练习剑请交阿绣验看。","剑已备好。这幅山路地图带给墨先生，他会教你引气。","心静气沉，感应天地。你已完成镇中历练，可前往云雾山除妖。另赠蓝色仙缘灵剑，请到背包穿戴。"]
			accept_task("town_%d" % index)
			dialog(TOWN_NAMES[index],lines[index],"完成任务 · 领取修为",complete_town.bind(index))
		else:
			dialog(TOWN_NAMES[index],"你已完成我的托付。" if index<q else "先完成前一位村民的托付，再来找我。", "继续",close_dialog)
	else:
		var stage:=int(character.field_quest)
		if index==0 and stage==0:
			dialog("林守卫","灰狼侵扰山道。先清除第一堆灰狼，再找云游道长请教对付妖狼的方法。","领取除妖任务",advance_field.bind(1))
		elif index==1 and stage==1 and 0 in character.cleared:
			dialog("云游道长","你已掌握战斗诀窍。余下两堆妖狼需逐一击破，我为你恢复气血。","领取后续任务",advance_field.bind(2))
		elif index==0 and stage==3:
			accept_task("field_return")
			dialog("林守卫","三处妖患尽除！这是你的历练奖励：248经验、100灵石及蓝色仙缘道袍。至此可达到10级，前往青云宗拜师。","领取奖励",advance_field.bind(4))
		else:
			dialog("林守卫" if index==0 else "云游道长",quest_label.text,"继续历练",close_dialog)

func complete_town(index: int) -> void:
	if int(character.quest)!=index: return
	character.quest=index+1
	character.level=maxi(int(character.level),[2,3,4,4,5][index])
	character.hp=max_hp()
	character.stones=int(character.stones)+20
	Gear.grant_gifts(character)
	persist()
	show_world()

func advance_field(stage: int) -> void:
	if stage==1 and int(character.field_quest)!=0: return
	if stage==2 and (int(character.field_quest)!=1 or not 0 in character.cleared): return
	if stage==4 and int(character.field_quest)!=3: return
	character.field_quest=stage
	character.hp=max_hp()
	if stage==4:
		add_experience(FIELD_COMPLETION_XP)
		character.stones=int(character.stones)+100
	Gear.grant_gifts(character)
	persist()
	show_world()

func start_battle(group: int) -> void:
	if next_encounter.is_empty():
		if character.zone!="field" or group<0 or group>=3: return
		if monster_dead(group) or int(character.field_quest)==0 or (group>0 and int(character.field_quest)<2): return
		battle_spec={"zone":"field","level":MONSTER_LEVELS[group],"count":3,"name":MONSTERS[group],"hp":160+group*70,"damage":12+group*7,"background":"res://assets/battle.png"}
	else:
		battle_spec=next_encounter; next_encounter={}
	return_pos=player_pos
	battle_group=group
	round_number=0
	settled=false
	combat_hp=int(character.hp)
	max_enemy_hp=int(battle_spec.hp)
	enemy_hp=max_enemy_hp
	battle_clock=0
	mode="battle"
	background(str(battle_spec.background))
	battle_player=player_actor(screen,Vector2(320,570),character.name,2.4)
	battle_retainer_units=character.retainers.following.duplicate(true)
	battle_retainer_nodes=[]
	for i in range(battle_retainer_units.size()):
		var unit: Dictionary=battle_retainer_units[i]
		unit.combat_hp=Retainers.stats(unit).hp
		battle_retainer_nodes.append(actor(screen,int(unit.portrait),Vector2(100+i*110,340),unit.name+" Lv.%d" % unit.level,1.4))
	battle_enemies=[]
	for i in range(int(battle_spec.count)): battle_enemies.append(actor(screen,7,Vector2(850+i*100,500+i*50),str(battle_spec.name)+" Lv.%d" % int(battle_spec.level),2.5 if battle_spec.get("boss",false) else 1.6))
	battle_effects=Control.new()
	battle_effects.name="BattleEffects"
	battle_effects.mouse_filter=Control.MOUSE_FILTER_IGNORE
	screen.add_child(battle_effects)
	phase=0
	phase_time=0
	round_active=false
	quick_mode=false
	player_hit_done=false
	enemy_hit_done=false
	battle_home=[battle_player.position]
	battle_static=[]
	for holder in [battle_player]+battle_enemies:
		var portrait: Sprite2D=holder.get_node("Portrait")
		battle_static.append({"texture":portrait.texture,"position":portrait.position,"scale":portrait.scale,"centered":portrait.centered})
	for enemy in battle_enemies: battle_home.append(enemy.position)
	var class_action:=load_battle_action("classes/"+ClassProfile.role(character))
	actions={"sword":(load_battle_action("sword") if ClassProfile.role(character)=="sword" else {}) if class_action.is_empty() else class_action,"bite":load_battle_action("bite")}
	quick_button=Button.new()
	quick_button.name="QuickBattle"
	quick_button.text="快速战斗"
	quick_button.tooltip_text="按相同规则立即结算剩余回合，奖励不变"
	quick_button.position=Vector2(1020,30)
	quick_button.size=Vector2(220,52)
	quick_button.pressed.connect(quick_battle)
	screen.add_child(quick_button)
	var header:=panel_at(screen,Vector2(30,25),Vector2(940,90))
	var headbox:=VBoxContainer.new()
	header.add_child(headbox)
	label_text(headbox,str(battle_spec.name)+" / 自动回合战斗",28)
	combat_status=label_text(headbox,"",20)
	var logpanel:=panel_at(screen,Vector2(40,620),Vector2(1200,155))
	battle_log=RichTextLabel.new()
	battle_log.custom_minimum_size=Vector2(1100,125)
	battle_log.scroll_following=true
	battle_log.add_theme_font_size_override("normal_font_size",19)
	logpanel.add_child(battle_log)
	battle_log.append_text("战斗开始。双方按回合自动行动。\n")
	update_combat()

func update_combat() -> void:
	combat_status.text="第 %d 回合   我方气血 %d   敌方总气血 %d/%d" % [round_number,combat_hp,enemy_hp,max_enemy_hp]

# Both presentation and quick combat call these same deterministic hit rules.
func begin_round() -> void:
	if round_active: return
	round_number+=1
	round_active=true
	player_hit_done=false
	enemy_hit_done=false

func resolve_player_hit(visual: bool) -> void:
	if player_hit_done or enemy_hp<=0 or combat_hp<=0: return
	player_hit_done=true
	var damage:=mini(enemy_hp,32+int(character.level)*3+int(gear_stats().attack)+(18 if round_number%3==0 else 0)+int(Spells.action(character,round_number).damage))
	enemy_hp-=damage
	var spell:=Spells.action(character,round_number)
	combat_hp=mini(max_hp(),combat_hp+int(spell.heal))
	if not quick_mode and int(spell.level)>0: battle_log.append_text("施展%s Lv.%d：恢复%d气血，本回合减伤%d。\n" % [spell.name,spell.level,spell.heal,spell.guard])
	for i in range(battle_retainer_units.size()):
		var unit: Dictionary=battle_retainer_units[i]
		if int(unit.combat_hp)<=0 or enemy_hp<=0: continue
		var support:=mini(enemy_hp,int(Retainers.stats(unit).attack))
		enemy_hp-=support
		if not quick_mode: battle_log.append_text("%s 助战，造成%d伤害。\n" % [unit.name,support])
		if visual:
			show_damage(battle_enemies[target_enemy()].position+Vector2(0,-35-i*24),support,false)
			var support_node: Control=battle_retainer_nodes[i]
			var home:=support_node.position
			var motion:=support_node.create_tween()
			motion.tween_property(support_node,"position",battle_enemies[target_enemy()].position+Vector2(-100,-40),0.15)
			motion.tween_property(support_node,"position",home,0.2)
	if not quick_mode: battle_log.append_text("第%d回合 · 挥剑造成%d伤害。\n" % [round_number,damage])
	if visual:
		show_damage(battle_enemies[target_enemy()].position,damage,false)
		show_impact(battle_enemies[target_enemy()].position,false)
	update_combat()

func resolve_enemy_hit(visual: bool) -> void:
	if enemy_hit_done or enemy_hp<=0 or combat_hp<=0: return
	enemy_hit_done=true
	if not battle_retainer_units.is_empty() and round_number%2==0:
		var index: int=(round_number/2-1)%battle_retainer_units.size()
		var unit: Dictionary=battle_retainer_units[index]
		if int(unit.combat_hp)>0:
			var harm:=mini(int(unit.combat_hp),maxi(1,int(battle_spec.get("damage",12+battle_group*7))-int(Retainers.stats(unit).defense)))
			unit.combat_hp-=harm
			if not quick_mode: battle_log.append_text("%s 受到%d伤害，气血剩余%d。\n" % [unit.name,harm,unit.combat_hp])
			if visual: show_damage(battle_retainer_nodes[index].position,harm,true)
			battle_retainer_nodes[index].modulate=Color(0.4,0.4,0.4) if int(unit.combat_hp)<=0 else Color.WHITE
			update_combat(); return
	var damage:=mini(combat_hp,maxi(1,int(battle_spec.get("damage",12+battle_group*7))-int(gear_stats().defense)-int(Spells.action(character,round_number).guard)))
	combat_hp-=damage
	if not quick_mode: battle_log.append_text("妖狼撕咬，造成%d伤害。\n" % damage)
	if visual:
		show_damage(battle_player.position,damage,true)
		show_impact(battle_player.position,true)
	update_combat()

func battle_turn() -> void:
	if mode!="battle": return
	if enemy_hp<=0 or combat_hp<=0:
		settle_battle()
		return
	begin_round()
	resolve_player_hit(false)
	resolve_enemy_hit(false)
	round_active=false
	if enemy_hp==0 or combat_hp==0: settle_battle()

func quick_battle() -> void:
	if mode!="battle" or settled: return
	quick_mode=true
	quick_button.disabled=true
	for child in battle_effects.get_children():
		battle_effects.remove_child(child)
		child.queue_free()
	# Complete any partly presented round without repeating an applied hit.
	while mode=="battle": battle_turn()
	battle_log.text="快速战斗结束 · 共%d回合\n%s\n剩余气血 %d" % [round_number,"战斗胜利" if enemy_hp==0 else "战斗失利",combat_hp]

func encounter_rewards(level: int, count: int, kind: String="wild") -> Dictionary:
	var multiplier:=DUNGEON_REWARD_MULTIPLIER if kind=="dungeon" else 1
	var experience:=maxi(1,level)*4*maxi(0,count)*multiplier
	if kind=="wild" and int(character.get("level",1))>=10: experience=mini(6,maxi(0,count)*2)
	return {"xp":experience,"stones":maxi(1,level)*2*maxi(0,count)*multiplier}

func settle_battle() -> void:
	if settled: return
	settled=true
	mode="result"
	if is_instance_valid(quick_button): quick_button.disabled=true
	reset_battle_poses()
	if battle_spec.get("zone","field")!="field":
		dungeon_world.settle(); return
	var rewards:=encounter_rewards(MONSTER_LEVELS[battle_group],3)
	var won:=enemy_hp==0
	var loot: Array=[]
	character.hp=maxi(combat_hp,1)
	if won:
		if not monster_dead(battle_group):
			Wild.killed(character,battle_group,int(Time.get_unix_time_from_system()))
			if not battle_group in character.cleared: character.cleared.append(battle_group)
			character.victories=int(character.victories)+1
			character.stones=int(character.stones)+int(rewards.stones)
			add_experience(int(rewards.xp))
			Retainers.award_battle(character,int(rewards.xp))
			loot=Gear.roll_wild(character,MONSTER_LEVELS[battle_group],3)
			loot.append_array(Spells.drop_wild(character,3))
			if character.cleared.size()==3 and int(character.field_quest)<3: character.field_quest=3
	else: character.hp=max_hp()
	persist()
	dialog("战斗胜利" if won else "战斗失利", "击杀3只%d级野怪 · 获得%d经验、%d灵石。\n共%d回合，当前等级%d。确认后返回地图。" % [MONSTER_LEVELS[battle_group],rewards.xp,rewards.stones,round_number,character.level] if won else "道长助你调息。未获得奖励，可回地图再次挑战。", "确定 · 返回地图",return_from_battle)
	if won:
		if not character.retainers.following.is_empty(): label_text(modal.get_child(0),"每位随行散修获得%d经验（双倍战斗经验）" % (int(rewards.xp)*2),16)
		var names: PackedStringArray=[]
		for item in loot: names.append(item.name)
		label_text(modal.get_child(0),"装备掉落："+("无" if names.is_empty() else "、".join(names))+ ("（背包满时已转待领取）" if not character.pending_loot.is_empty() else ""),16)
	# Settlement must be acknowledged before returning to the map.
	var box: VBoxContainer=modal.get_child(0)
	box.get_child(3).queue_free()

func return_from_battle() -> void:
	player_pos=return_pos
	show_world()

func advance_sect(stage: int) -> void:
	if int(character.level)<10 or int(character.sect_quest)!=stage-1: return
	character.sect_quest=stage
	if not Progress.foundation(character): character.realm="练气期"
	if stage==2: character.stones=int(character.stones)+100
	persist()
	show_world()

func persist() -> bool:
	if character.is_empty(): return false
	character.position=[player_pos.x,player_pos.y]
	var success: bool=store.save_slot(slot,character)
	if is_instance_valid(save_status): save_status.text="已保存" if success else store.last_error
	return success

func logout() -> void:
	character.logged_out_at=store.timestamp()
	if persist():
		character={}
		gear_notice=""
		slot=-1
		mode="slots"
		show_slots()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not character.is_empty():
			character.logged_out_at=store.timestamp()
			if not persist(): return
		get_tree().quit()

const MENU_NAMES := ["人物","散修","背包","仙园","任务","仙法","系统"]
const MENU_KEYS := [KEY_C,KEY_R,KEY_TAB,KEY_H,KEY_Q,KEY_K,KEY_ESCAPE]
const MENU_HINTS := ["C","R","Tab","H","Q","K","Esc"]
const EQUIPMENT_NAMES := ["武器","头冠","衣服","护腕","腰带","鞋履","戒指","护符"]
var menu_layer: Control
var menu_window: PanelContainer
var active_menu := -1
var task_list: VBoxContainer
var task_category := "可接任务"
var menu_error: Label

func profession_name(value: String) -> String:
	return {"剑修":"剑仙","法修":"阴阳","体修":"天师"}.get(value,value)

func add_menu_bar() -> void:
	var panel:=panel_at(screen,Vector2(20,720),Vector2(1240,70))
	panel.name="MenuBar"
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	panel.add_child(row)
	for i in range(MENU_NAMES.size()):
		var item:=Button.new()
		item.name="Menu%d" % i
		item.custom_minimum_size=Vector2(163,48)
		item.tooltip_text=MENU_NAMES[i]+" ["+MENU_HINTS[i]+"]"
		item.focus_mode=Control.FOCUS_NONE
		item.pressed.connect(toggle_menu.bind(i))
		row.add_child(item)
		if FileAccess.file_exists("res://assets/menu-icons.png"):
			var texture:=texture_file("res://assets/menu-icons.png")
			var atlas:=AtlasTexture.new()
			atlas.atlas=texture
			atlas.region=Rect2(Vector2(i*texture.get_width()/7.0,0),Vector2(texture.get_width()/7.0,texture.get_height()))
			var icon:=Sprite2D.new()
			icon.texture=atlas
			icon.position=Vector2(30,24)
			icon.scale=Vector2(42,42)/atlas.get_size()
			item.add_child(icon)
		var caption:=Label.new()
		caption.text=MENU_NAMES[i]+" ["+MENU_HINTS[i]+"]"
		caption.position=Vector2(58,12)
		caption.add_theme_font_size_override("font_size",17)
		caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
		item.add_child(caption)

func _input(event: InputEvent) -> void:
	if character.is_empty() or mode!="map": return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	var code: int=event.keycode if event.keycode!=0 else event.physical_keycode
	if is_instance_valid(modal):
		if code==KEY_ESCAPE:
			close_dialog()
			get_viewport().set_input_as_handled()
		return
	if code==KEY_ESCAPE and is_instance_valid(menu_layer):
		close_menu()
		get_viewport().set_input_as_handled()
		return
	var index:=MENU_KEYS.find(code)
	if index>=0:
		toggle_menu(index,false)
		get_viewport().set_input_as_handled()

func close_menu() -> void:
	if is_instance_valid(menu_layer):
		menu_layer.get_parent().remove_child(menu_layer)
		menu_layer.queue_free()
	menu_layer=null
	menu_window=null
	active_menu=-1

func toggle_menu(index: int, reset_page: bool=true) -> void:
	if mode!="map" or is_instance_valid(modal) or index<0 or index>=MENU_NAMES.size(): return
	if is_instance_valid(menu_layer) and active_menu==index:
		close_menu()
		return
	close_menu()
	if reset_page and index==2: bag_page=0
	if reset_page and index==3: estate_ui.section=""
	active_menu=index
	menu_layer=Control.new()
	menu_layer.name="MenuOverlay"
	menu_layer.size=Vector2(1280,712)
	menu_layer.mouse_filter=Control.MOUSE_FILTER_STOP
	screen.add_child(menu_layer)
	var dim:=ColorRect.new()
	dim.color=Color(0,0,0,0.42)
	dim.size=menu_layer.size
	menu_layer.add_child(dim)
	menu_window=panel_at(menu_layer,Vector2(255,110),Vector2(770,525))
	var content:=VBoxContainer.new()
	content.name="Content"
	content.add_theme_constant_override("separation",14)
	menu_window.add_child(content)
	var heading:=HBoxContainer.new()
	content.add_child(heading)
	var title:=label_text(heading,MENU_NAMES[index]+"  ["+MENU_HINTS[index]+"]",27)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(heading,"关闭 [Esc]",close_menu)
	match index:
		0: build_character_menu(content)
		1: retainer_ui.build(self,content)
		2: build_inventory_menu(content)
		3: estate_ui.build(self,content)
		4: build_task_menu(content)
		5: spell_ui.build(self,content)
		6: build_system_menu(content)
		_: label_text(content,"暂无内容",22)

func build_character_menu(content: VBoxContainer) -> void:
	content.add_theme_constant_override("separation",10)
	label_text(content,"%s · %s    %s / 等级%d" % [character.name,character.profession,character.realm,character.level],23)
	var stats:=gear_stats()
	label_text(content,"气血 %d/%d    攻击 %d (+%d)    防御 %d\n经验 %d/100    战斗胜场 %d    灵石 %d" % [character.hp,max_hp(),32+int(character.level)*3+int(stats.attack),stats.attack,stats.defense,character.xp,character.victories,character.stones],17)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",20)
	content.add_child(row)
	var preview:=Control.new()
	preview.custom_minimum_size=Vector2(180,190)
	row.add_child(preview)
	player_actor(preview,Vector2(90,160),character.name,2.0)
	var grid:=GridContainer.new()
	grid.name="EquipmentSlots"
	grid.columns=4
	grid.add_theme_constant_override("h_separation",10)
	grid.add_theme_constant_override("v_separation",10)
	row.add_child(grid)
	for i in range(8):
		var item: Dictionary=character.equipment[i]
		var equipment:=Button.new()
		equipment.custom_minimum_size=Vector2(117,82)
		equipment.tooltip_text=Gear.describe(item)+("\n点击卸下" if Gear.valid(item) else "")
		equipment.pressed.connect(unequip_slot.bind(i))
		grid.add_child(equipment)
		decorate_gear_cell(equipment,item,i,true)
	var set_text: String="套装：未激活"
	if int(stats.sets.get("xianyuan",0))>0:
		set_text="仙缘套装 %d/2 · " % int(stats.sets.xianyuan)+("2件已激活：攻击+8 防御+4 气血+40" if int(stats.sets.xianyuan)>=2 else "2件效果：攻击+8 防御+4 气血+40")
	if int(stats.sets.get("xiaoyao",0))>0: set_text=("" if set_text=="套装：未激活" else set_text+"\n")+"逍遥 %d/4 · 2件攻击+12防御+8气血+60；4件额外攻击+25防御+15气血+120" % int(stats.sets.xiaoyao)
	label_text(content,set_text,17)
	label_text(content,gear_notice if not gear_notice.is_empty() else "点击身上的装备卸下；悬停查看属性与套装效果",16)

func build_inventory_menu(content: VBoxContainer) -> void:
	estate_ui.game=self
	content.add_theme_constant_override("separation",8)
	var grid:=GridContainer.new()
	grid.name="InventorySlots"
	grid.columns=10
	content.add_child(grid)
	for i in range(bag_page*50,(bag_page+1)*50):
		var cell:=Button.new()
		cell.custom_minimum_size=Vector2(69,48)
		var item: Dictionary=character.inventory[i]
		cell.tooltip_text=Estate.describe(item)
		cell.pressed.connect(use_bag_item.bind(i))
		grid.add_child(cell)
		if Gear.valid(item): decorate_gear_cell(cell,item,int(item.slot),false)
		else:
			decorate_gear_cell(cell,{},0,false)
		if not Gear.valid(item) and not item.is_empty():
			var material_icon: Texture2D=estate_ui.item_icon(item)
			if material_icon!=null:
				var picture:=SlotIcon.add_to(cell,material_icon,Rect2(3,10,24,24))
				if item.get("kind","")=="fragment": picture.modulate=Color(Gear.QUALITY_COLORS[int(item.get("quality",0))])
				var caption:=Label.new(); caption.text=str(item.get("name","物品"))+"\n×"+str(item.get("qty",1))
				caption.position=Vector2(28,3); caption.size=Vector2(39,44); caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				caption.add_theme_font_size_override("font_size",10); caption.mouse_filter=Control.MOUSE_FILTER_IGNORE; cell.add_child(caption)
			else: cell.text=str(item.get("name","物品"))+"\n×"+str(item.get("qty",1))
			cell.add_theme_font_size_override("font_size",11)
	var pages:=HBoxContainer.new()
	content.add_child(pages)
	button(pages,"上一页",change_bag_page.bind(-1))
	var page_label:=label_text(pages,"第 %d / 10 页" % (bag_page+1),17)
	page_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(pages,"下一页",change_bag_page.bind(1))
	var occupied:=0
	for item in character.inventory:
		if not item.is_empty(): occupied+=1
	label_text(content,"容量 %d/500 · 每页50格 · 待领取 %d" % [occupied,character.pending_loot.size()],16)
	if not character.pending_loot.is_empty(): button(content,"领取待领物品",claim_pending_equipment)
	var assets:=label_text(content,"人物资产 · 灵石 %d" % character.stones,22)
	assets.name="GoldBalance"
	var currency_icon: Texture2D=estate_ui.item_icon({"id":"stones"})
	if currency_icon!=null:
		SlotIcon.add_to(assets,currency_icon,Rect2(340,0,24,24))
	label_text(content,gear_notice if not gear_notice.is_empty() else "点击装备穿戴、丹药服用；材料在仙园使用",14)

func change_bag_page(step: int) -> void:
	bag_page=clampi(bag_page+step,0,9)
	refresh_gear_panel(2)

func use_bag_item(index: int) -> void:
	if Gear.valid(character.inventory[index]): equip_from_bag(index)
	elif character.inventory[index].get("kind","")=="spell_manual":
		spell_ui.game=self
		spell_ui.learn(str(character.inventory[index].id),2)
	elif character.inventory[index].get("kind","")=="breakthrough_pill":
		gear_notice="筑基丹请到仙园洞府突破时使用，每次最多一枚"
		refresh_gear_panel(2)
	elif character.inventory[index].get("kind","")=="potion":
		var before:=character.duplicate(true)
		character.hp=mini(max_hp(),int(character.hp)+int(character.inventory[index].get("heal",50)))
		Estate.take_slot(character.inventory,index,1)
		if not persist(): character=before
		refresh_gear_panel(2)

func accept_task(id: String) -> void:
	if not id in character.accepted_tasks:
		character.accepted_tasks.append(id)
		persist()

func get_task_groups() -> Dictionary:
	var result: Dictionary={"可接任务":[],"已接任务":[],"已完成任务":[]}
	for i in range(5):
		var status: String="已完成任务" if i<int(character.quest) else ("已接任务" if "town_%d" % i in character.accepted_tasks else "可接任务")
		if i<=int(character.quest): result[status].append({"title":QUESTS[i],"npc":TOWN_NAMES[i],"zone":"town","index":i})
	var stage:=int(character.field_quest)
	if int(character.quest)>=5:
		result["已完成任务" if 0 in character.cleared else ("已接任务" if stage>=1 else "可接任务")].append({"title":"山林除妖 · 击败第一堆灰狼","npc":"林守卫","zone":"field","index":0})
	if 0 in character.cleared:
		result["已完成任务" if character.cleared.size()==3 else ("已接任务" if stage>=2 else "可接任务")].append({"title":"道长指引 · 平定其余两堆妖狼","npc":"云游道长","zone":"field","index":1})
	if character.cleared.size()==3:
		result["已完成任务" if stage==4 else ("已接任务" if "field_return" in character.accepted_tasks else "可接任务")].append({"title":"守卫复命 · 领取历练奖励","npc":"林守卫","zone":"field","index":0})
	if int(character.level)>=10:
		result["已完成任务" if int(character.sect_quest)>=1 else "可接任务"].append({"title":"修仙之路 · 拜入青云宗，进入练气期","npc":"接引长老","zone":"sect","index":0})
	if int(character.sect_quest)>=1:
		result["已完成任务" if int(character.sect_quest)>=2 else ("已接任务" if "sect_lesson" in character.accepted_tasks else "可接任务")].append({"title":"周天功法 · 向传功师姐请教","npc":"传功师姐","zone":"sect","index":1})
	if int(character.sect_quest)>=2:
		var step:=int(character.foundation_quest)
		var titles: Array=["筑基之约 · 达到20级拜访接引长老","三灵归元 · 集齐药种并炼制筑基丹","洞府筑基 · 突破筑基后向长老复命"]
		for i in range(3):
			if i>0 and step<i+1: continue
			var status: String="已完成任务" if step>=i+2 else ("已接任务" if step==i+1 else "可接任务")
			result[status].append({"title":titles[i],"npc":"接引长老","zone":"sect","index":0})
	return result

func build_task_menu(content: VBoxContainer) -> void:
	var tabs:=HBoxContainer.new()
	tabs.name="TaskTabs"
	content.add_child(tabs)
	var groups:=get_task_groups()
	for category in ["可接任务","已接任务","已完成任务"]:
		button(tabs,"%s (%d)" % [category,groups[category].size()],show_task_category.bind(category))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(730,360)
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	task_list=VBoxContainer.new()
	task_list.name="TaskList"
	task_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	task_list.add_theme_constant_override("separation",12)
	scroll.add_child(task_list)
	show_task_category(task_category)

func show_task_category(category: String) -> void:
	task_category=category
	for child in task_list.get_children():
		task_list.remove_child(child)
		child.queue_free()
	label_text(task_list,category,22)
	var entries: Array=get_task_groups()[category]
	if entries.is_empty(): label_text(task_list,"暂无"+category,18)
	for entry in entries:
		label_text(task_list,entry.title,19)
		label_text(task_list,"%s · %s" % [ZONES[entry.zone].title,entry.npc],16)
		if category!="已完成任务" and entry.zone==character.zone:
			button(task_list,"寻访"+entry.npc,seek_task_npc.bind(entry))

func seek_task_npc(entry: Dictionary) -> void:
	close_menu()
	travel(ZONES[entry.zone].positions[entry.index]+NPC_APPROACH,"npc:"+str(entry.index))

func build_system_menu(content: VBoxContainer) -> void:
	label_text(content,"游戏设置",22)
	label_text(content,"主音量",18)
	var volume:=HSlider.new()
	volume.name="Volume"
	volume.min_value=0
	volume.max_value=100
	volume.value=float(character.settings.volume)*100
	volume.value_changed.connect(func(value):
		character.settings.volume=value/100.0
		apply_settings()
		persist()
	)
	content.add_child(volume)
	var mute:=CheckBox.new()
	mute.name="Mute"
	mute.text="静音"
	mute.button_pressed=bool(character.settings.mute)
	mute.toggled.connect(func(value):
		character.settings.mute=value
		apply_settings()
		persist()
	)
	content.add_child(mute)
	var fullscreen:=CheckBox.new()
	fullscreen.name="Fullscreen"
	fullscreen.text="全屏显示"
	fullscreen.button_pressed=bool(character.settings.fullscreen)
	fullscreen.toggled.connect(func(value):
		character.settings.fullscreen=value
		apply_settings()
		persist()
	)
	content.add_child(fullscreen)
	label_text(content,"人物 C · 散修 R · 背包 Tab · 仙园 H · 任务 Q · 仙法 K · 系统 Esc",16)
	var commands:=HBoxContainer.new()
	content.add_child(commands)
	button(commands,"保存游戏",persist)
	button(commands,"选择其它角色",logout)
	button(commands,"退出游戏",save_and_exit)
	menu_error=label_text(content,"",16)

func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(float(character.settings.volume),0.001)))
	AudioServer.set_bus_mute(0,bool(character.settings.mute) or float(character.settings.volume)==0)
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(character.settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)

func save_and_exit() -> void:
	character.logged_out_at=store.timestamp()
	if persist(): get_tree().quit()
	elif is_instance_valid(menu_error): menu_error.text=store.last_error

var battle_player: Control
var battle_enemies: Array=[]
var battle_effects: Control
var battle_home: Array=[]
var battle_static: Array=[]
var quick_button: Button
var phase:=0
var phase_time:=0.0
var round_active:=false
var player_hit_done:=false
var enemy_hit_done:=false
var quick_mode:=false
var actions: Dictionary={}
const DamageNumber=preload("res://damage_number.gd")

func load_battle_action(id: String) -> Dictionary:
	var directory: String="res://assets/animations/"+id
	if not FileAccess.file_exists(directory+"/action.json"): return {}
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/action.json"))
	var textures: Array=[]
	for frame in spec.frames: textures.append(texture_file(directory+"/"+frame.file))
	spec.textures=textures
	return spec

func target_enemy() -> int: return (maxi(round_number,1)-1)%maxi(1,battle_enemies.size())

func phase_duration() -> float:
	if phase==6: return 1.35
	if phase in [1,4]:
		var action: Dictionary=actions.get("sword" if phase==1 else "bite",{})
		return float(action.get("duration_ms",640))/1000.0
	return 0.22

func advance_battle(delta: float) -> void:
	var remaining:=delta
	while remaining>0.00001 and mode=="battle":
		if phase==0: begin_round()
		var duration:=phase_duration()
		var step:=minf(remaining,duration-phase_time)
		phase_time+=step
		remaining-=step
		show_battle_phase(clampf(phase_time/duration,0,1))
		if phase_time>=duration-0.00001:
			phase_time=0
			if phase==6:
				settle_battle()
				return
			if phase==2 and enemy_hp==0: phase=6
			elif phase==5:
				round_active=false
				phase=6 if combat_hp==0 else 0
			else: phase+=1

func show_battle_phase(progress: float) -> void:
	var target:=target_enemy()
	var enemy: Control=battle_enemies[target]
	var player_start: Vector2=battle_home[0]
	var enemy_start: Vector2=battle_home[target+1]
	var player_strike: Vector2=enemy_start+Vector2(-120,25)
	var enemy_strike: Vector2=player_start+Vector2(125,-5)
	match phase:
		0: battle_player.position=player_start.lerp(player_strike,1.0-pow(1.0-progress,3))
		1:
			play_attack_pose(battle_player,"sword",phase_time,0)
			if phase_time>=float(actions.get("sword",{}).get("event_ms",300))/1000.0: resolve_player_hit(true)
		2:
			restore_battle_actor(battle_player,0)
			battle_player.position=player_strike.lerp(player_start,progress)
		3: enemy.position=enemy_start.lerp(enemy_strike,1.0-pow(1.0-progress,3))
		4:
			play_attack_pose(enemy,"bite",phase_time,target+1)
			if phase_time>=float(actions.get("bite",{}).get("event_ms",300))/1000.0: resolve_enemy_hit(true)
		5:
			restore_battle_actor(enemy,target+1)
			enemy.position=enemy_strike.lerp(enemy_start,progress)

func play_attack_pose(holder: Control, action_id: String, elapsed: float, actor_index: int) -> void:
	var portrait: Sprite2D=holder.get_node("Portrait")
	var action: Dictionary=actions.get(action_id,{})
	if action.is_empty():
		portrait.rotation=sin(elapsed/0.64*PI)*(-0.18 if action_id=="bite" else 0.18)
		return
	var frame_index:=0
	var milliseconds:=elapsed*1000
	for i in range(action.frames.size()):
		frame_index=i
		if milliseconds<float(action.frames[i].duration_ms): break
		milliseconds-=float(action.frames[i].duration_ms)
	portrait.texture=action.textures[frame_index]
	portrait.centered=false
	portrait.scale=Vector2.ONE*float(action.scale)
	portrait.position=-Vector2(action.pivot[0],action.pivot[1])*float(action.scale)

func restore_battle_actor(holder: Control, index: int) -> void:
	if not is_instance_valid(holder) or index>=battle_static.size(): return
	var portrait: Sprite2D=holder.get_node("Portrait")
	portrait.texture=battle_static[index].texture
	portrait.position=battle_static[index].position
	portrait.scale=battle_static[index].scale
	portrait.rotation=0
	portrait.centered=bool(battle_static[index].get("centered",true))

func reset_battle_poses() -> void:
	if not is_instance_valid(battle_player): return
	restore_battle_actor(battle_player,0)
	battle_player.position=battle_home[0]
	for i in range(battle_enemies.size()):
		restore_battle_actor(battle_enemies[i],i+1)
		battle_enemies[i].position=battle_home[i+1]

func show_damage(foot: Vector2, damage: int, against_player: bool) -> void:
	var number:=DamageNumber.new()
	number.name="DamageNumber"
	number.text="-%d" % damage
	number.position=foot+Vector2(-80,-155)
	number.size=Vector2(160,50)
	number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size",36)
	number.add_theme_color_override("font_color",Color("ff816c") if against_player else Color("ffe989"))
	number.add_theme_color_override("font_shadow_color",Color.BLACK)
	number.add_theme_constant_override("shadow_offset_x",3)
	number.add_theme_constant_override("shadow_offset_y",3)
	battle_effects.add_child(number)

func show_impact(foot: Vector2, bite: bool) -> void:
	var effect:=Node2D.new()
	effect.position=foot+Vector2(0,-65)
	battle_effects.add_child(effect)
	for i in range(2):
		var stroke:=Line2D.new()
		stroke.width=4
		stroke.default_color=Color("ffb5a0") if bite else Color("eafcff")
		stroke.points=PackedVector2Array([Vector2(-25,-12+i*24),Vector2(-12,10-i*10),Vector2(0,-6),Vector2(12,10-i*10),Vector2(25,-12+i*24)]) if bite else PackedVector2Array([Vector2(-40,-35+i*65),Vector2(40,35-i*65)])
		effect.add_child(stroke)
	var tween:=effect.create_tween()
	tween.tween_property(effect,"modulate:a",0.0,0.25)
	tween.tween_callback(effect.queue_free)

var gear_notice: String=""
func gear_stats() -> Dictionary:
	var result:=Gear.totals(character.get("equipment",[]))
	var realm_stats:=Progress.realm_stats(character)
	for key in ["attack","defense","hp"]: result[key]+=int(realm_stats[key])
	return result

func max_hp() -> int:
	return 100+int(character.get("level",1))*10+int(gear_stats().hp)

func decorate_gear_cell(cell: Button, item: Dictionary, slot_id: int, equipped: bool) -> void:
	cell.clip_contents=true
	var exists:=Gear.valid(item)
	var color:=Color(Gear.QUALITY_COLORS[int(item.quality)]) if exists else Color("9ab7c5")
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("162a32")
	style.border_color=color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	cell.add_theme_stylebox_override("normal",style)
	var hover:=style.duplicate()
	hover.bg_color=Color("304850")
	cell.add_theme_stylebox_override("hover",hover)
	if exists and FileAccess.file_exists("res://assets/equipment-icons.png"):
		var xiaoyao: bool=item.get("set_id","")=="xiaoyao" and FileAccess.file_exists("res://assets/xiaoyao-icons.png")
		var texture:=texture_file("res://assets/xiaoyao-icons.png" if xiaoyao else "res://assets/equipment-icons.png")
		var atlas:=AtlasTexture.new()
		atlas.atlas=texture
		var size:=Vector2(texture.get_width()/4.0,texture.get_height()/(1.0 if xiaoyao else 2.0))
		atlas.region=Rect2(Vector2([1,3,4,5].find(slot_id),0)*size,size) if xiaoyao else Rect2(Vector2(slot_id%4,slot_id/4)*size,size)
		SlotIcon.add_to(cell,atlas,Rect2(6,12,30,30))
	var nameplate:=Label.new()
	nameplate.mouse_filter=Control.MOUSE_FILTER_IGNORE
	nameplate.text=(Gear.SLOT_NAMES[slot_id]+"\n未装备") if equipped and not exists else (str(item.get("name","")) if exists else "")
	nameplate.position=Vector2(35,5) if exists else Vector2(6,6)
	nameplate.size=Vector2(69 if equipped else 28,68 if equipped else 40)
	nameplate.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	nameplate.add_theme_font_size_override("font_size",13 if equipped else 12)
	nameplate.add_theme_color_override("font_color",color)
	cell.add_child(nameplate)

func refresh_gear_panel(index: int) -> void:
	if is_instance_valid(menu_layer):
		close_menu()
		toggle_menu(index,false)
	if is_instance_valid(status_label): refresh_map()

func equip_from_bag(index: int) -> bool:
	if mode!="map" or index<0 or index>=500 or not Gear.valid(character.inventory[index]): return false
	if int(character.level)<int(character.inventory[index].level):
		gear_notice="等级不足，需要%d级" % int(character.inventory[index].level)
		refresh_gear_panel(2)
		return false
	var previous:=character.duplicate(true)
	var item: Dictionary=character.inventory[index]
	var target:=int(item.slot)
	character.inventory[index]=character.equipment[target]
	character.equipment[target]=item
	character.hp=mini(int(character.hp),max_hp())
	var saved:=persist()
	if not saved: character=previous
	gear_notice="已穿戴："+item.name if saved else store.last_error
	refresh_gear_panel(2)
	return saved

func unequip_slot(index: int) -> bool:
	if mode!="map" or index<0 or index>=8 or not Gear.valid(character.equipment[index]): return false
	var free:=Gear.empty_bag_slot(character)
	if free<0:
		gear_notice="背包已满，请先腾出一格再卸下装备"
		refresh_gear_panel(0)
		return false
	var previous:=character.duplicate(true)
	var item: Dictionary=character.equipment[index]
	character.inventory[free]=item
	character.equipment[index]={}
	character.hp=mini(int(character.hp),max_hp())
	var saved:=persist()
	if not saved: character=previous
	gear_notice="已卸下："+item.name if saved else store.last_error
	refresh_gear_panel(0)
	return saved

func claim_pending_equipment() -> void:
	var previous:=character.duplicate(true)
	var count:=Gear.claim_pending(character)
	if not persist():
		character=previous
		gear_notice=store.last_error
	else: gear_notice="已领取%d件装备；剩余%d件待领" % [count,character.pending_loot.size()]
	refresh_gear_panel(2)

func open_retainer_guide() -> void:
	close_dialog()
	character.retainers.introduced=true
	persist()
	toggle_menu(1)


func monster_dead(group: int) -> bool:
	return Wild.dead(character,group,int(Time.get_unix_time_from_system()))


func foundation_task_ready() -> bool:
	match int(character.foundation_quest):
		0: return true
		1: return int(character.level)>=20 or Progress.foundation(character)
		2: return Estate.count(character.inventory,"breakthrough_pill","foundation")>0 or Progress.foundation(character)
		3: return Progress.foundation(character)
	return false
func foundation_dialog() -> void:
	var step:=int(character.foundation_quest)
	var lines: Array=["练气之上，便是筑基。先将修为修炼至二十级，再来寻我。十级起完整通关五次万妖窟恰可达到二十级。","二十级是练气瓶颈。万妖窟三层BOSS分别出产青髓芝、紫灵花、玄阳参种子；去仙园药园种植，每种药材三份，可在炼丹炉炼成筑基丹。","带上筑基丹，前往仙园洞府突破。不用丹成功率30%，使用一枚为80%。失败退回十九级，须重新升满二十级再试；成功后向我复命。","你已踏入筑基，仙途更进一步。这二百灵石助你继续修行。"]
	if step>=4: dialog("接引长老","筑基之路已成，继续研习本职业筑基仙法。","继续修行",close_dialog); return
	var action: String="接取 · 筑基之约" if step==0 else ("领取 · 筑基奖励" if step==3 else "完成阶段 · 继续指引")
	if not foundation_task_ready():
		dialog("接引长老",lines[maxi(0,step-1)],"继续准备",close_dialog); return
	dialog("接引长老",lines[step],action,advance_foundation.bind(step+1))
func advance_foundation(next_step: int) -> void:
	if int(character.sect_quest)<2 or next_step!=int(character.foundation_quest)+1 or not foundation_task_ready(): return
	var before:=character.duplicate(true)
	character.foundation_quest=next_step
	if next_step==4: character.stones=int(character.stones)+200
	if not persist(): character=before; return
	close_dialog(); show_world()

func player_actor(parent: Node, pos: Vector2, title: String, scale_value: float=1.0) -> Control:
	var holder:=actor(parent,0,pos,title,scale_value)
	ClassProfile.apply(holder,character,scale_value,texture_file)
	return holder
