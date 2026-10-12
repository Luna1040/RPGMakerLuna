extends Node
## Trusted resolver and runtime release gate for NPC visuals. Agent-authored
## content can select IDs from this catalog but can never submit resource paths.

const CATALOG_PATH := "res://content/base/npc_asset_catalog.json"
const SCHEMA := "npc-asset-catalog/1"
const RENDERERS := ["legacy_idle", "roster_actions"]
var loaded := false
var last_errors: Array[String] = []
var catalog_hash := ""
var _profiles: Dictionary = {}
var _pairs: Dictionary = {}

func _ready() -> void:
	if not load_catalog(): push_error("NPC asset catalog rejected: " + "; ".join(last_errors))

func load_catalog(path := CATALOG_PATH) -> bool:
	var decoded = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var errors := validate_catalog(decoded)
	if not errors.is_empty():
		loaded = false
		last_errors = errors
		return false
	_profiles.clear()
	_pairs.clear()
	for entry: Dictionary in decoded.entries:
		_profiles[str(entry.profile_id)] = entry.duplicate(true)
		_pairs[_pair_key(str(entry.base_asset_id), str(entry.action_manifest_asset_id))] = str(entry.profile_id)
	catalog_hash = JSON.stringify(decoded, "", true, true).sha256_text()
	last_errors.clear()
	loaded = true
	return true

func validate_catalog(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary: return ["NPC asset catalog must be an object."]
	_unknown(value, ["schema_version", "catalog_id", "release_attestation_path", "entries"], "catalog", errors)
	if value.get("schema_version") != SCHEMA: errors.append("Unsupported NPC asset catalog schema.")
	if not _scoped(str(value.get("catalog_id", "")), "npc-assets"): errors.append("NPC asset catalog_id is invalid.")
	var attestation_path := str(value.get("release_attestation_path", ""))
	var attestation = JSON.parse_string(FileAccess.get_file_as_string(attestation_path)) if _trusted_path(attestation_path, ".json") and FileAccess.file_exists(attestation_path) else null
	if not attestation is Dictionary or attestation.get("release_ready") != true or int(attestation.get("checked_frames", 0)) != 351 or int(attestation.get("regression_checks", 0)) < 25:
		errors.append("NPC roster release attestation is missing or incomplete.")
	var entries = value.get("entries")
	if not entries is Array or entries.is_empty() or entries.size() > 64: return errors + ["NPC asset catalog entries must contain 1 to 64 profiles."]
	var ids := {}
	var pairs := {}
	for index in entries.size():
		var entry = entries[index]
		var location := "catalog.entries[%d]" % index
		if not entry is Dictionary:
			errors.append(location + " must be an object.")
			continue
		_unknown(entry, ["profile_id", "base_asset_id", "action_manifest_asset_id", "renderer", "base_path", "manifest_path", "roster_id", "default_action", "actions", "release_status", "quality_report_path"], location, errors)
		var profile_id := str(entry.get("profile_id", ""))
		var base_id := str(entry.get("base_asset_id", ""))
		var manifest_id := str(entry.get("action_manifest_asset_id", ""))
		if not _scoped(profile_id, "profile.npc") or ids.has(profile_id): errors.append(location + ".profile_id is invalid or duplicated.")
		ids[profile_id] = true
		if not _scoped(base_id, "asset.npc") or not _scoped(manifest_id, "asset.npc"): errors.append(location + " asset IDs are invalid.")
		var key := _pair_key(base_id, manifest_id)
		if pairs.has(key): errors.append(location + " duplicates an asset pair.")
		pairs[key] = true
		if entry.get("renderer") not in RENDERERS: errors.append(location + ".renderer is unsupported.")
		if entry.get("release_status") != "approved": errors.append(location + " is not release-approved.")
		var base_path := str(entry.get("base_path", ""))
		var manifest_path := str(entry.get("manifest_path", ""))
		var base_ready := _trusted_path(base_path, ".png") and FileAccess.file_exists(base_path)
		var manifest_ready := _trusted_path(manifest_path, ".json") and FileAccess.file_exists(manifest_path)
		if not base_ready: errors.append(location + ".base_path is missing or unsafe.")
		if not manifest_ready: errors.append(location + ".manifest_path is missing or unsafe.")
		var actions = entry.get("actions")
		if not actions is Array or actions.is_empty() or actions.size() > 16 or str(entry.get("default_action", "")) not in actions:
			errors.append(location + " actions/default_action are invalid.")
			continue
		if not base_ready or not manifest_ready: continue
		if entry.get("renderer") == "legacy_idle": _validate_legacy(entry, location, errors)
		else: _validate_roster(entry, location, errors)
	return errors

func validate_visual(value: Variant) -> Array[String]:
	if not value is Dictionary: return ["NPC visual must be an object."]
	var base_id := str(value.get("base_asset_id", ""))
	var manifest_id := str(value.get("idle_manifest_asset_id", ""))
	var profile_id := str(value.get("profile_id", _pairs.get(_pair_key(base_id, manifest_id), "")))
	if not loaded or not _profiles.has(profile_id): return ["NPC visual uses an unregistered asset profile: " + profile_id]
	var profile: Dictionary = _profiles[profile_id]
	var errors: Array[String] = []
	if profile.base_asset_id != base_id or profile.action_manifest_asset_id != manifest_id: errors.append("NPC visual asset IDs do not belong to profile " + profile_id)
	var action := str(value.get("ambient_action", profile.default_action))
	if action not in profile.actions: errors.append("NPC visual action is not approved for profile " + profile_id + ": " + action)
	return errors

func resolve_visual(value: Dictionary) -> Dictionary:
	if not validate_visual(value).is_empty(): return {}
	var profile_id := str(value.get("profile_id", _pairs.get(_pair_key(str(value.base_asset_id), str(value.idle_manifest_asset_id)), "")))
	var result: Dictionary = _profiles[profile_id].duplicate(true)
	result.ambient_action = str(value.get("ambient_action", result.default_action))
	return result

func public_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _profiles.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = _profiles[id]
		result.append({"profile_id":str(id), "base_asset_id":str(entry.base_asset_id),
			"idle_manifest_asset_id":str(entry.action_manifest_asset_id), "renderer":str(entry.renderer),
			"ambient_action":str(entry.default_action), "actions":entry.actions.duplicate(), "release_status":"approved"})
	return result

func _validate_legacy(entry: Dictionary, location: String, errors: Array[String]) -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(str(entry.manifest_path)))
	if not manifest is Dictionary or not manifest.get("frames") is Array or manifest.frames.size() < 2 or manifest.frames.size() > 124:
		errors.append(location + " legacy idle manifest is invalid.")
		return
	for frame in manifest.frames:
		if not frame is Dictionary or not _relative_png(str(frame.get("file", ""))) or not FileAccess.file_exists(str(entry.manifest_path).get_base_dir().path_join(str(frame.get("file", "")))):
			errors.append(location + " legacy idle frame is missing or unsafe.")
			break

