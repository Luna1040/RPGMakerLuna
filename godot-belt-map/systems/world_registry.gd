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
	if not ZONES.has(id): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(ZONES[id].contract))
	if not data is Dictionary or not data.get("bounds") is Dictionary or not data.get("volumes") is Array:
		return {}
	return data
