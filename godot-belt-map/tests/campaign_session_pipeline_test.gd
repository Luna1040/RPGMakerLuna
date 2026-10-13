extends SceneTree
## B launch boundary: installed campaign -> bootstrap commit -> isolated runtime.

const SaveStore = preload("res://systems/core/save_store.gd")
var failures: Array[String] = []
var scratch_root := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func make_draft(registry) -> Dictionary:
	var dialogue: Dictionary = registry.get_dialogue("innkeeper")
	dialogue.choices.append({"id":"session_archive_order", "label":"接受：新会话档案", "action":"accept",
		"quest":"session_archive", "when":{"quest":{"id":"session_archive", "status":["available"]}}})
	var quest := {"id":"session_archive", "title":"新会话档案", "description":"验证自定义战役只在新会话加载。",
		"npc":"innkeeper", "position":[6, 5], "requires":{}, "objectives":[
			{"id":"session_clue", "kind":"flag", "flag":"supply_hint", "target":1, "label":"取得会话线索"}],
		"rewards":{"xp":10, "reputation":{"innkeeper":1}}}
	return {"schema_version":"content-draft/1", "draft_id":"draft.test.session-launch",
		"project_id":"project.rpgmakerluna.courtyard", "base_catalog_hash":registry.catalog_hash,
		"base_content_revision":registry.revision, "author_role":"narrative", "summary":"新会话加载测试。",
		"operations":[
			{"op":"upsert", "target_type":"quest", "target_id":"session_archive", "definition":quest},
			{"op":"upsert", "target_type":"dialogue", "target_id":"innkeeper", "definition":dialogue}]}

