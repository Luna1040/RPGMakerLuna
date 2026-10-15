extends SceneTree

const Models = preload("res://models_3d.gd")

func own_children(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		own_children(child,owner_root)

func export_model(model: Node3D, name: String) -> void:
	model.position = Vector3.ZERO
	model.name = name
	for child in model.get_children():
		if child is Label3D:
			model.remove_child(child)
			child.free()
	own_children(model,model)
	var packed := PackedScene.new()
	assert(packed.pack(model)==OK)
	assert(ResourceSaver.save(packed,"res://assets/3d/"+name+".tscn")==OK)
	model.free()

func _initialize() -> void:
	assert(DirAccess.make_dir_recursive_absolute("res://assets/3d")==OK)
	var holder := Node3D.new()
	var font := FontFile.new()
	font.data = FileAccess.get_file_as_bytes("res://font.ttf")
	export_model(Models.profession_actor(holder,"刀客").root,"hero")
	for data in [["刀客","class_blade"],["剑客","class_sword"],["枪客","class_spear"],["医生","class_doctor"]]:
		export_model(Models.profession_actor(holder,data[0]).root,data[1])
	export_model(Models.actor(holder,Color("bca16b"),true).root,"master")
	export_model(Models.actor(holder,Color("ae6654")).root,"practice")
	export_model(Models.building(holder,Vector3.ZERO,true,font),"hall")
	export_model(Models.building(holder,Vector3.ZERO,false,font),"inn")
	holder.free()
	print("PASS: exported nine native 3D volume models including four Q-style profession variants")
	quit(0)
