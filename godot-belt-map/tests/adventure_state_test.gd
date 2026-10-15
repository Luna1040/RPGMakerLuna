extends SceneTree
const Adventure = preload("res://systems/adventure/adventure_state.gd")
const Equipment = preload("res://characters/first_knight/equipment.gd")
const Validator = preload("res://systems/adventure/adventure_catalog.gd")
var failures: Array[String] = []
var fixtures: Array[Node] = []

class Wallet extends Node:
	var materials := {"旧铜币": 0, "木料": 0, "碎布": 0, "秘银碎屑": 0}

class Levels extends RefCounted:
	var experience := 0
	func add_xp(amount: int) -> void:
		experience += amount

class Actor extends Node:
	signal stats_changed(health: float, mana: float)
	var health := 100.0
	var mana := 100.0
	var max_health := 100.0
	var max_mana := 100.0
	var defeated := false

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func fixture() -> RefCounted:
	var state := Adventure.new()
	var gear := Equipment.new()
	gear.persistence_enabled = false
	var loot := Wallet.new()
	fixtures.append(loot)
	state.set_up(gear, loot, Levels.new())
	check(state.validation_errors.is_empty(), "shipped catalog validation: " + "; ".join(state.validation_errors))
	return state

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_test_transactions()
	_test_quest_events()
	_test_narrative()
	_test_consumables()
	_test_restore()
	_test_catalog()
	for node: Node in fixtures:
		node.free()
	for message: String in failures:
		push_error(message)
	print("ADVENTURE_STATE_TEST ", "PASS" if failures.is_empty() else "FAIL", " · atomic shop/craft, accepted-only dedupe, exact-once rewards, three narrative paths, potions, save sanitation, graph validation")
	quit(0 if failures.is_empty() else 1)

func _test_transactions() -> void:
	var state = fixture()
	var before: Dictionary = state.snapshot()
	check(not state.buy("healing_potion").ok, "empty wallet purchase succeeded")
	check(state.snapshot() == before and state.loot.materials["旧铜币"] == 0, "failed purchase mutated state")
	state.loot.materials["旧铜币"] = 1000
	check(state.buy("healing_potion", 3).ok, "valid potion purchase failed")
	check(state.consumables.healing_potion == 5 and state.loot.materials["旧铜币"] == 976, "purchase quantity or payment wrong")
	var money: int = state.loot.materials["旧铜币"]
	check(not state.buy("healing_potion", 0).ok and not state.buy("healing_potion", -1).ok and not state.buy("healing_potion", 100).ok, "invalid quantities accepted")
	check(state.loot.materials["旧铜币"] == money, "invalid quantities deducted coins")
	check(state.buy("courtyard_blade").ok, "new equipment purchase failed")
	check(state.equipment.owned.has("courtyard_blade"), "purchase did not grant gear")
	money = state.loot.materials["旧铜币"]
	check(not state.buy("courtyard_blade").ok and state.loot.materials["旧铜币"] == money, "duplicate equipment purchase charged")
	check(not state.buy("courtyard_mail", 2).ok and state.loot.materials["旧铜币"] == money, "multiple unique equipment purchase charged")
	check(not state.craft("forge_courtyard_blade").ok, "duplicate equipment craft accepted")
	state.consumables.healing_potion = 99
	check(not state.buy("healing_potion").ok and state.loot.materials["旧铜币"] == money, "stack limit purchase charged")
	state.loot.materials["碎布"] = 2
	var wallet: Dictionary = state.loot.materials.duplicate()
	check(not state.craft("brew_healing").ok and state.loot.materials == wallet, "stack limit crafting destroyed ingredients")
	state.consumables.healing_potion = 98
	check(state.craft("brew_healing").ok, "valid crafting failed")
	check(state.consumables.healing_potion == 99 and state.loot.materials["碎布"] == 1 and state.loot.materials["旧铜币"] == money - 3, "craft output or materials wrong")
	state.loot.materials["木料"] = 100
	state.loot.materials["秘银碎屑"] = 0
	wallet = state.loot.materials.duplicate()
	check(not state.craft("forge_courtyard_blade").ok and wallet == state.loot.materials, "failed craft partial deduction")
	check(not state.buy("unknown").ok and not state.craft("unknown").ok, "unknown catalog IDs accepted")
	check(state.shop_rows().size() == 5 and state.recipe_rows().size() == 3, "economy UI row count wrong")

