extends Node3D

const Geo = preload("res://desk_geometry.gd")
const DeskControls = preload("res://desk_controls.gd")
const DeskDrag = preload("res://desk_drag.gd")
const PocketGame = preload("res://pocket_game.gd")
const REQUIRED := 12
const FIRST_VISIT := 74.0
const SECOND_VISIT := 134.0
const WARNING_SECONDS := 17.0
const INSPECTION_SECONDS := 7.0
const PALETTE := ["e1b353", "638b88", "db7d69", "ddd3b4"]
const PATTERN := [Vector2i(4,3),Vector2i(5,3),Vector2i(3,4),Vector2i(6,4),Vector2i(3,5),Vector2i(6,5),Vector2i(4,6),Vector2i(5,6),Vector2i(4,4),Vector2i(5,4),Vector2i(4,5),Vector2i(5,5)]

var camera: Camera3D
var props: Dictionary = {}
var homes: Dictionary = {}
var mats: Dictionary = {}
var board: Node3D
var bead_root: Node3D
var screen: MeshInstance3D
var screen_mat: StandardMaterial3D
var drawer: Node3D
var door_light: OmniLight3D
var title_layer: Control
var result_layer: Control
var result_text: Label
var objective: Label
var hint: Label
var notice: Label
var status: Label
var cursor: Label
var meter: ProgressBar
var clock_label: Label
var hover_id := ""
var phase := "intro"
var elapsed := 0.0
var phase_clock := 0.0
var visits_passed := 0
var beads_placed := 0
var covered := false
var tool_stowed := false
var working := false
var drawer_open := false
var equipped := false
var inspecting := ""
var moving := false
var look_drag := false
var yaw := 0.0
var pitch := -0.40
var target_yaw := 0.0
var target_pitch := -0.40
var inspect_rotation := Vector3.ZERO
var target_inspect_rotation := Vector3.ZERO
var inspect_distance := 0.50
var target_inspect_distance := 0.50
var last_step := -1
var notice_time := 0.0
var motion: Tween
var auto_visual := false
var started := false
var drag: RefCounted
var pocket: Node2D
var pocket_view: SubViewport
var pocket_screen_material: StandardMaterial3D
var pocket_playing := false
var drawer_moving := false
var play_button: Button
var drawer_camera_home := Transform3D.IDENTITY
var controls_label: Label
var controls: RefCounted
var inspect_parent: Node3D
var inspect_original:=Transform3D.IDENTITY
var inspect_local:=Transform3D.IDENTITY
var tool_original:=Transform3D.IDENTITY
var tool_parent: Node3D
var inspect_quaternion:=Quaternion.IDENTITY
var action_button: Button

func _ready() -> void:
	auto_visual = "--desk-visual-check" in OS.get_cmdline_user_args()
	make_materials()
	make_room()
	make_desk()
	make_props()
	make_camera()
	drag = DeskDrag.new(self)
	controls = DeskControls.new(self)
	make_ui()
	if auto_visual:
		begin()
		set_process(false)

func make_materials() -> void:
	mats.wood = Geo.textured("res://assets/textures/ai/walnut_albedo.png", "ffffff", 1.0)
	mats.wood.metallic_specular = 0.22
	mats.wood.roughness_texture = load("res://assets/textures/ai/walnut_roughness.png")
	mats.wood.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mats.wood.normal_enabled = true
	mats.wood.normal_texture = load("res://assets/textures/ai/walnut_normal.png")
	mats.wood.normal_scale = 0.35
	mats.wood.uv1_scale = Vector3(2.14/1.2,1.28/0.8,1)
	mats.drawer_wood = mats.wood.duplicate()
	mats.drawer_wood.uv1_scale = Vector3(0.38/1.2,0.47/0.8,1)
	mats.edge = Geo.material("493323",0.57)
	mats.dark = Geo.material("252d2c",0.48)
	mats.plastic = Geo.material("c0c1ae",0.47)
	mats.key = Geo.material("d4cfb9",0.52)
	mats.paper = Geo.textured("res://assets/textures/ai/paper_albedo.png", "ffffff", 1.0)
	mats.paper.roughness_texture = load("res://assets/textures/ai/paper_roughness.png")
	mats.paper.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mats.paper.normal_enabled = true
	mats.paper.normal_texture = load("res://assets/textures/ai/paper_normal.png")
	mats.paper.normal_scale = 0.18
	mats.paper.metallic_specular = 0.12
	mats.notes = mats.paper.duplicate()
	mats.notes.albedo_texture = load("res://assets/textures/ai/notes_albedo.png")
	mats.folder = Geo.textured("res://assets/textures/ai/linen_albedo.png", "cadbd5",1.0)
	mats.folder.roughness_texture = load("res://assets/textures/ai/linen_roughness.png")
	mats.folder.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mats.folder.normal_enabled = true
	mats.folder.normal_texture = load("res://assets/textures/ai/linen_normal.png")
	mats.folder.normal_scale = 0.25
	mats.folder.metallic_specular = 0.15
	mats.folder.uv1_scale = Vector3(1.08,1.12,1)
	mats.mat_linen = mats.folder.duplicate()
	mats.mat_linen.uv1_scale = Vector3(3.17,0.77,1)
	mats.brass = Geo.material("bca069",0.28,0.76)
	mats.steel = Geo.material("b0bdbb",0.23,0.87)
	mats.ceramic = Geo.material("cbbea0",0.31)
	mats.board = Geo.material("d6cdb2",0.56)
	mats.coffee = Geo.material("302017",0.21)
	mats.orange = Geo.material("db9d51",0.4)
	for i in range(4):mats["bead"+str(i)] = Geo.material(PALETTE[i],0.29)

