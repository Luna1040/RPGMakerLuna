extends SceneTree
## B authoring contract: Agent draft -> validation -> preview -> immutable publish.

const Validator = preload("res://systems/content/content_validator.gd")
var failures: Array[String] = []
var scratch_root := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func narrative_draft(registry) -> Dictionary:
	var dialogue: Dictionary = registry.get_dialogue("innkeeper")
	dialogue.choices.append({"id":"archive_rumor_order", "label":"接受：庭院旧档案", "action":"accept",
		"quest":"archive_rumor", "when":{"quest":{"id":"archive_rumor", "status":["available"]}}})
	var quest := {"id":"archive_rumor", "title":"庭院旧档案", "description":"向艾琳确认旧账簿中留下的补给线索。",
		"npc":"innkeeper", "position":[4, 4], "requires":{}, "objectives":[
			{"id":"ledger_clue", "kind":"flag", "flag":"supply_hint", "target":1, "label":"取得账簿线索"}],
		"rewards":{"xp":10, "reputation":{"innkeeper":1}}}
	return {"schema_version":"content-draft/1", "draft_id":"draft.test.archive-rumor",
		"project_id":"project.rpgmakerluna.courtyard", "base_catalog_hash":registry.catalog_hash,
		"base_content_revision":registry.revision, "author_role":"narrative", "summary":"新增一条旧档案支线。",
		"operations":[
			{"op":"upsert", "target_type":"quest", "target_id":"archive_rumor", "definition":quest},
			{"op":"upsert", "target_type":"dialogue", "target_id":"innkeeper", "definition":dialogue}]}

