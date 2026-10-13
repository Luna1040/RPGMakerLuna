extends Node2D
const Physics = preload("belt_physics.gd")
const KnightScene = preload("characters/first_knight/knight.tscn")
const WorldLoot = preload("world_loot.gd")
const TownNPCs = preload("town_npcs.gd")
const MapInterface = preload("map_interface.gd")
const SprintInput = preload("sprint_input.gd")
const SkillBar = preload("skill_bar.gd")
const CombatFX = preload("combat_fx.gd")
const PracticeTargets = preload("practice_targets.gd")
const CourtyardBackdrop = preload("courtyard_backdrop.gd")
var sprint = SprintInput.new()
var skill_bar
var combat_fx
var practice
var hit_pause := 0.0
var shake_left := 0.0
var dash_fx_left := 0.0
var loot
var townsfolk
var interface
var contract: Dictionary
var volumes: Array
var bounds: Rect2
var foot := Vector2(6.5,5.6)
var height_z := 0.0
var vertical_speed := 0.0
var grounded := true
var platform := ""
var last_safe := Vector2(6.5,5.6)
var knight: CharacterBody2D
var foot_node := Node2D.new()
var sorting := Node2D.new()
var camera := Camera2D.new()
var hud := Label.new()
var minimap := preload("atlas_canvas.gd").new()

var debug_collision := false
var developer_tools
var notice := ""
var attacks := 0
var spells := 0
var projectiles: Array = []
var ppm := 120.0
var depth_scale := 45.0
var origin_y := 410.0
var capture_time := 0.0
var captured := false
var capture_mode := ""
var testing_motion := false
var test_input := Vector2.ZERO
var runtime
@export var foundations_enabled := true

func project(p: Vector2, z: float = 0.0) -> Vector2:
	return Vector2(p.x*ppm, origin_y+p.y*depth_scale-z*ppm)

