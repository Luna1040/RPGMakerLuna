extends Node2D

const Model = preload("res://model.gd")
const PNGActor = preload("res://png_actor.gd")
var data: Dictionary
var live: Node2D
var baked: Node2D
var action := "walk"
var frame := 0
var elapsed := 0.0
var paused := false
var speed := 1.0
var baking := false
var smooth := false
var facing := 1
var config := {"body":"female","outfit":"knight","hair":"gold","weapon":"steel","effects":true,"view":18.0}
var controls: Array = []
var status: Label
var note: Label
var baked_info: Label
var live_info: Label
var stored_sets := 0
var set_path := ""
var menus := {}
var effect_control: CheckButton

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/character.json"))
	baked = PNGActor.new()
	baked.position = Vector2(305,560)
	baked.scale = Vector2(4,4)
	add_child(baked)
	make_live()
	build_ui()
	await ensure_baked()
	print("RENDER_PIPELINE_READY: pure PNG player vs live outlined 3D; featureless adult fitting bases without underwear")

func make_live() -> void:
	if is_instance_valid(live):
		remove_child(live)
		live.queue_free()
	live = Model.new()
	live.body_type = config.body
	live.outfit = config.outfit
	live.hair = config.hair
	live.weapon = config.weapon
	live.effects = config.effects
	live.camera_angle = config.view
	live.position = Vector2(850,560)
	live.scale = Vector2(4,4)
	add_child(live)
	apply_pose()

func label(at: Vector2, text: String, size: int, color := Color("b0bfd1")) -> Label:
	var node := Label.new()
	node.position = at
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	add_child(node)
	return node

func button(at: Vector2, text: String, callback: Callable, width := 100.0) -> Button:
	var node := Button.new()
	node.position = at
	node.size = Vector2(width,32)
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.pressed.connect(callback)
	add_child(node)
	controls.append(node)
	return node

func sync_menus() -> void:
	for key in menus:
		menus[key].control.select(menus[key].values.find(config[key]))
	if is_instance_valid(effect_control):
		effect_control.set_pressed_no_signal(config.effects)

func menu(at: Vector2, title: String, choices: Array, values: Array, key: String, initial: int) -> void:
	label(at,title,12)
	var node := OptionButton.new()
	node.position = at+Vector2(0,20)
	node.size = Vector2(145,32)
	node.focus_mode = Control.FOCUS_NONE
	for choice in choices:
		node.add_item(choice)
	node.select(initial)
	node.item_selected.connect(func(index: int) -> void:
		config[key] = values[index]
		if key == "body":
			make_live()
		await ensure_baked()
	)
	add_child(node)
	controls.append(node)
	menus[key] = {"control":node,"values":values}

func build_ui() -> void:
	label(Vector2(28,16),"SAME CHARACTER / PRE-RENDERED PNG vs LIVE 3D",25,Color("e9d699"))
	label(Vector2(28,54),"Original adult fitting bases | no baked underwear | separate body, clothes, hair, weapon and VFX",14)
	menu(Vector2(28,84),"BODY",["Female adult","Male adult"],["female","male"],"body",0)
	menu(Vector2(188,84),"OUTFIT",["Neutral base","Knight","Scout","Low-neck dress","Swimwear"],["none","knight","scout","dress","swim"],"outfit",1)
	menu(Vector2(348,84),"HAIR",["Gold ponytail","Copper ponytail","Short hair","No hair"],["gold","copper","short","none"],"hair",0)
	menu(Vector2(508,84),"VIEW",["Side 18 deg","3/4 55 deg","Front 90 deg"],[18.0,55.0,90.0],"view",0)
	menu(Vector2(668,84),"WEAPON",["Steel sword","Gold sword","No weapon"],["steel","gold","none"],"weapon",0)
	var effect := CheckButton.new()
	effect_control = effect
	effect.position = Vector2(830,105)
	effect.text = "VFX"
	effect.focus_mode = Control.FOCUS_NONE
	effect.button_pressed = true
	effect.toggled.connect(func(on: bool) -> void:
		config.effects = on
		await ensure_baked()
	)
	add_child(effect)
	controls.append(effect)
	button(Vector2(930,105),"Re-bake",func() -> void: await ensure_baked(true),110)
	button(Vector2(1049,105),"2D base",show_ai_base,90)
	button(Vector2(28,151),"Walk",func() -> void: play("walk"))
	button(Vector2(138,151),"Attack",func() -> void: play("slash"))
	button(Vector2(248,151),"Idle",func() -> void: play("idle"))
	button(Vector2(358,151),"Pause [P]",func() -> void: paused = not paused)
	button(Vector2(468,151),"Frame [N]",next_frame)
	button(Vector2(578,151),"Mirror [F]",func() -> void:
		facing *= -1
		apply_pose()
	)
	var speed_menu := OptionButton.new()
	speed_menu.position = Vector2(688,151)
	speed_menu.size = Vector2(100,32)
	speed_menu.focus_mode = Control.FOCUS_NONE
	for choice in ["Speed 1x","Speed 0.5x","Speed 0.25x"]:
		speed_menu.add_item(choice)
	speed_menu.item_selected.connect(func(index: int) -> void: speed = [1.0,.5,.25][index])
	add_child(speed_menu)
	controls.append(speed_menu)
	var interpolate := CheckButton.new()
	interpolate.position = Vector2(806,151)
	interpolate.text = "Live smooth"
	interpolate.focus_mode = Control.FOCUS_NONE
	interpolate.toggled.connect(func(on: bool) -> void: smooth = on)
	add_child(interpolate)
	controls.append(interpolate)
	label(Vector2(49,216),"PRE-RENDERED PNG FRAMES",20,Color("e9d699"))
	label(Vector2(608,216),"LIVE LOW-RES 3D TO 2D",20,Color("e9d699"))
	label(Vector2(49,249),"Disk PNGs + offsets. This player creates no 3D scene.",13)
	label(Vector2(608,249),"Same model, view, palette, outline and pose.",13)
	baked_info = label(Vector2(49,600),"",13)
	live_info = label(Vector2(608,600),"",13)
	status = label(Vector2(28,688),"",16,Color("e9d699"))
	note = label(Vector2(28,726),"",13)
	label(Vector2(28,786),"P: pause | N: step | F: mirror | Space: attack | W: walk. Garments are equipment; base has no private anatomy details.",13)

