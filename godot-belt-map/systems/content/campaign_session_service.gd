extends Node
## New-session-only campaign launcher. Content activation is committed only while
## the bootstrap scene owns the SceneTree (or from an isolated script test).

const SaveStore = preload("res://systems/core/save_store.gd")

signal launch_previewed(campaign_id: String, launch_token: String)
signal session_activated(context: Dictionary, save_directory: String)
signal session_launch_failed(campaign_id: String, errors: Array[String])

const BOOTSTRAP_SCENE := "res://systems/content/campaign_bootstrap.tscn"
const GAME_SCENE := "res://stage.tscn"
const OFFICIAL_SAVE_DIRECTORY := "user://rpg_saves"
const MAX_PREVIEWS := 16
const MAX_LIBRARY_PROJECTS := 64
const MAX_LIBRARY_CAMPAIGNS := 256

var last_error := ""
var _active_save_directory := OFFICIAL_SAVE_DIRECTORY
var _pending_launch: Dictionary = {}
var _previews: Dictionary = {}
var _preview_order: Array[String] = []
var _transition_scheduled := false

func preview_campaign_launch(project_id: String, campaign_id: String) -> Dictionary:
	var import_service = _import_service()
	if import_service == null:
		return _reject(campaign_id, ["CampaignImportService is unavailable."])
	var inspected: Dictionary = import_service.inspect_campaign(project_id, campaign_id)
	if not inspected.ok:
		return _reject(campaign_id, inspected.errors)
	var manifest: Dictionary = inspected.manifest
	var campaign_path: String = import_service.projects_root.path_join(project_id).path_join("campaigns").path_join(campaign_id)
	var save_directory := campaign_path.path_join(str(manifest.save_namespace))
	var token := _canonical_hash({"project_id":project_id, "campaign_id":campaign_id,
		"manifest_hash":str(manifest.manifest_hash), "content_hash":str(manifest.content_hash),
		"nonce":str(Time.get_ticks_usec())})
	_previews[token] = {"project_id":project_id, "campaign_id":campaign_id,
		"manifest_hash":str(manifest.manifest_hash), "content_hash":str(manifest.content_hash),
		"save_directory":save_directory}
	_preview_order.append(token)
	while _preview_order.size() > MAX_PREVIEWS:
		_previews.erase(_preview_order.pop_front())
	var result := {"ok":true, "errors":[], "project_id":project_id, "campaign_id":campaign_id,
		"display_name":str(manifest.display_name), "launch_token":token,
		"manifest_hash":str(manifest.manifest_hash), "content_hash":str(manifest.content_hash),
		"save_directory":save_directory, "activation_policy":str(manifest.activation_policy),
		"replaces_current_session":true, "activates_immediately":false,
		"requires_scene_bootstrap":true, "auto_loads_save":false}
	launch_previewed.emit(campaign_id, token)
	return result

func preview_official_launch() -> Dictionary:
	return {"ok":true, "errors":[], "kind":"official",
		"project_id":"project.rpgmakerluna.courtyard",
		"campaign_id":"campaign.official.courtyard", "display_name":"苍石庭院",
		"save_directory":OFFICIAL_SAVE_DIRECTORY, "replaces_current_session":true,
		"activates_immediately":false, "requires_scene_bootstrap":true,
		"auto_loads_save":false}

