extends RefCounted
## XP is progress within the current level. Bonuses are additive to base/gear stats.
signal changed
signal level_up(new_level: int)
const VERSION := 1
const MAX_LEVEL := 50
var level := 1
var xp := 0
var skill_points := 0

func xp_to_next() -> int:
	return 0 if level >= MAX_LEVEL else threshold_for(level)

func threshold_for(at_level: int) -> int:
	var growth := clampi(at_level, 1, MAX_LEVEL) - 1
	return 100 + 40 * growth + 10 * growth * growth

func add_xp(amount: int) -> Dictionary:
	var old_level := level
	var accepted := clampi(amount, 0, 1000000000) if level < MAX_LEVEL else 0
	if accepted > 0:
		xp += accepted
		while level < MAX_LEVEL and xp >= threshold_for(level):
			xp -= threshold_for(level)
			level += 1
			skill_points += 1
			level_up.emit(level)
		if level == MAX_LEVEL:
			xp = 0
		changed.emit()
	return {"levels_gained": level - old_level, "level": level, "xp": xp,
		"skill_points": skill_points, "accepted_xp": accepted}

func spend_skill_points(amount: int = 1) -> bool:
	if amount <= 0 or amount > skill_points:
		return false
	skill_points -= amount
	changed.emit()
	return true

func bonuses() -> Dictionary:
	var growth := level - 1
	return {"health": float(growth * 8), "mana": float(growth * 3),
		"attack": float(growth * 2), "magic": float(growth * 2), "defense": float(growth)}

func snapshot() -> Dictionary:
	return {"version": VERSION, "level": level, "xp": xp, "skill_points": skill_points}

func restore(data: Dictionary) -> bool:
	# Validate before assigning anything; corrupt data must not erase a live character.
	for key in ["version", "level", "xp", "skill_points"]:
		if not _whole_number(data.get(key)):
			return false
	if int(data.version) != VERSION:
		return false
	var next_level := int(clampf(float(data.level), 1.0, float(MAX_LEVEL)))
	var next_xp := 0 if next_level == MAX_LEVEL else int(clampf(float(data.xp), 0.0, float(threshold_for(next_level) - 1)))
	var next_points := int(clampf(float(data.skill_points), 0.0, float(next_level - 1)))
	level = next_level
	xp = next_xp
	skill_points = next_points
	changed.emit()
	return true

func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