func show_ai_base() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "AI original fitting base / neutral adult mannequin"
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(Image.load_from_file("res://assets/ai-body-reference-v2.png"))
	picture.custom_minimum_size = Vector2(600,600)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dialog.add_child(picture)
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(620,650))

func apply_config(actor: Node2D) -> void:
	actor.outfit = config.outfit
	actor.hair = config.hair
	actor.weapon = config.weapon
	actor.effects = config.effects
	actor.camera_angle = config.view

func bundle_path() -> String:
	return "res://exports/sets/pixel_v3/%s_%s_%s_%s_v%d_fx%d/frames.json" % [config.body,config.outfit,config.hair,config.weapon,int(config.view),int(config.effects)]

func ensure_baked(force := false) -> void:
	if baking:
		return
	baking = true
	for control in controls:
		control.disabled = true if control is BaseButton else false
	apply_config(live)
	live.set_pose(action,frame)
	set_path = bundle_path()
	if force or not FileAccess.file_exists(set_path):
		status.text = "Baking the selected loadout..."
		var baker := Model.new()
		baker.body_type = config.body
		apply_config(baker)
		add_child(baker)
		baker.hide()
		var origin: Vector2 = baker.camera.unproject_position(Vector3.ZERO)
		var result := {"version":2,"loadout":config.duplicate(),"origin":[origin.x,origin.y],"render_size":[128,128],"style":"3-band color + 1px outline","animations":{}}
		var directory := set_path.get_base_dir()
		for action_ in ["idle","walk","slash"]:
			var records := []
			DirAccess.make_dir_recursive_absolute(directory+"/"+action_)
			for index in range(data.animations[action_].frames.size()):
				baker.set_pose(action_,index)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var image: Image = baker.pixel_viewport.get_texture().get_image()
				var rect := image.get_used_rect()
				var path := "%s/%s/%02d.png" % [directory,action_,index]
				assert(rect.size != Vector2i.ZERO)
				assert(image.get_region(rect).save_png(path) == OK)
				records.append({"path":path,"size":[rect.size.x,rect.size.y],"offset":[rect.position.x-origin.x,rect.position.y-origin.y],"duration":data.animations[action_].frames[index].duration})
			result.animations[action_] = records
		var file := FileAccess.open(set_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
		remove_child(baker)
		baker.queue_free()
		await get_tree().process_frame
		stored_sets += 1
	baked.load_bundle(set_path)
	baking = false
	for control in controls:
		control.disabled = false
	apply_pose()
	note.text = "PNG set: "+set_path.trim_prefix("res://")+"\nChanging a loadout loads its cached PNG set or bakes it once. Left playback uses textures only."
	print("PNG_SET_READY: "+set_path)

func apply_pose() -> void:
	if not is_instance_valid(live):
		return
	live.facing = facing
	baked.facing = facing
	var blend := elapsed/float(data.animations[action].frames[frame].duration) if smooth and not paused else 0.0
	live.set_pose(action,frame,blend)
	baked.set_pose(action,frame)

func play(action_: String) -> void:
	if baking:
		return
	action = action_
	frame = 0
	elapsed = 0.0
	apply_pose()

func next_frame() -> void:
	if baking:
		return
	paused = true
	frame = (frame+1)%data.animations[action].frames.size()
	elapsed = 0
	apply_pose()

func _process(delta: float) -> void:
	if baking or not is_instance_valid(live) or not is_instance_valid(status):
		return
	if not paused:
		elapsed += delta*speed
		while elapsed >= float(data.animations[action].frames[frame].duration):
			elapsed -= float(data.animations[action].frames[frame].duration)
			frame = (frame+1)%data.animations[action].frames.size()
		apply_pose()
	status.text = "%s / %s | %s frame %d/%d | %s" % [config.body,config.outfit,action,frame+1,data.animations[action].frames.size(),"PAUSED" if paused else "PLAYING"]
	if not baked.bundle.is_empty():
		var record: Dictionary = baked.bundle.animations[action][frame]
		baked_info.text = "Current PNG: %d x %d px\nOrigin offset: %.2f, %.2f | 11 files per loadout\nCamera / light changes require another baked set." % [record.size[0],record.size[1],record.offset[0],record.offset[1]]
	live_info.text = "Live target: 128 x 128 | orthographic %.0f deg\nFixed bone lengths and sword mesh\nClothing and body share joint transforms." % config.view

func _unhandled_input(event: InputEvent) -> void:
	if baking:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P: paused = not paused
			KEY_N: next_frame()
			KEY_SPACE: play("slash")
			KEY_W: play("walk")
			KEY_F:
				facing *= -1
				apply_pose()

func _draw() -> void:
	for x in range(24,1130,24):
		for y in range(207,660,24):
			draw_rect(Rect2(x,y,23,23),Color("101a29"))
	for x in [30,589]:
		draw_rect(Rect2(x,207,535,456),Color("3c4d65"),false,1)
	for at in [Vector2(305,560),Vector2(850,560)]:
		draw_line(at+Vector2(-150,2),at+Vector2(150,2),Color("62758d"),1)
