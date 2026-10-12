extends RefCounted
## One owned instance per item; catalog IDs are the persistence boundary.
signal changed
const SAVE_PATH := "user://first_knight_equipment.json"
const SLOTS := ["weapon", "armor", "charm", "boots"]
const SLOT_NAMES := {"weapon":"武器", "armor":"铠甲", "charm":"饰品", "boots":"战靴"}
const STAT_NAMES := {"health":"生命上限", "mana":"法力上限", "attack":"近战加成", "magic":"法术加成", "defense":"护甲", "speed":"移动速度", "regen":"法力回复"}
const Validator = preload("res://systems/content/content_validator.gd")
const CATALOG_PATH := "res://content/base/equipment.json"
## Instance compatibility name retained for existing gameplay consumers and saves.
## Its authority is the validated ContentRegistry, not a second hard-coded table.
var CATALOG: Dictionary = {}
var owned: Array = ["knight_sword", "knight_armor", "edge_sword", "arcane_sword", "guardian_armor", "mage_armor", "storm_charm", "spring_charm", "wind_boots", "steel_boots"]
var equipped: Dictionary = {"weapon":"knight_sword", "armor":"knight_armor", "charm":"", "boots":""}
var persistence_enabled := true
var save_error := ""

func _init() -> void:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		var registry = main_loop.root.get_node_or_null("ContentRegistry")
		if registry != null and registry.loaded:
			CATALOG = registry.definitions("equipment")
			return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var errors := Validator.validate_content_bundle(parsed)
	if not errors.is_empty():
		push_error("Equipment catalog: " + "; ".join(errors))
		return
	for entry: Dictionary in parsed.entries:
		CATALOG[str(entry.id)] = entry.duplicate(true)

func grant(id: String) -> bool:
	if not CATALOG.has(id) or owned.has(id):
		return false
	owned.append(id)
	changed.emit()
	save_loadout()
	return true

func bonuses(loadout: Dictionary = {}) -> Dictionary:
	if loadout.is_empty():
		loadout = equipped
	var result := {"health":0.0,"mana":0.0,"attack":0.0,"magic":0.0,"defense":0.0,"speed":0.0,"regen":0.0}
	for id in loadout.values():
		if CATALOG.has(id):
			for stat in CATALOG[id]["stats"]:
				result[stat] += float(CATALOG[id]["stats"][stat])
	return result

func preview(id: String) -> Dictionary:
	var next := equipped.duplicate()
	if CATALOG.has(id):
		next[CATALOG[id]["slot"]] = id
	return bonuses(next)

func equip(id: String) -> bool:
	if not owned.has(id) or not CATALOG.has(id):
		return false
	var slot: String = CATALOG[id]["slot"]
	if equipped[slot] == id:
		return false
	equipped[slot] = id
	changed.emit()
	save_loadout()
	return true

func unequip(slot: String) -> bool:
	if not equipped.has(slot) or equipped[slot] == "":
		return false
	equipped[slot] = ""
	changed.emit()
	save_loadout()
	return true

func save_loadout(path: String = SAVE_PATH) -> bool:
	save_error = ""
	if not persistence_enabled:
		return true
	# Write then rename so a partial write cannot replace the last valid loadout.
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		save_error = "装备已生效，但无法保存到本地。"
		return false
	file.store_string(JSON.stringify({"version":1,"owned":owned,"equipped":equipped}))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		save_error = "装备已生效，但本地存档写入失败。"
		return false
	return true

func load_loadout(path: String = SAVE_PATH) -> void:
	if not persistence_enabled or not FileAccess.file_exists(path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	var data = parser.data
	if not data is Dictionary or data.get("version") != 1 or not data.get("owned") is Array or not data.get("equipped") is Dictionary:
		return
	var valid_owned: Array = []
	for id in data["owned"]:
		if id is String and CATALOG.has(id) and not valid_owned.has(id):
			valid_owned.append(id)
	var valid_equipped := {}
	for slot in SLOTS:
		var id = data["equipped"].get(slot, "")
		valid_equipped[slot] = id if id is String and valid_owned.has(id) and CATALOG[id]["slot"] == slot else ""
	owned = valid_owned
	equipped = valid_equipped
	changed.emit()
