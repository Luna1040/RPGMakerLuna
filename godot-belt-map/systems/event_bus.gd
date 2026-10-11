extends RefCounted
## Single event vocabulary; the bounded trace is useful for quests and diagnostics.
signal event_emitted(kind: String, payload: Dictionary)
const KINDS := ["crate_destroyed", "material_collected", "chest_opened", "enemy_killed", "boss_killed", "wave_cleared", "quest_claimed", "equipment_changed", "player_died", "zone_entered", "saved", "loaded"]
var trace: Array[Dictionary] = []
var sequence := 0

func publish(kind: String, payload: Dictionary = {}) -> bool:
	if kind not in KINDS:
		return false
	sequence += 1
	var event := payload.duplicate(true)
	event["sequence"] = sequence
	trace.append({"kind":kind, "data":event.duplicate(true)})
	if trace.size() > 120:
		trace.pop_front()
	event_emitted.emit(kind, event)
	return true