func _test_quest_events() -> void:
	var state = fixture()
	state.record_event("enemy_killed", {"id": "before-accept"})
	check(state.accept_quest("courtyard_menace"), "independent menace unavailable")
	check(not state.accept_quest("courtyard_menace"), "duplicate acceptance reset quest")
	check(state.quests.courtyard_menace.counts.is_empty(), "preacceptance kill counted")
	state.record_event("enemy_killed", {"id": "dummy", "training": true})
	state.record_event("enemy_killed", {"id": "one", "amount": 999})
	state.record_event("enemy_killed", {"id": "one"})
	check(state.quests.courtyard_menace.counts.enemies == 1, "duplicate/arbitrary amount kill counted")
	check(not state.claim_quest("courtyard_menace").ok, "incomplete quest claimed")
	state.record_event("enemy_killed", {"id": "two"})
	state.record_event("enemy_killed", {"id": "three"})
	check(state.claim_quest("courtyard_menace").ok, "completed quest claim failed")
	var xp: int = state.progression.experience
	var wallet: Dictionary = state.loot.materials.duplicate()
	check(xp == 65 and state.reputation.smith == 2, "quest reward omitted progression or reputation")
	check(not state.claim_quest("courtyard_menace").ok and state.progression.experience == xp and state.loot.materials == wallet, "duplicate claim minted rewards")
	check(state.accept_quest("clearance_waves"), "independent waves unavailable")
	state.record_event("wave_cleared", {"id": "run1-wave1"})
	state.record_event("wave_cleared", {"id": "run1-wave1"})
	state.record_event("wave_cleared", {"id": "run2-wave1"})
	check(state.quests.clearance_waves.counts.waves == 2, "wave receipts across encounters incorrect")
	check(state.accept_quest("courtyard_provisions"), "provision unavailable")
	state.record_event("crate_destroyed", {"id": "crate1"})
	state.loot.materials["木料"] = 3
	state.loot.materials["碎布"] = 1
	state.consumables.healing_potion = 99
	wallet = state.loot.materials.duplicate()
	check(not state.claim_quest("courtyard_provisions").ok and not state.quests.courtyard_provisions.claimed and state.loot.materials == wallet, "overflow quest reward consumed materials or receipt")
	state.consumables.healing_potion = 2
	check(state.claim_quest("courtyard_provisions").ok, "provision delivery failed")
	check(state.loot.materials["木料"] == 0 and state.loot.materials["碎布"] == 0, "provision materials not consumed")
	check(state.accept_quest("courtyard_finale"), "two independent helps did not converge without route")

func _test_narrative() -> void:
	var state = fixture()
	check(not state.accept_quest("courtyard_finale"), "finale allowed before any narrative route")
	check(state.choose("smith", "trial").action == "request_trial", "training invisibly blocked by story")
	check(state.choose("innkeeper", "ask_ledger").ok, "ledger clue failed")
	check(state.choose("smith", "ask_tracks").ok, "smith clue failed")
	check(state.claim_quest("missing_supplies").ok, "intersecting clue quest did not complete")
	check(state.choose("innkeeper", "route_investigate").ok, "evidence route failed")
	check(state.flags.culprit_exposed and state.routes.supply_resolution == "investigate", "investigation outcome not stored")
	state.loot.materials["旧铜币"] = 100
	state.loot.materials["木料"] = 10
	state.loot.materials["秘银碎屑"] = 10
	var wallet: Dictionary = state.loot.materials.duplicate()
	check(not state.choose("smith", "route_repair").ok and not state.choose("innkeeper", "route_bargain").ok and state.loot.materials == wallet, "exclusive route could be overwritten/charged")
	check(state.accept_quest("courtyard_finale"), "investigation failed to unlock finale")
	state.record_event("boss_killed", {"id": "boss1"})
	check(state.claim_quest("courtyard_finale").ok, "boss finale claim failed")
	check(state.flags.finale_cleared and state.progression.experience == 190, "route-specific XP reward wrong")
	check("守夜人" in str(state.dialogue_for("innkeeper").text), "NPC dialogue ignored conclusion")
	var graph: Dictionary = state.narrative_graph()
	check(graph.nodes.size() == state.catalog.quests.size() + 3 and graph.edges.size() >= 10, "narrative graph missing intersecting routes")
	var selected := 0
	var excluded := 0
	for node: Dictionary in graph.nodes:
		selected += int(node.status == "selected")
		excluded += int(node.status == "excluded")
	check(selected == 1 and excluded == 2, "graph fails to distinguish mutually exclusive outcomes")
	var repair = fixture()
	check(not repair.choose("smith", "route_repair").ok, "repair without materials succeeded")
	repair.loot.materials["木料"] = 3
	repair.loot.materials["秘银碎屑"] = 2
	check(repair.choose("smith", "route_repair").ok and repair.flags.ward_repaired, "repair route did not commit")
	check(repair.loot.materials["木料"] == 0 and repair.loot.materials["秘银碎屑"] == 0 and repair.accept_quest("courtyard_finale"), "repair cost/unlock wrong")
	var bargain = fixture()
	bargain.loot.materials["旧铜币"] = 30
	check(bargain.choose("innkeeper", "route_bargain").ok and bargain.loot.materials["旧铜币"] == 10, "bargain route failed")
	check(bargain.accept_quest("courtyard_provisions"), "provision trade alternate unavailable")
	check(bargain.choose("innkeeper", "provision_procurement").ok and bargain.claim_quest("courtyard_provisions").ok, "consumed crate world cannot use provision alternative")
	check(not bargain.choose("innkeeper", "provision_procurement").ok, "repeat procurement after claim accepted")
	state.reputation.innkeeper = 2
	state.reputation.smith = 2
	check(state.accept_quest("companion_oath"), "trusted companion branch locked")
	check(state.choose("innkeeper", "oath_bond").ok and state.claim_quest("companion_oath").ok, "companion relationship branch failed")

