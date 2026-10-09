extends Node2D

const Actor = preload("res://wardrobe_actor_v2.gd")
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
var edit_target := 0
var menus := {}

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Arial"])
	hero = Actor.new()
	hero.position = Vector2(275,710)
	hero.scale = Vector2(1.35,1.35)
	add_child(hero)
	hero.apply_preset("casual")
	preview = Actor.new()
	preview.position = Vector2(885,710)
	preview.scale = Vector2(1.35,1.35)
	add_child(preview)
	preview.apply_preset("bikini")
	build_ui()
	textures_reference = load("res://assets/original-reference.png")
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("WARDROBE_READY: complete costume parts with skin, armor/casual/bikini, independent torso/arms/legs/cape")
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

func check(at: Vector2,text_: String,initial: bool,callback: Callable) -> CheckButton:
	var node := CheckButton.new()
	node.position = at
	node.text = text_
	node.button_pressed = initial
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",16)
	node.toggled.connect(callback)
	add_child(node)
	return node

func build_ui() -> void:
	label(Vector2(28,18),"2.5D 换装室 · 服装与皮肤一起画",28)
	label(Vector2(28,59),"沿用骑士骨架：铠甲、日常服、比基尼各自有完整的躯干和肢体部件，可按部位混搭。",17)
	button(Vector2(28,99),"走路 / 待机",func(): autowalk = not autowalk; stepping = false)
	button(Vector2(146,99),"挥剑（空格）",func(): attack_time = 0.0; stepping = false)
	button(Vector2(275,99),"暂停 P",func(): paused = not paused; stepping = false)
	button(Vector2(366,99),"逐帧 N",advance_frame)
	button(Vector2(459,99),"恢复蓝甲",func():
		for actor in edited(): actor.apply_preset("armor_blue")
		sync_menus())
	button(Vector2(603,99),"换武器：钢 / 金",func():
		for actor in edited(): actor.golden_weapon = not actor.golden_weapon)
	button(Vector2(760,99),"导出 PNG 动作帧",func(): if not exporting: await bake(hero))
	button(Vector2(939,99),"0.5×",func(): speed = .5)
	button(Vector2(1001,99),"1×",func(): speed = 1)
	label(Vector2(28,145),"编辑",16)
	option("target",Vector2(73,143),["左侧","右侧","两侧"],func(index: int): edit_target = index; sync_menus(),85)
	label(Vector2(178,145),"整套",16)
	option("preset",Vector2(222,143),["蓝甲","红甲","日常","比基尼","混搭"],func(index: int):
		if index == 4: return
		for actor in edited(): actor.apply_preset(["armor_blue","armor_red","casual","bikini"][index])
		sync_menus(),92)
	menus.preset.set_item_disabled(4,true)
	label(Vector2(334,145),"上装",16)
	option("top",Vector2(378,143),["蓝甲","红甲","日常","比基尼"],func(index: int):
		for actor in edited():
			actor.top_style = ["armor","armor","casual","bikini"][index]
			if index in [0,1]: actor.outfit = "blue" if index == 0 else "red"
		sync_menus(),115)
	label(Vector2(516,145),"手臂",16)
	option("arms",Vector2(560,143),["铠甲","衣袖+手套","泳装裸臂"],func(index: int):
		for actor in edited(): actor.arm_style = ["armor","casual","bikini"][index]
		sync_menus(),145)
	label(Vector2(729,145),"腿脚",16)
	option("legs",Vector2(774,143),["铠甲","日常靴","泳装赤足"],func(index: int):
		for actor in edited(): actor.leg_style = ["armor","casual","bikini"][index]
		sync_menus(),100)
	label(Vector2(900,145),"披风",16)
	option("cape",Vector2(944,143),["无","蓝","红"],func(index: int):
		for actor in edited(): actor.cape_style = ["none","blue","red"][index]
		sync_menus(),90)
	check(Vector2(28,184),"平滑关节",false,func(value: bool): smooth = value)
	check(Vector2(178,184),"骨架检查",false,func(value: bool): for actor in [hero,preview]: actor.debug_bones = value)
	menus.hair = check(Vector2(334,184),"长发",true,func(value: bool): for actor in edited(): actor.show_hair = value)
	menus.weapon = check(Vector2(440,184),"武器",true,func(value: bool): for actor in edited(): actor.show_weapon = value)
	button(Vector2(564,187),"正面 / 微侧转",func(): for actor in edited(): actor.angle = 10 if actor.angle == 0 else 0)
	label(Vector2(80,234),"走路预览 / 可操作角色",21)
	label(Vector2(752,234),"另一套服装 · 挥剑预览",21)
	label(Vector2(28,744),"A / D 移动与转向   空格挥剑   P 暂停   N 逐帧   四帧走路约 4.5 fps",18)
	status = label(Vector2(28,784),"正在加载贴图…",16,Color("89d6c4"))
	label(Vector2(149,840),"整套预设和上装 / 手臂 / 腿脚 / 披风可独立切换，动作继续播放。",16)
	label(Vector2(149,878),"不使用肉色木偶底层；衣服和露出的皮肤是同一部件，关节与混搭边缘仍需修整。",16,Color("efc18d"))
	sync_menus()

