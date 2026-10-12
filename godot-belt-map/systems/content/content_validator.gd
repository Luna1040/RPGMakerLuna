extends RefCounted
## Strict validation boundary for authored or Agent-generated RPG content.
## Generated data can tune registered definitions, but cannot inject code or paths.

const CONTENT_BUNDLE_SCHEMA := "rpg-content-bundle/1"
const RUNTIME_PATCH_SCHEMA := "runtime-patch/1"
const RUNTIME_STATE_SCHEMA := "runtime-content-state/1"
const AGENT_TASK_SCHEMA := "agent-task/1"
const AGENT_RESULT_SCHEMA := "agent-result/1"
const CONTENT_DRAFT_SCHEMA := "content-draft/1"
const PUBLISHED_CONTENT_SCHEMA := "published-content/1"
const CAMPAIGN_IMPORT_REQUEST_SCHEMA := "campaign-import-request/1"
const CAMPAIGN_CONTENT_SCHEMA := "campaign-content/1"
const CAMPAIGN_MANIFEST_SCHEMA := "campaign-manifest/1"
const WorldBlueprint = preload("res://systems/content/world_blueprint_service.gd")
const CONTENT_TYPES := ["skills", "equipment", "npcs"]
const TARGET_TYPES := ["skill", "equipment", "item", "shop", "npc", "quest", "dialogue"]
const AGENT_ROLES := ["narrative", "world", "npc", "systems", "validator"]
const DRAFT_AUTHOR_ROLES := ["main", "narrative", "npc", "systems"]
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
	var content_type := str(bundle.get("content_type", ""))
	if content_type not in CONTENT_TYPES:
		errors.append("Unsupported content type: " + content_type)
	var entries = bundle.get("entries")
	if not entries is Array:
		errors.append("bundle.entries must be an array.")
		return errors
	if entries.is_empty() or entries.size() > 512:
		errors.append("bundle.entries must contain between 1 and 512 definitions.")
	var seen := {}
	for index in entries.size():
		var location := "bundle.entries[%d]" % index
		match content_type:
			"skills": errors.append_array(validate_skill(entries[index], location))
			"equipment": errors.append_array(validate_equipment(entries[index], location))
			"npcs": errors.append_array(validate_town_npc(entries[index], location))
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
	_validate_text(skill.get("display_name"), 64, location + ".display_name", errors)
	_validate_text(skill.get("description"), 240, location + ".description", errors)
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
		_validate_string_array(combat.get("tags"), 32, 64, location + ".combat.tags", errors)
	var presentation = skill.get("presentation")
	if not presentation is Dictionary:
		errors.append(location + ".presentation must be an object.")
	else:
		_unknown_keys(presentation, ["vfx_id", "sfx_id"], location + ".presentation", errors)
		for pair in [["vfx_id", "vfx"], ["sfx_id", "sfx"]]:
			if not _registered_id(str(presentation.get(pair[0], "")), pair[1]):
				errors.append(location + ".presentation." + pair[0] + " must be a canonical registered id.")
	return errors

static func validate_equipment(value: Variant, location := "equipment") -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return [location + " must be an object."]
	var item: Dictionary = value
	_unknown_keys(item, ["id", "kind", "name", "slot", "quality", "symbol", "description", "stats"], location, errors)
	for key in ["id", "kind", "name", "slot", "quality", "symbol", "description"]:
		_require_string(item, key, location, errors)
	if not _simple_id(str(item.get("id", ""))):
		errors.append(location + ".id must be a stable snake_case id.")
	if item.get("kind") != "equipment":
		errors.append(location + ".kind must equal 'equipment'.")
	if item.get("slot") not in ["weapon", "armor", "charm", "boots"]:
		errors.append(location + ".slot is unsupported.")
	_validate_text(item.get("name"), 64, location + ".name", errors)
	_validate_text(item.get("quality"), 32, location + ".quality", errors)
	_validate_text(item.get("symbol"), 8, location + ".symbol", errors)
	_validate_text(item.get("description"), 240, location + ".description", errors)
	var stats = item.get("stats")
	if not stats is Dictionary or stats.size() > 7:
		errors.append(location + ".stats must be an object with at most 7 stats.")
	else:
		for stat in stats:
			if stat not in ["health", "mana", "attack", "magic", "defense", "speed", "regen"]:
				errors.append(location + ".stats contains an unsupported stat: " + str(stat))
			else:
				_validate_number(stats[stat], -10000.0, 10000.0, false, location + ".stats." + str(stat), errors)
	return errors

