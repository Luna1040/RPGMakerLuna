extends SceneTree
## B campaign boundary: published artifact -> isolated immutable campaign package.

var failures: Array[String] = []
var scratch_root := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func make_draft(registry) -> Dictionary:
	var dialogue: Dictionary = registry.get_dialogue("innkeeper")
	dialogue.choices.append({"id":"campaign_archive_order", "label":"接受：新战役档案", "action":"accept",
		"quest":"campaign_archive", "when":{"quest":{"id":"campaign_archive", "status":["available"]}}})
	var quest := {"id":"campaign_archive", "title":"新战役档案", "description":"验证独立战役内容目录。",
		"npc":"innkeeper", "position":[5, 5], "requires":{}, "objectives":[
			{"id":"campaign_clue", "kind":"flag", "flag":"supply_hint", "target":1, "label":"取得战役线索"}],
		"rewards":{"xp":10, "reputation":{"innkeeper":1}}}
	return {"schema_version":"content-draft/1", "draft_id":"draft.test.campaign-import",
		"project_id":"project.rpgmakerluna.courtyard", "base_catalog_hash":registry.catalog_hash,
		"base_content_revision":registry.revision, "author_role":"narrative", "summary":"新战役导入测试。",
		"operations":[
			{"op":"upsert", "target_type":"quest", "target_id":"campaign_archive", "definition":quest},
			{"op":"upsert", "target_type":"dialogue", "target_id":"innkeeper", "definition":dialogue}]}

func make_request(campaign_id := "campaign.test.archive") -> Dictionary:
	return {"schema_version":"campaign-import-request/1", "request_id":"request.test.campaign-import",
		"project_id":"project.rpgmakerluna.courtyard", "draft_id":"draft.test.campaign-import",
		"campaign_id":campaign_id, "display_name":"新战役档案", "activation_policy":"new_campaign"}

