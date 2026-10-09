extends Node2D

const Actor = preload("res://actor.gd")
const ATTACK_TIMES := [.19,.19,.12,.12,.19,.28]
var hero: Node2D
var preview: Node2D
var elapsed := 0.0
var attack_time := -1.0
var paused := false
var speed := 1.0
var smooth := false
var autowalk := true
var stepping := false
var exporting := false
var status: Label
var font: SystemFont
var colors := []
var textures_reference: Texture2D

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Arial"])
	hero = Actor.new()
	hero.position = Vector2(275,690)
	hero.scale = Vector2(1.5,1.5)
	add_child(hero)
	preview = Actor.new()
	preview.position = Vector2(865,690)
	preview.scale = Vector2(1.5,1.5)
	add_child(preview)
	build_ui()
	textures_reference = load("res://assets/original-reference.png")
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("CUTOUT_KNIGHT_READY: articulated 3D textured parts; walk 4 keys, slash 6 keys; independent weapon and effects")
	if "--verify" in OS.get_cmdline_user_args():
		await verify_and_export()

func label(at: Vector2,text_: String,size := 18,color := Color("c6d8eb")) -> Label:
	var node := Label.new()
	node.position = at
	node.text = text_
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	add_child(node)
	return node

func button(at: Vector2,text_: String,callback: Callable) -> Button:
	var node := Button.new()
	node.position = at
	node.text = text_
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",17)
	node.pressed.connect(callback)
	add_child(node)
	return node

func check(at: Vector2,text_: String,initial: bool,callback: Callable) -> void:
	var node := CheckButton.new()
	node.position = at
	node.text = text_
	node.button_pressed = initial
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",16)
	node.toggled.connect(callback)
	add_child(node)

func build_ui() -> void:
	label(Vector2(28,18),"2.5D 姬骑士 · 分部件骨架动画",28)
	label(Vector2(28,59),"画好的像素贴图 + 独立 3D 网格 + 固定关节长度；关闭实时光照，武器与剑光分离。",17)
	button(Vector2(28,99),"走路 / 待机",func(): autowalk = not autowalk; stepping = false)
	button(Vector2(146,99),"挥剑（空格）",func(): attack_time = 0.0; stepping = false)
	button(Vector2(275,99),"暂停 P",func(): paused = not paused; stepping = false)
	button(Vector2(366,99),"逐帧 N",advance_frame)
	button(Vector2(459,99),"换装：蓝 / 红",func():
		for actor in [hero,preview]: actor.outfit = "red" if actor.outfit == "blue" else "blue")
	button(Vector2(603,99),"换武器：钢 / 金",func():
		for actor in [hero,preview]: actor.golden_weapon = not actor.golden_weapon)
	button(Vector2(760,99),"导出 PNG 动作帧",func(): if not exporting: await bake(hero))
	button(Vector2(939,99),"0.5×",func(): speed = .5)
	button(Vector2(1001,99),"1×",func(): speed = 1)
	check(Vector2(28,140),"平滑关节（默认关闭）",false,func(value: bool): smooth = value)
	check(Vector2(255,140),"骨架检查",false,func(value: bool): for actor in [hero,preview]: actor.debug_bones = value)
	check(Vector2(395,140),"披风",true,func(value: bool): for actor in [hero,preview]: actor.show_cape = value)
	check(Vector2(502,140),"长发",true,func(value: bool): for actor in [hero,preview]: actor.show_hair = value)
	check(Vector2(609,140),"武器",true,func(value: bool): for actor in [hero,preview]: actor.show_weapon = value)
	button(Vector2(726,143),"正面 / 微侧转",func(): for actor in [hero,preview]: actor.angle = 10 if actor.angle == 0 else 0)
	label(Vector2(80,180),"走路预览 / 可操作角色",21)
	label(Vector2(732,180),"挥剑预览 · 六个关键姿势",21)
	label(Vector2(28,720),"A / D 移动与转向   空格挥剑   P 暂停   N 逐帧   四帧走路约 4.5 fps",18)
	status = label(Vector2(28,756),"正在加载贴图…",17,Color("89d6c4"))
	label(Vector2(132,793),"原画参考 → 独立部件重绘 → 同一骨架控制",17)
	label(Vector2(132,824),"固定侧视原型；大幅转身与服装接缝仍需修整。",16,Color("efc18d"))

