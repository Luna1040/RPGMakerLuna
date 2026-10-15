extends Node3D

## Self-contained first-person liminal-horror level. Geometry is deliberately
## built from simple primitives so the prototype needs no external assets.

const CELL := 3.0
const WALL_HEIGHT := 3.2
const MAP: Array[String] = [
	"###############################",
	"#S#...............#...........#",
	"#.#.#.#.#.#.#.###....##.###.#.#",
	"#...#.#.#.#...#.#.#.....#...#.#",
	"#####.###.###.#.#.#..####.#.#.#",
	"#...#..P#...#.N...#...#...#.#.#",
	"#.#.###.#.#.##.##.##..###...###",
	"#.#...#.#.......#.#.#.....#...#",
	"#.#####.#######.#.#.#.#.#####.#",
	"#...#...#.....#.#.#...#...C.#.#",
	"#.#.#.###.###.#.#.#.##..###.#.#",
	"#.#.#.#...#.#...#.#.#.....#...#",
	"#.#.#.#.##..#####.#.#######.#.#",
	"#.#.#...#.......#.#...W.....#.#",
	"#.#.#####.#####.#.#####.###.#.#",
	"#.#W#.....#.....#.#...#.#...#.#",
	"#.#.#.#####.#.#.#.#.#.###...#.#",
	"#...#...#...#.#...#.#.....#...#",
	"#.#.###.###.#.##..#.#########.#",
	"#.#...#.#...#.#B......#.#.....#",
	"#.#.###.#.###.#######.#...#####",
	"#.#...#.#...#.......#.#...#...#",
	"#.###.#..##.#######.#.##.##.#.#",
	"#.#..A#.....#...#...#...P...#.#",
	"#.#.#########.##..##...##.###.#",
	"#...#.....#...#...#...#.......#",
	"#.#.#.###.#.#...#####.#.#####.#",
	"#.#...#N..#.#...#...#.#.#.....#",
	"#.#####...#.#.#.#.#.###...#.###",
	"#.......#...#.....#..........E#",
	"###############################",
]
const DARK := Color("343528")
const YELLOW_WALL := Color("aaa36b")
const CARPET := Color("55513b")
const EXIT_CELL := Vector2i(29, 29)
const ANOMALY_CELLS := {"A": Vector2i(5, 23), "B": Vector2i(15, 19), "C": Vector2i(26, 9)}
const ANOMALY_NAMES := {"A": "墙纸后鼓起的墙面", "B": "没有尽头的门框", "C": "走进墙里的湿脚印"}
const ANOMALY_CODES := {"A": "4", "B": "1", "C": "9"}
const WATER_CELLS := [Vector2i(3, 15), Vector2i(22, 13)]
const NOTE_CELLS := [Vector2i(14, 5), Vector2i(7, 27)]
const WATER_VALVE_CELLS := [Vector2i(5, 15), Vector2i(23, 13), Vector2i(20, 25)]
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
const STALKER_SCENE: PackedScene = preload("res://assets/creatures/the_stalker/Run.fbx")
const MOUSE_BASE_SENSITIVITY := 0.0023

var level_map: Array[String] = []
var player: CharacterBody3D
var camera: Camera3D
var ray: RayCast3D
var enemy: CharacterBody3D
var enemy_mesh: Node3D
var apparition_parts: Array[GeometryInstance3D] = []
var apparition_observed := false
var fall_death := false
var ambient_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var heartbeat_player: AudioStreamPlayer
var horror_ambience_player: AudioStreamPlayer
var horror_hit_player: AudioStreamPlayer
var mechanical_player: AudioStreamPlayer
var heavy_door_player: AudioStreamPlayer
var enemy_step_player: AudioStreamPlayer3D
var enemy_step_left := 0.0
var player_step_left := 0.0
var mascot_jumpscare: Node3D
var mascot_jumpscare_active := false
var mascot_jumpscare_triggered := false
var mascot_jumpscare_time := 0.0
var mascot_guarantee_time := 0.0
var mascot_aftercare_left := 0.0
var blackout_time := 0.0
var light_blackout_left := 0.0
var light_blackout_cooldown := 0.0
var level_environment: Environment
var exit_door: Node3D
var exit_label: Label3D
var hud: Label
var message: Label
var notice: Label
var photo_flash: OmniLight3D
var evidence: Dictionary = {}
var anomaly_targets: Array[Area3D] = []
var film := 6
var entity_awake := false
var monster_tutorial_shown := false
var sign_read := false
var monster_grace_left := 0.0
var entity_stunned := 0.0
var alert_left := 0.0
var repath_left := 0.0
var enemy_target := Vector3.ZERO
var game_over := false
var won := false
var sprinting := false
var notice_left := 0.0
var clock := 0.0
var intro_reveal_left := 0.0
var guide_clock := 0.0
var guide_stage := 0
var game_started := false
var paused := false
var jump_requested := false
var inventory_open := false
var fear := 0.0
var stamina := 100.0
var almond_water := 0
var note_count := 0
var archive_read := false
var keypad_active := false
var keypad_buffer := ""
var valve_progress := 0
var pool_gate_open := false
var mouse_sensitivity_multiplier := 0.55
var sensitivity_value_label: Label
var flicker_lights: Array[OmniLight3D] = []
var hud_subtitle: Label
var fear_bar: ProgressBar
var guide_label: Label
var inventory_panel: PanelContainer
var title_overlay: Control
var pause_overlay: Control
var end_overlay: Control

var mat_wall: StandardMaterial3D
var mat_manila_wall: StandardMaterial3D
var mat_manila_floor: StandardMaterial3D
var mat_blackout_floor: StandardMaterial3D
var mat_floor: StandardMaterial3D
var mat_ceiling: StandardMaterial3D
var mat_desk: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_trim: StandardMaterial3D
var mat_wood: StandardMaterial3D
var mat_steel: StandardMaterial3D
var mat_paper: StandardMaterial3D
var mat_light: StandardMaterial3D
var mat_anomaly: StandardMaterial3D


func _ready() -> void:
	_load_settings()
	_make_materials()
	level_map = _prepare_map()
	_build_level()
	_build_player()
	_build_entity()
	_build_sound_players()
	_build_mascot_jumpscare()
	_build_interface()
	_build_menus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_notice("Level 0 · 记录异常、查阅旧档案，也可以追踪管道水声寻找不同出口。", 7.0)


func _make_materials() -> void:
	var wallpaper := load("res://assets/textures/wallpaper_yellowed.jpg") as Texture2D
	var carpet := load("res://assets/textures/carpet_office_worn.jpg") as Texture2D
	var ceiling_tiles := load("res://assets/textures/ceiling_acoustic_tiles.jpg") as Texture2D
	var walnut := load("res://assets/textures/desk_walnut.jpg") as Texture2D
	var oxidized_steel := load("res://assets/textures/doorframe_oxidized_steel.jpg") as Texture2D
	var photo_paper := load("res://assets/textures/photopaper_ivory.jpg") as Texture2D
	mat_wall = _material(Color("d4c78e"), 0.0, 0.96)
	mat_wall.albedo_texture = wallpaper
	mat_wall.uv1_scale = Vector3.ONE
	_apply_pbr_maps(mat_wall, "wallpaper_yellowed")
	mat_floor = _material(Color("b7ad82"), 0.0, 1.0)
	mat_floor.albedo_texture = carpet
	mat_floor.uv1_scale = Vector3.ONE
	_apply_pbr_maps(mat_floor, "carpet_office_worn")
	mat_ceiling = _material(Color("ddd1aa"), 0.0, 0.95)
	mat_ceiling.albedo_texture = ceiling_tiles
	mat_ceiling.uv1_scale = Vector3.ONE
	_apply_pbr_maps(mat_ceiling, "ceiling_acoustic_tiles")
	mat_manila_wall = _material(Color("d6c5a2"), 0.0, 0.95)
	mat_manila_wall.albedo_texture = wallpaper
	mat_manila_wall.uv1_scale = Vector3.ONE
	mat_manila_floor = _material(Color("b0a58d"), 0.0, 1.0)
	mat_manila_floor.albedo_texture = carpet
	mat_manila_floor.uv1_scale = Vector3.ONE
	mat_blackout_floor = _material(Color("514b3b"), 0.0, 1.0)
	mat_blackout_floor.albedo_texture = carpet
	mat_blackout_floor.uv1_scale = Vector3.ONE
	mat_desk = _material(Color("655c43"), 0.0, 0.9)
	mat_dark = _material(Color("181a16"), 0.0, 0.9)
	mat_trim = _material(Color("514a36"), 0.0, 0.94)
	mat_wood = _material(Color("d5c2a0"), 0.0, 0.8)
	mat_wood.albedo_texture = walnut
	mat_wood.uv1_scale = Vector3(1.0, 2.0, 1.0)
	_apply_pbr_maps(mat_wood, "desk_walnut")
	mat_steel = _material(Color("b5a08a"), 0.2, 0.72)
	mat_steel.albedo_texture = oxidized_steel
	mat_steel.uv1_scale = Vector3.ONE
	_apply_pbr_maps(mat_steel, "doorframe_oxidized_steel")
	mat_paper = _material(Color("eee5d2"), 0.0, 0.92)
	mat_paper.albedo_texture = photo_paper
	mat_paper.uv1_scale = Vector3.ONE
	_apply_pbr_maps(mat_paper, "photopaper_ivory")
	mat_light = _material(Color("deddb1"), 0.0, 0.5)
	mat_light.emission_enabled = true
	mat_light.emission = Color("d8d39a")
	mat_light.emission_energy_multiplier = 0.35
	mat_anomaly = _material(Color("b8aa60"), 0.0, 0.75)
	mat_anomaly.emission_enabled = true
	mat_anomaly.emission = Color("f1c85b")
	mat_anomaly.emission_energy_multiplier = 0.7


func _apply_pbr_maps(material: StandardMaterial3D, texture_stem: String) -> void:
	var normal_map := load("res://assets/textures/%s_normal.png" % texture_stem) as Texture2D
	var roughness_map := load("res://assets/textures/%s_roughness.png" % texture_stem) as Texture2D
	if normal_map != null:
		material.normal_enabled = true
		material.normal_texture = normal_map
		material.normal_scale = 0.32
	if roughness_map != null:
		material.roughness_texture = roughness_map
		material.roughness = 1.0


func _load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		mouse_sensitivity_multiplier = clampf(float(settings.get_value("controls", "mouse_sensitivity", 0.55)), 0.2, 1.5)


func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("controls", "mouse_sensitivity", mouse_sensitivity_multiplier)
	settings.save("user://settings.cfg")


func _set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity_multiplier = value
	if sensitivity_value_label != null:
		sensitivity_value_label.text = "%d%%" % roundi(mouse_sensitivity_multiplier * 100.0)
	_save_settings()


func _procedural_texture(kind: String, base: Color) -> Texture2D:
	var image := Image.create(512, 512, false, Image.FORMAT_RGB8)
	var stain_noise := FastNoiseLite.new()
	stain_noise.seed = 1040 + kind.length() * 71
	stain_noise.frequency = 0.035
	stain_noise.fractal_octaves = 3
	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = 8917 + kind.length() * 13
	detail_noise.frequency = 0.19
	for y in range(512):
		for x in range(512):
			var stain := stain_noise.get_noise_2d(x, y)
			var detail := detail_noise.get_noise_2d(x, y)
			var grain := sin(float(x * 13 + y * 3) * 0.17) * 0.014
			var shade := 0.90 + stain * 0.12 + detail * 0.05 + grain
			if kind == "wall":
				if x % 128 == 0 or x % 128 == 1:
					shade *= 0.90
				if (x * 7 + y * 3) % 257 < 3:
					shade *= 0.69
				if y % 128 < 2:
					shade *= 0.94
			elif kind == "carpet":
				shade += float((x * 17 + y * 31) % 11 - 5) * 0.008
				if (x + y * 3) % 97 < 2:
					shade *= 0.78
			elif kind == "ceiling":
				if x % 128 < 3 or y % 128 < 3:
					shade *= 0.68
			elif kind == "manila":
				if x % 160 == 0:
					shade *= 0.9
			image.set_pixel(x, y, Color(
				clampf(base.r * shade, 0, 1),
				clampf(base.g * shade, 0, 1),
				clampf(base.b * shade, 0, 1)
			))
	return ImageTexture.create_from_image(image)


func _prepare_map() -> Array[String]:
	var cells: Array = []
	for row in MAP:
		var row_cells: Array[String] = []
		for x in range(row.length()):
			row_cells.append(row.substr(x, 1))
		cells.append(row_cells)
	# A rare Manila room: warm paper walls, a single entrance, documents, and a chair.
	for z in range(3, 8):
		for x in range(13, 18):
			var boundary := x == 13 or x == 17 or z == 3 or z == 7
			cells[z][x] = "=" if boundary else "."
	cells[7][15] = "."
	cells[5][15] = "M"
	cells[5][14] = "N"
	# Pillar variation with a clear ring of sight lines and an open exit to the maze.
	for z in range(3, 9):
		for x in range(20, 27):
			var boundary := x == 20 or x == 26 or z == 3 or z == 8
			cells[z][x] = "#" if boundary else "."
	cells[8][23] = "."
	cells[5][23] = "R"
	# Two floor holes replace the floor slab; sprint-jumps clear a full three-meter tile.
	cells[15][9] = "H"
	cells[21][25] = "H"
	# Break up the maze into a few broad, unnervingly empty office bays.
	for x in range(5, 12):
		cells[10][x] = "."
	for x in range(18, 25):
		cells[17][x] = "."
	for x in range(7, 14):
		cells[24][x] = "."
	for z in range(11, 15):
		cells[z][9] = "."
	# Keep the hazards and clue rooms deliberate after opening sightlines.
	cells[15][9] = "H"
	cells[5][15] = "M"
	cells[5][14] = "N"
	var result: Array[String] = []
	for row in cells:
		result.append("".join(PackedStringArray(row)))
	return result


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	value.texture_repeat = true
	value.uv1_scale = Vector3(1.5, 1.5, 1.5)
	value.metallic = metallic
	value.roughness = roughness
	return value


