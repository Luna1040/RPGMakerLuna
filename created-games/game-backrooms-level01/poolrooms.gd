extends Node3D

const PLAYER_SPEED := 4.7
const CELL_H := 3.2

var player: CharacterBody3D
var camera: Camera3D
var hud: Label
var toast: Label
var overlay: ColorRect
var paused := false
var finished := false
var valves_on := {}
var nearby_target: Node3D
var look_y := 0.0
var look_x := 0.0

var tile_mat: StandardMaterial3D
var grout_mat: StandardMaterial3D
var water_mat: StandardMaterial3D
var brass_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D


func _ready() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for key in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		var event := InputEventKey.new()
		event.keycode = key
		var action := "move_left" if key in [KEY_A, KEY_LEFT] else "move_right" if key in [KEY_D, KEY_RIGHT] else "move_forward" if key in [KEY_W, KEY_UP] else "move_back"
		InputMap.action_add_event(action, event)
	_build_materials()
	_build_environment()
	_build_layout()
	_build_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_notice("LEVEL 37 · 无尽泳池\n按墙边的蓝色指示灯寻找三只回水阀。水声会带你走向出口。", 7.0)


func _build_materials() -> void:
	tile_mat = StandardMaterial3D.new()
	tile_mat.albedo_color = Color("80b9b7")
	tile_mat.roughness = 0.22
	tile_mat.metallic = 0.06
	tile_mat.clearcoat_enabled = true
	tile_mat.clearcoat = 0.35
	grout_mat = StandardMaterial3D.new()
	grout_mat.albedo_color = Color("318b91")
	grout_mat.roughness = 0.32
	water_mat = StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.19, 0.66, 0.7, 0.48)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.12
	water_mat.metallic = 0.18
	water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	brass_mat = StandardMaterial3D.new()
	brass_mat.albedo_color = Color("b89a57")
	brass_mat.metallic = 0.68
	brass_mat.roughness = 0.3
	dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color("111d20")
	dark_mat.roughness = 0.84


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("16343b")
	sky_mat.sky_horizon_color = Color("699c9d")
	sky_mat.ground_bottom_color = Color("17292c")
	sky_mat.ground_horizon_color = Color("477579")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("78b8bd")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.28
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-57), deg_to_rad(31), 0)
	sun.light_color = Color("a7ffff")
	sun.light_energy = 0.48
	sun.shadow_enabled = true
	add_child(sun)
	var ambient := AudioStreamPlayer.new()
	ambient.name = "Poolroom ambience"
	ambient.volume_db = -15.0
	add_child(ambient)
	var stream := load("res://audio/level0_hum.wav") as AudioStream
	if stream != null:
		ambient.stream = stream
		ambient.play()


func _build_layout() -> void:
	# Each chamber keeps its own straight lines; the larger route intentionally
	# folds back on itself, with shallow water over a tiled floor.
	_room(Vector2(0, 0), 18, 18, ["east"], true)
	_room(Vector2(12, 0), 10, 5, ["west", "east"], true)
	_room(Vector2(23, 0), 14, 14, ["west", "north"], true)
	_room(Vector2(23, -11), 5, 8, ["south", "north"], false)
	_room(Vector2(23, -23), 20, 16, ["south", "east"], true)
	_room(Vector2(39, -23), 12, 5, ["west", "east"], true)
	_room(Vector2(51, -23), 18, 20, ["west", "south"], true)
	_room(Vector2(51, -9), 5, 8, ["north", "south"], false)
	_room(Vector2(51, 3), 18, 18, ["north", "east"], true)
	_room(Vector2(65, 3), 10, 5, ["west", "east"], false)
	_room(Vector2(77, 3), 18, 20, ["west"], true)
	_add_column(Vector3(-5.8, 0, -5.8), 3.15)
	_add_column(Vector3(5.8, 0, -5.8), 3.15)
	_add_column(Vector3(-5.8, 0, 5.8), 3.15)
	_add_column(Vector3(5.8, 0, 5.8), 3.15)
	# The low ledges and submerged stair-like shelves make water depth readable.
	for i in range(5):
		_add_box("Submerged step", Vector3(1.3, 0.22, 0.72), Vector3(19.0 + i * 0.5, 0.24 + i * 0.12, -3.2), tile_mat, true)
	_add_sign(Vector3(-6.9, 1.9, 0.0), "POOL 37 / RETURN FLOW\nFOLLOW BLUE PILOT LIGHTS\n3 VALVES · THEN EAST EXIT", PI * 0.5)
	_add_sign(Vector3(23, 1.9, -28.8), "DEPTH CHANGES\nKEEP TO THE TILE EDGE", 0)
	_add_valve("01 · INLET", Vector3(27.9, 1.0, -26.7), 0)
	_add_valve("02 · BALANCE", Vector3(56.6, 1.0, -27.6), 1)
	_add_valve("03 · RETURN", Vector3(80.1, 1.0, 1.1), 2)
	_add_exit(Vector3(85.7, 0, 3))
	_add_dark_window(Vector3(51, 2.0, 3), 7)
	_add_lights()


