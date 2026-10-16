extends Node3D
## A quiet architectural preview. No objectives, enemies or exit puzzle.
const WATER_Y := 0.04
const TILE_SHADER = preload("res://shaders/pool_tiles.gdshader")
var player: Node3D
var camera: Camera3D
var reflection_viewport: SubViewport
var reflection_camera: Camera3D
var water_material: ShaderMaterial
var tile_material: ShaderMaterial
var floor_material: ShaderMaterial
var trim_material: StandardMaterial3D
var metal_material: StandardMaterial3D
var ceiling_material: StandardMaterial3D
var pause_panel: Control
var intro: Control
var paused := false
var elapsed := 0.0
var rings: Array[Node3D] = []
var ambience: AudioStreamPlayer3D

func _ready() -> void:
	_materials()
	_environment()
	_architecture()
	_details()
	_player()
	_reflection()
	_ui()
	_sound()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _plain(color: String, roughness: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = roughness
	m.metallic = metal
	return m

func _tiles(color: Color, size: float = 0.18) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TILE_SHADER
	m.set_shader_parameter("tile_color", color)
	m.set_shader_parameter("tile_size", size)
	return m

func _materials() -> void:
	tile_material = _tiles(Color("e1e4cf"))
	floor_material = _tiles(Color("9ebea7"), 0.16)
	floor_material.set_shader_parameter("wetness", 0.8)
	trim_material = _plain("426d63", 0.24)
	metal_material = _plain("bac5bd", 0.2, 0.82)
	ceiling_material = _plain("b1b69a", 0.88)
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://shaders/pool_water.gdshader")

func _environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b3c7b5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4d1bb")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.12
	env.fog_enabled = true
	env.fog_light_color = Color("91b2a0")
	env.fog_light_energy = 0.35
	env.fog_density = 0.006
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-37, -63, 0)
	sun.light_color = Color("fff0ce")
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	for at in [Vector3(-9,4,4),Vector3(-9,4,-9),Vector3(-9,4,-21)]:
		var fill := OmniLight3D.new()
		fill.position = at
		fill.light_color = Color("d0e5cc")
		fill.light_energy = 0.42
		fill.omni_range = 15.0
		add_child(fill)

func _box(label: String, size: Vector3, at: Vector3, material: Material, solid: bool = true, layers: int = 1) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = at
	m.material_override = material
	m.layers = layers
	add_child(m)
	if solid:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		m.add_child(body)
	return m

