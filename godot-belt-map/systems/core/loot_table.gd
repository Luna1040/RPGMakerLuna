extends RefCounted
## Supplied RNG only: preserve rng.state alongside the save/run seed for reproducibility.
## Currency/material IDs intentionally match the existing courtyard inventory.
const DEFAULT_TABLES := {
	"crate": {"guaranteed": [
		{"kind": "currency", "id": "旧铜币", "min": 2, "max": 6},
		{"kind": "material", "id": "木料", "min": 1, "max": 3}],
		"rolls": 1, "chance": 0.75, "pool": [
			{"kind": "material", "id": "碎布", "min": 1, "max": 2, "weight": 50.0},
			{"kind": "material", "id": "木料", "min": 1, "max": 2, "weight": 50.0}]},
	"enemy": {"guaranteed": [{"kind": "currency", "id": "旧铜币", "min": 4, "max": 10}],
		"rolls": 1, "chance": 0.35, "pool": [
			{"kind": "material", "id": "碎布", "min": 1, "max": 3, "weight": 70.0},
			{"kind": "material", "id": "秘银碎屑", "min": 1, "max": 1, "weight": 20.0},
			{"kind": "equipment", "id": "edge_sword", "min": 1, "max": 1, "weight": 7.0},
			{"kind": "equipment", "id": "wind_boots", "min": 1, "max": 1, "weight": 3.0}]},
	"elite": {"guaranteed": [
		{"kind": "currency", "id": "旧铜币", "min": 20, "max": 35},
		{"kind": "material", "id": "秘银碎屑", "min": 1, "max": 3}],
		"rolls": 1, "chance": 1.0, "pool": [
			{"kind": "equipment", "id": "arcane_sword", "min": 1, "max": 1, "weight": 35.0},
			{"kind": "equipment", "id": "guardian_armor", "min": 1, "max": 1, "weight": 35.0},
			{"kind": "equipment", "id": "storm_charm", "min": 1, "max": 1, "weight": 30.0}]},
	"chest": {"guaranteed": [{"kind": "currency", "id": "旧铜币", "min": 25, "max": 60}],
		"rolls": 2, "chance": 1.0, "pool": [
			{"kind": "equipment", "id": "courtyard_blade", "min": 1, "max": 1, "weight": 30.0},
			{"kind": "equipment", "id": "courtyard_mail", "min": 1, "max": 1, "weight": 30.0},
			{"kind": "equipment", "id": "courtyard_charm", "min": 1, "max": 1, "weight": 25.0},
			{"kind": "equipment", "id": "steel_boots", "min": 1, "max": 1, "weight": 15.0}]}
}
var tables: Dictionary = DEFAULT_TABLES.duplicate(true)
var last_error := ""

func register_table(id: String, definition: Dictionary) -> bool:
	last_error = ""
	if id.is_empty() or not _valid_table(definition):
		last_error = "Invalid loot table."
		return false
	tables[id] = definition.duplicate(true)
	return true

func roll(table_id: String, rng: RandomNumberGenerator) -> Array:
	last_error = ""
	var result: Array = []
	if rng == null or not tables.has(table_id) or not _valid_table(tables[table_id]):
		last_error = "Unknown/invalid loot table or missing RNG."
		return result
	var table: Dictionary = tables[table_id]
	for entry: Dictionary in table.get("guaranteed", []):
		_append_drop(result, entry, rng)
	for _index in int(table.get("rolls", 0)):
		var chance := float(table.get("chance", 1.0))
		if chance <= 0.0 or (chance < 1.0 and rng.randf() >= chance):
			continue
		var entry := weighted_pick(table.pool, rng)
		_append_drop(result, entry, rng)
	return result

func weighted_pick(entries: Array, rng: RandomNumberGenerator) -> Dictionary:
	if rng == null or entries.is_empty():
		return {}
	var total := 0.0
	for entry in entries:
		if not entry is Dictionary or not _valid_entry(entry, true):
			return {}
		total += float(entry.weight)
	if not is_finite(total) or total <= 0:
		return {}
	var selected := rng.randf() * total
	var fallback: Dictionary = {}
	for entry: Dictionary in entries:
		if float(entry.weight) <= 0:
			continue
		fallback = entry
		selected -= float(entry.weight)
		if selected < 0:
			return entry.duplicate(true)
	return fallback.duplicate(true)

func _append_drop(result: Array, entry: Dictionary, rng: RandomNumberGenerator) -> void:
	if entry.is_empty() or entry.kind == "none":
		return
	var amount := rng.randi_range(int(entry.min), int(entry.max))
	if amount <= 0:
		return
	for existing: Dictionary in result:
		if existing.kind == entry.kind and existing.id == entry.id:
			existing.amount += amount
			return
	result.append({"kind": entry.kind, "id": entry.id, "amount": amount})

func _valid_table(table: Dictionary) -> bool:
	if not table.get("guaranteed", []) is Array or not table.get("pool", []) is Array:
		return false
	if not _whole_number(table.get("rolls", 0)) or float(table.get("rolls", 0)) < 0 or float(table.get("rolls", 0)) > 100:
		return false
	if not _number(table.get("chance", 1.0)) or float(table.get("chance", 1.0)) < 0 or float(table.get("chance", 1.0)) > 1:
		return false
	if table.get("guaranteed", []).size() > 100 or table.get("pool", []).size() > 1000:
		return false
	for entry in table.get("guaranteed", []):
		if not entry is Dictionary or not _valid_entry(entry, false):
			return false
	var total := 0.0
	for entry in table.get("pool", []):
		if not entry is Dictionary or not _valid_entry(entry, true):
			return false
		total += float(entry.weight)
	return is_finite(total) and (int(table.get("rolls", 0)) == 0 or total > 0)

func _valid_entry(entry: Dictionary, weighted: bool) -> bool:
	if not entry.get("kind") is String or not ["currency", "material", "equipment", "none"].has(entry.kind):
		return false
	if weighted and (not _number(entry.get("weight")) or float(entry.weight) < 0 or float(entry.weight) > 1000000000):
		return false
	if entry.kind == "none":
		return true
	if not entry.get("id") is String or str(entry.id).is_empty():
		return false
	if not _whole_number(entry.get("min")) or not _whole_number(entry.get("max")):
		return false
	if float(entry.min) < 0 or float(entry.max) < float(entry.min) or float(entry.max) > 1000000:
		return false
	return entry.kind != "equipment" or (int(entry.min) == 1 and int(entry.max) == 1)

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _whole_number(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))
