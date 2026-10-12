extends RefCounted
## Strict validation boundary for authored or Agent-generated RPG content.
## Generated data can tune registered definitions, but cannot inject code or paths.

const CONTENT_BUNDLE_SCHEMA := "rpg-content-bundle/1"
const RUNTIME_PATCH_SCHEMA := "runtime-patch/1"
const RUNTIME_STATE_SCHEMA := "runtime-content-state/1"
const PATCHABLE_SKILL_PATHS := {
	"/resource_cost/amount": {"min": 0.0, "max": 999.0, "integer": false},
	"/cooldown_seconds": {"min": 0.0, "max": 600.0, "integer": false},
	"/combat/base_damage": {"min": 0.0, "max": 100000.0, "integer": false},
	"/combat/depth_radius": {"min": 0.05, "max": 3.0, "integer": false},
	"/combat/chain_count": {"min": 1.0, "max": 8.0, "integer": true},
	"/combat/chain_radius_m": {"min": 0.0, "max": 12.0, "integer": false}
}

static func validate_content_bundle(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Content bundle must be a JSON object."]
	var bundle: Dictionary = value
	_unknown_keys(bundle, ["schema_version", "bundle_id", "content_type", "entries"], "bundle", errors)
	_require_string(bundle, "bundle_id", "bundle", errors)
	if bundle.get("schema_version") != CONTENT_BUNDLE_SCHEMA:
		errors.append("Unsupported content bundle schema_version.")
	if bundle.get("content_type") != "skills":
		errors.append("Only the registered skills content type is supported.")
	var entries = bundle.get("entries")
	if not entries is Array:
		errors.append("bundle.entries must be an array.")
		return errors
	if entries.is_empty() or entries.size() > 512:
		errors.append("bundle.entries must contain between 1 and 512 definitions.")
	var seen := {}
	for index in entries.size():
		var location := "bundle.entries[%d]" % index
		errors.append_array(validate_skill(entries[index], location))
		if entries[index] is Dictionary:
			var id := str(entries[index].get("id", ""))
			if seen.has(id):
				errors.append("Duplicate content id: " + id)
			seen[id] = true
	return errors

static func validate_skill(value: Variant, location := "skill") -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return [location + " must be an object."]
	var skill: Dictionary = value
	_unknown_keys(skill, ["id", "kind", "display_name", "description", "action_profile_id", "resource_cost", "cooldown_seconds", "combat", "presentation"], location, errors)
	for key in ["id", "kind", "display_name", "description", "action_profile_id"]:
		_require_string(skill, key, location, errors)
	if not _registered_id(str(skill.get("id", "")), "skill"):
		errors.append(location + ".id must be a canonical skill id.")
	if skill.get("kind") != "skill":
		errors.append(location + ".kind must equal 'skill'.")
	if str(skill.get("display_name", "")).length() > 64:
		errors.append(location + ".display_name exceeds 64 characters.")
	if str(skill.get("description", "")).length() > 240:
		errors.append(location + ".description exceeds 240 characters.")
	if not _registered_id(str(skill.get("action_profile_id", "")), "action"):
		errors.append(location + ".action_profile_id must be a canonical action id.")
	var cost = skill.get("resource_cost")
	if not cost is Dictionary:
		errors.append(location + ".resource_cost must be an object.")
	else:
		_unknown_keys(cost, ["type", "amount"], location + ".resource_cost", errors)
		if cost.get("type") not in ["mp", "stamina", "none"]:
			errors.append(location + ".resource_cost.type is unsupported.")
		_validate_number(cost.get("amount"), 0.0, 999.0, false, location + ".resource_cost.amount", errors)
	_validate_number(skill.get("cooldown_seconds"), 0.0, 600.0, false, location + ".cooldown_seconds", errors)
	var combat = skill.get("combat")
	if not combat is Dictionary:
		errors.append(location + ".combat must be an object.")
	else:
		_unknown_keys(combat, ["base_damage", "depth_radius", "chain_count", "chain_radius_m", "tags"], location + ".combat", errors)
		_validate_number(combat.get("base_damage"), 0.0, 100000.0, false, location + ".combat.base_damage", errors)
		_validate_number(combat.get("depth_radius"), 0.05, 3.0, false, location + ".combat.depth_radius", errors)
		_validate_number(combat.get("chain_count"), 1.0, 8.0, true, location + ".combat.chain_count", errors)
		_validate_number(combat.get("chain_radius_m"), 0.0, 12.0, false, location + ".combat.chain_radius_m", errors)
		var tags = combat.get("tags")
		if not tags is Array or tags.size() > 32:
			errors.append(location + ".combat.tags must be an array of at most 32 tags.")
		elif tags.size() != _unique_strings(tags).size():
			errors.append(location + ".combat.tags must contain unique non-empty strings.")
	var presentation = skill.get("presentation")
	if not presentation is Dictionary:
		errors.append(location + ".presentation must be an object.")
	else:
		_unknown_keys(presentation, ["vfx_id", "sfx_id"], location + ".presentation", errors)
		for pair in [["vfx_id", "vfx"], ["sfx_id", "sfx"]]:
			if not _registered_id(str(presentation.get(pair[0], "")), pair[1]):
				errors.append(location + ".presentation." + pair[0] + " must be a canonical registered id.")
	return errors

static func validate_runtime_patch(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Runtime patch must be a JSON object."]
	var patch: Dictionary = value
	_unknown_keys(patch, ["schema_version", "patch_id", "base_content_revision", "operations"], "patch", errors)
	if patch.get("schema_version") != RUNTIME_PATCH_SCHEMA:
		errors.append("Unsupported runtime patch schema_version.")
	_require_string(patch, "patch_id", "patch", errors)
	if str(patch.get("patch_id", "")).length() > 128:
		errors.append("patch.patch_id exceeds 128 characters.")
	_validate_number(patch.get("base_content_revision"), 0.0, 2147483647.0, true, "patch.base_content_revision", errors)
	var operations = patch.get("operations")
	if not operations is Array:
		errors.append("patch.operations must be an array.")
		return errors
	if operations.is_empty() or operations.size() > 64:
		errors.append("patch.operations must contain between 1 and 64 operations.")
	for index in operations.size():
		var location := "patch.operations[%d]" % index
		var operation = operations[index]
		if not operation is Dictionary:
			errors.append(location + " must be an object.")
			continue
		_unknown_keys(operation, ["op", "target_type", "target_id", "path", "value"], location, errors)
		if operation.get("op") != "replace":
			errors.append(location + ".op must equal 'replace'.")
		if operation.get("target_type") != "skill":
			errors.append(location + ".target_type must equal 'skill'.")
		if not _registered_id(str(operation.get("target_id", "")), "skill"):
			errors.append(location + ".target_id must be a canonical skill id.")
		var path := str(operation.get("path", ""))
		if not PATCHABLE_SKILL_PATHS.has(path):
			errors.append(location + ".path is not patchable: " + path)
			continue
		var limits: Dictionary = PATCHABLE_SKILL_PATHS[path]
		_validate_number(operation.get("value"), limits.min, limits.max, limits.integer, location + ".value", errors)
	return errors

static func validate_patch_value(path: String, value: Variant, location := "value") -> Array[String]:
	var errors: Array[String] = []
	if not PATCHABLE_SKILL_PATHS.has(path):
		return [location + " uses an unsupported path: " + path]
	var limits: Dictionary = PATCHABLE_SKILL_PATHS[path]
	_validate_number(value, limits.min, limits.max, limits.integer, location, errors)
	return errors

static func _unknown_keys(value: Dictionary, allowed: Array, location: String, errors: Array[String]) -> void:
	for key in value:
		if not key is String or key not in allowed:
			errors.append(location + " contains unsupported field: " + str(key))

static func _require_string(value: Dictionary, key: String, location: String, errors: Array[String]) -> void:
	if not value.get(key) is String or str(value.get(key)).strip_edges().is_empty():
		errors.append(location + "." + key + " must be a non-empty string.")

static func _validate_number(value: Variant, minimum: float, maximum: float, integer: bool, location: String, errors: Array[String]) -> void:
	if not (value is int or value is float) or not is_finite(float(value)):
		errors.append(location + " must be a finite number.")
		return
	var number := float(value)
	if number < minimum or number > maximum or (integer and floorf(number) != number):
		errors.append("%s must be %s between %s and %s." % [location, "an integer" if integer else "a number", minimum, maximum])

static func _registered_id(value: String, id_prefix: String) -> bool:
	if value.length() > 128:
		return false
	var expression := RegEx.new()
	return expression.compile("^" + id_prefix + "\\.[a-z0-9][a-z0-9_.-]+$") == OK and expression.search(value) != null

static func _unique_strings(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		if not value is String or str(value).strip_edges().is_empty() or str(value).length() > 64:
			return {}
		result[value] = true
	return result
