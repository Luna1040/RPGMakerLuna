extends Node
## Imports a reviewed content artifact into an isolated, immutable campaign
## package. This service never activates the package in the current session.

signal campaign_previewed(campaign_id: String, preview_token: String)
signal campaign_installed(campaign_id: String, manifest_path: String)
signal campaign_rejected(campaign_id: String, errors: Array[String])

const Validator = preload("content_validator.gd")
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_PREVIEWS := 32
const RESERVED_CAMPAIGN_PREFIXES := ["campaign.official.", "campaign.base.", "campaign.system."]

var projects_root := "user://projects"
var _previews: Dictionary = {}
var _preview_order: Array[String] = []

func validate_import_request(value: Variant) -> Array[String]:
	var errors := Validator.validate_campaign_import_request(value)
	if value is Dictionary:
		var campaign_id := str(value.get("campaign_id", ""))
		for prefix in RESERVED_CAMPAIGN_PREFIXES:
			if campaign_id.begins_with(prefix):
				errors.append("Reserved campaign IDs cannot be imported: " + campaign_id)
				break
	return errors

func preview_import(value: Variant) -> Dictionary:
	var evaluated := _evaluate(value)
	var campaign_id := str(value.get("campaign_id", "")) if value is Dictionary else ""
	if not evaluated.errors.is_empty():
		return _reject(campaign_id, evaluated.errors)
	var request: Dictionary = value
	var token := _canonical_hash({"request_hash":_canonical_hash(request),
		"artifact_hash":str(evaluated.artifact.artifact_hash), "content_hash":str(evaluated.content.content_hash),
		"manifest_hash":str(evaluated.manifest.manifest_hash), "catalog_hash":_registry().catalog_hash,
		"content_revision":_registry().revision})
	_previews[token] = {"request_hash":_canonical_hash(request),
		"artifact_hash":str(evaluated.artifact.artifact_hash), "content_hash":str(evaluated.content.content_hash),
		"manifest_hash":str(evaluated.manifest.manifest_hash), "catalog_hash":_registry().catalog_hash,
		"content_revision":_registry().revision}
	if token not in _preview_order:
		_preview_order.append(token)
	while _preview_order.size() > MAX_PREVIEWS:
		_previews.erase(_preview_order.pop_front())
	var result := {"ok":true, "errors":[], "campaign_id":campaign_id, "preview_token":token,
		"source_draft_id":str(request.draft_id), "operation_count":request_operation_count(evaluated.artifact),
		"content_hash":str(evaluated.content.content_hash), "manifest_hash":str(evaluated.manifest.manifest_hash),
		"campaign_path":str(evaluated.campaign_path), "save_namespace":str(evaluated.save_namespace),
		"already_installed":bool(evaluated.already_installed), "activates_runtime":false,
		"requires_new_session":true, "activation_policy":str(request.activation_policy)}
	campaign_previewed.emit(campaign_id, token)
	return result

func install_campaign(value: Variant, preview_token: String) -> Dictionary:
	var campaign_id := str(value.get("campaign_id", "")) if value is Dictionary else ""
	if not _previews.has(preview_token):
		return _reject(campaign_id, ["Unknown or expired campaign import preview token."])
	var evaluated := _evaluate(value)
	if not evaluated.errors.is_empty():
		return _reject(campaign_id, evaluated.errors)
	var preview: Dictionary = _previews[preview_token]
	if preview.request_hash != _canonical_hash(value) or preview.artifact_hash != evaluated.artifact.artifact_hash:
		return _reject(campaign_id, ["Campaign import no longer matches the reviewed preview."])
	if preview.content_hash != evaluated.content.content_hash or preview.manifest_hash != evaluated.manifest.manifest_hash:
		return _reject(campaign_id, ["Campaign package changed after preview."])
	if preview.catalog_hash != _registry().catalog_hash or int(preview.content_revision) != _registry().revision:
		return _reject(campaign_id, ["Content catalog changed after campaign preview; generate a new preview."])
	if evaluated.already_installed:
		return _success(evaluated, true)
	var campaign_path := str(evaluated.campaign_path)
	var parent_path := campaign_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent_path)) != OK:
		return _reject(campaign_id, ["Could not create the isolated campaigns directory."])
	var staging_path := campaign_path + ".tmp-" + str(Time.get_ticks_usec())
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging_path)) != OK:
		return _reject(campaign_id, ["Could not create the campaign staging directory."])
	var write_error := _write_json(staging_path.path_join("content.json"), evaluated.content)
	if write_error.is_empty():
		write_error = _write_json(staging_path.path_join("manifest.json"), evaluated.manifest)
	if not write_error.is_empty():
		_cleanup_staging(staging_path)
		return _reject(campaign_id, [write_error])
	var staged := _inspect_at(staging_path, str(value.project_id), campaign_id)
	if not staged.ok or staged.manifest.get("manifest_hash") != evaluated.manifest.manifest_hash:
		_cleanup_staging(staging_path)
		return _reject(campaign_id, ["Staged campaign package failed read-back validation: " + "; ".join(staged.errors)])
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(campaign_path)):
		_cleanup_staging(staging_path)
		return _reject(campaign_id, ["Campaign ID became occupied during installation; existing data was not overwritten."])
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(staging_path), ProjectSettings.globalize_path(campaign_path)) != OK:
		_cleanup_staging(staging_path)
		return _reject(campaign_id, ["Could not atomically install the campaign package."])
	var installed := _inspect_at(campaign_path, str(value.project_id), campaign_id)
	if not installed.ok or installed.manifest.get("manifest_hash") != evaluated.manifest.manifest_hash:
		return _reject(campaign_id, ["Installed campaign failed final verification."])
	campaign_installed.emit(campaign_id, campaign_path.path_join("manifest.json"))
	return _success(evaluated, false)