func make_room() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("162124")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("7b9395")
	e.ambient_light_energy = 0.48
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		e.ssao_enabled=true
		e.ssao_radius=.13
		e.ssao_intensity=.85
		e.ssao_power=1.2
		e.ssao_light_affect=.12
		e.ssr_enabled=true
		e.ssr_max_steps=32
		e.ssr_fade_in=.2
		e.ssr_fade_out=2.0
		e.glow_enabled=true
		e.glow_intensity=.22
		e.glow_hdr_threshold=1.15
		e.glow_bloom=.03
	env.environment = e
	add_child(env)
	Geo.box(self,Vector3(6,0.08,6),Vector3(0,-0.05,0),Geo.material("2b3230"))
	Geo.box(self,Vector3(5,3,0.1),Vector3(0,1.4,-1.37),Geo.material("36413e",0.96))
	Geo.box(self,Vector3(5,0.07,0.04),Vector3(0,0.18,-1.3),mats.edge)
	# Softly lit corkboard and a few original, unlabelled material samples.
	Geo.box(self,Vector3(1.04,0.58,0.045),Vector3(-0.25,1.42,-1.28),mats.edge)
	Geo.box(self,Vector3(0.99,0.53,0.012),Vector3(-0.25,1.42,-1.247),Geo.material("746753"))
	for i in range(5):
		var p := Geo.box(self,Vector3(0.115,0.13,0.002),Vector3(-0.63+i*0.173,1.44+sin(i*2.0)*0.06,-1.232),Geo.material(["d0bd91","92a092","ccbea3","648484","b4a78c"][i]),0)
		p.rotation.z = sin(i)*0.08
		Geo.sphere(self,0.005,p.position+Vector3(0,0.053,0.008),mats.brass)
	# Door and a light gap signal the visit without needing a character placeholder.
	Geo.box(self,Vector3(0.7,1.98,0.06),Vector3(1.65,0.97,-1.285),Geo.material("242e2b"))
	Geo.rod(self,Vector3(1.86,1.00,-1.235),Vector3(1.92,1.00,-1.235),0.012,mats.brass)
	door_light = OmniLight3D.new()
	door_light.position = Vector3(1.65,0.14,-1.15)
	door_light.light_color = Color("ffcd83")
	door_light.light_energy = 0
	door_light.omni_range = 1.7
	add_child(door_light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.4,1.8,0.5)
	fill.light_color = Color("b5d0d7")
	fill.light_energy = 0.30
	fill.omni_range = 3.5
	add_child(fill)
	# One local low-resolution capture supplies room reflections to glass and metal.
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		var reflection:=ReflectionProbe.new()
		reflection.position=Vector3(0,1.1,0)
		reflection.size=Vector3(3.6,2.6,3.3)
		reflection.origin_offset=Vector3(0,.2,0)
		reflection.box_projection=true
		reflection.interior=true
		reflection.intensity=.45
		reflection.update_mode=ReflectionProbe.UPDATE_ONCE
		add_child(reflection)
	var bounce:=OmniLight3D.new()
	bounce.position=Vector3(.78,.78,1.07)
	bounce.light_color=Color("d6b487")
	bounce.light_energy=.14
	bounce.omni_range=.68
	add_child(bounce)

func make_desk() -> void:
	Geo.box(self,Vector3(2.14,0.065,1.28),Vector3(0,0.73,-0.01),mats.wood,0.013)
	Geo.box(self,Vector3(2.05,0.028,1.2),Vector3(0,0.687,-0.01),mats.edge,0.008)
	for x in [-0.94,0.94]:
		for z in [-0.48,0.47]:Geo.box(self,Vector3(0.065,0.69,0.065),Vector3(x,0.335,z),mats.edge,0.007)
	# Drawer carcass below the right of the tabletop.
	for x in [0.543,0.957]:Geo.box(self,Vector3(0.024,0.28,0.64),Vector3(x,0.555,0.23),mats.edge,0.005)
	Geo.box(self,Vector3(0.42,0.025,0.64),Vector3(0.75,0.423,0.23),mats.edge,0.005)
	Geo.box(self,Vector3(0.42,0.28,0.025),Vector3(0.75,0.555,-0.083),mats.edge,0.005)
	drawer = Node3D.new()
	drawer.position = Vector3(0.75,0.61,0.34)
	add_child(drawer)
	Geo.box(drawer,Vector3(0.38,0.015,0.47),Vector3(0,-0.056,0),mats.drawer_wood)
	Geo.box(drawer,Vector3(0.4,0.12,0.025),Vector3(0,0,0.24),mats.drawer_wood,0.006)
	for x in [-0.186,0.186]:Geo.box(drawer,Vector3(0.015,0.095,0.46),Vector3(x,-0.003,0),mats.edge)
	Geo.rod(drawer,Vector3(-0.07,0.0,0.28),Vector3(0.07,0.0,0.28),0.009,mats.brass)
	Geo.rod(drawer,Vector3(-0.07,0.0,0.25),Vector3(-0.07,0.0,0.28),0.008,mats.brass)
	Geo.rod(drawer,Vector3(0.07,0.0,0.25),Vector3(0.07,0.0,0.28),0.008,mats.brass)
	Geo.hit(drawer,"drawer",Vector3(0.43,0.18,0.08),Vector3(0,0,0.27))
	# Woven mat is independent geometry; it does not replace the tabletop.
	Geo.box(self,Vector3(0.95,0.003,0.23),Vector3(-0.21,0.765,-0.04),mats.mat_linen,0.0005)

