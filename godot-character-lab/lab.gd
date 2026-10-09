extends Node2D

const AIActor = preload("res://ai_actor.gd")
const ModelActor = preload("res://model_actor.gd")
var data: Dictionary
var skin_actor: Node2D
var ai_actor: Node2D
var model_actor: Node2D
var action := "walk"
var frame := 0
var elapsed := 0.0
var paused := false
var speed := 1.0
var smooth := false
var action_label: Label
var measurements_label: Label
var model_label: Label
var caption_label: Label
var export_button: Button
var export_running := false

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/character.json"))
	skin_actor = AIActor.new()
	skin_actor.configure(data)
	skin_actor.skin_only = true
	skin_actor.position = Vector2(212,530)
	skin_actor.scale = Vector2(3,3)
	add_child(skin_actor)
	ai_actor = AIActor.new()
	ai_actor.configure(data)
	ai_actor.position = Vector2(585,530)
	ai_actor.scale = Vector2(3,3)
	add_child(ai_actor)
	model_actor = ModelActor.new()
	model_actor.position = Vector2(951,530)
	model_actor.scale = Vector2(3,3)
	add_child(model_actor)
	build_ui()
	apply_pose()
	print("CHARACTER_LAB_READY: real AI skin + modular generated armor/hair; original 3D -> transparent 128px viewport")

func label(at: Vector2, content: String, size: int, color := Color("a8b9cc")) -> Label:
	var item := Label.new()
	item.position = at
	item.text = content
	item.add_theme_font_size_override("font_size",size)
	item.add_theme_color_override("font_color",color)
	add_child(item)
	return item

func button(at: Vector2, content: String, callback: Callable, width := 90.0) -> Button:
	var item := Button.new()
	item.text = content
	item.position = at
	item.size = Vector2(width,32)
	item.focus_mode = Control.FOCUS_NONE
	item.pressed.connect(callback)
	add_child(item)
	return item

func toggle(at: Vector2, content: String, value: bool, callback: Callable) -> void:
	var item := CheckButton.new()
	item.text = content
	item.position = at
	item.button_pressed = value
	item.focus_mode = Control.FOCUS_NONE
	item.toggled.connect(callback)
	add_child(item)

func build_ui() -> void:
	label(Vector2(28,16),"CHARACTER PIPELINE / AI 2D vs 3D TO PIXELS",25,Color("e6d797"))
	label(Vector2(28,54),"Same actions and original foot / hand targets. Skin / clothes / hair / weapons tested separately.",15)
	button(Vector2(28,92),"Walk",func() -> void: play("walk"))
	button(Vector2(128,92),"Attack",func() -> void: play("slash"))
	button(Vector2(228,92),"Idle",func() -> void: play("idle"))
	button(Vector2(328,92),"Pause [P]",func() -> void: paused = not paused,100)
	button(Vector2(438,92),"Frame [N]",next_frame,100)
	var speed_menu := OptionButton.new()
	speed_menu.position = Vector2(548,92)
	speed_menu.size = Vector2(105,32)
	speed_menu.focus_mode = Control.FOCUS_NONE
	for title in ["Speed 1x","Speed 0.5x","Speed 0.25x"]:
		speed_menu.add_item(title)
	speed_menu.item_selected.connect(func(index: int) -> void: speed = [1.0,.5,.25][index])
	add_child(speed_menu)
	button(Vector2(668,92),"Flip [F]",func() -> void:
		for actor in [skin_actor,ai_actor,model_actor]:
			actor.facing *= -1
		apply_pose()
	)
	button(Vector2(768,92),"3D view [R]",rotate_view,110)
	export_button = button(Vector2(894,92),"Bake 3D PNGs",bake_frames,155)
	button(Vector2(1062,92),"3D outfit [O]",cycle_outfit,112)
	toggle(Vector2(28,132),"AI anchor align",true,func(on: bool) -> void:
		skin_actor.align_feet = on
		ai_actor.align_feet = on
		apply_pose()
	)
	toggle(Vector2(208,132),"Pose overlay",false,func(on: bool) -> void:
		skin_actor.ghost = on
		ai_actor.ghost = on
		apply_pose()
	)
	toggle(Vector2(390,132),"Clothes",true,func(on: bool) -> void:
		ai_actor.dressed = on
		model_actor.outfit = "knight" if on else "none"
		apply_pose()
	)
	toggle(Vector2(530,132),"Hair",true,func(on: bool) -> void:
		ai_actor.hair = on
		model_actor.hair = "gold" if on else "none"
		apply_pose()
	)
	toggle(Vector2(640,132),"Weapon",true,func(on: bool) -> void:
		ai_actor.weapon = on
		model_actor.weapon = "steel" if on else "none"
		apply_pose()
	)
	toggle(Vector2(790,132),"VFX",true,func(on: bool) -> void:
		ai_actor.effects = on
		model_actor.effects = on
		apply_pose()
	)
	toggle(Vector2(895,132),"Smooth 3D",false,func(on: bool) -> void: smooth = on)
	button(Vector2(1048,132),"3D hair [H]",cycle_hair,126)
	label(Vector2(45,196),"01 / AI SKIN BASE",19,Color("e6d797"))
	label(Vector2(417,196),"02 / AI CLOTHES + HAIR",19,Color("e6d797"))
	label(Vector2(789,196),"03 / REAL 3D -> 2D",19,Color("e6d797"))
	label(Vector2(45,230),"Generated from exact pose reference",13)
	label(Vector2(417,230),"Transparent equipment overlays",13)
	label(Vector2(789,230),"Original meshes + shared joint controls",13)
	label(Vector2(45,555),"AI may change contours and joint positions.",13)
	label(Vector2(417,555),"Floor alignment fixes position, not anatomy.",13)
	label(Vector2(789,555),"Weapon geometry never changes length.",13)
	action_label = label(Vector2(30,598),"",17,Color("e6d797"))
	measurements_label = label(Vector2(30,638),"",14)
	model_label = label(Vector2(650,638),"",14)
	caption_label = label(Vector2(30,744),"P: pause  |  N: next frame  |  F: mirror  |  R: camera view  |  Space: attack  |  W: walk",14)
	label(Vector2(30,781),"Prototype comparison: AI assets are generated; 3D model and animation are procedural original geometry.",13)

