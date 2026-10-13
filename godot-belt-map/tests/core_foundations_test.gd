extends SceneTree
const SaveStore = preload("res://systems/core/save_store.gd")
const Progression = preload("res://systems/core/progression.gd")
const StatusEffects = preload("res://systems/core/status_effects.gd")
const LootTable = preload("res://systems/core/loot_table.gd")
const Gear = preload("res://characters/first_knight/equipment.gd")
var checks := 0
var failures := 0
var scratch := ""

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	scratch = "user://core_test_%d_%d" % [Time.get_ticks_usec(), OS.get_process_id()]
	test_saves()
	test_progression()
	test_statuses()
	test_loot()
	cleanup()
	print("CORE_FOUNDATIONS_TEST %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	verify(file != null, "Test fixture could not be written: " + path)
	if file != null:
		file.store_string(content)
		file.close()

func test_saves() -> void:
	var store := SaveStore.new(scratch)
	verify(store.list_slots().size() == 3, "Slot listing must always expose three slots")
	verify(not store.load_slot(1).ok, "Missing slot unexpectedly loads")
	verify(not store.save_slot(0, {}) and not store.save_slot(4, {}), "Out-of-range slots accepted")
	var payload := {"name": "苍石骑士", "level": 3, "position": [1.25, 5.0], "flags": {"quest": true}, "empty": null}
	verify(store.save_slot(1, payload), "Initial save failed: " + store.last_error)
	var first := store.load_slot(1)
	verify(first.ok and not first.recovered and first.data == JSON.parse_string(JSON.stringify(payload)), "Save round-trip corrupted values")
	verify(first.metadata.slot == 1 and first.metadata.version == 1 and first.metadata.created_at > 0, "Save metadata missing")
	first.data.flags.quest = false
	verify(store.load_slot(1).data.flags.quest, "Returned save data aliases persistent contents")
	var updated := payload.duplicate(true)
	updated.level = 4
	verify(store.save_slot(1, updated), "Second save could not replace existing primary/backup")
	updated.level = 5
	verify(store.save_slot(1, updated), "Third save could not replace an existing backup")
	verify(store.load_slot(1).data.level == 5, "Latest primary was not committed")
	var original_primary := FileAccess.get_file_as_string(store.slot_path(1))
	var original_backup := FileAccess.get_file_as_string(store.slot_path(1) + ".bak")
	write_text(store.slot_path(1), "{truncated")
	var recovered := store.load_slot(1)
	verify(recovered.ok and recovered.recovered and recovered.data.level == 4, "Corrupt primary did not recover the last valid backup")
	verify(FileAccess.get_file_as_string(store.slot_path(1)) == "{truncated", "Load unexpectedly rewrote a damaged file")
	verify(store.save_slot(1, updated), "Recovered slot cannot be saved")
	verify(FileAccess.get_file_as_string(store.slot_path(1) + ".bak") == original_backup, "Recovery replaced a good backup with corrupt data")
	verify(store.load_slot(1).ok, "Recovered save did not produce a valid primary")
	var unsupported: Dictionary = JSON.parse_string(original_primary)
	unsupported.version = 999
	var unsupported_text := JSON.stringify(unsupported)
	write_text(store.slot_path(1), unsupported_text)
	verify(not store.load_slot(1).ok, "Future primary incorrectly rolled back to an older backup")
	verify(not store.save_slot(1, {}), "Failed load allowed autosave to erase a future save")
	verify(FileAccess.get_file_as_string(store.slot_path(1)) == unsupported_text, "Future save changed after a failed operation")
	write_text(store.slot_path(1), original_primary)
	verify(store.load_slot(1).ok and store.save_slot(1, updated), "Successful repaired load did not unlock slot")
	verify(not store.save_slot(2, {"value": NAN}), "Nonfinite numbers accepted")
	verify(not store.save_slot(2, {"value": Vector2.ONE}), "Non-JSON native values accepted")
	verify(not store.save_slot(2, {"rng_state": 9223372036854775807}), "64-bit integers that lose JSON precision accepted")
	verify(not store.save_slot(2, {5: "integer-key"}), "Non-string JSON keys accepted")
	var recursive := {}
	recursive["self"] = recursive
	verify(not store.save_slot(2, recursive), "Recursive JSON payload accepted")
	recursive.clear()
	verify(store.save_slot(2, {"health": 100}), "Independent second slot failed")
	var tampered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.slot_path(2)))
	tampered.data.health = 999
	write_text(store.slot_path(2), JSON.stringify(tampered))
	verify(not store.load_slot(2).ok, "Checksum tampering was not detected")
	verify(not store.save_slot(2, {"health": 0}), "Failed corrupt load was overwritten by defaults")
	verify(not SaveStore.new(scratch).save_slot(2, {}), "Fresh store overwrote corrupt data without a good backup")
	write_text(store.slot_path(3), "[]")
	verify(not store.load_slot(3).ok, "Non-object JSON root accepted")
	var slots := store.list_slots()
	verify(slots[0].ok and not slots[1].ok and not slots[2].ok, "Slot listing obscures corrupt slots")
	verify(not FileAccess.file_exists(scratch.path_join("slot_0.json")), "Invalid slot created a file")
	verify(store.protect_slot(1, "Invalid character schema"), "Semantic load failure could not protect valid envelope")
	verify(not store.save_slot(1, {}) and store.last_error.contains("Invalid character schema"), "Semantic failure protection did not prevent autosave")
	verify(not store.protect_slot(0), "Invalid protection slot accepted")
	verify(store.load_slot(1).ok and store.save_slot(1, updated), "Successful new load did not clear semantic protection")
	# Simulate power loss between primary rename operations: a backup alone is loadable.
	DirAccess.remove_absolute(store.slot_path(1))
	verify(store.load_slot(1).ok and store.load_slot(1).recovered, "Missing primary did not recover existing backup")

