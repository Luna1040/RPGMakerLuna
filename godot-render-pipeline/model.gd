extends Node2D

# A deterministic articulated original 3D mannequin. Segment meshes and clothing
# are driven by the same joint coordinates; no frame images are generated here.
var viewport: SubViewport
var camera: Camera3D
var model: Node3D
var display: Sprite2D
var meshes := {}
var materials := {}
var outfit := "knight"
var hair := "gold"
var weapon := "steel"
var skin := "warm"
var cape := true
var effects := true
var facing := 1
var camera_angle := 18.0
var current_pose := {}
var weapon_root: Node3D
var effect_root: Node3D
var last_action := "idle"
var last_frame := 0
var body_type := "female"
var pixel_viewport: SubViewport
var breast_nodes: Array = []
var abs_nodes: Array = []

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(128,128)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0,0,0,0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b3c5df")
	environment.environment.ambient_light_energy = 0.4
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = 0.9
	viewport.add_child(light)
	model = Node3D.new()
	viewport.add_child(model)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.near = 0.1
	camera.far = 30.0
	viewport.add_child(camera)
	camera.make_current()
	for item in {"skin":"e9b58c","skin_dark":"cb916e","training":"303d50","armor":"93aecd","armor_dark":"557294","scout":"478c7e","boot":"526881","gold":"deb557","hair_gold":"d9ac48","hair_copper":"af603a","blade":"ccd9e7","ink":"172636","cape":"355b9d"}:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://pixel-material.gdshader")
		mat.set_shader_parameter("base_color",Color({"skin":"e9b58c","skin_dark":"cb916e","training":"303d50","armor":"b4c5df","armor_dark":"647fa8","scout":"4b9683","boot":"526881","gold":"e5bd64","hair_gold":"edc268","hair_copper":"c07946","blade":"d2e2f2","ink":"172636","cape":"3c65ac"}[item]))
		materials[item] = mat
	for item in {"swim":"389ca7","dress":"9b4779"}:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://pixel-material.gdshader")
		mat.set_shader_parameter("base_color",Color({"swim":"389ca7","dress":"9b4779"}[item]))
		materials[item] = mat
	build_model()
	# Postprocessing renders the same one-pixel outline for both live display
	# and the images captured by the offline baker.
	pixel_viewport = SubViewport.new()
	pixel_viewport.size = Vector2i(128,128)
	pixel_viewport.transparent_bg = true
	pixel_viewport.disable_3d = true
	pixel_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pixel_viewport)
	var quad := Sprite2D.new()
	quad.centered = false
	quad.texture = viewport.get_texture()
	quad.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var outline := ShaderMaterial.new()
	outline.shader = load("res://pixel-outline.gdshader")
	quad.material = outline
	pixel_viewport.add_child(quad)
	display = Sprite2D.new()
	display.texture = pixel_viewport.get_texture()
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(display)
	update_camera()
	set_pose("idle",0)