func _ready() -> void:
	ThemeDB.fallback_font=load("res://assets/fonts/NotoSansSC-subset.ttf")
	contract=JSON.parse_string(FileAccess.get_file_as_string("res://map-contract.json"))
	var launch_args:=OS.get_cmdline_args()+OS.get_cmdline_user_args()
	var isolated_test:=false
	for arg in launch_args:
		if arg=="--script" or arg.begins_with("--smoke-") or arg.begins_with("--capture="):
			isolated_test=true
	foundations_enabled=foundations_enabled and (not isolated_test or "--foundations" in launch_args)
	if foundations_enabled:
		var bridge=get_node_or_null("/root/GameSession")
		if bridge!=null and not bridge.pending.is_empty():
			var target:Dictionary=preload("systems/world_registry.gd").load_zone(bridge.target_zone)
			if not target.is_empty(): contract=target
			if bridge.target_zone=="ruins" and bridge.pending.get("run",{}).get("rooms",false):
				preload("systems/dungeon_rooms.gd").configure(contract,bridge.pending.run)
	volumes=contract.volumes
	var b: Dictionary=contract.bounds
	bounds=Rect2(b.x,b.depth,b.width,b.depth_size)
	foot=Vector2(contract.spawn.x,contract.spawn.depth)
	last_safe=foot
	if contract.has("background"):
		var backdrop:=Sprite2D.new()
		backdrop.texture=load(str(contract.background))
		backdrop.centered=false
		backdrop.scale=Vector2.ONE*(3072.0/backdrop.texture.get_width())
		# Match the new image's pavement horizon to the walkable belt.
		backdrop.position=Vector2(0,-50)
		backdrop.z_index=-20
		add_child(backdrop)
	else:
		CourtyardBackdrop.new().setup(self)
	sorting.y_sort_enabled=true
	sorting.z_index=1
	add_child(sorting)
	for v: Dictionary in volumes:
		if v.has("asset"):
			add_prop(v)
	sorting.add_child(foot_node)
	knight=KnightScene.instantiate()
	knight.use_local_input=false
	knight.visual_scale=0.62
	knight.equipment.persistence_enabled=false
	knight.collision_layer=0
	knight.collision_mask=0
	foot_node.add_child(knight)
	knight.set_physics_process(false)
	knight.attack_hitbox.connect(on_attack)
	knight.spell_requested.connect(on_spell)
	loot = WorldLoot.new()
	add_child(loot)
	loot.setup(sorting, volumes, project, knight.equipment)
	loot.notice.connect(func(text: String): notice = text)
	townsfolk = TownNPCs.new()
	if contract.get("town_npcs",true): townsfolk.setup(self)
	interface = MapInterface.new()
	add_child(interface)
	interface.setup(knight, loot)
	interface.prompt_label.position.y=643
	skill_bar=SkillBar.new()
	add_child(skill_bar)
	skill_bar.setup(knight)
	skill_bar.skill_pressed.connect(use_skill)
	skill_bar.spell_pressed.connect(use_spell)
	combat_fx=CombatFX.new()
	combat_fx.z_index=5
	add_child(combat_fx)
	practice=PracticeTargets.new()
	if contract.get("town_npcs",true) and contract.get("zone_id","town")!="city": practice.setup(self)
	camera.position=Vector2(clampf(foot.x*ppm,640,2432),400)
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := Panel.new()
	panel.position=Vector2(22,18)
	panel.size=Vector2(1236,86)
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.04,0.08,0.1,0.8)
	style.border_color=Color(0.75,0.7,0.46,0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	layer.add_child(panel)
	hud.position=Vector2(38,28)
	hud.size=Vector2(930,76)
	hud.clip_text=true
	hud.add_theme_font_size_override("font_size",18)
	hud.add_theme_color_override("font_color",Color(0.95,0.93,0.8))
	layer.add_child(hud)
	minimap.position=Vector2(982,18)
	minimap.size=Vector2(276,142)
	minimap.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(minimap)
	minimap.setup(self, true)
	interface.setup_atlas(self)
	if not OS.has_feature("web"):
		developer_tools=preload("developer_tools.gd").new()
		add_child(developer_tools)
		developer_tools.setup(self)
	if foundations_enabled:
		runtime=preload("systems/game_runtime.gd").new()
		add_child(runtime)
		runtime.setup(self)
	var args := OS.get_cmdline_user_args()
	if "--smoke-map" in args:
		call_deferred("smoke_test")
	if "--smoke-interactions" in args:
		call_deferred("interaction_test")
	if "--smoke-combat" in args:
		call_deferred("combat_test")
	for arg in args:
		if arg.begins_with("--capture="):
			capture_mode=arg.trim_prefix("--capture=")
	if capture_mode=="box":
		foot=Vector2(8.4,5.9)
		height_z=0.85
		platform="box-a"
	elif capture_mode=="behind-tree":
		foot=Vector2(10.55,3.6)
	elif capture_mode=="front-tree":
		foot=Vector2(10.55,5.7)
	elif capture_mode=="town":
		foot=Vector2(6.2,4.4)
	elif capture_mode=="chest":
		foot=Vector2(11.1,6.8)
	elif capture_mode=="fountain":
		foot=Vector2(14.0,6.5)
		camera.position.x=clampf(foot.x*ppm,640,2432)
	elif capture_mode in ["fountain-side","fountain-back"]:
		foot=Physics.step_position(volumes,bounds,Vector2(13.2,5.4),Vector2(2,0),0,true) if capture_mode=="fountain-side" else Vector2(16.15,3.95)
		camera.position.x=clampf(foot.x*ppm,640,2432)
	elif capture_mode=="developer":
		foot=Vector2(14.0,6.5)
		camera.position.x=clampf(foot.x*ppm,640,2432)
		developer_tools.panel.show()
		developer_tools.collision_toggle.button_pressed=true
		developer_tools.hit_toggle.button_pressed=true
	elif capture_mode=="jump":
		foot=Vector2(7.0,6.8)
		grounded=false
		vertical_speed=Physics.JUMP_SPEED
	elif capture_mode=="dialogue":
		foot=Vector2(6.0,4.4)
		call_deferred("capture_dialogue")
	elif capture_mode in ["atlas","world-atlas"]:
		interface.toggle_atlas()
		interface.atlas.set_world(capture_mode=="world-atlas")
		call_deferred("save_capture")
	elif capture_mode=="inventory":
		_physics_process(0.016)
		knight.equipment.grant("courtyard_blade")
		knight.equipment.equip("courtyard_blade")
		interface.toggle_inventory()
		call_deferred("save_capture")
	elif capture_mode=="east-town":
		foot=Vector2(17.6,6.4)
		camera.position.x=clampf(foot.x*ppm,640,2432)
	elif capture_mode=="chest-open":
		foot=Vector2(11.8,6.8)
		loot.interact(foot,0)
		foot=Vector2(11.0,7.3)
		camera.position.x=clampf(foot.x*ppm,640,2432)
	elif capture_mode in ["run","dash","plunge","skill1","skill2","skill3"]:
		foot=Vector2(4.8,8.3)
		if capture_mode=="run":
			sprint.active=true
			sprint.direction=Vector2.RIGHT
		elif capture_mode=="dash":
			knight.request_dash_attack()
		elif capture_mode=="plunge":
			foot.x=6.6
			height_z=1.3
			grounded=false
			knight.set_airborne(true,0)
			knight.request_air_attack()
		else:
			use_skill(["crescent","rising","trinity"][int(capture_mode.right(1))-1])
	if not capture_mode.is_empty():
		camera.position.y=clampf(project(foot).y-220,400,570)
	if capture_mode.begins_with("foundation-") and runtime!=null:
		runtime.panel.open(capture_mode.trim_prefix("foundation-"))
		call_deferred("save_capture")

func capture_dialogue() -> void:
	_physics_process(0.016)
	interface.begin_conversation(townsfolk.nearest(foot, 0))
	save_capture()

func combat_test() -> void:
	var checks = load("res://combat_stage_test.gd").new()
	get_tree().quit(0 if checks.run(self) else 1)

func add_prop(v: Dictionary) -> void:
	var node := Node2D.new()
	node.name=str(v.id)
	# The lower edge is the front of the actual ground footprint, not crown width.
	node.position=project(Vector2(float(v.x)+float(v.width)/2,float(v.depth)+float(v.depth_size)))
	var sprite := Sprite2D.new()
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/"+str(v.asset)+"-meta.json"))
	var box: Array=metadata.alphaBBox
	var texture := AtlasTexture.new()
	texture.atlas=load("res://assets/"+str(v.asset)+".png")
	texture.region=Rect2(box[0],box[1],box[2]-box[0],box[3]-box[1])
	sprite.texture=texture
	var scale_factor := float(v.visualHeight)*ppm/texture.get_height()
	sprite.scale=Vector2.ONE*scale_factor
	sprite.position=Vector2(0,-texture.get_height()*scale_factor/2)
	if v.get("sortAtCenter", false):
		# Sort at the base ellipse center, without moving the painted fountain.
		var sort_shift := float(v.depth_size)*depth_scale/2.0
		node.position.y -= sort_shift
		sprite.position.y += sort_shift
	node.add_child(sprite)
	if str(v.asset) == "fountain":
		var water := preload("fountain_water.gd").new()
		water.setup(sprite, box)
		node.add_child(water)
	sorting.add_child(node)

func _unhandled_key_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if not capture_mode.is_empty():
		return
	if not event.is_pressed() or event.is_echo():
		return
	if runtime!=null and event is InputEventKey:
		if runtime.handle_key(event):
			get_viewport().set_input_as_handled()
			return
		var mapped:InputEventKey=event.duplicate()
		mapped.keycode=runtime.controls.canonical(event)
		event=mapped
	if event.keycode == KEY_M:
		interface.toggle_atlas()
		sprint.reset()
		get_viewport().set_input_as_handled()
		return
	if interface.is_modal():
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_I:
			interface.close_panels()
		elif interface.dialogue.visible and event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
			interface.advance_conversation()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_I:
		if grounded and knight.is_locomotion():
			interface.toggle_inventory()
		return
	if event.keycode == KEY_E:
		interact()
		return
	if event.keycode==KEY_SPACE:
		if grounded and knight.is_locomotion():
			grounded=false
			vertical_speed=Physics.JUMP_SPEED
			knight.set_airborne(true,vertical_speed)
			notice="跳跃：高度与地面纵深独立"
	elif event.keycode==KEY_J:
		context_attack()
	elif event.keycode==KEY_K:
		use_spell()
	elif event.keycode in [KEY_1,KEY_2,KEY_3]:
		use_skill({KEY_1:"crescent",KEY_2:"rising",KEY_3:"trinity"}[event.keycode])
	elif event.keycode==KEY_F2:
		debug_collision=not debug_collision
	elif event.keycode==KEY_F9:
		if runtime!=null and runtime.Registry.is_dungeon(runtime.zone):
			runtime.say("试炼中使用冒险菜单撤退或读档。")
			return
		foot=Vector2(contract.spawn.x,contract.spawn.depth)
		last_safe=foot
		height_z=0
		vertical_speed=0
		grounded=true
		platform=""
		sprint.reset()
		hit_pause=0
		shake_left=0
		if runtime==null:
			knight.reset_character()
		else:
			knight.set_airborne(false,0)
			if not knight.defeated: knight.change_action("stand")
			notice="已返回庭院出生点；生命与法力保持不变。"
	elif event.keycode==KEY_Q:
		if grounded and knight.is_locomotion():
			loot.quick_equip(foot,height_z)

func _input(event: InputEvent) -> void:
	var bridge=get_node_or_null("/root/GameSession")
	if bridge!=null and bridge.busy:
		get_viewport().set_input_as_handled()
		return
	if runtime!=null and event is InputEventKey and runtime.panel.is_open() and runtime.panel.tab=="dialogue":
		var physical:int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if physical in [KEY_SPACE,KEY_ENTER,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]:
			if event.pressed and not event.echo: runtime.panel.dialogue_view.keyboard(physical)
			get_viewport().set_input_as_handled()
			return
	if runtime!=null and event is InputEventKey and runtime.panel.capture_action!="":
		runtime.panel.capture_key(event)
		get_viewport().set_input_as_handled()
		return
	# Modal shortcuts must run before focused Controls consume ui_cancel/navigation.
	if runtime!=null and event is InputEventKey and event.pressed and not event.echo and capture_mode.is_empty() and not get_tree().paused:
		var modal_key:int=runtime.controls.canonical(event)
		if modal_key==KEY_ESCAPE or (modal_key==KEY_L and runtime.panel.is_open()):
			if runtime.handle_key(event):
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and capture_mode.is_empty():
		if interface != null and interface.is_modal():
			sprint.reset()
			return
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if runtime!=null: key=runtime.controls.canonical(event)
		sprint.register_key(key,event.pressed,event.echo)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and capture_mode.is_empty():
		sprint.reset()

func context_attack() -> void:
	if interface.is_modal(): return
	knight.set_airborne(not grounded,vertical_speed)
	if not grounded:
		if knight.request_air_attack():
			notice="坠星下劈 · 落地冲击"
	elif sprint.active and knight.is_locomotion():
		if knight.request_dash_attack():
			sprint.reset()
			notice="疾风冲刺斩"
	else:
		knight.request_attack()

func use_skill(id: String) -> void:
	if interface.is_modal() or not grounded: return
	if knight.request_skill(id):
		sprint.reset()
		notice=knight.SKILLS[id].name
	elif knight.skill_cooldowns.get(id,0)>0:
		notice="技能冷却中"
	elif knight.SKILLS.has(id) and knight.mana<float(knight.SKILLS[id].cost):
		notice="法力不足"

func use_spell() -> void:
	if interface.is_modal(): return
	knight.request_cast()

func interact() -> void:
	if not grounded or not knight.is_locomotion():
		return
	if runtime!=null and runtime.portals!=null and runtime.portals.interact(): return
	if loot.interact(foot, height_z):
		return
	var npc: Dictionary = townsfolk.nearest(foot, height_z)
	if not npc.is_empty():
		knight.set_movement_axis(0)
		knight.change_action("stand")
		if runtime!=null: runtime.open_npc(npc)
		else: interface.begin_conversation(npc)

func _physics_process(delta: float) -> void:
	var bridge=get_node_or_null("/root/GameSession")
	if bridge!=null and bridge.busy: return
	if not is_instance_valid(knight):
		return
	# Death is a state transition and must settle even if Esc opened this frame.
	if runtime!=null and runtime.death_pending: runtime.step(0)
	skill_bar.visible=not interface.is_modal()
	if interface.is_modal():
		sprint.reset()
		knight.set_running(false)
		knight.set_movement_axis(0)
		if runtime==null: knight._physics_process(delta)
		interface.set_prompt("")
		return
	if hit_pause>0:
		hit_pause=maxf(0,hit_pause-delta)
		return
	var input := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if runtime!=null: input=runtime.controls.movement()
	if testing_motion:
		input=test_input
	if not capture_mode.is_empty():
		input=Vector2.RIGHT if capture_mode=="run" else Vector2.ZERO
	input=input.limit_length(1)
	sprint.step(delta,input)
	var can_move: bool=knight.is_locomotion() and not knight.defeated
	var old_foot := foot
	var speed: float=(knight.move_speed+knight.equipment_speed_bonus)/ppm
	var is_running: bool=sprint.active and can_move
	knight.set_running(is_running and grounded)
	if is_running: speed*=SprintInput.SPEED_MULTIPLIER
	if can_move:
		foot=Physics.step_position(volumes,bounds,foot,input*speed*delta,height_z,grounded)
	elif knight.state=="dash_attack":
		var burst_dt := maxf(0,minf(knight.elapsed+delta,0.28)-maxf(knight.elapsed,0.06))
		if burst_dt>0:
			foot=Physics.step_position(volumes,bounds,foot,Vector2(knight.facing*7.2*burst_dt,0),height_z,grounded)
	if input.x!=0 and can_move:
		knight.facing=1 if input.x>0 else -1
	var moved := foot.distance_to(old_foot)>0.00001
	knight.set_movement_axis((input.x if input.x!=0 else knight.facing*0.001) if moved else 0)
	var landed := false
	var valid_landing := true
	if not grounded:
		var old_z := height_z
		if knight.state=="air_slash" and knight.elapsed>=0.12:
			vertical_speed=minf(vertical_speed,-9.5)
		vertical_speed -= Physics.GRAVITY*delta
		height_z += vertical_speed*delta
		var landing := Physics.support(volumes,foot,old_z)
		if vertical_speed<=0 and height_z<=float(landing.z):
			landed=true
			if landing.valid:
				height_z=landing.z
				platform=landing.platform
				grounded=true
				vertical_speed=0
				last_safe=foot
			else:
				valid_landing=false
				# No standing on water: restore the last bank/platform after a failed jump.
				foot=last_safe
				var safe := Physics.support(volumes,foot)
				height_z=safe.z
				platform=safe.platform
				grounded=true
				vertical_speed=0
				notice="水面不可落脚，已退回安全岸边"
	else:
		var surface := Physics.support(volumes,foot,height_z+Physics.STEP)
		if surface.valid and float(surface.z)<height_z-0.001:
			grounded=false
			vertical_speed=0
		elif surface.valid:
			height_z=surface.z
			platform=surface.platform
			last_safe=foot
	var sort_offset := 0.0
	if not platform.is_empty():
		for v: Dictionary in volumes:
			if v.id==platform:
				sort_offset=maxf(0,(float(v.depth)+float(v.depth_size)-foot.y)*depth_scale)+0.5
	foot_node.position=project(foot)+Vector2(0,sort_offset)
	knight.position=Vector2(0,-height_z*ppm-sort_offset)
	# Reuse the original animation/state/combo logic; map owns all x/depth/z motion.
	knight.set_airborne(not grounded, vertical_speed)
	if landed:
		knight.notify_air_attack_landed(valid_landing)
	knight._physics_process(delta)
	knight.position=Vector2(0,-height_z*ppm-sort_offset)
	camera.position.x=lerpf(camera.position.x,clampf(foot.x*ppm,640,2432),minf(1,delta*6))
	camera.position.y=lerpf(camera.position.y,clampf(project(foot).y-220,400,570),minf(1,delta*6))
	shake_left=maxf(0,shake_left-delta)
	camera.offset=Vector2(sin(capture_time*90)*4,cos(capture_time*75)*2)*minf(1,shake_left/.08)
	if runtime!=null and not runtime.controls.screen_shake: camera.offset=Vector2.ZERO
	dash_fx_left-=delta
	if moved and (is_running or knight.state=="dash_attack") and dash_fx_left<=0:
		combat_fx.play("dash",project(foot,height_z),knight.facing,.7)
		dash_fx_left=.09
	for p: Dictionary in projectiles.duplicate():
		var before_x: float = p.node.position.x / ppm
		p.node.position.x += p.facing*680*delta
		p.life-=delta
		var impact: bool = loot.hit_projectile(before_x, p.node.position.x / ppm, p.depth, p.height, p.damage)
		if not impact and runtime!=null:
			impact=runtime.encounters.hit_projectile(before_x,p.node.position.x/ppm,p.depth,p.height,p.damage)
		if not impact:
			impact=practice.projectile(before_x,p.node.position.x/ppm,p.depth,p.height,p.damage)
		if impact or p.life<=0:
			p.node.queue_free()
			projectiles.erase(p)
	townsfolk.step(delta, foot, height_z)
	practice.step(delta)
	if runtime!=null: runtime.step(delta)
	var hint: String = runtime.portals.prompt() if runtime!=null and runtime.portals!=null else ""
	if hint.is_empty(): hint=loot.prompt(foot,height_z)
	if hint.is_empty():
		var near: Dictionary = townsfolk.nearest(foot, height_z)
		if not near.is_empty():
			hint = "E 交谈 · " + str(near.name)
	if runtime!=null:
		hint=hint.replace("E ",runtime.controls.key_name("interact")+" ").replace("Q ",runtime.controls.key_name("equip")+" ")
	interface.set_prompt(hint)
	hud.text="苍石庭院  /  姬骑士 · 战斗演示\n双击方向 奔跑   空格 跳跃   J 攻击/冲刺斩/下劈   1–3 技能   K 雷光   E 交互   I 背包   R 复位\n高度 %.2fm  ·  %s  ·  %s" % [height_z,("奔跑" if is_running else "箱顶 "+platform if not platform.is_empty() else "地面" if grounded else "空中"),notice]
	if runtime!=null:
		hud.text="%s  /  姬骑士\n方向键移动/双击奔跑   %s 跳跃   %s 上挑   %s 攻击   %s 交互   %s 背包   %s 地图   %s 手册   Esc 暂停\n%s" % [runtime.Registry.title(runtime.zone),runtime.controls.key_name("jump"),runtime.controls.key_name("skill2"),runtime.controls.key_name("attack"),runtime.controls.key_name("interact"),runtime.controls.key_name("inventory"),runtime.controls.key_name("map"),runtime.controls.key_name("journal"),notice]
	queue_redraw()
	minimap.queue_redraw()
	capture_time+=delta
	var capture_at: float={"jump":.34,"run":.3,"dash":.19,"plunge":.30,"skill1":.27,"skill2":.29,"skill3":.74}.get(capture_mode,.8)
	if not capture_mode.is_empty() and capture_time>capture_at and not captured:
		captured=true
		call_deferred("save_capture")

func on_attack(event: Dictionary) -> void:
	attacks+=1
	notice="%s · 攻击事件 %d（沿用原角色时序）" % [str(event.action),attacks]
	var hit_count: int=loot.hit_melee(foot, height_z, event)+practice.hit(foot,height_z,event)
	if runtime!=null:
		hit_count+=runtime.encounters.hit(foot,height_z,event)
		runtime.audio.play("hit" if hit_count>0 else "swing")
	if developer_tools!=null:
		developer_tools.record_hit(event,hit_count)
	var kind: String=event.get("skill","")
	if kind.is_empty(): kind=str(event.action)
	if kind in ["crescent","rising","trinity","dash_attack","air_slash"]:
		combat_fx.play(kind,project(foot,height_z),knight.facing,1.0)
		notice={"crescent":"月弧斩","rising":"破晓升龙","trinity":"幻影三连","dash_attack":"疾风冲刺斩","air_slash":"坠星下劈"}[kind]+(" · 命中 %d" % hit_count if hit_count>0 else "")
	if hit_count>0:
		hit_pause=.035
		shake_left=.10

func on_spell(event: Dictionary) -> void:
	spells+=1
	var sprite := Sprite2D.new()
	sprite.texture=load("res://characters/first_knight/assets/magic_bolt.png")
	sprite.position=event.origin
	sprite.scale=Vector2(0.28*event.facing,0.28)
	sprite.z_index=2
	var mat := CanvasItemMaterial.new()
	mat.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material=mat
	add_child(sprite)
	projectiles.append({"node":sprite,"facing":event.facing,"life":2.5,"depth":foot.y,"height":(project(foot).y-sprite.position.y)/ppm,"damage":event.damage})
	notice="施法事件 %d · 独立加法特效" % spells

func _draw() -> void:
	if volumes==null:
		return
	for v: Dictionary in volumes:
		var pos := project(Vector2(v.x,v.depth))
		var rect := Rect2(pos,Vector2(float(v.width)*ppm,float(v.depth_size)*depth_scale))
		if v.kind=="water" and not v.has("asset"):
			draw_style_box(pool_style(),rect.grow(9))
			draw_rect(rect,Color(0.12,0.43,0.49,0.95))
			for i in 18:
				var y := rect.position.y+8+i*rect.size.y/19
				draw_line(Vector2(rect.position.x+12+sin(i*1.3)*8,y),Vector2(rect.end.x-12+cos(i)*9,y),Color(0.52,0.8,0.79,0.25),1.5)
		elif v.kind!="npc" and v.kind!="fountain-column":
			var shadow := project(Vector2(float(v.x)+float(v.width)/2,float(v.depth)+float(v.depth_size)))
			draw_set_transform(shadow,0,Vector2(1,0.22))
			for ring in 10:
				draw_circle(Vector2.ZERO,float(v.width)*ppm*(0.56-ring*0.024),Color(0.03,0.08,0.08,0.023))
			draw_set_transform(Vector2.ZERO)
	var shadow_size := 25.0*(1-height_z*0.12)
	draw_set_transform(project(foot),0,Vector2(1,0.24))
	draw_circle(Vector2.ZERO,shadow_size,Color(0.025,0.05,0.05,0.33))
	draw_set_transform(Vector2.ZERO)

func pool_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.42,0.42,0.3)
	style.border_color=Color(0.68,0.65,0.44)
	style.set_border_width_all(4)
	return style