func inspect_campaign(project_id: String, campaign_id: String) -> Dictionary:
	if not _scoped_id(project_id, "project") or not _scoped_id(campaign_id, "campaign"):
		return {"ok":false, "errors":["Project and campaign IDs must be canonical."], "manifest":{}}
	return _inspect_at(_campaign_path(project_id, campaign_id), project_id, campaign_id)

func validate_campaign_content(value: Variant) -> Array[String]:
	var errors := Validator.validate_campaign_content_shape(value)
	if not value is Dictionary:
		return errors
	var content: Dictionary = value
	for pair in [["skills", "skill"], ["equipment", "equipment"], ["npcs", "npc"]]:
		var definitions = content.get(pair[0])
		if not definitions is Dictionary:
			continue
		if definitions.is_empty() or definitions.size() > 512:
			errors.append("campaign_content.%s must contain between 1 and 512 entries." % pair[0])
		for definition_id in definitions:
			var definition = definitions[definition_id]
			if not definition is Dictionary or str(definition.get("id", "")) != str(definition_id):
				errors.append("Campaign %s key does not match its definition id: %s" % [pair[0], definition_id])
				continue
			match pair[1]:
				"skill": errors.append_array(Validator.validate_skill(definition, "campaign.skills[" + str(definition_id) + "]"))
				"equipment": errors.append_array(Validator.validate_equipment(definition, "campaign.equipment[" + str(definition_id) + "]"))
				"npc": errors.append_array(Validator.validate_town_npc(definition, "campaign.npcs[" + str(definition_id) + "]"))
	var npcs = content.get("npcs")
	var equipment = content.get("equipment")
	var adventure = content.get("adventure")
	var world = content.get("world")
	if npcs is Dictionary and equipment is Dictionary and adventure is Dictionary and world is Dictionary:
		var draft_service = _draft_service()
		if draft_service == null:
			errors.append("ContentDraftService is unavailable for campaign catalog validation.")
		else:
			errors.append_array(draft_service.validate_materialized_content(npcs, adventure, equipment, world))
		var candidate_hash := _canonical_hash({"npcs":npcs, "adventure":adventure, "equipment":equipment, "world":world})
		if content.get("candidate_content_hash") != candidate_hash:
			errors.append("Campaign candidate content hash does not match its materialized content.")
	if content.get("content_hash") != _document_hash(content, "content_hash"):
		errors.append("Campaign content checksum does not match its contents.")
	return errors

func validate_campaign_manifest(value: Variant) -> Array[String]:
	var errors := Validator.validate_campaign_manifest(value)
	if value is Dictionary and value.get("manifest_hash") != _document_hash(value, "manifest_hash"):
		errors.append("Campaign manifest checksum does not match its contents.")
	return errors

func clear_previews() -> void:
	_previews.clear()
	_preview_order.clear()