func _build_level() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	level_environment = env
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("625f49")
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("9d986f")
	env.fog_density = 0.024
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-72, -25, 0)
	sun.light_color = Color("d3c991")
	sun.light_energy = 0.08
	add_child(sun)

	for z in range(level_map.size()):
		for x in range(level_map[z].length()):
			var cell := level_map[z].substr(x, 1)
			var grid := Vector2i(x, z)
			var center := _cell_world(grid)
			if cell == "#" or cell == "=":
				var wall_material := mat_manila_wall if cell == "=" else mat_wall
				var tile_material := wall_material.duplicate() as StandardMaterial3D
				var tone := 0.93 + float(posmod(x * 19 + z * 31, 13)) * 0.012
				tile_material.albedo_color = tile_material.albedo_color * Color(tone, tone * 0.99, tone * 0.95)
				_add_box("Wallpaper", Vector3(CELL, WALL_HEIGHT, CELL), center + Vector3(0, WALL_HEIGHT * 0.5, 0), tile_material, true)
				_add_wall_baseboards(grid, center)
			elif cell == "H":
				_add_pit(center)
				_add_box("Ceiling", Vector3(CELL, 0.18, CELL), center + Vector3(0, WALL_HEIGHT + 0.08, 0), mat_ceiling, false)
			else:
				var floor_material := mat_manila_floor if _inside_manila(grid) else (mat_blackout_floor if _is_blackout_cell(grid) else mat_floor)
				_add_box("Damp carpet", Vector3(CELL, 0.16, CELL), center + Vector3(0, -0.08, 0), floor_material, true)
				_add_box("Ceiling tiles", Vector3(CELL, 0.18, CELL), center + Vector3(0, WALL_HEIGHT + 0.08, 0), mat_ceiling, false)
				if cell == "P":
					_add_film_pack(center)
				elif cell == "W":
					_add_pickup(center, "almond_water", "杏仁水", Color("80c6ad"))
				elif cell == "N":
					_add_note(center, x + z)
				elif cell == "M":
					_add_manila_room(center)
				elif cell == "R":
					_add_pillars(center)
				if cell == "W":
					_add_wet_carpet(center)
				if cell == "." and (x * 7 + z * 11) % 47 == 0:
					_add_abandoned_debris(center, x + z)
				if cell == "." and (x * 5 + z * 13) % 61 == 0:
					var vent_position := center
					var vent_yaw := 0.0
					if x > 0 and level_map[z].substr(x - 1, 1) == "#":
						vent_position.x -= CELL * 0.48
						vent_yaw = PI * 0.5
					elif x + 1 < level_map[z].length() and level_map[z].substr(x + 1, 1) == "#":
						vent_position.x += CELL * 0.48
						vent_yaw = -PI * 0.5
					elif z > 0 and level_map[z - 1].substr(x, 1) == "#":
						vent_position.z -= CELL * 0.48
					else:
						vent_position.z += CELL * 0.48
						vent_yaw = PI
					_add_wall_vent(vent_position, vent_yaw)
				if not _is_blackout_cell(grid) and (x * 3 + z * 2) % 13 == 0:
					_add_fluorescent(center, _inside_manila(grid))

	_add_anomaly("A", _cell_world(ANOMALY_CELLS["A"]))
	_add_anomaly("B", _cell_world(ANOMALY_CELLS["B"]))
	_add_anomaly("C", _cell_world(ANOMALY_CELLS["C"]))
	_add_exit(_cell_world(EXIT_CELL))
	_add_spawn_notice_board()
	_add_escape_routes()
	_build_ambient_audio()

	var world_environment := get_world_3d().environment
	if world_environment != null:
		world_environment.adjustment_enabled = true
		world_environment.adjustment_saturation = 0.68


func _inside_manila(cell: Vector2i) -> bool:
	return cell.x >= 13 and cell.x <= 17 and cell.y >= 3 and cell.y <= 7


func _is_blackout_cell(cell: Vector2i) -> bool:
	return cell.x >= 1 and cell.x <= 5 and cell.y >= 12 and cell.y <= 18


func _build_ambient_audio() -> void:
	var stream := load("res://audio/level0_hum.wav") as AudioStreamWAV
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ambient_player = AudioStreamPlayer.new()
	ambient_player.name = "Fluorescent hum"
	ambient_player.stream = stream
	ambient_player.volume_db = -9.0
	add_child(ambient_player)
	ambient_player.play()
	# A very quiet, CC0 horror texture sits under the fluorescent hum.
	var horror_stream := load("res://audio/external/ambient_horror.ogg") as AudioStreamOggVorbis
	if horror_stream != null:
		horror_stream.loop = true
		horror_ambience_player = AudioStreamPlayer.new()
		horror_ambience_player.name = "Distant horror ambience"
		horror_ambience_player.stream = horror_stream
		horror_ambience_player.volume_db = -27.0
		add_child(horror_ambience_player)
		horror_ambience_player.play()


func _build_sound_players() -> void:
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "Level SFX"
	sfx_player.volume_db = -5.0
	add_child(sfx_player)
	horror_hit_player = AudioStreamPlayer.new()
	horror_hit_player.name = "Jumpscare impact"
	horror_hit_player.stream = load("res://audio/external/horror_hit_bassy_01.wav") as AudioStream
	horror_hit_player.volume_db = -11.0
	add_child(horror_hit_player)
	mechanical_player = AudioStreamPlayer.new()
	mechanical_player.name = "Mechanical clank layer"
	mechanical_player.stream = load("res://audio/external/mechanical_clank.wav") as AudioStream
	mechanical_player.volume_db = -13.0
	add_child(mechanical_player)
	heavy_door_player = AudioStreamPlayer.new()
	heavy_door_player.name = "Heavy exit door"
	heavy_door_player.stream = load("res://audio/external/heavy_door_open.wav") as AudioStream
	heavy_door_player.volume_db = -12.0
	add_child(heavy_door_player)
	heartbeat_player = AudioStreamPlayer.new()
	heartbeat_player.name = "Threat heartbeat"
	heartbeat_player.volume_db = -32.0
	var heartbeat := load("res://audio/sfx_heartbeat.wav") as AudioStreamWAV
	if heartbeat != null:
		heartbeat.loop_mode = AudioStreamWAV.LOOP_FORWARD
		heartbeat_player.stream = heartbeat
	add_child(heartbeat_player)
	enemy_step_player = AudioStreamPlayer3D.new()
	enemy_step_player.name = "Distant footsteps"
	enemy_step_player.stream = load("res://audio/sfx_footstep.wav") as AudioStream
	enemy_step_player.volume_db = -9.0
	enemy_step_player.max_distance = 30.0
	enemy_step_player.unit_size = 5.0
	enemy.add_child(enemy_step_player)


func _build_mascot_jumpscare() -> void:
	mascot_jumpscare = _make_mochi_mascot()
	mascot_jumpscare.name = "Company mascot easter egg"
	mascot_jumpscare.position = Vector3(0, 0, -2.0)
	mascot_jumpscare.scale = Vector3.ZERO
	mascot_jumpscare.visible = false
	camera.add_child(mascot_jumpscare)


func _make_mochi_mascot() -> Node3D:
	var mascot := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Sculpted rounded mochi body"
	body.mesh = _make_mochi_body_mesh()
	var mochi_material := _material(Color("f8f7f1"), 0.0, 0.88)
	mochi_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mochi_material.roughness = 0.72
	body.material_override = mochi_material
	mascot.add_child(body)
	var key_light := OmniLight3D.new()
	key_light.name = "Softbox key light"
	key_light.position = Vector3(-0.75, 0.65, -0.82)
	key_light.light_color = Color("fff7e9")
	key_light.light_energy = 1.15
	key_light.omni_range = 3.2
	mascot.add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.name = "Cool rim fill"
	fill_light.position = Vector3(0.75, 0.2, 0.1)
	fill_light.light_color = Color("c9d6e8")
	fill_light.light_energy = 0.38
	fill_light.omni_range = 2.6
	mascot.add_child(fill_light)
	var ink := _material(Color("08090a"), 0.0, 0.8)
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 1.0
		eye_mesh.height = 2.0
		eye_mesh.radial_segments = 20
		eye_mesh.rings = 12
		eye.mesh = eye_mesh
		eye.scale = Vector3(0.13, 0.145, 0.055)
		eye.position = Vector3(side * 0.43, 0.13, -0.424)
		eye.material_override = ink
		mascot.add_child(eye)
	var mouth := MeshInstance3D.new()
	var mouth_mesh := CapsuleMesh.new()
	mouth_mesh.radius = 0.085
	mouth_mesh.height = 1.05
	mouth_mesh.radial_segments = 24
	mouth_mesh.rings = 8
	mouth.mesh = mouth_mesh
	mouth.rotation.z = PI * 0.5
	mouth.position = Vector3(0, -0.18, -0.432)
	mouth.material_override = ink
	mouth.name = "Rounded horizontal mouth"
	mascot.add_child(mouth)
	return mascot


func _make_mochi_body_mesh() -> ArrayMesh:
	# Rounded, slightly squared cross-sections give the mascot its soft mochi silhouette.
	var profile := [
		Vector3(0.56, -0.58, 0.15),
		Vector3(0.78, -0.56, 0.28),
		Vector3(0.88, -0.48, 0.36),
		Vector3(0.92, -0.36, 0.42),
		Vector3(0.92, -0.05, 0.46),
		Vector3(0.90, 0.30, 0.45),
		Vector3(0.84, 0.52, 0.41),
		Vector3(0.69, 0.70, 0.35),
		Vector3(0.46, 0.86, 0.26),
		Vector3(0.20, 0.96, 0.12),
		Vector3(0.012, 0.98, 0.012),
	]
	var segments := 72
	var rings_per_profile_segment := 6
	var superellipse_power := 0.66
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range((profile.size() - 1) * rings_per_profile_segment):
		var profile_index := ring / rings_per_profile_segment
		var profile_step := float(ring % rings_per_profile_segment) / float(rings_per_profile_segment)
		var lower := _interpolate_mochi_profile(profile, profile_index, profile_step)
		var upper := _interpolate_mochi_profile(profile, profile_index, profile_step + 1.0 / float(rings_per_profile_segment))
		for segment in range(segments):
			var next_segment := (segment + 1) % segments
			var angle_a := TAU * float(segment) / float(segments)
			var angle_b := TAU * float(next_segment) / float(segments)
			var a := _mochi_profile_vertex(lower, angle_a, superellipse_power)
			var b := _mochi_profile_vertex(lower, angle_b, superellipse_power)
			var c := _mochi_profile_vertex(upper, angle_b, superellipse_power)
			var d := _mochi_profile_vertex(upper, angle_a, superellipse_power)
			surface.add_vertex(a)
			surface.add_vertex(d)
			surface.add_vertex(c)
			surface.add_vertex(a)
			surface.add_vertex(c)
			surface.add_vertex(b)
	# Close the flattened underside so the front view cannot see through the shell.
	var bottom_center := Vector3(0.0, profile[0].y, 0.0)
	for segment in range(segments):
		var angle_a := TAU * float(segment) / float(segments)
		var angle_b := TAU * float(segment + 1) / float(segments)
		surface.add_vertex(bottom_center)
		surface.add_vertex(_mochi_profile_vertex(profile[0], angle_a, superellipse_power))
		surface.add_vertex(_mochi_profile_vertex(profile[0], angle_b, superellipse_power))
	surface.index()
	surface.generate_normals()
	return surface.commit()


func _interpolate_mochi_profile(profile: Array, index: int, weight: float) -> Vector3:
	if weight >= 1.0:
		return profile[mini(index + 1, profile.size() - 1)]
	var p0: Vector3 = profile[maxi(index - 1, 0)]
	var p1: Vector3 = profile[index]
	var p2: Vector3 = profile[mini(index + 1, profile.size() - 1)]
	var p3: Vector3 = profile[mini(index + 2, profile.size() - 1)]
	var t2 := weight * weight
	var t3 := t2 * weight
	var result := 0.5 * ((2.0 * p1) + (-p0 + p2) * weight + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
	result.x = maxf(result.x, 0.008)
	result.z = maxf(result.z, 0.008)
	return result


func _mochi_profile_vertex(ring: Vector3, angle: float, power: float) -> Vector3:
	var cosine := cos(angle)
	var sine := sin(angle)
	var x := ring.x * signf(cosine) * pow(absf(cosine), power)
	var z := ring.z * signf(sine) * pow(absf(sine), power)
	return Vector3(x, ring.y, z)


func _trigger_mascot_jumpscare() -> void:
	if mascot_jumpscare_triggered or mascot_jumpscare == null:
		return
	mascot_jumpscare_triggered = true
	mascot_jumpscare_active = true
	mascot_jumpscare_time = 0.0
	mascot_aftercare_left = 2.2
	mascot_jumpscare.position = Vector3(0, 0, -2.4)
	mascot_jumpscare.scale = Vector3.ONE * 0.03
	mascot_jumpscare.visible = true
	fear = minf(fear + 24.0, 99.0)
	photo_flash.light_energy = maxf(photo_flash.light_energy, 3.0)
	_play_sfx("mascot", -2.0)
	if horror_hit_player != null:
		horror_hit_player.play()
	_show_notice("……软绵绵的白色脸突然贴了上来。心跳加快了，但你没有受伤。", 3.0)
	_update_hud()


func _play_sfx(sound_name: String, volume_db: float = -5.0) -> void:
	if sfx_player == null:
		return
	var stream := load("res://audio/sfx_%s.wav" % sound_name) as AudioStream
	if stream == null:
		return
	sfx_player.stream = stream
	sfx_player.volume_db = volume_db
	sfx_player.play()
	if sound_name == "valve" and mechanical_player != null:
		mechanical_player.play()


func _add_pit(center: Vector3) -> void:
	var pit := StaticBody3D.new()
	pit.name = "Unlit pit"
	pit.position = center + Vector3(0, -3.6, 0)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL, 0.2, CELL)
	mesh.mesh = box
	mesh.material_override = mat_dark
	pit.add_child(mesh)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	shape_node.shape = shape
	pit.add_child(shape_node)
	add_child(pit)


func _add_wet_carpet(center: Vector3) -> void:
	var stain := MeshInstance3D.new()
	var patch := PlaneMesh.new()
	patch.size = Vector2(1.4, 1.1)
	stain.mesh = patch
	stain.position = center + Vector3(0, 0.012, 0)
	var wet := _material(Color("282c25"), 0.0, 0.18)
	stain.material_override = wet
	add_child(stain)


func _add_box(label: String, size: Vector3, at: Vector3, material: Material, solid: bool) -> Node3D:
	var holder: Node3D
	if solid:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	holder.name = label
	holder.position = at
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	holder.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		holder.add_child(collision)
	add_child(holder)
	return holder


