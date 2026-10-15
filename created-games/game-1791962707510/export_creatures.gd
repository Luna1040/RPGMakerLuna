extends SceneTree
const C = preload("res://creatures_3d.gd")
const Names=["野猫","蛤蟆","狐狸","野猪","狂牛","灰狼"]
func own(node: Node, target: Node) -> void:
	for child in node.get_children():
		child.owner=target
		own(child,target)
func _initialize() -> void:
	var holder := Node3D.new()
	for i in range(6):
		var visual := C.make(holder,Names[i])
		own(visual,visual)
		var scene := PackedScene.new()
		assert(scene.pack(visual)==OK)
		assert(ResourceSaver.save(scene,"res://assets/3d/monster_%d.tscn" % i)==OK)
		visual.free()
	holder.free()
	print("PASS: six native volumetric chibi animal models exported")
	quit()