func node_mesh(name_: String, mesh: Mesh, material: String, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = materials[material]
	(parent if parent != null else model).add_child(node)
	meshes[name_] = node
	return node

func ball(name_: String, radius: float, material: String, parent: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2
	mesh.radial_segments = 12
	mesh.rings = 6
	return node_mesh(name_,mesh,material,parent)

func rod(name_: String, radius: float, material: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius*0.82
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	node_mesh(name_,mesh,material)

func cuboid(name_: String, dimensions: Vector3, material: String, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return node_mesh(name_,mesh,material,parent)

func rings_mesh(rings: Array, sides := 10) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rings.size()-1):
		for col in range(sides):
			var a := TAU*col/sides
			var b := TAU*(col+1)/sides
			var low: Vector3 = rings[row]
			var high: Vector3 = rings[row+1]
			var v := [Vector3(cos(a)*low.x,low.y,sin(a)*low.z),Vector3(cos(b)*low.x,low.y,sin(b)*low.z),Vector3(cos(a)*high.x,high.y,sin(a)*high.z),Vector3(cos(b)*high.x,high.y,sin(b)*high.z)]
			for index in [0,2,1,1,2,3]:
				tool.add_vertex(v[index])
	tool.generate_normals()
	return tool.commit()

func build_model() -> void:
	var torso := torso_profile()
	node_mesh("torso",rings_mesh(torso),"skin")
	var covered := []
	for ring in torso:
		covered.append(Vector3(ring.x+0.016,ring.y,ring.z+0.016))
	node_mesh("shirt",rings_mesh(covered),"armor")
	# A smooth pelvis is part of the neutral fitting base, not underwear.
	var pelvis := ball("pelvis",.16,"skin")
	pelvis.position = Vector3(0,.745,0)
	pelvis.scale = Vector3(.94,.85,1.0 if body_type == "female" else .85)
	add_body_details()
	node_mesh("swim_bottom",rings_mesh([Vector3(.18,.68,.15),Vector3(.17,.87,.14)]),"swim")
	var bodice := torso_profile()
	var dress_rings := []
	for ring in bodice:
		if ring.y <= 1.16:
			dress_rings.append(Vector3(ring.x+.020,ring.y,ring.z+.020))
	node_mesh("dress_bodice",rings_mesh(dress_rings),"dress")
	node_mesh("dress_skirt",rings_mesh([Vector3(.27,.42,.23),Vector3(.22,.67,.19),Vector3(.12,.94,.105)]),"dress")
	node_mesh("tabard",rings_mesh([Vector3(.20,.65,.145),Vector3(.12,.91,.112)]),"cape")
	var belt := cuboid("belt",Vector3(.26,.055,.25),"gold")
	belt.position = Vector3(0,.89,0)
	var neck := ball("neck",.065,"skin")
	neck.scale.y = 1.3
	neck.position = Vector3(.015,1.39,0)
	var head := ball("head",.17,"skin")
	head.scale = Vector3(.88,1.38,.82)
	head.position = Vector3(.03,1.655,0)
	var nose := ball("nose",.045,"skin")
	nose.scale = Vector3(.9,.7,.6)
	nose.position = Vector3(.195,1.64,0)
	var eye := ball("eye",.015,"ink")
	eye.scale.z = .5
	eye.position = Vector3(.118,1.704,.114)
	var eye_white := ball("eye_white",.023,"blade")
	eye_white.scale = Vector3(.60,.65,.25)
	eye_white.position = Vector3(.115,1.704,.116)
	eye.position = Vector3(.183,1.704,.073)
	eye.scale = Vector3(.35,.7,.55)
	eye_white.position = Vector3(.173,1.704,.073)
	eye_white.scale = Vector3(.22,.8,.60)
	var far_eye := ball("far_eye",.015,"ink")
	far_eye.position = Vector3(.183,1.704,-.073)
	far_eye.scale = eye.scale
	var far_white := ball("far_eye_white",.023,"blade")
	far_white.position = Vector3(.173,1.704,-.073)
	far_white.scale = eye_white.scale
	var brow := cuboid("brow",Vector3(.040,.012,.014),"ink")
	brow.position = Vector3(.175,1.74,.073)
	brow.rotation.y = PI*.5
	var mouth := cuboid("mouth",Vector3(.012,.008,.025),"skin_dark")
	mouth.position = Vector3(.175,1.59,0)
	var hair_rings := []
	for i in range(7):
		var angle := .05+i/6.0*1.43
		hair_rings.append(Vector3(sin(angle)*.174,1.665+cos(angle)*.255,sin(angle)*.16))
	hair_rings.reverse()
	node_mesh("hair_cap",rings_mesh(hair_rings),"hair_gold")
	var pony := ball("ponytail",.09,"hair_gold")
	pony.position = Vector3(-.20,1.36,-.055)
	pony.scale = Vector3(.7,3.5,.7)
	pony.rotation.z = -.30
	var pony_tip := ball("ponytail_tip",.07,"hair_gold")
	pony_tip.position = Vector3(-.265,1.11,-.055)
	pony_tip.scale = Vector3(.7,1.2,.6)
	var ribbon := ball("ribbon",.045,"cape")
	ribbon.position = Vector3(-.13,1.64,0)
	var cape_mesh := cuboid("cape",Vector3(.035,.74,.30),"cape")
	cape_mesh.position = Vector3(-.17,.98,-.055)
	cape_mesh.rotation.z = -.15
	for side in ["far","near"]:
		rod(side+"_thigh",.078,"skin")
		rod(side+"_calf",.050,"skin")
		rod(side+"_upper_arm",.062,"skin")
		rod(side+"_forearm",.048,"skin")
		rod(side+"_sleeve",.076,"armor")
		rod(side+"_guard",.060,"armor_dark")
		rod(side+"_boot",.072,"boot")
		ball(side+"_knee",.072,"skin")
		ball(side+"_elbow",.053,"skin")
		ball(side+"_hand",.052,"skin")
		ball(side+"_pauldron",.095,"armor")
		cuboid(side+"_foot",Vector3(.28,.115,.16),"training")
		meshes[side+"_foot"].material_override = materials.skin
		cuboid(side+"_shoe",Vector3(.30,.125,.19),"armor")
	weapon_root = Node3D.new()
	model.add_child(weapon_root)
	cuboid("hilt",Vector3(.20,.043,.048),"training",weapon_root).position.x = -.005
	cuboid("guard",Vector3(.055,.30,.055),"gold",weapon_root).position.x = .12
	# One blade mesh, constant world length; this node only translates/rotates.
	var blade_tool := SurfaceTool.new()
	blade_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := [Vector3(.16,.065,0),Vector3(.84,.045,0),Vector3(1.0,0,0),Vector3(.84,-.045,0),Vector3(.16,-.065,0),Vector3(.16,0,.035),Vector3(.84,0,.025)]
	for face in [[0,1,5],[1,6,5],[1,2,6],[2,3,6],[3,4,5],[3,5,6],[0,5,4]]:
		for index in face:
			blade_tool.add_vertex(vertices[index])
	blade_tool.generate_normals()
	var blade := node_mesh("blade",blade_tool.commit(),"blade",weapon_root)
	var blade_mat := materials.blade.duplicate() as ShaderMaterial
	blade.material_override = blade_mat
	effect_root = Node3D.new()
	effect_root.position = Vector3(.25,1.16,.30)
	model.add_child(effect_root)
	var arc_tool := SurfaceTool.new()
	arc_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(24):
		var a := -1.25+i/24.0*1.6
		var b := -1.25+(i+1)/24.0*1.6
		var center := Vector3.ZERO
		var quad := [center+Vector3(cos(a)*1.34,-sin(a)*1.34,0),center+Vector3(cos(b)*1.34,-sin(b)*1.34,0),center+Vector3(cos(a)*1.20,-sin(a)*1.20,0),center+Vector3(cos(b)*1.20,-sin(b)*1.20,0)]
		for index in [0,1,2,1,3,2]:
			arc_tool.add_vertex(quad[index])
	var effect_mat := StandardMaterial3D.new()
	effect_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	effect_mat.albedo_color = Color("b1f5ed")
	effect_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arc := MeshInstance3D.new()
	arc.mesh = arc_tool.commit()
	arc.material_override = effect_mat
	effect_root.add_child(arc)

func torso_profile() -> Array:
	if body_type == "male":
		return [Vector3(.14,.72,.13),Vector3(.13,.88,.12),Vector3(.145,1.03,.135),Vector3(.18,1.18,.19),Vector3(.155,1.31,.18)]
	return [Vector3(.15,.72,.145),Vector3(.135,.81,.13),Vector3(.095,.94,.09),Vector3(.115,1.04,.10),Vector3(.13,1.16,.115),Vector3(.13,1.30,.11)]

func add_body_details() -> void:
	if body_type == "female":
		for z in [-.062,.062]:
			var index := breast_nodes.size()
			var base := ball("chest_%d" % index,.071,"skin")
			base.position = Vector3(.12,1.16,z)
			base.scale = Vector3(1.15,1.0,.94)
			var cover := ball("chest_cover_%d" % index,.078,"armor")
			cover.position = base.position
			cover.scale = base.scale
			breast_nodes.append([base,cover])
	else:
		for row in range(3):
			for z in [-.052,.052]:
				var ab := ball("abs_%d" % abs_nodes.size(),.038,"skin")
				ab.position = Vector3(.135,.94+row*.078,z)
				ab.scale = Vector3(.35,.90,1.0)
				abs_nodes.append(ab)
		for z in [-.086,.086]:
			var pec := ball("pec_%s" % str(z),.088,"skin")
			pec.position = Vector3(.15,1.185,z)
			pec.scale = Vector3(.55,.75,1.0)

func update_camera() -> void:
	var target := Vector3(.43,1.5625,0)
	var angle := deg_to_rad(camera_angle)
	camera.position = target+Vector3(sin(angle)*7,0,cos(angle)*7)
	camera.look_at(target)
	display.position = -camera.unproject_position(Vector3.ZERO)
	display.scale.x = facing
	if facing < 0:
		display.position.x *= -1

func point(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x/32.0,-p.y/32.0,z)

func segment(name_: String, a: Vector3, b: Vector3) -> void:
	var node: MeshInstance3D = meshes[name_]
	node.position = (a+b)*0.5
	var direction := (b-a).normalized()
	var x := Vector3.FORWARD.cross(direction).normalized()
	if x.length_squared() < .1:
		x = Vector3.RIGHT
	var z := x.cross(direction).normalized()
	node.basis = Basis(x,direction*a.distance_to(b),z)

func solve_joint(a: Vector3, target: Vector3, upper: float, lower: float, hint: Vector3, forward_knee := false) -> Array:
	# Fixed-length two-bone IK in the XY plane. Pose references supply targets,
	# not bone scale; clothing and skin both use the resulting joint transforms.
	var delta := Vector2(target.x-a.x,target.y-a.y)
	var distance := clampf(delta.length(),absf(upper-lower)+.001,upper+lower-.001)
	var direction := delta.normalized()
	var projected := (upper*upper-lower*lower+distance*distance)/(2*distance)
	var height := sqrt(maxf(0,upper*upper-projected*projected))
	var normal := Vector2(-direction.y,direction.x)
	var center := Vector2(a.x,a.y)+direction*projected
	var first := center+normal*height
	var second := center-normal*height
	var hint2 := Vector2(hint.x,hint.y)
	var knee := first if first.distance_squared_to(hint2) <= second.distance_squared_to(hint2) else second
	if forward_knee:
		knee = first if first.x > second.x else second
	return [Vector3(knee.x,knee.y,a.z),Vector3(a.x+direction.x*distance,a.y+direction.y*distance,a.z)]

func pose(action: String, frame_: int) -> Dictionary:
	var p := {"near_knee":Vector2(4,-13),"near_ankle":Vector2(5,-3),"far_knee":Vector2(-4,-13),"far_ankle":Vector2(-5,-3),"elbow":Vector2(8,-32),"hand":Vector2(13,-26),"angle":.62}
	if action == "walk":
		p.near_knee = [Vector2(8,-13),Vector2(3,-13),Vector2(-8,-14),Vector2(-5,-17)][frame_]
		p.near_ankle = [Vector2(14,-3),Vector2(0,-3),Vector2(-12,-3),Vector2(-6,-10)][frame_]
		p.far_knee = [Vector2(-7,-14),Vector2(-5,-17),Vector2(7,-13),Vector2(3,-13)][frame_]
		p.far_ankle = [Vector2(-12,-3),Vector2(-6,-10),Vector2(14,-3),Vector2(0,-3)][frame_]
	if action == "slash":
		p.near_knee = Vector2(9,-13)
		p.near_ankle = Vector2(15,-3)
		p.far_knee = Vector2(-7,-14)
		p.far_ankle = Vector2(-11,-3)
		p.elbow = [Vector2(-5,-40),Vector2(0,-48),Vector2(13,-41),Vector2(14,-30),Vector2(9,-31),Vector2(8,-32)][frame_]
		p.hand = [Vector2(-9,-46),Vector2(5,-53),Vector2(24,-42),Vector2(22,-24),Vector2(16,-24),Vector2(13,-26)][frame_]
		p.angle = [-2.2,-1.2,.10,.78,.65,.62][frame_]
	return p

func set_pose(action: String, frame_: int, blend := 0.0) -> void:
	if model == null:
		return
	last_action = action
	last_frame = frame_
	var p := pose(action,frame_)
	if blend > 0:
		var count := 1 if action == "idle" else (4 if action == "walk" else 6)
		var next := pose(action,(frame_+1)%count)
		for key in p:
			p[key] = lerp(p[key],next[key],blend)
	current_pose = p
	for side in ["far","near"]:
		var depth := .16 if body_type == "male" else .12
		var z := -depth if side == "far" else depth
		var hip := point(Vector2(-2 if side == "far" else 2,-24),z)
		var knee := point(p[side+"_knee"],z)
		var ankle := point(p[side+"_ankle"],z)
		var leg_solution := solve_joint(hip,ankle,.41,.41,knee,true)
		knee = leg_solution[0]
		ankle = leg_solution[1]
		segment(side+"_thigh",hip,knee)
		segment(side+"_calf",knee,ankle)
		segment(side+"_boot",knee.lerp(ankle,.30),ankle)
		meshes[side+"_knee"].position = knee
		for foot in ["_foot","_shoe"]:
			meshes[side+foot].position = ankle+Vector3(.06,-.033,0)
		var shoulder := point(Vector2(-3 if side == "far" else 2,-41),z)
		var elbow := point(Vector2(-5,-32) if side == "far" else p.elbow,z)
		var hand := point(Vector2(-4,-27) if side == "far" else p.hand,z)
		var arm_solution := solve_joint(shoulder,hand,.29 if side == "far" else .36,.25 if side == "far" else .33,elbow)
		elbow = arm_solution[0]
		hand = arm_solution[1]
		segment(side+"_upper_arm",shoulder,elbow)
		segment(side+"_forearm",elbow,hand)
		segment(side+"_sleeve",shoulder,elbow)
		segment(side+"_guard",elbow,hand)
		meshes[side+"_elbow"].position = elbow
		meshes[side+"_hand"].position = hand
		meshes[side+"_pauldron"].position = shoulder
		if side == "near":
			weapon_root.position = hand+Vector3(0,0,.03)
	weapon_root.rotation.z = -float(p.angle)
	weapon_root.visible = weapon != "none"
	effect_root.visible = effects and weapon != "none" and action == "slash" and frame_ in [2,3]
	effect_root.rotation.z = -.9 if frame_ == 3 else 0.0
	update_equipment()
	update_camera()

func update_equipment() -> void:
	var armor := outfit in ["knight","scout"]
	var swim := outfit == "swim"
	var dress := outfit == "dress"
	meshes.shirt.visible = armor or (swim and body_type == "female")
	meshes.tabard.visible = armor
	meshes.belt.visible = armor or dress
	meshes.swim_bottom.visible = swim
	meshes.dress_bodice.visible = dress
	meshes.dress_skirt.visible = dress
	for pair in breast_nodes:
		pair[1].visible = armor or swim or dress
		pair[1].material_override = materials.swim if swim else (materials.dress if dress else materials.armor)
	for ab in abs_nodes:
		ab.visible = not armor and not dress
	for side in ["far","near"]:
		for part in ["_sleeve","_guard","_pauldron","_boot","_shoe"]:
			meshes[side+part].visible = armor
		meshes[side+"_foot"].visible = not armor
		for part in ["_sleeve","_guard","_pauldron","_shoe"]:
			meshes[side+part].material_override = materials.scout if outfit == "scout" else materials.armor
	meshes.shirt.material_override = materials.swim if swim else (materials.scout if outfit == "scout" else materials.armor)
	meshes.cape.visible = cape and armor
	for part in ["hair_cap"]:
		meshes[part].visible = hair != "none"
	for part in ["ponytail","ponytail_tip","ribbon"]:
		meshes[part].visible = hair not in ["none","short"]
	for part in ["hair_cap","ponytail","ponytail_tip"]:
		meshes[part].material_override = materials.hair_copper if hair == "copper" else materials.hair_gold
	var blade_material: ShaderMaterial = meshes.blade.material_override
	blade_material.set_shader_parameter("base_color",Color("e7c169") if weapon == "gold" else Color("ccd9e7"))