func _make_prop_box(parent: Node3D, label: String, size: Vector3, local_position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = local_position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


func _rounded_box_mesh(size: Vector3, requested_bevel: float = 0.035) -> ArrayMesh:
	# A subdivided rounded-cube surface gives close-up props real edge highlights.
	var half := size * 0.5
	var bevel := clampf(requested_bevel, 0.002, minf(size.x, minf(size.y, size.z)) * 0.44)
	var inner := half - Vector3.ONE * bevel
	var divisions := 5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for axis in range(3):
		for sign_value in [-1.0, 1.0]:
			var u_axis := (axis + 1) % 3
			var v_axis := (axis + 2) % 3
			if sign_value < 0.0:
				var swap_axis := u_axis
				u_axis = v_axis
				v_axis = swap_axis
			var base := vertices.size()
			for iy in range(divisions + 1):
				for ix in range(divisions + 1):
					var u := float(ix) / divisions
					var v := float(iy) / divisions
					var point := Vector3.ZERO
					point[axis] = sign_value * half[axis]
					point[u_axis] = lerpf(-half[u_axis], half[u_axis], u)
					point[v_axis] = lerpf(-half[v_axis], half[v_axis], v)
					var core := Vector3(
						clampf(point.x, -inner.x, inner.x),
						clampf(point.y, -inner.y, inner.y),
						clampf(point.z, -inner.z, inner.z)
					)
					var normal := (point - core).normalized()
					vertices.append(core + normal * bevel)
					normals.append(normal)
					uvs.append(Vector2(u, v))
			for iy in range(divisions):
				for ix in range(divisions):
					var a := base + iy * (divisions + 1) + ix
					var b := a + 1
					var c := a + divisions + 1
					var d := c + 1
					indices.append_array(PackedInt32Array([a, b, d, a, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _add_rounded_prop(parent: Node3D, label: String, size: Vector3, at: Vector3, material: Material, bevel: float = 0.035) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = label
	mesh_instance.mesh = _rounded_box_mesh(size, bevel)
	mesh_instance.position = at
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_rounded_world_box(label: String, size: Vector3, at: Vector3, material: Material, solid: bool, bevel: float = 0.035) -> Node3D:
	var holder: Node3D = StaticBody3D.new() if solid else Node3D.new()
	holder.name = label
	holder.position = at
	_add_rounded_prop(holder, label + " beveled surface", size, Vector3.ZERO, material, bevel)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		holder.add_child(collision)
	add_child(holder)
	return holder


func _lathe_mesh(profile: Array[Vector2], radial_segments: int = 48) -> ArrayMesh:
	# Profile is radius/height; manually authored normals keep the turned surface smooth.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(profile.size()):
		var previous: Vector2 = profile[maxi(0, row - 1)]
		var following: Vector2 = profile[mini(profile.size() - 1, row + 1)]
		var rise := maxf(absf(following.y - previous.y), 0.001)
		var radial_normal_y := -(following.x - previous.x) / rise
		for segment in range(radial_segments):
			var angle := TAU * float(segment) / radial_segments
			var radial := Vector3(cos(angle), 0, sin(angle))
			var normal := Vector3(radial.x, radial_normal_y, radial.z).normalized()
			vertices.append(Vector3(radial.x * profile[row].x, profile[row].y, radial.z * profile[row].x))
			normals.append(normal)
			uvs.append(Vector2(float(segment) / radial_segments, float(row) / maxi(1, profile.size() - 1)))
	for row in range(profile.size() - 1):
		for segment in range(radial_segments):
			var next := (segment + 1) % radial_segments
			var lower := row * radial_segments
			var upper := (row + 1) * radial_segments
			var a := lower + segment
			var b := lower + next
			var c := upper + segment
			var d := upper + next
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _add_wall_baseboards(cell: Vector2i, center: Vector3) -> void:
	# Add trim only on faces exposed to walkable floor, so wall intersections stay clean.
	if _is_walkable(cell + Vector2i.RIGHT):
		_add_box("Worn wall baseboard", Vector3(0.085, 0.14, CELL), center + Vector3(CELL * 0.5 - 0.045, 0.07, 0), mat_trim, false)
	if _is_walkable(cell + Vector2i.LEFT):
		_add_box("Worn wall baseboard", Vector3(0.085, 0.14, CELL), center + Vector3(-CELL * 0.5 + 0.045, 0.07, 0), mat_trim, false)
	if _is_walkable(cell + Vector2i.DOWN):
		_add_box("Worn wall baseboard", Vector3(CELL, 0.14, 0.085), center + Vector3(0, 0.07, CELL * 0.5 - 0.045), mat_trim, false)
	if _is_walkable(cell + Vector2i.UP):
		_add_box("Worn wall baseboard", Vector3(CELL, 0.14, 0.085), center + Vector3(0, 0.07, -CELL * 0.5 + 0.045), mat_trim, false)


func _add_fluorescent(center: Vector3, warm: bool = false) -> void:
	_add_box("Fluorescent fixture housing", Vector3(1.7, 0.12, 0.72), center + Vector3(0, WALL_HEIGHT - 0.29, 0), mat_trim, false)
	_add_box("Fluorescent diffuser", Vector3(1.42, 0.035, 0.44), center + Vector3(0, WALL_HEIGHT - 0.215, 0), mat_light, false)
	var light := OmniLight3D.new()
	light.position = center + Vector3(0, WALL_HEIGHT - 0.34, 0)
	light.light_color = Color("efd59a") if warm else Color("d8dda9")
	light.light_energy = 0.4 if warm else 0.52
	light.omni_range = 6.4
	light.omni_attenuation = 1.8
	flicker_lights.append(light)
	add_child(light)


func _add_manila_room(center: Vector3) -> void:
	# This is the only clearly furnished room: a quiet, warmer dead-end with records and a chair.
	var table_center := center + Vector3(-0.42, 0.72, 0.0)
	_add_rounded_world_box("Hand-finished walnut tabletop", Vector3(1.42, 0.15, 0.86), table_center, mat_wood, true, 0.055)
	_add_rounded_world_box("Table edge moulding", Vector3(1.44, 0.045, 0.88), table_center + Vector3(0, -0.07, 0), mat_trim, false, 0.018)
	_add_rounded_world_box("Table apron", Vector3(1.18, 0.18, 0.62), table_center + Vector3(0, -0.19, 0), mat_wood, false, 0.035)
	_add_rounded_world_box("Desk drawer carcass", Vector3(0.72, 0.17, 0.49), table_center + Vector3(0, -0.18, -0.06), mat_desk, false, 0.025)
	_add_rounded_world_box("Drawer face", Vector3(0.74, 0.16, 0.035), table_center + Vector3(0, -0.17, -0.32), mat_wood, false, 0.025)
	_add_rounded_world_box("Drawer escutcheon", Vector3(0.26, 0.065, 0.018), table_center + Vector3(0, -0.17, -0.35), mat_trim, false, 0.022)
	_add_rounded_world_box("Drawer pull", Vector3(0.16, 0.025, 0.045), table_center + Vector3(0, -0.17, -0.375), mat_steel, false, 0.012)
	# Recessed drawer panel, corner hardware, and a second rail give the desk readable scale.
	_add_box("Drawer inset shadow", Vector3(0.59, 0.105, 0.012), table_center + Vector3(0, -0.17, -0.343), mat_desk, false)
	_add_box("Back apron rail", Vector3(1.12, 0.09, 0.07), table_center + Vector3(0, -0.20, 0.285), mat_trim, false)
	for screw_x in [-0.32, 0.32]:
		var screw := MeshInstance3D.new()
		var screw_mesh := SphereMesh.new()
		screw_mesh.radius = 0.018
		screw_mesh.height = 0.012
		screw.mesh = screw_mesh
		screw.position = table_center + Vector3(screw_x, -0.17, -0.368)
		screw.material_override = mat_steel
		add_child(screw)
	var turned_leg_profile: Array[Vector2] = [Vector2(0, -0.335), Vector2(0.044, -0.335), Vector2(0.055, -0.31), Vector2(0.048, -0.25), Vector2(0.039, -0.12), Vector2(0.047, 0.12), Vector2(0.062, 0.29), Vector2(0.057, 0.335), Vector2(0, 0.335)]
	var turned_leg_mesh := _lathe_mesh(turned_leg_profile, 32)
	for dx in [-0.58, 0.58]:
		for dz in [-0.31, 0.31]:
			var leg := StaticBody3D.new()
			leg.name = "Turned walnut table leg"
			leg.position = table_center + Vector3(dx, -0.385, dz)
			var leg_visual := MeshInstance3D.new()
			leg_visual.mesh = turned_leg_mesh
			leg_visual.material_override = mat_wood
			leg.add_child(leg_visual)
			var leg_collision := CollisionShape3D.new()
			var leg_shape := CylinderShape3D.new()
			leg_shape.radius = 0.065
			leg_shape.height = 0.67
			leg_collision.shape = leg_shape
			leg.add_child(leg_collision)
			add_child(leg)
			_add_box("Desk foot cap", Vector3(0.105, 0.08, 0.105), table_center + Vector3(dx, -0.68, dz), mat_dark, false)
			_add_rounded_world_box("Turned-leg brass collar", Vector3(0.11, 0.035, 0.11), table_center + Vector3(dx, -0.55, dz), mat_trim, false, 0.015)
	var binder := MeshInstance3D.new()
	var book := BoxMesh.new()
	book.size = Vector3(0.36, 0.065, 0.27)
	binder.mesh = book
	binder.position = center + Vector3(-0.42, 0.835, 0.0)
	binder.material_override = _material(Color("70634d"), 0, 0.94)
	add_child(binder)
	var binder_label := _make_prop_box(binder, "Ledger label", Vector3(0.17, 0.008, 0.11), Vector3(0, 0.037, 0), mat_paper)
	binder_label.rotation.x = 0
	var book_spine := _make_prop_box(binder, "Ledger spine", Vector3(0.04, 0.012, 0.25), Vector3(-0.16, 0.035, 0), mat_steel)
	book_spine.rotation.z = 0
	var seat := Node3D.new()
	seat.name = "Manila chair"
	seat.position = center + Vector3(0.62, 0.34, 0.12)
	_add_rounded_world_box("Solid chair seat frame", Vector3(0.54, 0.12, 0.5), seat.position + Vector3(0, -0.015, 0), mat_wood, true, 0.045)
	_add_rounded_world_box("Worn leather chair pad", Vector3(0.47, 0.085, 0.42), seat.position + Vector3(0, 0.085, -0.015), mat_desk, false, 0.04)
	_add_box("Chair front apron", Vector3(0.43, 0.13, 0.065), seat.position + Vector3(0, -0.13, -0.22), mat_trim, false)
	for back_x in [-0.22, 0.22]:
		_add_box("Chair back stile", Vector3(0.065, 0.72, 0.075), seat.position + Vector3(back_x, 0.38, 0.22), mat_wood, true)
	for rail_y in [0.18, 0.39, 0.60]:
		_add_box("Chair back slat", Vector3(0.39, 0.13, 0.055), seat.position + Vector3(0, rail_y, 0.22), mat_wood, false)
	for dx in [-0.21, 0.21]:
		for dz in [-0.18, 0.18]:
			_add_box("Chair leg", Vector3(0.055, 0.34, 0.055), seat.position + Vector3(dx, -0.17, dz), mat_dark, true)
	for dx in [-0.21, 0.21]:
		_add_box("Chair side stretcher", Vector3(0.035, 0.045, 0.34), seat.position + Vector3(dx, -0.22, 0), mat_wood, false)
	var rest_area := Area3D.new()
	rest_area.name = "Rest chair interaction"
	rest_area.position = seat.position + Vector3(0, 0.55, -0.12)
	rest_area.collision_layer = 2
	rest_area.collision_mask = 0
	rest_area.set_meta("interact_kind", "rest")
	var rest_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	rest_shape.shape = sphere
	rest_area.add_child(rest_shape)
	add_child(rest_area)
	var paper := Area3D.new()
	paper.name = "Field notes"
	paper.position = center + Vector3(-0.42, 0.89, 0.0)
	paper.collision_layer = 2
	paper.collision_mask = 0
	paper.set_meta("interact_kind", "manila_note")
	var paper_mesh := MeshInstance3D.new()
	var paper_box := BoxMesh.new()
	paper_box.size = Vector3(0.44, 0.018, 0.31)
	paper_mesh.mesh = paper_box
	paper_mesh.material_override = mat_paper
	paper.add_child(paper_mesh)
	_make_prop_box(paper, "Manila note backing", Vector3(0.47, 0.022, 0.34), Vector3(0, -0.018, 0), mat_desk)
	var note_title := Label3D.new()
	note_title.text = "FIELD REPORT   /   L0"
	note_title.font_size = 7
	note_title.pixel_size = 0.003
	note_title.position = Vector3(-0.14, 0.012, -0.105)
	note_title.modulate = Color("50483b")
	paper.add_child(note_title)
	for clip_x in [-0.08, 0.08]:
		var clip_pin := MeshInstance3D.new()
		var pin_mesh := SphereMesh.new()
		pin_mesh.radius = 0.014
		clip_pin.mesh = pin_mesh
		clip_pin.position = Vector3(clip_x, 0.025, -0.125)
		clip_pin.material_override = mat_steel
		paper.add_child(clip_pin)
	_add_interaction_area(paper, 0.9)
	add_child(paper)
	var shelf_label := Label3D.new()
	shelf_label.text = "MANILA ROOM"
	shelf_label.font_size = 22
	shelf_label.pixel_size = 0.003
	shelf_label.position = center + Vector3(0, 2.55, -1.25)
	shelf_label.modulate = Color("c7b492")
	add_child(shelf_label)


func _add_pillars(center: Vector3) -> void:
	for offset in [Vector3(-3.0, 0, -3.0), Vector3(3.0, 0, -3.0), Vector3(-3.0, 0, 3.0), Vector3(3.0, 0, 3.0)]:
		var column := StaticBody3D.new()
		column.name = "Concrete support"
		column.position = center + offset + Vector3(0, WALL_HEIGHT * 0.5, 0)
		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.32
		cylinder.bottom_radius = 0.42
		cylinder.height = WALL_HEIGHT
		cylinder.radial_segments = 6
		mesh.mesh = cylinder
		mesh.material_override = mat_manila_wall
		column.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.42
		shape.height = WALL_HEIGHT
		collision.shape = shape
		column.add_child(collision)
		add_child(column)


func _add_film_pack(center: Vector3) -> void:
	var pack := Area3D.new()
	pack.name = "Spare film"
	pack.collision_layer = 0
	pack.collision_mask = 1
	pack.position = center + Vector3(0, 0.095, 0)
	_make_prop_box(pack, "Instant film cassette", Vector3(0.34, 0.19, 0.27), Vector3(0, 0, 0), mat_dark)
	_make_prop_box(pack, "Cassette face plate", Vector3(0.31, 0.025, 0.24), Vector3(0, 0.103, 0), mat_steel)
	_make_prop_box(pack, "Stack of ivory photo sheets", Vector3(0.27, 0.018, 0.21), Vector3(0, 0.125, 0), mat_paper)
	_make_prop_box(pack, "Top instant photo sheet", Vector3(0.25, 0.008, 0.19), Vector3(0, 0.139, 0), mat_paper)
	for offset in [-0.065, 0.0, 0.065]:
		_make_prop_box(pack, "Layered paper edge", Vector3(0.255, 0.004, 0.195), Vector3(0, 0.115 + offset * 0.16, offset), mat_paper)
	_make_prop_box(pack, "Cassette dark window", Vector3(0.11, 0.006, 0.035), Vector3(0, 0.145, -0.065), mat_dark)
	var paper_mark := Label3D.new()
	paper_mark.text = "INSTANT   10"
	paper_mark.font_size = 7
	paper_mark.pixel_size = 0.0025
	paper_mark.position = Vector3(0, 0.149, 0.055)
	paper_mark.rotation.x = -PI * 0.5
	paper_mark.modulate = Color("575043")
	pack.add_child(paper_mark)
	var label := Label3D.new()
	label.text = "相纸"
	label.font_size = 9
	label.pixel_size = 0.0025
	label.position = Vector3(0, 0.03, -0.139)
	label.modulate = Color("ddd3b9")
	pack.add_child(label)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.52, 0.45, 0.5)
	collision.shape = shape
	collision.position.y = 0.04
	pack.add_child(collision)
	pack.body_entered.connect(_on_film_pack_collected.bind(pack))
	add_child(pack)


func _add_pickup(center: Vector3, item_id: String, item_name: String, tint: Color) -> void:
	var pickup := Area3D.new()
	pickup.name = item_id
	pickup.position = center + Vector3(0, 0.42, 0)
	pickup.collision_layer = 2
	pickup.collision_mask = 0
	pickup.set_meta("interact_kind", "pickup")
	pickup.set_meta("item_id", item_id)
	pickup.set_meta("item_name", item_name)
	var glass := _material(Color(tint.r * 0.58, tint.g * 0.78, tint.b * 0.72, 0.38), 0.02, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	glass.clearcoat_enabled = true
	glass.clearcoat = 0.72
	glass.clearcoat_roughness = 0.12
	var bottle_profile: Array[Vector2] = [
		Vector2(0.0, -0.34), Vector2(0.082, -0.34), Vector2(0.125, -0.33),
		Vector2(0.146, -0.30), Vector2(0.15, -0.26), Vector2(0.15, 0.015),
		Vector2(0.143, 0.045), Vector2(0.116, 0.075), Vector2(0.078, 0.105),
		Vector2(0.066, 0.13), Vector2(0.066, 0.275), Vector2(0.073, 0.29),
		Vector2(0.073, 0.345), Vector2(0.065, 0.37), Vector2(0.0, 0.37)
	]
	var bottle := MeshInstance3D.new()
	bottle.name = "Custom turned clear-glass almond-water bottle"
	bottle.mesh = _lathe_mesh(bottle_profile, 64)
	bottle.material_override = glass
	pickup.add_child(bottle)
	var pickup_hint := Label3D.new()
	pickup_hint.text = "杏仁水\n靠近拾取 · Q 饮用"
	pickup_hint.font_size = 25
	pickup_hint.pixel_size = 0.005
	pickup_hint.position = Vector3(0, 0.58, 0)
	pickup_hint.modulate = Color("c9fff0")
	pickup_hint.outline_size = 7
	pickup_hint.outline_modulate = Color("17302a")
	pickup_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pickup.add_child(pickup_hint)
	var liquid_material := _material(Color(tint.r * 0.75, tint.g * 0.88, tint.b * 0.82, 0.88), 0.0, 0.2)
	liquid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	liquid_material.emission_enabled = true
	liquid_material.emission = Color(tint.r * 0.14, tint.g * 0.19, tint.b * 0.15)
	liquid_material.emission_energy_multiplier = 0.22
	var liquid := MeshInstance3D.new()
	var liquid_profile: Array[Vector2] = [Vector2(0.0, -0.292), Vector2(0.09, -0.292), Vector2(0.119, -0.278), Vector2(0.125, -0.25), Vector2(0.125, -0.085), Vector2(0.121, -0.07), Vector2(0.0, -0.07)]
	liquid.mesh = _lathe_mesh(liquid_profile, 48)
	liquid.material_override = liquid_material
	pickup.add_child(liquid)
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.064
	cap_mesh.bottom_radius = 0.074
	cap_mesh.height = 0.072
	cap_mesh.radial_segments = 40
	cap.mesh = cap_mesh
	cap.position.y = 0.325
	cap.material_override = _material(Color("4b5b4d"), 0.12, 0.42)
	pickup.add_child(cap)
	for ridge in range(14):
		var angle := TAU * float(ridge) / 14.0
		var grip := MeshInstance3D.new()
		var grip_mesh := BoxMesh.new()
		grip_mesh.size = Vector3(0.009, 0.048, 0.018)
		grip.mesh = grip_mesh
		grip.position = Vector3(cos(angle) * 0.072, 0.325, sin(angle) * 0.072)
		grip.rotation.y = -angle
		grip.material_override = _material(Color("83907b"), 0.08, 0.55)
		pickup.add_child(grip)
	var tamper_band := MeshInstance3D.new()
	var tamper_mesh := TorusMesh.new()
	tamper_mesh.inner_radius = 0.061
	tamper_mesh.outer_radius = 0.073
	tamper_mesh.rings = 12
	tamper_mesh.ring_segments = 40
	tamper_band.mesh = tamper_mesh
	tamper_band.position.y = 0.282
	tamper_band.material_override = _material(Color("bdad7c"), 0.42, 0.35)
	pickup.add_child(tamper_band)
	var label_band := MeshInstance3D.new()
	var label_mesh := CylinderMesh.new()
	label_mesh.top_radius = 0.151
	label_mesh.bottom_radius = 0.151
	label_mesh.height = 0.16
	label_mesh.radial_segments = 64
	label_band.mesh = label_mesh
	label_band.position.y = -0.095
	label_band.material_override = _material(Color("e0d8ba"), 0.0, 0.88)
	pickup.add_child(label_band)
	for label_y in [-0.176, -0.014]:
		var label_rim := MeshInstance3D.new()
		var rim_mesh := TorusMesh.new()
		rim_mesh.inner_radius = 0.144
		rim_mesh.outer_radius = 0.152
		rim_mesh.rings = 12
		rim_mesh.ring_segments = 48
		label_rim.mesh = rim_mesh
		label_rim.position.y = label_y
		label_rim.material_override = _material(Color("a78b52"), 0.42, 0.38)
		pickup.add_child(label_rim)
	var bottle_label := Label3D.new()
	bottle_label.text = "杏仁水\nALKALINE"
	bottle_label.font_size = 11
	bottle_label.pixel_size = 0.0036
	bottle_label.position = Vector3(0.006, -0.055, -0.152)
	bottle_label.modulate = Color("3e4a39")
	pickup.add_child(bottle_label)
	var droplet := MeshInstance3D.new()
	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 1.0
	droplet_mesh.height = 2.0
	droplet.mesh = droplet_mesh
	droplet.scale = Vector3(0.025, 0.042, 0.009)
	droplet.position = Vector3(-0.074, -0.09, -0.15)
	droplet.material_override = _material(Color("718e73"), 0.05, 0.3)
	pickup.add_child(droplet)
	_add_interaction_area(pickup, 1.0)
	var proximity := Area3D.new()
	proximity.name = "Automatic pickup range"
	proximity.position.y = 0.25
	proximity.collision_layer = 0
	proximity.collision_mask = 1
	var proximity_shape := CollisionShape3D.new()
	var proximity_sphere := SphereShape3D.new()
	proximity_sphere.radius = 1.15
	proximity_shape.shape = proximity_sphere
	proximity.add_child(proximity_shape)
	proximity.body_entered.connect(_on_almond_water_body_entered.bind(pickup))
	pickup.add_child(proximity)
	add_child(pickup)


func _on_almond_water_body_entered(body: Node3D, pickup: Area3D) -> void:
	if body == player:
		_collect_almond_water(pickup)


func _collect_almond_water(pickup: Node) -> void:
	if not is_instance_valid(pickup) or pickup.get_meta("collected", false):
		return
	pickup.set_meta("collected", true)
	almond_water += 1
	_play_sfx("pickup")
	_show_notice("捡到杏仁水！恐惧时按 Q 饮用。背包数量：%d" % almond_water, 3.0)
	pickup.queue_free()
	_update_hud()


func _add_note(center: Vector3, seed_value: int) -> void:
	var note := Area3D.new()
	note.name = "Lost note"
	note.position = center + Vector3(0, 0.24, 0)
	note.collision_layer = 2
	note.collision_mask = 0
	note.set_meta("interact_kind", "note")
	var paper := MeshInstance3D.new()
	var paper_mesh := BoxMesh.new()
	paper_mesh.size = Vector3(0.42, 0.025, 0.32)
	paper.mesh = paper_mesh
	paper.material_override = mat_paper
	note.add_child(paper)
	var backing := _make_prop_box(note, "Folded paper backing", Vector3(0.45, 0.02, 0.35), Vector3(0, -0.02, 0), mat_wood)
	backing.rotation.y = 0.02
	for line in range(3):
		var ink := MeshInstance3D.new()
		var ink_box := BoxMesh.new()
		ink_box.size = Vector3(0.28 - float(line % 2) * 0.07, 0.004, 0.009)
		ink.mesh = ink_box
		ink.position = Vector3(-0.025, 0.017, -0.075 + line * 0.07)
		ink.material_override = _material(Color("514b3e"), 0, 1)
		note.add_child(ink)
	var heading := Label3D.new()
	heading.text = "MAINTENANCE LOG"
	heading.font_size = 7
	heading.pixel_size = 0.0025
	heading.position = Vector3(-0.01, 0.018, -0.11)
	heading.rotation.x = -PI * 0.5
	heading.modulate = Color("493d31")
	note.add_child(heading)
	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.035
	glow.mesh = glow_mesh
	glow.position.y = 0.14
	glow.material_override = mat_anomaly
	note.add_child(glow)
	_add_interaction_area(note, 0.75)
	add_child(note)


func _add_abandoned_debris(center: Vector3, seed_value: int) -> void:
	var cluster := Node3D.new()
	cluster.name = "Ceiling tile and paper debris"
	cluster.position = center + Vector3(0, 0.025, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 17891
	for i in range(4):
		var scrap := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(rng.randf_range(0.10, 0.34), 0.025, rng.randf_range(0.08, 0.25))
		scrap.mesh = shape
		scrap.position = Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
		scrap.rotation.y = rng.randf_range(-PI, PI)
		scrap.material_override = _material(Color("716d58").lerp(Color("b3a88a"), rng.randf()), 0, 0.98)
		cluster.add_child(scrap)
	add_child(cluster)


func _add_wall_vent(center: Vector3, yaw: float) -> void:
	var vent := Node3D.new()
	vent.name = "Oxidised wall vent"
	vent.position = center + Vector3(0.0, 1.1, 0.0)
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(0.46, 0.28, 0.045)
	frame.mesh = frame_mesh
	frame.material_override = _material(Color("514f43"), 0.12, 0.82)
	vent.add_child(frame)
	var grille := MeshInstance3D.new()
	var grille_mesh := BoxMesh.new()
	grille_mesh.size = Vector3(0.36, 0.18, 0.035)
	grille.mesh = grille_mesh
	grille.position.z = -0.03
	grille.material_override = mat_dark
	vent.add_child(grille)
	for i in range(5):
		var slat := MeshInstance3D.new()
		var slat_mesh := BoxMesh.new()
		slat_mesh.size = Vector3(0.34, 0.012, 0.025)
		slat.mesh = slat_mesh
		slat.position = Vector3(0, -0.065 + i * 0.032, -0.055)
		slat.material_override = _material(Color("847d61"), 0.25, 0.65)
		vent.add_child(slat)
	vent.rotation.y = yaw
	add_child(vent)


func _add_interaction_area(parent: Node3D, radius: float) -> void:
	var area := Area3D.new()
	area.position.y = 0.9
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("interactable", true)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 1.0)
	shape.shape = sphere
	area.add_child(shape)
	parent.add_child(area)


func _on_film_pack_collected(body: Node3D, pack: Area3D) -> void:
	if body != player:
		return
	var before := film
	film = mini(10, film + 2)
	pack.queue_free()
	_show_notice("捡到两张相纸。%d → %d" % [before, film], 2.5)
	_update_hud()


func _add_anomaly(id: String, at: Vector3) -> void:
	var prop := Node3D.new()
	prop.name = "Reality fold " + id
	prop.position = at
	add_child(prop)
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("target_kind", "anomaly")
	area.set_meta("anomaly_id", id)
	var photo_offset := Vector3(0, 1.2, 0)
	if id == "A":
		photo_offset = Vector3(0.0, 1.55, -0.95)
	elif id == "B":
		photo_offset = Vector3(0.0, 1.28, -0.85)
	else:
		photo_offset = Vector3(0.0, 0.12, 0.0)
	area.set_meta("photo_point", photo_offset)
	area.set_meta("interactable", true)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.15
	shape.shape = sphere
	area.add_child(shape)
	prop.add_child(area)
	anomaly_targets.append(area)
	if id == "A":
		# Wallpaper buckles as if something is pressing from the other side.
		var bulge := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.28
		mesh.height = 0.9
		bulge.mesh = mesh
		bulge.scale = Vector3(0.12, 1.0, 0.6)
		bulge.position = Vector3(0.0, 1.55, -0.95)
		bulge.material_override = mat_dark
		prop.add_child(bulge)
	elif id == "B":
		# A layered, rusted service doorway. The dark inset makes the empty opening
		# feel like it continues much farther than the surrounding maze.
		var void_material := _material(Color("070807"), 0.0, 1.0)
		void_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_make_prop_box(prop, "Impossible doorway void", Vector3(1.06, 2.24, 0.035), Vector3(0, 1.13, -0.70), void_material)
		for x in [-0.66, 0.66]:
			_make_prop_box(prop, "Outer steel jamb", Vector3(0.19, 2.56, 0.32), Vector3(x, 1.28, -0.83), mat_steel)
			_make_prop_box(prop, "Inner brass reveal", Vector3(0.045, 2.28, 0.35), Vector3(x * 0.81, 1.18, -0.91), mat_anomaly)
			_make_prop_box(prop, "Jamb inset groove", Vector3(0.025, 2.12, 0.025), Vector3(x * 1.16, 1.20, -1.01), mat_dark)
		_make_prop_box(prop, "Heavy steel lintel", Vector3(1.49, 0.22, 0.32), Vector3(0, 2.50, -0.83), mat_steel)
		_make_prop_box(prop, "Inner lintel reveal", Vector3(1.12, 0.045, 0.35), Vector3(0, 2.36, -0.91), mat_anomaly)
		_make_prop_box(prop, "Worn threshold", Vector3(1.47, 0.08, 0.42), Vector3(0, 0.04, -0.82), mat_steel)
		for x in [-0.66, 0.66]:
			for y in [0.36, 2.18]:
				var rivet := MeshInstance3D.new()
				var rivet_mesh := SphereMesh.new()
				rivet_mesh.radius = 0.033
				rivet_mesh.height = 0.025
				rivet.mesh = rivet_mesh
				rivet.position = Vector3(x, y, -1.01)
				rivet.material_override = mat_trim
				prop.add_child(rivet)
		var plate := _make_prop_box(prop, "Doorway number plate", Vector3(0.54, 0.16, 0.045), Vector3(0, 2.68, -1.00), mat_dark)
		var room_number := Label3D.new()
		room_number.text = "ROOM 09"
		room_number.font_size = 12
		room_number.pixel_size = 0.003
		room_number.position = plate.position + Vector3(0, 0, -0.026)
		room_number.modulate = Color("d5c493")
		prop.add_child(room_number)
	else:
		# Wet footprints stop at the wall; no second copy of the roaming apparition.
		var footprint_material := _material(Color("69c9bc"), 0.0, 0.12)
		footprint_material.emission_enabled = true
		footprint_material.emission = Color("38b9a8")
		footprint_material.emission_energy_multiplier = 1.8
		for step in range(9):
			var footprint := MeshInstance3D.new()
			var print_mesh := SphereMesh.new()
			print_mesh.radius = 0.18
			print_mesh.height = 0.06
			footprint.mesh = print_mesh
			footprint.scale = Vector3(0.9, 0.5, 1.35)
			footprint.position = Vector3(-0.23 if step % 2 == 0 else 0.23, 0.045, 1.0 - step * 0.25)
			footprint.material_override = footprint_material
			prop.add_child(footprint)


func _add_exit(at: Vector3) -> void:
	exit_door = _add_box("Flickering wall", Vector3(2.4, 3.0, 0.22), at + Vector3(0, 1.5, -1.15), mat_wall, true)
	for x in [-1.25, 1.25]:
		_add_box("Exit crack metal edge", Vector3(0.09, 3.05, 0.10), at + Vector3(x, 1.5, -1.02), mat_steel, false)
	_add_box("Exit crack lintel", Vector3(2.58, 0.09, 0.10), at + Vector3(0, 3.02, -1.02), mat_steel, false)
	var seam := MeshInstance3D.new()
	var line := BoxMesh.new()
	line.size = Vector3(0.035, 2.15, 0.04)
	seam.mesh = line
	seam.position = at + Vector3(0.0, 1.5, -1.0)
	seam.material_override = mat_light
	add_child(seam)
	exit_label = Label3D.new()
	exit_label.text = ""
	exit_label.font_size = 24
	exit_label.pixel_size = 0.004
	exit_label.position = at + Vector3(0, 2.3, -0.98)
	add_child(exit_label)


func _add_spawn_notice_board() -> void:
	# The player spawns facing the wall-mounted board, making it the first readable landmark.
	var board := Area3D.new()
	board.name = "Spawn exit instructions"
	board.position = _cell_world(Vector2i(2, 1)) + Vector3(-1.56, 1.62, 0)
	board.rotation.y = PI * 0.5
	board.collision_layer = 2
	board.collision_mask = 0
	board.set_meta("interact_kind", "spawn_sign")
	var board_shape := CollisionShape3D.new()
	var board_box := BoxShape3D.new()
	board_box.size = Vector3(1.18, 0.92, 0.16)
	board_shape.shape = board_box
	board.add_child(board_shape)
	var backing := MeshInstance3D.new()
	backing.mesh = _rounded_box_mesh(Vector3(1.18, 0.92, 0.11), 0.045)
	backing.material_override = mat_wood
	board.add_child(backing)
	var paper := MeshInstance3D.new()
	paper.mesh = _rounded_box_mesh(Vector3(1.02, 0.78, 0.025), 0.012)
	paper.position.z = -0.068
	paper.material_override = mat_paper
	board.add_child(paper)
	for edge_x in [-0.54, 0.54]:
		var frame := MeshInstance3D.new()
		frame.mesh = _rounded_box_mesh(Vector3(0.055, 0.94, 0.055), 0.018)
		frame.position.x = edge_x
		frame.material_override = mat_steel
		board.add_child(frame)
	for edge_y in [-0.44, 0.44]:
		var frame := MeshInstance3D.new()
		frame.mesh = _rounded_box_mesh(Vector3(1.12, 0.055, 0.055), 0.018)
		frame.position.y = edge_y
		frame.material_override = mat_steel
		board.add_child(frame)
	var clip_material := _material(Color("89764d"), 0.48, 0.37)
	for clip_x in [-0.37, 0.37]:
		var clip := MeshInstance3D.new()
		clip.mesh = _rounded_box_mesh(Vector3(0.12, 0.055, 0.026), 0.018)
		clip.position = Vector3(clip_x, 0.345, -0.087)
		clip.material_override = clip_material
		board.add_child(clip)
	for bolt_x in [-0.51, 0.51]:
		for bolt_y in [-0.39, 0.39]:
			var bolt := MeshInstance3D.new()
			var bolt_mesh := SphereMesh.new()
			bolt_mesh.radius = 0.022
			bolt_mesh.height = 0.018
			bolt.mesh = bolt_mesh
			bolt.position = Vector3(bolt_x, bolt_y, -0.105)
			bolt.material_override = clip_material
			board.add_child(bolt)
	var heading := Label3D.new()
	heading.text = "LEVEL 0 / 出口告示"
	heading.font_size = 32
	heading.pixel_size = 0.0035
	heading.position = Vector3(0, 0.28, -0.09)
	heading.modulate = Color("5a452c")
	board.add_child(heading)
	var instructions := Label3D.new()
	instructions.text = "先拍下三处空间异常\n再去右下角找裂墙出口\nE：查看完整线索"
	instructions.font_size = 24
	instructions.pixel_size = 0.0032
	instructions.position = Vector3(0, -0.10, -0.09)
	instructions.modulate = Color("413b30")
	board.add_child(instructions)
	var prompt := Label3D.new()
	prompt.text = "E  /  READ"
	prompt.font_size = 20
	prompt.pixel_size = 0.003
	prompt.position = Vector3(0, -0.36, -0.09)
	prompt.modulate = Color("887448")
	board.add_child(prompt)
	add_child(board)


func _add_escape_routes() -> void:
	# Route B: a keypad hidden in the Manila Room. The archived anomaly IDs form
	# the code; the note on the table gives their order.
	var terminal := Area3D.new()
	terminal.name = "Old service lift keypad"
	terminal.position = _cell_world(Vector2i(15, 6)) + Vector3(0, 0.0, 0)
	terminal.collision_layer = 2
	terminal.collision_mask = 0
	terminal.set_meta("interact_kind", "route_terminal")
	var terminal_shape := CollisionShape3D.new()
	var terminal_sphere := SphereShape3D.new()
	terminal_sphere.radius = 0.9
	terminal_shape.shape = terminal_sphere
	terminal_shape.position.y = 1.05
	terminal.add_child(terminal_shape)
	var terminal_body := MeshInstance3D.new()
	terminal_body.name = "Rounded cast-iron lift keypad housing"
	terminal_body.mesh = _rounded_box_mesh(Vector3(0.45, 1.3, 0.3), 0.045)
	terminal_body.position.y = 0.67
	terminal_body.material_override = mat_steel
	terminal.add_child(terminal_body)
	var screen_bezel := MeshInstance3D.new()
	screen_bezel.mesh = _rounded_box_mesh(Vector3(0.38, 0.32, 0.05), 0.035)
	screen_bezel.position = Vector3(0, 1.05, -0.169)
	screen_bezel.material_override = _material(Color("282d25"), 0.28, 0.48)
	terminal.add_child(screen_bezel)
	var terminal_screen := MeshInstance3D.new()
	var screen_box := BoxMesh.new()
	screen_box.size = Vector3(0.30, 0.235, 0.018)
	terminal_screen.mesh = screen_box
	terminal_screen.position = Vector3(0, 1.05, -0.201)
	var phosphor := _material(Color("80936b"), 0.0, 0.32)
	phosphor.emission_enabled = true
	phosphor.emission = Color("758a55")
	phosphor.emission_energy_multiplier = 0.7
	terminal_screen.material_override = phosphor
	terminal.add_child(terminal_screen)
	var display_text := Label3D.new()
	display_text.text = "LIFT 02  /  READY"
	display_text.font_size = 13
	display_text.pixel_size = 0.0025
	display_text.position = Vector3(0, 1.04, -0.212)
	display_text.modulate = Color("e0e8b5")
	terminal.add_child(display_text)
	var face_plate := MeshInstance3D.new()
	face_plate.mesh = _rounded_box_mesh(Vector3(0.36, 0.48, 0.035), 0.025)
	face_plate.position = Vector3(0, 0.58, -0.18)
	face_plate.material_override = _material(Color("272820"), 0.22, 0.54)
	terminal.add_child(face_plate)
	var keypad_chars: Array[Array] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["C", "0", "↵"]]
	for row in range(4):
		for column in range(3):
			var button := MeshInstance3D.new()
			button.mesh = _rounded_box_mesh(Vector3(0.071, 0.071, 0.032), 0.012)
			button.position = Vector3(-0.105 + column * 0.105, 0.75 - row * 0.095, -0.219)
			var button_material := _material(Color("817d68"), 0.16, 0.48)
			if row == 3 and column == 0:
				button_material = _material(Color("713f35"), 0.12, 0.52)
			elif row == 3 and column == 2:
				button_material = _material(Color("526748"), 0.18, 0.4)
			button.material_override = button_material
			terminal.add_child(button)
			var button_mark := Label3D.new()
			button_mark.text = str(keypad_chars[row][column])
			button_mark.font_size = 13
			button_mark.pixel_size = 0.0025
			button_mark.position = button.position + Vector3(0, -0.006, -0.018)
			button_mark.modulate = Color("eee5c9")
			terminal.add_child(button_mark)
	for side_x in [-0.17, 0.17]:
		for bolt_y in [0.39, 0.77]:
			var terminal_bolt := MeshInstance3D.new()
			var bolt_mesh := SphereMesh.new()
			bolt_mesh.radius = 0.022
			bolt_mesh.height = 0.018
			terminal_bolt.mesh = bolt_mesh
			terminal_bolt.position = Vector3(side_x, bolt_y, -0.205)
			terminal_bolt.material_override = mat_steel
			terminal.add_child(terminal_bolt)
	var status_led := MeshInstance3D.new()
	var led_mesh := SphereMesh.new()
	led_mesh.radius = 0.018
	led_mesh.height = 0.018
	status_led.mesh = led_mesh
	status_led.position = Vector3(0.17, 1.34, -0.16)
	status_led.material_override = phosphor
	terminal.add_child(status_led)
	var terminal_label := Label3D.new()
	terminal_label.text = "SERVICE LIFT\nE: 输入编号"
	terminal_label.font_size = 12
	terminal_label.pixel_size = 0.003
	terminal_label.position = Vector3(0, 1.55, 0)
	terminal_label.modulate = Color("d6cfaa")
	terminal.add_child(terminal_label)
	add_child(terminal)

	# Route C: restore flow through three scattered valves to reveal a flooded
	# threshold beside the wet-footprint anomaly.
	for index in range(WATER_VALVE_CELLS.size()):
		_add_water_valve(index, _cell_world(WATER_VALVE_CELLS[index]))
	_add_pool_gate(_cell_world(ANOMALY_CELLS["C"]) + Vector3(-1.3, 0, -0.7))


func _add_water_valve(index: int, at: Vector3) -> void:
	var valve := Area3D.new()
	valve.name = "Water valve %d" % (index + 1)
	valve.position = at
	valve.collision_layer = 2
	valve.collision_mask = 0
	valve.set_meta("interact_kind", "water_valve")
	valve.set_meta("valve_index", index)
	valve.set_meta("notches", [2, 1, 3][index])
	valve.add_to_group("pool_valves")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	shape.shape = sphere
	shape.position.y = 0.95
	valve.add_child(shape)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.045
	stem_mesh.bottom_radius = 0.045
	stem_mesh.height = 0.55
	stem.mesh = stem_mesh
	stem.position.y = 0.28
	stem.material_override = _material(Color("625d4e"), 0.55, 0.5)
	valve.add_child(stem)
	var wheel := MeshInstance3D.new()
	var wheel_mesh := TorusMesh.new()
	wheel_mesh.inner_radius = 0.13
	wheel_mesh.outer_radius = 0.20
	wheel_mesh.rings = 16
	wheel_mesh.ring_segments = 32
	wheel.mesh = wheel_mesh
	wheel.position.y = 0.58
	wheel.rotation_degrees.x = 90
	wheel.material_override = _material(Color("85784f"), 0.5, 0.48)
	valve.add_child(wheel)
	for spoke_index in range(4):
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.026, 0.31, 0.032)
		spoke.mesh = spoke_mesh
		spoke.position = Vector3(0, 0.58, 0)
		spoke.rotation.z = float(spoke_index) * PI * 0.5
		spoke.material_override = mat_steel
		valve.add_child(spoke)
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.07
	hub_mesh.bottom_radius = 0.07
	hub_mesh.height = 0.08
	hub.mesh = hub_mesh
	hub.position = Vector3(0, 0.58, 0.015)
	hub.rotation.x = PI * 0.5
	hub.material_override = mat_steel
	valve.add_child(hub)
	var label := Label3D.new()
	label.text = "水阀\n刻痕 %d" % int(valve.get_meta("notches"))
	label.font_size = 34
	label.pixel_size = 0.006
	label.position = Vector3(0, 1.68, 0)
	label.modulate = Color("b8fff2")
	label.outline_size = 9
	label.outline_modulate = Color("10292a")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	valve.add_child(label)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color("58e7d3")
	beacon.light_energy = 1.15
	beacon.omni_range = 4.8
	beacon.shadow_enabled = false
	beacon.position.y = 1.6
	valve.add_child(beacon)
	add_child(valve)


func _add_pool_gate(at: Vector3) -> void:
	var gate := Area3D.new()
	gate.name = "Flooded threshold to Level 37"
	gate.position = at
	gate.collision_layer = 2
	gate.collision_mask = 0
	gate.set_meta("interact_kind", "pool_gate")
	gate.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.15
	shape.shape = sphere
	shape.position.y = 1.0
	gate.add_child(shape)
	var frame_material := _material(Color("318e8b"), 0.28, 0.42)
	frame_material.emission_enabled = true
	frame_material.emission = Color("12605d")
	frame_material.emission_energy_multiplier = 0.8
	for offset in [-0.72, 0.72]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.12, 2.15, 0.13)
		post.mesh = post_mesh
		post.position = Vector3(offset, 1.05, 0)
		post.material_override = frame_material
		gate.add_child(post)
	var lintel := MeshInstance3D.new()
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(1.55, 0.13, 0.13)
	lintel.mesh = lintel_mesh
	lintel.position = Vector3(0, 2.08, 0)
	lintel.material_override = frame_material
	gate.add_child(lintel)
	var portal := MeshInstance3D.new()
	var portal_mesh := PlaneMesh.new()
	portal_mesh.size = Vector2(1.25, 1.85)
	portal.mesh = portal_mesh
	portal.position = Vector3(0, 1.0, -0.06)
	var portal_material := _material(Color("496f6d"), 0.05, 0.24)
	portal_material.emission_enabled = true
	portal_material.emission = Color("20aaa0")
	portal_material.emission_energy_multiplier = 1.4
	portal.material_override = portal_material
	gate.add_child(portal)
	var label := Label3D.new()
	label.text = "LEVEL 37\n按 E 进入"
	label.font_size = 27
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.42, 0)
	label.modulate = Color("aafff1")
	label.outline_size = 8
	label.outline_modulate = Color("103334")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gate.add_child(label)
	gate.visible = false
	add_child(gate)
	set_meta("pool_gate", gate)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = _cell_world(_find_cell("S")) + Vector3(0, 0.15, 0)
	player.rotation.y = PI
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.65
	capsule.shape = shape
	capsule.position.y = 0.82
	player.add_child(capsule)
	var head := Node3D.new()
	head.position.y = 1.48
	player.add_child(head)
	camera = Camera3D.new()
	camera.fov = 78
	camera.current = true
	head.add_child(camera)
	var flashlight := SpotLight3D.new()
	flashlight.light_color = Color("e6e1c0")
	flashlight.light_energy = 1.25
	flashlight.spot_range = 13.0
	flashlight.spot_angle = 42.0
	flashlight.shadow_enabled = false
	camera.add_child(flashlight)
	photo_flash = OmniLight3D.new()
	photo_flash.light_color = Color.WHITE
	photo_flash.light_energy = 0
	photo_flash.omni_range = 11
	photo_flash.omni_attenuation = 1.2
	camera.add_child(photo_flash)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -18)
	ray.collision_mask = 3
	ray.collide_with_areas = true
	ray.enabled = true
	camera.add_child(ray)
	add_child(player)


