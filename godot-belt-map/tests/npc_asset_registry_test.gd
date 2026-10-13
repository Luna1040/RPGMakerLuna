extends SceneTree
## B-13: generated NPCs can select multiple release-approved character/action
## profiles, while paths, mismatched IDs and unreviewed packs remain blocked.

var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func run() -> void:
	var assets = root.get_node_or_null("NpcAssetRegistry")
	var registry = root.get_node_or_null("ContentRegistry")
	var drafts = root.get_node_or_null("ContentDraftService")
	var bridge = root.get_node_or_null("WorkbenchBridge")
	check(assets != null and assets.loaded, "NpcAssetRegistry unavailable")
	if assets == null or not assets.loaded:
		finish()
		return
	var profiles: Array[Dictionary] = assets.public_profiles()
	check(profiles.size() == 9, "release catalog did not expose nine distinct NPC profiles")
	check(profiles.all(func(row): return row.release_status == "approved" and not row.actions.is_empty()), "public profile omitted release/action evidence")
	check(profiles.any(func(row): return row.profile_id == "profile.npc.serin" and row.actions.has("cast")), "multi-action Serin profile is unavailable")
	check("res://" not in JSON.stringify(profiles), "public/Agent-facing profiles leaked resource paths")
	check(bridge.capabilities().get("npc_asset_profiles", []).size() == 9, "workbench capabilities omitted NPC asset profiles")

	var visual := {"profile_id":"profile.npc.caster", "base_asset_id":"asset.npc.caster.portrait",
		"idle_manifest_asset_id":"asset.npc.caster.actions", "ambient_action":"stand",
		"pivot_px":[384.0,650.0], "drawn_height_px":500.0, "portrait_region_px":[0.0,0.0,768.0,768.0]}
	check(assets.validate_visual(visual).is_empty(), "approved caster visual was rejected")
	var resolved: Dictionary = assets.resolve_visual(visual)
	check(resolved.renderer == "roster_actions" and resolved.actions.has("attack") and resolved.actions.has("hurt"), "approved action profile did not resolve")
	var mismatch: Dictionary = visual.duplicate(true)
	mismatch.idle_manifest_asset_id = "asset.npc.scout.actions"
	check(not assets.validate_visual(mismatch).is_empty(), "cross-profile base/manifest substitution was accepted")
	var invented: Dictionary = visual.duplicate(true)
	invented.profile_id = "profile.npc.invented"
	check(not assets.validate_visual(invented).is_empty(), "invented NPC asset profile was accepted")
	var forbidden_action: Dictionary = visual.duplicate(true)
	forbidden_action.ambient_action = "execute_script"
	check(not assets.validate_visual(forbidden_action).is_empty(), "unapproved NPC action was accepted")

	var raw_catalog = JSON.parse_string(FileAccess.get_file_as_string(assets.CATALOG_PATH))
	var unsafe_catalog: Dictionary = raw_catalog.duplicate(true)
	unsafe_catalog.entries[2].manifest_path = "res://scripts/steal.gd"
	check(not assets.validate_catalog(unsafe_catalog).is_empty(), "unsafe asset path passed the trusted catalog gate")
	var pending_catalog: Dictionary = raw_catalog.duplicate(true)
	pending_catalog.entries[2].release_status = "pending_review"
	check(not assets.validate_catalog(pending_catalog).is_empty(), "unreviewed action pack passed the release gate")
	var unattested_catalog: Dictionary = raw_catalog.duplicate(true)
	unattested_catalog.release_attestation_path = "res://assets/roster/missing.json"
	check(not assets.validate_catalog(unattested_catalog).is_empty(), "unattested roster passed the release gate")

	var npc: Dictionary = registry.get_npc("innkeeper")
	npc.id = "agent_caster"
	npc.display_name = "伊瑟 · 星图术士"
	npc.position_m = [11.0, 5.8]
	npc.visual = visual
	var dialogue: Dictionary = registry.get_dialogue("innkeeper")
	dialogue.name = npc.display_name
	var draft := {"schema_version":"content-draft/1", "draft_id":"draft.test.npc-assets",
		"project_id":"project.rpgmakerluna.courtyard", "base_catalog_hash":registry.catalog_hash,
		"base_content_revision":registry.revision, "author_role":"npc", "summary":"使用已验收多动作角色资产。", "operations":[
			{"op":"upsert", "target_type":"npc", "target_id":"agent_caster", "definition":npc},
			{"op":"upsert", "target_type":"dialogue", "target_id":"agent_caster", "definition":dialogue}]}
	check(drafts.validate_draft(draft).is_empty(), "approved multi-action NPC draft was rejected: " + str(drafts.validate_draft(draft)))
	var bad_draft: Dictionary = draft.duplicate(true)
	bad_draft.draft_id = "draft.test.npc-assets-mismatch"
	bad_draft.operations[0].definition.visual.idle_manifest_asset_id = "asset.npc.scout.actions"
	check(not drafts.validate_draft(bad_draft).is_empty(), "mismatched NPC asset pair entered a content draft")
	finish()

func finish() -> void:
	for message in failures: push_error(message)
	print("NPC_ASSET_REGISTRY_TEST %s · profiles, reviewed actions, path isolation, pair integrity, draft gate" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
