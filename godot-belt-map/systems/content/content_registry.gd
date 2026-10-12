extends Node
## Validated definitions plus reversible runtime overrides. Returned values are copies.

signal content_loaded(bundle_id: String, base_hash: String)
signal content_changed(revision: int, patch_id: String)
signal content_rejected(patch_id: String, errors: Array[String])

const Validator = preload("content_validator.gd")
const AdventureValidator = preload("res://systems/adventure/adventure_catalog.gd")
const BASE_SKILLS_PATH := "res://content/base/skills.json"
const BASE_EQUIPMENT_PATH := "res://content/base/equipment.json"
const BASE_NPCS_PATH := "res://content/base/town_npcs.json"
const ADVENTURE_PATH := "res://systems/adventure/adventure_data.json"
const STATE_SCHEMA := "runtime-content-state/1"
const OFFICIAL_PROJECT_ID := "project.rpgmakerluna.courtyard"
const OFFICIAL_CAMPAIGN_ID := "campaign.official.courtyard"

var loaded := false
var revision := 0
var bundle_id := ""
var bundle_ids: Dictionary = {}
## Patch/save compatibility hash: intentionally covers only the patchable skill bundle.
var base_hash := ""
## Full read-only catalog hash for Main Agent context and cache invalidation.
var catalog_hash := ""
var last_errors: Array[String] = []
var _base_skills: Dictionary = {}
var _skills: Dictionary = {}
var _equipment: Dictionary = {}
var _npcs: Dictionary = {}
var _quests: Dictionary = {}
var _dialogues: Dictionary = {}
var _adventure: Dictionary = {}
var _world:Dictionary={}
var _applied_patch_ids: Array[String] = []
var _history: Array[Dictionary] = []
var _content_context: Dictionary = {}

func _ready() -> void:
	if not load_base_content():
		push_error("ContentRegistry rejected base content: " + "; ".join(last_errors))

func load_base_content(path := BASE_SKILLS_PATH) -> bool:
	var errors: Array[String] = []
	var skills_value = _read_json(path, "skills", errors)
	var equipment_value = _read_json(BASE_EQUIPMENT_PATH, "equipment", errors)
	var npcs_value = _read_json(BASE_NPCS_PATH, "town NPCs", errors)
	var adventure_value = _read_json(ADVENTURE_PATH, "adventure", errors)
	if not errors.is_empty():
		return _reject("base-load", errors)
	for bundle in [skills_value, equipment_value, npcs_value]:
		errors.append_array(Validator.validate_content_bundle(bundle))
	if not errors.is_empty():
		return _reject("base-load", errors)
	var next_skills := _entries_by_id(skills_value.entries)
	var next_equipment := _entries_by_id(equipment_value.entries)
	var next_npcs := _entries_by_id(npcs_value.entries)
	errors.append_array(AdventureValidator.validate(adventure_value, next_equipment))
	for npc_id in next_npcs:
		if not adventure_value.get("npcs", {}).has(npc_id):
			errors.append("Town NPC has no registered dialogue definition: " + npc_id)
	if not errors.is_empty():
		return _reject("base-load", errors)
	var next_quests := {}
	for quest: Dictionary in adventure_value.quests:
		next_quests[str(quest.id)] = quest.duplicate(true)
	_base_skills = next_skills
	_skills = next_skills.duplicate(true)
	_equipment = next_equipment
	_npcs = next_npcs
	_quests = next_quests
	_dialogues = adventure_value.npcs.duplicate(true)
	_adventure = adventure_value.duplicate(true)
	_world={}
	bundle_id = str(skills_value.bundle_id)
	bundle_ids = {
		"skills": str(skills_value.bundle_id),
		"equipment": str(equipment_value.bundle_id),
		"npcs": str(npcs_value.bundle_id),
		"adventure": "base.courtyard.adventure"
	}
	base_hash = JSON.stringify(skills_value, "", true, true).sha256_text()
	catalog_hash = JSON.stringify({"skills":skills_value, "equipment":equipment_value,
		"npcs":npcs_value, "adventure":adventure_value}, "", true, true).sha256_text()
	_content_context = {"kind":"official", "project_id":OFFICIAL_PROJECT_ID,
		"campaign_id":OFFICIAL_CAMPAIGN_ID, "content_hash":catalog_hash, "manifest_hash":""}
	revision = 0
	_applied_patch_ids.clear()
	_history.clear()
	last_errors.clear()
	loaded = true
	content_loaded.emit(bundle_id, base_hash)
	return true