func _make_apparition() -> Node3D:
	var imported_figure := STALKER_SCENE.instantiate() as Node3D
	if imported_figure == null:
		return _make_procedural_apparition()
	imported_figure.name = "The Stalker · CC0 animated creature"
	imported_figure.scale = Vector3.ONE
	imported_figure.rotation.y = PI
	apparition_parts.clear()
	for part in imported_figure.find_children("*", "GeometryInstance3D", true, false):
		if part is GeometryInstance3D:
			apparition_parts.append(part)
	var animation_player := imported_figure.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player != null and animation_player.has_animation("Run"):
		animation_player.play("Run")
	return imported_figure


func _make_procedural_apparition() -> Node3D:
	var figure := Node3D.new()
	figure.name = "The Listener · original Level 0 apparition"
	var skin := _material(Color("a79b79"), 0.0, 0.92)
	skin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	skin.uv1_scale = Vector3(1.8, 1.8, 1.8)
	var skin_texture := load("res://assets/creatures/level01_listener_skin.png") as Texture2D
	if skin_texture != null:
		skin.albedo_texture = skin_texture
	else:
		skin.albedo_texture = _procedural_texture("carpet", Color("81765d"))
	var bruised := _material(Color("51483a"), 0.0, 0.96)
	var cartilage := _material(Color("71664f"), 0.0, 0.88)
	var cavity := _material(Color("090b09"), 0.0, 1.0)
	cavity.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ember := _material(Color("7b5940"), 0.0, 0.65)
	ember.emission_enabled = true
	ember.emission = Color("492f20")
	ember.emission_energy_multiplier = 0.35
	var rag := _material(Color("29271f"), 0.0, 1.0)

	# The Listener is a hunched, asymmetric 2.7 m figure with a collapsed rib cage,
	# a split face, one arm dragging near the floor, and an overlong opposite leg.
	_creature_ellipsoid(figure, "sunken pelvis", Vector3(0, 0.92, 0.04), Vector3(0.34, 0.34, 0.27), skin, Vector3(-8, 0, -7))
	_creature_ellipsoid(figure, "rib cage", Vector3(0.0, 1.48, -0.02), Vector3(0.43, 0.67, 0.33), skin, Vector3(4, 0, -11))
	_creature_ellipsoid(figure, "raised shoulder hump", Vector3(0.04, 1.91, 0.15), Vector3(0.39, 0.35, 0.34), bruised, Vector3(-12, 0, -15))
	_creature_segment(figure, "corded neck", Vector3(0.02, 1.82, -0.01), Vector3(0.04, 2.28, -0.09), 0.18, 0.13, skin)
	_creature_ellipsoid(figure, "long blank skull", Vector3(0.035, 2.39, -0.13), Vector3(0.27, 0.39, 0.28), skin, Vector3(0, 4, -19))
	_creature_ellipsoid(figure, "jaw pulled open", Vector3(0.045, 2.20, -0.275), Vector3(0.20, 0.13, 0.13), bruised, Vector3(0, 0, 7))
	_creature_ellipsoid(figure, "vertical facial void", Vector3(0.045, 2.34, -0.388), Vector3(0.105, 0.245, 0.028), cavity)
	for side in [-1.0, 1.0]:
		_creature_ellipsoid(figure, "recessed eye socket", Vector3(side * 0.112, 2.48, -0.351), Vector3(0.055, 0.071, 0.025), cavity)
		_creature_ellipsoid(figure, "distant eye glint", Vector3(side * 0.112, 2.48, -0.377), Vector3(0.018, 0.023, 0.012), ember)
		for tooth in range(3):
			var tooth_y := 2.27 + tooth * 0.065
			_creature_segment(figure, "broken upper tooth", Vector3(side * (0.035 + tooth * 0.006), tooth_y, -0.41), Vector3(side * (0.035 + tooth * 0.006), tooth_y - 0.045, -0.415), 0.018, 0.001, cartilage, 5)
			_creature_segment(figure, "broken lower tooth", Vector3(side * (0.035 + tooth * 0.006), tooth_y - 0.058, -0.41), Vector3(side * (0.035 + tooth * 0.006), tooth_y - 0.018, -0.415), 0.001, 0.016, cartilage, 5)

	# Raised, irregular cartilage ribs make the torso read as a body under skin.
	for rib in range(5):
		var rib_y := 1.20 + rib * 0.16
		for side in [-1.0, 1.0]:
			_creature_segment(figure, "raised rib", Vector3(side * 0.025, rib_y, -0.306), Vector3(side * (0.22 + rib * 0.018), rib_y + 0.055, -0.303 + rib * 0.018), 0.045, 0.018, cartilage, 7)
			_creature_segment(figure, "rib hooked inward", Vector3(side * (0.22 + rib * 0.018), rib_y + 0.055, -0.303 + rib * 0.018), Vector3(side * (0.30 + rib * 0.015), rib_y - 0.025, -0.265 + rib * 0.015), 0.018, 0.006, cartilage, 7)
	for vertebra in range(7):
		var spine_y := 1.02 + vertebra * 0.17
		_creature_ellipsoid(figure, "protruding vertebra", Vector3(0.025, spine_y, 0.32 - vertebra * 0.025), Vector3(0.075, 0.09, 0.08), cartilage)
		if vertebra in [2, 4, 6]:
			_creature_segment(figure, "back spur", Vector3(0.025, spine_y, 0.37), Vector3(0.055, spine_y + 0.10, 0.49), 0.075, 0.004, bruised, 6)

	# Unevenly jointed arms: left fingers almost scrape the carpet; right arm stays bent.
	_creature_ellipsoid(figure, "left shoulder", Vector3(-0.37, 1.76, 0.01), Vector3(0.23, 0.29, 0.25), bruised, Vector3(0, 0, -17))
	_creature_segment(figure, "left upper arm", Vector3(-0.38, 1.77, 0.01), Vector3(-0.53, 1.13, -0.045), 0.18, 0.125, skin, 9)
	_creature_ellipsoid(figure, "left elbow", Vector3(-0.53, 1.12, -0.045), Vector3(0.15, 0.18, 0.16), bruised)
	_creature_segment(figure, "left forearm", Vector3(-0.53, 1.10, -0.05), Vector3(-0.66, 0.32, -0.17), 0.13, 0.075, skin, 9)
	_creature_ellipsoid(figure, "left palm", Vector3(-0.68, 0.20, -0.18), Vector3(0.13, 0.19, 0.075), bruised, Vector3(0, 0, -12))
	_creature_ellipsoid(figure, "right shoulder", Vector3(0.37, 1.77, 0.045), Vector3(0.22, 0.28, 0.23), skin, Vector3(0, 0, 12))
	_creature_segment(figure, "right upper arm", Vector3(0.37, 1.78, 0.04), Vector3(0.57, 1.34, 0.10), 0.17, 0.12, skin, 9)
	_creature_ellipsoid(figure, "right elbow", Vector3(0.57, 1.33, 0.10), Vector3(0.13, 0.17, 0.14), bruised)
	_creature_segment(figure, "right forearm", Vector3(0.57, 1.32, 0.10), Vector3(0.49, 0.68, -0.12), 0.12, 0.075, skin, 9)
	_creature_ellipsoid(figure, "right palm", Vector3(0.48, 0.57, -0.13), Vector3(0.13, 0.18, 0.07), bruised)
	for digit in range(4):
		var finger_x := float(digit) - 1.5
		var left_start := Vector3(-0.68 + finger_x * 0.055, 0.13, -0.20)
		var left_tip := left_start + Vector3(finger_x * 0.10, -0.21 - (0.04 if digit == 1 else 0.0), -0.035)
		_creature_segment(figure, "left elongated finger", left_start, left_tip, 0.035, 0.021, skin, 6)
		_creature_segment(figure, "left hooked nail", left_tip, left_tip + Vector3(finger_x * 0.035, -0.11, -0.025), 0.022, 0.001, cartilage, 5)
		var right_start := Vector3(0.48 + finger_x * 0.055, 0.51, -0.18)
		var right_tip := right_start + Vector3(finger_x * 0.10, -0.16, -0.05)
		_creature_segment(figure, "right long finger", right_start, right_tip, 0.032, 0.019, skin, 6)
		_creature_segment(figure, "right hooked nail", right_tip, right_tip + Vector3(finger_x * 0.03, -0.09, -0.025), 0.020, 0.001, cartilage, 5)

	# One leg buckles inward; the other is stretched into a narrow, dragging stride.
	_creature_ellipsoid(figure, "left hip", Vector3(-0.17, 0.92, 0.02), Vector3(0.22, 0.27, 0.23), skin)
	_creature_segment(figure, "left thigh", Vector3(-0.17, 0.93, 0.02), Vector3(-0.25, 0.51, 0.08), 0.20, 0.12, skin, 9)
	_creature_ellipsoid(figure, "left knee", Vector3(-0.25, 0.50, 0.08), Vector3(0.13, 0.16, 0.14), bruised)
	_creature_segment(figure, "left shin", Vector3(-0.25, 0.49, 0.08), Vector3(-0.16, 0.13, -0.10), 0.12, 0.07, skin, 8)
	_creature_ellipsoid(figure, "left dragging foot", Vector3(-0.16, 0.095, -0.18), Vector3(0.18, 0.10, 0.31), bruised, Vector3(12, 0, 0))
	_creature_ellipsoid(figure, "right hip", Vector3(0.16, 0.93, 0.05), Vector3(0.22, 0.28, 0.24), skin)
	_creature_segment(figure, "right thigh", Vector3(0.16, 0.93, 0.05), Vector3(0.30, 0.59, 0.12), 0.19, 0.12, skin, 9)
	_creature_ellipsoid(figure, "right knee", Vector3(0.30, 0.58, 0.12), Vector3(0.13, 0.15, 0.14), bruised)
	_creature_segment(figure, "right elongated shin", Vector3(0.30, 0.57, 0.12), Vector3(0.24, 0.12, -0.10), 0.12, 0.064, skin, 8)
	_creature_ellipsoid(figure, "right narrow foot", Vector3(0.24, 0.09, -0.18), Vector3(0.15, 0.09, 0.28), bruised)
	for toe in range(3):
		var toe_x := float(toe - 1) * 0.085
		var toe_start := Vector3(-0.16 + toe_x, 0.085, -0.36)
		_creature_segment(figure, "left toe", toe_start, toe_start + Vector3(toe_x * 0.3, -0.015, -0.17), 0.045, 0.021, skin, 6)
		_creature_segment(figure, "left toe claw", toe_start + Vector3(toe_x * 0.3, -0.015, -0.17), toe_start + Vector3(toe_x * 0.42, -0.025, -0.28), 0.022, 0.001, cartilage, 5)

	# Torn membranes and dark folds break the clean toy-like silhouette.
	for fold in range(4):
		var side := -1.0 if fold % 2 == 0 else 1.0
		var top := Vector3(side * (0.14 + fold * 0.025), 1.08 - fold * 0.035, 0.18)
		var tip := top + Vector3(side * (0.11 + fold * 0.02), -0.34 - float(fold % 2) * 0.12, 0.07)
		_creature_segment(figure, "ragged hide strip", top, tip, 0.065, 0.003, rag, 5)

	for part in figure.find_children("*", "GeometryInstance3D", true, false):
		if part is GeometryInstance3D:
			apparition_parts.append(part)
	return figure


