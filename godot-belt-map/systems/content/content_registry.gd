extends Node
## Validated definitions plus reversible runtime overrides. Returned values are copies.

signal content_loaded(bundle_id: String, base_hash: String)
signal content_changed(revision: int, patch_id: String)
signal content_rejected(patch_id: String, errors: Array[String])

const Validator = preload("content_validator.gd")
const BASE_SKILLS_PATH := "res://content/base/skills.json"
const STATE_SCHEMA := "runtime-content-state/1"

var loaded := false
var revision := 0
var bundle_id := ""
var base_hash := ""
var last_errors: Array[String] = []
var _base_skills: Dictionary = {}
var _skills: Dictionary = {}
var _applied_patch_ids: Array[String] = []
var _history: Array[Dictionary] = []

func _ready() -> void:
	if not load_base_content():
		push_error("ContentRegistry rejected base content: " + "; ".join(last_errors))

func load_base_content(path := BASE_SKILLS_PATH) -> bool:
	last_errors.clear()
	if not FileAccess.file_exists(path):
		return _reject("base-load", ["Content bundle file does not exist: " + path])
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return _reject("base-load", ["Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]])
	var errors := Validator.validate_content_bundle(parser.data)
	if not errors.is_empty():
		return _reject("base-load", errors)
	var bundle: Dictionary = parser.data
	var next := {}
	for entry in bundle.entries:
		next[str(entry.id)] = entry.duplicate(true)
	_base_skills = next
	_skills = next.duplicate(true)
	bundle_id = str(bundle.bundle_id)
	base_hash = JSON.stringify(bundle, "", true, true).sha256_text()
	revision = 0
	_applied_patch_ids.clear()
	_history.clear()
	loaded = true
	content_loaded.emit(bundle_id, base_hash)
	return true

func get_skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {}).duplicate(true)

func registered_skill_ids() -> Array[String]:
	var result: Array[String] = []
	for id in _skills:
		result.append(str(id))
	result.sort()
	return result

func patchable_paths() -> Array[String]:
	var result: Array[String] = []
	for path in Validator.PATCHABLE_SKILL_PATHS:
		result.append(str(path))
	result.sort()
	return result

func was_patch_applied(patch_id: String) -> bool:
	return patch_id in _applied_patch_ids

func validate_runtime_patch(value: Variant, check_revision := true) -> Array[String]:
	var errors := Validator.validate_runtime_patch(value)
	if not value is Dictionary:
		return errors
	var patch: Dictionary = value
	if check_revision and _whole(patch.get("base_content_revision")) and int(patch.base_content_revision) != revision:
		errors.append("Patch base_content_revision %s does not match current revision %d." % [patch.get("base_content_revision"), revision])
	for operation in patch.get("operations", []):
		if operation is Dictionary:
			var target := str(operation.get("target_id", ""))
			if not target.is_empty() and not _skills.has(target):
				errors.append("Unknown patch target: " + target)
	return errors

func apply_runtime_patch(value: Variant) -> Dictionary:
	var patch_id := str(value.get("patch_id", "")) if value is Dictionary else ""
	if not patch_id.is_empty() and was_patch_applied(patch_id):
		return {"ok": true, "duplicate": true, "patch_id": patch_id, "revision": revision, "errors": []}
	var errors := validate_runtime_patch(value)
	if not errors.is_empty():
		_reject(patch_id, errors)
		return {"ok": false, "duplicate": false, "patch_id": patch_id, "revision": revision, "errors": errors}
	var patch: Dictionary = value
	var candidate: Dictionary = _skills.duplicate(true)
	for operation in patch.operations:
		_set_path(candidate[str(operation.target_id)], str(operation.path), operation.value)
	var affected := {}
	for operation in patch.operations:
		affected[str(operation.target_id)] = true
	for target in affected:
		errors.append_array(Validator.validate_skill(candidate[target], "patched[" + target + "]"))
	if not errors.is_empty():
		_reject(patch_id, errors)
		return {"ok": false, "duplicate": false, "patch_id": patch_id, "revision": revision, "errors": errors}
	_history.append({"patch_id": patch_id, "skills": _skills.duplicate(true), "applied_ids": _applied_patch_ids.duplicate()})
	_skills = candidate
	_applied_patch_ids.append(patch_id)
	revision += 1
	content_changed.emit(revision, patch_id)
	return {"ok": true, "duplicate": false, "patch_id": patch_id, "revision": revision, "errors": []}

func undo_last_patch() -> Dictionary:
	if _history.is_empty():
		return {"ok": false, "revision": revision, "patch_id": "", "errors": ["No runtime patch is available to undo."]}
	var previous: Dictionary = _history.pop_back()
	var patch_id := str(previous.patch_id)
	_skills = previous.skills.duplicate(true)
	_applied_patch_ids.assign(previous.applied_ids)
	revision += 1
	content_changed.emit(revision, "undo:" + patch_id)
	return {"ok": true, "revision": revision, "patch_id": patch_id, "errors": []}

func export_runtime_state() -> Dictionary:
	var overrides := {}
	for id in _skills:
		var changed := {}
		for path in Validator.PATCHABLE_SKILL_PATHS:
			var current = _get_path(_skills[id], path)
			var original = _get_path(_base_skills[id], path)
			if current != original:
				changed[path] = current
		if not changed.is_empty():
			overrides[id] = changed
	return {"schema_version": STATE_SCHEMA, "base_hash": base_hash, "revision": revision,
		"overrides": overrides, "applied_patch_ids": _applied_patch_ids.duplicate()}

func empty_runtime_state() -> Dictionary:
	return {"schema_version": STATE_SCHEMA, "base_hash": base_hash, "revision": 0,
		"overrides": {}, "applied_patch_ids": []}

func validate_runtime_state(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Runtime content state must be an object."]
	var state: Dictionary = value
	for key in state:
		if key not in ["schema_version", "base_hash", "revision", "overrides", "applied_patch_ids"]:
			errors.append("Runtime content state contains unsupported field: " + str(key))
	if state.get("schema_version") != STATE_SCHEMA:
		errors.append("Unsupported runtime content state schema_version.")
	if state.get("base_hash") != base_hash:
		errors.append("Runtime content state targets a different base bundle.")
	if not _whole(state.get("revision")) or int(state.get("revision", -1)) < 0:
		errors.append("Runtime content revision must be a non-negative integer.")
	var ids = state.get("applied_patch_ids")
	if not ids is Array or ids.size() > 512:
		errors.append("applied_patch_ids must be an array of at most 512 ids.")
	else:
		var seen := {}
		for id in ids:
			if not id is String or str(id).is_empty() or str(id).length() > 128 or seen.has(id):
				errors.append("applied_patch_ids contains an invalid or duplicate id.")
				break
			seen[id] = true
	var overrides = state.get("overrides")
	if not overrides is Dictionary or overrides.size() > 512:
		errors.append("Runtime content overrides must be an object of at most 512 skills.")
		return errors
	var candidate := _base_skills.duplicate(true)
	for id in overrides:
		if not id is String or not candidate.has(id) or not overrides[id] is Dictionary:
			errors.append("Runtime content override targets an unknown skill: " + str(id))
			continue
		for path in overrides[id]:
			errors.append_array(Validator.validate_patch_value(str(path), overrides[id][path], "overrides[%s][%s]" % [id, path]))
			if Validator.PATCHABLE_SKILL_PATHS.has(path):
				_set_path(candidate[id], path, overrides[id][path])
		errors.append_array(Validator.validate_skill(candidate[id], "overrides[" + id + "]"))
	return errors

func restore_runtime_state(value: Variant) -> bool:
	var errors := validate_runtime_state(value)
	if not errors.is_empty():
		last_errors.assign(errors)
		return false
	var state: Dictionary = value
	# Scene handoff carries the same state through the Autoload. Preserve the
	# in-session undo stack when no actual content change is being restored.
	if export_runtime_state() == state:
		return true
	var candidate := _base_skills.duplicate(true)
	for id in state.overrides:
		for path in state.overrides[id]:
			_set_path(candidate[id], str(path), state.overrides[id][path])
	_skills = candidate
	revision = int(state.revision)
	_applied_patch_ids.assign(state.applied_patch_ids)
	_history.clear()
	content_changed.emit(revision, "state-restore")
	return true

func _set_path(definition: Dictionary, path: String, value: Variant) -> void:
	match path:
		"/resource_cost/amount": definition.resource_cost.amount = value
		"/cooldown_seconds": definition.cooldown_seconds = value
		"/combat/base_damage": definition.combat.base_damage = value
		"/combat/depth_radius": definition.combat.depth_radius = value
		"/combat/chain_count": definition.combat.chain_count = value
		"/combat/chain_radius_m": definition.combat.chain_radius_m = value

func _get_path(definition: Dictionary, path: String) -> Variant:
	match path:
		"/resource_cost/amount": return definition.resource_cost.amount
		"/cooldown_seconds": return definition.cooldown_seconds
		"/combat/base_damage": return definition.combat.base_damage
		"/combat/depth_radius": return definition.combat.depth_radius
		"/combat/chain_count": return definition.combat.chain_count
		"/combat/chain_radius_m": return definition.combat.chain_radius_m
	return null

func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value)

func _reject(patch_id: String, errors: Array[String]) -> bool:
	last_errors.assign(errors)
	content_rejected.emit(patch_id, last_errors)
	return false
