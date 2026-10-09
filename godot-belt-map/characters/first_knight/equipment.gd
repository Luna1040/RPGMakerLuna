extends RefCounted
## One owned instance per item; catalog IDs are the persistence boundary.
signal changed
const SAVE_PATH := "user://first_knight_equipment.json"
const SLOTS := ["weapon", "armor", "charm", "boots"]
const SLOT_NAMES := {"weapon":"武器", "armor":"铠甲", "charm":"饰品", "boots":"战靴"}
const STAT_NAMES := {"health":"生命上限", "mana":"法力上限", "attack":"近战加成", "magic":"法术加成", "defense":"护甲", "speed":"移动速度", "regen":"法力回复"}
const CATALOG := {
	"knight_sword":{"name":"骑士长剑", "slot":"weapon", "quality":"初始", "symbol":"剑", "description":"陪伴骑士的长剑。保留原有三段攻击。", "stats":{}},
	"knight_armor":{"name":"银金骑士甲", "slot":"armor", "quality":"初始", "symbol":"甲", "description":"骑士原有的银金铠甲。", "stats":{}},
	"edge_sword":{"name":"破锋长剑", "slot":"weapon", "quality":"精良", "symbol":"剑", "description":"每一段近战攻击额外造成 8 点伤害。", "stats":{"attack":8.0}},
	"arcane_sword":{"name":"秘银符文剑", "slot":"weapon", "quality":"稀有", "symbol":"剑", "description":"兼顾剑术与法术的符文武器。", "stats":{"attack":4.0,"magic":14.0}},
	"guardian_armor":{"name":"守誓重甲", "slot":"armor", "quality":"稀有", "symbol":"甲", "description":"增加生存能力，但略微降低移动速度。", "stats":{"health":40.0,"defense":6.0,"speed":-15.0}},
	"mage_armor":{"name":"灵纹轻甲", "slot":"armor", "quality":"精良", "symbol":"甲", "description":"提高法力储备，适合连续施法。", "stats":{"mana":30.0,"defense":2.0}},
	"storm_charm":{"name":"雷光护符", "slot":"charm", "quality":"稀有", "symbol":"符", "description":"增强法术直接伤害；感电机制保持原样。", "stats":{"magic":10.0,"mana":20.0}},
	"spring_charm":{"name":"泉息吊坠", "slot":"charm", "quality":"精良", "symbol":"符", "description":"提高每秒法力回复和生命上限。", "stats":{"regen":3.0,"health":15.0}},
	"wind_boots":{"name":"疾风战靴", "slot":"boots", "quality":"精良", "symbol":"靴", "description":"提升地面移动速度。", "stats":{"speed":35.0}},
	"courtyard_blade":{"name":"庭卫精钢剑", "slot":"weapon", "quality":"稀有", "symbol":"剑", "description":"庭院宝箱中的精钢长剑，近战伤害提高 12。", "stats":{"attack":12.0}},
	"courtyard_mail":{"name":"苍石护甲", "slot":"armor", "quality":"稀有", "symbol":"甲", "description":"庭卫珍藏的护甲，提高生命与防御。", "stats":{"health":25.0,"defense":5.0}},
	"courtyard_charm":{"name":"晨星吊坠", "slot":"charm", "quality":"稀有", "symbol":"符", "description":"散发微光的护符，提高法力与回复。", "stats":{"mana":15.0,"regen":2.0}},
	"steel_boots":{"name":"钢铸战靴", "slot":"boots", "quality":"精良", "symbol":"靴", "description":"用少量机动性换取更坚实的防护。", "stats":{"defense":3.0,"health":15.0,"speed":-5.0}}
}
var owned: Array = ["knight_sword", "knight_armor", "edge_sword", "arcane_sword", "guardian_armor", "mage_armor", "storm_charm", "spring_charm", "wind_boots", "steel_boots"]
var equipped: Dictionary = {"weapon":"knight_sword", "armor":"knight_armor", "charm":"", "boots":""}
var persistence_enabled := true
var save_error := ""

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