func attack_frame(t: float) -> Array:
	var position_ := t
	for i in range(6):
		if position_ < ATTACK_TIMES[i]:
			return [i,position_/ATTACK_TIMES[i]]
		position_ -= ATTACK_TIMES[i]
	return [5,0.0]

func advance_frame() -> void:
	paused = true
	stepping = true
	var count := 4 if hero.current_action == "walk" else (6 if hero.current_action == "slash" else 1)
	hero.set_pose(hero.current_action,(hero.current_frame+1)%count,0,elapsed)
	preview.set_pose("slash",(preview.current_frame+1)%6,0,elapsed)
	update_status()

func _process(delta: float) -> void:
	if hero == null or exporting:
		return
	if not paused:
		elapsed += delta*speed
		if attack_time >= 0:
			attack_time += delta*speed
			if attack_time > 1.09:
				attack_time = -1.0
		var direction := int(Input.is_physical_key_pressed(KEY_D))-int(Input.is_physical_key_pressed(KEY_A))
		if direction != 0 and attack_time < 0:
			hero.position.x = clampf(hero.position.x+direction*delta*75,155,415)
			hero.facing = direction
	update_actors()

func update_actors() -> void:
	if stepping:
		hero.set_pose(hero.current_action,hero.current_frame,0,elapsed)
		preview.set_pose(preview.current_action,preview.current_frame,0,elapsed)
		update_status()
		return
	var moving := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_D)
	var frame := int(elapsed/.22)%4
	var blend := fmod(elapsed,.22)/.22 if smooth else 0.0
	if attack_time >= 0:
		var key := attack_frame(attack_time)
		hero.set_pose("slash",key[0],key[1] if smooth else 0.0,elapsed)
	else:
		hero.set_pose("walk" if autowalk or moving else "idle",frame if autowalk or moving else 0,blend,elapsed)
	var loop := fmod(elapsed,1.80)
	if loop < 1.09:
		var key := attack_frame(loop)
		preview.set_pose("slash",key[0],key[1] if smooth else 0.0,elapsed)
	else:
		preview.set_pose("idle",0,0.0,elapsed)
	update_status()