func _creature_ellipsoid(parent: Node3D, label: String, at: Vector3, scale: Vector3, material: Material, rotation_degrees: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 14
	sphere.rings = 10
	part.mesh = sphere
	part.position = at
	part.scale = scale
	part.rotation_degrees = rotation_degrees
	part.material_override = material
	parent.add_child(part)
	return part


func _creature_segment(parent: Node3D, label: String, start: Vector3, finish: Vector3, radius_start: float, radius_finish: float, material: Material, sides: int = 8) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var segment := CylinderMesh.new()
	segment.top_radius = radius_finish
	segment.bottom_radius = radius_start
	segment.height = maxf(start.distance_to(finish), 0.02)
	segment.radial_segments = sides
	segment.rings = 3
	part.mesh = segment
	part.position = (start + finish) * 0.5
	part.basis = Basis(Quaternion(Vector3.UP, (finish - start).normalized()))
	part.material_override = material
	parent.add_child(part)
	return part


func _build_entity() -> void:
	enemy = CharacterBody3D.new()
	enemy.name = "Unconfirmed hallway shadow"
	enemy.collision_layer = 2
	enemy.collision_mask = 1
	enemy.position = _cell_world(Vector2i(8, 1)) + Vector3(0, 0.15, 0)
	enemy_target = enemy.position
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 2.25
	shape_node.shape = capsule
	shape_node.position.y = 1.1
	enemy.add_child(shape_node)
	enemy_mesh = _make_apparition()
	enemy_mesh.name = "Faceted shadow"
	enemy_mesh.position.y = 0
	enemy.add_child(enemy_mesh)
	enemy.visible = false
	add_child(enemy)


func _stage_stalker_encounter() -> void:
	var player_cell := _world_cell(player.global_position)
	var desired := player.global_position + (-camera.global_basis.z) * 11.0
	var best_cell := Vector2i(-1, -1)
	var best_score := INF
	for z in range(level_map.size()):
		for x in range(level_map[z].length()):
			var cell := Vector2i(x, z)
			if not _is_walkable(cell) or cell == player_cell or _inside_manila(cell):
				continue
			var world := _cell_world(cell)
			var separation := world.distance_to(player.global_position)
			if separation < 8.0 or separation > 15.0:
				continue
			if _next_path_cell(cell, player_cell) == cell:
				continue
			var score := world.distance_to(desired) + absf(separation - 11.0) * 0.28
			if score < best_score:
				best_score = score
				best_cell = cell
	if best_cell.x < 0:
		for z in range(level_map.size()):
			for x in range(level_map[z].length()):
				var cell := Vector2i(x, z)
				if not _is_walkable(cell) or cell == player_cell or _inside_manila(cell):
					continue
				if _next_path_cell(cell, player_cell) == cell:
					continue
				var distance := _cell_world(cell).distance_to(player.global_position)
				var score := absf(distance - 11.0)
				if score < best_score:
					best_score = score
					best_cell = cell
	if best_cell.x >= 0:
		enemy.position = _cell_world(best_cell) + Vector3(0, 0.15, 0)
		enemy_target = enemy.position
		enemy.velocity = Vector3.ZERO
		enemy.look_at(Vector3(player.global_position.x, enemy.global_position.y, player.global_position.z), Vector3.UP)
		enemy.visible = true
		alert_left = 10.0


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(26, 20)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color("eee8cc"))
	layer.add_child(hud)
	hud_subtitle = Label.new()
	hud_subtitle.position = Vector2(26, 75)
	hud_subtitle.add_theme_font_size_override("font_size", 15)
	hud_subtitle.add_theme_color_override("font_color", Color("c8c0a0"))
	layer.add_child(hud_subtitle)
	fear_bar = ProgressBar.new()
	fear_bar.position = Vector2(26, 112)
	fear_bar.size = Vector2(220, 12)
	fear_bar.max_value = 100
	fear_bar.show_percentage = false
	fear_bar.add_theme_stylebox_override("fill", _flat_style(Color("a94639")))
	layer.add_child(fear_bar)
	guide_label = Label.new()
	guide_label.position = Vector2(26, 140)
	guide_label.custom_minimum_size = Vector2(590, 150)
	guide_label.add_theme_font_size_override("font_size", 14)
	guide_label.add_theme_color_override("font_color", Color("d4cda9"))
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_label.visible = false
	layer.add_child(guide_label)
	message = Label.new()
	message.anchor_left = 0.5
	message.anchor_right = 0.5
	message.anchor_top = 0.5
	message.anchor_bottom = 0.5
	message.offset_left = -280
	message.offset_right = 280
	message.offset_top = -38
	message.offset_bottom = 60
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 24)
	message.add_theme_color_override("font_color", Color("f5eac4"))
	layer.add_child(message)
	notice = Label.new()
	notice.anchor_left = 0.5
	notice.anchor_right = 0.5
	notice.anchor_top = 1.0
	notice.anchor_bottom = 1.0
	notice.offset_left = -410
	notice.offset_right = 410
	notice.offset_top = -180
	notice.offset_bottom = -24
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size", 18)
	notice.add_theme_color_override("font_color", Color("ddd4ae"))
	layer.add_child(notice)
	inventory_panel = PanelContainer.new()
	inventory_panel.anchor_left = 0.5
	inventory_panel.anchor_right = 0.5
	inventory_panel.anchor_top = 0.5
	inventory_panel.anchor_bottom = 0.5
	inventory_panel.offset_left = -230
	inventory_panel.offset_right = 230
	inventory_panel.offset_top = -190
	inventory_panel.offset_bottom = 190
	inventory_panel.visible = false
	layer.add_child(inventory_panel)
	_update_hud()
	message.text = "+"


