extends RefCounted
## One owner of narrative state and shop transactions. Wallet remains loot.materials.
## IDs, never translated labels, are the save boundary. No scene or input ownership.
signal changed
signal notice(text: String)

const DATA_PATH := "res://systems/adventure/adventure_data.json"
const CatalogValidator = preload("adventure_catalog.gd")
const MAX_MATERIAL := 999999
const SAVE_VERSION := 1
var equipment: RefCounted
var loot: Node
var progression: RefCounted
var catalog: Dictionary = {}
var validation_errors: Array[String] = []
var quests: Dictionary = {}
var flags: Dictionary = {}
var reputation: Dictionary = {"innkeeper": 0, "smith": 0}
var routes: Dictionary = {}
var consumables: Dictionary = {"healing_potion": 2, "mana_potion": 1}
var _busy := false

func set_up(gear: RefCounted, world_loot: Node, levels: RefCounted) -> void:
	equipment = gear
	loot = world_loot
	progression = levels
	catalog = _registered_catalog()
	if catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		catalog = parsed if parsed is Dictionary else {}
	validation_errors = CatalogValidator.validate(catalog, equipment.CATALOG if equipment != null else {})
	if not validation_errors.is_empty():
		push_error("Adventure catalog: " + "; ".join(validation_errors))
		catalog = {}
		return
	for id: String in catalog.flags:
		if not flags.has(id):
			flags[id] = false
	for id: String in catalog.consumables:
		consumables[id] = clampi(int(consumables.get(id, 0)), 0, int(catalog.consumables[id].max_stack))

func _registered_catalog() -> Dictionary:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		var registry = main_loop.root.get_node_or_null("ContentRegistry")
		if registry != null and registry.loaded:
			return registry.adventure_catalog()
	return {}

func _ready_to_mutate() -> bool:
	return not _busy and equipment != null and is_instance_valid(loot) and validation_errors.is_empty() and not catalog.is_empty()

