extends Node
## In-process contract for the future web/Agent bridge. It never evaluates code.

signal patch_queued(patch_id: String, queue_size: int)
signal patch_applied(result: Dictionary)
signal patch_rejected(result: Dictionary)
signal patch_undone(result: Dictionary)

const Validator = preload("res://systems/content/content_validator.gd")
const MAX_PENDING := 32
const ROLE_TARGET_TYPES := {
	"narrative": ["quest", "dialogue"],
	"world": [],
	"npc": ["npc", "dialogue"],
	"systems": ["skill", "equipment"],
	"validator": ["skill", "equipment", "npc", "quest", "dialogue"]
}
var runtime = null
var pending: Array[Dictionary] = []

func bind_runtime(value) -> void:
	runtime = value
	if value is Node:
		var bound = value
		value.tree_exiting.connect(func():
			if runtime == bound:
				runtime = null
		, CONNECT_ONE_SHOT)

func unbind_runtime() -> void:
	runtime = null

func capabilities() -> Dictionary:
	var registry = _registry()
	return {
		"schema_version": "workbench-capabilities/1",
		"runtime_patch_schema": "runtime-patch/1",
		"agent_task_schema": "agent-task/1",
		"agent_result_schema": "agent-result/1",
		"content_draft_schema": "content-draft/1",
		"published_content_schema": "published-content/1",
		"campaign_import_request_schema": "campaign-import-request/1",
		"campaign_manifest_schema": "campaign-manifest/1",
		"campaign_content_schema": "campaign-content/1",
		"content_revision": registry.revision if registry != null else -1,
		"catalog_hash": registry.catalog_hash if registry != null else "",
		"targets": registry.registered_skill_ids() if registry != null else [],
		"targets_by_type": registry.registered_targets() if registry != null else {},
		"patchable_paths": registry.patchable_paths() if registry != null else [],
		"agent_roles": Validator.AGENT_ROLES.duplicate(),
		"role_target_types": ROLE_TARGET_TYPES.duplicate(true),
		"draft_target_types": ["quest", "dialogue", "npc"],
		"published_content_activation": "new_campaign_import",
		"campaign_activation_policies": ["new_campaign", "explicit_project_copy"],
		"campaign_session_activation": "scene_bootstrap_new_session_only",
		"campaign_library": "validated_read_only_with_save_slot_summaries",
		"content_context": registry.content_context() if registry != null else {},
		"active_save_directory": _campaign_session().active_save_directory() if _campaign_session() != null else "user://rpg_saves",
		"safe_to_apply": safe_to_apply(),
		"pending_count": pending.size(),
		"allows_generated_code": false
	}

func inspect_target(target_type: String, target_id: String) -> Dictionary:
	## Agents read the current validated definition before proposing a patch.
	## Copies prevent the transport or UI layer from mutating live content.
	var registry = _registry()
	if registry == null or not registry.target_exists(target_type, target_id):
		return {}
	return {"target_type":target_type, "target_id":target_id, "content_revision":registry.revision,
		"catalog_hash":registry.catalog_hash, "definition":registry.get_definition(target_type, target_id)}

func validate_agent_task(value: Variant) -> Array[String]:
	var errors := Validator.validate_agent_task(value)
	var registry = _registry()
	if registry == null or not registry.loaded:
		errors.append("ContentRegistry is unavailable.")
		return errors
	if not value is Dictionary:
		return errors
	var task: Dictionary = value
	if _whole(task.get("content_revision")) and int(task.content_revision) != registry.revision:
		errors.append("Agent task content_revision does not match the current registry revision.")
	var role := str(task.get("agent_role", ""))
	var allowed_types: Array = ROLE_TARGET_TYPES.get(role, [])
	var allow_new_ids := bool(task.get("constraints", {}).get("allow_new_ids", false)) if task.get("constraints", {}) is Dictionary else false
	if allow_new_ids and role not in ["narrative", "npc"]:
		errors.append("Only Narrative or NPC Agents may propose new draft IDs.")
	for field in ["allowed_targets", "context_refs"]:
		for ref in task.get(field, []):
			if not ref is Dictionary:
				continue
			var target_type := str(ref.get("target_type", ""))
			var target_id := str(ref.get("target_id", ""))
			if not registry.target_exists(target_type, target_id) and (field == "context_refs" or not allow_new_ids):
				errors.append("Unknown %s target: %s:%s" % [field, target_type, target_id])
			if field == "allowed_targets" and target_type not in allowed_types:
				errors.append("Agent role %s cannot propose changes for %s targets." % [role, target_type])
	return errors