func list_campaigns(project_id: String = "") -> Dictionary:
	## Read-only library view for Godot and web workbenches. Invalid packages are
	## visible but cannot be launched; no caller-supplied path is accepted.
	var requested := project_id.strip_edges()
	if not requested.is_empty() and not _scoped_id(requested, "project"):
		return {"ok":false, "errors":["Project ID must be canonical."],
			"campaigns":[], "active_context":active_context()}
	var campaigns: Array[Dictionary] = []
	var truncated := false
	if requested.is_empty() or requested == "project.rpgmakerluna.courtyard":
		campaigns.append(_official_library_entry())
	var import_service = _import_service()
	if import_service == null:
		return {"ok":false, "errors":["CampaignImportService is unavailable."],
			"campaigns":campaigns, "active_context":active_context()}
	var projects: Array[String] = []
	if not requested.is_empty():
		projects.append(requested)
	else:
		var root_directory := DirAccess.open(import_service.projects_root)
		if root_directory != null:
			for directory in root_directory.get_directories():
				if _scoped_id(directory, "project"):
					if projects.size() >= MAX_LIBRARY_PROJECTS:
						truncated = true
						continue
					projects.append(directory)
	projects.sort()
	var custom: Array[Dictionary] = []
	for candidate_project in projects:
		var campaigns_path: String = import_service.projects_root.path_join(candidate_project).path_join("campaigns")
		var campaigns_directory := DirAccess.open(campaigns_path)
		if campaigns_directory == null:
			continue
		var campaign_ids: Array[String] = []
		for directory in campaigns_directory.get_directories():
			if _scoped_id(directory, "campaign"):
				if campaign_ids.size() >= MAX_LIBRARY_CAMPAIGNS:
					truncated = true
					continue
				campaign_ids.append(directory)
		campaign_ids.sort()
		for campaign_id in campaign_ids:
			if custom.size() >= MAX_LIBRARY_CAMPAIGNS:
				truncated = true
				break
			custom.append(_campaign_library_entry(import_service, candidate_project, campaign_id))
		if custom.size() >= MAX_LIBRARY_CAMPAIGNS:
			break
	custom.sort_custom(func(a: Dictionary, b: Dictionary):
		return str(a.get("display_name", a.get("campaign_id", ""))).naturalnocasecmp_to(
			str(b.get("display_name", b.get("campaign_id", "")))) < 0)
	campaigns.append_array(custom)
	return {"ok":true, "errors":[], "campaigns":campaigns, "truncated":truncated,
		"active_context":active_context()}

func queue_campaign_launch(project_id: String, campaign_id: String, launch_token: String) -> Dictionary:
	if not _previews.has(launch_token):
		return _reject(campaign_id, ["Unknown or expired campaign launch token."])
	var preview: Dictionary = _previews[launch_token]
	if preview.project_id != project_id or preview.campaign_id != campaign_id:
		return _reject(campaign_id, ["Campaign launch identity does not match its preview."])
	var import_service = _import_service()
	if import_service == null:
		return _reject(campaign_id, ["CampaignImportService is unavailable."])
	var inspected: Dictionary = import_service.inspect_campaign(project_id, campaign_id)
	if not inspected.ok:
		return _reject(campaign_id, inspected.errors)
	if inspected.manifest.manifest_hash != preview.manifest_hash or inspected.manifest.content_hash != preview.content_hash:
		return _reject(campaign_id, ["Campaign package changed after launch preview."])
	_pending_launch = {"kind":"campaign", "project_id":project_id, "campaign_id":campaign_id,
		"manifest_hash":str(preview.manifest_hash), "content_hash":str(preview.content_hash),
		"save_directory":str(preview.save_directory)}
	return {"ok":true, "errors":[], "queued":true, "campaign_id":campaign_id,
		"activates_immediately":false, "requires_scene_bootstrap":true}

func start_campaign_session(project_id: String, campaign_id: String, launch_token: String) -> Dictionary:
	if _transition_scheduled:
		return _reject(campaign_id, ["Another new-session transition is already scheduled."])
	var queued := queue_campaign_launch(project_id, campaign_id, launch_token)
	if not queued.ok:
		return queued
	_transition_scheduled = true
	call_deferred("_change_to_bootstrap")
	return {"ok":true, "errors":[], "scheduled":true, "campaign_id":campaign_id,
		"replaces_current_session":true, "auto_loads_save":false}

func queue_official_launch() -> Dictionary:
	_pending_launch = {"kind":"official", "project_id":"project.rpgmakerluna.courtyard",
		"campaign_id":"campaign.official.courtyard", "save_directory":OFFICIAL_SAVE_DIRECTORY}
	return {"ok":true, "errors":[], "queued":true, "campaign_id":"campaign.official.courtyard",
		"activates_immediately":false, "requires_scene_bootstrap":true}