func _room(center: Vector2, width: float, depth: float, openings: Array, pool: bool) -> void:
	var floor := _mesh_box("Substrate", Vector3(width, 0.3, depth), Vector3(center.x, -0.15, center.y), grout_mat)
	_add_collision(floor, Vector3(width, 0.3, depth))
	_add_box("Glossy turquoise tiles", Vector3(width - 0.08, 0.08, depth - 0.08), Vector3(center.x, 0.025, center.y), tile_mat, false)
	_add_grout_lines(center, width, depth)
	_add_roof(center, width, depth)
	# Water is represented as a separate optical surface so it never catches the player.
	if pool:
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(width - 3.0, depth - 3.0)
		water.mesh = plane
		water.position = Vector3(center.x, 0.075, center.y)
		water.material_override = water_mat
		add_child(water)
	var half_w := width * 0.5
	var half_d := depth * 0.5
	_wall_side(center, width, "north", openings.has("north"))
	_wall_side(center, width, "south", openings.has("south"))
	_wall_front_back(center, depth, "west", openings.has("west"))
	_wall_front_back(center, depth, "east", openings.has("east"))


func _wall_side(center: Vector2, width: float, side: String, opening: bool) -> void:
	var z := center.y + (-1.0 if side == "north" else 1.0) * 0.5 * _room_depth_at(center)
	var door_width := 3.0 if opening else 0.0
	var span := (_room_width_at(center) - door_width) * 0.5
	if opening:
		for sign in [-1.0, 1.0]:
			_add_box("Tiled wall", Vector3(span, CELL_H, 0.36), Vector3(center.x + sign * (door_width * 0.5 + span * 0.5), CELL_H * 0.5, z), tile_mat, true)
		_add_box("Door lintel", Vector3(door_width, 0.48, 0.36), Vector3(center.x, CELL_H - 0.24, z), tile_mat, true)
	else:
		_add_box("Tiled wall", Vector3(_room_width_at(center), CELL_H, 0.36), Vector3(center.x, CELL_H * 0.5, z), tile_mat, true)


func _wall_front_back(center: Vector2, depth: float, side: String, opening: bool) -> void:
	var width := _room_width_at(center)
	var x := center.x + (-1.0 if side == "west" else 1.0) * width * 0.5
	var room_depth := _room_depth_at(center)
	var door_width := 3.0 if opening else 0.0
	var span := (room_depth - door_width) * 0.5
	if opening:
		for sign in [-1.0, 1.0]:
			_add_box("Tiled wall", Vector3(0.36, CELL_H, span), Vector3(x, CELL_H * 0.5, center.y + sign * (door_width * 0.5 + span * 0.5)), tile_mat, true)
		_add_box("Door lintel", Vector3(0.36, 0.48, door_width), Vector3(x, CELL_H - 0.24, center.y), tile_mat, true)
	else:
		_add_box("Tiled wall", Vector3(0.36, CELL_H, room_depth), Vector3(x, CELL_H * 0.5, center.y), tile_mat, true)


func _room_width_at(center: Vector2) -> float:
	for item in [[Vector2(0,0),18.0,18.0],[Vector2(12,0),10.0,5.0],[Vector2(23,0),14.0,14.0],[Vector2(23,-11),5.0,8.0],[Vector2(23,-23),20.0,16.0],[Vector2(39,-23),12.0,5.0],[Vector2(51,-23),18.0,20.0],[Vector2(51,-9),5.0,8.0],[Vector2(51,3),18.0,18.0],[Vector2(65,3),10.0,5.0],[Vector2(77,3),18.0,20.0]]:
		if item[0] == center: return item[1]
	return 12.0


