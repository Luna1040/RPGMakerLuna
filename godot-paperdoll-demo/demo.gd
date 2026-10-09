extends Node2D

const Actor = preload("res://actor.gd")
var manifest: Dictionary
var base_actor: Node2D
var dressed_actor: Node2D
var slash_actor: Node2D
var hero: Node2D
var actors: Array = []
var selectors := {}
var debug_enabled := false
var playback_speed := 1.0
var swing_count := 0
var status: Label
var paused := false

func _ready() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/character.json"))
	base_actor = make_actor(Vector2(180,420))
	base_actor.mannequin = true
	base_actor.play("walk")
	dressed_actor = make_actor(Vector2(475,420))
	dressed_actor.play("walk")
	slash_actor = make_actor(Vector2(815,420))
	slash_actor.repeat_attack = true
	slash_actor.play("slash")
	hero = make_actor(Vector2(655,690))
	hero.action_event.connect(func(event: String) -> void:
		if event == "swing":
			swing_count += 1
	)
	build_ui()
	print("WARDROBE_READY: 4 walk poses, 6 attack poses, modular outfits, single shared weapon textures")

func make_actor(at: Vector2) -> Node2D:
	var actor := Actor.new()
	actor.configure(manifest)
	actor.position = at
	actor.scale = Vector2(3,3)
	add_child(actor)
	actors.append(actor)
	return actor

func label_at(at: Vector2, content: String, size: int, color := Color("a9bace")) -> Label:
	var label := Label.new()
	label.position = at
	label.text = content
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	add_child(label)
	return label

func selector(at: Vector2, title: String, values: Array, property: String, selected := 0) -> void:
	label_at(at,title,13)
	var button := OptionButton.new()
	button.focus_mode = Control.FOCUS_NONE
	button.position = at+Vector2(0,22)
	button.size = Vector2(125,32)
	for value in values:
		button.add_item(String(value).capitalize())
	button.select(selected)
	button.item_selected.connect(func(index: int) -> void:
		for actor in [dressed_actor,slash_actor,hero]:
			actor.set(property,values[index])
			actor.queue_redraw()
	)
	add_child(button)
	selectors[property] = button

