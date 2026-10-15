extends RefCounted
const M = preload("res://models_3d.gd")
static var fabric: ImageTexture

static func cloth(color: Color) -> StandardMaterial3D:
	var result := M.material(color)
	result.roughness=0.72
	var path := "res://assets/textures/chibi/silk-brocade.png"
	if fabric==null and FileAccess.file_exists(path):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK:
			image.generate_mipmaps()
			fabric=ImageTexture.create_from_image(image)
	if fabric!=null: result.albedo_texture=fabric
	result.uv1_scale=Vector3(2,2,1)
	return result

static func garment(parent: Node3D, profile: Array, color: Color, depth: float=0.8) -> MeshInstance3D:
	# Smooth tailored surface of revolution, with stable UVs and modeled cloth pleats.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size()-1):
		for segment in range(48):
			for corner in [[0,0],[1,0],[1,1],[0,0],[1,1],[0,1]]:
				var level: int=row+corner[1]
				var angle: float = TAU*(segment+corner[0])/48.0
				var y: float=profile[level][0]
				var radius: float=profile[level][1]*(1+0.028*cos(angle*12)*clampf(1-y,0,1))
				tool.set_normal(Vector3(cos(angle),0.15,sin(angle)/depth).normalized())
				tool.set_uv(Vector2(float(segment+corner[0])/48,y))
				tool.add_vertex(Vector3(cos(angle)*radius,y-0.85,sin(angle)*radius*depth))
	var node := M.mesh_node(parent,tool.commit(),Vector3(0,0.85,0),color)
	node.material_override=cloth(color)
	node.set_meta("silk_brocade",true)
	return node

static func trim(parent: Node3D, at: Vector3, length: float, color: Color, angle: float=0) -> void:
	var stripe := M.box(parent,at,Vector3(0.045,length,0.025),color)
	stripe.rotation.z=angle

static func sculpt_lock(parent: Node3D, points: Array, width: float, color: Color) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(points.size()-1):
		for segment in range(12):
			for corner in [[0,0],[1,0],[1,1],[0,0],[1,1],[0,1]]:
				var k: int=row+corner[1]
				var angle: float=TAU*(segment+corner[0])/12.0
				var radius := width*maxf(0.045,1.0-float(k)/(points.size()-1))
				tool.add_vertex(points[k]+Vector3(cos(angle)*radius,0,sin(angle)*radius*0.48))
	tool.generate_normals()
	var lock := M.mesh_node(parent,tool.commit(),Vector3.ZERO,color)
	lock.name="SculptHairLock"

static func polished_details(model: Dictionary, color: Color) -> void:
	var root: Node3D=model.root
	# Closed swept locks taper to tips; layered fabric and boot soles have real depth.
	for old in root.get_children():
		if old.name.begins_with("HairLock") or old.name.begins_with("HairBackLock"): old.hide()
	for i in range(9):
		var x := (i-4)*0.074
		sculpt_lock(root,[Vector3(x,1.96,0.11),Vector3(x+0.028,1.87,0.28),Vector3(x+0.048,1.73,0.345),Vector3(x+0.015,1.67+absf(x)*0.19,0.36)],0.06,Color("33434d"))
	for side in [-1,1]:
		var boot := M.oval(root,Vector3(side*0.15,0.075,0.075),Vector3(0.12,0.064,0.20),Color("28343c"))
		boot.name="BootSole"
		M.oval(root,Vector3(side*0.15,0.12,0.19),Vector3(0.109,0.065,0.09),Color("4e5c63"))
		M.oval(root,Vector3(side*0.245,1.54,0.276),Vector3(0.057,0.022,0.018),Color("e6a88f"))
	var flap := garment(root,[[0.43,0.37],[0.52,0.34],[0.72,0.285]],color.darkened(0.12))
	flap.name="LayeredHem"
	var belt := garment(root,[[0.85,0.26],[0.89,0.27],[0.95,0.27]],Color("59473a"))
	belt.name="WaistBelt"
	M.oval(root,Vector3(0,0.90,0.233),Vector3(0.06,0.054,0.022),Color("d7b870"))