func start_official_session() -> Dictionary:
	if _transition_scheduled:
		return _reject("campaign.official.courtyard", ["Another new-session transition is already scheduled."])
	queue_official_launch()
	_transition_scheduled = true
	call_deferred("_change_to_bootstrap")
	return {"ok":true, "errors":[], "scheduled":true,
		"campaign_id":"campaign.official.courtyard", "replaces_current_session":true}

func commit_pending_launch() -> Dictionary:
	if not _commit_allowed():
		return _reject(str(_pending_launch.get("campaign_id", "")), ["Campaign content can only be committed from the new-session bootstrap."])
	if _pending_launch.is_empty():
		return _rollback(["No campaign launch is pending."])
	var pending: Dictionary = _pending_launch.duplicate(true)
	if pending.get("kind") == "official":
		var registry = _registry()
		if registry == null or not registry.load_base_content():
			return _rollback(["Official content could not be restored."])
		_active_save_directory = OFFICIAL_SAVE_DIRECTORY
		_pending_launch.clear()
		_transition_scheduled = false
		last_error = ""
		var official_result := {"ok":true, "errors":[], "context":registry.content_context(),
			"save_directory":_active_save_directory, "auto_loads_save":false}
		session_activated.emit(official_result.context, _active_save_directory)
		return official_result
	var import_service = _import_service()
	var registry = _registry()
	if import_service == null or registry == null:
		return _rollback(["Campaign launch services are unavailable."])
	var inspected: Dictionary = import_service.inspect_campaign(str(pending.project_id), str(pending.campaign_id))
	if not inspected.ok:
		return _rollback(inspected.errors)
	if inspected.manifest.manifest_hash != pending.manifest_hash or inspected.manifest.content_hash != pending.content_hash:
		return _rollback(["Campaign package changed after it was queued."])
	if not registry.activate_campaign_content(inspected.content, inspected.manifest):
		return _rollback(registry.last_errors)
	_active_save_directory = str(pending.save_directory)
	_pending_launch.clear()
	_transition_scheduled = false
	last_error = ""
	var result := {"ok":true, "errors":[], "context":registry.content_context(),
		"save_directory":_active_save_directory, "auto_loads_save":false}
	session_activated.emit(result.context, _active_save_directory)
	return result

func active_save_directory() -> String:
	return _active_save_directory

func active_context() -> Dictionary:
	var registry = _registry()
	return registry.content_context() if registry != null else {}

func has_pending_launch() -> bool:
	return not _pending_launch.is_empty()

func clear_launch_previews() -> void:
	_previews.clear()
	_preview_order.clear()

func _official_library_entry() -> Dictionary:
	var context := active_context()
	return {"kind":"official", "project_id":"project.rpgmakerluna.courtyard",
		"campaign_id":"campaign.official.courtyard", "display_name":"苍石庭院",
		"activation_policy":"official", "available":true,
		"active":context.get("kind") == "official",
		"content_hash":str(context.get("content_hash", "")) if context.get("kind") == "official" else "",
		"manifest_hash":"", "source_draft_id":"official",
		"save_directory":OFFICIAL_SAVE_DIRECTORY,
		"slots":_slot_summaries(OFFICIAL_SAVE_DIRECTORY), "errors":[]}

func _campaign_library_entry(import_service, project_id: String, campaign_id: String) -> Dictionary:
	var campaign_path: String = import_service.projects_root.path_join(project_id).path_join("campaigns").path_join(campaign_id)
	var inspected: Dictionary = import_service.inspect_campaign(project_id, campaign_id)
	var context := active_context()
	if not inspected.ok:
		return {"kind":"campaign", "project_id":project_id, "campaign_id":campaign_id,
			"display_name":campaign_id, "activation_policy":"unknown", "available":false,
			"active":context.get("project_id") == project_id and context.get("campaign_id") == campaign_id,
			"content_hash":"", "manifest_hash":"", "source_draft_id":"",
			"save_directory":campaign_path.path_join("saves"), "slots":[],
			"errors":inspected.errors.duplicate()}
	var manifest: Dictionary = inspected.manifest
	var source: Dictionary = manifest.get("source_artifact", {})
	var save_directory := campaign_path.path_join(str(manifest.save_namespace))
	return {"kind":"campaign", "project_id":project_id, "campaign_id":campaign_id,
		"display_name":str(manifest.display_name),
		"activation_policy":str(manifest.activation_policy), "available":true,
		"active":context.get("project_id") == project_id and context.get("campaign_id") == campaign_id,
		"content_hash":str(manifest.content_hash), "manifest_hash":str(manifest.manifest_hash),
		"source_draft_id":str(source.get("draft_id", "")), "save_directory":save_directory,
		"slots":_slot_summaries(save_directory), "errors":[]}

