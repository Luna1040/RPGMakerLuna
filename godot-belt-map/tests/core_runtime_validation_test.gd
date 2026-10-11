extends SceneTree
## Runtime validation audit uses minimal inventory fixtures and never loads a map/save.
const Runtime = preload("res://systems/game_runtime.gd")
const TalentTree = preload("res://systems/core/talent_tree.gd")
var checks := 0
var failures := 0
var runtime

class KnightFixture extends RefCounted:
	var equipment = preload("res://characters/first_knight/equipment.gd").new()

class LootFixture extends Node:
	var materials := {"木料": 0, "碎布": 0, "旧铜币": 0, "秘银碎屑": 0}

class StageFixture extends RefCounted:
	var knight = KnightFixture.new()
	var loot = LootFixture.new()

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func reject(data: Dictionary, reason: String) -> void:
	verify(not runtime.validate_snapshot(data), "Runtime accepted invalid snapshot: " + reason)

func run() -> void:
	runtime = Runtime.new()
	runtime.stage = StageFixture.new()
	runtime.stage.knight.equipment.persistence_enabled = false
	runtime.adventure.set_up(runtime.stage.knight.equipment, runtime.stage.loot, runtime.progression)
	# Parent otherwise detached child nodes so fixture destruction cannot leak them.
	runtime.add_child(runtime.audio)
	runtime.add_child(runtime.encounters)
	runtime.add_child(runtime.stage.loot)
	runtime.encounters.add_child(runtime.encounters.companion_root)
	runtime.encounters.companion_root.add_child(runtime.encounters.companion_sprite)
	runtime.encounters.companion_root.add_child(runtime.encounters.companion_label)
	var gear = runtime.stage.knight.equipment
	var baseline := {"schema": 1, "zone": "town", "worlds": {"town": {"broken": [], "opened": [], "drops": []}},
		"player": {"foot": [3.0, 4.0], "height": 0.0, "health": 100.0, "mana": 100.0, "facing": 1},
		"equipment": {"owned": gear.owned.duplicate(), "equipped": gear.equipped.duplicate()},
		"materials": runtime.stage.loot.materials.duplicate(), "progression": runtime.progression.snapshot(),
		"talents": TalentTree.new().snapshot(), "adventure": runtime.adventure.snapshot(),
		"run": {"phase": "none", "wave": 0, "seed": 1, "boons": [], "offers": []},
		"companion": {"recruited": false, "mode": "follow"}, "play_seconds": 0.0,
		"run_counter": 0, "slot": 1, "autosave_armed": false}
	verify(runtime.validate_snapshot(baseline), "Valid baseline snapshot rejected")
	verify(runtime.validate_snapshot(JSON.parse_string(JSON.stringify(baseline))), "JSON-decoded baseline snapshot rejected")
	var malformed: Dictionary = baseline.duplicate(true)
	malformed.equipment.equipped["extra_weapon"] = "edge_sword"
	reject(malformed, "extra equipment slot grants stacked bonuses")
	malformed = baseline.duplicate(true)
	malformed.equipment.equipped.erase("boots")
	reject(malformed, "missing slot breaks later equip")
	malformed = baseline.duplicate(true)
	malformed.equipment.owned.append(malformed.equipment.owned[0])
	reject(malformed, "duplicate ownership")
	malformed = baseline.duplicate(true)
	malformed.equipment.equipped.weapon = "knight_armor"
	reject(malformed, "armor in weapon slot")
	malformed = baseline.duplicate(true)
	malformed.materials["旧铜币"] = 1.5
	reject(malformed, "fractional currency")
	malformed = baseline.duplicate(true)
	malformed.run.seed = "1"
	reject(malformed, "string run seed")
	malformed = baseline.duplicate(true)
	malformed.run.wave = 0.5
	reject(malformed, "fractional wave")
	malformed = baseline.duplicate(true)
	malformed.player.facing = 0
	reject(malformed, "zero facing")
	malformed = baseline.duplicate(true)
	malformed.player.health = -20
	reject(malformed, "negative saved health")
	malformed = baseline.duplicate(true)
	malformed.player.mana = INF
	reject(malformed, "nonfinite saved mana")
	malformed = baseline.duplicate(true)
	malformed.play_seconds = NAN
	reject(malformed, "nonfinite play time")
	malformed = baseline.duplicate(true)
	malformed.companion.recruited = "false"
	reject(malformed, "string recruited flag")
	malformed = baseline.duplicate(true)
	malformed.worlds.town.drops.append({"id": "旧铜币", "amount": [], "equipment": false, "foot": [3, 4]})
	reject(malformed, "non-numeric drop amount")
	malformed = baseline.duplicate(true)
	malformed.worlds.town.drops.append({"id": "unknown", "amount": 1, "equipment": true, "foot": [3, 4]})
	reject(malformed, "unknown drop ID")
	malformed = baseline.duplicate(true)
	malformed.schema = "1"
	reject(malformed, "string schema accepted by int coercion")
	malformed = baseline.duplicate(true)
	malformed.talents.ranks.blade_training = 1
	reject(malformed, "level one has an unearned talent point")
	malformed = baseline.duplicate(true)
	malformed.progression.level = 2
	malformed.progression.skill_points = 1
	malformed.talents.ranks.blade_training = 1
	reject(malformed, "earned point exists both in balance and talent tree")
	malformed.progression.skill_points = 0
	verify(runtime.validate_snapshot(malformed), "Valid spent talent point is rejected")
	var old_save: Dictionary = baseline.duplicate(true)
	old_save.erase("talents")
	verify(runtime.validate_snapshot(old_save), "Unspent legacy snapshot cannot migrate to an empty talent tree")
	verify(gear.equipped == baseline.equipment.equipped and gear.owned == baseline.equipment.owned and runtime.progression.level == 1, "Validation changed live character state")
	runtime.free()
	print("CORE_RUNTIME_VALIDATION_TEST %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
