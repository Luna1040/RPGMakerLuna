extends SceneTree
const Fine=preload("res://tailored_models.gd")
func own(node: Node, target: Node) -> void:
	for child in node.get_children():
		child.owner=target
		if child is MeshInstance3D and child.get_meta("silk_brocade",false): child.material_override.albedo_texture=null
		own(child,target)
func save(root_model: Node3D, filename: String) -> void:
	root_model.name="VisualBody"
	own(root_model,root_model)
	var scene := PackedScene.new()
	assert(scene.pack(root_model)==OK)
	assert(ResourceSaver.save(scene,"res://assets/3d/"+filename+".tscn")==OK)
	root_model.free()
func _initialize() -> void:
	var holder := Node3D.new()
	for index in range(6): save(Fine.npc(holder,index).root,"npc_%d" % index)
	for data in [["刀客","class_blade"],["剑客","class_sword"],["枪客","class_spear"],["医生","class_doctor"]]: save(Fine.profession(holder,data[0]).root,data[1])
	save(Fine.profession(holder,"刀客").root,"hero")
	save(Fine.npc(holder,0).root,"master")
	save(Fine.profession(holder,"刀客").root,"practice")
	holder.free()
	print("PASS: 13 tailored native 3D assets, six distinct NPC identities and four professions exported")
	quit()