func prop(id: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = id
	n.position = pos
	add_child(n)
	props[id] = n
	return n

func make_props() -> void:
	var computer := prop("computer",Vector3(-0.26,0.7635,-0.46))
	Geo.box(computer,Vector3(0.3,0.025,0.19),Vector3(0,0.012,0.035),mats.dark,0.008)
	Geo.box(computer,Vector3(0.049,0.23,0.04),Vector3(0,0.13,-0.019),mats.dark,0.007)
	Geo.box(computer,Vector3(0.655,0.404,0.047),Vector3(0,0.347,0),mats.dark,0.012)
	Geo.box(computer,Vector3(0.619,0.358,0.004),Vector3(0,0.355,0.027),Geo.material("101919"),0.001)
	screen_mat = Geo.textured("res://assets/textures/screen_break.png")
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(0.602,0.376)
	screen = Geo.mesh(computer,q,Vector3(0,0.355,0.031),screen_mat)
	Geo.sphere(computer,0.0028,Vector3(0.29,0.171,0.028),Geo.material("90bc98"))
	Geo.hit(computer,"computer",Vector3(0.67,0.42,0.09),Vector3(0,0.35,0))
	Geo.label(computer,"栖岸",Vector3(0,0.16,0.033),11,Color("9da89a"))
	var keyboard := prop("keyboard",Vector3(-0.29,0.776,-0.063))
	Geo.box(keyboard,Vector3(0.49,0.019,0.16),Vector3.ZERO,mats.plastic,0.008)
	for row in range(5):
		for col in range(14):
			if row==4 and col>3 and col<10:continue
			var key := Geo.box(keyboard,Vector3(0.026,0.008,0.021),Vector3(-0.218+col*0.033,0.014,-0.061+row*0.028),mats.key,0.0015)
			if row<4 and col<13:
				var l := Geo.label(keyboard, char(65+(col+row*7)%26),key.position+Vector3(0,0.005,0),8,Color("696e5e"))
				l.rotation.x=-PI/2
	Geo.box(keyboard,Vector3(0.19,0.008,0.021),Vector3(0.013,0.014,0.051),mats.key,0.002)
	var mouse := prop("mouse",Vector3(0.12,0.783,-0.09))
	var mouse_body := Geo.sphere(mouse,0.038,Vector3.ZERO,mats.plastic)
	mouse_body.scale = Vector3(0.78,0.42,1.2)
	Geo.box(mouse,Vector3(0.002,0.002,0.03),Vector3(0,0.015,-0.017),mats.dark,0)
	Geo.box(mouse,Vector3(0.005,0.004,0.011),Vector3(0,0.017,-0.016),mats.dark,0.001)
	make_lamp()
	board = prop("board",Vector3(0.06,0.7655,0.267))
	board.rotation.y = -0.08
	Geo.box(board,Vector3(0.256,0.006,0.256),Vector3.ZERO,mats.board,0.005)
	for row in range(10):
		for col in range(10):Geo.cylinder(board,0.0014,0.008,Vector3(-0.108+col*0.024,0.007,-0.108+row*0.024),mats.board)
	Geo.hit(board,"board",Vector3(0.27,0.02,0.27))
	bead_root = Node3D.new()
	board.add_child(bead_root)
	# Faint target rings make the next bead location visible without overlay arrows.
	for cell in PATTERN:Geo.torus(board,0.004,0.005,Vector3(-0.108+cell.x*0.024,0.0038,-0.108+cell.y*0.024),Geo.material("948b74"))
	var folder := prop("folder",Vector3(-0.54,0.7655,0.25))
	folder.rotation.y = 0.14
	Geo.box(folder,Vector3(0.324,0.003,0.33),Vector3(0,-0.001,0),mats.folder,0.0005)
	Geo.box(folder,Vector3(0.306,0.012,0.31),Vector3(0,0.006,0.003),mats.paper,0.001)
	Geo.box(folder,Vector3(0.327,0.003,0.336),Vector3(0,0.014,0),mats.folder,0.0005)
	Geo.box(folder,Vector3(0.023,0.017,0.33),Vector3(-0.155,0.006,0),mats.folder,0.001)
	Geo.box(folder,Vector3(0.06,0.001,0.028),Vector3(0.10,0.016,-0.104),mats.paper,0)
	Geo.box(folder,Vector3(0.073,0.003,0.029),Vector3(0.106,0.010,-0.177),mats.folder,0.0005)
	var fl := Geo.label(folder,"样本 / 06",Vector3(0.10,0.0168,-0.104),10,Color("42524d"))
	fl.rotation.x=-PI/2
	Geo.hit(folder,"folder",Vector3(0.34,0.034,0.36))
	var notes := prop("notes",Vector3(-0.74,0.763,-0.036))
	notes.rotation.y = -0.12
	for i in range(5):Geo.box(notes,Vector3(0.205,0.0008,0.27),Vector3(i*0.001,0.0008*i,i*0.001),mats.paper,0)
	Geo.box(notes,Vector3(0.205,0.0009,0.27),Vector3(0,0.0045,0),mats.notes,0)
	Geo.hit(notes,"notes",Vector3(0.21,0.03,0.28))
	var clip := Geo.torus(notes,0.008,0.009,Vector3(0.058,0.009,-0.114),mats.steel)
	clip.scale=Vector3(0.5,0.6,1.4)
	var tools := prop("tools",Vector3(0.342,0.7645,0.281))
	tools.rotation.y = -0.38
	for side in [-1,1]:
		var strip := Geo.box(tools,Vector3(0.008,0.003,0.135),Vector3(side*0.007,0,0),mats.steel,0.001)
		strip.rotation.y=side*0.068
		Geo.rod(tools,Vector3(side*0.011,0,-0.060),Vector3(side*0.002,0,-0.079),0.0017,mats.steel)
	Geo.box(tools,Vector3(0.015,0.003,0.012),Vector3(0,0,0.063),mats.steel,0.001)
	for i in range(8):
		for side in [-1,1]:Geo.box(tools,Vector3(0.009,0.0009,0.001),Vector3(side*0.008,0.0018,0.007+i*0.004),mats.dark,0)
	Geo.hit(tools,"tools",Vector3(0.072,0.045,0.19))
	var tray := prop("tray",Vector3(0.40,0.767,0.082))
	Geo.box(tray,Vector3(0.211,0.009,0.107),Vector3.ZERO,mats.plastic,0.005)
	for i in range(5):Geo.box(tray,Vector3(0.003,0.022,0.101),Vector3(-0.103+i*0.052,0.008,0),mats.plastic,0.001)
	for z in [-0.052,0.052]:Geo.box(tray,Vector3(0.213,0.022,0.003),Vector3(0,0.008,z),mats.plastic,0.001)
	for i in range(4):
		for j in range(9):
			var bead := Geo.tube(tray,0.006,0.0026,0.010,Vector3(-0.078+i*0.052+(j%3-1)*0.012,0.007+(j/3)*0.004,-0.03+(j/3)*0.024),mats["bead"+str(i)])
			bead.rotation = Vector3(sin(j*3+i)*0.35,0,cos(j+i)*0.35)
	Geo.hit(tray,"tray",Vector3(0.23,0.05,0.12))
	make_mug()
	make_handheld()
	# A pencil, eraser, sticky notes, wiring and two books add restrained lived-in detail.
	var pencil := prop("pencil",Vector3(-0.50,0.771,-0.09))
	Geo.rod(pencil,Vector3(-0.06,0,-0.01),Vector3(0.08,0,0.03),0.004,mats.orange)
	Geo.rod(pencil,Vector3(0.08,0,0.03),Vector3(0.10,0,0.036),0.003,Geo.material("bea278"))
	Geo.sphere(pencil,0.002,Vector3(0.101,0,0.036),mats.dark)
	Geo.box(self,Vector3(0.04,0.013,0.021),Vector3(-0.48,0.769,-0.14),Geo.material("bba991"))
	for i in range(3):
		var sticky := Geo.box(self,Vector3(0.07,0.001,0.07),Vector3(-0.83+i*0.056,0.77,-0.385+i*0.018),Geo.material(["beaf76","a3b3a1","c0a27d"][i]),0)
		sticky.rotation.y = i*0.22
	for i in range(2):
		var cover_mat := Geo.material(["415958","9a7950"][i])
		var yy := 0.781+i*0.037
		for dy in [-0.016,0.016]:Geo.box(self,Vector3(0.25,0.004,0.17),Vector3(0.38,yy+dy,-0.47),cover_mat,0.0007)
		Geo.box(self,Vector3(0.008,0.035,0.17),Vector3(0.501,yy,-0.47),cover_mat,0.001)
		Geo.box(self,Vector3(0.238,0.028,0.162),Vector3(0.377,yy,-0.466),mats.paper,0.0007)
	for i in range(20):
		var a:=Vector3(-0.24+sin(i*0.16)*0.025,0.776,-0.53-i*0.018)
		var b:=Vector3(-0.24+sin((i+1)*0.16)*0.025,0.776,-0.53-(i+1)*0.018)
		Geo.rod(self,a,b,0.003,mats.dark)
	for id in props:homes[id]=props[id].transform

func make_lamp() -> void:
	var lamp := prop("lamp",Vector3(0.76,0.763,-0.30))
	Geo.cylinder(lamp,0.093,0.014,Vector3(0,0.007,0),mats.dark)
	Geo.cylinder(lamp,0.086,0.011,Vector3(0,0.02,0),mats.brass)
	Geo.torus(lamp,0.061,0.064,Vector3(0,0.027,0),mats.brass)
	Geo.rod(lamp,Vector3(0,0.027,0),Vector3(0.023,0.22,-0.025),0.01,mats.brass)
	Geo.sphere(lamp,0.024,Vector3(0.023,0.22,-0.025),mats.brass)
	Geo.rod(lamp,Vector3(0.023,0.22,-0.025),Vector3(-0.105,0.43,0.04),0.009,mats.brass)
	Geo.sphere(lamp,0.016,Vector3(-0.105,0.43,0.04),mats.brass)
	var shade := Node3D.new()
	shade.position=Vector3(-0.112,0.428,0.065)
	shade.rotation.z=-0.25
	lamp.add_child(shade)
	# Open tapered shade with a warm inner reflector.
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inside:=SurfaceTool.new()
	inside.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(64):
		var a:=float(i)/64*TAU
		var b:=float(i+1)/64*TAU
		var p:=Vector3(cos(a)*0.108,-0.05,sin(a)*0.108)
		var q:=Vector3(cos(b)*0.108,-0.05,sin(b)*0.108)
		var r:=Vector3(cos(a)*0.046,0.045,sin(a)*0.046)
		var s:=Vector3(cos(b)*0.046,0.045,sin(b)*0.046)
		Geo.tri(st,p,r,s,Vector3.ONE);Geo.tri(st,p,s,q,Vector3.ONE)
		var ip:=p*Vector3(.985,1,.985)
		var iq:=q*Vector3(.985,1,.985)
		var ir:=r*Vector3(.985,1,.985)
		var ins:=s*Vector3(.985,1,.985)
		Geo.tri(inside,ip,ins,ir,Vector3.ONE);Geo.tri(inside,ip,iq,ins,Vector3.ONE)
	var green:=Geo.material("526e5c",0.33,0.28)
	Geo.mesh(shade,st.commit(),Vector3.ZERO,green)
	Geo.mesh(shade,inside.commit(),Vector3.ZERO,Geo.material("d7c9a7",0.48))
	Geo.torus(shade,0.105,0.110,Vector3(0,-0.05,0),mats.brass)
	var bulb:=Geo.material("ffdeb0",0.4)
	bulb.emission_enabled=true
	bulb.emission=Color("ffc989")
	bulb.emission_energy_multiplier=1.4
	Geo.sphere(shade,0.026,Vector3(0,-0.022,0),bulb)
	var light:=SpotLight3D.new()
	light.position=lamp.position+shade.position+Vector3(0,-0.045,0)
	add_child(light)
	light.look_at(Vector3(0.35,0.76,0.14),Vector3.FORWARD)
	light.light_color=Color("ffd49c")
	light.light_energy=1.15
	light.spot_range=2.4
	light.spot_angle=66
	light.spot_angle_attenuation=0.7
	light.shadow_enabled=true
	light.shadow_bias=0.012
	light.shadow_normal_bias=0.018
	light.shadow_blur=1.4
	light.light_size=0.055
	var glow:=OmniLight3D.new()
	glow.position=light.position
	glow.light_color=light.light_color
	glow.light_energy=0.16
	glow.omni_range=0.7
	add_child(glow)

func make_mug() -> void:
	var mug:=prop("mug",Vector3(-0.81,0.763,-0.287))
	Geo.tube(mug,0.044,0.038,0.094,Vector3.ZERO,mats.ceramic)
	Geo.cylinder(mug,0.043,0.006,Vector3(0,0.003,0),mats.ceramic)
	Geo.torus(mug,0.037,0.044,Vector3(0,0.093,0),mats.ceramic)
	Geo.cylinder(mug,0.037,0.001,Vector3(0,0.073,0),mats.coffee)
	var handle:=Geo.torus(mug,0.021,0.029,Vector3(-0.05,0.047,0),mats.ceramic)
	handle.rotation.x=PI/2
	Geo.hit(mug,"mug",Vector3(0.13,0.11,0.10),Vector3(-0.014,0.05,0))

func make_camera() -> void:
	camera=Camera3D.new()
	camera.position=Vector3(0,1.265,1.27)
	camera.rotation=Vector3(pitch,0,0)
	camera.fov=54
	camera.near=0.035
	camera.far=15
	add_child(camera)
	camera.make_current()

func text_label(parent: Node, text: String, pos: Vector2, font_size: int, color: String = "e8dfc7") -> Label:
	var l:=Label.new()
	l.text=text
	l.position=pos
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",Color(color))
	l.add_theme_color_override("font_shadow_color",Color(0.02,0.03,0.025,0.8))
	l.add_theme_constant_override("shadow_offset_x",1)
	l.add_theme_constant_override("shadow_offset_y",2)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func panel_style() -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=Color(0.045,0.08,0.078,0.94)
	s.border_color=Color("63786d")
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	return s

func make_ui() -> void:
	var layer:=CanvasLayer.new()
	add_child(layer)
	var hud:=Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	text_label(hud,"真的在干了",Vector2(26,23),23)
	text_label(hud,"栖岸设计  /  周五 15:47",Vector2(28,55),12,"a9b9aa")
	clock_label=text_label(hud,"",Vector2(1100,33),16)
	status=text_label(hud,"",Vector2(28,81),13,"c2cbb9")
	objective=text_label(hud,"",Vector2(28,690),18)
	hint=text_label(hud,"",Vector2(28,722),15,"d0ccb6")
	controls_label=text_label(hud,"鼠标环顾 · 滚轮靠近 / 远离 · 左键查看 / 开关 · 右键拖物件 / 近看短按放回",Vector2(36,766),13,"99aca0")
	notice=text_label(hud,"",Vector2(28,110),15,"e8ba78")
	meter=ProgressBar.new()
	meter.position=Vector2(28,660)
	meter.custom_minimum_size=Vector2(224,4)
	meter.size=Vector2(224,4)
	meter.max_value=REQUIRED
	meter.show_percentage=false
	meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var bg:=StyleBoxFlat.new();bg.bg_color=Color("34463f");bg.set_corner_radius_all(2)
	var fg:=StyleBoxFlat.new();fg.bg_color=Color("d2b077");fg.set_corner_radius_all(2)
	for s in [bg,fg]:
		s.content_margin_top=0;s.content_margin_bottom=0;s.content_margin_left=0;s.content_margin_right=0
	meter.add_theme_stylebox_override("background",bg)
	meter.add_theme_stylebox_override("fill",fg)
	hud.add_child(meter)
	cursor=text_label(hud,"·",Vector2.ZERO,28,"e8d3a2")
	title_layer=Control.new()
	title_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(title_layer)
	var p:=Panel.new()
	p.position=Vector2(50,156)
	p.size=Vector2(442,447)
	p.add_theme_stylebox_override("panel",panel_style())
	title_layer.add_child(p)
	text_label(p,"一首歌的空隙",Vector2(27,23),29)
	text_label(p,"先给自己一点点时间。",Vector2(29,73),18,"b9c7b6")
	text_label(p,"任务一：查看镊子拿好，查看板子放 12 颗。\n任务二：掌机跑到灯塔（约 35–45 秒）。\n首轮脚步在 01:14，再给 17 秒收拾。\n\n① 右键拖文件夹盖够拼豆板\n② 左键开抽屉，右键拖掌机和镊子入内\n③ 放稳后关抽屉，电脑切回工作页面\n\n两次检查通过，两个任务完成即可胜利。",Vector2(29,117),16)
	text_label(p,"鼠标自然环顾，滚轮靠近 / 远离。\n左键查看；近看右键按住转动，短按放回。",Vector2(29,329),14,"a9b9aa")
	var b:=Button.new()
	b.text="开始这五分钟"
	b.position=Vector2(27,384)
	b.size=Vector2(386,42)
	b.add_theme_font_size_override("font_size",19)
	b.pressed.connect(begin)
	p.add_child(b)
	result_layer=Control.new()
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(result_layer)
	var rp:=Panel.new()
	rp.position=Vector2(410,257)
	rp.size=Vector2(470,280)
	rp.add_theme_stylebox_override("panel",panel_style())
	result_layer.add_child(rp)
	result_text=text_label(rp,"",Vector2(27,26),22)
	var retry:=Button.new()
	retry.text="再借五分钟 · 重新开始"
	retry.position=Vector2(27,207)
	retry.size=Vector2(416,42)
	retry.pressed.connect(reset_game)
	rp.add_child(retry)
	result_layer.hide()
	play_button=Button.new()
	play_button.focus_mode=Control.FOCUS_NONE
	play_button.text="进入掌机屏幕"
	play_button.position=Vector2(1040,704)
	play_button.size=Vector2(210,38)
	play_button.pressed.connect(start_pocket)
	hud.add_child(play_button)
	action_button=Button.new()
	action_button.focus_mode=Control.FOCUS_NONE
	action_button.position=Vector2(1020,700);action_button.size=Vector2(230,42)
	action_button.pressed.connect(func():
		if inspecting=="tools":equip_tool()
		elif inspecting=="board":place_bead()
	)
	hud.add_child(action_button)
	update_hud()

func begin() -> void:
	title_layer.hide()
	controls.focused=true
	if started:
		phase=get_meta("resume_phase","free")
		return
	started=true
	phase="free"
	toast("任务一：12 颗拼豆。任务二：点掌机近看，再点屏幕玩到灯塔。",6)
	update_hud()

func _process(delta: float) -> void:
	if not started:return
	if phase in ["won","lost","paused"]:
		if drag.settling:drag.tick(delta)
		return
	controls.tick(delta)
	if not inspecting.is_empty() and not moving:
		inspect_quaternion=inspect_quaternion.slerp(Basis.from_euler(target_inspect_rotation).get_rotation_quaternion(),1-exp(-delta*32))
		inspect_distance=lerpf(inspect_distance,target_inspect_distance,1-exp(-delta*28))
		var n:Node3D=props[inspecting]
		n.global_position=inspection_position()
		n.global_basis=camera.global_basis*Basis(inspect_quaternion)
	elif equipped and not moving and drag.id.is_empty():
		props.tools.global_position=camera.to_global(Vector3(0.19,-0.15,-0.40))
		props.tools.global_basis=camera.global_basis*Basis.from_euler(Vector3(0.35,-0.5,-0.25))
	drag.tick(delta)
	covered=drag.cover_ratio()>=.97
	tool_stowed=drag.stowed("tools")
	pocket.set_active(pocket_playing and phase in ["free","warning"] and inspecting=="handheld" and not moving)
	elapsed+=delta
	if notice_time>0:
		notice_time-=delta
		if notice_time<=0:notice.text=""
	if phase=="free":
		var next_visit:float=FIRST_VISIT if visits_passed==0 else SECOND_VISIT
		if visits_passed<2 and elapsed>=next_visit:begin_warning()
		elif visits_passed==2 and beads_placed>=REQUIRED and pocket.won:finish(true)
	elif phase=="warning":
		phase_clock+=delta
		var step:=int(phase_clock/(1.5 if phase_clock<9 else 0.75))
		if step!=last_step:
			last_step=step
			play_sound("footstep",-15 if phase_clock<9 else -9)
		door_light.light_energy=0.35+phase_clock/WARNING_SECONDS*0.8
		if phase_clock>=WARNING_SECONDS:begin_check()
	elif phase=="checking":
		phase_clock+=delta
		if not is_safe():finish(false)
		elif phase_clock>=INSPECTION_SECONDS:
			visits_passed+=1
			phase="free"
			door_light.light_energy=0
			play_sound("complete",-14)
			toast("脚步远了。右键移开文件夹，左键开抽屉后拖出物件。",6)
	hover_id=pick_id(get_viewport().get_mouse_position())
	cursor.position=get_viewport().get_mouse_position()+Vector2(-4,-15)
	cursor.visible=not hover_id.is_empty() and not title_layer.visible
	update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if pocket_playing:
			if event.pressed and event.keycode==KEY_ESCAPE:stop_pocket();return
			if event.pressed and not event.echo and event.keycode==KEY_Q:return_item();return
			pocket.key_input(event);return
		if event.pressed and not event.echo:
			if event.keycode==KEY_R and phase in ["won","lost"]:reset_game();return
			if event.keycode in [KEY_ESCAPE,KEY_TAB]:
				if not started or phase in ["won","lost"]:return
				if title_layer.visible:title_layer.hide();phase=get_meta("resume_phase","free");controls.focused=true
				else:controls.release_inputs(true)
				return
			if phase in ["intro","won","lost","paused"]:return
			if event.keycode==KEY_Q:return_item();return
			if event.keycode==KEY_SPACE and inspecting=="board" and equipped and not moving:place_bead();return
	if phase in ["intro","won","lost","paused","checking"]:return
	if event is InputEventMouseMotion:controls.motion(event);return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:
			if event.pressed:controls.right_press(event.position)
			else:controls.right_release(event.position)
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			controls.wheel(1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1);return
		if event.button_index==MOUSE_BUTTON_LEFT:
			if pocket_playing:
				var uv=screen_pointer(event.position)
				if uv!=null:pocket.pointer(uv,event.pressed)
				return
			if event.pressed and not moving and drag.id.is_empty():
				if inspecting=="handheld" and screen_pointer(event.position)!=null:start_pocket()
				elif inspecting.is_empty():interact(pick_id(event.position))

func pick_id(mouse: Vector2) -> String:
	var origin:=camera.project_ray_origin(mouse)
	var query:=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(mouse)*4,2)
	query.collide_with_areas=true
	query.collide_with_bodies=false
	var result:=get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():return ""
	var id:String=result.collider.get_meta("id","")
	if id=="board" and covered:return "folder"
	if id in ["tools","handheld"] and props[id].get_parent()==drawer and not drawer_open:return "drawer"
	return id