static func base(parent: Node3D, color: Color, elder: bool=false, female: bool=false) -> Dictionary:
	var model := M.actor(parent,color,elder)
	var root: Node3D=model.root
	model.robe.free()
	var profile := [[0.41,0.36],[0.47,0.34],[0.60,0.30],[0.88,0.25],[1.10,0.28],[1.24,0.27],[1.31,0.20]]
	if female: profile=[[0.18,0.38],[0.27,0.39],[0.50,0.34],[0.88,0.235],[1.08,0.255],[1.24,0.25],[1.31,0.18]]
	model.robe=garment(root,profile,color)
	model.robe.name="Robe"
	# Face and hair scale remain real geometry; age and gender change the silhouette.
	var head: Node3D=root.get_node("Head")
	head.scale.x*=0.94 if female else 1.0
	# Three-head proportions: scale every face/hair component together around the neck.
	for part in root.get_children():
		if part is MeshInstance3D and part.position.y>1.36:
			part.position=Vector3(0,1.63,0)+(part.position-Vector3(0,1.63,0))*0.85
			part.scale*=0.85
	if female:
		for x in [-0.136,0.136]:
			M.oval(root,Vector3(x,1.715,0.335),Vector3(0.085,0.012,0.012),Color("2f3034"))
	for side in [-1,1]:
		var old: Node3D=model.left_arm if side<0 else model.right_arm
		old.free()
		var arm := Node3D.new()
		arm.name="LeftArm" if side<0 else "RightArm"
		arm.position=Vector3(side*0.36,1.35,0)
		root.add_child(arm)
		var sleeve := garment(arm,[[-0.44,0.17 if female else 0.13],[-0.38,0.17 if female else 0.14],[-0.22,0.14],[-0.07,0.11],[0.04,0.10]],color)
		sleeve.material_override=cloth(color)
		sleeve.set_meta("silk_brocade",true)
		M.cylinder(arm,Vector3(0,-0.43,0),0.075,0.13,Color("cfb274"))
		M.oval(arm,Vector3(0,-0.51,0.025),Vector3(0.078,0.083,0.073),Color("f2caa5"))
		for finger in range(3): M.oval(arm,Vector3((finger-1)*0.027,-0.54,0.073),Vector3(0.014,0.035,0.017),Color("e8bd98"))
		if side<0: model.left_arm=arm
		else: model.right_arm=arm
	var weapon := M.box(model.right_arm,Vector3(0,-0.49,0.48),Vector3(0.06,0.04,1.15),Color("cadde0"))
	weapon.name="Sword"
	model.sword=weapon
	for side in [-1,1]:
		trim(root,Vector3(side*0.12,1.11,0.24),0.31,Color("eee7ca"),side*0.48)
		trim(root,Vector3(side*0.24,0.67,0.265),0.43,Color("cfa768"),side*0.11)
		for i in range(3):
			var knot := M.oval(root,Vector3(side*0.12,0.62+i*0.11,0.30),Vector3(0.036,0.013,0.012),Color("ecd089"))
			knot.rotation.z=side*0.2
		M.box(root,Vector3(side*0.15,0.14,0.23),Vector3(0.11,0.018,0.025),Color("cbb37f"))
	polished_details(model,color)
	return model

static func hair_color(root: Node3D, color: Color) -> void:
	for child in root.get_children():
		if child is MeshInstance3D and (child.name.contains("Hair") or child.name.contains("Lock") or child.name=="Topknot"):
			child.material_override=M.material(color)