func _flat_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style


func _build_menus() -> void:
	var layer := get_node("HUD") as CanvasLayer
	title_overlay = _make_overlay(layer, "LEVEL 0  /  黄灯办公区", "荧光灯嗡鸣着延伸进看不见尽头的走廊。
拍摄异常、破解旧电梯密码，或接通阀门找到不同层级的出口。", [["开始探索", _start_game], ["操作说明", _show_controls], ["退出", _quit_game]])
	pause_overlay = _make_overlay(layer, "暂停", "", [["继续", _resume_game], ["重新开始", _restart_game], ["返回标题", _return_title]])
	_add_sensitivity_control(pause_overlay)
	end_overlay = _make_overlay(layer, "", "", [["重新探索", _restart_game], ["返回标题", _return_title]])
	title_overlay.visible = true
	pause_overlay.visible = false
	end_overlay.visible = false


func _add_sensitivity_control(overlay: Control) -> void:
	var column := overlay.get_child(0).get_child(0) as VBoxContainer
	var settings_box := VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "鼠标灵敏度"
	title.custom_minimum_size.x = 112
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 1.5
	slider.step = 0.05
	slider.value = mouse_sensitivity_multiplier
	slider.custom_minimum_size.x = 225
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_set_mouse_sensitivity)
	row.add_child(slider)
	sensitivity_value_label = Label.new()
	sensitivity_value_label.custom_minimum_size.x = 48
	sensitivity_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sensitivity_value_label.text = "%d%%" % roundi(mouse_sensitivity_multiplier * 100.0)
	row.add_child(sensitivity_value_label)
	settings_box.add_child(row)
	var hint := Label.new()
	hint.text = "Esc 暂停时可随时调整（设置会自动保存）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("c8c0a0"))
	settings_box.add_child(hint)
	column.add_child(settings_box)


func _make_overlay(parent: Node, title: String, subtitle: String, actions: Array) -> Control:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.027, 0.021, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(shade)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 420)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-240, -210)
	shade.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	column.add_child(heading)
	var description := Label.new()
	description.text = subtitle
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 90
	description.add_theme_font_size_override("font_size", 16)
	column.add_child(description)
	for action in actions:
		var button := Button.new()
		button.text = action[0]
		button.custom_minimum_size = Vector2(300, 46)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(action[1])
		column.add_child(button)
	return shade