func save_capture() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	get_viewport().get_texture().get_image().save_png("res://captures/"+capture_mode+".png")
	print("CAPTURE ",capture_mode," height=",height_z," platform=",platform)
	get_tree().quit()

func smoke_test() -> void:
	var box_pos := Vector2(8.4,5.85)
	assert(Physics.blocked(volumes,box_pos,0.0),"Box side must block")
	assert(not Physics.blocked(volumes,box_pos,0.85),"Box top must clear body")
	var top := Physics.support(volumes,box_pos)
	assert(top.valid and is_equal_approx(top.z,0.85) and top.platform=="box-a")
	assert(Physics.blocked(volumes,Vector2(10.6,4.6),0.0),"Tree trunk must block")
	assert(Physics.blocked(volumes,Vector2(10.6,4.6),Physics.JUMP_RISE),"Tree cannot be jumped through")
	assert(not Physics.support(volumes,Vector2(16,5)).valid,"Water cannot support feet")
	var bank := Vector2(13.9,5)
	var walked := Physics.step_position(volumes,bounds,bank,Vector2(1,0),0,true)
	assert(walked.x<14.3,"Walking onto water must fail")
	var walked_box := Physics.step_position(volumes,bounds,Vector2(7.4,5.85),Vector2(1.2,0),0,true)
	assert(walked_box.x<7.9,"Swept movement must not cross crate")
	var jumped_box := Physics.step_position(volumes,bounds,Vector2(7.4,5.85),Vector2(1.2,0),1.1,false)
	assert(jumped_box.x>8.5,"Airborne body must pass above crate")
	assert(project(Vector2(6,5),1).y < project(Vector2(6,5),0).y)
	assert(project(Vector2(6,6),0).y > project(Vector2(6,5),0).y)
	assert(Physics.JUMP_RISE>0.85 and Physics.JUMP_RISE<1.36)
	assert(knight.clips.has("attack3") and knight.clips.has("cast"))
	# Exercise actual map gravity/landing, not only static geometry predicates.
	testing_motion=true
	foot=Vector2(7.45,5.85)
	height_z=0
	grounded=false
	vertical_speed=Physics.JUMP_SPEED
	test_input=Vector2.RIGHT
	for i in 45:
		_physics_process(1.0/60)
	assert(grounded and is_equal_approx(height_z,0.85) and platform=="box-a","Full jump must land on crate")
	for i in 60:
		_physics_process(1.0/60)
	assert(grounded and is_zero_approx(height_z),"Walking off crate must fall to ground")
	test_input=Vector2.ZERO
	_physics_process(1.0/60)
	knight.request_attack()
	for i in 40:
		knight._physics_process(0.02)
	assert(attacks==1,"Original character hit event must reach map")
	knight.request_cast()
	for i in 40:
		knight._physics_process(0.02)
	assert(spells==1,"Original character spell event must reach map")
	print("PASS: crate sides/top, trunk and airborne collision, water support, swept movement, independent depth/height, imported original attack/spell events.")
	get_tree().quit()