func _result(ok: bool, message: String, action: String = "", extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": ok, "message": message, "action": action}
	result.merge(extra, true)
	if not message.is_empty():
		notice.emit(message)
	return result

func _quest(id: String) -> Dictionary:
	for entry: Dictionary in catalog.get("quests", []):
		if entry.id == id:
			return entry
	return {}

func _status(id: String) -> String:
	var definition := _quest(id)
	if definition.is_empty():
		return "unknown"
	var state: Dictionary = quests.get(id, {})
	if state.get("claimed", false):
		return "claimed"
	if state.get("accepted", false):
		return "ready" if _complete(definition) else "active"
	return "available" if _condition(definition.get("requires", {})) else "locked"

func accept_quest(id: String) -> bool:
	if not _ready_to_mutate() or _status(id) != "available":
		return false
	quests[id] = {"accepted": true, "claimed": false, "counts": {}, "seen": {}}
	changed.emit()
	notice.emit("接受委托：" + str(_quest(id).title))
	return true

func record_event(event_type: String, data: Dictionary = {}) -> void:
	if not _ready_to_mutate():
		return
	# Every objective owns its receipt set: simultaneous quests can share one event.
	# Producers provide unique IDs per encounter; ID-less events are valid but not deduplicated.
	var aliases := {"kill": "enemy_killed", "enemy_defeated": "enemy_killed", "boss_defeated": "boss_killed", "wave_completed": "wave_cleared", "crate_broken": "crate_destroyed"}
	var actual: String = aliases.get(event_type, event_type)
	var mutated := false
	for definition: Dictionary in catalog.quests:
		var state: Dictionary = quests.get(definition.id, {})
		if not state.get("accepted", false) or state.get("claimed", false):
			continue
		for objective: Dictionary in definition.objectives:
			if objective.kind != "event" or objective.event != actual:
				continue
			if data.get("training", false) or data.get("is_dummy", false):
				continue
			var count := int(state.counts.get(objective.id, 0))
			if count >= int(objective.target):
				continue
			var receipt := str(data.get("event_id", data.get("id", ""))).left(160)
			var seen: Array = state.seen.get(objective.id, [])
			if not receipt.is_empty() and seen.has(receipt):
				continue
			if not receipt.is_empty():
				seen.append(receipt)
			state.seen[objective.id] = seen
			# A death/wave event advances exactly once; never trust a caller's arbitrary amount.
			state.counts[objective.id] = mini(count + 1, int(objective.target))
			mutated = true
	if mutated:
		changed.emit()

func _objective_current(quest_id: String, objective: Dictionary) -> int:
	match str(objective.kind):
		"event":
			return mini(int(quests.get(quest_id, {}).get("counts", {}).get(objective.id, 0)), int(objective.target))
		"material":
			return mini(_wallet_amount(objective.material), int(objective.target))
		"flag":
			return int(flags.get(objective.flag, false))
	return 0

func _complete(definition: Dictionary) -> bool:
	for objective: Dictionary in definition.objectives:
		if _objective_current(definition.id, objective) < int(objective.target):
			return false
	return true

func _condition(test: Dictionary) -> bool:
	if test.has("all"):
		for child: Dictionary in test.all:
			if not _condition(child):
				return false
	if test.has("any"):
		var matches := false
		for child: Dictionary in test.any:
			matches = matches or _condition(child)
		if not matches:
			return false
	if test.has("excludes"):
		for child: Dictionary in test.excludes:
			if _condition(child):
				return false
	if test.has("quest") and not test.quest.status.has(_status(test.quest.id)):
		return false
	if test.has("flag") and flags.get(test.flag.id, false) != test.flag.get("value", true):
		return false
	if test.has("route") and routes.get(test.route.group, "") != test.route.value:
		return false
	if test.has("route_selected") and str(routes.get(test.route_selected, "")).is_empty():
		return false
	if test.has("reputation") and int(reputation.get(test.reputation.npc, 0)) < int(test.reputation.min):
		return false
	if test.has("materials") and not _cost_reason(test.materials).is_empty():
		return false
	return true

func quest_rows() -> Array:
	var result: Array = []
	for definition: Dictionary in catalog.get("quests", []):
		var state := _status(definition.id)
		var objectives: Array = []
		for objective: Dictionary in definition.objectives:
			var current := int(objective.target) if state == "claimed" else _objective_current(definition.id, objective)
			objectives.append({"id": objective.id, "label": objective.label, "current": current, "target": int(objective.target), "complete": current >= int(objective.target)})
		result.append({"id": definition.id, "title": definition.title, "description": definition.description, "npc_id": definition.npc, "status": state, "can_accept": state == "available", "can_claim": state == "ready", "objectives": objectives, "rewards": _quest_rewards(definition), "requires": definition.get("requires", {}).duplicate(true)})
	return result

func _quest_rewards(definition: Dictionary) -> Dictionary:
	var reward: Dictionary = definition.rewards.duplicate(true)
	var bonus: Dictionary = definition.get("route_rewards", {}).get(routes.get("supply_resolution", ""), {})
	for key: String in bonus:
		if bonus[key] is Dictionary:
			if not reward.has(key):
				reward[key] = {}
			for id: String in bonus[key]:
				reward[key][id] = int(reward[key].get(id, 0)) + int(bonus[key][id])
		elif key == "xp":
			reward.xp = int(reward.get("xp", 0)) + int(bonus.xp)
	return reward

func claim_quest(id: String) -> Dictionary:
	if not _ready_to_mutate():
		return _result(false, "系统尚未就绪或有交易正在进行。")
	if _status(id) != "ready":
		return _result(false, "委托尚未完成，或报酬已经领取。")
	var definition := _quest(id)
	var cost: Dictionary = definition.get("consume", {})
	var reward := _quest_rewards(definition)
	var reason := _cost_reason(cost)
	if reason.is_empty():
		reason = _reward_reason(reward, cost)
	if not reason.is_empty():
		return _result(false, reason)
	_busy = true
	# Mark the receipt before emitting any downstream signals (XP can level up).
	quests[id].claimed = true
	_spend(cost)
	_apply_reward(reward)
	_busy = false
	changed.emit()
	return _result(true, "完成「%s」：%s" % [definition.title, _reward_text(reward)], "", {"quest_id": id, "rewards": reward})

func _wallet_amount(id: String) -> int:
	if not is_instance_valid(loot):
		return 0
	return clampi(int(loot.materials.get(id, 0)), 0, MAX_MATERIAL)

func wallet() -> Dictionary:
	var result := {}
	for id: String in catalog.get("materials", []):
		result[id] = _wallet_amount(id)
	return result

func _cost_reason(cost: Dictionary, quantity: int = 1) -> String:
	for id: String in cost:
		if _wallet_amount(id) < int(cost[id]) * quantity:
			return "%s不足，需要 %d，持有 %d。" % [id, int(cost[id]) * quantity, _wallet_amount(id)]
	return ""

func _spend(cost: Dictionary, quantity: int = 1) -> void:
	for id: String in cost:
		loot.materials[id] = _wallet_amount(id) - int(cost[id]) * quantity

func _reward_reason(reward: Dictionary, cost: Dictionary = {}) -> String:
	if int(reward.get("xp", 0)) > 0 and (progression == null or not progression.has_method("add_xp")):
		return "经验系统尚未就绪，报酬暂未领取。"
	for id: String in reward.get("materials", {}):
		if _wallet_amount(id) - int(cost.get(id, 0)) + int(reward.materials[id]) > MAX_MATERIAL:
			return id + "已达到背包上限，请先使用一部分。"
	for id: String in reward.get("consumables", {}):
		if int(consumables.get(id, 0)) + int(reward.consumables[id]) > int(catalog.consumables[id].max_stack):
			return str(catalog.consumables[id].name) + "已达到堆叠上限。"
	return ""

func _apply_reward(reward: Dictionary) -> void:
	for id: String in reward.get("materials", {}):
		loot.materials[id] = _wallet_amount(id) + int(reward.materials[id])
	for id: String in reward.get("consumables", {}):
		consumables[id] = int(consumables.get(id, 0)) + int(reward.consumables[id])
	_apply_effects(reward)
	if int(reward.get("xp", 0)) > 0 and progression != null and progression.has_method("add_xp"):
		progression.add_xp(int(reward.xp))

func _apply_effects(effects: Dictionary) -> void:
	for id: String in effects.get("flags", {}):
		flags[id] = bool(effects.flags[id])
	for id: String in effects.get("reputation", {}):
		reputation[id] = clampi(int(reputation.get(id, 0)) + int(effects.reputation[id]), -100, 100)

func _reward_text(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if int(reward.get("xp", 0)) > 0:
		parts.append("经验 +%d" % int(reward.xp))
	for id: String in reward.get("materials", {}):
		parts.append("%s ×%d" % [id, int(reward.materials[id])])
	for id: String in reward.get("consumables", {}):
		parts.append("%s ×%d" % [catalog.consumables[id].name, int(reward.consumables[id])])
	return "、".join(parts)

func dialogue_for(npc_id: String) -> Dictionary:
	var npc: Dictionary = catalog.get("npcs", {}).get(npc_id, {})
	if npc.is_empty():
		return {"npc_id": npc_id, "name": "", "text": "", "choices": []}
	var line: String = npc.greeting
	for variant: Dictionary in npc.get("variants", []):
		if _condition(variant.when):
			line = variant.text
			break
	var choices: Array = []
	for choice: Dictionary in npc.choices:
		if not _condition(choice.get("when", {})):
			continue
		var reason := _choice_reason(choice)
		choices.append({"id": choice.id, "label": choice.label, "action": choice.action, "enabled": reason.is_empty(), "reason": reason})
	return {"npc_id": npc_id, "name": npc.name, "text": line, "choices": choices, "reputation": int(reputation.get(npc_id, 0))}

func _choice_reason(choice: Dictionary) -> String:
	if choice.action == "claim" and _status(choice.quest) != "ready":
		return "目标尚未全部完成；请查看任务进度。"
	return _cost_reason(choice.get("cost", {}))

func choose(npc_id: String, choice_id: String) -> Dictionary:
	if not _ready_to_mutate():
		return _result(false, "系统尚未就绪或有交易正在进行。")
	var selected: Dictionary = {}
	for choice: Dictionary in catalog.npcs.get(npc_id, {}).get("choices", []):
		if choice.id == choice_id:
			selected = choice
			break
	if selected.is_empty() or not _condition(selected.get("when", {})):
		return _result(false, "这条对话已经变化，请重新选择。")
	var reason := _choice_reason(selected)
	if not reason.is_empty():
		return _result(false, reason)
	match str(selected.action):
		"accept":
			var accepted := accept_quest(selected.quest)
			return _result(accepted, "委托已加入任务页。" if accepted else "无法接受该委托。")
		"claim":
			return claim_quest(selected.quest)
		"route":
			_busy = true
			_spend(selected.get("cost", {}))
			routes[selected.group] = selected.route
			_apply_effects(selected.get("effects", {}))
			_busy = false
			changed.emit()
			return _result(true, selected.get("text", "故事分支已记录。"), "", {"route": selected.route})
		"procure":
			return _procure(selected)
		"effect":
			# Repeating informational dialogue is safe: clue effects are booleans.
			var effects: Dictionary = selected.get("effects", {})
			for id: String in effects.get("accept", []):
				if _status(id) == "available":
					accept_quest(id)
			_busy = true
			_apply_effects(effects)
			_busy = false
			changed.emit()
			return _result(true, selected.get("text", "已记录。"))
		_:
			return _result(true, selected.get("text", ""), selected.action)

func _procure(choice: Dictionary) -> Dictionary:
	var reward := {"materials": {"木料": 3, "碎布": 1}}
	var reason := _reward_reason(reward, choice.cost)
	if not reason.is_empty():
		return _result(false, reason)
	_busy = true
	_spend(choice.cost)
	_apply_reward(reward)
	quests[choice.quest].counts["crate"] = 1
	_busy = false
	changed.emit()
	return _result(true, choice.text)

func _output_reason(kind: String, id: String, quantity: int) -> String:
	if quantity < 1 or quantity > 99:
		return "购买数量必须在 1 到 99 之间。"
	if kind == "equipment":
		if not equipment.CATALOG.has(id):
			return "装备不存在。"
		if quantity != 1:
			return "唯一装备每次只能购买一件。"
		if equipment.owned.has(id):
			return "已经拥有这件装备，不会再次扣款。"
	elif kind == "consumable":
		if not catalog.consumables.has(id):
			return "药剂不存在。"
		if int(consumables.get(id, 0)) + quantity > int(catalog.consumables[id].max_stack):
			return "药剂堆叠上限为 %d。" % int(catalog.consumables[id].max_stack)
	else:
		return "不支持的物品类型。"
	return ""

func _transact(kind: String, id: String, amount: int, cost: Dictionary, cost_quantity: int = 1) -> Dictionary:
	if not _ready_to_mutate():
		return _result(false, "系统尚未就绪或有交易正在进行。")
	var reason := _output_reason(kind, id, amount)
	if reason.is_empty():
		reason = _cost_reason(cost, cost_quantity)
	if not reason.is_empty():
		return _result(false, reason)
	_busy = true
	var previous_blocked := equipment.is_blocking_signals()
	if kind == "equipment":
		# Grant may save the equipment file; its observers must not see a half-paid trade.
		equipment.set_block_signals(true)
		if not equipment.grant(id):
			equipment.set_block_signals(previous_blocked)
			_busy = false
			return _result(false, "装备发放失败，未扣除任何材料。")
	_spend(cost, cost_quantity)
	if kind == "consumable":
		consumables[id] = int(consumables.get(id, 0)) + amount
	_busy = false
	if kind == "equipment":
		equipment.set_block_signals(previous_blocked)
		if not previous_blocked:
			equipment.changed.emit()
	changed.emit()
	var item_name: String = equipment.CATALOG[id].name if kind == "equipment" else catalog.consumables[id].name
	return _result(true, "获得 %s ×%d" % [item_name, amount], "", {"item_id": id, "quantity": amount})

func buy(item_id: String, quantity: int = 1) -> Dictionary:
	for item: Dictionary in catalog.get("shop", []):
		if item.id == item_id:
			return _transact(item.kind, item_id, quantity, item.cost, quantity)
	return _result(false, "商店没有这件物品。")

func craft(recipe_id: String) -> Dictionary:
	for recipe: Dictionary in catalog.get("recipes", []):
		if recipe.id == recipe_id:
			return _transact(recipe.output.kind, recipe.output.id, int(recipe.output.amount), recipe.cost)
	return _result(false, "未知配方。")

func shop_rows() -> Array:
	var rows: Array = []
	for item: Dictionary in catalog.get("shop", []):
		var info: Dictionary = equipment.CATALOG[item.id] if item.kind == "equipment" else catalog.consumables[item.id]
		var reason := _output_reason(item.kind, item.id, 1)
		if reason.is_empty():
			reason = _cost_reason(item.cost)
		rows.append({"id": item.id, "name": info.name, "description": info.description, "kind": item.kind, "cost": item.cost.duplicate(), "owned": equipment.owned.has(item.id) if item.kind == "equipment" else int(consumables.get(item.id, 0)), "can_buy": reason.is_empty(), "reason": reason})
	return rows

func recipe_rows() -> Array:
	var rows: Array = []
	for recipe: Dictionary in catalog.get("recipes", []):
		var reason := _output_reason(recipe.output.kind, recipe.output.id, int(recipe.output.amount))
		if reason.is_empty():
			reason = _cost_reason(recipe.cost)
		rows.append({"id": recipe.id, "name": recipe.name, "cost": recipe.cost.duplicate(), "output": recipe.output.duplicate(), "can_craft": reason.is_empty(), "reason": reason})
	return rows

func use_consumable(id: String, actor: Node) -> Dictionary:
	if not _ready_to_mutate() or not is_instance_valid(actor) or not catalog.get("consumables", {}).has(id):
		return _result(false, "无法使用这件物品。")
	if int(consumables.get(id, 0)) <= 0:
		return _result(false, "该药剂已经用完。")
	if not _has_property(actor, "health") or not _has_property(actor, "mana") or not _has_property(actor, "max_health") or not _has_property(actor, "max_mana"):
		return _result(false, "当前角色不支持药剂。")
	if float(actor.get("health")) <= 0 or (_has_property(actor, "defeated") and bool(actor.get("defeated"))):
		return _result(false, "倒下时无法喝药，请先复活。")
	var item: Dictionary = catalog.consumables[id]
	var before := float(actor.get(item.stat))
	var maximum := float(actor.get("max_" + str(item.stat)))
	if before >= maximum:
		return _result(false, "状态已满，未消耗药剂。")
	_busy = true
	actor.set(item.stat, minf(maximum, before + float(item.amount)))
	consumables[id] = int(consumables[id]) - 1
	_busy = false
	if actor.has_signal("stats_changed"):
		actor.emit_signal("stats_changed", float(actor.get("health")), float(actor.get("mana")))
	changed.emit()
	return _result(true, "使用%s，恢复 %d 点。" % [item.name, int(float(actor.get(item.stat)) - before)])

func _has_property(value: Object, property: String) -> bool:
	for entry: Dictionary in value.get_property_list():
		if entry.name == property:
			return true
	return false

func graph_nodes() -> Array:
	var nodes: Array = []
	for quest: Dictionary in catalog.get("quests", []):
		nodes.append({"id": quest.id, "kind": "quest", "title": quest.title, "description": quest.description, "status": _status(quest.id), "position": quest.position.duplicate()})
	var index := 0
	for pair: Array in [["smith", "route_repair"], ["innkeeper", "route_bargain"], ["innkeeper", "route_investigate"]]:
		for choice: Dictionary in catalog.get("npcs", {}).get(pair[0], {}).get("choices", []):
			if choice.id != pair[1]:
				continue
			var selected := str(routes.get(choice.group, ""))
			var state := "selected" if selected == choice.route else ("excluded" if not selected.is_empty() else ("available" if _condition(choice.get("when", {})) else "locked"))
			nodes.append({"id": choice.id, "kind": "choice", "title": {"repair": "修复结界", "bargain": "协商改道", "investigate": "追查真相"}[choice.route], "description": choice.label, "status": state, "position": [2, index], "npc_id": pair[0], "choice_id": choice.id})
			index += 1
	return nodes

func narrative_graph() -> Dictionary:
	return {"title": catalog.get("title", ""), "nodes": graph_nodes(), "edges": catalog.get("graph_edges", []).duplicate(true), "routes": routes.duplicate(), "flags": flags.duplicate(), "reputation": reputation.duplicate()}

func snapshot() -> Dictionary:
	# Wallet belongs to the world save, never duplicate it here.
	return {"version": SAVE_VERSION, "quests": quests.duplicate(true), "flags": flags.duplicate(), "reputation": reputation.duplicate(), "routes": routes.duplicate(), "consumables": consumables.duplicate()}

func restore(data: Dictionary) -> bool:
	if not _ready_to_mutate() or data.get("version") != SAVE_VERSION:
		return false
	for field: String in ["quests", "flags", "reputation", "routes", "consumables"]:
		if not data.get(field) is Dictionary:
			return false
	var restored_quests := {}
	for definition: Dictionary in catalog.quests:
		var raw: Variant = data.quests.get(definition.id, {})
		if not raw is Dictionary or raw.get("accepted") != true:
			continue
		var state := {"accepted": true, "claimed": raw.get("claimed") == true, "counts": {}, "seen": {}}
		var counts: Dictionary = raw.get("counts", {}) if raw.get("counts", {}) is Dictionary else {}
		var receipts: Dictionary = raw.get("seen", {}) if raw.get("seen", {}) is Dictionary else {}
		for objective: Dictionary in definition.objectives:
			if objective.kind != "event":
				continue
			var saved: Variant = counts.get(objective.id, 0)
			var count := 0
			if saved is int or saved is float:
				count = clampi(int(saved), 0, int(objective.target)) if is_finite(float(saved)) else 0
			state.counts[objective.id] = int(objective.target) if state.claimed else count
			var clean: Array = []
			var seen: Variant = receipts.get(objective.id, [])
			if seen is Array:
				for token: Variant in seen:
					if token is String and not token.is_empty() and not clean.has(token.left(160)):
						clean.append(token.left(160))
					if clean.size() >= int(objective.target):
						break
			state.seen[objective.id] = clean
		restored_quests[definition.id] = state
	var restored_flags := {}
	for id: String in catalog.flags:
		restored_flags[id] = data.flags.get(id) == true
	var restored_routes := {}
	for group: String in catalog.routes:
		var route: Variant = data.routes.get(group, "")
		if route is String and catalog.routes[group].has(route):
			restored_routes[group] = route
	# Route-dependent booleans are derived, so conflicting saves cannot choose all outcomes.
	for pair: Array in [["ward_repaired", "repair"], ["bargain_struck", "bargain"], ["culprit_exposed", "investigate"]]:
		restored_flags[pair[0]] = restored_routes.get("supply_resolution", "") == pair[1]
	var restored_reputation := {}
	for npc: String in catalog.npcs:
		var value: Variant = data.reputation.get(npc, 0)
		restored_reputation[npc] = clampi(int(value), -100, 100) if (value is int or value is float) and is_finite(float(value)) else 0
	var restored_consumables := {}
	for id: String in catalog.consumables:
		var value: Variant = data.consumables.get(id, 0)
		restored_consumables[id] = clampi(int(value), 0, int(catalog.consumables[id].max_stack)) if (value is int or value is float) and is_finite(float(value)) else 0
	quests = restored_quests
	flags = restored_flags
	routes = restored_routes
	reputation = restored_reputation
	consumables = restored_consumables
	changed.emit()
	return true
