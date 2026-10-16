from pathlib import Path
p=Path('main.gd')
s=p.read_text(encoding='utf-8-sig')
s=s[:s.index('func show_world()')]
s=s.replace('if persist(): show_world()', 'migrate()\n\tif persist(): show_world()')
s+='''func migrate() -> void:
	for key in {"quest":0,"zone":"town","field_quest":0,"cleared":[],"position":[620,610]}:
		if not character.has(key): character[key] = {"quest":0,"zone":"town","field_quest":0,"cleared":[],"position":[620,610]}[key]

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
const TOWN_POS := [Vector2(270,330),Vector2(560,310),Vector2(860,350),Vector2(400,540),Vector2(830,565)]
const FIELD_POS := [Vector2(250,340),Vector2(900,320)]
const GROUP_POS := [Vector2(420,490),Vector2(680,565),Vector2(1000,520)]
const MONSTERS := ["山林灰狼", "侵山妖狼", "狼王与群狼"]
const QUESTS := ["拜访韩村长，领取入门介绍信", "把介绍信交给柳药师，领取药包", "将药包送给张铁匠，领取练习剑", "携练习剑找阿绣，领取山路地图", "把地图交给墨先生，完成引气入体", "新手任务已完成，前往东侧出口进入云雾山"]

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

func background(path: String) -> void:
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen=Control.new()
	screen.size=Vector2(1280,800)
	add_child(screen)
	var image:=TextureRect.new()
	image.texture=load(path) if ResourceLoader.exists(path) else load("res://assets/city.png")
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
	if ResourceLoader.exists("res://assets/cast.png"):
		var atlas:=AtlasTexture.new()
		var source: Texture2D=load("res://assets/cast.png")
		atlas.atlas=source
		var cell:=Vector2(source.get_width()/4.0,source.get_height()/2.0)
		atlas.region=Rect2(Vector2(index%4,index/4)*cell,cell)
		var portrait:=TextureRect.new()
		portrait.texture=atlas
		portrait.position=Vector2(-36,-115)*scale_value
		portrait.size=Vector2(72,108)*scale_value
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
		holder.add_child(portrait)
	var nameplate:=Label.new()
	nameplate.text=title
	nameplate.position=Vector2(-70,0)
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
	background("res://assets/town.png" if character.zone=="town" else "res://assets/field.png")
	map_layer=Control.new()
	map_layer.size=Vector2(1280,800)
	map_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	screen.add_child(map_layer)
	var town: bool=character.zone=="town"
	var names: Array=TOWN_NAMES if town else ["林守卫","云游道长"]
	var locations: Array=TOWN_POS if town else FIELD_POS
	for i in range(names.size()):
		actor(map_layer,i+1 if town else (6 if i==0 else 5),locations[i],names[i])
		var hit:=Button.new()
		hit.text="对话" + (" ！" if (town and i==int(character.quest)) else "")
		hit.position=locations[i]+Vector2(-40,30)
		hit.size=Vector2(80,30)
		hit.pressed.connect(travel.bind(locations[i]+Vector2(0,85),"npc:"+str(i)))
		map_layer.add_child(hit)
	if not town:
		for i in range(3):
			var cleared: bool=i in character.cleared
			actor(map_layer,7,GROUP_POS[i],MONSTERS[i]+(" · 已平定" if cleared else " ×3"))
			var fight:=Button.new()
			fight.text="前往战斗" if not cleared else "已击败"
			fight.disabled=cleared
			fight.position=GROUP_POS[i]+Vector2(-50,30)
			fight.size=Vector2(100,30)
			fight.pressed.connect(travel.bind(GROUP_POS[i]+Vector2(-90,65),"monster:"+str(i)))
			map_layer.add_child(fight)
	avatar=actor(map_layer,0,player_pos,character.name)
	var top:=panel_at(screen,Vector2(20,18),Vector2(920,70))
	var topbox:=VBoxContainer.new()
	top.add_child(topbox)
	label_text(topbox,"凡人修真  /  "+("青牛镇 · 山村初识" if town else "云雾山 · 初试锋芒"),25)
	status_label=label_text(topbox,"",16)
	var taskpanel:=panel_at(screen,Vector2(20,665),Vector2(930,115))
	var taskbox:=VBoxContainer.new()
	taskpanel.add_child(taskbox)
	quest_label=label_text(taskbox,"",20)
	label_text(taskbox,"点击地面飘行 · 点击NPC自动靠近 · 到怪物面前再确认战斗",16)
	var controls:=panel_at(screen,Vector2(980,665),Vector2(280,115))
	var buttons:=VBoxContainer.new()
	controls.add_child(buttons)
	button(buttons,"前往云雾山" if town else "返回青牛镇",travel.bind(Vector2(1140,600),"exit"))
	button(buttons,"保存并下线",logout)
	refresh_map()

func refresh_map() -> void:
	status_label.text="%s · %s   等级 %d   气血 %d   灵石 %d" % [character.name,character.profession,character.level,character.hp,character.stones]
	if character.zone=="town":
		quest_label.text="主线 · "+QUESTS[mini(int(character.quest),5)]
	else:
		var stage:=int(character.field_quest)
		var text: String="拜访林守卫，领取山林除妖任务"
		if stage==1: text="击败第一堆灰狼，再向云游道长复命"
		elif stage==2: text="听从道长指引，击败其余两堆妖狼（%d/3）" % character.cleared.size()
		elif stage==3: text="三堆怪物已平定，向林守卫领取奖励"
		elif stage==4: text="云雾山任务完成！可返回青牛镇调息"
		quest_label.text="历练 · "+text

func travel(pos: Vector2, interaction: String) -> void:
	if mode!="map" or is_instance_valid(modal): return
	destination=pos
	pending=interaction

func _unhandled_input(event: InputEvent) -> void:
	if mode!="map" or is_instance_valid(modal): return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point:=get_global_mouse_position()
		if point.y>130 and point.y<640:
			destination=Vector2(clampf(point.x,100,1170),clampf(point.y,220,640))
			pending=""

func _process(delta: float) -> void:
	if mode=="map" and is_instance_valid(avatar) and not is_instance_valid(modal):
		player_pos=player_pos.move_toward(destination,260*delta)
		avatar.position=player_pos+Vector2(0,sin(Time.get_ticks_msec()/240.0)*3)
		if player_pos.distance_to(destination)<2 and not pending.is_empty():
			var action:=pending
			pending=""
			interact(action)
	elif mode=="battle":
		battle_clock+=delta
		if battle_clock>=0.8:
			battle_clock=0
			battle_turn()

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
	if action=="exit":
		if character.zone=="town" and (int(character.quest)<5 or int(character.level)<10):
			dialog("山路尚未开放","完成五位村民联动的新手任务，达到10级后才能出镇。","继续寻访",close_dialog)
			return
		character.zone="field" if character.zone=="town" else "town"
		player_pos=Vector2(620,610)
		if character.zone=="town": character.hp=100+int(character.level)*10
		persist()
		show_world()
	elif action.begins_with("npc:"):
		talk(int(action.get_slice(":",1)))
	elif action.begins_with("monster:"):
		var group:=int(action.get_slice(":",1))
		if int(character.field_quest)==0 or (group>0 and int(character.field_quest)<2):
			dialog("尚未领取任务","先听取"+("林守卫" if int(character.field_quest)==0 else "云游道长")+"的指引。","明白了",close_dialog)
		else:
			dialog(MONSTERS[group],"你已来到怪物面前。进入独立野外战斗空间，双方将自动轮流出手。","战斗",start_battle.bind(group))

func talk(index: int) -> void:
	if character.zone=="town":
		var q:=int(character.quest)
		if q==index:
			var lines: Array=["山路妖气渐浓。拿着我的介绍信，去找柳药师。","村长托你来得正好。把这包疗伤药送给张铁匠。","有了药包，我便可继续锻剑。这柄练习剑请交阿绣验看。","剑已备好。这幅山路地图带给墨先生，他会教你引气。","心静气沉，感应天地。你已完成镇中历练，可前往云雾山除妖。"]
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
			dialog("林守卫","三处妖患尽除！这是你的历练奖励：200修为，100灵石。","领取奖励",advance_field.bind(4))
		else:
			dialog("林守卫" if index==0 else "云游道长",quest_label.text,"继续历练",close_dialog)

func complete_town(index: int) -> void:
	if int(character.quest)!=index: return
	character.quest=index+1
	character.level=maxi(int(character.level),[3,5,7,9,10][index])
	character.hp=100+int(character.level)*10
	character.stones=int(character.stones)+20
	persist()
	show_world()

func advance_field(stage: int) -> void:
	if stage==4 and int(character.field_quest)!=3: return
	character.field_quest=stage
	character.hp=100+int(character.level)*10
	if stage==4:
		character.xp=int(character.xp)+200
		character.stones=int(character.stones)+100
	persist()
	show_world()

func start_battle(group: int) -> void:
	if group in character.cleared: return
	return_pos=player_pos
	battle_group=group
	round_number=0
	settled=false
	combat_hp=int(character.hp)
	max_enemy_hp=160+group*70
	enemy_hp=max_enemy_hp
	battle_clock=0
	mode="battle"
	background("res://assets/battle.png")
	actor(screen,0,Vector2(320,570),character.name,2.4)
	for i in range(3): actor(screen,7,Vector2(850+i*100,500+i*50),"妖狼",1.6)
	var header:=panel_at(screen,Vector2(30,25),Vector2(940,90))
	var headbox:=VBoxContainer.new()
	header.add_child(headbox)
	label_text(headbox,"云雾山 · "+MONSTERS[group]+" / 自动回合战斗",28)
	combat_status=label_text(headbox,"",20)
	var logpanel:=panel_at(screen,Vector2(40,620),Vector2(1200,155))
	battle_log=RichTextLabel.new()
	battle_log.custom_minimum_size=Vector2(1100,125)
	battle_log.scroll_following=true
	battle_log.add_theme_font_size_override("normal_font_size",19)
	logpanel.add_child(battle_log)
	battle_log.append_text("战斗开始。双方按回合自动行动。\\n")
	update_combat()

func update_combat() -> void:
	combat_status.text="第 %d 回合   我方气血 %d   敌方总气血 %d/%d" % [round_number,combat_hp,enemy_hp,max_enemy_hp]

func battle_turn() -> void:
	if mode!="battle": return
	round_number+=1
	var damage:=32+int(character.level)*3+(18 if round_number%3==0 else 0)
	enemy_hp=maxi(0,enemy_hp-damage)
	battle_log.append_text("第%d回合 · %s造成%d伤害。\\n" % [round_number,"御剑诀" if round_number%3==0 else "飞剑",damage])
	if enemy_hp>0:
		var retaliation:=12+battle_group*7
		combat_hp=maxi(0,combat_hp-retaliation)
		battle_log.append_text("妖狼反击，造成%d伤害。\\n" % retaliation)
	update_combat()
	if enemy_hp==0 or combat_hp==0: settle_battle()

func settle_battle() -> void:
	if settled: return
	settled=true
	mode="result"
	var won:=enemy_hp==0
	character.hp=maxi(combat_hp,1)
	if won:
		if not battle_group in character.cleared:
			character.cleared.append(battle_group)
			character.victories=int(character.victories)+1
			character.stones=int(character.stones)+30
			character.xp=int(character.xp)+80
			if character.cleared.size()==3: character.field_quest=3
	else: character.hp=100+int(character.level)*10
	persist()
	dialog("战斗胜利" if won else "战斗失利", "获得80修为、30灵石。进度已保存，确认后返回原位置。" if won else "道长助你调息。未获得奖励，可回地图再次挑战。", "确定 · 返回地图",return_from_battle)
	# Settlement must be acknowledged before returning to the map.
	var box: VBoxContainer=modal.get_child(0)
	box.get_child(box.get_child_count()-1).queue_free()

func return_from_battle() -> void:
	player_pos=return_pos
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
		slot=-1
		mode="slots"
		show_slots()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not character.is_empty():
			character.logged_out_at=store.timestamp()
			if not persist(): return
		get_tree().quit()
'''
p.write_text(s,encoding='utf-8')