func _architecture() -> void:
	_box("Submerged mosaic basin", Vector3(26,0.3,40), Vector3(0,-0.8,-6), floor_material, true, 4)
	_box("Entrance terrazzo deck", Vector3(26,0.9,6), Vector3(0,-0.3,11), tile_material)
	for x in [-11.25,11.25]:
		_box("Poolside walkway", Vector3(3.5,0.9,34), Vector3(x,-0.3,-9), tile_material)
		_box("Rounded ceramic coping", Vector3(0.22,0.12,34), Vector3(sign(x)*9.55,0.2,-9), tile_material)
		_box("Green pool border", Vector3(0.1,0.055,34), Vector3(sign(x)*9.36,0.07,-9), trim_material, false)
	_box("Ceiling", Vector3(26.5,0.28,40.5), Vector3(0,6.7,-6), ceiling_material)
	_box("Entrance wall", Vector3(26,6.8,0.4), Vector3(0,3.0,14), tile_material)
	# Tall windows admit oblique sunlight from the left. Deep reveals sell wall thickness.
	_box("Window sill wall", Vector3(0.55,3.0,40), Vector3(-13,0.85,-6), tile_material)
	_box("Window header", Vector3(0.55,0.85,40), Vector3(-13,6.15,-6), tile_material)
	var glass := _plain("dae4cb", 0.3)
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for z in [-23.5,-16.5,-9.5,-2.5,4.5,11.5]:
		_box("Window pier", Vector3(0.6,3.5,1.0), Vector3(-13,4.05,z), tile_material)
	for z in [-20.0,-13.0,-6.0,1.0,8.0]:
		var pane := _box("Frosted daylight", Vector3(0.05,3.1,5.7), Vector3(-13.4,4.08,z), glass, false)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for dz in [-1.45,1.45]:
			_box("Window mullion", Vector3(0.2,3.1,0.055), Vector3(-13.1,4.08,z+dz), tile_material, false)
	# Right wall has a dark elevated slide entrance, and a recessed tiled alcove.
	_box("Right wall", Vector3(0.4,6.8,40), Vector3(13,3.0,-6), tile_material)
	_box("Far wall left", Vector3(9.5,6.8,0.45), Vector3(-8.25,3,-26), tile_material)
	_box("Far wall right", Vector3(9.5,6.8,0.45), Vector3(8.25,3,-26), tile_material)
	_box("Far opening lintel", Vector3(7,2.2,0.45), Vector3(0,5.3,-26), tile_material)
	_box("Distant passage floor", Vector3(7,0.3,15), Vector3(0,-0.8,-33.5), floor_material, true, 4)
	for x in [-3.5,3.5]:
		_box("Distant passage walls", Vector3(0.4,5.5,15), Vector3(x,2.1,-33.5), tile_material)
	_box("Distant passage roof", Vector3(7,0.3,15), Vector3(0,4.9,-33.5), ceiling_material)
	_box("Passage shadow", Vector3(7,5.5,0.4), Vector3(0,2.1,-41), _plain("142c27",1.0))
	for z in [1.5,-10.0,-21.5]:
		for x in [-5.7,5.7]:
			_column(Vector3(x,0,z),1.35)
	# Wide shallow stairs descend naturally into the flooded hall.
	for i in range(5):
		_box("Submerged entrance step", Vector3(8.5,0.18,0.58), Vector3(0,0.06-i*0.17,7.85-i*0.55), floor_material, true, 4)
	_water(Vector2(19.0,34.0), Vector3(0,WATER_Y,-9))
	_water(Vector2(7.0,15.0), Vector3(0,WATER_Y,-33.5))

func _column(at: Vector3, radius: float) -> void:
	var column := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 7.2
	mesh.radial_segments = 80
	column.mesh = mesh
	column.position = at + Vector3(0,2.95,0)
	var m := tile_material.duplicate() as ShaderMaterial
	m.set_shader_parameter("cylinder_scale",Vector2(TAU*radius,7.2))
	column.material_override = m
	add_child(column)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 7.2
	collision.shape = shape
	body.add_child(collision)
	column.add_child(body)
	for y in [0.1,6.38]:
		var band := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = radius-0.025
		ring.outer_radius = radius+0.04
		band.mesh = ring
		band.position = at+Vector3(0,y,0)
		band.scale.y = 0.7
		band.material_override = trim_material
		add_child(band)

func _water(size: Vector2, at: Vector3) -> void:
	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	surface.mesh = plane
	surface.position = at
	surface.material_override = water_material
	surface.layers = 2
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)

func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var m := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 16
	m.mesh = cylinder
	m.position = (a+b)*0.5
	m.basis = Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	m.material_override = material
	parent.add_child(m)