func _room_depth_at(center: Vector2) -> float:
	for item in [[Vector2(0,0),18.0,18.0],[Vector2(12,0),10.0,5.0],[Vector2(23,0),14.0,14.0],[Vector2(23,-11),5.0,8.0],[Vector2(23,-23),20.0,16.0],[Vector2(39,-23),12.0,5.0],[Vector2(51,-23),18.0,20.0],[Vector2(51,-9),5.0,8.0],[Vector2(51,3),18.0,18.0],[Vector2(65,3),10.0,5.0],[Vector2(77,3),18.0,20.0]]:
		if item[0] == center: return item[2]
	return 12.0


func _add_grout_lines(center: Vector2, width: float, depth: float) -> void:
	var step := 1.1
	var count_x := int(width / step)
	var count_z := int(depth / step)
	for x in range(count_x + 1):
		_add_box("Fine tile grout", Vector3(0.018, 0.006, depth - 0.18), Vector3(center.x - width * 0.5 + x * step, 0.071, center.y), grout_mat, false)
	for z in range(count_z + 1):
		_add_box("Fine tile grout", Vector3(width - 0.18, 0.006, 0.018), Vector3(center.x, 0.071, center.y - depth * 0.5 + z * step), grout_mat, false)


func _add_roof(center: Vector2, width: float, depth: float) -> void:
	_add_box("Ceiling", Vector3(width, 0.36, depth), Vector3(center.x, CELL_H + 0.2, center.y), dark_mat, true)


func _add_column(at: Vector3, height: float) -> void:
	_add_box("Square tiled pier", Vector3(0.9, height, 0.9), Vector3(at.x, height * 0.5, at.z), tile_mat, true)
	_add_box("Brass pier base", Vector3(1.08, 0.1, 1.08), Vector3(at.x, 0.18, at.z), brass_mat, false)


func _add_sign(at: Vector3, words: String, yaw: float) -> void:
	var board := _add_box("Enamel wayfinding sign", Vector3(2.15, 0.92, 0.10), at, dark_mat, false)
	board.rotation.y = yaw
	var label := Label3D.new()
	label.text = words
	label.font_size = 32
	label.pixel_size = 0.006
	label.modulate = Color("a8f9f0")
	label.position = at + Vector3(0, 0, -0.07)
	label.rotation.y = yaw
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(label)


func _add_valve(title: String, at: Vector3, index: int) -> void:
	var root := StaticBody3D.new()
	root.name = title
	root.position = at
	root.set_meta("valve_index", index)
	root.set_meta("interactable", true)
	add_child(root)
	_add_box_to(root, "Valve body", Vector3(0.62, 0.62, 0.18), brass_mat, false, Vector3.ZERO)
	var collider := CollisionShape3D.new()
	var valve_shape := BoxShape3D.new()
	valve_shape.size = Vector3(0.75, 0.85, 0.65)
	collider.shape = valve_shape
	collider.position = Vector3(0, 0.1, -0.12)
	root.add_child(collider)
	var wheel := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.23
	torus.outer_radius = 0.29
	wheel.mesh = torus
	wheel.position = Vector3(0, 0.12, -0.20)
	wheel.rotation.x = PI * 0.5
	wheel.material_override = brass_mat
	root.add_child(wheel)
	root.set_meta("wheel", wheel)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("52eee1")
	lamp.light_energy = 0.55
	lamp.omni_range = 2.2
	lamp.position = Vector3(0.42, 0.55, -0.35)
	root.add_child(lamp)
	var tag := Label3D.new()
	tag.text = title
	tag.font_size = 28
	tag.pixel_size = 0.005
	tag.modulate = Color("daf8ed")
	tag.position = Vector3(0, 0.72, -0.1)
	root.add_child(tag)


func _add_exit(at: Vector3) -> void:
	var door := _add_box("Exit shutter", Vector3(2.8, 3.0, 0.28), at + Vector3(0, 1.5, 0), dark_mat, true)
	door.name = "Poolroom exit"
	door.set_meta("exit_door", true)
	var frame := _add_box("Brass exit frame", Vector3(3.15, 3.25, 0.22), at + Vector3(0, 1.62, -0.15), brass_mat, false)
	var sign := Label3D.new()
	sign.text = "PUMP ROOM / OUT"
	sign.font_size = 36
	sign.pixel_size = 0.006
	sign.modulate = Color("e7ffff")
	sign.position = at + Vector3(0, 2.35, -0.31)
	add_child(sign)