func _show_controls() -> void:
	var label := title_overlay.get_child(0).get_child(0).get_child(1) as Label
	label.text = "WASD 移动 · Shift 奔跑 · 空格跳跃 · 鼠标观察
E 调查/拾取/操作阀门或出口 · 左键拍照闪光
Tab 背包 · Q 使用杏仁水 · Esc 暂停（可调鼠标灵敏度）
拍三处异常可开墙缝；查档案找电梯密码；按刻痕顺序开阀门可找水门。
怪物：第一次拍照后苏醒；无遮挡地看着它会完全停住，移开视线后继续追你；拍中它会把它随机传送到迷宫另一处。
冲刺和快门会吸引它，靠近时心跳会变响。黑暗区没有灯；地面陷坑可以助跑跳过。"
	label.custom_minimum_size.y = 220


func _start_game() -> void:
	title_overlay.visible = false
	paused = false
	game_started = true
	# A brief, distant sighting confirms the creature is part of the level before
	# the camera mechanic wakes it for the real chase.
	intro_reveal_left = 5.0
	enemy.visible = true
	enemy.look_at(Vector3(player.global_position.x, enemy.global_position.y, player.global_position.z), Vector3.UP)
	player.rotation.y = -PI * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_show_notice("左侧任务栏会持续指路。追踪者怕被盯住：无遮挡地看着它时，它会完全停下；拍中它会将它随机传送。", 7.5)


func _resume_game() -> void:
	paused = false
	pause_overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restart_game() -> void:
	get_tree().reload_current_scene()


func _return_title() -> void:
	get_tree().reload_current_scene()


func _quit_game() -> void:
	get_tree().quit()


func _process(delta: float) -> void:
	if not game_started:
		return
	if paused:
		if heartbeat_player != null:
			heartbeat_player.stop()
		return
	if keypad_active:
		return
	if game_over or won:
		return
	if not mascot_jumpscare_triggered:
		mascot_guarantee_time += delta
		if mascot_guarantee_time >= 22.0:
			_trigger_mascot_jumpscare()
	clock += delta
	mascot_aftercare_left = maxf(0.0, mascot_aftercare_left - delta)
	guide_clock += delta
	if notice_left <= 0.0 and guide_stage == 0 and guide_clock > 18.0 and not sign_read:
		guide_stage = 1
		_show_notice("入口告示牌写着离开方法，回到起点正前方按 E 阅读；先完成主线，再按喜好探索其他出口。", 6.0)
	elif notice_left <= 0.0 and guide_stage == 1 and guide_clock > 42.0 and not archive_read:
		guide_stage = 2
		_show_notice("迷路时找较暖的灯光和木桌：Manila Room 的档案会提示旧电梯密码与阀门顺序。", 6.0)
	if notice_left > 0:
		notice_left -= delta
		if notice_left <= 0:
			notice.text = ""
	if photo_flash.light_energy > 0:
		photo_flash.light_energy = maxf(0.0, photo_flash.light_energy - delta * 45.0)
	if mascot_jumpscare_active:
		mascot_jumpscare_time += delta
		var scare_progress := clampf(mascot_jumpscare_time / 0.58, 0.0, 1.0)
		var eased_progress := 1.0 - pow(1.0 - scare_progress, 3.0)
		mascot_jumpscare.position = Vector3(0, 0, lerpf(-2.4, -0.72, eased_progress))
		mascot_jumpscare.scale = Vector3.ONE * lerpf(0.03, 1.15, eased_progress)
		mascot_jumpscare.rotation.z = sin(mascot_jumpscare_time * 28.0) * 0.05
		mascot_jumpscare.rotation.y = sin(mascot_jumpscare_time * 15.0) * 0.08
		if mascot_jumpscare_time >= 1.2:
			mascot_jumpscare_active = false
			mascot_jumpscare.visible = false
			mascot_jumpscare.scale = Vector3.ZERO
	if game_over or won:
		return
	if entity_stunned > 0:
		entity_stunned = maxf(0.0, entity_stunned - delta)
	monster_grace_left = maxf(0.0, monster_grace_left - delta)
	if intro_reveal_left > 0.0 and not entity_awake:
		intro_reveal_left = maxf(0.0, intro_reveal_left - delta)
		if intro_reveal_left == 0.0:
			enemy.visible = false
	if alert_left > 0:
		alert_left -= delta
	var in_manila := _inside_manila(_world_cell(player.global_position))
	if entity_awake and not in_manila and monster_grace_left <= 0.0:
		_update_entity(delta)
		if entity_stunned <= 0.0:
			enemy.visible = true
			var sway := sin(clock * 2.1) * 0.06
			enemy_mesh.rotation.z = sway
			for part in apparition_parts:
				part.transparency = 0.0
	var enemy_distance := player.global_position.distance_to(enemy.global_position)
	if entity_awake and enemy.visible and not monster_tutorial_shown:
		monster_tutorial_shown = true
		monster_grace_left = 4.5
		_show_notice("追踪者应对：盯住它，它会完全停下；拍中它，它会随机传送到迷宫另一处。移开视线后它才会继续追。", 6.0)
	var in_blackout := _is_blackout_cell(_world_cell(player.global_position))
	if in_blackout:
		blackout_time += delta
		if blackout_time >= 1.1 and not mascot_jumpscare_triggered:
			_trigger_mascot_jumpscare()
	else:
		blackout_time = 0.0
	var has_enemy_sight := _has_line_of_sight_to_enemy()
	var threat_near := entity_awake and not in_manila and enemy_distance < 14.0 and entity_stunned <= 0.0 and has_enemy_sight
	if threat_near:
		if heartbeat_player != null:
			if not heartbeat_player.playing:
				heartbeat_player.play()
			heartbeat_player.volume_db = lerpf(-34.0, -7.0, clampf((14.0 - enemy_distance) / 13.0, 0.0, 1.0))
	else:
		if heartbeat_player != null and heartbeat_player.playing:
			heartbeat_player.stop()
		if enemy_step_player != null:
			enemy_step_player.stop()
	if entity_awake and not in_manila and enemy.velocity.length() > 0.5 and enemy_distance < 25.0:
		enemy_step_left -= delta
		if enemy_step_left <= 0.0 and enemy_step_player != null:
			enemy_step_player.play()
			enemy_step_left = 0.62 if alert_left > 0.0 else 0.95
	else:
		enemy_step_left = 0.0
	if in_manila:
		enemy.visible = false
	if ambient_player != null:
		ambient_player.volume_db = -42.0 if in_blackout else (-22.0 if in_manila else -9.0)
		level_environment.ambient_light_color = Color("171712") if in_blackout else Color("625f49")
		level_environment.ambient_light_energy = 0.035 if in_blackout else 0.22
		level_environment.fog_light_color = Color("25251e") if in_blackout else Color("9d986f")
		level_environment.fog_density = 0.05 if in_blackout else 0.024
	var horizontal_gap := Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(enemy.global_position.x, enemy.global_position.z))
	var vertical_overlap := absf(player.global_position.y - enemy.global_position.y) < 1.35
	if entity_awake and not in_manila and horizontal_gap <= 0.72 and vertical_overlap and entity_stunned <= 0 and mascot_aftercare_left <= 0.0 and monster_grace_left <= 0.0:
		_finish(false)
	if mascot_aftercare_left > 0.0 or mascot_jumpscare_active or monster_grace_left > 0.0:
		pass
	elif entity_awake and not in_manila and enemy_distance < 11.0 and has_enemy_sight:
		fear = minf(100.0, fear + delta * (11.0 - enemy_distance) * 1.55)
	else:
		fear = maxf(0.0, fear - delta * 2.2)
	_update_hud()
	_flicker_nearby_lights(enemy_distance)


func _physics_process(delta: float) -> void:
	if not game_started or paused or game_over or won or inventory_open or keypad_active or mascot_jumpscare_active:
		return
	var input_vector := Vector2.ZERO
	input_vector.x = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	input_vector.y = float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	input_vector = input_vector.normalized()
	sprinting = Input.is_key_pressed(KEY_SHIFT) and input_vector.length() > 0.1
	var speed := 5.1 if sprinting and stamina > 1.0 else 3.35
	if jump_requested and player.is_on_floor() and stamina >= 8.0:
		player.velocity.y = 7.2
		stamina = maxf(0.0, stamina - 8.0)
		jump_requested = false
	elif player.is_on_floor():
		player.velocity.y = -0.5
	else:
		player.velocity.y -= 22.0 * delta
	if sprinting and stamina > 0.0:
		stamina = maxf(0.0, stamina - delta * 22.0)
	else:
		stamina = minf(100.0, stamina + delta * 13.0)
	var local_move := Vector3(input_vector.x, 0, input_vector.y)
	var direction := player.global_basis * local_move
	direction.y = 0
	if direction.length() > 0.01:
		direction = direction.normalized()
		player.velocity.x = direction.x * speed
		player.velocity.z = direction.z * speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, 14 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0, 14 * delta)
	player.move_and_slide()
	if input_vector.length() > 0.1 and player.is_on_floor():
		player_step_left -= delta
		if player_step_left <= 0.0:
			_play_sfx("footstep", -14.0)
			player_step_left = 0.38 if sprinting else 0.56
	else:
		player_step_left = 0.0
	if player.global_position.y < -1.2:
		fall_death = true
		_finish(false)
	if sprinting and entity_awake:
		alert_left = maxf(alert_left, 2.0)
	if entity_awake and alert_left > 0:
		var forward := -camera.global_basis.z
		if player.global_position.distance_to(enemy.global_position) < 8.5 and forward.dot((enemy.global_position - camera.global_position).normalized()) > 0.15:
			alert_left = maxf(alert_left, 1.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if keypad_active:
			_handle_keypad_key(event)
			return
		if event.keycode == KEY_SPACE and game_started and not paused and not inventory_open:
			jump_requested = true
		elif event.keycode == KEY_ESCAPE:
			if not game_started:
				return
			if inventory_open:
				_toggle_inventory()
			elif not game_over and not won:
				paused = not paused
				pause_overlay.visible = paused
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_R and (game_over or won):
			_restart_game()
		elif event.keycode == KEY_TAB and game_started and not paused:
			_toggle_inventory()
		elif event.keycode == KEY_Q and game_started and not paused:
			_use_almond_water()
		elif event.keycode == KEY_E and game_started and not paused:
			_interact()
	if event is InputEventMouseButton and game_started and not paused and not inventory_open:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_take_photo()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and game_started and not paused and not inventory_open and not game_over and not won:
		player.rotate_y(-event.relative.x * MOUSE_BASE_SENSITIVITY * mouse_sensitivity_multiplier)
		camera.rotate_x(-event.relative.y * MOUSE_BASE_SENSITIVITY * mouse_sensitivity_multiplier)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-82), deg_to_rad(82))


func _handle_keypad_key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		keypad_active = false
		keypad_buffer = ""
		message.text = "+"
		return
	if event.keycode == KEY_BACKSPACE:
		keypad_buffer = keypad_buffer.left(maxi(0, keypad_buffer.length() - 1))
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		keypad_active = false
		message.text = "+"
		if keypad_buffer == "419":
			_play_sfx("watergate")
			_finish_route("Level 2 · 管道梦境", "旧电梯向下运行了很久。门开时，黄色墙纸已经变成裸露的管线与混凝土。\n路线：按 Manila Room 档案给出的顺序输入三个异常编号。")
		else:
			_play_sfx("error")
			keypad_buffer = ""
			_show_notice("电梯继电器弹回原位。密码不对，再核对异常编号与顺序。", 3.5)
		return
	else:
		var key_text := OS.get_keycode_string(event.keycode)
		if key_text.length() == 1 and key_text >= "0" and key_text <= "9" and keypad_buffer.length() < 3:
			keypad_buffer += key_text
			_play_sfx("valve", -13.0)
		message.text = "旧电梯密码\n按墙鼓包 → 空门 → 湿脚印的照片编号输入\n[ 输入数字 · Enter 确认 · Esc 退出 ]\n%s_" % keypad_buffer


func _interact() -> void:
	if player.global_position.distance_to(_cell_world(EXIT_CELL)) < 3.0:
		_try_exit()
		return
	ray.target_position = Vector3(0, 0, -3.6)
	ray.force_raycast_update()
	ray.target_position = Vector3(0, 0, -18)
	if not ray.is_colliding():
		_show_notice("没有可调查的东西。", 1.4)
		return
	var target := ray.get_collider() as Node
	while target != null and not target.has_meta("interact_kind") and not target.has_meta("target_kind"):
		target = target.get_parent()
	if target == null:
		_show_notice("这里只剩下发黄的墙纸。", 1.8)
		return
	var kind := str(target.get_meta("interact_kind", ""))
	if kind == "pickup":
		var item_id := str(target.get_meta("item_id", ""))
		if item_id == "almond_water":
			_collect_almond_water(target)
	elif kind == "spawn_sign":
		sign_read = true
		_play_sfx("paper")
		_show_notice("Level 0 出口告示：\n主线：左键拍下三处异常，随后前往右下方裂墙按 E。\n旧电梯：去暖色灯光下的 Manila Room 查维修档案，按异常编号顺序输入。\n水门：按左侧任务栏的实时方向提示，找到刻 1、刻 2、刻 3 的阀门；全开后沿任务指引回蓝门。\n怪物：被你看见时完全停住；被拍中后随机传送。", 11.0)
		_update_hud()
	elif kind == "note":
		note_count += 1
		_play_sfx("paper")
		var line := "字迹写着：‘对准鼓包、空门、湿脚印拍照，按记录顺序得到电梯密码。出口不止墙缝，去有木桌的暖色房间找维修档案。’" if note_count == 1 else "纸条背面：‘阀门上刻着一、二、三道槽。只按这个顺序转动；三处接通后，回湿脚印旁找亮起的蓝色门框。’"
		_show_notice(line, 5.0)
		target.queue_free()
		_update_hud()
	elif kind == "manila_note":
		note_count = mini(2, note_count + 1)
		archive_read = true
		_play_sfx("paper")
		_show_notice("维修档案：旧电梯密码＝鼓包 4 → 空门 1 → 湿脚印 9。水门路线：找到刻 1、刻 2、刻 3 的阀门，依次各按 E 一次；如果顺序错了就从刻 1 重新开始。三处水流接通后，回湿脚印旁找蓝色门框。", 10.0)
		target.queue_free()
		_update_hud()
	elif kind == "route_terminal":
		_play_sfx("paper")
		keypad_active = true
		keypad_buffer = ""
		message.text = "旧电梯密码\n按墙鼓包 → 空门 → 湿脚印的照片编号输入\n[ 输入数字 · Enter 确认 · Esc 退出 ]\n_"
		_show_notice("提示：按三张异常照片上的编号顺序输入，或返回 Manila Room 查看维修档案。", 5.0)
	elif kind == "water_valve":
		var valve_index := int(target.get_meta("valve_index", -1))
		var expected_order: Array[int] = [1, 0, 2]
		if valve_progress >= expected_order.size():
			_show_notice("三处水流已经接通。回到湿脚印旁寻找亮起的蓝色门框。", 3.5)
			return
		if valve_index == expected_order[valve_progress]:
			_play_sfx("valve")
			valve_progress += 1
			target.rotation.y += PI * 0.5
			var next_notch := valve_progress + 1
			var valve_message := "刻痕 %d 接通（%d / 3）。" % [int(target.get_meta("notches", 0)), valve_progress]
			if valve_progress < 3:
				valve_message += "下一步找刻痕 %d 的阀门。" % next_notch
			else:
				valve_message += "水门已开启，回湿脚印旁找蓝色门框。"
			_show_notice(valve_message, 4.0)
			if valve_progress == expected_order.size():
				_play_sfx("watergate")
				pool_gate_open = true
				var gate := get_meta("pool_gate") as Node3D
				if gate != null:
					gate.visible = true
					if gate is Area3D:
						gate.monitorable = true
				_show_notice("三段水流接通。湿脚印旁，一道蓝色门框亮了起来。", 5.0)
		else:
			_play_sfx("error")
			valve_progress = 0
			for valve in get_tree().get_nodes_in_group("pool_valves"):
				valve.rotation.y = 0.0
			_show_notice("顺序错误，三只阀门已复位。从刻痕 1 开始，依次操作刻痕 1 → 2 → 3。", 4.0)
	elif kind == "pool_gate":
		if pool_gate_open:
			get_tree().change_scene_to_file("res://poolrooms.tscn")
		else:
			_show_notice("门框后只有干燥的黑暗。先按阀门刻痕从少到多接通水流。", 3.5)
	elif kind == "rest":
		if target.has_meta("used"):
			_show_notice("你坐了片刻。椅垫仍然是干的。", 2.5)
		else:
			target.set_meta("used", true)
			fear = maxf(0.0, fear - 30.0)
			stamina = 100.0
			_show_notice("Manila Room 安静得听不见灯鸣。你恢复了体力，恐惧暂时退去。", 4.0)
		_update_hud()
	elif target.get_meta("target_kind", "") == "anomaly":
		_show_notice("这里的空间不对劲。用相机记录它的变化。", 2.4)
	else:
		_show_notice("它表面沾着潮湿的灰。", 1.8)


