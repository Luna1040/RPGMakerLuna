extends Node
## Sandboxed authoring pipeline. Published artifacts are immutable data and are
## never activated in the running campaign by this service.

signal draft_previewed(draft_id: String, preview_token: String)
signal draft_published(draft_id: String, artifact_path: String)
signal draft_rejected(draft_id: String, errors: Array[String])

const Validator = preload("content_validator.gd")
const AdventureValidator = preload("res://systems/adventure/adventure_catalog.gd")
const MAX_PREVIEWS := 32
const ROLE_TARGET_TYPES := {
	"main": ["quest", "dialogue", "npc", "equipment", "item", "shop"],
	"narrative": ["quest", "dialogue"],
	"npc": ["npc", "dialogue"],
	"systems": ["equipment", "item", "shop"]
}

var publish_root := "user://projects"
var _previews: Dictionary = {}
var _preview_order: Array[String] = []

func validate_draft(value: Variant) -> Array[String]:
	return _evaluate(value).errors

func verify_published_artifact(value: Variant) -> Array[String]:
	var errors := Validator.validate_published_content(value)
	if value is Dictionary and value.get("artifact_hash") != _artifact_hash(value):
		errors.append("Published artifact checksum does not match its contents.")
	return errors

func materialize_candidate(value: Variant) -> Dictionary:
	var evaluated := _evaluate(value)
	if not evaluated.errors.is_empty():
		return {"ok":false, "errors":evaluated.errors, "candidate_content_hash":"", "content":{}}
	var registry = _registry()
	return {"ok":true, "errors":[], "candidate_content_hash":str(evaluated.candidate_hash),
		"content":{"skills":registry.definitions("skill"), "equipment":evaluated.equipment.duplicate(true),
			"npcs":evaluated.npcs.duplicate(true), "adventure":evaluated.adventure.duplicate(true),
			"world":evaluated.world.duplicate(true)}}

func validate_materialized_content(npcs: Variant, adventure: Variant, equipment: Variant, world:Variant={}) -> Array[String]:
	var errors: Array[String] = []
	if not npcs is Dictionary or not adventure is Dictionary or not equipment is Dictionary:
		return ["Materialized NPC, adventure, and equipment catalogs must be objects."]
	if _registry() == null or not _registry().loaded:
		return ["ContentRegistry is unavailable."]
	_validate_candidate(npcs, adventure, equipment, errors)
	if world is Dictionary and not world.is_empty(): errors.append_array(get_node("/root/WorldBlueprintService").validate_world_bundle(world))
	return errors

func preview_draft(value: Variant) -> Dictionary:
	var evaluated := _evaluate(value)
	var draft_id := str(value.get("draft_id", "")) if value is Dictionary else ""
	if not evaluated.errors.is_empty():
		return _reject(draft_id, evaluated.errors)
	var draft: Dictionary = value
	var draft_hash := _canonical_hash(draft)
	var candidate_hash := str(evaluated.candidate_hash)
	var token := _canonical_hash({"draft_hash":draft_hash, "candidate_content_hash":candidate_hash,
		"source_catalog_hash":str(draft.base_catalog_hash), "source_content_revision":int(draft.base_content_revision)})
	var changes: Array[Dictionary] = []
	var registry = _registry()
	for operation: Dictionary in draft.operations:
		var before: Dictionary = registry.get_definition(str(operation.target_type), str(operation.target_id))
		var changed_paths: Array[String] = []
		_collect_changed_paths(before, operation.definition, "", changed_paths)
		changes.append({"target_type":str(operation.target_type), "target_id":str(operation.target_id),
			"change":"add" if before.is_empty() else "replace", "changed_paths":changed_paths})
	_previews[token] = {"draft_hash":draft_hash, "candidate_hash":candidate_hash,
		"catalog_hash":str(draft.base_catalog_hash), "revision":int(draft.base_content_revision)}
	if token not in _preview_order:
		_preview_order.append(token)
	while _preview_order.size() > MAX_PREVIEWS:
		_previews.erase(_preview_order.pop_front())
	var preview := {"ok":true, "errors":[], "draft_id":draft_id, "preview_token":token,
		"candidate_content_hash":candidate_hash, "operation_count":draft.operations.size(),
		"changes":changes, "activates_runtime":false, "reload_required":"new_campaign_import"}
	draft_previewed.emit(draft_id, token)
	return preview