func run() -> void:
	var registry = root.get_node_or_null("ContentRegistry")
	var draft_service = root.get_node_or_null("ContentDraftService")
	var import_service = root.get_node_or_null("CampaignImportService")
	var session_service = root.get_node_or_null("CampaignSessionService")
	check(registry != null and registry.loaded, "ContentRegistry unavailable")
	check(draft_service != null and import_service != null and session_service != null, "campaign session Autoloads unavailable")
	if registry == null or draft_service == null or import_service == null or session_service == null:
		finish()
		return
	registry.load_base_content()
	var original_publish_root: String = draft_service.publish_root
	var original_projects_root: String = import_service.projects_root
	scratch_root = "user://campaign-session-test-" + str(Time.get_ticks_usec())
	draft_service.publish_root = scratch_root
	import_service.projects_root = scratch_root
	draft_service.clear_previews()
	import_service.clear_previews()
	session_service.clear_launch_previews()

	var draft := make_draft(registry)
	var draft_preview: Dictionary = draft_service.preview_draft(draft)
	var published: Dictionary = draft_service.publish_draft(draft, str(draft_preview.get("preview_token", "")))
	check(published.ok, "session test artifact could not be published")
	var import_request := {"schema_version":"campaign-import-request/1", "request_id":"request.test.session-import",
		"project_id":"project.rpgmakerluna.courtyard", "draft_id":"draft.test.session-launch",
		"campaign_id":"campaign.test.session", "display_name":"新会话战役", "activation_policy":"new_campaign"}
	var import_preview: Dictionary = import_service.preview_import(import_request)
	var installed: Dictionary = import_service.install_campaign(import_request, str(import_preview.get("preview_token", "")))
	check(installed.ok, "session test campaign could not be installed: " + str(installed.get("errors", [])))

	var launch_preview: Dictionary = session_service.preview_campaign_launch(str(import_request.project_id), str(import_request.campaign_id))
	check(launch_preview.ok and launch_preview.replaces_current_session, "campaign launch preview was not produced")
	check(not launch_preview.activates_immediately and launch_preview.requires_scene_bootstrap and not launch_preview.auto_loads_save, "launch preview bypassed the new-session boundary")
	check(registry.is_official_context() and not registry.target_exists("quest", "session_archive"), "launch preview mutated official content")
	check(session_service.active_save_directory() == "user://rpg_saves", "launch preview changed the active save directory")
	check(not session_service.queue_campaign_launch(str(import_request.project_id), "campaign.test.other", launch_preview.launch_token).ok, "launch token crossed campaign identity")
	var queued: Dictionary = session_service.queue_campaign_launch(str(import_request.project_id), str(import_request.campaign_id), launch_preview.launch_token)
	check(queued.ok and session_service.has_pending_launch(), "reviewed campaign launch was not queued")

	var content_path := str(installed.campaign_path).path_join("content.json")
	var original_content_text := FileAccess.get_file_as_string(content_path)
	var tampered = JSON.parse_string(original_content_text)
	if tampered is Dictionary:
		tampered.npcs.innkeeper.display_name = "排队后被篡改"
		write_text(content_path, JSON.stringify(tampered, "  ", true, true))
	var failed_commit: Dictionary = session_service.commit_pending_launch()
	check(not failed_commit.ok, "changed package was committed after launch queue")
	check(registry.is_official_context() and session_service.active_save_directory() == "user://rpg_saves", "failed launch did not roll back to official context")
	check(not session_service.has_pending_launch(), "failed launch left a pending context")
	write_text(content_path, original_content_text)

	launch_preview = session_service.preview_campaign_launch(str(import_request.project_id), str(import_request.campaign_id))
	var scheduled: Dictionary = session_service.start_campaign_session(str(import_request.project_id), str(import_request.campaign_id), launch_preview.launch_token)
	check(scheduled.ok and scheduled.scheduled, "valid campaign session transition was not scheduled: " + str(scheduled.get("errors", [])))
	check(await wait_for_scene("res://stage.tscn"), "campaign bootstrap did not create the gameplay scene")
	check(registry.content_context().kind == "campaign" and registry.content_context().campaign_id == import_request.campaign_id, "campaign registry context was not activated")
	check(registry.target_exists("quest", "session_archive"), "campaign quest was not visible after new-session commit")
	check(session_service.active_save_directory() == installed.save_namespace, "campaign save directory did not switch to the isolated namespace")

	var isolated_saves = SaveStore.new(str(installed.save_namespace))
	check(isolated_saves.save_slot(1, {"campaign_id":str(import_request.campaign_id)}), "isolated campaign save store could not write")
	check(FileAccess.file_exists(isolated_saves.slot_path(1)) and isolated_saves.slot_path(1).begins_with(installed.campaign_path), "campaign save escaped its package directory")

	var stage = current_scene
	check(stage.runtime != null and stage.runtime.saves.directory == installed.save_namespace, "real stage did not start with isolated campaign saves")
	if stage.runtime != null:
		check(stage.runtime.adventure.catalog.get("quests", []).any(func(quest): return quest is Dictionary and quest.get("id") == "session_archive"), "real stage did not consume campaign adventure content")
		var custom_snapshot: Dictionary = stage.runtime.snapshot()
		check(custom_snapshot.content_context == registry.content_context() and stage.runtime.validate_snapshot(custom_snapshot), "campaign save did not bind to its content context")
		var legacy_custom: Dictionary = custom_snapshot.duplicate(true)
		legacy_custom.erase("content_context")
		check(not stage.runtime.validate_snapshot(legacy_custom), "legacy official save shape was accepted in a custom campaign")
		var mismatched_context: Dictionary = custom_snapshot.duplicate(true)
		mismatched_context.content_context.campaign_id = "campaign.test.other"
		check(not stage.runtime.validate_snapshot(mismatched_context), "save from another campaign context was accepted")

	var official: Dictionary = session_service.start_official_session()
	check(official.ok and official.scheduled, "official session transition was not scheduled")
	check(await wait_for_scene("res://stage.tscn", stage), "official bootstrap did not replace the campaign gameplay scene")
	check(registry.is_official_context(), "official context could not be restored through the bootstrap boundary")
	check(not registry.target_exists("quest", "session_archive"), "custom quest leaked into official context")
	check(session_service.active_save_directory() == "user://rpg_saves", "official save namespace was not restored")
	check(current_scene.runtime != null and current_scene.runtime.saves.directory == "user://rpg_saves", "official stage did not restore the official SaveStore")

	cleanup(str(installed.campaign_path), str(published.artifact_path), str(import_request.project_id))
	draft_service.publish_root = original_publish_root
	import_service.projects_root = original_projects_root
	draft_service.clear_previews()
	import_service.clear_previews()
	session_service.clear_launch_previews()
	finish()

func wait_for_scene(path: String, previous = null) -> bool:
	for _frame in range(120):
		await process_frame
		if current_scene != null and current_scene != previous and str(current_scene.scene_file_path) == path:
			return true
	return false

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()

func cleanup(campaign_path: String, artifact_path: String, project_id: String) -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		var save_path: String = campaign_path.path_join("saves").path_join("slot_1.json") + str(suffix)
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	for path in [campaign_path.path_join("saves"), campaign_path.path_join("manifest.json"), campaign_path.path_join("content.json"), artifact_path]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var project_path := scratch_root.path_join(project_id)
	for path in [campaign_path, project_path.path_join("campaigns"), project_path.path_join("published"), project_path, scratch_root]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish() -> void:
	for message in failures:
		push_error(message)
	print("CAMPAIGN_SESSION_PIPELINE_TEST %s · bootstrap-only activation, rollback, isolated saves, real-stage consumption" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