func _toggle_inventory() -> void:
	inventory_open = not inventory_open
	inventory_panel.visible = inventory_open
	if inventory_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var column := VBoxContainer.new()
		for child in inventory_panel.get_children():
			child.queue_free()
		var heading := Label.new()
		heading.text = "背包  /  INVENTORY"
		heading.add_theme_font_size_override("font_size", 24)
		column.add_child(heading)
		for item_text in ["拍立得相纸　%d / 10" % film, "杏仁水　%d 瓶（Q 使用）" % almond_water, "记录纸条　%d / 2" % note_count, "异常照片　%d / 3" % evidence.size()]:
			var entry := Label.new()
			entry.text = "▸ " + item_text
			entry.add_theme_font_size_override("font_size", 18)
			column.add_child(entry)
		var hint := Label.new()
		hint.text = "杏仁水可降低恐惧并恢复体力。
Tab / Esc 关闭背包"
		column.add_child(hint)
		inventory_panel.add_child(column)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _use_almond_water() -> void:
	if almond_water <= 0:
		_show_notice("背包里没有杏仁水。", 1.8)
		return
	almond_water -= 1
	fear = maxf(0.0, fear - 38.0)
	stamina = minf(100.0, stamina + 55.0)
	_show_notice("杏仁水的甜味压住了耳鸣。恐惧下降，体力恢复。", 3.0)
	_update_hud()


func _flicker_nearby_lights(_distance: float) -> void:
	light_blackout_cooldown = maxf(0.0, light_blackout_cooldown - get_process_delta_time())
	light_blackout_left = maxf(0.0, light_blackout_left - get_process_delta_time())
	if entity_awake and _distance < 12.0 and light_blackout_cooldown <= 0.0:
		light_blackout_left = 1.05
		light_blackout_cooldown = 9.0
	for light in flicker_lights:
		var local_phase := clock * 0.9 + float(light.get_instance_id() % 17)
		var flicker := 0.4 if sin(local_phase * 10.7) > 0.97 else 1.0
		if light_blackout_left > 0.0 and light.global_position.distance_to(enemy.global_position) < 14.0:
			flicker = 0.0 if light_blackout_left > 0.78 else (0.18 if light_blackout_left > 0.55 else 1.0)
		light.light_energy = (0.32 if _inside_manila(_world_cell(light.global_position)) else 0.4) * flicker


func _has_line_of_sight_to_enemy() -> bool:
	if enemy == null or player == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, enemy.global_position + Vector3.UP * 1.0)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == enemy


func _take_photo() -> void:
	if film <= 0:
		_show_notice("相纸用完了。记住墙缝的位置，找到出口。", 2.5)
		return
	film -= 1
	_play_sfx("camera")
	photo_flash.light_energy = 7.0
	if not entity_awake:
		entity_awake = true
		alert_left = 10.0
		_stage_stalker_encounter()
		_show_notice("闪光惊醒了追踪者！盯住它可让它完全停下；相机拍中它会随机传送到迷宫另一处。冲刺和快门声会吸引它。", 7.0)
	else:
		alert_left = maxf(alert_left, 7.0)
	var captured := false
	var target := _find_photo_anomaly()
	if target != null:
		var id := str(target.get_meta("anomaly_id", ""))
		if not evidence.has(id):
			evidence[id] = true
			captured = true
			_show_notice("照片记录：%s  /  编号 %s" % [ANOMALY_NAMES[id], ANOMALY_CODES[id]], 4.0)
			if evidence.size() == 3:
				_open_exit()
		else:
			_show_notice("这处异常已经记录过了。", 2.0)
	if entity_awake and enemy.visible and _photo_hits_enemy():
		_teleport_stalker_after_photo()
		captured = true
		_show_notice("拍中追踪者！它被随机传送到了迷宫另一处，趁现在拉开距离。", 3.8)
	elif not captured:
		_show_notice("相纸已曝光，但没锁定异常。靠近一些，把异常放在画面中央附近再拍。", 2.8)
	_update_hud()


func _photo_hits_enemy() -> bool:
	if enemy == null or not enemy.visible:
		return false
	var target_point := enemy.global_position + Vector3.UP * 1.1
	var offset := target_point - camera.global_position
	var distance := offset.length()
	if distance > 18.0 or distance < 0.1:
		return false
	if (-camera.global_basis.z).dot(offset / distance) < 0.82:
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target_point)
	query.exclude = [player.get_rid()]
	query.collision_mask = 2
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == enemy


func _teleport_stalker_after_photo() -> void:
	var player_cell := _world_cell(player.global_position)
	var current_cell := _world_cell(enemy.global_position)
	var candidates: Array[Vector2i] = []
	for z in range(level_map.size()):
		for x in range(level_map[z].length()):
			var cell := Vector2i(x, z)
			if not _is_walkable(cell) or _inside_manila(cell) or cell == current_cell:
				continue
			var distance := _cell_world(cell).distance_to(player.global_position)
			if distance < 18.0 or distance > 70.0:
				continue
			if _next_path_cell(cell, player_cell) == cell:
				continue
			candidates.append(cell)
	if candidates.is_empty():
		_stage_stalker_encounter()
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var destination: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	enemy.global_position = _cell_world(destination) + Vector3(0, 0.15, 0)
	enemy_target = enemy.global_position
	enemy.velocity = Vector3.ZERO
	enemy.visible = false
	entity_stunned = 1.35
	monster_grace_left = 1.35
	alert_left = 2.0
	apparition_observed = false


func _find_photo_anomaly() -> Area3D:
	var forward := -camera.global_basis.z
	var best: Area3D = null
	var best_score := -INF
	var space := get_world_3d().direct_space_state
	for anomaly in anomaly_targets:
		if not is_instance_valid(anomaly) or evidence.has(str(anomaly.get_meta("anomaly_id", ""))):
			continue
		var point: Vector3 = anomaly.global_position + (anomaly.get_meta("photo_point", Vector3(0, 1.0, 0)) as Vector3)
		var offset: Vector3 = point - camera.global_position
		var distance: float = offset.length()
		if distance > 16.0 or distance < 0.1:
			continue
		var alignment := forward.dot(offset / distance)
		if alignment < 0.82:
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, point)
		query.exclude = [player.get_rid()]
		query.collision_mask = 1
		var obstruction := space.intersect_ray(query)
		if not obstruction.is_empty() and camera.global_position.distance_to(obstruction.position) < distance - 0.45:
			continue
		var score: float = alignment * 2.0 - distance * 0.018
		if score > best_score:
			best_score = score
			best = anomaly
	return best


func _try_exit() -> void:
	var exit_at := _cell_world(EXIT_CELL)
	if player.global_position.distance_to(exit_at) > 3.0:
		return
	if evidence.size() < 3:
		_show_notice("墙缝仍然闭合。还需要记录 %d 处异常。" % (3 - evidence.size()), 2.5)
		return
	_finish_route("Level 1 · 宜居地带", "墙面裂开，另一侧传来电流声与空调风。你跨过门槛，身后的黄灯走廊随即消失。\n路线：拍摄并记录 Level 0 的三处空间异常，找到出口墙缝。")


func _open_exit() -> void:
	_play_sfx("watergate")
	if heavy_door_player != null:
		heavy_door_player.play()
	if exit_door != null:
		exit_door.queue_free()
		exit_door = null
	if exit_label != null:
		exit_label.text = "出口已显现 · 按 E 进入"
		exit_label.modulate = Color("f2d891")
	_show_notice("三处异常都已记录。裂墙出口位于地图右下方，走到发光标牌附近按 E 离开。", 6.0)


func _finish(success: bool) -> void:
	game_over = not success
	won = success
	if heartbeat_player != null:
		heartbeat_player.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if success:
		end_overlay.visible = true
		var block := end_overlay.get_child(0).get_child(0)
		(block.get_child(0) as Label).text = "第一层 · 逃离成功"
		(block.get_child(1) as Label).text = "你把肩膀抵向墙面。它像水一样裂开。\n再睁眼时，地毯变成了灰色。\n记录纸条：%d / 2" % note_count
	else:
		end_overlay.visible = true
		var block := end_overlay.get_child(0).get_child(0)
		(block.get_child(0) as Label).text = "你被留在了黄灯下"
		(block.get_child(1) as Label).text = "你坠进没有灯的地坑。" if fall_death else "追踪者抓住了你。它只有在真正碰到你时才会造成伤害。"


func _finish_route(destination: String, details: String) -> void:
	won = true
	game_over = false
	if heartbeat_player != null:
		heartbeat_player.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_overlay.visible = true
	var block := end_overlay.get_child(0).get_child(0)
	(block.get_child(0) as Label).text = "出口已开启 · %s" % destination
	(block.get_child(1) as Label).text = details + "\n\n当前原型包含 Level 0；下一层场景尚未接入。"


func _update_entity(delta: float) -> void:
	if entity_stunned > 0:
		return
	var to_shadow := enemy.global_position + Vector3.UP * 1.1 - camera.global_position
	var facing := -camera.global_basis.z
	var in_view_cone := facing.dot(to_shadow.normalized()) > 0.76
	var seen := false
	if in_view_cone:
		ray.target_position = camera.to_local(enemy.global_position + Vector3.UP * 1.1)
		ray.force_raycast_update()
		seen = ray.is_colliding() and ray.get_collider() == enemy
		ray.target_position = Vector3(0, 0, -18)
	apparition_observed = seen
	if seen:
		enemy.velocity = Vector3.ZERO
		return
	repath_left -= delta
	if repath_left <= 0:
		repath_left = 0.65
		var start := _world_cell(enemy.global_position)
		var goal := _world_cell(player.global_position)
		var next := _next_path_cell(start, goal)
		if next != start:
			enemy_target = _cell_world(next)
	var delta_pos := enemy_target - enemy.global_position
	delta_pos.y = 0
	var speed := 3.0 if alert_left > 0 else 1.35
	if delta_pos.length() > 0.12:
		var direction := delta_pos.normalized()
		enemy.velocity.x = direction.x * speed
		enemy.velocity.z = direction.z * speed
		enemy.look_at(Vector3(player.global_position.x, enemy.global_position.y, player.global_position.z), Vector3.UP)
	else:
		enemy.velocity.x = 0
		enemy.velocity.z = 0
	enemy.velocity.y = -0.5
	enemy.move_and_slide()


func _next_path_cell(start: Vector2i, goal: Vector2i) -> Vector2i:
	if start == goal:
		return start
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var previous: Dictionary = {}
	var found := false
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == goal:
			found = true
			break
		for offset in DIRECTIONS:
			var neighbor := current + offset
			if _is_walkable(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				previous[neighbor] = current
				queue.append(neighbor)
	if not found:
		return start
	var step := goal
	while previous.has(step) and previous[step] != start:
		step = previous[step]
	return step


func _show_notice(text: String, duration: float) -> void:
	notice.text = text
	notice_left = duration


func _update_hud() -> void:
	if hud == null:
		return
	hud.text = "相纸 %d/10　异常 %d/3　杏仁水 %d" % [film, evidence.size(), almond_water]
	hud_subtitle.text = "体力 %d%%　恐惧 %d%%　空格跳跃 · Tab 背包 · E 交互" % [roundi(stamina), roundi(fear)]
	fear_bar.value = fear
	if guide_label != null:
		guide_label.visible = game_started and not paused and not won and not game_over
		if pool_gate_open:
			guide_label.text = "【逃生路线】三只阀门已接通：回到湿脚印异常旁，穿过亮起的蓝色门框。"
		elif evidence.size() >= 3:
			guide_label.text = "【主线出口已开】前往地图右下方的裂墙，看到‘出口已显现’标牌后按 E。\n【其他出口】旧电梯与水门线索见 Manila Room 桌上的维修档案。"
		elif archive_read:
			guide_label.text = "【主线】拍摄三处异常（%d / 3），再去右下方裂墙。\n【旧电梯】异常编号按顺序输入 4 → 1 → 9。　【水门】依次操作刻痕 1 → 2 → 3 的阀门。" % evidence.size()
		elif note_count > 0:
			guide_label.text = "【主线】拍摄三处异常（%d / 3），再去右下方裂墙。\n【支线线索】去暖色灯光下的 Manila Room 找维修档案；异常用左键拍摄。" % evidence.size()
		else:
			guide_label.text = "【主线】用左键拍摄三处异常（%d / 3），之后前往地图右下方的裂墙按 E。\n【其他出口】沿暖色灯光找 Manila Room，桌上的维修档案会告诉你另外两条路线。" % evidence.size()
		guide_label.text += "\n" + _water_route_hint()


func _water_route_hint() -> String:
	if valve_progress >= 3:
		var gate_at := _cell_world(ANOMALY_CELLS["C"]) + Vector3(-1.3, 0, -0.7)
		return "【水门】三只阀门已接通：湿脚印和蓝色门框在%s，靠近门框按 E 进入 Level 37。" % _relative_direction_hint(gate_at)
	var expected_order: Array[int] = [1, 0, 2]
	var valve_index := expected_order[valve_progress]
	var notch := int([2, 1, 3][valve_index])
	var valve_at := _cell_world(WATER_VALVE_CELLS[valve_index])
	return "【水门】按刻痕 1 → 2 → 3 找阀门。下一个：刻痕 %d，在%s；靠近后按 E。" % [notch, _relative_direction_hint(valve_at)]


func _relative_direction_hint(target: Vector3) -> String:
	var offset := target - player.global_position
	offset.y = 0.0
	var distance := roundi(offset.length())
	if distance <= 1:
		return "就在旁边"
	var direction := offset.normalized()
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var angle := atan2(right.dot(direction), forward.dot(direction))
	var bearing := "前方"
	if angle > 2.35 or angle < -2.35:
		bearing = "身后"
	elif angle > 0.78:
		bearing = "右前方"
	elif angle > 0.25:
		bearing = "右侧"
	elif angle < -0.78:
		bearing = "左前方"
	elif angle < -0.25:
		bearing = "左侧"
	return "%s约 %d 米" % [bearing, distance]


func _cell_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - 7) * CELL, 0, (cell.y - 6) * CELL)


func _world_cell(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / CELL + 7), roundi(world.z / CELL + 6))


func _find_cell(token: String) -> Vector2i:
	for z in range(level_map.size()):
		for x in range(level_map[z].length()):
			if level_map[z].substr(x, 1) == token:
				return Vector2i(x, z)
	return Vector2i(1, 1)


func _is_walkable(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= level_map.size() or cell.x < 0 or cell.x >= level_map[cell.y].length():
		return false
	var token := level_map[cell.y].substr(cell.x, 1)
	return token != "#" and token != "=" and token != "H"
