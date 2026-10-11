extends RefCounted
## Every rank costs one earned progression skill point. No scene or UI ownership.
signal changed
const VERSION := 1
const CATALOG := {
	"blade_training": {"name": "剑术研习", "branch": "offense", "max_rank": 3,
		"description": "每级近战攻击 +3。", "requires": {}, "stats": {"attack": 3.0}},
	"execution": {"name": "迅捷锋刃", "branch": "offense", "max_rank": 3,
		"description": "每级近战攻击 +4、移动速度 +5。需要剑术研习 2 级。",
		"requires": {"blade_training": 2}, "stats": {"attack": 4.0, "speed": 5.0}},
	"arcane_focus": {"name": "魔力专注", "branch": "magic", "max_rank": 3,
		"description": "每级魔法攻击 +3、法力上限 +5。", "requires": {}, "stats": {"magic": 3.0, "mana": 5.0}},
	"arcane_flow": {"name": "奥术回流", "branch": "magic", "max_rank": 3,
		"description": "每级魔法攻击 +4、每秒法力回复 +0.5。需要魔力专注 2 级。",
		"requires": {"arcane_focus": 2}, "stats": {"magic": 4.0, "regen": 0.5}},
	"vitality": {"name": "坚韧体魄", "branch": "survival", "max_rank": 3,
		"description": "每级生命上限 +10、护甲 +1。", "requires": {}, "stats": {"health": 10.0, "defense": 1.0}},
	"iron_will": {"name": "钢铁意志", "branch": "survival", "max_rank": 3,
		"description": "每级生命上限 +8、护甲 +2。需要坚韧体魄 2 级。",
		"requires": {"vitality": 2}, "stats": {"health": 8.0, "defense": 2.0}}
}
var ranks: Dictionary = {}
var last_error := ""
var _busy := false

func _init() -> void:
	for id in CATALOG:
		ranks[id] = 0

func rank(id: String) -> int:
	return int(ranks.get(id, 0))

func spent_points() -> int:
	var total := 0
	for id in CATALOG:
		total += rank(id)
	return total

func can_spend(id: String, progression: RefCounted) -> bool:
	return _spend_reason(id, progression).is_empty()

func spend(id: String, progression: RefCounted) -> bool:
	last_error = _spend_reason(id, progression)
	if not last_error.is_empty():
		return false
	_busy = true
	# Publish a consistent combined tree/point balance even to changed-signal listeners.
	ranks[id] = rank(id) + 1
	if not progression.spend_skill_points(1):
		ranks[id] = rank(id) - 1
		_busy = false
		last_error = "技能点不足。"
		return false
	_busy = false
	last_error = ""
	changed.emit()
	return true

func refund(progression: RefCounted) -> int:
	last_error = ""
	if _busy or not _valid_progression(progression):
		last_error = "角色成长数据不可用。"
		return 0
	var total := spent_points()
	if total == 0:
		return 0
	var available: int = progression.skill_points
	var earned: int = progression.level - 1
	if available < 0 or available + total > earned:
		last_error = "技能点与等级不一致，不能返还超额技能点。"
		return 0
	_busy = true
	for id in CATALOG:
		ranks[id] = 0
	progression.skill_points = available + total
	if progression.has_signal("changed"):
		progression.emit_signal("changed")
	_busy = false
	last_error = ""
	changed.emit()
	return total

func bonuses() -> Dictionary:
	var result := {"health": 0.0, "mana": 0.0, "attack": 0.0, "magic": 0.0,
		"defense": 0.0, "speed": 0.0, "regen": 0.0}
	for id in CATALOG:
		for stat in CATALOG[id].stats:
			result[stat] += float(CATALOG[id].stats[stat]) * rank(id)
	return result

func snapshot() -> Dictionary:
	return {"version": VERSION, "ranks": ranks.duplicate()}

func restore(data: Dictionary) -> bool:
	last_error = ""
	if _busy or not _whole_number(data.get("version")) or float(data.version) != VERSION or not data.get("ranks") is Dictionary:
		last_error = "天赋存档格式或版本无效。"
		return false
	for id in data.ranks:
		if not id is String or not CATALOG.has(id):
			last_error = "天赋存档包含未知天赋。"
			return false
	var restored := {}
	for id in CATALOG:
		var value: Variant = data.ranks.get(id, 0)
		if not _whole_number(value) or float(value) < 0 or float(value) > int(CATALOG[id].max_rank):
			last_error = "天赋等级超出范围。"
			return false
		restored[id] = int(value)
	for id in CATALOG:
		if int(restored[id]) <= 0:
			continue
		for prerequisite in CATALOG[id].requires:
			if int(restored[prerequisite]) < int(CATALOG[id].requires[prerequisite]):
				last_error = "天赋缺少前置等级。"
				return false
	# Runtime validates spent_points + remaining skill_points == level - 1 separately.
	ranks = restored
	changed.emit()
	return true

func _spend_reason(id: String, progression: RefCounted) -> String:
	if _busy:
		return "天赋调整进行中。"
	if not CATALOG.has(id):
		return "未知天赋。"
	if not _valid_progression(progression):
		return "角色成长数据不可用。"
	if rank(id) >= int(CATALOG[id].max_rank):
		return "天赋已达到最高等级。"
	if progression.skill_points <= 0:
		return "技能点不足。"
	if progression.skill_points + spent_points() > progression.level - 1:
		return "技能点与等级不一致。"
	for prerequisite in CATALOG[id].requires:
		if rank(prerequisite) < int(CATALOG[id].requires[prerequisite]):
			return "%s需要 %d 级。" % [CATALOG[prerequisite].name, CATALOG[id].requires[prerequisite]]
	return ""

func _valid_progression(progression: RefCounted) -> bool:
	if not is_instance_valid(progression) or not progression.has_method("spend_skill_points"):
		return false
	return progression.get("skill_points") is int and progression.get("level") is int and progression.level >= 1 and progression.skill_points >= 0

func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