func activate_campaign_content(content: Variant, manifest: Variant) -> bool:
	## This method is only called by CampaignSessionService after the old gameplay
	## scene has been replaced by the bootstrap scene.
	var errors: Array[String] = []
	if not content is Dictionary or not manifest is Dictionary:
		return _reject("campaign-load", ["Campaign content and manifest must be objects."])
	var import_service = get_node_or_null("/root/CampaignImportService")
	if import_service == null:
		return _reject("campaign-load", ["CampaignImportService is unavailable."])
	errors.append_array(import_service.validate_campaign_content(content))
	errors.append_array(import_service.validate_campaign_manifest(manifest))
	if content.get("project_id") != manifest.get("project_id") or content.get("campaign_id") != manifest.get("campaign_id"):
		errors.append("Campaign content identity does not match its manifest.")
	if content.get("content_hash") != manifest.get("content_hash"):
		errors.append("Campaign content checksum does not match its manifest.")
	if not errors.is_empty():
		return _reject("campaign-load", errors)
	var next_skills: Dictionary = content.skills.duplicate(true)
	var next_equipment: Dictionary = content.equipment.duplicate(true)
	var next_npcs: Dictionary = content.npcs.duplicate(true)
	var next_adventure: Dictionary = content.adventure.duplicate(true)
	var next_world:Dictionary=content.get("world",{}).duplicate(true)
	var next_quests := {}
	for quest: Dictionary in next_adventure.quests:
		next_quests[str(quest.id)] = quest.duplicate(true)
	_base_skills = next_skills.duplicate(true)
	_skills = next_skills
	_equipment = next_equipment
	_npcs = next_npcs
	_quests = next_quests
	_dialogues = next_adventure.npcs.duplicate(true)
	_adventure = next_adventure
	_world=next_world
	bundle_id = str(manifest.campaign_id)
	bundle_ids = {"skills":bundle_id + ".skills", "equipment":bundle_id + ".equipment",
		"npcs":bundle_id + ".npcs", "adventure":bundle_id + ".adventure"}
	base_hash = JSON.stringify({"campaign_id":bundle_id, "skills":next_skills}, "", true, true).sha256_text()
	catalog_hash = str(content.content_hash)
	_content_context = {"kind":"campaign", "project_id":str(manifest.project_id),
		"campaign_id":str(manifest.campaign_id), "content_hash":str(content.content_hash),
		"manifest_hash":str(manifest.manifest_hash)}
	revision = 0
	_applied_patch_ids.clear()
	_history.clear()
	last_errors.clear()
	loaded = true
	content_loaded.emit(bundle_id, base_hash)
	return true

func content_context() -> Dictionary:
	return _content_context.duplicate(true)

func is_official_context() -> bool:
	return _content_context.get("kind") == "official"

func matches_content_context(value: Variant, allow_legacy_official := false) -> bool:
	if not value is Dictionary:
		return allow_legacy_official and is_official_context()
	return value == _content_context

func get_skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {}).duplicate(true)

func get_equipment(equipment_id: String) -> Dictionary:
	return _equipment.get(equipment_id, {}).duplicate(true)

func get_npc(npc_id: String) -> Dictionary:
	return _npcs.get(npc_id, {}).duplicate(true)

func get_quest(quest_id: String) -> Dictionary:
	return _quests.get(quest_id, {}).duplicate(true)

func get_dialogue(npc_id: String) -> Dictionary:
	return _dialogues.get(npc_id, {}).duplicate(true)

func get_definition(target_type: String, target_id: String) -> Dictionary:
	match target_type:
		"skill": return get_skill(target_id)
		"equipment": return get_equipment(target_id)
		"npc": return get_npc(target_id)
		"quest": return get_quest(target_id)
		"dialogue": return get_dialogue(target_id)
		"item": return _adventure.get("consumables",{}).get(target_id,{}).duplicate(true)
		"shop":
			for row in _adventure.get("shop",[]):
				if row is Dictionary and row.get("id")==target_id: return row.duplicate(true)
	return {}

func definitions(target_type: String) -> Dictionary:
	match target_type:
		"skill": return _skills.duplicate(true)
		"equipment": return _equipment.duplicate(true)
		"npc": return _npcs.duplicate(true)
		"quest": return _quests.duplicate(true)
		"dialogue": return _dialogues.duplicate(true)
		"item": return _adventure.get("consumables",{}).duplicate(true)
		"shop":
			var rows:Dictionary={}
			for row in _adventure.get("shop",[]):
				if row is Dictionary: rows[str(row.get("id",""))]=row.duplicate(true)
			return rows
	return {}

func adventure_catalog() -> Dictionary:
	return _adventure.duplicate(true)

func world_bundle()->Dictionary:
	return _world.duplicate(true)

func registered_skill_ids() -> Array[String]:
	return registered_ids("skill")

func registered_ids(target_type: String) -> Array[String]:
	var result: Array[String] = []
	for id in definitions(target_type):
		result.append(str(id))
	result.sort()
	return result

func registered_targets() -> Dictionary:
	var result := {}
	for target_type in Validator.TARGET_TYPES:
		result[target_type] = registered_ids(target_type)
	return result

func target_exists(target_type: String, target_id: String) -> bool:
	return not get_definition(target_type, target_id).is_empty()

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

func _read_json(path: String, label: String, errors: Array[String]) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s content file does not exist: %s" % [label, path])
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("Invalid %s JSON at line %d: %s" % [label, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data

func _entries_by_id(entries: Array) -> Dictionary:
	var result := {}
	for entry: Dictionary in entries:
		result[str(entry.id)] = entry.duplicate(true)
	return result

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