func test_progression() -> void:
	var progress := Progression.new()
	verify(progress.level == 1 and progress.xp_to_next() == 100, "Initial progression invalid")
	verify(progress.bonuses().health == 0 and progress.bonuses().attack == 0, "Initial level grants unintended bonuses")
	verify(progress.add_xp(-10).accepted_xp == 0 and progress.xp == 0, "Negative XP changed progression")
	verify(progress.add_xp(99).levels_gained == 0 and progress.xp == 99, "Premature level-up")
	verify(progress.add_xp(1).levels_gained == 1 and progress.level == 2 and progress.xp == 0, "Exact XP threshold missed")
	verify(progress.skill_points == 1 and progress.bonuses().health == 8, "Level stats/skill points missing")
	verify(progress.add_xp(380).levels_gained == 2 and progress.level == 4 and progress.xp == 10, "Multiple level-ups did not retain remainder")
	verify(progress.spend_skill_points(2) and progress.skill_points == 1, "Skill point spending failed")
	verify(not progress.spend_skill_points(2) and not progress.spend_skill_points(-1), "Overspending/negative spending accepted")
	var saved := progress.snapshot()
	var copy := Progression.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(saved))) and copy.snapshot() == saved, "Progression JSON round-trip failed")
	verify(not copy.restore({"version": 999, "level": 3, "xp": 1, "skill_points": 1}) and copy.snapshot() == saved, "Invalid restore altered live progression")
	verify(not copy.restore({"version": 1, "level": "3", "xp": 1, "skill_points": 1}), "Wrong field type accepted")
	verify(copy.restore({"version": 1, "level": -2, "xp": -90, "skill_points": 999}) and copy.level == 1 and copy.xp == 0 and copy.skill_points == 0, "Negative/over-awarded progression not sanitized")
	verify(copy.restore({"version": 1, "level": 5, "xp": 999999, "skill_points": 999}) and copy.xp < copy.xp_to_next() and copy.skill_points == 4, "Corrupt XP/points exceed level limits")
	progress.add_xp(1000000000)
	verify(progress.level == Progression.MAX_LEVEL and progress.xp == 0 and progress.xp_to_next() == 0, "Progression level cap failed")
	var cap := progress.snapshot()
	verify(progress.add_xp(20).accepted_xp == 0 and progress.snapshot() == cap, "XP at cap produces rewards")

func damage_total(events: Array) -> float:
	var total := 0.0
	for event: Dictionary in events:
		if event.type == "damage":
			total += float(event.amount)
	return total