func _details() -> void:
	# Linear drains, subtle depth markers and steel ladders provide human scale.
	var drain := _plain("697568",0.68,0.3)
	for x in [-9.95,9.95]:
		_box("Drain channel",Vector3(0.16,0.025,33.4),Vector3(x,0.16,-9),drain,false)
		for i in range(112):
			_box("Drain slot",Vector3(0.13,0.008,0.018),Vector3(x,0.175,7.5-i*0.295),trim_material,false)
	for z in [1.0,-17.0]:
		for dz in [-0.34,0.34]:
			var points: Array[Vector3]=[Vector3(-10.3,0.2,z+dz),Vector3(-10.3,0.95,z+dz),Vector3(-10.1,1.15,z+dz),Vector3(-9.7,1.15,z+dz),Vector3(-9.4,0.9,z+dz),Vector3(-9.35,-0.5,z+dz)]
			for i in range(points.size()-1):
				_tube(self,points[i],points[i+1],0.034,metal_material)
		for y in [-0.35,-0.05,0.25]:
			_tube(self,Vector3(-9.35,y,z-0.34),Vector3(-9.35,y,z+0.34),0.03,metal_material)
	_float_ring(Vector3(-2.4,0.14,1.3),"d4a473")
	_float_ring(Vector3(7.6,0.14,-18.0),"aaa875")
	_slide()
	_wall_text("PROFONDEUR  0.80 m",Vector3(-12.68,1.65,5.0),PI*0.5,0.004)
	_wall_text("BASSIN  37",Vector3(0,4.8,-25.72),0.0,0.012)