func publish_draft(value: Variant, preview_token: String) -> Dictionary:
	var draft_id := str(value.get("draft_id", "")) if value is Dictionary else ""
	if not _previews.has(preview_token):
		return _reject(draft_id, ["Unknown or expired content preview token."])
	var evaluated := _evaluate(value)
	if not evaluated.errors.is_empty():
		return _reject(draft_id, evaluated.errors)
	var draft: Dictionary = value
	var preview: Dictionary = _previews[preview_token]
	if preview.draft_hash != _canonical_hash(draft) or preview.candidate_hash != evaluated.candidate_hash:
		return _reject(draft_id, ["Content draft no longer matches the reviewed preview."])
	if preview.catalog_hash != _registry().catalog_hash or int(preview.revision) != _registry().revision:
		return _reject(draft_id, ["Content catalog changed after preview; generate a new preview."])
	var artifact := {"schema_version":Validator.PUBLISHED_CONTENT_SCHEMA, "draft_id":draft_id,
		"project_id":str(draft.project_id), "source_catalog_hash":str(draft.base_catalog_hash),
		"source_content_revision":int(draft.base_content_revision),
		"candidate_content_hash":str(evaluated.candidate_hash), "draft":draft.duplicate(true)}
	artifact["artifact_hash"] = _artifact_hash(artifact)
	var errors := verify_published_artifact(artifact)
	if not errors.is_empty():
		return _reject(draft_id, errors)
	var directory := publish_root.path_join(str(draft.project_id)).path_join("published")
	var artifact_path := directory.path_join(draft_id + ".json")
	if FileAccess.file_exists(artifact_path):
		var existing = JSON.parse_string(FileAccess.get_file_as_string(artifact_path))
		if existing is Dictionary and existing.get("artifact_hash") == artifact.artifact_hash:
			return {"ok":true, "duplicate":true, "errors":[], "draft_id":draft_id,
				"artifact_path":artifact_path, "artifact_hash":artifact.artifact_hash,
				"activates_runtime":false, "reload_required":"new_campaign_import"}
		return _reject(draft_id, ["Published draft_id already exists with different content."])
	var write_error := _write_atomic(artifact_path, JSON.stringify(artifact, "  ", true, true) + "\n")
	if not write_error.is_empty():
		return _reject(draft_id, [write_error])
	var persisted = JSON.parse_string(FileAccess.get_file_as_string(artifact_path))
	if not persisted is Dictionary:
		return _reject(draft_id, ["Published artifact failed JSON read-back verification."])
	var persisted_errors := verify_published_artifact(persisted)
	if not persisted_errors.is_empty():
		return _reject(draft_id, ["Published artifact failed schema read-back verification: " + "; ".join(persisted_errors)])
	draft_published.emit(draft_id, artifact_path)
	return {"ok":true, "duplicate":false, "errors":[], "draft_id":draft_id,
		"artifact_path":artifact_path, "artifact_hash":artifact.artifact_hash,
		"activates_runtime":false, "reload_required":"new_campaign_import"}

func clear_previews() -> void:
	_previews.clear()
	_preview_order.clear()