func _slot_summaries(directory: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in SaveStore.new(directory).list_slots():
		var metadata: Dictionary = slot.get("metadata", {})
		result.append({"slot":int(slot.get("slot", 0)), "exists":bool(slot.get("exists", false)),
			"ok":bool(slot.get("ok", false)), "recovered":bool(slot.get("recovered", false)),
			"updated_at":int(metadata.get("updated_at", 0)), "error":str(slot.get("error", ""))})
	return result

func _scoped_id(value: String, prefix: String) -> bool:
	var expression := RegEx.new()
	if expression.compile("^" + prefix + "\\.[a-z0-9][a-z0-9_.-]+$") != OK:
		return false
	return value.length() <= 128 and expression.search(value) != null

func _rollback(errors: Array[String]) -> Dictionary:
	var campaign_id := str(_pending_launch.get("campaign_id", ""))
	var registry = _registry()
	var rollback_errors: Array[String] = errors.duplicate()
	if registry == null or not registry.load_base_content():
		rollback_errors.append("Official content rollback failed.")
	_active_save_directory = OFFICIAL_SAVE_DIRECTORY
	_pending_launch.clear()
	_transition_scheduled = false
	last_error = "; ".join(rollback_errors)
	session_launch_failed.emit(campaign_id, rollback_errors)
	return {"ok":false, "errors":rollback_errors, "context":registry.content_context() if registry != null else {},
		"save_directory":_active_save_directory}

func _commit_allowed() -> bool:
	if "--script" in OS.get_cmdline_args():
		return true
	var current = get_tree().current_scene
	return current != null and str(current.scene_file_path) == BOOTSTRAP_SCENE

func _change_to_bootstrap() -> void:
	var packed = load(BOOTSTRAP_SCENE)
	if not packed is PackedScene:
		_cancel_transition(["Could not load the campaign bootstrap scene; the current session was kept unchanged."])
		return
	if get_tree().change_scene_to_packed(packed) != OK:
		_cancel_transition(["Could not open the campaign bootstrap scene; the current session was kept unchanged."])
		return
	# Clear cross-scene state only after SceneTree accepted the replacement. A
	# bootstrap load/open failure therefore leaves the live session untouched.
	_clear_scene_handoff()

func _cancel_transition(errors: Array[String]) -> void:
	var campaign_id := str(_pending_launch.get("campaign_id", ""))
	_pending_launch.clear()
	_transition_scheduled = false
	last_error = "; ".join(errors)
	session_launch_failed.emit(campaign_id, errors)

func _clear_scene_handoff() -> void:
	var bridge = get_node_or_null("/root/GameSession")
	if bridge != null:
		bridge.pending = {}
		bridge.target_zone = "town"
	var workbench = get_node_or_null("/root/WorkbenchBridge")
	if workbench != null:
		workbench.clear_pending()
		workbench.unbind_runtime()

func _canonical_hash(value: Variant) -> String:
	var normalized = JSON.parse_string(JSON.stringify(value, "", true, true))
	return JSON.stringify(normalized, "", true, true).sha256_text()

func _registry():
	return get_node_or_null("/root/ContentRegistry")

func _import_service():
	return get_node_or_null("/root/CampaignImportService")

func _reject(campaign_id: String, errors: Array[String]) -> Dictionary:
	last_error = "; ".join(errors)
	session_launch_failed.emit(campaign_id, errors)
	return {"ok":false, "errors":errors, "campaign_id":campaign_id}