func play(action_: String) -> void:
	if export_running:
		return
	action = action_
	frame = 0
	elapsed = 0.0
	apply_pose()

func next_frame() -> void:
	if export_running:
		return
	paused = true
	frame = (frame+1)%data.animations[action].frames.size()
	elapsed = 0.0
	apply_pose()

func rotate_view() -> void:
	model_actor.camera_angle = 55.0 if model_actor.camera_angle < 40 else (90.0 if model_actor.camera_angle < 80 else 18.0)
	apply_pose()

func cycle_outfit() -> void:
	model_actor.outfit = "scout" if model_actor.outfit == "knight" else "knight"
	apply_pose()

func cycle_hair() -> void:
	model_actor.hair = "copper" if model_actor.hair == "gold" else "gold"
	apply_pose()

func apply_pose() -> void:
	skin_actor.set_pose(action,frame)
	ai_actor.set_pose(action,frame)
	var blend := elapsed/float(data.animations[action].frames[frame].duration) if smooth and not paused else 0.0
	model_actor.set_pose(action,frame,blend)

func _process(delta: float) -> void:
	if data.is_empty():
		return
	if not paused and not export_running:
		elapsed += delta*speed
		while elapsed >= float(data.animations[action].frames[frame].duration):
			elapsed -= float(data.animations[action].frames[frame].duration)
			frame = (frame+1)%data.animations[action].frames.size()
		apply_pose()
	var index: int = ai_actor.pose_index()
	var skin_error: float = ai_actor.measurements.skin[index].foot_error
	var armor_error: float = ai_actor.measurements.armor[index].foot_error
	action_label.text = "Action: %s | frame %d/%d | %s" % [action,frame+1,data.animations[action].frames.size(),"PAUSED" if paused else "PLAYING"]
	measurements_label.text = "AI raw floor error (logical pixels):\nSkin: %+.2f px  |  Clothes: %+.2f px\nCorrection is translation only; no pose resizing.\nAI has 4 attack keys; 3D has all 6 keys." % [skin_error,armor_error]
	model_label.text = "3D render: 128 x 128 / orthographic / transparent\nCamera: %.0f degrees | skin, outfit, hair & sword are meshes\nClothing follows the same joints. Depth handles occlusion.\nBake exports cropped PNGs + floor offsets." % model_actor.camera_angle

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P: paused = not paused
			KEY_N: next_frame()
			KEY_R: rotate_view()
			KEY_O: cycle_outfit()
			KEY_H: cycle_hair()
			KEY_F:
				for actor in [skin_actor,ai_actor,model_actor]:
					actor.facing *= -1
				apply_pose()
			KEY_SPACE: play("slash")
			KEY_W: play("walk")

func _draw() -> void:
	for x in range(24,1190,24):
		for y in range(181,580,24):
			draw_rect(Rect2(x,y,23,23),Color("101a28"))
	for x in [30,402,774]:
		draw_rect(Rect2(x,185,360,397),Color("33475d"),false,1)
	for anchor in [Vector2(212,530),Vector2(585,530),Vector2(951,530)]:
		draw_line(anchor+Vector2(-110,2),anchor+Vector2(110,2),Color("647789"),1)

func bake_frames() -> void:
	if export_running:
		return
	export_running = true
	export_button.disabled = true
	var previous_action := action
	var previous_frame := frame
	var previous_paused := paused
	paused = true
	var frames := {"version":1,"camera_degrees":model_actor.camera_angle,"origin":[],"loadout":{"outfit":model_actor.outfit,"hair":model_actor.hair,"weapon":model_actor.weapon},"animations":{}}
	var origin: Vector2 = model_actor.camera.unproject_position(Vector3.ZERO)
	frames.origin = [origin.x,origin.y]
	for action_ in ["idle","walk","slash"]:
		var records := []
		var folder := "res://exports/baked/%s" % action_
		DirAccess.make_dir_recursive_absolute(folder)
		for i in range(data.animations[action_].frames.size()):
			model_actor.set_pose(action_,i)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image: Image = model_actor.viewport.get_texture().get_image()
			var rect := image.get_used_rect()
			var path := "%s/%02d.png" % [folder,i]
			assert(image.get_region(rect).save_png(path) == OK)
			records.append({"path":path,"offset":[rect.position.x-origin.x,rect.position.y-origin.y],"size":[rect.size.x,rect.size.y],"duration":data.animations[action_].frames[i].duration})
		frames.animations[action_] = records
	var file := FileAccess.open("res://exports/baked/frames.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(frames,"\t"))
	file.close()
	action = previous_action
	frame = previous_frame
	paused = previous_paused
	export_running = false
	export_button.disabled = false
	caption_label.text = "BAKED: exports/baked/frames.json + 11 cropped PNGs (current loadout; next export replaces this preview set)."
	apply_pose()
	print("BAKE_COMPLETE: 11 cropped frames + fixed floor offsets")