func interaction_test() -> void:
	set_physics_process(false)
	testing_motion = true
	test_input = Vector2.ZERO
	var failures: Array[String] = []
	# Actual attack events, not direct crate damage calls.
	foot = Vector2(6.5,5.85)
	knight.facing = 1
	knight.request_attack()
	for i in 45:
		_physics_process(0.02)
	if not loot.crates.has("box-a") or loot.crates["box-a"].hp >= 30:
		failures.append("First sword hit must damage nearby crate")
	knight.request_attack()
	for i in 45:
		_physics_process(0.02)
	if loot.crates.has("box-a") or Physics.blocked(volumes,Vector2(8.4,5.85),0):
		failures.append("Destroyed crate retains ground collision")
	loot._process(0.3)
	foot = Vector2(8.4,6.1)
	interact()
	if loot.materials["木料"] != 3:
		failures.append("Crate drops not collected through E interaction")
	# Real spell trajectory uses captured launch lane and height, not current player position.
	foot = Vector2(7.0,7.0)
	knight.request_cast()
	for i in 75:
		_physics_process(0.02)
	if loot.crates.has("box-b"):
		failures.append("Actual cast projectile did not destroy crate")
	foot = Vector2(11.8,6.8)
	interact()
	loot._process(0.4)
	foot.y += 0.45
	interact()
	if not knight.equipment.owned.has("courtyard_blade"):
		failures.append("Chest weapon missing from inventory")
	knight.equipment.equip("courtyard_blade")
	if knight.get_attack_damage("attack1") != 34:
		failures.append("Equipped weapon does not affect actual character damage")
	interface.toggle_inventory()
	if not interface.inventory.visible or interface.inventory_content.buttons.size() != knight.equipment.owned.size() or interface.inventory_content.stat_text.text.is_empty():
		failures.append("Inventory failed to render")
	interface.close_panels()
	foot = Vector2(6.0,4.4)
	interact()
	if not interface.dialogue.visible:
		failures.append("Nearby resident did not open dialogue")
	var before := foot
	test_input = Vector2.RIGHT
	_physics_process(0.1)
	if foot != before:
		failures.append("Character moved while talking")
	interface.advance_conversation()
	interface.advance_conversation()
	interface.advance_conversation()
	if interface.is_modal():
		failures.append("Final dialogue page failed to close")
	if not townsfolk.nearest(foot,1.0).is_empty():
		failures.append("Airborne character can talk to ground resident")
	test_input=Vector2.ZERO
	var jump_key := InputEventKey.new()
	jump_key.keycode=KEY_SPACE
	jump_key.pressed=true
	_unhandled_key_input(jump_key)
	_physics_process(0.1)
	var rising_speed := vertical_speed
	_unhandled_key_input(jump_key)
	if grounded or not is_equal_approx(vertical_speed,rising_speed) or not knight.airborne:
		failures.append("Jump animation/physics state or double-jump lock failed")
	for i in 60:
		_physics_process(1.0/60)
	if not grounded or knight.airborne:
		failures.append("Jump did not return to grounded animation state")
	for message in failures:
		push_error(message)
	print("INTERACTION_TEST ", "PASS" if failures.is_empty() else "FAIL", " · sword, projectile, crates, pickups, chest, actual equipment stats, dialogue, input focus")
	get_tree().quit(0 if failures.is_empty() else 1)