static func validate_town_npc(value: Variant, location := "npc") -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return [location + " must be an object."]
	var npc: Dictionary = value
	_unknown_keys(npc, ["id", "kind", "display_name", "position_m", "visual", "ambient_lines"], location, errors)
	for key in ["id", "kind", "display_name"]:
		_require_string(npc, key, location, errors)
	if not _simple_id(str(npc.get("id", ""))):
		errors.append(location + ".id must be a stable snake_case id.")
	if npc.get("kind") != "npc":
		errors.append(location + ".kind must equal 'npc'.")
	_validate_text(npc.get("display_name"), 64, location + ".display_name", errors)
	_validate_number_array(npc.get("position_m"), 2, -10000.0, 10000.0, location + ".position_m", errors)
	_validate_string_array(npc.get("ambient_lines"), 32, 400, location + ".ambient_lines", errors, 1)
	var visual = npc.get("visual")
	if not visual is Dictionary:
		errors.append(location + ".visual must be an object.")
	else:
		_unknown_keys(visual, ["base_asset_id", "idle_manifest_asset_id", "pivot_px", "drawn_height_px", "portrait_region_px"], location + ".visual", errors)
		for key in ["base_asset_id", "idle_manifest_asset_id"]:
			if not _registered_id(str(visual.get(key, "")), "asset"):
				errors.append(location + ".visual." + key + " must be a registered asset id.")
		_validate_number_array(visual.get("pivot_px"), 2, -10000.0, 10000.0, location + ".visual.pivot_px", errors)
		_validate_number(visual.get("drawn_height_px"), 1.0, 10000.0, false, location + ".visual.drawn_height_px", errors)
		_validate_number_array(visual.get("portrait_region_px"), 4, 0.0, 10000.0, location + ".visual.portrait_region_px", errors)
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