func _add_dark_window(center: Vector3, count: int) -> void:
	for i in range(count):
		var pane := _add_box("Black inspection glass", Vector3(1.0, 1.45, 0.08), Vector3(center.x - 3.4 + i * 1.12, center.y, center.z - 8.82), dark_mat, false)
		var rim := _add_box("Window trim", Vector3(1.08, 1.53, 0.1), pane.position + Vector3(0, 0, -0.08), brass_mat, false)


func _add_lights() -> void:
	for at in [Vector3(0,2.9,0),Vector3(23,2.9,0),Vector3(23,2.9,-23),Vector3(51,2.9,-23),Vector3(51,2.9,3),Vector3(77,2.9,3)]:
		var fixture := _add_box("Diffused pool light", Vector3(2.5, 0.09, 0.72), at, tile_mat, false)
		var light := OmniLight3D.new()
		light.light_color = Color("9ef6f0")
		light.light_energy = 2.0
		light.omni_range = 11.0
		light.position = at + Vector3(0, -0.18, 0)
		light.shadow_enabled = true
		add_child(light)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Wanderer"
	player.position = Vector3(0, 0.15, 0)
	player.floor_snap_length = 0.25
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.68
	collision.shape = capsule
	collision.position.y = 0.84
	player.add_child(collision)
	var head := Node3D.new()
	head.position.y = 1.48
	player.add_child(head)
	camera = Camera3D.new()
	camera.fov = 78
	head.add_child(camera)
	var flash := SpotLight3D.new()
	flash.light_color = Color("d7ffff")
	flash.light_energy = 0.6
	flash.spot_range = 15
	flash.spot_angle = 46
	flash.shadow_enabled = false
	camera.add_child(flash)
	var ray := RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.7)
	ray.collision_mask = 1
	ray.collide_with_areas = false
	ray.enabled = true
	camera.add_child(ray)
	add_child(player)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(24, 22)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color("d5ffff"))
	layer.add_child(hud)
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-7, -15)
	cross.add_theme_font_size_override("font_size", 23)
	cross.add_theme_color_override("font_color", Color("efffff"))
	layer.add_child(cross)
	toast = Label.new()
	toast.position = Vector2(260, 600)
	toast.custom_minimum_size = Vector2(760, 90)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 21)
	toast.add_theme_color_override("font_color", Color("e5ffff"))
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(toast)
	var controls := Label.new()
	controls.text = "WASD 移动  ·  鼠标观察  ·  E 调查 / 转阀  ·  Space 跳跃  ·  Esc 暂停"
	controls.position = Vector2(24, 748)
	controls.add_theme_font_size_override("font_size", 14)
	controls.add_theme_color_override("font_color", Color("b3cdca"))
	layer.add_child(controls)
	var guide := Label.new()
	guide.name = "Pool Guide"
	guide.text = "目标：操作 3 只回水阀（01 → 02 → 03），再穿过东侧泵房出口。\n留意天花灯、墙面编号与水面下的台阶。"
	guide.position = Vector2(24, 105)
	guide.custom_minimum_size = Vector2(500, 68)
	guide.add_theme_font_size_override("font_size", 15)
	guide.add_theme_color_override("font_color", Color("cff1e9"))
	layer.add_child(guide)
	var panel := PanelContainer.new()
	panel.name = "End panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-260, -125)
	panel.size = Vector2(520, 250)
	panel.visible = false
	var label := Label.new()
	label.name = "Result"
	label.text = "水泵重新启动。远处的门开了。"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 26)
	panel.add_child(label)
	layer.add_child(panel)
	set_meta("end_panel", panel)