func interact(id: String) -> void:
	if pocket_playing or not drag.id.is_empty() or drawer_moving:return
	if moving or phase not in ["free","warning"]:return
	match id:
		"tools","board","folder":inspect_item(id)
		"drawer":use_drawer()
		"computer":
			working=not working
			screen_mat.albedo_texture=load("res://assets/textures/screen_work.png" if working else "res://assets/textures/screen_break.png")
			play_sound("place",-19)
			toast("工作核对表已打开。" if working else "音乐页面已打开。",2)
		"mug","notes","tray","handheld":inspect_item(id)

func inspect_item(id: String) -> void:
	if moving or not inspecting.is_empty() or id not in ["mug","notes","tray","folder","board","tools","handheld"] or phase=="checking":return
	if covered and id=="board":toast("右键拖开文件夹，再看板子。",2);return
	if not drag.id.is_empty() or drawer_moving:return
	var n:Node3D=props[id]
	if n.get_parent()==drawer and not drawer_open:return
	controls.freeze_camera()
	inspect_parent=n.get_parent();inspect_local=n.transform;inspect_original=n.global_transform
	if n.get_parent()!=self:n.reparent(self,true)
	inspecting=id
	target_inspect_rotation=Vector3(1.15,0,0) if id in ["board","folder","tray","notes","tools","handheld"] else Vector3.ZERO
	inspect_quaternion=Basis.from_euler(target_inspect_rotation).get_rotation_quaternion()
	var end:=Transform3D(camera.global_basis*Basis(inspect_quaternion),inspection_position())
	move_item(n,end,.42,.14,func():toast("点屏幕开始 · 右键短按放回" if id=="handheld" else "右键按住转动 · 短按放回",3);update_hud())