func build_ui() -> void:
	label_at(Vector2(30,18),"ORIGINAL PIXEL CHARACTER / WARDROBE LAB",25,Color("e7d79b"))
	label_at(Vector2(30,54),"Fixed floor anchor  |  Cropped frames + offsets  |  Separate weapon + VFX  |  3x nearest pixels",14)
	selector(Vector2(30,86),"TOP / ARMOR",["knight","scout","none"],"outfit")
	selector(Vector2(170,86),"BOOTS",["knight","scout","none"],"boots")
	selector(Vector2(310,86),"HAIR",["gold","copper","none"],"hair")
	selector(Vector2(450,86),"WEAPON",["steel","gold","none"],"weapon")
	var cape_button := CheckButton.new()
	cape_button.focus_mode = Control.FOCUS_NONE
	cape_button.text = "Cape"
	cape_button.position = Vector2(595,106)
	cape_button.button_pressed = true
	cape_button.toggled.connect(func(on: bool) -> void:
		for actor in [dressed_actor,slash_actor,hero]:
			actor.cape = on
			actor.queue_redraw()
	)
	add_child(cape_button)
	var effect_button := CheckButton.new()
	effect_button.focus_mode = Control.FOCUS_NONE
	effect_button.text = "VFX"
	effect_button.position = Vector2(690,106)
	effect_button.button_pressed = true
	effect_button.toggled.connect(func(on: bool) -> void:
		for actor in [dressed_actor,slash_actor,hero]:
			actor.effects = on
			actor.queue_redraw()
	)
	add_child(effect_button)
	var bounds_button := CheckButton.new()
	bounds_button.focus_mode = Control.FOCUS_NONE
	bounds_button.text = "Anchors"
	bounds_button.position = Vector2(780,106)
	bounds_button.toggled.connect(func(on: bool) -> void:
		debug_enabled = on
		for actor in actors:
			actor.debug_bounds = on
			actor.queue_redraw()
	)
	add_child(bounds_button)
	var speed := OptionButton.new()
	speed.focus_mode = Control.FOCUS_NONE
	speed.position = Vector2(950,110)
	for title in ["Speed 1x","Speed 0.5x","Speed 0.25x"]:
		speed.add_item(title)
	speed.item_selected.connect(func(index: int) -> void: playback_speed = [1.0,0.5,0.25][index])
	add_child(speed)
	label_at(Vector2(48,166),"01 / BASE POSES",17,Color("e7d79b"))
	label_at(Vector2(340,166),"02 / SAME POSES + CLOTHES",17,Color("e7d79b"))
	label_at(Vector2(650,166),"03 / ATTACK + WEAPON + VFX",17,Color("e7d79b"))
	label_at(Vector2(48,435),"Light leg = near / dark leg = far",13)
	label_at(Vector2(340,435),"Top, boots, hair & cape are separate",13)
	label_at(Vector2(650,435),"One sword texture / fixed size every frame",13)
	label_at(Vector2(48,479),"PLAYABLE TEST",18,Color("e7d79b"))
	label_at(Vector2(48,513),"WASD / arrows: move\nSpace: attack | P: pause\nN: next frame (when paused)\n\nSlow playback: top-right menu\nChange clothes during an action.",14)
	status = label_at(Vector2(48,660),"",12)
	label_at(Vector2(30,722),"Original procedural pixel prototype. Art direction can be upgraded without changing the motion / wardrobe format.",14)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			start_attack()
		elif event.physical_keycode == KEY_P:
			paused = not paused
			for actor in actors:
				actor.paused = paused
		elif event.physical_keycode == KEY_N and paused:
			for actor in actors:
				actor.frame = (actor.frame+1) % manifest.animations[actor.animation].frames.size()
				actor.elapsed = 0.0
				actor.queue_redraw()
		get_viewport().set_input_as_handled()

func start_attack() -> void:
	if hero.animation != "slash":
		hero.play("slash",true)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(hero):
		return
	var move := Input.get_vector("ui_left","ui_right","ui_up","ui_down")
	move += Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if hero.animation != "slash" and not paused:
		hero.position = (hero.position+move.limit_length()*110*delta).clamp(Vector2(430,678),Vector2(930,696))
		if move.x != 0:
			hero.facing = -1 if move.x < 0 else 1
		hero.play("walk" if move.length() > 0 else "idle")
	for actor in actors:
		actor.tick(delta*playback_speed)
	var rec: Dictionary = slash_actor.current_record()
	var body: Dictionary = rec.layers.body
	status.text = "Hero: %s / frame %d%s\nAttack body: %dx%d px | sword: fixed\nSwing events: %d" % [hero.animation,hero.frame+1," / PAUSED" if paused else "",body.size[0],body.size[1],swing_count]
	queue_redraw()

func _draw() -> void:
	for x in range(24,1090,24):
		for y in range(154,711,24):
			draw_rect(Rect2(x,y,23,23),Color("101927"))
	for area in [Rect2(30,156,290,303),Rect2(330,156,300,303),Rect2(640,156,430,303),Rect2(30,474,1040,237)]:
		draw_rect(area,Color("314255"),false,1)
	for at in [Vector2(180,420),Vector2(475,420),Vector2(815,420)]:
		draw_line(at+Vector2(-95,3),at+Vector2(95,3),Color("455973"),1)
	if is_instance_valid(hero):
		draw_line(Vector2(410,700),Vector2(1025,700),Color("455973"),1)
		for actor in actors:
			var points := PackedVector2Array()
			for i in range(24):
				var a := TAU*i/24.0
				points.append(actor.position+Vector2(cos(a)*27,sin(a)*5+3))
			draw_colored_polygon(points,Color(0.01,0.02,0.035,0.65))
