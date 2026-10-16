extends RefCounted
const M = preload("res://models_3d.gd")

static func make(parent: Node3D, species: String) -> Node3D:
	var root := Node3D.new()
	root.name="CreatureVisual"
	parent.add_child(root)
	var color: Color = {"野猫":Color("c7ab83"),"蛤蟆":Color("79a668"),"狐狸":Color("dc9254"),"野猪":Color("856b61"),"狂牛":Color("986f51"),"灰狼":Color("83959c")}[species]
	var heavy := species in ["野猪","狂牛"]
	M.oval(root,Vector3(0,0.57,0),Vector3(0.47 if heavy else 0.32,0.38 if heavy else 0.27,0.68 if heavy else 0.48),color)
	M.oval(root,Vector3(0,0.77,0.49),Vector3(0.36 if heavy else 0.31,0.32,0.31),color)
	M.oval(root,Vector3(0,0.59,0.76),Vector3(0.25,0.15,0.20),color.lightened(0.18))
	M.oval(root,Vector3(0,0.65,0.89),Vector3(0.13,0.07,0.05),Color("3a393b"))
	for x in [-0.19,0.19]:
		M.oval(root,Vector3(x,0.86,0.76),Vector3(0.065,0.085,0.028),Color("fff7dc"))
		M.oval(root,Vector3(x,0.86,0.789),Vector3(0.033,0.05,0.016),Color("243a41"))
		M.oval(root,Vector3(x-0.012,0.89,0.801),Vector3(0.011,0.016,0.006),Color.WHITE)
	for x in [-0.23,0.23]:
		for z in [-0.32,0.31]:
			var leg := M.oval(root,Vector3(x,0.23,z),Vector3(0.12,0.23,0.13),color.darkened(0.05))
			leg.name="Leg%d" % (int(x>0)*2+int(z>0))
			M.oval(leg,Vector3(0,-0.65,0.24),Vector3(1.05,0.32,1.25),Color("3c4240") if heavy else color.lightened(0.1))
	if species=="蛤蟆":
		root.scale=Vector3(1.2,0.70,1.1)
		for x in [-0.23,0.23]: M.oval(root,Vector3(x,0.95,0.52),Vector3(0.15,0.16,0.14),color.lightened(0.2))
		for x in [-0.23,0.23]:
			M.oval(root,Vector3(x,0.97,0.645),Vector3(0.10,0.11,0.028),Color("fff7dc"))
			M.oval(root,Vector3(x,0.97,0.671),Vector3(0.044,0.08,0.015),Color("243a41"))
		for i in range(10): M.oval(root,Vector3(sin(i*2.4)*0.24,0.81,cos(i*2.4)*0.32-0.2),Vector3(0.04,0.035,0.05),color.darkened(0.17))
	elif species=="狂牛":
		for x in [-0.29,0.29]:
			var horn := M.cylinder(root,Vector3(x,1.12,0.48),0.46,0.10,Color("f1dfb2"),0.01)
			horn.rotation.z=-signf(x)*0.65
			M.oval(root,Vector3(x*1.35,0.95,0.45),Vector3(0.20,0.07,0.12),color)
	elif species=="野猪":
		for x in [-0.22,0.22]:
			M.cylinder(root,Vector3(x,0.69,0.84),0.24,0.055,Color("f8eacb"),0.008)
			M.oval(root,Vector3(x,1.05,0.40),Vector3(0.13,0.13,0.075),color.darkened(0.1))
	else:
		if species=="野猫":
			for x in [-0.30,0.30]:
				for y in [0.61,0.67]:
					var whisker := M.box(root,Vector3(x,y,0.78),Vector3(0.26,0.012,0.012),Color("f9eed6"))
					whisker.rotation.z=signf(x)*0.1
		for x in [-0.24,0.24]:
			M.cylinder(root,Vector3(x,1.09,0.44),0.35,0.13,color,0.008)
			M.cylinder(root,Vector3(x,1.11,0.49),0.23,0.065,Color("edc3ae"),0.003)
		var tail := M.oval(root,Vector3(0,0.70,-0.67),Vector3(0.18 if species=="狐狸" else 0.09,0.18 if species=="狐狸" else 0.09,0.45),color)
		tail.rotation.x=-0.6
		M.oval(tail,Vector3(0,0,-0.73),Vector3(0.9,0.9,0.28),Color("ece9d6"))
		M.oval(root,Vector3(0,0.54,0.47),Vector3(0.22,0.24,0.08),Color("ece9d6"))
	return root