func inspection_position() -> Vector3:
	var pos:=camera.to_global(Vector3(0,-0.015,-inspect_distance))
	# Fixed desk camera: keep the largest rotatable prop clear of the wood at all angles.
	pos.y=maxf(pos.y,1.02)
	return pos

func return_item() -> void:
	if moving or not drag.id.is_empty():return
	stop_pocket()
	if not inspecting.is_empty():
		var id:=inspecting
		var end:=inspect_parent.global_transform*inspect_local if is_instance_valid(inspect_parent) else inspect_original
		if inspect_parent==drawer and (not drawer_open or not drag.fits(id,end) or drag.overlaps_stored(id,end)):
			toast("抽屉原位没有空位。先保持打开再放回。",3);return
		inspecting=""
		var parent:=inspect_parent
		move_item(props[id],end,.38,.10,func():
			if is_instance_valid(parent) and props[id].get_parent()!=parent:props[id].reparent(parent,true)
			controls.rebase();play_sound("place");update_hud()
		)
	elif equipped:
		equipped=false
		var parent:=tool_parent
		var end:Transform3D=parent.global_transform*tool_original if is_instance_valid(parent) else global_transform*homes.tools
		move_item(props.tools,end,.38,.10,func():
			if is_instance_valid(parent) and props.tools.get_parent()!=parent:props.tools.reparent(parent,true)
			controls.rebase();play_sound("place")
		)