func _wall_text(text: String, at: Vector3, yaw: float, size: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = load("res://font.ttf")
	label.font_size = 36
	label.pixel_size = size
	label.modulate = Color("456b60")
	label.outline_size = 0
	label.position = at
	label.rotation.y = yaw
	label.no_depth_test = false
	add_child(label)

func _float_ring(at: Vector3, color: String) -> void:
	var root := Node3D.new()
	root.position = at
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.32
	mesh.outer_radius = 0.62
	mesh.rings = 48
	mesh.ring_segments = 24
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.scale.y = 0.68
	m.material_override = _plain(color,0.4)
	root.add_child(m)
	var seam := MeshInstance3D.new()
	var seam_mesh := TorusMesh.new()
	seam_mesh.inner_radius = 0.606
	seam_mesh.outer_radius = 0.615
	seam.mesh = seam_mesh
	seam.material_override = _plain("c9c1a1",0.6)
	root.add_child(seam)
	_tube(root,Vector3(0.45,0.09,0.04),Vector3(0.45,0.16,0.04),0.025,trim_material)
	add_child(root)
	rings.append(root)

func _slide() -> void:
	var shell := _plain("8daca0",0.24)
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A dark opening conceals where the flume originates.
	_box("Unlit slide recess",Vector3(0.025,2.5,2.4),Vector3(12.78,4.55,-17),_plain("102620",1.0),false)
	var controls: Array[Vector3]=[Vector3(12.6,4.3,-17),Vector3(11.4,4.1,-16.8),Vector3(10.3,3.5,-15),Vector3(9.7,2.6,-12),Vector3(9.0,1.5,-9.4),Vector3(7.9,0.65,-7.7),Vector3(6.5,0.42,-7.0)]
	var path: Array[Vector3]=[]
	for i in range(controls.size()-1):
		for j in range(12):
			path.append(controls[i].cubic_interpolate(controls[i+1],controls[maxi(0,i-1)],controls[mini(controls.size()-1,i+2)],float(j)/12.0))
	path.append(controls[-1])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(path.size()-1):
		var tangent := (path[i+1]-path[i]).normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		for j in range(24):
			var a := PI*float(j)/24.0
			var b := PI*float(j+1)/24.0
			var p0 := path[i]+(side*cos(a)-Vector3.UP*sin(a))*0.72
			var p1 := path[i]+(side*cos(b)-Vector3.UP*sin(b))*0.72
			var p2 := path[i+1]+(side*cos(a)-Vector3.UP*sin(a))*0.72
			var p3 := path[i+1]+(side*cos(b)-Vector3.UP*sin(b))*0.72
			for v in [p0,p2,p1,p1,p2,p3]:
				surface.add_vertex(v)
		for direction in [-1.0,1.0]:
			_tube(self,path[i]+side*0.72*direction,path[i+1]+side*0.72*direction,0.045,shell)
	surface.generate_normals()
	var flume := MeshInstance3D.new()
	flume.mesh = surface.commit()
	flume.material_override = shell
	add_child(flume)
	for i in [18,42,60]:
		_tube(self,Vector3(path[i].x,-0.6,path[i].z),path[i]-Vector3.UP*0.72,0.065,metal_material)

func _player() -> void:
	player = Node3D.new()
	player.position = Vector3(-3.0,0.22,10.3)
	camera = Camera3D.new()
	camera.position.y = 1.55
	camera.fov = 65.0
	camera.near = 0.07
	camera.far = 90.0
	camera.cull_mask = 7
	player.add_child(camera)
	add_child(player)
	player.rotation.y = -0.12
	camera.rotation.x = -0.045
	camera.current = true

func _reflection() -> void:
	reflection_viewport = SubViewport.new()
	reflection_viewport.size = Vector2i(800,450)
	reflection_viewport.world_3d = get_viewport().world_3d
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reflection_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(reflection_viewport)
	reflection_camera = Camera3D.new()
	reflection_camera.cull_mask = 1
	reflection_camera.far = 90.0
	reflection_viewport.add_child(reflection_camera)
	reflection_camera.current = true
	water_material.set_shader_parameter("reflection_tex",reflection_viewport.get_texture())
	_update_reflection()

func _update_reflection() -> void:
	var eye := camera.global_position
	eye.y = 2.0*WATER_Y-eye.y
	var forward := -camera.global_basis.z
	forward.y = -forward.y
	var up := camera.global_basis.y
	up.y = -up.y
	reflection_camera.global_position = eye
	reflection_camera.look_at(eye+forward,up)
	reflection_camera.fov = camera.fov
	water_material.set_shader_parameter("reflection_view",reflection_camera.global_transform.affine_inverse())
	water_material.set_shader_parameter("reflection_projection",reflection_camera.get_camera_projection())

func _ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	intro = Control.new()
	intro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(intro)
	var title := Label.new()
	title.text = "LEVEL 37  /  无尽泳池"
	title.position = Vector2(36,30)
	title.add_theme_font_size_override("font_size",21)
	title.modulate = Color("e5e7d7")
	intro.add_child(title)
	var soon := Label.new()
	soon.text = "敬请期待"
	soon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	soon.position = Vector2(-170,-65)
	soon.size = Vector2(130,32)
	soon.add_theme_font_size_override("font_size",20)
	soon.modulate = Color(0.85,0.88,0.80,0.72)
	canvas.add_child(soon)
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-150,-120)
	pause_panel.size = Vector2(300,240)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	pause_panel.add_child(column)
	var label := Label.new()
	label.text = "无尽泳池 · 敬请期待"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	for entry in [["继续观看",_resume],["返回 Level 0",_return],["退出",_quit]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(280,46)
		button.pressed.connect(entry[1])
		column.add_child(button)
	canvas.add_child(pause_panel)
	pause_panel.visible = false

func _sound() -> void:
	ambience = AudioStreamPlayer3D.new()
	var stream := load("res://audio/external/valve_running_water.wav").duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = roundi(stream.get_length()*stream.mix_rate)
	ambience.stream = stream
	ambience.position = Vector3(6,0.2,-8)
	ambience.volume_db = -26.0
	ambience.unit_size = 6.0
	ambience.max_distance = 35.0
	add_child(ambience)
	ambience.play()

func _process(delta: float) -> void:
	if paused: return
	elapsed += delta
	intro.modulate.a = clampf(1.0-(elapsed-4.0)/3.0,0.0,1.0)
	for i in range(rings.size()):
		rings[i].position.y = 0.14+sin(elapsed*0.8+float(i))*0.018
		rings[i].rotation.z = sin(elapsed*0.65+float(i))*0.024
	_update_reflection()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotation.y -= event.relative.x*0.0016
		camera.rotation.x = clampf(camera.rotation.x-event.relative.y*0.0016,-1.25,1.25)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		paused = not paused
		pause_panel.visible = paused
		ambience.stream_paused = paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED

func _resume() -> void:
	paused = false
	pause_panel.hide()
	ambience.stream_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _return() -> void:
	get_tree().change_scene_to_file("res://main.tscn")
func _quit() -> void:
	get_tree().quit()