func run() -> void:
	var registry = root.get_node_or_null("ContentRegistry")
	var draft_service = root.get_node_or_null("ContentDraftService")
	var import_service = root.get_node_or_null("CampaignImportService")
	var bridge = root.get_node_or_null("WorkbenchBridge")
	check(registry != null and registry.loaded, "ContentRegistry unavailable")
	check(draft_service != null and import_service != null and bridge != null, "campaign authoring Autoloads unavailable")
	if registry == null or draft_service == null or import_service == null or bridge == null:
		finish()
		return
	var original_publish_root: String = draft_service.publish_root
	var original_projects_root: String = import_service.projects_root
	scratch_root = "user://campaign-import-test-" + str(Time.get_ticks_usec())
	draft_service.publish_root = scratch_root
	import_service.projects_root = scratch_root
	draft_service.clear_previews()
	import_service.clear_previews()

	var draft := make_draft(registry)
	var draft_preview: Dictionary = draft_service.preview_draft(draft)
	var published: Dictionary = draft_service.publish_draft(draft, str(draft_preview.get("preview_token", "")))
	check(published.ok, "test content artifact could not be published: " + str(published.get("errors", [])))
	var request := make_request()
	check(import_service.validate_import_request(request).is_empty(), "valid campaign import request was rejected")
	var preview: Dictionary = bridge.preview_campaign_import(request)
	check(preview.ok and preview.operation_count == 2, "campaign import preview was not produced: " + str(preview.get("errors", [])))
	check(not preview.activates_runtime and preview.requires_new_session, "campaign preview claimed to activate the running session")
	check(preview.activation_policy == "new_campaign", "campaign activation policy was not preserved")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(str(preview.get("campaign_path", "")))), "campaign preview wrote an installation directory")
	check(not registry.target_exists("quest", "campaign_archive"), "campaign preview mutated the live registry")

	var installed: Dictionary = bridge.install_campaign(request, str(preview.get("preview_token", "")))
	check(installed.ok and not installed.duplicate, "reviewed campaign was not installed atomically: " + str(installed.get("errors", [])))
	check(FileAccess.file_exists(str(installed.get("manifest_path", ""))), "campaign manifest was not installed")
	check(FileAccess.file_exists(str(installed.get("campaign_path", "")).path_join("content.json")), "campaign content snapshot was not installed")
	check(str(installed.get("save_namespace", "")).begins_with(str(installed.get("campaign_path", ""))), "campaign saves escaped the campaign namespace")
	check(installed.get("save_namespace") != "user://rpg_saves", "campaign reused the official save namespace")
	check(not registry.target_exists("quest", "campaign_archive"), "campaign installation mutated the live registry")
	var inspected: Dictionary = bridge.inspect_campaign(str(request.project_id), str(request.campaign_id))
	check(inspected.ok, "installed campaign failed inspection: " + str(inspected.get("errors", [])))
	if inspected.ok:
		check(inspected.manifest.runtime_activation == "new_session_only", "manifest allowed current-session activation")
		check(inspected.manifest.save_namespace == "saves", "manifest used a non-isolated save namespace")
		check(has_quest(inspected.content.adventure, "campaign_archive"), "installed campaign omitted generated quest")
	var duplicate: Dictionary = bridge.install_campaign(request, preview.preview_token)
	check(duplicate.ok and duplicate.duplicate, "identical campaign installation was not idempotent")

	var changed_request: Dictionary = request.duplicate(true)
	changed_request.display_name = "预览后篡改的名称"
	check(not bridge.install_campaign(changed_request, preview.preview_token).ok, "changed campaign request reused a preview token")
	var reserved: Dictionary = make_request("campaign.official.courtyard")
	check(not import_service.validate_import_request(reserved).is_empty(), "reserved official campaign ID was accepted")
	var copy_request: Dictionary = make_request("campaign.test.explicit-copy")
	copy_request.request_id = "request.test.campaign-copy"
	copy_request.activation_policy = "explicit_project_copy"
	var copy_preview: Dictionary = import_service.preview_import(copy_request)
	check(copy_preview.ok and copy_preview.activation_policy == "explicit_project_copy" and not copy_preview.activates_runtime, "explicit project copy policy was not isolated")

	var artifact_path := str(published.get("artifact_path", ""))
	var original_artifact_text := FileAccess.get_file_as_string(artifact_path)
	var tampered_artifact = JSON.parse_string(original_artifact_text)
	if tampered_artifact is Dictionary:
		tampered_artifact.draft.summary = "被篡改且未重新签名。"
		write_text(artifact_path, JSON.stringify(tampered_artifact, "  ", true, true))
		var tamper_request: Dictionary = make_request("campaign.test.tampered-artifact")
		tamper_request.request_id = "request.test.tampered-artifact"
		check(not import_service.preview_import(tamper_request).ok, "tampered published artifact passed campaign preview")
		write_text(artifact_path, original_artifact_text)

	var content_path := str(installed.get("campaign_path", "")).path_join("content.json")
	var manifest_path := str(installed.get("manifest_path", ""))
	var original_content_text := FileAccess.get_file_as_string(content_path)
	var original_manifest_text := FileAccess.get_file_as_string(manifest_path)
	var tampered_content = JSON.parse_string(original_content_text)
	if tampered_content is Dictionary:
		tampered_content.npcs.innkeeper.display_name = "被篡改的旅店老板"
		write_text(content_path, JSON.stringify(tampered_content, "  ", true, true))
		check(not bridge.inspect_campaign(str(request.project_id), str(request.campaign_id)).ok, "tampered installed campaign passed inspection")
		write_text(content_path, original_content_text)
		check(bridge.inspect_campaign(str(request.project_id), str(request.campaign_id)).ok, "restored campaign package did not validate")
	var forged_content = JSON.parse_string(original_content_text)
	var forged_manifest = JSON.parse_string(original_manifest_text)
	if forged_content is Dictionary and forged_manifest is Dictionary:
		forged_content.npcs.innkeeper.visual.base_asset_id = "asset.npc.forged.base"
		forged_content.candidate_content_hash = canonical_hash({"npcs":forged_content.npcs, "adventure":forged_content.adventure})
		forged_content.content_hash = document_hash(forged_content, "content_hash")
		forged_manifest.content_hash = forged_content.content_hash
		forged_manifest.source_artifact.candidate_content_hash = forged_content.candidate_content_hash
		forged_manifest.manifest_hash = document_hash(forged_manifest, "manifest_hash")
		write_text(content_path, JSON.stringify(forged_content, "  ", true, true))
		write_text(manifest_path, JSON.stringify(forged_manifest, "  ", true, true))
		check(not bridge.inspect_campaign(str(request.project_id), str(request.campaign_id)).ok, "re-hashed package bypassed the registered asset boundary")
		write_text(content_path, original_content_text)
		write_text(manifest_path, original_manifest_text)

	cleanup(str(installed.get("campaign_path", "")), artifact_path, str(request.project_id))
	draft_service.publish_root = original_publish_root
	import_service.projects_root = original_projects_root
	draft_service.clear_previews()
	import_service.clear_previews()
	finish()

func has_quest(adventure: Dictionary, quest_id: String) -> bool:
	for quest in adventure.get("quests", []):
		if quest is Dictionary and quest.get("id") == quest_id:
			return true
	return false

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

func document_hash(value: Dictionary, hash_field: String) -> String:
	var content := value.duplicate(true)
	content.erase(hash_field)
	return canonical_hash(content)

func canonical_hash(value: Variant) -> String:
	var normalized = JSON.parse_string(JSON.stringify(value, "", true, true))
	return JSON.stringify(normalized, "", true, true).sha256_text()

func cleanup(campaign_path: String, artifact_path: String, project_id: String) -> void:
	for path in [campaign_path.path_join("manifest.json"), campaign_path.path_join("content.json"), artifact_path]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var project_path := scratch_root.path_join(project_id)
	for path in [campaign_path, project_path.path_join("campaigns"), project_path.path_join("published"), project_path, scratch_root]:
		if not path.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish() -> void:
	for message in failures:
		push_error(message)
	print("CAMPAIGN_IMPORT_PIPELINE_TEST %s · checksummed artifact, isolated manifest/content, atomic install, tamper rejection" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
