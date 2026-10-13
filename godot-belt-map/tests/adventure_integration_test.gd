extends SceneTree
## Exercises the real stage, NPC buttons, loot signals, encounter deaths and save envelope.
var failures: Array[String] = []
var stage

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child: Node in node.get_children():
		var found := find_button(child, text)
		if found != null:
			return found
	return null

func click(text: String) -> void:
	var button := find_button(stage.runtime.panel.overlay, text)
	check(button != null, "NPC/menu button missing: " + text)
	if button != null:
		check(not button.disabled, "NPC/menu button disabled: " + text)
		if not button.disabled:
			button.pressed.emit()

func click_choice(id: String) -> void:
	var view=stage.runtime.panel.dialogue_view
	while not view.at_choices: view.advance()
	# Exercise topic, paced dialogue, then explicit confirmation.
	var dialogue:Dictionary=stage.runtime.adventure.dialogue_for(stage.runtime.panel.npc_id)
	for choice:Dictionary in dialogue.get("choices",[]):
		if choice.id==id:
			check(bool(choice.get("enabled",true)),"Required dialogue choice unavailable: "+id)
			var label:String=str(choice.label)
			if not bool(choice.get("enabled",true)): label+=" · "+str(choice.get("reason",""))
			click(label)
			while not view.at_choices: view.advance()
			click("确认 · "+str(choice.label))
			return
	check(false,"Current NPC has no visible dialogue choice: "+id)

func npc(id: String) -> void:
	for resident: Dictionary in stage.townsfolk.residents:
		if resident.id == id:
			stage.runtime.open_npc(resident)
			check(stage.runtime.panel.is_open() and stage.runtime.panel.tab == "dialogue", "NPC interaction failed to open real modal")
			return
	check(false, "missing actual town resident: " + id)

