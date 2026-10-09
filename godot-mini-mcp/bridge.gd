extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		finish({"ok": false, "error": "Expected request file"})
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not request is Dictionary:
		finish({"ok": false, "error": "Invalid JSON request"})
		return
	var scene: String = request.get("scene", "res://main.tscn")
	var packed: PackedScene = load(scene) as PackedScene
	if packed == null:
		finish({"ok": false, "error": "Cannot load scene: " + scene})
		return
	var node: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	if request.command == "summary":
		var entries: Array = []
		collect(node, node, entries, int(request.get("max_nodes", 40)))
		finish({"ok": true, "scene": scene, "nodes": entries, "truncated": node_count(node) > entries.size()})
	elif request.command == "batch":
		var failure := ""
		for op: Dictionary in request.operations:
			if op.kind == "add_node":
				var parent := find_node(node, op.get("parent", "."))
				var type_name: String = op.get("type", "Node2D")
				var child_name: String = op.get("name", "")
				if parent == null or not ClassDB.class_exists(type_name) or not ClassDB.is_parent_class(type_name, "Node") or not ClassDB.can_instantiate(type_name):
					failure = "Invalid parent or node type"
					break
				if child_name.is_empty() or child_name.validate_node_name() != child_name or parent.has_node(NodePath(child_name)):
					failure = "Invalid or duplicate node name"
					break
				var child: Node = ClassDB.instantiate(type_name)
				child.name = child_name
				parent.add_child(child)
				child.owner = node
			elif op.kind == "set_property":
				var target := find_node(node, op.get("path", "."))
				var property: String = op.get("property", "")
				if target == null:
					failure = "Node does not exist"
					break
				var property_type := -1
				for info: Dictionary in target.get_property_list():
					if info.name == property:
						property_type = info.type
						break
				var value: Variant = op.get("value")
				if property_type == TYPE_VECTOR2 and value is Array and value.size() == 2:
					value = Vector2(value[0], value[1])
				elif property_type == TYPE_COLOR and value is Array and value.size() == 4:
					value = Color(value[0], value[1], value[2], value[3])
				elif property_type == TYPE_INT and (value is float or value is int):
					value = int(value)
				elif property_type == TYPE_FLOAT and (value is float or value is int):
					value = float(value)
				if property_type < 0 or property in ["script", "owner", "name"] or typeof(value) != property_type:
					failure = "Unknown, unsupported or mismatched property: " + property
					break
				target.set(property, value)
			else:
				failure = "Unsupported operation"
				break
		if not failure.is_empty():
			finish({"ok": false, "error": failure, "saved": false})
		else:
			var output := PackedScene.new()
			var error := output.pack(node)
			var temp: String = scene.get_basename() + ".ai-tmp.tscn"
			if error == OK:
				error = ResourceSaver.save(output, temp)
			if error == OK:
				error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(scene))
			finish({"ok": error == OK, "saved": error == OK, "changed_operations": request.operations.size(), "error_code": error})
	node.free()

func find_node(base: Node, path: String) -> Node:
	if path == "." or path == "/":
		return base
	if path.begins_with("/") or ".." in path.split("/"):
		return null
	return base.get_node_or_null(NodePath(path))

func collect(base: Node, current: Node, entries: Array, limit: int) -> void:
	if entries.size() >= limit:
		return
	var entry := {"path": str(base.get_path_to(current)), "type": current.get_class()}
	if current is Node2D:
		entry.position = [current.position.x, current.position.y]
	if current is Label:
		entry.text = current.text.left(100)
	entries.append(entry)
	for child in current.get_children():
		collect(base, child, entries, limit)

func node_count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += node_count(child)
	return total

func finish(result: Dictionary) -> void:
	print("@@MCP@@" + JSON.stringify(result))
	quit(0 if result.get("ok", false) else 1)