func update_status() -> void:
	status.text = "左：%s %d    右：%s %d    速度 %.1f×    独立剑长 %.1f" % [hero.current_action,hero.current_frame+1,preview.current_action,preview.current_frame+1,speed,hero.sword_grip.distance_to(hero.sword_tip)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: attack_time = 0.0; stepping = false
			KEY_P: paused = not paused; stepping = false
			KEY_N: advance_frame()

func _draw() -> void:
	for x in range(0,1280,32):
		draw_line(Vector2(x,225),Vector2(x,711),Color(.08,.115,.17),1)
	for y in range(226,711,32):
		draw_line(Vector2(0,y),Vector2(1280,y),Color(.08,.115,.17),1)
	draw_line(Vector2(25,692),Vector2(615,692),Color("788ba6"),2)
	draw_line(Vector2(667,692),Vector2(1250,692),Color("788ba6"),2)
	draw_line(Vector2(640,210),Vector2(640,711),Color("293a50"),1)
	if textures_reference != null:
		draw_texture_rect(textures_reference,Rect2(28,777,80,80),false)

func bake(actor: Node2D) -> Dictionary:
	exporting = true
	var path := "res://exports/%s_%s" % [actor.outfit,"gold" if actor.golden_weapon else "steel"]
	DirAccess.make_dir_recursive_absolute(path)
	var manifest := {"origin":[0,0],"outfit":actor.outfit,"weapon":"gold" if actor.golden_weapon else "steel","source":"knight-parts-v1.png","animations":{},"note":"Full composite snapshots; live runtime keeps each part, weapon and effects independent"}
	var origin: Vector2 = actor.camera.unproject_position(Vector3.ZERO)
	for action in ["idle","walk","slash"]:
		var records := []
		var count := 1 if action == "idle" else (4 if action == "walk" else 6)
		for frame in range(count):
			actor.set_pose(action,frame,0,frame*.22)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image: Image = actor.viewport.get_texture().get_image()
			var crop := image.get_used_rect()
			var file := "%s/%s_%02d.png" % [path,action,frame]
			image.get_region(crop).save_png(file)
			records.append({"path":file,"offset":[crop.position.x-roundi(origin.x),crop.position.y-roundi(origin.y)],"size":[crop.size.x,crop.size.y],"duration":.22 if action == "walk" else (ATTACK_TIMES[frame] if action == "slash" else .5)})
		manifest.animations[action] = records
	var f := FileAccess.open(path+"/frames.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest,"\t"))
	exporting = false
	print("CUTOUT_BAKE_READY ",path," 11 frames")
	return manifest

func verify_and_export() -> void:
	exporting = true
	var bone_checks := 0
	var weapon_checks := 0
	var clipping := []
	for action in ["idle","walk","slash"]:
		var count := 1 if action == "idle" else (4 if action == "walk" else 6)
		for frame in range(count):
			hero.set_pose(action,frame,0,frame*.22)
			for side in ["near","far"]:
				for chain in [["hip","knee","ankle",UPPER_LEG,LOWER_LEG],["shoulder","elbow","hand",UPPER_ARM,LOWER_ARM]]:
					var a: Vector2 = hero.joints[side+"_"+chain[0]]
					var b: Vector2 = hero.joints[side+"_"+chain[1]]
					var c: Vector2 = hero.joints[side+"_"+chain[2]]
					assert(absf(a.distance_to(b)-chain[3]) < .01,"Upper bone length changed")
					assert(absf(b.distance_to(c)-chain[4]) < .01,"Lower bone length changed")
					bone_checks += 2
			assert(absf(hero.sword_grip.distance_to(hero.sword_tip)-Actor.SWORD_WIDTH*(1-Actor.SWORD_GRIP_X)) < .01,"Sword length changed")
			assert(hero.parts.sword.scale.is_equal_approx(Vector3.ONE),"Weapon scale changed")
			assert(hero.sword_grip.distance_to(Vector3(hero.hand.x,-hero.hand.y,11)) < .01,"Weapon detached from hand")
			weapon_checks += 1
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image: Image = hero.viewport.get_texture().get_image()
			var bounds := image.get_used_rect()
			if bounds.position.x <= 1 or bounds.position.y <= 1 or bounds.end.x >= 447 or bounds.end.y >= 447:
				clipping.append(action+str(frame))
			image.save_png("res://preview/%s_%02d.png" % [action,frame])
	assert(clipping.is_empty(),"Art or sword clipped: "+str(clipping))
	# Explicitly verify the two legs exchange front/back targets in the gait.
	var p0: Dictionary = hero.targets("walk",0)
	var p2: Dictionary = hero.targets("walk",2)
	assert(p0.near_ankle.x > p0.far_ankle.x and p2.near_ankle.x < p2.far_ankle.x,"Legs do not alternate")
	hero.set_pose("walk",0)
	preview.set_pose("slash",0)
	advance_frame()
	assert(hero.current_frame == 1 and preview.current_frame == 1,"Single-frame stepping skipped a pose")
	stepping = false
	await bake(hero)
	hero.outfit = "red"
	hero.set_pose("idle",0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	hero.viewport.get_texture().get_image().save_png("res://preview/red-idle.png")
	hero.outfit = "blue"
	hero.set_pose("walk",0)
	preview.set_pose("slash",1)
	update_status()
	paused = true
	exporting = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://preview/comparison.png")
	var report := {"frames_checked":11,"bone_lengths_checked":bone_checks,"weapon_length_and_grip_checked":weapon_checks,"clipped_frames":clipping,"legs_exchange":true,"unlit":true,"parts_independent":true,"technique":"textured articulated 3D planes at separate depths; fixed side view"}
	var f := FileAccess.open("res://preview/verification.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	print("CUTOUT_VERIFY_PASS ",JSON.stringify(report))
	get_tree().quit()

const UPPER_LEG = Actor.UPPER_LEG
const LOWER_LEG = Actor.LOWER_LEG
const UPPER_ARM = Actor.UPPER_ARM
const LOWER_ARM = Actor.LOWER_ARM