static func long_hair(root: Node3D, color: Color) -> void:
	hair_color(root,color)
	for side in [-1,1]:
		var strand := M.oval(root,Vector3(side*0.34,1.18,-0.14),Vector3(0.11,0.46,0.12),color)
		strand.rotation.z=side*0.10
	for x in [-0.20,-0.10,0.0,0.10,0.20]:
		M.oval(root,Vector3(x,1.17,-0.40),Vector3(0.085,0.42,0.09),color)

static func profession(parent: Node3D, kind: String) -> Dictionary:
	var color: Color={"刀客":Color("477fba"),"剑客":Color("7656a5"),"枪客":Color("32796d"),"医生":Color("e3ded1")}[kind]
	var model := base(parent,color,false,kind=="医生")
	var root: Node3D=model.root
	var hair: Color={"刀客":Color("6c889c"),"剑客":Color("934634"),"枪客":Color("273b3b"),"医生":Color("253b36")}[kind]
	hair_color(root,hair)
	if kind=="剑客" or kind=="医生": long_hair(root,hair)
	# Shoulder armor and layered fitted jacket; no flat full-body character billboard.
	for side in [-1,1]:
		M.oval(root,Vector3(side*0.30,1.24,0),Vector3(0.17,0.10,0.19),Color("d5c28e") if kind=="刀客" else color.lightened(0.18))
		M.cylinder(root,Vector3(side*0.15,0.33,0),0.065,0.11,Color("bea26c"))
	var grip := M.cylinder(model.right_arm,Vector3(0,-0.49,-0.11),0.23,0.045,Color("665547"))
	grip.rotation.x=PI/2
	M.box(model.right_arm,Vector3(0,-0.49,0.06),Vector3(0.28,0.055,0.06),Color("ccad69"))
	var w := 0.085 if kind=="刀客" else 0.040
	var points := PackedVector3Array([Vector3(-w,-0.025,-0.5),Vector3(w,-0.025,-0.5),Vector3(0,-0.025,0.8),Vector3(-w,0.025,-0.5),Vector3(w,0.025,-0.5),Vector3(0,0.025,0.8)])
	var blade := M.volume(root,points,PackedInt32Array([0,2,1,3,4,5,0,1,4,0,4,3,1,2,5,1,5,4,2,0,3,2,3,5]),Color.WHITE)
	model.sword.mesh=blade.mesh
	blade.free()
	if kind=="枪客" or kind=="医生":
		model.sword.hide()
		var pole := M.cylinder(model.right_arm,Vector3(0,-0.30,0.45),2.1 if kind=="枪客" else 1.3,0.035,Color("725335"))
		if kind=="枪客":
			pole.rotation.x=PI/2
			var tip := M.cylinder(model.right_arm,Vector3(0,-0.30,1.63),0.36,0.105,Color("cddfe1"),0)
			tip.rotation.x=PI/2
			M.box(model.right_arm,Vector3(0,-0.31,1.42),Vector3(0.10,0.25,0.03),Color("c25d48"))
		else:
			M.oval(root,Vector3(0,2.03,-0.08),Vector3(0.30,0.13,0.25),Color("be7f96"))
			M.oval(model.right_arm,Vector3(0,0.41,0.45),Vector3(0.09,0.10,0.09),Color("65bab0"))
			M.box(root,Vector3(-0.3,0.73,-0.07),Vector3(0.18,0.25,0.16),Color("a78558"))
	return model