func edited() -> Array:
	return [hero,preview] if edit_target == 2 else ([preview] if edit_target == 1 else [hero])

func option(key: String,at: Vector2,items: Array,callback: Callable,width: float) -> void:
	var node := OptionButton.new()
	node.position = at
	node.custom_minimum_size = Vector2(width,32)
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",16)
	for item in items: node.add_item(item)
	node.item_selected.connect(callback)
	add_child(node)
	menus[key] = node

func sync_menus() -> void:
	if not menus.has("top"): return
	var actor: Node2D = edited()[0]
	menus.top.select((0 if actor.outfit == "blue" else 1) if actor.top_style == "armor" else (2 if actor.top_style == "casual" else 3))
	menus.arms.select(["armor","casual","bikini"].find(actor.arm_style))
	menus.legs.select(["armor","casual","bikini"].find(actor.leg_style))
	menus.cape.select(["none","blue","red"].find(actor.cape_style))
	menus.hair.set_pressed_no_signal(actor.show_hair)
	menus.weapon.set_pressed_no_signal(actor.show_weapon)
	var preset := 4
	if actor.top_style == actor.arm_style and actor.arm_style == actor.leg_style:
		if actor.top_style == "armor" and actor.cape_style == actor.outfit:
			preset = 0 if actor.outfit == "blue" else 1
		elif actor.top_style == "casual" and actor.cape_style == "none": preset = 2
		elif actor.top_style == "bikini" and actor.cape_style == "none": preset = 3
	menus.preset.select(preset)

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
	status.text = "左：%s %d  [%s / %s / %s]    右：%s %d  [%s]    独立剑长 %.1f" % [hero.current_action,hero.current_frame+1,hero.top_style,hero.arm_style,hero.leg_style,preview.current_action,preview.current_frame+1,preview.top_style,hero.sword_grip.distance_to(hero.sword_tip)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: attack_time = 0.0; stepping = false
			KEY_P: paused = not paused; stepping = false
			KEY_N: advance_frame()

func _draw() -> void:
	for x in range(0,1280,32):
		draw_line(Vector2(x,272),Vector2(x,727),Color(.08,.115,.17),1)
	for y in range(272,727,32):
		draw_line(Vector2(0,y),Vector2(1280,y),Color(.08,.115,.17),1)
	draw_line(Vector2(25,712),Vector2(615,712),Color("788ba6"),2)
	draw_line(Vector2(667,712),Vector2(1250,712),Color("788ba6"),2)
	draw_line(Vector2(640,269),Vector2(640,727),Color("293a50"),1)
	if textures_reference != null:
		draw_texture_rect(textures_reference,Rect2(28,819,100,100),false)

func bake(actor: Node2D) -> Dictionary:
	exporting = true
	var path := "res://exports/%s_%s" % [actor.wardrobe_key(),("gold" if actor.golden_weapon else "steel") if actor.show_weapon else "no_weapon"]
	DirAccess.make_dir_recursive_absolute(path)
	var manifest := {"origin":[0,0],"outfit":actor.outfit,"top":actor.top_style,"arms":actor.arm_style,"legs":actor.leg_style,"cape":actor.cape_style,"weapon":"gold" if actor.golden_weapon else "steel","source":"original atlases + assets/corrections.json (native rectangular cutouts, per-part pivots)","animations":{},"note":"Each runtime costume part includes clothing and exposed skin. Offline exports are full composite snapshots."}
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
	var outfit_checks := 0
	var mixed_checks := 0
	var hand_visibility_checks := 0
	for preset in ["armor_blue","armor_red","casual","bikini"]:
		hero.apply_preset(preset)
		for action in ["idle","walk","slash"]:
			var count := 1 if action == "idle" else (4 if action == "walk" else 6)
			for frame in range(count):
				hero.set_pose(action,frame,0,frame*.22)
				assert_one_style(hero)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var image: Image = hero.viewport.get_texture().get_image()
				var bounds := image.get_used_rect()
				assert(bounds.position.x > 1 and bounds.position.y > 1 and bounds.end.x < 447 and bounds.end.y < 447,"Costume clipped: "+preset+action+str(frame))
				image.save_png("res://preview/%s_%s_%02d.png" % [preset,action,frame])
				outfit_checks += 1
		# Test visible painted hands, not merely whether their mesh is enabled.
		hero.set_pose("idle",0)
		assert(hero.joints.far_hand.x < hero.joints.far_shoulder.x-25,"Free hand moved in front of torso")
		for side in ["near","far"]:
			var prefix: String = "" if hero.arm_style == "armor" else hero.arm_style+"_"
			var name_: String = prefix+side+"_forearm"
			var original_tint: Color = Color.WHITE
			if hero.mats[name_].get_shader_parameter("tint") != null:
				original_tint = hero.mats[name_].get_shader_parameter("tint")
			hero.mats[name_].set_shader_parameter("tint",Color(1,0,1))
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var probe: Image = hero.viewport.get_texture().get_image()
			var joint: Vector2 = hero.joints[side+"_hand"]
			var center: Vector2 = hero.camera.unproject_position(Vector3(joint.x,-joint.y,13 if side == "near" else -4))
			var visible_pixels := 0
			for y in range(int(center.y)-5,int(center.y)+6):
				for x in range(int(center.x)-5,int(center.x)+6):
					var c := probe.get_pixel(x,y)
					if c.a > .5 and c.r > .2 and c.b > .15 and c.g < .08: visible_pixels += 1
			hero.mats[name_].set_shader_parameter("tint",original_tint)
			assert(visible_pixels >= 2,"Hand hidden or fist not aligned: "+preset+" "+side)
			hand_visibility_checks += 1
	for top in ["armor","casual","bikini"]:
		for arms in ["armor","casual","bikini"]:
			for legs in ["armor","casual","bikini"]:
				hero.top_style = top
				hero.arm_style = arms
				hero.leg_style = legs
				hero.set_pose("slash",2)
				var old_joints: Dictionary = hero.joints.duplicate()
				var old_grip: Vector3 = hero.sword_grip
				var old_action: String = hero.current_action
				var old_frame: int = hero.current_frame
				assert_one_style(hero)
				hero.apply_preset("bikini")
				assert(hero.current_action == old_action and hero.current_frame == old_frame,"Wardrobe reset animation phase")
				assert(hero.joints == old_joints and hero.sword_grip.is_equal_approx(old_grip),"Equipment changed bone targets or weapon grip")
				mixed_checks += 1
	# Explicitly verify the two legs exchange front/back targets in the gait.
	var p0: Dictionary = hero.targets("walk",0)
	var p2: Dictionary = hero.targets("walk",2)
	assert(p0.near_ankle.x > p0.far_ankle.x and p2.near_ankle.x < p2.far_ankle.x,"Legs do not alternate")
	hero.set_pose("walk",0)
	preview.set_pose("slash",0)
	advance_frame()
	assert(hero.current_frame == 1 and preview.current_frame == 1,"Single-frame stepping skipped a pose")
	stepping = false
	for preset in ["armor_blue","armor_red","casual","bikini"]:
		hero.apply_preset(preset)
		await bake(hero)
		exporting = true
	hero.apply_preset("armor_red")
	hero.set_pose("idle",0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	hero.viewport.get_texture().get_image().save_png("res://preview/red-idle.png")
	hero.apply_preset("casual")
	hero.set_pose("walk",0)
	preview.apply_preset("bikini")
	preview.set_pose("slash",1)
	update_status()
	sync_menus()
	paused = true
	exporting = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://preview/comparison.png")
	var report := {"baseline_frames_checked":11,"outfit_poses_checked":outfit_checks,"mixed_combinations_checked":mixed_checks,"bone_lengths_checked":bone_checks,"weapon_length_and_grip_checked":weapon_checks,"hand_visibility_checks":hand_visibility_checks,"free_hand_behind_body":true,"clipped_frames":clipping,"legs_exchange":true,"neutral_body_loaded":false,"wardrobe_preserves_animation_phase":true,"unlit":true,"parts_independent":true,"technique":"complete costume+skin parts on shared articulated 3D planes; fixed side view"}
	var f := FileAccess.open("res://preview/verification.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	print("CUTOUT_VERIFY_PASS ",JSON.stringify(report))
	get_tree().quit()

func assert_one_style(actor: Node2D) -> void:
	var torsos := 0
	for name_ in ["torso_blue","torso_red","casual_torso","bikini_torso"]:
		if actor.parts[name_].visible: torsos += 1
	assert(torsos == 1,"Torso layers overlap or disappear")
	for side in ["near","far"]:
		for suffix in ["thigh","shin","boot","upper_arm","forearm"]:
			var visible := 0
			for prefix in ["","casual_","bikini_"]:
				if actor.parts[prefix+side+"_"+suffix].visible: visible += 1
			assert(visible == 1,"Outfit part duplicated/missing: "+side+suffix)
	for key in actor.parts:
		assert(not key.begins_with("base_"),"Cancelled mannequin layer still exists")

const UPPER_LEG = Actor.UPPER_LEG
const LOWER_LEG = Actor.LOWER_LEG
const UPPER_ARM = Actor.UPPER_ARM
const LOWER_ARM = Actor.LOWER_ARM