func run() -> void:
	var registry = root.get_node_or_null("ContentRegistry")
	var service = root.get_node_or_null("ContentDraftService")
	var bridge = root.get_node_or_null("WorkbenchBridge")
	check(registry != null and registry.loaded, "ContentRegistry unavailable")
	check(service != null and bridge != null, "content authoring Autoloads unavailable")
	if registry == null or service == null or bridge == null:
		finish()
		return
	var original_publish_root: String = service.publish_root
	scratch_root = "user://content-draft-test-" + str(Time.get_ticks_usec())
	service.publish_root = scratch_root
	service.clear_previews()
	var draft := narrative_draft(registry)
	check(service.validate_draft(draft).is_empty(), "valid narrative draft was rejected: " + "; ".join(service.validate_draft(draft)))
	var preview: Dictionary = bridge.preview_content_draft(draft)
	check(preview.ok and preview.operation_count == 2 and preview.changes.size() == 2, "content preview was not produced")
	check(not preview.activates_runtime and preview.reload_required == "new_campaign_import", "preview claimed to hot-activate campaign content")
	check(not registry.target_exists("quest", "archive_rumor"), "preview mutated the live registry")
	var published: Dictionary = bridge.publish_content_draft(draft, str(preview.get("preview_token", "")))
	check(published.ok and not published.duplicate and FileAccess.file_exists(str(published.get("artifact_path", ""))), "reviewed draft was not published atomically: " + str(published.get("errors", [])))
	if published.ok:
		var artifact = JSON.parse_string(FileAccess.get_file_as_string(published.artifact_path))
		check(artifact is Dictionary and Validator.validate_published_content(artifact).is_empty(), "published artifact failed schema validation")
		check(artifact.get("candidate_content_hash") == preview.candidate_content_hash, "published candidate differs from preview")
	var duplicate: Dictionary = bridge.publish_content_draft(draft, preview.preview_token)
	check(duplicate.ok and duplicate.duplicate, "idempotent publish was not recognized")
	var tampered: Dictionary = draft.duplicate(true)
	tampered.summary = "预览后被替换的内容。"
	check(not bridge.publish_content_draft(tampered, preview.preview_token).ok, "tampered draft reused a preview token")
	var stale: Dictionary = draft.duplicate(true)
	stale.draft_id = "draft.test.stale"
	stale.base_catalog_hash = "0".repeat(64)
	check(not service.preview_draft(stale).ok, "stale catalog hash was accepted")

	var task := {"schema_version":"agent-task/1", "request_id":"request.test.narrative-draft",
		"project_id":"project.rpgmakerluna.courtyard", "content_revision":registry.revision,
		"agent_role":"narrative", "objective":"新增一条与现有艾琳对话相连的支线。",
		"allowed_targets":[{"target_type":"quest", "target_id":"archive_rumor"}, {"target_type":"dialogue", "target_id":"innkeeper"}],
		"constraints":{"max_proposals":1, "allow_new_ids":true, "allow_generated_code":false},
		"context_refs":[{"target_type":"dialogue", "target_id":"innkeeper"}]}
	check(bridge.validate_agent_task(task).is_empty(), "Narrative Agent could not receive a new draft ID")
	var result := {"schema_version":"agent-result/1", "request_id":"request.test.narrative-draft", "agent_role":"narrative",
		"status":"completed", "summary":"支线草稿完成。", "deliverables":[
			{"deliverable_id":"deliverable.test.archive-draft", "kind":"content_draft", "payload":draft}],
		"evidence":["任务与对话引用已配对。"], "warnings":[]}
	var reviewed: Dictionary = bridge.review_agent_result(task, result)
	check(reviewed.ok and reviewed.content_drafts.size() == 1, "valid child Agent content draft was rejected")
	check(not registry.target_exists("quest", "archive_rumor"), "Agent result review mutated the live registry")
	var wrong_project_result: Dictionary = result.duplicate(true)
	wrong_project_result.deliverables[0].payload.project_id = "project.unrelated.world"
	check(not bridge.review_agent_result(task, wrong_project_result).ok, "Agent draft crossed its assigned project boundary")
	var forbidden_task: Dictionary = task.duplicate(true)
	forbidden_task.agent_role = "systems"
	check(not bridge.validate_agent_task(forbidden_task).is_empty(), "Systems Agent received new narrative ID authority")

	var npc_definition: Dictionary = registry.get_npc("innkeeper")
	npc_definition.id = "archive_scribe"
	npc_definition.display_name = "档案员"
	npc_definition.visual.base_asset_id = "asset.npc.unregistered.base"
	var bad_asset := {"schema_version":"content-draft/1", "draft_id":"draft.test.bad-asset",
		"project_id":"project.rpgmakerluna.courtyard", "base_catalog_hash":registry.catalog_hash,
		"base_content_revision":registry.revision, "author_role":"npc", "summary":"使用未登记资产。", "operations":[
			{"op":"upsert", "target_type":"npc", "target_id":"archive_scribe", "definition":npc_definition},
			{"op":"upsert", "target_type":"dialogue", "target_id":"archive_scribe", "definition":registry.get_dialogue("innkeeper")}]}
	check(not service.validate_draft(bad_asset).is_empty(), "unregistered NPC asset id was accepted")
	var bad_reference: Dictionary = draft.duplicate(true)
	bad_reference.draft_id = "draft.test.bad-reference"
	bad_reference.operations[0].definition.npc = "missing_npc"
	check(not service.validate_draft(bad_reference).is_empty(), "dangling quest NPC reference was accepted")
	if published.ok:
		var wrong_source = JSON.parse_string(FileAccess.get_file_as_string(published.artifact_path))
		wrong_source.source_content_revision = int(wrong_source.source_content_revision) + 1
		check(not Validator.validate_published_content(wrong_source).is_empty(), "published artifact accepted mismatched source context")

	cleanup(str(published.get("artifact_path", "")))
	service.publish_root = original_publish_root
	service.clear_previews()
	finish()

func cleanup(artifact_path: String) -> void:
	if not artifact_path.is_empty() and FileAccess.file_exists(artifact_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(artifact_path))
	var published_dir := scratch_root.path_join("project.rpgmakerluna.courtyard").path_join("published")
	for path in [published_dir, published_dir.get_base_dir(), scratch_root]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish() -> void:
	for message in failures:
		push_error(message)
	print("CONTENT_DRAFT_PIPELINE_TEST %s · strict graph validation, preview isolation, Agent scope, immutable atomic publish" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
