extends RefCounted
## Structural and cross-reference checks before a catalog can mutate game state.

static func validate(data: Dictionary, equipment: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if data.get("schema_version") != 1:
		errors.append("unsupported schema_version")
	for field: String in ["quests", "shop", "recipes", "graph_edges", "materials", "flags"]:
		if not data.get(field) is Array:
			errors.append(field + " must be an array")
	for field: String in ["npcs", "routes", "consumables"]:
		if not data.get(field) is Dictionary:
			errors.append(field + " must be an object")
	if not errors.is_empty():
		return errors
	for field: String in ["materials", "flags"]:
		var names := {}
		for value: Variant in data[field]:
			if not value is String or value.is_empty() or names.has(value):
				errors.append("invalid/duplicate " + field + " ID")
			else:
				names[value] = true
	for group: String in data.routes:
		if not data.routes[group] is Array or data.routes[group].is_empty():
			errors.append("invalid route group: " + group)
			continue
		var values := {}
		for value: Variant in data.routes[group]:
			if not value is String or value.is_empty() or values.has(value):
				errors.append("invalid/duplicate route value: " + group)
			else:
				values[value] = true
	if not errors.is_empty():
		return errors
	var ids := {}
	for quest: Variant in data.quests:
		if not quest is Dictionary or not quest.get("id") is String or not quest.get("objectives") is Array or not quest.get("rewards") is Dictionary:
			errors.append("invalid quest structure")
			continue
		if ids.has(quest.id):
			errors.append("duplicate quest: " + quest.id)
		ids[quest.id] = quest
		if not data.npcs.has(quest.get("npc", "")):
			errors.append("unknown quest NPC: " + quest.id)
		for field: String in ["title", "description"]:
			if not quest.get(field) is String:
				errors.append("quest " + quest.id + " missing " + field)
		if quest.objectives.is_empty():
			errors.append("quest has no objective: " + quest.id)
		var objectives := {}
		for objective: Variant in quest.objectives:
			if not objective is Dictionary or not objective.get("id") is String or not _positive_integer(objective.get("target")) or not objective.get("label") is String:
				errors.append("invalid objective: " + quest.id)
				continue
			if objectives.has(objective.id):
				errors.append("duplicate objective: " + quest.id)
			objectives[objective.id] = true
			match str(objective.get("kind", "")):
				"event":
					if not ["crate_destroyed", "enemy_killed", "boss_killed", "wave_cleared"].has(objective.get("event")):
						errors.append("unknown objective event: " + quest.id)
				"material":
					if not data.materials.has(objective.get("material")):
						errors.append("unknown objective material: " + quest.id)
				"flag":
					if not data.flags.has(objective.get("flag")):
						errors.append("unknown objective flag: " + quest.id)
				_:
					errors.append("unknown objective kind: " + quest.id)
		_check_cost(quest.get("consume", {}), data, errors)
		_check_reward(quest.rewards, data, errors)
		if not quest.get("position") is Array or quest.position.size() != 2 or not (quest.position[0] is int or quest.position[0] is float) or not (quest.position[1] is int or quest.position[1] is float):
			errors.append("invalid graph position: " + quest.id)
		if not quest.get("route_rewards", {}) is Dictionary:
			errors.append("route_rewards must be an object")
		else:
			for route: Variant in quest.get("route_rewards", {}):
				if not data.routes.get("supply_resolution", []).has(route):
					errors.append("unknown reward route")
				_check_reward(quest.route_rewards[route], data, errors)
	for quest: Dictionary in ids.values():
		_check_condition(quest.get("requires", {}), data, ids, errors)
	var visited := {}
	for id: String in ids:
		_check_cycle(id, ids, [], visited, errors)
	for id: String in data.consumables:
		var item: Variant = data.consumables[id]
		if not item is Dictionary or not item.get("name") is String or not item.get("description") is String or not ["health", "mana"].has(item.get("stat")) or not _positive_integer(item.get("amount")) or not _positive_integer(item.get("max_stack")):
			errors.append("invalid consumable: " + id)
	var graph_ids := ids.duplicate()
	for npc_id: String in data.npcs:
		var npc: Variant = data.npcs[npc_id]
		if not npc is Dictionary or not npc.get("name") is String or not npc.get("greeting") is String or not npc.get("choices") is Array:
			errors.append("invalid NPC: " + npc_id)
			continue
		if not npc.get("variants", []) is Array:
			errors.append("NPC variants must be an array")
			continue
		for variant: Variant in npc.get("variants", []):
			if not variant is Dictionary or not variant.get("text") is String:
				errors.append("invalid NPC variant: " + npc_id)
			else:
				_check_condition(variant.get("when", {}), data, ids, errors)
		var choices := {}
		for choice: Variant in npc.choices:
			if not choice is Dictionary or not choice.get("id") is String or not choice.get("label") is String:
				errors.append("invalid NPC choice: " + npc_id)
				continue
			if choices.has(choice.id):
				errors.append("duplicate NPC choice: " + choice.id)
			choices[choice.id] = true
			if not ["accept", "claim", "effect", "route", "procure", "shop", "craft", "journal", "request_trial", "recruit_companion"].has(choice.get("action")):
				errors.append("unknown dialogue action: " + choice.id)
			if choice.has("quest") and not ids.has(choice.quest):
				errors.append("unknown dialogue quest: " + choice.id)
			if choice.get("action") == "route":
				if not data.routes.get(choice.get("group", ""), []).has(choice.get("route")):
					errors.append("unknown route: " + choice.id)
				graph_ids[choice.id] = choice
			_check_condition(choice.get("when", {}), data, ids, errors)
			_check_cost(choice.get("cost", {}), data, errors)
			var effects: Variant = choice.get("effects", {})
			_check_reward(effects, data, errors)
			if effects is Dictionary:
				if not effects.get("accept", []) is Array:
					errors.append("accepted quests must be an array")
				else:
					for id: Variant in effects.get("accept", []):
						if not id is String or not ids.has(id):
							errors.append("unknown accepted quest")
	var shop_ids := {}
	for item: Variant in data.shop:
		if not item is Dictionary:
			errors.append("invalid shop row")
			continue
		_check_output(item, data, equipment, errors)
		_check_cost(item.get("cost", {}), data, errors)
		if shop_ids.has(item.get("id", "")):
			errors.append("duplicate shop item")
		shop_ids[item.get("id", "")] = true
	var recipe_ids := {}
	for recipe: Variant in data.recipes:
		if not recipe is Dictionary or not recipe.get("id") is String or not recipe.get("name") is String or not recipe.get("output") is Dictionary:
			errors.append("invalid recipe")
			continue
		_check_cost(recipe.get("cost", {}), data, errors)
		_check_output(recipe.output, data, equipment, errors)
		if not _positive_integer(recipe.output.get("amount")):
			errors.append("invalid recipe output amount")
		if recipe_ids.has(recipe.id):
			errors.append("duplicate recipe: " + recipe.id)
		recipe_ids[recipe.id] = true
	for edge: Variant in data.graph_edges:
		if not edge is Dictionary or not graph_ids.has(edge.get("from")) or not graph_ids.has(edge.get("to")):
			errors.append("graph edge references an unknown node")
	return errors

static func _positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0 and float(value) <= 999999 and float(value) == floorf(float(value))

static func _check_cost(cost: Variant, data: Dictionary, errors: Array[String]) -> void:
	if not cost is Dictionary:
		errors.append("cost must be an object")
		return
	for id: Variant in cost:
		if not data.materials.has(id) or not _positive_integer(cost[id]):
			errors.append("unknown material or invalid amount in cost")

static func _check_reward(reward: Variant, data: Dictionary, errors: Array[String]) -> void:
	if not reward is Dictionary:
		errors.append("reward/effects must be an object")
		return
	for field: String in ["materials", "consumables", "flags", "reputation"]:
		if not reward.get(field, {}) is Dictionary:
			errors.append("reward " + field + " must be an object")
			return
	_check_cost(reward.get("materials", {}), data, errors)
	if reward.has("xp") and not _positive_integer(reward.xp):
		errors.append("invalid XP reward")
	for id: String in reward.get("consumables", {}):
		if not data.consumables.has(id) or not _positive_integer(reward.consumables[id]):
			errors.append("invalid consumable reward")
	for id: String in reward.get("flags", {}):
		if not data.flags.has(id) or not reward.flags[id] is bool:
			errors.append("invalid flag effect")
	for id: String in reward.get("reputation", {}):
		if not data.npcs.has(id) or not (reward.reputation[id] is int or reward.reputation[id] is float):
			errors.append("invalid reputation effect")

static func _check_output(output: Dictionary, data: Dictionary, equipment: Dictionary, errors: Array[String]) -> void:
	if output.get("kind") == "equipment":
		if not equipment.has(output.get("id")):
			errors.append("unknown equipment output")
	elif output.get("kind") == "consumable":
		if not data.consumables.has(output.get("id")):
			errors.append("unknown consumable output")
	else:
		errors.append("unknown output kind")

static func _check_condition(condition: Variant, data: Dictionary, ids: Dictionary, errors: Array[String], depth: int = 0) -> void:
	if not condition is Dictionary or depth > 32:
		errors.append("invalid/deep condition")
		return
	for key: String in condition:
		if not ["all", "any", "excludes", "quest", "flag", "route", "route_selected", "reputation", "materials"].has(key):
			errors.append("unknown condition operator: " + key)
	for key: String in ["all", "any", "excludes"]:
		if condition.has(key):
			if not condition[key] is Array:
				errors.append(key + " must be an array")
			else:
				for child: Variant in condition[key]:
					_check_condition(child, data, ids, errors, depth + 1)
	if condition.has("quest"):
		var quest: Variant = condition.quest
		if not quest is Dictionary or not ids.has(quest.get("id")) or not quest.get("status") is Array:
			errors.append("invalid quest condition")
		else:
			for status: Variant in quest.status:
				if not ["available", "locked", "active", "ready", "claimed"].has(status):
					errors.append("invalid quest status condition")
	if condition.has("flag") and (not condition.flag is Dictionary or not data.flags.has(condition.flag.get("id")) or not condition.flag.get("value", true) is bool):
		errors.append("invalid flag condition")
	if condition.has("route") and (not condition.route is Dictionary or not data.routes.get(condition.route.get("group", ""), []).has(condition.route.get("value"))):
		errors.append("invalid route condition")
	if condition.has("route_selected") and not data.routes.has(condition.route_selected):
		errors.append("invalid route group condition")
	if condition.has("reputation") and (not condition.reputation is Dictionary or not data.npcs.has(condition.reputation.get("npc")) or not (condition.reputation.get("min") is int or condition.reputation.get("min") is float)):
		errors.append("invalid reputation condition")
	if condition.has("materials"):
		_check_cost(condition.materials, data, errors)

static func _dependencies(condition: Dictionary) -> Array:
	var result: Array = []
	if condition.has("quest") and condition.quest is Dictionary:
		result.append(condition.quest.get("id", ""))
	for key: String in ["all", "any", "excludes"]:
		if condition.get(key, []) is Array:
			for child: Variant in condition.get(key, []):
				if child is Dictionary:
					result.append_array(_dependencies(child))
	return result

static func _check_cycle(id: String, quests: Dictionary, stack: Array, visited: Dictionary, errors: Array[String]) -> void:
	if stack.has(id):
		errors.append("quest prerequisite cycle: " + " -> ".join(stack) + " -> " + id)
		return
	if visited.has(id) or not quests.has(id):
		return
	var next := stack.duplicate()
	next.append(id)
	if quests[id].get("requires", {}) is Dictionary:
		for other: String in _dependencies(quests[id].get("requires", {})):
			_check_cycle(other, quests, next, visited, errors)
	visited[id] = true