func review_agent_result(task_value: Variant, result_value: Variant) -> Dictionary:
	## Validation is deliberately non-mutating. Main Agent must explicitly send each
	## returned runtime patch through submit_patch(), preserving safe-point checks.
	var errors := validate_agent_task(task_value)
	errors.append_array(Validator.validate_agent_result(result_value))
	if not task_value is Dictionary or not result_value is Dictionary:
		return {"ok":false, "errors":errors, "actionable_patches":[], "content_drafts":[]}
	var task: Dictionary = task_value
	var result: Dictionary = result_value
	if result.get("request_id") != task.get("request_id"):
		errors.append("Agent result request_id does not match its task.")
	if result.get("agent_role") != task.get("agent_role"):
		errors.append("Agent result role does not match its task.")
	var deliverables: Array = result.get("deliverables", []) if result.get("deliverables", []) is Array else []
	var maximum := int(task.get("constraints", {}).get("max_proposals", 0)) if task.get("constraints", {}) is Dictionary else 0
	if deliverables.size() > maximum:
		errors.append("Agent result exceeds task.constraints.max_proposals.")
	var allowed := {}
	for ref in task.get("allowed_targets", []):
		if ref is Dictionary:
			allowed[str(ref.get("target_type", "")) + ":" + str(ref.get("target_id", ""))] = true
	var readable := allowed.duplicate()
	for ref in task.get("context_refs", []):
		if ref is Dictionary:
			readable[str(ref.get("target_type", "")) + ":" + str(ref.get("target_id", ""))] = true
	var actionable: Array[Dictionary] = []
	var content_drafts: Array[Dictionary] = []
	for deliverable in deliverables:
		if not deliverable is Dictionary:
			continue
		if deliverable.get("kind") == "analysis":
			var key := str(deliverable.get("target_type", "")) + ":" + str(deliverable.get("target_id", ""))
			if not readable.has(key):
				errors.append("Analysis deliverable targets content outside the task context: " + key)
		elif deliverable.get("kind") == "runtime_patch" and deliverable.get("payload") is Dictionary:
			if task.get("agent_role") != "systems":
				errors.append("Only the systems Agent may propose runtime patches.")
			var patch: Dictionary = deliverable.payload
			errors.append_array(_registry().validate_runtime_patch(patch))
			for operation in patch.get("operations", []):
				if operation is Dictionary:
					var key := str(operation.get("target_type", "")) + ":" + str(operation.get("target_id", ""))
					if not allowed.has(key):
						errors.append("Runtime patch targets content outside task.allowed_targets: " + key)
			actionable.append(patch.duplicate(true))
		elif deliverable.get("kind") == "content_draft" and deliverable.get("payload") is Dictionary:
			var draft: Dictionary = deliverable.payload
			if task.get("agent_role") not in ["narrative", "npc"] or draft.get("author_role") != task.get("agent_role"):
				errors.append("Content draft author_role must match its Narrative or NPC Agent task.")
			if draft.get("project_id") != task.get("project_id"):
				errors.append("Content draft project_id must match its Agent task.")
			for operation in draft.get("operations", []):
				if operation is Dictionary:
					var key := str(operation.get("target_type", "")) + ":" + str(operation.get("target_id", ""))
					if not allowed.has(key):
						errors.append("Content draft targets content outside task.allowed_targets: " + key)
			var draft_service = _draft_service()
			if draft_service == null:
				errors.append("ContentDraftService is unavailable.")
			else:
				errors.append_array(draft_service.validate_draft(draft))
			content_drafts.append(draft.duplicate(true))
	if result.get("status") != "completed" and (not actionable.is_empty() or not content_drafts.is_empty()):
		errors.append("Incomplete or blocked Agent results cannot contain actionable proposals.")
	return {"ok":errors.is_empty(), "errors":errors,
		"actionable_patches":actionable if errors.is_empty() else [],
		"content_drafts":content_drafts if errors.is_empty() else []}

func preview_content_draft(value: Variant) -> Dictionary:
	var service = _draft_service()
	if service == null:
		return _reject(str(value.get("draft_id", "")) if value is Dictionary else "", ["ContentDraftService is unavailable."])
	return service.preview_draft(value)

func publish_content_draft(value: Variant, preview_token: String) -> Dictionary:
	## Publishing writes an immutable data artifact only. It never hot-replaces the
	## active campaign; activation belongs to a future isolated campaign importer.
	var service = _draft_service()
	if service == null:
		return _reject(str(value.get("draft_id", "")) if value is Dictionary else "", ["ContentDraftService is unavailable."])
	return service.publish_draft(value, preview_token)

func preview_campaign_import(value: Variant) -> Dictionary:
	var service = _campaign_service()
	if service == null:
		return {"ok":false, "errors":["CampaignImportService is unavailable."],
			"campaign_id":str(value.get("campaign_id", "")) if value is Dictionary else ""}
	return service.preview_import(value)

