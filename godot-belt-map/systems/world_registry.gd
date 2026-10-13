extends RefCounted
const ZONES := {"town":{"name":"苍石庭院","contract":"res://map-contract.json"},"ruins":{"name":"古塔试炼场","contract":"res://systems/data/ruins.json"},"forest":{"name":"旧林道","contract":"res://systems/data/forest.json"},"city":{"name":"晨钟城","contract":"res://systems/data/city.json"}}

static func is_safe(id: String) -> bool:
	return id in ["town","city"]

static func is_dungeon(id: String) -> bool:
	return id in ["ruins","forest"]

static func title(id: String) -> String:
	return str(ZONES.get(id,{}).get("name",id))

static func waves(id: String) -> int:
	return 1 if id=="forest" else 3

static func load_zone(id: String) -> Dictionary:
	var registry: Node = _content_registry()
	if registry!=null:
		var world:Dictionary=registry.world_bundle()
		var zones: Variant = world.get("zones", {})
		if zones is Dictionary and zones.has(id): return zones[id].duplicate(true)
	if not ZONES.has(id): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(ZONES[id].contract))
	if not data is Dictionary or not data.get("bounds") is Dictionary or not data.get("volumes") is Array:
		return {}
	return data

static func zone_ids()->Array[String]:
	var registry: Node = _content_registry()
	if registry!=null:
		var world:Dictionary=registry.world_bundle()
		var zones: Variant = world.get("zones", {})
		if zones is Dictionary and not zones.is_empty():
			var result:Array[String]=[]
			for id in zones: result.append(str(id))
			result.sort()
			return result
	var fallback:Array[String]=[]
	for id in ZONES: fallback.append(str(id))
	return fallback

static func has_zone(id:String)->bool: return id in zone_ids()

static func initial_zone_id()->String:
	var registry: Node = _content_registry()
	if registry!=null:
		var world:Dictionary=registry.world_bundle()
		var zones: Variant = world.get("zones", {})
		if world.get("initial_zone_id") is String and zones is Dictionary and zones.has(world.initial_zone_id): return str(world.initial_zone_id)
	return "town"

static func _content_registry() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	return loop.root.get_node_or_null("ContentRegistry") if loop is SceneTree else null