func request_operation_count(artifact: Dictionary) -> int:
	var draft = artifact.get("draft", {})
	return draft.get("operations", []).size() if draft is Dictionary and draft.get("operations", []) is Array else 0

func _evaluate(value: Variant) -> Dictionary:
	var errors := validate_import_request(value)
	var registry = _registry()
	var draft_service = _draft_service()
	if registry == null or not registry.loaded:
		errors.append("ContentRegistry is unavailable.")
	if draft_service == null:
		errors.append("ContentDraftService is unavailable.")
	if not errors.is_empty() or not value is Dictionary or registry == null or draft_service == null:
		return _evaluation_failure(errors)
	var request: Dictionary = value
	var loaded := _read_json(_artifact_path(str(request.project_id), str(request.draft_id)), "published content artifact")
	errors.append_array(loaded.errors)
	if not errors.is_empty():
		return _evaluation_failure(errors)
	var artifact: Dictionary = loaded.value
	errors.append_array(draft_service.verify_published_artifact(artifact))
	if artifact.get("project_id") != request.project_id or artifact.get("draft_id") != request.draft_id:
		errors.append("Published artifact identity does not match the campaign import request.")
	if artifact.get("source_catalog_hash") != registry.catalog_hash or artifact.get("source_content_revision") != registry.revision:
		errors.append("Published artifact does not target the current source catalog context.")
	if not errors.is_empty():
		return _evaluation_failure(errors)
	var materialized: Dictionary = draft_service.materialize_candidate(artifact.draft)
	errors.append_array(materialized.errors)
	if materialized.get("candidate_content_hash") != artifact.candidate_content_hash:
		errors.append("Published artifact candidate hash does not match materialized content.")
	if not errors.is_empty():
		return _evaluation_failure(errors)
	var materialized_content: Dictionary = materialized.content
	var content := {"schema_version":Validator.CAMPAIGN_CONTENT_SCHEMA,
		"project_id":str(request.project_id), "campaign_id":str(request.campaign_id),
		"source_catalog_hash":str(artifact.source_catalog_hash),
		"source_content_revision":int(artifact.source_content_revision),
		"candidate_content_hash":str(artifact.candidate_content_hash),
		"skills":materialized_content.skills.duplicate(true),
		"equipment":materialized_content.equipment.duplicate(true),
		"npcs":materialized_content.npcs.duplicate(true),
		"adventure":materialized_content.adventure.duplicate(true),
		"world":materialized_content.world.duplicate(true)}
	content["content_hash"] = _document_hash(content, "content_hash")
	errors.append_array(validate_campaign_content(content))
	var manifest := {"schema_version":Validator.CAMPAIGN_MANIFEST_SCHEMA,
		"project_id":str(request.project_id), "campaign_id":str(request.campaign_id),
		"display_name":str(request.display_name), "activation_policy":str(request.activation_policy),
		"source_artifact":{"draft_id":str(artifact.draft_id), "artifact_hash":str(artifact.artifact_hash),
			"source_catalog_hash":str(artifact.source_catalog_hash),
			"source_content_revision":int(artifact.source_content_revision),
			"candidate_content_hash":str(artifact.candidate_content_hash)},
		"content_file":"content.json", "content_hash":str(content.content_hash),
		"save_namespace":"saves", "runtime_activation":"new_session_only"}
	manifest["manifest_hash"] = _document_hash(manifest, "manifest_hash")
	errors.append_array(validate_campaign_manifest(manifest))
	var campaign_path := _campaign_path(str(request.project_id), str(request.campaign_id))
	var already_installed := false
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(campaign_path)):
		var existing := _inspect_at(campaign_path, str(request.project_id), str(request.campaign_id))
		if not existing.ok:
			errors.append("Existing campaign directory is invalid and will not be overwritten: " + "; ".join(existing.errors))
		elif existing.manifest.get("manifest_hash") != manifest.manifest_hash:
			errors.append("Campaign ID already exists with different immutable content.")
		else:
			already_installed = true
	return {"errors":errors, "artifact":artifact, "content":content, "manifest":manifest,
		"campaign_path":campaign_path, "save_namespace":campaign_path.path_join("saves"),
		"already_installed":already_installed}