func equip_tool() -> void:
	if moving or inspecting!="tools":return
	tool_parent=inspect_parent;tool_original=inspect_local
	inspecting="";equipped=true
	tool_stowed=false
	var end:=Transform3D(camera.global_basis*Basis.from_euler(Vector3(.35,-.5,-.25)),camera.to_global(Vector3(.19,-.15,-.40)))
	move_item(props.tools,end,.24,.025,func():toast("镊子已拿好。点板查看，再点“放一颗”或空格。",4);update_hud())

func move_item(n: Node3D, end: Transform3D, duration: float, lift: float, done: Callable) -> void:
	moving=true
	var start:=n.global_transform
	if motion and motion.is_running():motion.kill()
	motion=create_tween()
	motion.tween_method(func(t: float):
		# One smooth lifted path; height is never below either endpoint.
		var smooth:=t*t*(3-2*t)
		var pos:=start.origin.lerp(end.origin,smooth)
		pos.y+=sin(PI*t)*lift
		var basis:=Basis(start.basis.get_rotation_quaternion().slerp(end.basis.get_rotation_quaternion(),smooth))
		n.global_transform=Transform3D(basis,pos)
	,0.0,1.0,duration)
	motion.tween_callback(func():
		n.global_transform=end
		moving=false
		done.call()
	)

func place_bead() -> void:
	if moving or inspecting!="board":return
	if drag.cover_ratio()>=.97:toast("右键拖开文件夹再继续。",2);return
	if not equipped:toast("先查看镊子，点“拿镊子拼豆”，再查看板子。",3);return
	if beads_placed>=REQUIRED:toast("小图案完成了，留意门外动静。",3);return
	# The small tip approaches the target; the bead release event is independent of its mesh.
	var cell:Vector2i=PATTERN[beads_placed]
	var bead:=Geo.tube(bead_root,0.0062,0.0026,0.012,Vector3.ZERO,mats["bead"+str(beads_placed%4)])
	var end:=board.to_global(Vector3(-0.108+cell.x*0.024,0.004,-0.108+cell.y*0.024))
	bead.global_position=props.tools.to_global(Vector3(0,0,-0.07))
	move_item(bead,Transform3D(board.global_basis,end),0.27,0.07,func():
		bead.transform=Transform3D(Basis.IDENTITY,Vector3(-0.108+cell.x*.024,.004,-0.108+cell.y*.024))
		beads_placed+=1
		play_sound("place",-14)
		if beads_placed==6:toast("一半了。门外有动静时，先把摸鱼现场藏好。",4)
		if beads_placed==REQUIRED:toast("拼豆完成。再通过两次检查，就能带走这点好心情。",5)
	)

