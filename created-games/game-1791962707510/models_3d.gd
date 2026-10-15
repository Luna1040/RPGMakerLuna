extends RefCounted
## Native, low-poly volume models. These are simplified prototype assets, not AI images.

static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m

static func mesh_node(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	node.position = at
	parent.add_child(node)
	return node

static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color, layer: int = 0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := mesh_node(parent,mesh,at,color)
	if layer > 0:
		var body := StaticBody3D.new()
		body.collision_layer = layer
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var volume := BoxShape3D.new()
		volume.size = size
		shape.shape = volume
		node.add_child(body)
		body.add_child(shape)
	return node

static func cylinder(parent: Node3D, at: Vector3, height: float, radius: float, color: Color, top: float = -1) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.radial_segments = 24
	mesh.rings = 1
	return mesh_node(parent,mesh,at,color)

static func sphere(parent: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2
	mesh.radial_segments = 32
	mesh.rings = 16
	return mesh_node(parent,mesh,at,color)

static func volume(parent: Node3D, vertices: PackedVector3Array, triangles: PackedInt32Array, color: Color, collision: bool = false) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles: tool.add_vertex(vertices[index])
	tool.generate_normals()
	var mesh := tool.commit()
	var node := mesh_node(parent,mesh,Vector3.ZERO,color)
	# Roof eaves have two visible faces; geometry remains a closed volume.
	(node.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	if collision:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_convex_shape()
		node.add_child(body)
		body.add_child(shape)
	return node

static func roof(parent: Node3D, at: Vector3, width: float, depth: float, height: float, color: Color) -> void:
	var holder := Node3D.new()
	holder.position = at
	parent.add_child(holder)
	var v := PackedVector3Array([Vector3(-width/2,0,-depth/2),Vector3(width/2,0,-depth/2),Vector3(0,height,-depth/2),Vector3(-width/2,0,depth/2),Vector3(width/2,0,depth/2),Vector3(0,height,depth/2)])
	volume(holder,v,PackedInt32Array([0,2,1,3,4,5,0,3,5,0,5,2,1,2,5,1,5,4,0,1,4,0,4,3]),color,true).set_meta("material_kind","roof")
	box(holder,Vector3(0,height+0.03,0),Vector3(0.2,0.18,depth+0.3),color.lightened(0.16)).set_meta("material_kind","roof")
	for z in [-depth/2,depth/2]:
		for x in [-width/2,width/2]:
			var tip := box(holder,Vector3(x,0.08,z),Vector3(0.4,0.16,0.3),color.lightened(0.2))
			tip.set_meta("material_kind","roof")
			tip.rotation.z = -signf(x)*0.4

static func caption(parent: Node3D, text: String, at: Vector3, font: Font, size: int = 36) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.pixel_size = 0.012
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 5
	parent.add_child(label)
	return label

static func building(parent: Node3D, at: Vector3, hall: bool, font: Font) -> Node3D:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	var width := 7.0 if hall else 5.0
	var depth := 4.5 if hall else 4.0
	var wall_color := Color("e4c697") if hall else Color("d7ad88")
	var roof_color := Color("3d746d") if hall else Color("a24f49")
	box(root,Vector3(0,0.15,0),Vector3(width+0.5,0.3,depth+0.5),Color("9b9b88"),2).set_meta("material_kind","wall")
	box(root,Vector3(0,1.65,0),Vector3(width,3,depth),wall_color,2).set_meta("material_kind","wall")
	# Side and back windows are modeled as well as the front facade.
	for z in [-depth/2-0.02,depth/2+0.02]:
		for x in [-width*0.3,width*0.3]:
			box(root,Vector3(x,1.75,z),Vector3(1,1.15,0.1),Color("4f5749"))
			for offset in [-0.27,0,0.27]: box(root,Vector3(x+offset,1.75,z),Vector3(0.05,1.2,0.14),Color("bd9267")).set_meta("material_kind","wood")
	for x in [-width/2-0.03,width/2+0.03]: box(root,Vector3(x,1.75,0),Vector3(0.1,1.15,1.4),Color("4f5749"))
	for x in [-width/2+0.3,width/2-0.3]:
		cylinder(root,Vector3(x,1.8,depth/2+0.22),3.6,0.16,Color("773e36")).set_meta("material_kind","wood")
	box(root,Vector3(0,1.25,depth/2+0.06),Vector3(1.5,2.4,0.15),Color("674536")).set_meta("material_kind","wood")
	box(root,Vector3(0,2.8,depth/2+0.2),Vector3(2.5,0.5,0.15),Color("544437")).set_meta("material_kind","wood")
	caption(root,"泫渤大殿" if hall else "香玉客栈",Vector3(0,3.25,depth/2+0.4),font,29)
	roof(root,Vector3(0,3.25,0),width+1.5,depth+1.6,1.5,roof_color)
	if hall:
		box(root,Vector3(0,4.25,0),Vector3(width*0.55,1,depth*0.65),wall_color).set_meta("material_kind","wall")
		roof(root,Vector3(0,4.65,0),width*0.7,depth*0.9,1.05,roof_color)
	else:
		for x in [-1.9,1.9]:
			cylinder(root,Vector3(x,2.35,depth/2+0.55),0.6,0.25,Color("ec9b65"))
	return root

static func oval(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := sphere(parent,at,1,color)
	node.scale=size
	return node

static func actor(parent: Node3D, color: Color, elder: bool = false) -> Dictionary:
	var visual := Node3D.new()
	visual.name="VisualBody"
	parent.add_child(visual)
	var skin := Color("f6d4ae")
	var hair_color := Color("dddcd2") if elder else Color("293a45")
	var robe := cylinder(visual,Vector3(0,0.85,0),0.86,0.34,color,0.27)
	robe.name="Robe"
	oval(visual,Vector3(0,1.19,0),Vector3(0.29,0.26,0.23),color)
	# Rounded hems, wrapped sash and crossed cloth lapels remain real volumes.
	cylinder(visual,Vector3(0,0.44,0),0.07,0.347,color.darkened(0.12))
	cylinder(visual,Vector3(0,0.91,0),0.10,0.313,Color("dfba6b"))
	for x in [-0.12,0.12]:
		var lapel := box(visual,Vector3(x,1.12,0.225),Vector3(0.065,0.37,0.032),Color("f3edce"))
		lapel.rotation.z=signf(x)*0.48
	oval(visual,Vector3(0,0.91,0.32),Vector3(0.065,0.065,0.025),Color("f6dc96"))
	var left_leg := oval(visual,Vector3(-0.15,0.26,0),Vector3(0.105,0.23,0.12),Color("334654"))
	var right_leg := oval(visual,Vector3(0.15,0.26,0),Vector3(0.105,0.23,0.12),Color("334654"))
	left_leg.name="LeftLeg"
	right_leg.name="RightLeg"
	for x in [-0.15,0.15]:
		oval(visual,Vector3(x,0.09,0.07),Vector3(0.13,0.095,0.2),Color("293942")).name="BootLeft" if x<0 else "BootRight"
		box(visual,Vector3(x,0.025,0.06),Vector3(0.23,0.035,0.3),Color("c2b391"))
	oval(visual,Vector3(0,1.63,0.01),Vector3(0.445,0.46,0.405),skin).name="Head"
	for x in [-0.43,0.43]: oval(visual,Vector3(x,1.61,0),Vector3(0.065,0.10,0.06),skin)
	oval(visual,Vector3(0,1.87,-0.055),Vector3(0.47,0.30,0.41),hair_color).name="Hair"
	oval(visual,Vector3(0,1.64,-0.19),Vector3(0.44,0.38,0.28),hair_color).name="BackHair"
	for i in range(5):
		oval(visual,Vector3((i-2)*0.13,1.43,-0.35),Vector3(0.10,0.17,0.09),hair_color).name="HairBackLock%d" % i
	# Sculpted tapered locks frame the face instead of a single helmet sphere.
	for i in range(7):
		var x := (i-3)*0.105
		var lock := oval(visual,Vector3(x,1.86-absf(x)*0.18,0.29),Vector3(0.08,0.20-absf(x)*0.1,0.10),hair_color)
		lock.name="HairLock%d" % i
		lock.rotation.z=-x*0.7
	for x in [-0.40,0.40]:
		oval(visual,Vector3(x,1.64,-0.01),Vector3(0.075,0.24,0.15),hair_color).name="SideLockL" if x<0 else "SideLockR"
	oval(visual,Vector3(0,2.13,-0.10),Vector3(0.145,0.13,0.15),hair_color).name="Topknot"
	cylinder(visual,Vector3(0,2.06,-0.1),0.055,0.15,Color("daba72"))
	for x in [-0.16,0.16]:
		# Thin curved eye surfaces: no protruding spherical eyeballs.
		oval(visual,Vector3(x,1.65,0.375),Vector3(0.108,0.132,0.024),Color("fff9ea"))
		oval(visual,Vector3(x,1.64,0.397),Vector3(0.062,0.103,0.012),Color("325968"))
		oval(visual,Vector3(x,1.655,0.408),Vector3(0.035,0.073,0.008),Color("172732"))
		oval(visual,Vector3(x-0.022,1.69,0.417),Vector3(0.021,0.028,0.008),Color.WHITE)
		var brow := oval(visual,Vector3(x,1.81,0.36),Vector3(0.10,0.024,0.025),hair_color)
		brow.rotation.z=signf(x)*0.11
		oval(visual,Vector3(x*1.45,1.49,0.337),Vector3(0.06,0.024,0.009),Color("e8a18e"))
	oval(visual,Vector3(0,1.54,0.418),Vector3(0.035,0.040,0.024),skin.darkened(0.02))
	oval(visual,Vector3(0,1.43,0.37),Vector3(0.065,0.012,0.015),Color("b96861"))
	if elder:
		oval(visual,Vector3(0,1.38,0.31),Vector3(0.15,0.16,0.09),Color("e5e0ce"))
		for x in [-0.08,0.08]: oval(visual,Vector3(x,1.47,0.40),Vector3(0.09,0.025,0.025),Color("e5e0ce"))
	var left_arm := oval(visual,Vector3(-0.37,1.09,0),Vector3(0.14,0.28,0.16),color.lightened(0.05))
	left_arm.name="LeftArm"
	oval(left_arm,Vector3(0,-0.78,0.04),Vector3(0.70,0.27,0.60),skin)
	var right_arm := Node3D.new()
	visual.add_child(right_arm)
	right_arm.name="RightArm"
	right_arm.position=Vector3(0.37,1.35,0)
	oval(right_arm,Vector3(0,-0.22,0),Vector3(0.14,0.28,0.16),color.lightened(0.05))
	oval(right_arm,Vector3(0,-0.50,0.015),Vector3(0.09,0.08,0.08),skin)
	var sword := box(right_arm,Vector3(0,-0.49,0.48),Vector3(0.07,0.04,1.15),Color("dce9e8"))
	sword.name="Sword"
	box(right_arm,Vector3(0,-0.49,0.05),Vector3(0.28,0.075,0.07),Color("e2ba71"))
	var ribbon := box(visual,Vector3(0,0.85,-0.30),Vector3(0.20,0.55,0.045),Color("da7058"))
	ribbon.name="Ribbon"
	return {"root":visual,"left_leg":left_leg,"right_leg":right_leg,"left_arm":left_arm,"right_arm":right_arm,"robe":robe,"ribbon":ribbon,"sword":sword}

static func profession_actor(parent: Node3D, profession: String) -> Dictionary:
	var color: Color = {"刀客":Color("78b3d8"),"剑客":Color("8470af"),"枪客":Color("47988b"),"医生":Color("d4ded1")}.get(profession,Color("78b3d8"))
	var model := actor(parent,color)
	var root: Node3D = model.root
	var hair_color: Color = {"刀客":Color("a3bfd1"),"剑客":Color("a95238"),"枪客":Color("273e3c"),"医生":Color("293a38")}.get(profession,Color("273e3c"))
	root.get_node("Hair").material_override=material(hair_color)
	root.get_node("Topknot").material_override=material(hair_color)
	for child in root.get_children():
		if child.name.begins_with("Hair") or child.name=="BackHair" or child.name.begins_with("SideLock"): child.material_override=material(hair_color)
	box(root,Vector3(0,0.85,0.275),Vector3(0.24,0.58,0.045),Color("eef2df"))
	for x in [-0.19,0.19]: box(root,Vector3(x,0.85,0.28),Vector3(0.055,0.6,0.04),Color("bfac75"))
	if profession=="剑客":
		var pony := cylinder(root,Vector3(0,1.62,-0.5),0.55,0.13,hair_color,0.08)
		pony.rotation.x=0.4
		(model.sword.mesh as BoxMesh).size=Vector3(0.045,0.045,1.25)
	elif profession=="枪客" or profession=="医生":
		model.sword.mesh=BoxMesh.new()
		(model.sword.mesh as BoxMesh).size=Vector3(0.05,0.05,0.05)
		model.sword.visible=false
		var length := 2.2 if profession=="枪客" else 1.3
		var pole := cylinder(model.right_arm,Vector3(0,-0.28,0.48),length,0.045,Color("8f6b48"))
		pole.rotation.x=PI/2 if profession=="枪客" else 0
		if profession=="枪客":
			var tip := cylinder(model.right_arm,Vector3(0,-0.28,1.74),0.35,0.13,Color("d4e0d9"),0.0)
			tip.rotation.x=PI/2
		else:
			cylinder(root,Vector3(0,1.93,-0.08),0.18,0.4,Color("db91a6"),0.33)
			sphere(model.right_arm,Vector3(0,0.48,0.48),0.12,Color("deb56a"))
			sphere(model.right_arm,Vector3(0,0.49,0.55),0.06,Color("86c6c0"))
	return model

static func actor_from_scene(parent: Node3D, path: String) -> Dictionary:
	if FileAccess.file_exists("res://assets/client-actors/MOB00006.glb"):
		return load("res://client_actor_rig.gd").make(parent,path)
	var visual: Node3D = (load(path) as PackedScene).instantiate()
	parent.add_child(visual)
	apply_tailored_texture(visual)
	return {"root":visual,"left_leg":visual.get_node("LeftLeg"),"right_leg":visual.get_node("RightLeg"),"left_arm":visual.get_node("LeftArm"),"right_arm":visual.get_node("RightArm"),"robe":visual.get_node("Robe"),"ribbon":visual.get_node("Ribbon"),"sword":visual.get_node("RightArm/Sword")}

static func apply_tailored_texture(node: Node) -> void:
	if node is MeshInstance3D and node.get_meta("silk_brocade",false):
		node.material_override=load("res://tailored_models.gd").cloth(node.material_override.albedo_color)
	for child in node.get_children(): apply_tailored_texture(child)

static func tree(parent: Node3D, at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	box(root,Vector3(0,1.2,0),Vector3(0.4,2.4,0.4),Color("82634a"),2).set_meta("material_kind","wood")
	for i in range(3): cylinder(root,Vector3(0,2.1+i*0.6,0),1.7,1.5-i*0.25,Color("507d61").lightened(i*0.04),0.08)

static func ramp(parent: Node3D) -> void:
	# A 0.6 m change over 3 m: a physically walkable slope with decorative tread lines.
	var v := PackedVector3Array([Vector3(8,0,7),Vector3(11,0,7),Vector3(8,0.6,4),Vector3(11,0.6,4),Vector3(8,0,4),Vector3(11,0,4)])
	var node := volume(parent,v,PackedInt32Array([0,2,3,0,3,1,0,4,2,1,3,5,2,4,5,2,5,3,0,1,5,0,5,4]),Color("aaa28b"))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = node.mesh.create_trimesh_shape()
	node.add_child(body)
	body.add_child(shape)
	box(parent,Vector3(9.5,0.3,3),Vector3(3,0.6,2),Color("a8a18c"),1)