func _inspect_at(campaign_path: String, project_id: String, campaign_id: String) -> Dictionary:
	var manifest_result := _read_json(campaign_path.path_join("manifest.json"), "campaign manifest")
	var content_result := _read_json(campaign_path.path_join("content.json"), "campaign content")
	var errors: Array[String] = []
	errors.append_array(manifest_result.errors)
	errors.append_array(content_result.errors)
	if not errors.is_empty():
		return {"ok":false, "errors":errors, "manifest":{}, "content":{}}
	var manifest: Dictionary = manifest_result.value
	var content: Dictionary = content_result.value
	errors.append_array(validate_campaign_manifest(manifest))
	errors.append_array(validate_campaign_content(content))
	if manifest.get("project_id") != project_id or content.get("project_id") != project_id:
		errors.append("Installed campaign project identity does not match its directory.")
	if manifest.get("campaign_id") != campaign_id or content.get("campaign_id") != campaign_id:
		errors.append("Installed campaign identity does not match its directory.")
	if manifest.get("content_hash") != content.get("content_hash"):
		errors.append("Campaign manifest and content checksums do not match.")
	var source = manifest.get("source_artifact", {})
	if source is Dictionary:
		if source.get("source_catalog_hash") != content.get("source_catalog_hash") or source.get("source_content_revision") != content.get("source_content_revision") or source.get("candidate_content_hash") != content.get("candidate_content_hash"):
			errors.append("Campaign manifest source context does not match campaign content.")
	return {"ok":errors.is_empty(), "errors":errors,
		"manifest":manifest.duplicate(true) if errors.is_empty() else {},
		"content":content.duplicate(true) if errors.is_empty() else {}}

func _read_json(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"value":{}, "errors":["Missing %s: %s" % [label, path]]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"value":{}, "errors":["Could not read %s." % label]}
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return {"value":{}, "errors":["%s exceeds the 8 MiB limit." % label.capitalize()]}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"value":{}, "errors":["Invalid %s JSON." % label]}
	return {"value":parser.data, "errors":[]}

func _write_json(path: String, value: Dictionary) -> String:
	var text := JSON.stringify(value, "  ", true, true) + "\n"
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return "Campaign package file exceeds the 8 MiB limit."
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not open a campaign staging file."
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	return "" if write_error == OK else "Could not write a campaign staging file."

func _cleanup_staging(path: String) -> void:
	for file_name in ["manifest.json", "content.json"]:
		var file_path := path.path_join(file_name)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _success(evaluated: Dictionary, duplicate: bool) -> Dictionary:
	return {"ok":true, "duplicate":duplicate, "errors":[],
		"campaign_id":str(evaluated.manifest.campaign_id),
		"campaign_path":str(evaluated.campaign_path),
		"manifest_path":str(evaluated.campaign_path).path_join("manifest.json"),
		"content_hash":str(evaluated.content.content_hash),
		"manifest_hash":str(evaluated.manifest.manifest_hash),
		"save_namespace":str(evaluated.save_namespace), "activates_runtime":false,
		"requires_new_session":true, "activation_policy":str(evaluated.manifest.activation_policy)}

func _evaluation_failure(errors: Array[String]) -> Dictionary:
	return {"errors":errors, "artifact":{}, "content":{}, "manifest":{},
		"campaign_path":"", "save_namespace":"", "already_installed":false}

func _artifact_path(project_id: String, draft_id: String) -> String:
	return projects_root.path_join(project_id).path_join("published").path_join(draft_id + ".json")

func _campaign_path(project_id: String, campaign_id: String) -> String:
	return projects_root.path_join(project_id).path_join("campaigns").path_join(campaign_id)

func _document_hash(value: Dictionary, hash_field: String) -> String:
	var content := value.duplicate(true)
	content.erase(hash_field)
	return _canonical_hash(content)

func _canonical_hash(value: Variant) -> String:
	var normalized = JSON.parse_string(JSON.stringify(value, "", true, true))
	return JSON.stringify(normalized, "", true, true).sha256_text()

func _scoped_id(value: String, prefix: String) -> bool:
	if value.length() > 128:
		return false
	var expression := RegEx.new()
	return expression.compile("^" + prefix + "\\.[a-z0-9][a-z0-9_.-]+$") == OK and expression.search(value) != null

func _registry():
	return get_node_or_null("/root/ContentRegistry")

func _draft_service():
	return get_node_or_null("/root/ContentDraftService")

func _reject(campaign_id: String, errors: Array[String]) -> Dictionary:
	campaign_rejected.emit(campaign_id, errors)
	return {"ok":false, "errors":errors, "campaign_id":campaign_id}
