extends RefCounted
const ZONES := {"town":{"name":"苍石庭院","contract":"res://map-contract.json"},"ruins":{"name":"古塔试炼场","contract":"res://systems/data/ruins.json"}}

static func load_zone(id: String) -> Dictionary:
	if not ZONES.has(id): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(ZONES[id].contract))
	if not data is Dictionary or not data.get("bounds") is Dictionary or not data.get("volumes") is Array:
		return {}
	return data
