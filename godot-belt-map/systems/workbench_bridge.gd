extends Node
## In-process contract for the future web/Agent bridge. It never evaluates code.

signal patch_queued(patch_id: String, queue_size: int)
signal patch_applied(result: Dictionary)
signal patch_rejected(result: Dictionary)
signal patch_undone(result: Dictionary)

const MAX_PENDING := 32
var runtime = null
var pending: Array[Dictionary] = []

func bind_runtime(value) -> void:
	runtime = value

func capabilities() -> Dictionary:
	var registry = _registry()
	return {
		"schema_version": "workbench-capabilities/1",
		"runtime_patch_schema": "runtime-patch/1",
		"content_revision": registry.revision if registry != null else -1,
		"targets": registry.registered_skill_ids() if registry != null else [],
		"patchable_paths": registry.patchable_paths() if registry != null else [],
		"safe_to_apply": safe_to_apply(),
		"pending_count": pending.size(),
		"allows_generated_code": false
	}

func inspect_target(target_type: String, target_id: String) -> Dictionary:
	## Agents read the current validated definition before proposing a patch.
	## Copies prevent the transport or UI layer from mutating live content.
	var registry = _registry()
	if registry == null or target_type != "skill":
		return {}
	return {"target_type":"skill", "target_id":target_id, "content_revision":registry.revision,
		"definition":registry.get_skill(target_id)} if target_id in registry.registered_skill_ids() else {}

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