func _process(delta: float) -> void:
	if player == null:
		return
	var ray := camera.get_child(1) as RayCast3D
	ray.force_raycast_update()
	nearby_target = null
	if ray.is_colliding():
		var collider := ray.get_collider() as Node
		while collider != null and not collider.has_meta("interactable") and not collider.has_meta("exit_door"):
			collider = collider.get_parent()
		nearby_target = collider as Node3D
	_update_hud()
	if not finished and valves_on.size() == 3:
		var direction := -camera.global_basis.z
		if player.global_position.distance_to(Vector3(84.5, 0, 3)) < 2.8 and direction.dot(Vector3.RIGHT) > 0.3:
			var door := get_node_or_null("Poolroom exit")
			if door != null:
				door.queue_free()
			finished = true
			var panel := get_meta("end_panel") as PanelContainer
			panel.visible = true
			(panel.get_child(0) as Label).text = "回水泵重新启动。\n水面平静下来，出口外传来风声。\n\nLEVEL 37 · 已逃离"
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			paused = true


func _physics_process(delta: float) -> void:
	if player == null or paused:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var local_dir := Vector3(input.x, 0, input.y)
	var direction := player.global_basis * local_dir
	direction.y = 0
	if direction.length_squared() > 0.01:
		direction = direction.normalized()
	var speed := PLAYER_SPEED * (1.4 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	player.velocity.x = move_toward(player.velocity.x, direction.x * speed, delta * 10.0)
	player.velocity.z = move_toward(player.velocity.z, direction.z * speed, delta * 10.0)
	if not player.is_on_floor():
		player.velocity.y -= 18.0 * delta
	elif Input.is_key_pressed(KEY_SPACE):
		player.velocity.y = 5.2
	player.move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not paused:
		look_y -= event.relative.x * 0.0022
		look_x = clampf(look_x - event.relative.y * 0.0022, -1.2, 1.2)
		player.rotation.y = look_y
		camera.rotation.x = look_x
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not finished:
			paused = not paused
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_E and not paused:
			_interact()
		elif event.keycode == KEY_R and finished:
			get_tree().change_scene_to_file("res://main.tscn")
		elif event.keycode == KEY_ENTER and paused and not finished:
			paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed and paused and not finished:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		paused = false


func _interact() -> void:
	if nearby_target == null:
		_notice("只听见水声在瓷砖间折返。", 1.7)
		return
	if nearby_target.has_meta("valve_index"):
		var index := int(nearby_target.get_meta("valve_index"))
		if valves_on.has(index):
			_notice("阀门已锁定在开启位置。", 1.6)
			return
		var expected := valves_on.size()
		if index != expected:
			_notice("水锤震了一下。维护牌提示按 01 → 02 → 03 的顺序开阀。", 2.8)
			return
		valves_on[index] = true
		var wheel := nearby_target.get_meta("wheel") as MeshInstance3D
		wheel.rotation.z += PI * 0.55
		var label := nearby_target.get_child(4) as Label3D
		label.modulate = Color("83ffe7")
		_notice("回水阀 %02d 开启（%d / 3）。深处的水流变得更响了。" % [index + 1, valves_on.size()], 3.0)
	elif nearby_target.has_meta("exit_door"):
		if valves_on.size() == 3:
			_notice("水泵启动，出口打开。", 2.0)
		else:
			_notice("门磁没有供电。先恢复三只回水阀。", 2.0)
	else:
		_notice("指示牌的箭头被潮气泡皱了。", 1.7)


func _update_hud() -> void:
	hud.text = "LEVEL 37 · 无尽泳池     回水阀 %d / 3" % valves_on.size()
	if nearby_target != null:
		if nearby_target.has_meta("valve_index"):
			hud.text += "\nE · 转动 %s" % nearby_target.name
		elif nearby_target.has_meta("exit_door"):
			hud.text += "\nE · 检查泵房出口"


func _notice(text: String, seconds: float = 2.0) -> void:
	toast.text = text
	toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(maxf(seconds - 0.3, 0.1))
	tween.tween_property(toast, "modulate:a", 0.0, 0.3)


func _add_box(label: String, size: Vector3, at: Vector3, material: Material, solid: bool) -> Node3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	if solid:
		var body := StaticBody3D.new()
		body.name = label
		body.position = at
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		return body
	else:
		mesh.position = at
		add_child(mesh)
		return mesh


func _mesh_box(label: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	add_child(mesh)
	return mesh


func _add_box_to(parent: Node3D, label: String, size: Vector3, material: Material, solid: bool, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	parent.add_child(mesh)


func _add_collision(mesh: MeshInstance3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = mesh.position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