func toggle_cover() -> void:
	toast("按住右键抓文件夹，拖到拼豆板上再松开；左键只近看。",4)

func use_drawer() -> void:
	if drawer_moving or moving or not drag.id.is_empty() or phase not in ["free","warning"]:return
	if drawer_open and not drag.can_close():toast("物件还没放稳，抽屉不能关。",3);return
	stop_pocket()
	drawer_moving=true
	var opening:=not drawer_open
	controls.freeze_camera()
	if opening:
		drawer_camera_home=camera.transform
	var camera_start:=camera.transform
	var camera_end:=drawer_camera_home
	if opening:
		var pose:=Transform3D(Basis.IDENTITY,Vector3(.12,1.45,1.65))
		camera_end=pose.looking_at(Vector3(.72,.63,.79),Vector3.UP)
	play_sound("drawer",-15)
	var t:=create_tween()
	t.tween_property(drawer,"position:z",.82 if opening else .34,.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_method(func(v: float):
		var smooth:=v*v*(3-2*v)
		camera.transform=camera_start.interpolate_with(camera_end,smooth)
		yaw=camera.rotation.y;pitch=camera.rotation.x
		target_yaw=yaw;target_pitch=pitch
	,.0,1.0,.55)
	t.tween_callback(func():drawer_open=opening;drawer_moving=false;controls.rebase();toast("右键拖掌机和镊子到抽屉内腔空位，松开后左键关上。" if opening else "抽屉已关上。",3);update_hud())

func move_lower(n: Node3D, end: Transform3D, done: Callable) -> void:
	moving=true
	var t:=create_tween()
	t.tween_property(n,"global_position",end.origin,0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(n,"quaternion",end.basis.get_rotation_quaternion(),0.20)
	t.tween_callback(done)

func begin_warning() -> void:
	phase="warning"
	phase_clock=0
	last_step=-1
	toast("门外：皮鞋声由远到近。17 秒后老板会推门。",7)
	play_sound("footstep",-15)

func is_safe() -> bool:
	return drag.cover_ratio()>=.97 and drag.stowed("tools") and drag.stowed("handheld") and pocket.won and not drawer_open and not drawer_moving and working and inspecting.is_empty() and not moving and drag.id.is_empty()

func begin_check() -> void:
	stop_pocket()
	phase="checking"
	phase_clock=0
	if not is_safe():finish(false);return
	toast("门开了。老板：『嗯，核对完发给我。』",7)
	door_light.light_energy=1.25

func finish(success: bool) -> void:
	stop_pocket()
	phase="won" if success else "lost"
	result_layer.show()
	look_drag=false
	if success:
		play_sound("complete",-6)
		result_text.text="这五分钟，属于你。\n\n12 颗拼豆 · 掌机灯塔通关 · 两次检查通过\n一个小小心愿完成了。\n\nR 重来，也可以点下面按钮。"
	else:
		var reasons:PackedStringArray=[]
		if drag.cover_ratio()<.97:reasons.append("拼豆板没有盖够")
		if not drag.stowed("tools") or drawer_open:reasons.append("镊子 / 抽屉没有收好")
		if not pocket.won:reasons.append("掌机关卡还没通关")
		if not drag.stowed("handheld") or drawer_open:reasons.append("掌机还在外面")
		if not working:reasons.append("电脑还停在音乐页")
		if not inspecting.is_empty() or moving:reasons.append("手里的东西还没放回")
		result_text.text="门开了，露馅了。\n\n"+"\n".join(reasons)+"\n\n下次听到脚步，先盖、收、切。"
	update_hud()

func reset_game() -> void:
	# The bridge and assistant autoload stay attached to this same card/scene.
	get_tree().reload_current_scene()

func toast(text: String, seconds: float = 3.0) -> void:
	notice.text=text
	notice_time=seconds

func play_sound(id: String, db: float = -11) -> void:
	if DisplayServer.get_name()=="headless":return
	var p:=AudioStreamPlayer.new()
	p.stream=load("res://assets/audio/"+id+".wav")
	p.volume_db=db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func update_hud() -> void:
	var compact:=drawer_open or drawer_moving
	objective.position=Vector2(28,147) if compact else Vector2(28,690)
	hint.position=Vector2(28,179) if compact else Vector2(28,722)
	meter.visible=not compact
	controls_label.visible=not compact
	meter.value=beads_placed
	clock_label.text="%02d:%02d  /  午后" % [int(elapsed)/60,int(elapsed)%60]
	if phase=="warning":
		objective.text="皮鞋声靠近 · 收拾还剩 %d 秒" % maxi(0,ceili(WARNING_SECONDS-phase_clock))
		status.text="%s 盖板 %d%%  /  %s 镊子  /  %s 掌机通关藏好  /  %s 关抽屉  /  %s 工作页" % ["✓" if covered else "○",int(drag.cover_ratio()*100),"✓" if drag.stowed("tools") else "○","✓" if drag.stowed("handheld") and pocket.won else "○","✓" if not drawer_open else "○","✓" if working else "○"]
	elif phase=="checking":objective.text="老板检查中 · 保持桌面整洁"
	else:
		objective.text="任务一 %s %d/12 颗  ·  任务二 %s 灯塔 %d%%" % ["✓" if beads_placed>=REQUIRED else "○",beads_placed,"✓" if pocket.won else "○",mini(100,int(pocket.player.x/pocket.FINISH_X*100))]
		status.text="检查 %d / 2 · 首次脚步在 01:14；出现后仍有 17 秒收拾" % visits_passed
	if pocket_playing:hint.text="掌机：A D / ← → 移动 · 空格跳 · R 重试 · Esc 离开屏幕；桌面时钟继续走"
	elif not drag.id.is_empty():hint.text="%s · %s" % [{"folder":"文件夹","tools":"镊子","handheld":"掌机"}.get(drag.id,drag.id),drag.solution.get("reason","松开落下")]
	elif not inspecting.is_empty():hint.text="近看：右键按住转动，短按放回 · 滚轮距离"+(" · 点屏幕开始玩" if inspecting=="handheld" else "")
	elif moving or drawer_moving:hint.text="轻拿轻放…"
	else:
		match hover_id:
			"tools":hint.text="左键查看镊子 · 查看后可拿来拼豆 · 右键拖到抽屉"
			"board":hint.text="左键查看板子 · 拿好镊子后，查看中放豆"
			"folder":hint.text="左键近看 · 按住右键拖到 / 移开拼豆板"
			"handheld":hint.text="左键拿到眼前，点屏幕玩 · 右键拖到打开的抽屉"
			"drawer":hint.text="左键独立拉开 / 关闭抽屉 · 不会自动收物件"
			"computer":hint.text="左键切换电脑页面 · 当前："+("工作" if working else "电台")
			_:hint.text="左键近看物件 · 移动鼠标环顾"
	if action_button:
		action_button.visible=not moving and not pocket_playing and (inspecting=="tools" or (inspecting=="board" and equipped))
		action_button.text="拿镊子拼豆" if inspecting=="tools" else "放一颗 · 空格"
	play_button.visible=inspecting=="handheld" and not pocket_playing and not moving and phase in ["free","warning"]

func make_handheld() -> void:
	var console:=prop("handheld",Vector3(.68,.763,.26))
	console.rotation.y=-.06
	var polymer:=Geo.textured("res://assets/textures/ai/polymer_albedo.png","d1d6d8",1.0)
	polymer.roughness_texture=load("res://assets/textures/ai/polymer_roughness.png")
	polymer.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
	polymer.normal_enabled=true
	polymer.normal_texture=load("res://assets/textures/ai/polymer_normal.png")
	polymer.normal_scale=.22
	polymer.metallic_specular=.25
	polymer.uv1_scale=Vector3(1.5,.9,1)
	var seam:=Geo.material("141e21",.70)
	var cyan:=Geo.material("458e9b",.56,.04)
	var coral:=Geo.material("b46d56",.55,.04)
	var rubber:=Geo.material("1b282b",.92)
	# Rounded silhouette with real thickness, bevels, separate rails and controller shells.
	Geo.box(console,Vector3(.230,.017,.137),Vector3(0,.013,0),polymer,.007)
	Geo.box(console,Vector3(.224,.002,.131),Vector3(0,.023,0),seam,.004)
	for side in [-1,1]:
		var mat:Material=cyan if side<0 else coral
		Geo.box(console,Vector3(.043,.022,.144),Vector3(side*.133,.014,0),mat,.008)
		Geo.box(console,Vector3(.0015,.020,.128),Vector3(side*.109,.014,0),seam,.0003)
		Geo.box(console,Vector3(.034,.002,.131),Vector3(side*.133,.003,0),rubber,.001)
		Geo.box(console,Vector3(.031,.006,.012),Vector3(side*.131,.022,-.064),rubber,.002)
		var zz:float=-.037 if side<0 else .033
		Geo.cylinder(console,.014,.005,Vector3(side*.134,.027,zz),rubber)
		Geo.cylinder(console,.0105,.006,Vector3(side*.134,.032,zz),polymer)
		Geo.torus(console,.009,.011,Vector3(side*.134,.035,zz),rubber)
		for d in [Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1)]:
			Geo.cylinder(console,.0042,.003,Vector3(side*.134+d.x*.008,.028,-zz+d.y*.008),rubber)
		Geo.box(console,Vector3(.008,.003,.002),Vector3(side*.133,.027,-.056),rubber,.0003)
		for z in [-.056,.056]:
			var screw:=Geo.cylinder(console,.0017,.001,Vector3(side*.150,.006,z),mats.steel)
			Geo.box(screw,Vector3(.0004,.0003,.0022),Vector3(0,.0006,0),seam,0)
	# Rear kickstand, connector socket, speaker perforations and air vents.
	Geo.box(console,Vector3(.037,.002,.074),Vector3(.070,.003,.004),seam,.001)
	Geo.box(console,Vector3(.017,.005,.003),Vector3(0,.012,.069),seam,.001)
	for i in range(16):Geo.box(console,Vector3(.0025,.002,.006),Vector3(-.055+i*.007,.024,-.063),seam,.0003)
	for side in [-1,1]:
		for i in range(7):Geo.cylinder(console,.0007,.0008,Vector3(side*.089+i*.002,.025,.060),seam)
	pocket_view=SubViewport.new()
	pocket_view.size=Vector2i(640,360)
	pocket_view.disable_3d=true
	pocket_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(pocket_view)
	pocket=PocketGame.new()
	pocket_view.add_child(pocket)
	var display:=StandardMaterial3D.new()
	pocket_screen_material=display
	display.albedo_texture=pocket_view.get_texture()
	display.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	display.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var quad:=QuadMesh.new();quad.size=Vector2(.205,.1153)
	var panel:=Geo.mesh(console,quad,Vector3(0,.0245,0),display)
	panel.rotation.x=-PI/2
	# Slim physical glass edge; no opaque overlay hiding the playable viewport.
	var glass:=Geo.material("8badae",.17,.25)
	glass.albedo_color.a=.13;glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	var cover:=Geo.mesh(console,quad,Vector3(0,.0247,0),glass)
	cover.rotation.x=-PI/2
	cover.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Geo.hit(console,"handheld",Vector3(.315,.037,.148),Vector3(0,.016,0))
	console.set_meta("polymer",polymer)

func start_pocket() -> void:
	if inspecting!="handheld" or moving or phase not in ["free","warning"]:return
	pocket_playing=true;look_drag=false;pocket.set_active(true)
	toast("A D / 方向键移动，空格跳。R 重试。Esc 离开屏幕准备藏放。",5)

func stop_pocket() -> void:
	pocket_playing=false
	if pocket:pocket.set_active(false)

func release_render_targets() -> void:
	# Break material -> ViewportTexture links before the SubViewport leaves the tree.
	# Godot owns the ReflectionProbe RIDs; freeing nodes and draining renderer frames
	# releases their captures. Never free engine-owned RIDs directly.
	stop_pocket()
	if pocket_screen_material:pocket_screen_material.albedo_texture=null
	if is_instance_valid(pocket_view):
		pocket_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
		pocket_view.set_physics_object_picking(false)

func _exit_tree() -> void:
	release_render_targets()

func screen_pointer(mouse: Vector2) -> Variant:
	var n:Node3D=props.handheld
	var origin:Vector3=n.to_local(camera.project_ray_origin(mouse))
	var ray:Vector3=n.global_basis.inverse()*camera.project_ray_normal(mouse)
	if absf(ray.y)<.00001:return null
	var distance:float=(.0245-origin.y)/ray.y
	if distance<=0:return null
	var point:Vector3=origin+ray*distance
	if absf(point.x)>.1025 or absf(point.z)>.05765:return null
	return Vector2((point.x/.205+.5)*640,(point.z/.1153+.5)*360)

func _notification(what: int) -> void:
	if controls==null:return
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		controls.focused=false;controls.release_inputs(true)
	elif what==NOTIFICATION_WM_MOUSE_EXIT:
		controls.focused=false;controls.release_inputs(false)
	elif what in [NOTIFICATION_WM_MOUSE_ENTER,NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		controls.focused=true;controls.rebase()