func _validate_roster(entry: Dictionary, location: String, errors: Array[String]) -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(str(entry.manifest_path)))
	var canvas = manifest.get("canvas", []) if manifest is Dictionary else []
	if not manifest is Dictionary or int(manifest.get("version", 0)) != 1 or manifest.get("id") != entry.roster_id or not canvas is Array or canvas.size() != 2 or int(canvas[0]) != 768 or int(canvas[1]) != 768:
		errors.append(location + " roster manifest identity/canvas is invalid.")
		return
	var report_path := str(entry.get("quality_report_path", ""))
	var report = JSON.parse_string(FileAccess.get_file_as_string(report_path)) if _trusted_path(report_path, ".json") and FileAccess.file_exists(report_path) else null
	if not report is Dictionary or report.get("id") != entry.roster_id or report.get("status") != "packed" or not report.get("skipped_actions", []).is_empty():
		errors.append(location + " lacks a complete packed quality report.")
	for action_name in entry.actions:
		var clip = manifest.get("actions", {}).get(action_name, {})
		if not clip is Dictionary or clip.get("review_status") != "visually_reviewed" or not clip.get("frames") is Array or clip.frames.size() < 2:
			errors.append(location + " action is missing or not visually reviewed: " + str(action_name))
			continue
		for frame in clip.frames:
			if not frame is Dictionary or not _relative_png(str(frame.get("file", ""))) or not FileAccess.file_exists(str(entry.manifest_path).get_base_dir().path_join(str(frame.get("file", "")))):
				errors.append(location + " action frame is missing or unsafe: " + str(action_name))
				break

func _trusted_path(path: String, suffix: String) -> bool:
	return path.begins_with("res://assets/") and path.ends_with(suffix) and ".." not in path and "\\" not in path and "?" not in path and "#" not in path

func _relative_png(path: String) -> bool:
	return not path.is_empty() and path.ends_with(".png") and not path.is_absolute_path() and ".." not in path and "\\" not in path

func _scoped(value: String, prefix: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^" + prefix.replace(".", "\\.") + "\\.[a-z0-9][a-z0-9_.-]+$") == OK and value.length() <= 128 and regex.search(value) != null

func _pair_key(base_id: String, manifest_id: String) -> String: return base_id + "|" + manifest_id

func _unknown(value: Dictionary, allowed: Array, location: String, errors: Array[String]) -> void:
	for key in value:
		if key not in allowed: errors.append(location + " contains unsupported field: " + str(key))