func _test_consumables() -> void:
	var state = fixture()
	var actor := Actor.new()
	fixtures.append(actor)
	check(not state.use_consumable("healing_potion", actor).ok and state.consumables.healing_potion == 2, "full health wasted potion")
	actor.health = 60
	check(state.use_consumable("healing_potion", actor).ok and actor.health == 100 and state.consumables.healing_potion == 1, "potion restore or clamp failed")
	actor.health = 0
	actor.defeated = true
	check(not state.use_consumable("healing_potion", actor).ok and state.consumables.healing_potion == 1, "potion revived fallen actor")
	actor.health = 100
	actor.defeated = false
	actor.mana = 10
	check(state.use_consumable("mana_potion", actor).ok and actor.mana == 55, "mana potion failed")
	check(not state.use_consumable("mana_potion", actor).ok, "empty stack potion succeeded")
	check(not state.use_consumable("unknown", actor).ok, "unknown potion accepted")

func _test_restore() -> void:
	var state = fixture()
	state.accept_quest("courtyard_menace")
	state.record_event("enemy_killed", {"id": "persist-me"})
	state.choose("innkeeper", "ask_ledger")
	var save: Dictionary = state.snapshot()
	var restored = fixture()
	var wallet: Dictionary = restored.loot.materials.duplicate()
	check(restored.restore(save) and restored.snapshot() == save, "snapshot roundtrip differs")
	check(restored.loot.materials == wallet and restored.progression.experience == 0, "restore mutates external world/XP")
	restored.record_event("enemy_killed", {"id": "persist-me"})
	check(restored.quests.courtyard_menace.counts.enemies == 1, "reload allowed duplicate event progress")
	var before: Dictionary = restored.snapshot()
	check(not restored.restore({"version": 900}) and restored.snapshot() == before, "invalid save partially overwrites state")
	save.consumables = {"healing_potion": 1e10, "mana_potion": -20, "unknown": 900}
	save.flags["unknown"] = true
	save.flags.ward_repaired = true
	save.flags.bargain_struck = true
	save.routes.supply_resolution = "investigate"
	save.reputation = {"innkeeper": -900, "smith": "garbage", "hacker": 999}
	save.quests["unknown"] = {"accepted": true, "claimed": true}
	save.quests.courtyard_menace.counts.enemies = 1e10
	check(restored.restore(save), "sanitizable save rejected")
	check(restored.consumables.healing_potion == 99 and restored.consumables.mana_potion == 0 and not restored.consumables.has("unknown"), "consumable restoration not sanitized")
	check(not restored.flags.has("unknown") and not restored.flags.ward_repaired and not restored.flags.bargain_struck and restored.flags.culprit_exposed, "route flags restoration contradictory")
	check(restored.reputation.innkeeper == -100 and restored.reputation.smith == 0 and not restored.reputation.has("hacker"), "reputation restoration unsafe")
	check(not restored.quests.has("unknown") and restored.quests.courtyard_menace.counts.enemies == 3, "quest restoration not sanitized")
	check(restored.claim_quest("courtyard_menace").ok, "restored ready quest cannot claim")
	var claimed: Dictionary = restored.snapshot()
	var final = fixture()
	check(final.restore(claimed) and not final.claim_quest("courtyard_menace").ok and final.progression.experience == 0, "claimed quest duplicated after load")

func _test_catalog() -> void:
	var state = fixture()
	var equipment_catalog: Dictionary = Equipment.new().CATALOG
	var data: Dictionary = state.catalog.duplicate(true)
	data.quests[0].requires = {"quest": {"id": "courtyard_menace", "status": ["claimed"]}}
	data.quests[1].requires = {"quest": {"id": "courtyard_provisions", "status": ["claimed"]}}
	check(not Validator.validate(data, equipment_catalog).is_empty(), "prerequisite cycle accepted")
	data = state.catalog.duplicate(true)
	data.graph_edges.append({"from": "nonexistent", "to": "courtyard_provisions"})
	check(not Validator.validate(data, equipment_catalog).is_empty(), "unknown graph reference accepted")
	data = state.catalog.duplicate(true)
	data.shop[0].cost["旧铜币"] = -8
	check(not Validator.validate(data, equipment_catalog).is_empty(), "negative catalog cost accepted")
	data = state.catalog.duplicate(true)
	data.npcs.smith.choices[0].when = {"surprise": true}
	check(not Validator.validate(data, equipment_catalog).is_empty(), "unknown condition treated as true")
	data = state.catalog.duplicate(true)
	data.quests[0].route_rewards = []
	data.npcs.smith.choices[0].effects = {"flags": []}
	data.quests[0].position = "not-a-position"
	check(not Validator.validate(data, equipment_catalog).is_empty(), "malformed nested catalog accepted")
	data = state.catalog.duplicate(true)
	data.routes.supply_resolution = "wrong-type"
	check(not Validator.validate(data, equipment_catalog).is_empty(), "malformed route catalog accepted")