static func npc(parent: Node3D, index: int) -> Dictionary:
	var colors := [Color("e8e1cc"),Color("ddb987"),Color("aa3a31"),Color("777b79"),Color("805438"),Color("287c83")]
	var model := base(parent,colors[index],index==3,index==1 or index==5)
	var root: Node3D=model.root
	model.sword.hide()
	if index==0:
		hair_color(root,Color("bfc4bd"))
		for side in [-1,1]:
			M.box(root,Vector3(side*0.30,0.87,0.17),Vector3(0.10,0.90,0.04),Color("ae3e45"))
			M.oval(root,Vector3(side*0.25,1.29,0),Vector3(0.20,0.09,0.24),Color("ae3e45"))
		for i in range(5): M.oval(root,Vector3(0,0.71+i*0.10,0.29),Vector3(0.09,0.019,0.019),Color("d2ad53"))
	elif index==1:
		long_hair(root,Color("25332e"))
		root.get_node("Topknot").hide()
		for side in [-1,1]:
			for petal in range(5):
				M.oval(root,Vector3(side*0.40+cos(petal*TAU/5)*0.045,1.88+sin(petal*TAU/5)*0.045,0.21),Vector3(0.045,0.040,0.028),Color("c85951"))
			M.oval(root,Vector3(side*0.43,1.47,0.10),Vector3(0.022,0.05,0.022),Color("d9ba71"))
		M.box(root,Vector3(0,0.75,0.295),Vector3(0.10,0.77,0.04),Color("b9473f"))
	elif index==2:
		model.robe.scale=Vector3(1.38,1,1.25)
		for child in root.get_children():
			if child.name.contains("Hair") or child.name.contains("Lock"): child.hide()
		root.get_node("Topknot").position.y=2.04
		root.get_node("Head").scale.x*=1.08
		for side in [-1,1]:
			M.oval(root,Vector3(side*0.085,1.47,0.40),Vector3(0.095,0.027,0.03),Color("655141"))
		M.box(model.left_arm,Vector3(0,-0.39,0.19),Vector3(0.23,0.30,0.08),Color("4f4338"))
	elif index==3:
		M.oval(root,Vector3(0,1.97,-0.08),Vector3(0.39,0.20,0.33),Color("858781"))
		for index_lock in range(7):
			var x := (index_lock-3)*0.047
			var length := 0.46-absf(x)*0.55
			M.cylinder(root,Vector3(x,1.47-length/2,0.32-absf(x)*0.10),length,0.009,Color("e4e0d3"),0.042)
		for side in [-1,1]: M.oval(root,Vector3(side*0.065,1.45,0.365),Vector3(0.09,0.023,0.025),Color("e4e0d3"))
		for side in [-1,1]: M.box(root,Vector3(side*0.26,1.05,0.17),Vector3(0.13,0.46,0.08),Color("ae894b"))
		M.cylinder(model.right_arm,Vector3(0,-0.60,0.23),1.5,0.045,Color("725537"))
	elif index==4:
		M.oval(root,Vector3(0,1.99,-0.05),Vector3(0.40,0.13,0.33),Color("9f3b37"))
		for arm in [model.left_arm,model.right_arm]:
			arm.get_child(0).material_override=M.material(Color("d8a87a"))
			arm.get_child(0).scale*=1.18
		M.box(root,Vector3(0,0.80,0.29),Vector3(0.35,0.73,0.045),Color("523e32"))
		M.cylinder(model.right_arm,Vector3(0,-0.43,0.25),0.70,0.042,Color("8a6344"))
		M.box(model.right_arm,Vector3(0,-0.04,0.25),Vector3(0.37,0.18,0.18),Color("617078"))
	elif index==5:
		long_hair(root,Color("243c3b"))
		M.cylinder(root,Vector3(0,2.11,-0.08),0.22,0.18,Color("243c3b"))
		var pin := M.cylinder(root,Vector3(0,2.13,-0.10),0.75,0.016,Color("dfb955"))
		pin.rotation.z=PI/2
		for side in [-1,1]: M.box(root,Vector3(side*0.17,0.75,0.28),Vector3(0.075,0.90,0.025),Color("b88b42"))
		M.cylinder(model.left_arm,Vector3(0,-0.43,0.15),0.29,0.10,Color("be9b78"))
	if index in [0,1,5]:
		model.left_arm.rotation=Vector3(-0.45,0,0.70)
		model.right_arm.rotation=Vector3(-0.45,0,-0.70)
	elif index==2:
		model.left_arm.rotation=Vector3(-0.35,0,0.55)
	return model
