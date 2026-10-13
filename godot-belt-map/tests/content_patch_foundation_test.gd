extends SceneTree
## B contract: validated content, idempotent patches, undo and save-state roundtrip.

const Validator = preload("res://systems/content/content_validator.gd")
const Knight = preload("res://characters/first_knight/knight.gd")
const Equipment = preload("res://characters/first_knight/equipment.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func patch(id: String, revision: int, operations: Array) -> Dictionary:
	return {"schema_version":"runtime-patch/1", "patch_id":id,
		"base_content_revision":revision, "operations":operations}

func replace(path: String, value: Variant) -> Dictionary:
	return {"op":"replace", "target_type":"skill", "target_id":"skill.knight.lightning",
		"path":path, "value":value}

func run() -> void:
	var registry = root.get_node_or_null("ContentRegistry")
	var bridge = root.get_node_or_null("WorkbenchBridge")
	check(registry != null and registry.loaded, "ContentRegistry did not load validated base content")
	check(bridge != null, "WorkbenchBridge autoload is missing")
	if registry == null:
		finish()
		return
	var original: Dictionary = registry.export_runtime_state()
	var lightning: Dictionary = registry.get_skill("skill.knight.lightning")
	check(lightning.get("display_name") == "雷光", "lightning is not registered by stable id")
	check(lightning.get("combat", {}).get("chain_count") == 1, "base lightning must hit one target")
	check(not registry.catalog_hash.is_empty(), "full content catalog hash is missing")
	check(registry.registered_ids("equipment").size() == 13, "equipment catalog was not registered")
	check(registry.get_equipment("edge_sword").get("stats", {}).get("attack") == 8.0, "equipment stable ID lookup failed")
	check(registry.get_npc("innkeeper").get("visual", {}).get("base_asset_id") == "asset.npc.innkeeper.base", "NPC registered asset lookup failed")
	check(registry.get_quest("courtyard_provisions").get("npc") == "innkeeper", "quest stable ID lookup failed")
	check(registry.get_dialogue("smith").get("choices", []).size() > 0, "dialogue stable ID lookup failed")
	var copied_equipment: Dictionary = registry.get_equipment("edge_sword")
	copied_equipment.stats.attack = 9999
	check(registry.get_equipment("edge_sword").stats.attack == 8.0, "registered definition leaked a mutable reference")
	var equipment := Equipment.new()
	check(equipment.CATALOG.has("courtyard_blade") and equipment.CATALOG.edge_sword.stats.attack == 8.0, "gameplay equipment did not consume ContentRegistry")
	var actor := Knight.new()
	actor.content_registry_override = registry
	check(is_equal_approx(actor.get_spell_mana_cost(), 25.0), "actor did not consume registered mana cost")
	check(is_equal_approx(actor.get_spell_cooldown(), 2.4), "actor did not consume registered cooldown")
	check(is_equal_approx(actor.get_spell_damage(), 42.0), "actor did not consume registered damage")
	actor.free()

	var valid := patch("test.lightning.chain-three", registry.revision, [
		replace("/combat/chain_count", 3), replace("/combat/base_damage", 47.0)])
	var result: Dictionary = registry.apply_runtime_patch(valid)
	check(result.ok and result.revision == 1, "valid atomic patch was rejected")
	lightning = registry.get_skill("skill.knight.lightning")
	check(lightning.combat.chain_count == 3 and is_equal_approx(lightning.combat.base_damage, 47.0), "multi-operation patch was partially applied")
	var duplicate: Dictionary = registry.apply_runtime_patch(valid)
	check(duplicate.ok and duplicate.duplicate and registry.revision == 1, "patch idempotency changed revision")
	var stale := patch("test.stale", 0, [replace("/combat/base_damage", 50.0)])
	check(not registry.apply_runtime_patch(stale).ok and is_equal_approx(registry.get_skill("skill.knight.lightning").combat.base_damage, 47.0), "stale patch changed content")
	var unsafe := patch("test.unsafe", registry.revision, [replace("/script", "res://attack.gd")])
	check(not Validator.validate_runtime_patch(unsafe).is_empty() and not registry.apply_runtime_patch(unsafe).ok, "generated script path crossed the data boundary")
	var fractional := patch("test.fractional-chain", registry.revision, [replace("/combat/chain_count", 2.5)])
	check(not registry.apply_runtime_patch(fractional).ok, "fractional chain count was accepted")
	var undo: Dictionary = registry.undo_last_patch()
	check(undo.ok and registry.get_skill("skill.knight.lightning").combat.chain_count == 1, "undo did not restore the prior definition")

	var persisted_patch := patch("test.persisted", registry.revision, [replace("/combat/chain_count", 3)])
	check(registry.apply_runtime_patch(persisted_patch).ok, "persisted patch was rejected")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(registry.export_runtime_state()))
	check(registry.load_base_content() and registry.get_skill("skill.knight.lightning").combat.chain_count == 1, "base reload did not clear runtime overrides")
	check(registry.restore_runtime_state(saved) and registry.get_skill("skill.knight.lightning").combat.chain_count == 3, "runtime content save roundtrip lost the patch")
	var tampered: Dictionary = saved.duplicate(true)
	tampered.overrides["skill.knight.lightning"]["/script"] = 1
	check(not registry.validate_runtime_state(tampered).is_empty(), "tampered saved content state was accepted")

	if bridge != null:
		var capabilities: Dictionary = bridge.capabilities()
		check(not capabilities.allows_generated_code and "/combat/chain_count" in capabilities.patchable_paths, "workbench capability boundary is inaccurate")
		check(capabilities.targets_by_type.equipment.size() == 13 and capabilities.agent_task_schema == "agent-task/1", "workbench did not advertise unified catalog/Agent contracts")
		var inspected: Dictionary = bridge.inspect_target("skill", "skill.knight.lightning")
		check(inspected.get("definition", {}).get("combat", {}).get("chain_count") == 3 and inspected.content_revision == registry.revision, "Agent target inspection is stale or mutable")
		check(bridge.inspect_target("quest", "courtyard_provisions").get("definition", {}).get("title") == "艾琳的补给", "Agent cannot inspect registered quest")
		var task := {"schema_version":"agent-task/1", "request_id":"request.test.systems", "project_id":"project.rpgmakerluna.courtyard",
			"content_revision":registry.revision, "agent_role":"systems", "objective":"审查并提出雷光数值调整。",
			"allowed_targets":[{"target_type":"skill", "target_id":"skill.knight.lightning"}],
			"constraints":{"max_proposals":2, "allow_new_ids":false, "allow_generated_code":false},
			"context_refs":[{"target_type":"quest", "target_id":"courtyard_provisions"}]}
		check(bridge.validate_agent_task(task).is_empty(), "valid Main Agent task contract was rejected")
		var proposed_patch := patch("test.agent.proposal", registry.revision, [replace("/combat/base_damage", 49.0)])
		var agent_result := {"schema_version":"agent-result/1", "request_id":"request.test.systems", "agent_role":"systems",
			"status":"completed", "summary":"数值建议已完成。", "deliverables":[
				{"deliverable_id":"deliverable.test.lightning-note", "kind":"analysis", "target_type":"skill", "target_id":"skill.knight.lightning", "content":"建议小幅提高基础伤害。"},
				{"deliverable_id":"deliverable.test.lightning-patch", "kind":"runtime_patch", "payload":proposed_patch}],
			"evidence":["当前定义通过注册表读取。"], "warnings":[]}
		var reviewed: Dictionary = bridge.review_agent_result(task, agent_result)
		check(reviewed.ok and reviewed.actionable_patches.size() == 1, "valid child Agent result was rejected")
		check(is_equal_approx(registry.get_skill("skill.knight.lightning").combat.base_damage, 42.0), "review_agent_result applied a patch without Main Agent submission")
		var forged: Dictionary = agent_result.duplicate(true)
		forged.request_id = "request.test.other"
		check(not bridge.review_agent_result(task, forged).ok, "mismatched child Agent result was accepted")
		var forbidden_task: Dictionary = task.duplicate(true)
		forbidden_task.agent_role = "npc"
		check(not bridge.validate_agent_task(forbidden_task).is_empty(), "NPC Agent received systems mutation authority")
		bridge.bind_runtime(null)
		var queued := patch("test.queued", registry.revision, [replace("/cooldown_seconds", 2.0)])
		var queued_result: Dictionary = bridge.submit_patch(queued)
		check(queued_result.ok and queued_result.queued and registry.get_skill("skill.knight.lightning").cooldown_seconds == 2.4, "unsafe point applied instead of queueing")
		bridge.clear_pending()
	check(registry.restore_runtime_state(original), "test cleanup could not restore original content state")
	finish()

func finish() -> void:
	for message in failures:
		push_error(message)
	print("CONTENT_PATCH_FOUNDATION_TEST %s · unified catalogs, Agent contracts, atomic apply, idempotency, stale rejection, undo, persistence, safe queue" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