func _evaluate(value: Variant) -> Dictionary:
	var errors := Validator.validate_content_draft_shape(value)
	var registry = _registry()
	if registry == null or not registry.loaded:
		errors.append("ContentRegistry is unavailable.")
		return {"errors":errors, "candidate_hash":""}
	if not value is Dictionary:
		return {"errors":errors, "candidate_hash":""}
	var draft: Dictionary = value
	if draft.get("base_catalog_hash") != registry.catalog_hash:
		errors.append("Content draft targets a different catalog hash.")
	if _whole(draft.get("base_content_revision")) and int(draft.base_content_revision) != registry.revision:
		errors.append("Content draft revision does not match the current registry revision.")
	var author_role := str(draft.get("author_role", ""))
	var allowed_types: Array = ROLE_TARGET_TYPES.get(author_role, [])
	var candidate_npcs: Dictionary = registry.definitions("npc")
	var candidate_adventure: Dictionary = registry.adventure_catalog()
	var candidate_equipment:Dictionary=registry.definitions("equipment")
	var candidate_world:Dictionary=draft.get("world_bundle",{}).duplicate(true)
	for operation in draft.get("operations", []):
		if not operation is Dictionary:
			continue
		var target_type := str(operation.get("target_type", ""))
		var target_id := str(operation.get("target_id", ""))
		var definition = operation.get("definition")
		if target_type not in allowed_types:
			errors.append("Draft author role %s cannot upsert %s targets." % [author_role, target_type])
		if not definition is Dictionary:
			continue
		if target_type in ["quest", "npc", "equipment", "item", "shop"] and str(definition.get("id", "")) != target_id:
			errors.append("Draft %s definition id does not match target: %s" % [target_type, target_id])
		match target_type:
			"equipment": errors.append_array(Validator.validate_equipment(definition,"draft.equipment["+target_id+"]"))
			"item": _strict_item(definition,"draft.item["+target_id+"]",errors)
			"shop": _strict_shop(definition,"draft.shop["+target_id+"]",errors)
		match target_type:
			"quest": _upsert_quest(candidate_adventure, target_id, definition)
			"dialogue": candidate_adventure.npcs[target_id] = definition.duplicate(true)
			"npc": candidate_npcs[target_id] = definition.duplicate(true)
			"equipment": candidate_equipment[target_id]=definition.duplicate(true)
			"item":
				var item: Dictionary = definition.duplicate(true)
				item.erase("id")
				candidate_adventure.consumables[target_id]=item
			"shop": _upsert_shop(candidate_adventure,target_id,definition)
	_validate_candidate(candidate_npcs, candidate_adventure, candidate_equipment, errors)
	if not candidate_world.is_empty(): errors.append_array(get_node("/root/WorldBlueprintService").validate_world_bundle(candidate_world))
	var candidate_hash := _canonical_hash({"npcs":candidate_npcs, "adventure":candidate_adventure,"equipment":candidate_equipment,"world":candidate_world})
	return {"errors":errors, "candidate_hash":candidate_hash,
		"npcs":candidate_npcs, "adventure":candidate_adventure,"equipment":candidate_equipment,"world":candidate_world}

func _validate_candidate(npcs: Dictionary, adventure: Dictionary, equipment: Dictionary, errors: Array[String]) -> void:
	if npcs.size() > 512 or adventure.get("quests", []).size() > 512 or adventure.get("npcs", {}).size() > 512:
		errors.append("Candidate content exceeds the 512-entry catalog limit.")
	var allowed_assets := {}
	for base_npc: Dictionary in _registry().definitions("npc").values():
		allowed_assets[str(base_npc.visual.base_asset_id)] = true
		allowed_assets[str(base_npc.visual.idle_manifest_asset_id)] = true
	for npc_id in npcs:
		var definition = npcs[npc_id]
		errors.append_array(Validator.validate_town_npc(definition, "candidate.npcs[" + str(npc_id) + "]"))
		if definition is Dictionary:
			if str(definition.get("id", "")) != str(npc_id):
				errors.append("NPC definition id does not match target: " + str(npc_id))
			var visual = definition.get("visual", {})
			if visual is Dictionary:
				for field in ["base_asset_id", "idle_manifest_asset_id"]:
					if not allowed_assets.has(str(visual.get(field, ""))):
						errors.append("NPC uses an unregistered asset id: " + str(visual.get(field, "")))
	for equipment_id in equipment:
		var equipment_definition=equipment[equipment_id]
		errors.append_array(Validator.validate_equipment(equipment_definition,"candidate.equipment["+str(equipment_id)+"]"))
		if equipment_definition is Dictionary and equipment_definition.get("id")!=equipment_id: errors.append("Equipment definition id does not match target: "+str(equipment_id))
	for quest in adventure.get("quests", []):
		_strict_quest(quest, "candidate.quest", errors)
	for dialogue_id in adventure.get("npcs", {}):
		_strict_dialogue(adventure.npcs[dialogue_id], "candidate.dialogue[" + str(dialogue_id) + "]", errors)
	for npc_id in npcs:
		if not adventure.get("npcs", {}).has(npc_id):
			errors.append("NPC has no dialogue definition: " + str(npc_id))
	for dialogue_id in adventure.get("npcs", {}):
		if not npcs.has(dialogue_id):
			errors.append("Dialogue has no registered NPC presentation: " + str(dialogue_id))
	errors.append_array(AdventureValidator.validate(adventure, equipment))