static func validate_agent_task(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Agent task must be a JSON object."]
	var task: Dictionary = value
	_unknown_keys(task, ["schema_version", "request_id", "project_id", "content_revision", "agent_role", "objective", "allowed_targets", "constraints", "context_refs"], "task", errors)
	if task.get("schema_version") != AGENT_TASK_SCHEMA:
		errors.append("Unsupported agent task schema_version.")
	for pair in [["request_id", "request"], ["project_id", "project"]]:
		if not _registered_id(str(task.get(pair[0], "")), pair[1]):
			errors.append("task." + pair[0] + " must be a canonical " + pair[1] + " id.")
	_validate_number(task.get("content_revision"), 0.0, 2147483647.0, true, "task.content_revision", errors)
	if task.get("agent_role") not in AGENT_ROLES:
		errors.append("task.agent_role is unsupported.")
	_validate_text(task.get("objective"), 1000, "task.objective", errors)
	_validate_target_refs(task.get("allowed_targets"), 64, "task.allowed_targets", errors)
	_validate_target_refs(task.get("context_refs"), 128, "task.context_refs", errors)
	var constraints = task.get("constraints")
	if not constraints is Dictionary:
		errors.append("task.constraints must be an object.")
	else:
		_unknown_keys(constraints, ["max_proposals", "allow_new_ids", "allow_generated_code"], "task.constraints", errors)
		_validate_number(constraints.get("max_proposals"), 0.0, 32.0, true, "task.constraints.max_proposals", errors)
		if not constraints.get("allow_new_ids") is bool:
			errors.append("task.constraints.allow_new_ids must be a boolean.")
		if constraints.get("allow_generated_code") != false:
			errors.append("task.constraints.allow_generated_code must be false.")
	return errors

static func validate_agent_result(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Agent result must be a JSON object."]
	var result: Dictionary = value
	_unknown_keys(result, ["schema_version", "request_id", "agent_role", "status", "summary", "deliverables", "evidence", "warnings"], "result", errors)
	if result.get("schema_version") != AGENT_RESULT_SCHEMA:
		errors.append("Unsupported agent result schema_version.")
	if not _registered_id(str(result.get("request_id", "")), "request"):
		errors.append("result.request_id must be a canonical request id.")
	if result.get("agent_role") not in AGENT_ROLES:
		errors.append("result.agent_role is unsupported.")
	if result.get("status") not in ["completed", "needs_revision", "blocked"]:
		errors.append("result.status is unsupported.")
	_validate_text(result.get("summary"), 2000, "result.summary", errors)
	_validate_string_array(result.get("evidence"), 64, 1000, "result.evidence", errors)
	_validate_string_array(result.get("warnings"), 64, 1000, "result.warnings", errors)
	var deliverables = result.get("deliverables")
	if not deliverables is Array or deliverables.size() > 32:
		errors.append("result.deliverables must be an array of at most 32 entries.")
		return errors
	var seen := {}
	for index in deliverables.size():
		var location := "result.deliverables[%d]" % index
		var deliverable = deliverables[index]
		if not deliverable is Dictionary:
			errors.append(location + " must be an object.")
			continue
		_unknown_keys(deliverable, ["deliverable_id", "kind", "target_type", "target_id", "content", "payload"], location, errors)
		var deliverable_id := str(deliverable.get("deliverable_id", ""))
		if not _registered_id(deliverable_id, "deliverable") or seen.has(deliverable_id):
			errors.append(location + ".deliverable_id must be a unique canonical id.")
		seen[deliverable_id] = true
		match str(deliverable.get("kind", "")):
			"analysis":
				_validate_target_ref(deliverable, location, errors)
				_validate_text(deliverable.get("content"), 4000, location + ".content", errors)
				if deliverable.has("payload"):
					errors.append(location + ".payload is not allowed for analysis.")
			"runtime_patch":
				if deliverable.has("target_type") or deliverable.has("target_id") or deliverable.has("content"):
					errors.append(location + " runtime_patch must describe targets inside payload.operations only.")
				errors.append_array(validate_runtime_patch(deliverable.get("payload")))
			"content_draft":
				if deliverable.has("target_type") or deliverable.has("target_id") or deliverable.has("content"):
					errors.append(location + " content_draft must describe targets inside payload.operations only.")
				errors.append_array(validate_content_draft_shape(deliverable.get("payload")))
			"world_blueprint":
				if deliverable.has("target_type") or deliverable.has("target_id") or deliverable.has("content"):
					errors.append(location + " world_blueprint must describe its world inside payload only.")
				errors.append_array(WorldBlueprint.validate_shape(deliverable.get("payload")))
			_:
				errors.append(location + ".kind is unsupported.")
	return errors

static func validate_content_draft_shape(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Content draft must be a JSON object."]
	var draft: Dictionary = value
	_unknown_keys(draft, ["schema_version", "draft_id", "project_id", "base_catalog_hash", "base_content_revision", "author_role", "summary", "operations", "world_bundle"], "draft", errors)
	if draft.get("schema_version") != CONTENT_DRAFT_SCHEMA:
		errors.append("Unsupported content draft schema_version.")
	for pair in [["draft_id", "draft"], ["project_id", "project"]]:
		if not _registered_id(str(draft.get(pair[0], "")), pair[1]):
			errors.append("draft." + pair[0] + " must be a canonical " + pair[1] + " id.")
	if not _sha256(str(draft.get("base_catalog_hash", ""))):
		errors.append("draft.base_catalog_hash must be a lowercase SHA-256 hash.")
	_validate_number(draft.get("base_content_revision"), 0.0, 2147483647.0, true, "draft.base_content_revision", errors)
	if draft.get("author_role") not in DRAFT_AUTHOR_ROLES:
		errors.append("draft.author_role is unsupported.")
	if draft.has("world_bundle"):
		if draft.get("author_role")!="main": errors.append("Only a Main Agent draft may contain world_bundle.")
		errors.append_array(WorldBlueprint.validate_world_bundle(draft.world_bundle))
	_validate_text(draft.get("summary"), 2000, "draft.summary", errors)
	var operations = draft.get("operations")
	if not operations is Array:
		errors.append("draft.operations must be an array.")
		return errors
	if operations.is_empty() or operations.size() > 64:
		errors.append("draft.operations must contain between 1 and 64 operations.")
	var seen := {}
	for index in operations.size():
		var location := "draft.operations[%d]" % index
		var operation = operations[index]
		if not operation is Dictionary:
			errors.append(location + " must be an object.")
			continue
		_unknown_keys(operation, ["op", "target_type", "target_id", "definition"], location, errors)
		if operation.get("op") != "upsert":
			errors.append(location + ".op must equal 'upsert'.")
		var target_type := str(operation.get("target_type", ""))
		var target_id := str(operation.get("target_id", ""))
		if target_type not in TARGET_TYPES or not valid_target_id(target_type, target_id):
			errors.append(location + " contains an invalid draft target.")
		var key := target_type + ":" + target_id
		if seen.has(key):
			errors.append(location + " duplicates draft target " + key)
		seen[key] = true
		if not operation.get("definition") is Dictionary:
			errors.append(location + ".definition must be an object.")
	return errors

static func validate_published_content(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Published content must be a JSON object."]
	var artifact: Dictionary = value
	_unknown_keys(artifact, ["schema_version", "draft_id", "project_id", "source_catalog_hash", "source_content_revision", "candidate_content_hash", "draft", "artifact_hash"], "published", errors)
	if artifact.get("schema_version") != PUBLISHED_CONTENT_SCHEMA:
		errors.append("Unsupported published content schema_version.")
	for pair in [["draft_id", "draft"], ["project_id", "project"]]:
		if not _registered_id(str(artifact.get(pair[0], "")), pair[1]):
			errors.append("published." + pair[0] + " must be a canonical " + pair[1] + " id.")
	for field in ["source_catalog_hash", "candidate_content_hash", "artifact_hash"]:
		if not _sha256(str(artifact.get(field, ""))):
			errors.append("published." + field + " must be a lowercase SHA-256 hash.")
	_validate_number(artifact.get("source_content_revision"), 0.0, 2147483647.0, true, "published.source_content_revision", errors)
	errors.append_array(validate_content_draft_shape(artifact.get("draft")))
	if artifact.get("draft") is Dictionary:
		if artifact.get("draft_id") != artifact.draft.get("draft_id") or artifact.get("project_id") != artifact.draft.get("project_id"):
			errors.append("Published content identity does not match its draft.")
		if artifact.get("source_catalog_hash") != artifact.draft.get("base_catalog_hash") or artifact.get("source_content_revision") != artifact.draft.get("base_content_revision"):
			errors.append("Published content source context does not match its draft.")
	return errors

static func validate_campaign_import_request(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Campaign import request must be a JSON object."]
	var request: Dictionary = value
	_unknown_keys(request, ["schema_version", "request_id", "project_id", "draft_id", "campaign_id", "display_name", "activation_policy"], "campaign_import", errors)
	if request.get("schema_version") != CAMPAIGN_IMPORT_REQUEST_SCHEMA:
		errors.append("Unsupported campaign import request schema_version.")
	for pair in [["request_id", "request"], ["project_id", "project"], ["draft_id", "draft"], ["campaign_id", "campaign"]]:
		if not _registered_id(str(request.get(pair[0], "")), pair[1]):
			errors.append("campaign_import." + pair[0] + " must be a canonical " + pair[1] + " id.")
	_validate_text(request.get("display_name"), 96, "campaign_import.display_name", errors)
	if request.get("activation_policy") not in ["new_campaign", "explicit_project_copy"]:
		errors.append("campaign_import.activation_policy is unsupported.")
	return errors

static func validate_campaign_content_shape(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Campaign content must be a JSON object."]
	var content: Dictionary = value
	_unknown_keys(content, ["schema_version", "project_id", "campaign_id", "source_catalog_hash", "source_content_revision", "candidate_content_hash", "skills", "equipment", "npcs", "adventure", "world", "content_hash"], "campaign_content", errors)
	if content.get("schema_version") != CAMPAIGN_CONTENT_SCHEMA:
		errors.append("Unsupported campaign content schema_version.")
	for pair in [["project_id", "project"], ["campaign_id", "campaign"]]:
		if not _registered_id(str(content.get(pair[0], "")), pair[1]):
			errors.append("campaign_content." + pair[0] + " must be a canonical " + pair[1] + " id.")
	for field in ["source_catalog_hash", "candidate_content_hash", "content_hash"]:
		if not _sha256(str(content.get(field, ""))):
			errors.append("campaign_content." + field + " must be a lowercase SHA-256 hash.")
	_validate_number(content.get("source_content_revision"), 0.0, 2147483647.0, true, "campaign_content.source_content_revision", errors)
	for field in ["skills", "equipment", "npcs", "adventure", "world"]:
		if not content.get(field) is Dictionary:
			errors.append("campaign_content." + field + " must be an object.")
	return errors

static func validate_campaign_manifest(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Campaign manifest must be a JSON object."]
	var manifest: Dictionary = value
	_unknown_keys(manifest, ["schema_version", "project_id", "campaign_id", "display_name", "activation_policy", "source_artifact", "content_file", "content_hash", "save_namespace", "runtime_activation", "manifest_hash"], "campaign_manifest", errors)
	if manifest.get("schema_version") != CAMPAIGN_MANIFEST_SCHEMA:
		errors.append("Unsupported campaign manifest schema_version.")
	for pair in [["project_id", "project"], ["campaign_id", "campaign"]]:
		if not _registered_id(str(manifest.get(pair[0], "")), pair[1]):
			errors.append("campaign_manifest." + pair[0] + " must be a canonical " + pair[1] + " id.")
	_validate_text(manifest.get("display_name"), 96, "campaign_manifest.display_name", errors)
	if manifest.get("activation_policy") not in ["new_campaign", "explicit_project_copy"]:
		errors.append("campaign_manifest.activation_policy is unsupported.")
	if manifest.get("content_file") != "content.json" or manifest.get("save_namespace") != "saves":
		errors.append("Campaign manifest paths must use the isolated content.json and saves names.")
	if manifest.get("runtime_activation") != "new_session_only":
		errors.append("Campaign manifest runtime_activation must equal new_session_only.")
	for field in ["content_hash", "manifest_hash"]:
		if not _sha256(str(manifest.get(field, ""))):
			errors.append("campaign_manifest." + field + " must be a lowercase SHA-256 hash.")
	var source = manifest.get("source_artifact")
	if not source is Dictionary:
		errors.append("campaign_manifest.source_artifact must be an object.")
	else:
		_unknown_keys(source, ["draft_id", "artifact_hash", "source_catalog_hash", "source_content_revision", "candidate_content_hash"], "campaign_manifest.source_artifact", errors)
		if not _registered_id(str(source.get("draft_id", "")), "draft"):
			errors.append("campaign_manifest.source_artifact.draft_id must be canonical.")
		for field in ["artifact_hash", "source_catalog_hash", "candidate_content_hash"]:
			if not _sha256(str(source.get(field, ""))):
				errors.append("campaign_manifest.source_artifact." + field + " must be a lowercase SHA-256 hash.")
		_validate_number(source.get("source_content_revision"), 0.0, 2147483647.0, true, "campaign_manifest.source_artifact.source_content_revision", errors)
	return errors

static func validate_patch_value(path: String, value: Variant, location := "value") -> Array[String]:
	var errors: Array[String] = []
	if not PATCHABLE_SKILL_PATHS.has(path):
		return [location + " uses an unsupported path: " + path]
	var limits: Dictionary = PATCHABLE_SKILL_PATHS[path]
	_validate_number(value, limits.min, limits.max, limits.integer, location, errors)
	return errors

static func valid_target_id(target_type: String, target_id: String) -> bool:
	if target_type == "skill":
		return _registered_id(target_id, "skill")
	return target_type in TARGET_TYPES and _simple_id(target_id)

static func _validate_target_refs(value: Variant, maximum: int, location: String, errors: Array[String]) -> void:
	if not value is Array or value.size() > maximum:
		errors.append("%s must be an array of at most %d target references." % [location, maximum])
		return
	var seen := {}
	for index in value.size():
		var ref_location := "%s[%d]" % [location, index]
		var ref = value[index]
		if not ref is Dictionary:
			errors.append(ref_location + " must be an object.")
			continue
		_unknown_keys(ref, ["target_type", "target_id"], ref_location, errors)
		_validate_target_ref(ref, ref_location, errors)
		var key := str(ref.get("target_type", "")) + ":" + str(ref.get("target_id", ""))
		if seen.has(key):
			errors.append(ref_location + " duplicates target " + key)
		seen[key] = true

static func _validate_target_ref(ref: Dictionary, location: String, errors: Array[String]) -> void:
	var target_type := str(ref.get("target_type", ""))
	var target_id := str(ref.get("target_id", ""))
	if not valid_target_id(target_type, target_id):
		errors.append(location + " contains an invalid target reference.")

static func _unknown_keys(value: Dictionary, allowed: Array, location: String, errors: Array[String]) -> void:
	for key in value:
		if not key is String or key not in allowed:
			errors.append(location + " contains unsupported field: " + str(key))

static func _require_string(value: Dictionary, key: String, location: String, errors: Array[String]) -> void:
	if not value.get(key) is String or str(value.get(key)).strip_edges().is_empty():
		errors.append(location + "." + key + " must be a non-empty string.")

static func _validate_text(value: Variant, maximum: int, location: String, errors: Array[String]) -> void:
	if not value is String or str(value).strip_edges().is_empty() or str(value).length() > maximum:
		errors.append("%s must be a non-empty string of at most %d characters." % [location, maximum])

static func _validate_string_array(value: Variant, maximum: int, text_maximum: int, location: String, errors: Array[String], minimum := 0) -> void:
	if not value is Array or value.size() < minimum or value.size() > maximum:
		errors.append("%s must be an array containing %d to %d strings." % [location, minimum, maximum])
		return
	var seen := {}
	for index in value.size():
		var text = value[index]
		if not text is String or str(text).strip_edges().is_empty() or str(text).length() > text_maximum or seen.has(text):
			errors.append("%s[%d] must be a unique non-empty string of at most %d characters." % [location, index, text_maximum])
		seen[text] = true

static func _validate_number_array(value: Variant, count: int, minimum: float, maximum: float, location: String, errors: Array[String]) -> void:
	if not value is Array or value.size() != count:
		errors.append("%s must be an array of %d numbers." % [location, count])
		return
	for index in count:
		_validate_number(value[index], minimum, maximum, false, "%s[%d]" % [location, index], errors)

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

static func _sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-f0-9]{64}$") == OK and expression.search(value) != null

static func _simple_id(value: String) -> bool:
	if value.length() > 64:
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z][a-z0-9_]{2,63}$") == OK and expression.search(value) != null