func run() -> void:
	stage = load("res://stage.tscn").instantiate()
	root.add_child(stage)
	stage.set_physics_process(false)
	stage.testing_motion = true
	if stage.runtime == null:
		push_error("Run with -- --foundations so this tests the integrated runtime.")
		quit(1)
		return
	var runtime = stage.runtime
	runtime.persistence_enabled = false
	check(not runtime.panel.is_open(), "new town starts behind a modal")
	check(stage.loot.materials["旧铜币"] == 30, "new-game wallet missing")
	check(not runtime.companion_recruited and not runtime.encounters.companion_enabled, "unearned companion spawned")
	var initial: Dictionary = runtime.snapshot()

	# Choose real rendered NPC buttons, not merely service methods.
	npc("innkeeper")
	click_choice("provision_order")
	click_choice("ask_ledger")
	check(runtime.adventure.flags.supply_hint, "innkeeper clue did not enter narrative")
	npc("smith")
	click_choice("menace_order")
	click_choice("waves_order")
	click_choice("ask_tracks")
	check(runtime.adventure.flags.smith_marks, "smith clue did not enter narrative")
	npc("innkeeper")
	click_choice("investigation_report")
	click_choice("route_investigate")
	check(runtime.adventure.routes.get("supply_resolution") == "investigate", "dialogue route not committed")
	npc("smith")
	click_choice("finale_order")

	# Actual destructible loot -> event bus -> quest -> shared wallet.
	check(not stage.loot.crates.is_empty(), "test map has no destructible crate")
	if not stage.loot.crates.is_empty():
		var crate_id: String = stage.loot.crates.keys()[0]
		stage.loot.damage_crate(crate_id, 9999)
		for drop: Dictionary in stage.loot.drops:
			drop.age = 1.0
		var drops: Array = stage.loot.drops.duplicate()
		for drop: Dictionary in drops:
			stage.loot.interact(drop.foot, 0.0)
	check(runtime.adventure.quests.courtyard_provisions.counts.get("crate", 0) == 1, "crate signal never reached accepted quest")
	check(stage.loot.materials["木料"] >= 3 and stage.loot.materials["碎布"] >= 1, "real drop pickup failed")
	npc("innkeeper")
	click_choice("provision_delivery")
	check(runtime.adventure.quests.courtyard_provisions.claimed, "NPC reward action did not claim provisions")
	check(stage.loot.materials["木料"] == 0 and stage.loot.materials["碎布"] == 0, "claim did not consume real shared materials")

	# A deterministic encounter exercises actual kill receipt and wave signals.
	# Direct damage avoids using player animation timing in a narrative integration test.
	runtime.panel.close()
	runtime.run_state.seed = 93711
	for wave in range(1, 4):
		check(runtime.encounters.begin_wave(wave, 93711 + wave), "encounter refused wave %d" % wave)
		for enemy: Dictionary in runtime.encounters.enemies:
			runtime.encounters._damage(enemy, 9999.0, "test", false)
		runtime.encounters._check_cleared()
	check(runtime.adventure.quests.courtyard_menace.counts.enemies == 3, "actual enemy kills failed quest")
	check(runtime.adventure.quests.clearance_waves.counts.waves == 3, "actual wave events failed quest")
	check(runtime.adventure.quests.courtyard_finale.counts.boss == 1, "boss/wave dual event duplicated or missed boss objective")
	npc("smith")
	click_choice("menace_reward")
	click_choice("waves_reward")
	click_choice("finale_reward")
	check(runtime.adventure.flags.finale_cleared, "finale flag never reached NPC story")
	check(runtime.progression.level >= 2 and stage.knight.max_health > 100, "quest XP did not update real character level bonus")
	npc("innkeeper")
	click_choice("oath_accept")
	click_choice("oath_bond")
	click_choice("oath_reward")
	click_choice("call_companion")
	check(runtime.companion_recruited and runtime.encounters.companion_enabled, "earned companion action not integrated")
	var trust: Dictionary = runtime.adventure.reputation.duplicate()
	var progression: Dictionary = runtime.progression.snapshot()
	var materials: Dictionary = stage.loot.materials.duplicate()
	click_choice("call_companion")
	check(runtime.adventure.reputation == trust and runtime.progression.snapshot() == progression and stage.loot.materials == materials, "repeated recruitment minted rewards or trust")

	# Menus must render using real service row shapes without unpausing the stage.
	for tab: String in ["journal", "network", "trade", "adventure"]:
		runtime.panel.open(tab)
		check(stage.interface.is_modal(), "session menu not included in modal gate: " + tab)
		check(runtime.panel.body.get_child_count() > 0, "empty integrated menu: " + tab)
	runtime.panel.close()

	# Use isolated on-disk slot; never read or write the player's actual save slots.
	var temporary := OS.get_environment("TEMP").path_join("rpg-adventure-integration-%d" % Time.get_ticks_usec())
	var saves = preload("res://systems/core/save_store.gd").new(temporary)
	var complete: Dictionary = runtime.snapshot()
	check(runtime.validate_snapshot(complete), "real finished adventure snapshot rejected")
	check(saves.save_slot(1, complete), "isolated save envelope write failed: " + saves.last_error)
	var loaded: Dictionary = saves.load_slot(1)
	check(loaded.ok, "isolated save envelope read failed")
	if loaded.ok:
		check(runtime.restore(initial), "could not restore initial world before load")
		check(not runtime.adventure.flags.finale_cleared and not runtime.companion_recruited, "restore failed to reset earlier story state")
		check(runtime.restore(loaded.data), "saved adventure envelope failed runtime restore")
		check(runtime.adventure.flags.finale_cleared and runtime.adventure.routes.supply_resolution == "investigate", "story branch lost through persisted roundtrip")
		check(runtime.companion_recruited and runtime.encounters.companion_enabled, "companion lost through persisted roundtrip")
		var saved_xp: Dictionary = runtime.progression.snapshot()
		var saved_wallet: Dictionary = stage.loot.materials.duplicate()
		check(not runtime.adventure.claim_quest("courtyard_finale").ok, "saved claimed finale paid again")
		check(runtime.progression.snapshot() == saved_xp and stage.loot.materials == saved_wallet, "duplicate persisted claim changed progression or money")
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path := saves.slot_path(1) + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(temporary)
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	for message: String in failures:
		push_error(message)
	print("ADVENTURE_INTEGRATION_TEST ", "PASS" if failures.is_empty() else "FAIL", " · real NPC buttons, crate loot, encounter events, nonlinear conclusion, level stats, companion, modal menus, disk save roundtrip")
	quit(0 if failures.is_empty() else 1)