func _strict_quest(value: Variant, location: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append(location + " must be an object.")
		return
	var quest: Dictionary = value
	_unknown_keys(quest, ["id", "title", "description", "npc", "position", "requires", "objectives", "consume", "rewards", "route_rewards"], location, errors)
	for field in ["id", "title", "description", "npc"]:
		_text(quest.get(field), 500 if field == "description" else 96, location + "." + field, errors)
	if not Validator.valid_target_id("quest", str(quest.get("id", ""))):
		errors.append(location + ".id is not a stable quest id.")
	if not quest.get("requires", {}) is Dictionary:
		errors.append(location + ".requires must be an object.")
	if not quest.get("consume", {}) is Dictionary:
		errors.append(location + ".consume must be an object.")
	var objectives = quest.get("objectives")
	if not objectives is Array or objectives.is_empty() or objectives.size() > 32:
		errors.append(location + ".objectives must contain between 1 and 32 entries.")
	else:
		for index in objectives.size():
			var objective = objectives[index]
			var child := "%s.objectives[%d]" % [location, index]
			if not objective is Dictionary:
				errors.append(child + " must be an object.")
				continue
			_unknown_keys(objective, ["id", "kind", "event", "material", "flag", "target", "label"], child, errors)
			_text(objective.get("id"), 64, child + ".id", errors)
			_text(objective.get("label"), 160, child + ".label", errors)
	_strict_reward(quest.get("rewards"), false, location + ".rewards", errors)
	var route_rewards = quest.get("route_rewards", {})
	if not route_rewards is Dictionary:
		errors.append(location + ".route_rewards must be an object.")
	else:
		for route in route_rewards:
			_strict_reward(route_rewards[route], false, location + ".route_rewards." + str(route), errors)

func _strict_dialogue(value: Variant, location: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append(location + " must be an object.")
		return
	var dialogue: Dictionary = value
	_unknown_keys(dialogue, ["name", "greeting", "variants", "choices"], location, errors)
	_text(dialogue.get("name"), 96, location + ".name", errors)
	_text(dialogue.get("greeting"), 1000, location + ".greeting", errors)
	var variants = dialogue.get("variants", [])
	if not variants is Array or variants.size() > 64:
		errors.append(location + ".variants must be an array of at most 64 entries.")
	else:
		for index in variants.size():
			var variant = variants[index]
			var child := "%s.variants[%d]" % [location, index]
			if not variant is Dictionary:
				errors.append(child + " must be an object.")
				continue
			_unknown_keys(variant, ["when", "text"], child, errors)
			_text(variant.get("text"), 1000, child + ".text", errors)
			if not variant.get("when", {}) is Dictionary:
				errors.append(child + ".when must be an object.")
	var choices = dialogue.get("choices")
	if not choices is Array or choices.is_empty() or choices.size() > 128:
		errors.append(location + ".choices must contain between 1 and 128 entries.")
	else:
		for index in choices.size():
			var choice = choices[index]
			var child := "%s.choices[%d]" % [location, index]
			if not choice is Dictionary:
				errors.append(child + " must be an object.")
				continue
			_unknown_keys(choice, ["id", "label", "action", "effects", "text", "quest", "when", "cost", "route", "group"], child, errors)
			for field in ["id", "label", "action"]:
				_text(choice.get(field), 160, child + "." + field, errors)
			if choice.has("text"):
				_text(choice.text, 1000, child + ".text", errors)
			if not choice.get("when", {}) is Dictionary or not choice.get("cost", {}) is Dictionary:
				errors.append(child + ".when and .cost must be objects.")
			_strict_reward(choice.get("effects", {}), true, child + ".effects", errors)

func _strict_reward(value: Variant, allow_accept: bool, location: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append(location + " must be an object.")
		return
	var reward: Dictionary = value
	var allowed := ["xp", "materials", "consumables", "flags", "reputation"]
	if allow_accept:
		allowed.append("accept")
	_unknown_keys(reward, allowed, location, errors)
	for field in ["materials", "consumables", "flags", "reputation"]:
		if reward.has(field) and not reward[field] is Dictionary:
			errors.append(location + "." + field + " must be an object.")
	if reward.has("accept") and not reward.accept is Array:
		errors.append(location + ".accept must be an array.")

func _strict_item(value:Dictionary,location:String,errors:Array[String])->void:
	_unknown_keys(value,["id","name","description","stat","amount","max_stack"],location,errors)
	_text(value.get("id"),64,location+".id",errors)
	_text(value.get("name"),64,location+".name",errors)
	_text(value.get("description"),240,location+".description",errors)
	if value.get("stat") not in ["health","mana"]: errors.append(location+".stat is unsupported.")
	for field in ["amount","max_stack"]:
		var number=value.get(field)
		if not (number is int or number is float) or not is_finite(float(number)) or floorf(float(number))!=float(number) or int(number)<1 or int(number)>9999:
			errors.append(location+"."+field+" must be an integer from 1 to 9999.")

func _strict_shop(value:Dictionary,location:String,errors:Array[String])->void:
	_unknown_keys(value,["id","kind","cost"],location,errors)
	_text(value.get("id"),64,location+".id",errors)
	if value.get("kind") not in ["equipment","consumable"]: errors.append(location+".kind is unsupported.")
	if not value.get("cost") is Dictionary or value.cost.is_empty() or value.cost.size()>8: errors.append(location+".cost must contain 1 to 8 material prices.")

func _upsert_quest(adventure: Dictionary, target_id: String, definition: Dictionary) -> void:
	for index in adventure.get("quests", []).size():
		if str(adventure.quests[index].get("id", "")) == target_id:
			adventure.quests[index] = definition.duplicate(true)
			return
	adventure.quests.append(definition.duplicate(true))

func _upsert_shop(adventure:Dictionary,target_id:String,definition:Dictionary)->void:
	for index in adventure.get("shop",[]).size():
		if str(adventure.shop[index].get("id",""))==target_id:
			adventure.shop[index]=definition.duplicate(true)
			return
	adventure.shop.append(definition.duplicate(true))

func _collect_changed_paths(before: Variant, after: Variant, path: String, result: Array[String]) -> void:
	if result.size() >= 128 or before == after:
		return
	if before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		for key in after:
			if key not in keys:
				keys.append(key)
		keys.sort()
		for key in keys:
			_collect_changed_paths(before.get(key), after.get(key), path + "/" + str(key), result)
		return
	result.append(path if not path.is_empty() else "/")

func _unknown_keys(value: Dictionary, allowed: Array, location: String, errors: Array[String]) -> void:
	for key in value:
		if key not in allowed:
			errors.append(location + " contains unsupported field: " + str(key))

func _text(value: Variant, maximum: int, location: String, errors: Array[String]) -> void:
	if not value is String or str(value).strip_edges().is_empty() or str(value).length() > maximum:
		errors.append("%s must be a non-empty string of at most %d characters." % [location, maximum])

func _write_atomic(path: String, text: String) -> String:
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return "Could not create published content directory."
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return "Could not open temporary published content file."
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Could not write published content artifact."
	var persisted = JSON.parse_string(FileAccess.get_file_as_string(temp_path))
	if not persisted is Dictionary or not verify_published_artifact(persisted).is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return "Temporary published content artifact failed verification."
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return "Could not atomically commit published content artifact."
	return ""

func _artifact_hash(value: Dictionary) -> String:
	var content := value.duplicate(true)
	content.erase("artifact_hash")
	return _canonical_hash(content)

func _canonical_hash(value: Variant) -> String:
	# Normalize through JSON once so integer/float Variant distinctions cannot
	# change an artifact checksum after it is written and parsed again.
	var normalized = JSON.parse_string(JSON.stringify(value, "", true, true))
	return JSON.stringify(normalized, "", true, true).sha256_text()

func _registry():
	return get_node_or_null("/root/ContentRegistry")

func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value)

func _reject(draft_id: String, errors: Array[String]) -> Dictionary:
	draft_rejected.emit(draft_id, errors)
	return {"ok":false, "errors":errors, "draft_id":draft_id}
