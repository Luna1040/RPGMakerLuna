extends RefCounted
## Scene-independent effects. Call step once per simulation tick, then apply its events.
## DOT potency is damage PER TICK PER STACK; slow is a 0..0.9 fraction; shield is HP.
const VERSION := 1
const MAX_DURATION := 3600.0
const MAX_POTENCY := 1000000.0
const DEFINITIONS := {
	"slow": {"max_stacks": 1, "interval": 0.0},
	"stun": {"max_stacks": 1, "interval": 0.0},
	"shock": {"max_stacks": 3, "interval": 1.0},
	"burn": {"max_stacks": 5, "interval": 0.5},
	"bleed": {"max_stacks": 5, "interval": 1.0},
	"shield": {"max_stacks": 1, "interval": 0.0}
}
var effects: Dictionary = {}

func apply(id: String, duration: float, potency: float = 1.0, source: String = "") -> bool:
	if not DEFINITIONS.has(id) or not is_finite(duration) or not is_finite(potency) or duration <= 0 or potency < 0:
		return false
	duration = minf(duration, MAX_DURATION)
	potency = minf(potency, 0.9 if id == "slow" else MAX_POTENCY)
	if effects.has(id):
		var current: Dictionary = effects[id]
		current.remaining = maxf(current.remaining, duration)
		current.potency = maxf(current.potency, potency)
		current.stacks = mini(int(current.stacks) + 1, int(DEFINITIONS[id].max_stacks))
		current.source = source.left(128)
		if id == "shield":
			current.shield_left = maxf(float(current.shield_left), potency)
	else:
		effects[id] = {"id": id, "remaining": duration, "potency": potency, "stacks": 1,
			"tick_elapsed": 0.0, "source": source.left(128), "shield_left": potency if id == "shield" else 0.0}
	return true

func step(delta: float) -> Array:
	var events: Array = []
	if not is_finite(delta) or delta <= 0:
		return events
	var ids := effects.keys()
	ids.sort()
	for id: String in ids:
		var effect: Dictionary = effects[id]
		var active_time := minf(delta, float(effect.remaining))
		var interval := float(DEFINITIONS[id].interval)
		if interval > 0:
			var elapsed := float(effect.tick_elapsed) + active_time
			# Aggregate catch-up ticks so a long frame cannot cause an unbounded event burst.
			var ticks := int(floorf((elapsed + 0.00000001) / interval))
			effect.tick_elapsed = maxf(0.0, elapsed - ticks * interval)
			if ticks > 0 and float(effect.potency) > 0:
				events.append({"type": "damage", "effect": id, "amount": float(effect.potency) * int(effect.stacks) * ticks,
					"ticks": ticks, "stacks": int(effect.stacks), "source": effect.source})
		effect.remaining = maxf(0.0, float(effect.remaining) - delta)
		if float(effect.remaining) <= 0.00000001:
			effects.erase(id)
			events.append({"type": "expired", "effect": id, "source": effect.source})
	return events

func cleanse(id: String = "") -> int:
	if id.is_empty():
		var count := effects.size()
		effects.clear()
		return count
	return 1 if effects.erase(id) else 0

func has(id: String) -> bool:
	return effects.has(id)

func is_stunned() -> bool:
	return has("stun")

func movement_multiplier() -> float:
	if is_stunned():
		return 0.0
	return 1.0 - float(effects.slow.potency) if has("slow") else 1.0

func absorb_damage(amount: float) -> float:
	## Returns damage still to be applied to HP after shield absorption.
	if not is_finite(amount) or amount <= 0:
		return 0.0
	if not has("shield"):
		return amount
	var consumed := minf(amount, float(effects.shield.shield_left))
	effects.shield.shield_left -= consumed
	if float(effects.shield.shield_left) <= 0:
		effects.erase("shield")
	return amount - consumed

func snapshot() -> Dictionary:
	var entries: Array = []
	var ids := effects.keys()
	ids.sort()
	for id in ids:
		entries.append(effects[id].duplicate(true))
	return {"version": VERSION, "effects": entries}

func restore(data: Dictionary) -> bool:
	if not _number(data.get("version")) or float(data.version) != VERSION or not data.get("effects") is Array:
		return false
	if data.effects.size() > DEFINITIONS.size():
		return false
	var restored := {}
	for entry in data.effects:
		if not entry is Dictionary or not entry.get("id") is String:
			return false
		var id: String = entry.id
		if not DEFINITIONS.has(id) or restored.has(id):
			return false
		for key in ["remaining", "potency", "stacks", "tick_elapsed", "shield_left"]:
			if not _number(entry.get(key)):
				return false
		if not entry.get("source") is String:
			return false
		if float(entry.remaining) <= 0:
			continue
		var interval := float(DEFINITIONS[id].interval)
		var potency := clampf(float(entry.potency), 0.0, 0.9 if id == "slow" else MAX_POTENCY)
		restored[id] = {"id": id, "remaining": minf(float(entry.remaining), MAX_DURATION),
			"potency": potency, "stacks": int(clampf(float(entry.stacks), 1.0, float(DEFINITIONS[id].max_stacks))),
			"tick_elapsed": clampf(float(entry.tick_elapsed), 0.0, maxf(0.0, interval - 0.0000001)),
			"source": str(entry.source).left(128), "shield_left": clampf(float(entry.shield_left), 0.0, potency) if id == "shield" else 0.0}
		if id == "shield" and float(restored[id].shield_left) <= 0:
			restored.erase(id)
	effects = restored
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