func install_campaign(value: Variant, preview_token: String) -> Dictionary:
	## Installation only creates an isolated package. A future launcher must start
	## a fresh session and use the manifest's separate save namespace.
	var service = _campaign_service()
	if service == null:
		return {"ok":false, "errors":["CampaignImportService is unavailable."],
			"campaign_id":str(value.get("campaign_id", "")) if value is Dictionary else ""}
	return service.install_campaign(value, preview_token)

func inspect_campaign(project_id: String, campaign_id: String) -> Dictionary:
	var service = _campaign_service()
	if service == null:
		return {"ok":false, "errors":["CampaignImportService is unavailable."], "manifest":{}}
	return service.inspect_campaign(project_id, campaign_id)

func list_campaigns(project_id: String = "") -> Dictionary:
	var service = _campaign_session()
	if service == null:
		return {"ok":false, "errors":["CampaignSessionService is unavailable."],
			"campaigns":[], "active_context":{}}
	return service.list_campaigns(project_id)

func preview_campaign_launch(project_id: String, campaign_id: String) -> Dictionary:
	var service = _campaign_session()
	if service == null:
		return {"ok":false, "errors":["CampaignSessionService is unavailable."], "campaign_id":campaign_id}
	return service.preview_campaign_launch(project_id, campaign_id)

func preview_official_launch() -> Dictionary:
	var service = _campaign_session()
	if service == null:
		return {"ok":false, "errors":["CampaignSessionService is unavailable."]}
	return service.preview_official_launch()

func start_campaign_session(project_id: String, campaign_id: String, launch_token: String) -> Dictionary:
	var service = _campaign_session()
	if service == null:
		return {"ok":false, "errors":["CampaignSessionService is unavailable."], "campaign_id":campaign_id}
	return service.start_campaign_session(project_id, campaign_id, launch_token)

func start_official_session() -> Dictionary:
	var service = _campaign_session()
	if service == null:
		return {"ok":false, "errors":["CampaignSessionService is unavailable."]}
	return service.start_official_session()

func submit_patch(value: Variant) -> Dictionary:
	var registry = _registry()
	if registry == null or not registry.loaded:
		return _reject("", ["ContentRegistry is unavailable."])
	var patch_id := str(value.get("patch_id", "")) if value is Dictionary else ""
	if registry.was_patch_applied(patch_id):
		return registry.apply_runtime_patch(value)
	var errors: Array[String] = registry.validate_runtime_patch(value)
	if not errors.is_empty():
		return _reject(patch_id, errors)
	if not safe_to_apply():
		if pending.size() >= MAX_PENDING:
			return _reject(patch_id, ["Runtime patch queue is full."])
		for queued in pending:
			if queued.patch_id == patch_id:
				return {"ok": true, "queued": true, "duplicate": true, "patch_id": patch_id,
					"revision": registry.revision, "errors": []}
		pending.append(value.duplicate(true))
		patch_queued.emit(patch_id, pending.size())
		return {"ok": true, "queued": true, "duplicate": false, "patch_id": patch_id,
			"revision": registry.revision, "errors": []}
	return _apply(value)

func process_pending() -> Dictionary:
	if pending.is_empty() or not safe_to_apply():
		return {"ok": false, "idle": true, "pending_count": pending.size()}
	var patch: Dictionary = pending.pop_front()
	return _apply(patch)

func request_undo() -> Dictionary:
	if not safe_to_apply():
		return {"ok": false, "revision": _registry().revision if _registry() != null else -1,
			"errors": ["Runtime is not at a safe patch point."]}
	var result: Dictionary = _registry().undo_last_patch()
	if result.ok:
		patch_undone.emit(result)
	else:
		patch_rejected.emit(result)
	return result

func clear_pending() -> void:
	pending.clear()

func safe_to_apply() -> bool:
	return is_instance_valid(runtime) and runtime.has_method("safe_to_save") and runtime.safe_to_save()

func _apply(patch: Dictionary) -> Dictionary:
	var result: Dictionary = _registry().apply_runtime_patch(patch)
	result["queued"] = false
	if result.ok:
		patch_applied.emit(result)
	else:
		patch_rejected.emit(result)
	return result

func _reject(patch_id: String, errors: Array[String]) -> Dictionary:
	var registry = _registry()
	var result := {"ok": false, "queued": false, "duplicate": false, "patch_id": patch_id,
		"revision": registry.revision if registry != null else -1, "errors": errors}
	patch_rejected.emit(result)
	return result

func _registry():
	return get_node_or_null("/root/ContentRegistry")

func _draft_service():
	return get_node_or_null("/root/ContentDraftService")

func _campaign_service():
	return get_node_or_null("/root/CampaignImportService")

func _campaign_session():
	return get_node_or_null("/root/CampaignSessionService")

func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value)