func test_statuses() -> void:
	var status := StatusEffects.new()
	verify(not status.apply("unknown", 1) and not status.apply("slow", NAN) and not status.apply("burn", 1, -1), "Invalid status parameters accepted")
	verify(status.apply("slow", 2, 0.3) and is_equal_approx(status.movement_multiplier(), 0.7), "Slow multiplier incorrect")
	status.apply("slow", 1, 0.1)
	verify(is_equal_approx(status.movement_multiplier(), 0.7) and status.effects.slow.remaining == 2, "Weaker refresh shortened/overrode slow")
	status.apply("stun", 0.25)
	verify(status.is_stunned() and status.movement_multiplier() == 0, "Stun does not block movement")
	status.step(0.25)
	verify(not status.is_stunned() and status.has("slow"), "Effect lifetimes not independent")
	verify(status.cleanse("slow") == 1 and status.cleanse("slow") == 0, "Targeted cleanse return value incorrect")
	status.apply("burn", 1.5, 4, "test")
	verify(damage_total(status.step(0.25)) == 0, "DOT ticks before its interval")
	status.apply("burn", 1.5, 4, "test")
	verify(damage_total(status.step(0.25)) == 8, "Reapplying DOT reset its tick phase or lost stacks")
	for _i in 10:
		status.apply("burn", 1.5, 4, "test")
	verify(status.effects.burn.stacks == 5, "Burn stack cap not enforced")
	var final_events := status.step(10000)
	verify(damage_total(final_events) == 60 and not status.has("burn"), "Large delta DOT catch-up exceeded lifetime or lost ticks")
	verify(final_events.size() == 2 and final_events[0].ticks == 3 and final_events[1].type == "expired", "DOT catch-up should aggregate before expiration")
	status.apply("shield", 10, 100)
	verify(status.absorb_damage(30) == 0 and status.effects.shield.shield_left == 70, "Shield absorption incorrect")
	status.apply("shield", 1, 50)
	verify(status.effects.shield.shield_left == 70, "Weaker shield discarded remaining protection")
	verify(status.absorb_damage(90) == 20 and not status.has("shield"), "Depleted shield did not forward remaining damage")
	status.apply("shock", 3, 5, "mage")
	status.apply("bleed", 3, 2, "knight")
	status.step(0.4)
	var saved := status.snapshot()
	var restored := StatusEffects.new()
	verify(restored.restore(JSON.parse_string(JSON.stringify(saved))), "Status JSON restore failed")
	verify(status.step(3) == restored.step(3), "Resumed DOT timers differ from uninterrupted simulation")
	var one_step := StatusEffects.new()
	var many_steps := StatusEffects.new()
	one_step.apply("burn", 2.0, 5)
	many_steps.apply("burn", 2.0, 5)
	var partitioned := 0.0
	for _i in 20:
		partitioned += damage_total(many_steps.step(0.1))
	verify(is_equal_approx(partitioned, damage_total(one_step.step(2.0))), "DOT damage depends on frame partitioning")
	restored.apply("slow", 10, 0.5)
	var before := restored.snapshot()
	verify(not restored.restore({"version": 1, "effects": [{"id": "burn", "remaining": "oops"}]}) and restored.snapshot() == before, "Failed status restore replaced active effects")
	verify(restored.step(NAN).is_empty() and restored.snapshot() == before, "Nonfinite delta corrupts effect state")
	verify(restored.cleanse() == 1 and restored.effects.is_empty(), "Cleanse-all failed")

func test_loot() -> void:
	var loot := LootTable.new()
	var equipment_catalog: Dictionary = Gear.new().CATALOG
	var left := RandomNumberGenerator.new()
	var right := RandomNumberGenerator.new()
	left.seed = 102410
	right.seed = 102410
	for table_id in ["crate", "enemy", "elite", "chest"]:
		for _i in 30:
			var rolled := loot.roll(table_id, left)
			verify(rolled == loot.roll(table_id, right), "Seeded loot is nondeterministic: " + table_id)
			for entry: Dictionary in rolled:
				verify(entry.amount > 0, "Loot quantity is not positive")
				if entry.kind == "equipment":
					verify(equipment_catalog.has(entry.id), "Loot equipment ID not in game catalog")
	var state_before := left.state
	verify(loot.roll("unknown", left).is_empty() and left.state == state_before, "Invalid loot table consumes RNG")
	verify(loot.roll("enemy", null).is_empty(), "Null RNG accepted")
	var single := {"guaranteed": [], "rolls": 3, "chance": 1.0, "pool": [
		{"kind": "material", "id": "wood", "min": 2, "max": 2, "weight": 1.0},
		{"kind": "material", "id": "never", "min": 1, "max": 1, "weight": 0.0}]}
	verify(loot.register_table("custom", single), "Custom valid loot table rejected")
	var fixed := loot.roll("custom", left)
	verify(fixed.size() == 1 and fixed[0].id == "wood" and fixed[0].amount == 6, "Weighted zero entry selected or duplicate drops not merged")
	single.pool[0].weight = 0.0
	verify(loot.roll("custom", left) == fixed, "Loot table shares mutable caller data")
	verify(not loot.register_table("bad", single), "Zero-total weighted table accepted")
	verify(not loot.register_table("bad", {"rolls": 1, "chance": NAN}), "Nonfinite chance accepted")
	verify(not loot.register_table("bad", {"guaranteed": [{"kind": "currency", "id": "gold", "min": 5, "max": 1}]}), "Reversed quantity bounds accepted")
	verify(loot.register_table("empty", {"rolls": 1, "chance": 0.0, "pool": [{"kind": "none", "weight": 1.0}]}), "Valid zero-chance table rejected")
	state_before = left.state
	verify(loot.roll("empty", left).is_empty() and left.state == state_before, "Zero chance consumes RNG or drops loot")
	# String state storage survives JSON's floating-point numeric representation.
	var persisted: Dictionary = JSON.parse_string(JSON.stringify({"state": str(left.state)}))
	var continuation := RandomNumberGenerator.new()
	continuation.state = int(persisted.state)
	verify(loot.roll("chest", continuation) == loot.roll("chest", left), "Restored RNG state diverges")

func cleanup() -> void:
	# Only files created by this test, beneath this exact unique user:// directory.
	for slot in range(1, 4):
		for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
			var path := scratch.path_join("slot_%d.json%s" % [slot, suffix])
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(scratch)
