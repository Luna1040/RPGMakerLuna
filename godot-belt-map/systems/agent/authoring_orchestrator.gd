extends Node
## Trusted Main-Agent state machine. Model transports can only claim validated
## tasks and submit schema-checked results; they never mutate gameplay directly.

signal run_created(run_id: String)
signal run_updated(run_id: String, status: String)
signal task_dispatched(run_id: String, request_id: String, agent_role: String)
signal task_updated(run_id: String, request_id: String, status: String)

const REQUEST_SCHEMA := "authoring-run-request/1"
const RUN_SCHEMA := "authoring-run/1"
const STATE_SCHEMA := "authoring-orchestrator-state/1"
const MAX_RUNS := 16
const GENRES := ["western_fantasy", "cultivation", "wuxia", "hybrid"]
const TONES := ["heroic", "dark", "light", "mystery"]
const SCOPES := ["demo", "chapter", "campaign"]
const CONTENT_POLICIES := ["general", "mature_consensual"]
const SYSTEMS := ["world", "map", "town", "npcs", "main_quest", "side_quests", "affinity", "items", "equipment", "shops"]
const TERMINAL_STATUSES := ["published", "completed_analysis", "cancelled", "stale"]

var _runs: Dictionary = {}
var _run_order: Array[String] = []
var _counter := 0

func _ready() -> void:
	var registry = _registry()
	if registry != null:
		registry.content_loaded.connect(_on_content_loaded)

func validate_run_request(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Authoring run request must be an object."]
	var request: Dictionary = value
	for key in request:
		if key not in ["schema_version", "project_id", "genre", "theme", "tone", "scope", "content_policy", "requested_systems", "constraints"]:
			errors.append("Authoring request contains unsupported field: " + str(key))
	if request.get("schema_version") != REQUEST_SCHEMA:
		errors.append("Unsupported authoring run request schema_version.")
	if not _scoped_id(str(request.get("project_id", "")), "project"):
		errors.append("Authoring request project_id must be canonical.")
	_validate_text(request.get("theme"), 240, "theme", errors)
	if request.get("genre") not in GENRES:
		errors.append("Authoring request genre is unsupported.")
	if request.get("tone") not in TONES:
		errors.append("Authoring request tone is unsupported.")
	if request.get("scope") not in SCOPES:
		errors.append("Authoring request scope is unsupported.")
	if request.get("content_policy") not in CONTENT_POLICIES:
		errors.append("Authoring request content_policy is unsupported.")
	var requested = request.get("requested_systems")
	if not requested is Array or requested.is_empty() or requested.size() > 12:
		errors.append("requested_systems must contain between 1 and 12 entries.")
	else:
		var seen := {}
		for system in requested:
			if not system is String or system not in SYSTEMS or seen.has(system):
				errors.append("requested_systems contains an unsupported or duplicate entry.")
				break
			seen[system] = true
	var constraints = request.get("constraints")
	if not constraints is Array or constraints.size() > 16:
		errors.append("constraints must be an array of at most 16 entries.")
	else:
		var seen_constraints := {}
		for constraint in constraints:
			if not constraint is String:
				errors.append("Authoring request constraint must be text.")
				continue
			_validate_text(constraint, 240, "constraint", errors)
			if seen_constraints.has(constraint):
				errors.append("constraints must not contain duplicates.")
			seen_constraints[constraint] = true
	if request.get("content_policy") == "mature_consensual":
		# This policy is deliberately narrow. Transport prompts must preserve it.
		for boundary in ["所有相关角色必须为成年人", "亲密内容必须明确自愿", "禁止性暴力与胁迫"]:
			if boundary not in constraints:
				errors.append("Mature authoring requires boundary: " + boundary)
	return errors

func create_run(value: Variant) -> Dictionary:
	var errors := validate_run_request(value)
	var registry = _registry()
	var bridge = _bridge()
	if registry == null or not registry.loaded:
		errors.append("ContentRegistry is unavailable.")
	if bridge == null:
		errors.append("WorkbenchBridge is unavailable.")
	if not errors.is_empty():
		return {"ok":false, "errors":errors, "run":{}}
	if _run_order.size() >= MAX_RUNS and not _discard_oldest_terminal():
		return {"ok":false, "errors":["Authoring run capacity is full; finish or cancel an existing run."], "run":{}}
	_counter += 1
	var suffix := "%d_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), _counter]
	var run_id := "run.authoring." + suffix
	var request: Dictionary = value.duplicate(true)
	var tasks := _plan_tasks(request, suffix)
	for record: Dictionary in tasks:
		errors.append_array(bridge.validate_agent_task(record.task))
	if not errors.is_empty():
		return {"ok":false, "errors":errors, "run":{}}
	var run := {"schema_version":RUN_SCHEMA, "run_id":run_id, "status":"planned",
		"request":request, "base_catalog_hash":registry.catalog_hash,
		"base_content_revision":registry.revision, "content_context":registry.content_context(),
		"tasks":tasks, "draft":{}, "world_bundle":{}, "analysis_report":[], "actionable_patches":[], "preview":{}, "publication":{},
		"errors":[], "warnings":[], "created_at":int(Time.get_unix_time_from_system())}
	_runs[run_id] = run
	_run_order.append(run_id)
	run_created.emit(run_id)
	return {"ok":true, "errors":[], "run":run.duplicate(true)}

func get_run(run_id: String) -> Dictionary:
	return _runs.get(run_id, {}).duplicate(true)

func latest_run() -> Dictionary:
	return get_run(_run_order.back()) if not _run_order.is_empty() else {}

func list_runs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for run_id in _run_order:
		var run: Dictionary = _runs[run_id]
		result.append({"run_id":run_id, "status":run.status,
			"theme":str(run.request.theme), "genre":str(run.request.genre),
			"created_at":int(run.created_at), "task_count":run.tasks.size()})
	return result

func export_state() -> Dictionary:
	## Persist only source requests and untrusted Agent results. Derived reviews,
	## prompts, preview tokens and drafts are rebuilt through the trusted gates.
	var persisted_runs: Array[Dictionary] = []
	for run_id in _run_order:
		var run: Dictionary = _runs[run_id]
		var tasks: Array[Dictionary] = []
		for record: Dictionary in run.tasks:
			tasks.append({"role":str(record.role), "status":str(record.status),
				"result":record.result.duplicate(true), "errors":record.errors.duplicate(true)})
		persisted_runs.append({"run_id":run_id, "status":str(run.status),
			"request":run.request.duplicate(true), "base_catalog_hash":str(run.base_catalog_hash),
			"base_content_revision":int(run.base_content_revision),
			"content_context":run.content_context.duplicate(true), "tasks":tasks,
			"publication":run.publication.duplicate(true), "created_at":int(run.created_at)})
	return {"schema_version":STATE_SCHEMA, "runs":persisted_runs}

func import_state(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary or value.get("schema_version") != STATE_SCHEMA:
		return {"ok":false, "errors":["Unsupported authoring orchestrator state."], "restored":0}
	var persisted = value.get("runs")
	if not persisted is Array or persisted.size() > MAX_RUNS:
		return {"ok":false, "errors":["Authoring orchestrator state exceeds its run limit."], "restored":0}
	_runs.clear()
	_run_order.clear()
	var restored := 0
	for raw_run in persisted:
		var restored_result := _restore_run(raw_run)
		if restored_result.get("ok", false):
			restored += 1
		else:
			for message in restored_result.get("errors", []):
				errors.append(str(message))
	_counter += restored
	return {"ok":errors.is_empty(), "errors":errors, "restored":restored}

func clear_state_for_restore() -> bool:
	if not OS.is_debug_build(): return false
	_runs.clear()
	_run_order.clear()
	return true

func dispatch_ready_tasks(run_id: String) -> Dictionary:
	var run := _mutable_run(run_id)
	var errors := _current_errors(run)
	if not errors.is_empty():
		return _run_failure(run_id, errors)
	if run.status in TERMINAL_STATUSES or run.status in ["previewed", "ready_for_preview"]:
		return _run_failure(run_id, ["Authoring run does not accept further task dispatch."])
	var bundles: Array[Dictionary] = []
	for record: Dictionary in run.tasks:
		if record.status != "planned" or not _dependencies_complete(run, record.dependencies):
			continue
		if record.role == "validator":
			record.task.objective = _validator_objective(run)
		record.status = "dispatched"
		record.errors = []
		var bundle := _task_bundle(run, record)
		bundles.append(bundle)
		task_dispatched.emit(run_id, str(record.task.request_id), str(record.role))
	if not bundles.is_empty():
		run.status = "awaiting_validator" if bundles.all(func(bundle): return bundle.agent_role == "validator") else "awaiting_agents"
		_emit_run(run)
	return {"ok":true, "errors":[], "run_id":run_id, "tasks":bundles,
		"status":str(run.status), "idle":bundles.is_empty()}

func active_task_bundles(run_id: String) -> Dictionary:
	var run := _mutable_run(run_id)
	if run.is_empty():
		return _run_failure(run_id, ["Unknown authoring run."])
	if run.status in TERMINAL_STATUSES:
		return _run_failure(run_id, ["Authoring run does not accept active task retrieval."])
	var bundles: Array[Dictionary] = []
	for record: Dictionary in run.tasks:
		if record.status in ["dispatched", "needs_revision", "blocked"]:
			bundles.append(_task_bundle(run, record))
	return {"ok":true, "errors":[], "run_id":run_id, "tasks":bundles,
		"status":str(run.status)}

func submit_agent_result(run_id: String, result_value: Variant) -> Dictionary:
	var run := _mutable_run(run_id)
	var errors := _current_errors(run)
	if not errors.is_empty():
		return _run_failure(run_id, errors)
	if run.status in TERMINAL_STATUSES:
		return _run_failure(run_id, ["Authoring run does not accept Agent results in its terminal state."])
	if not result_value is Dictionary:
		return _run_failure(run_id, ["Agent result must be an object."])
	var result: Dictionary = result_value
	var record := _task_record(run, str(result.get("request_id", "")))
	if record.is_empty():
		return _run_failure(run_id, ["Agent result does not belong to this authoring run."])
	if record.status not in ["dispatched", "needs_revision", "blocked"]:
		return _run_failure(run_id, ["Agent task is not waiting for a result."])
	var reviewed: Dictionary = _bridge().review_agent_result(record.task, result)
	if not reviewed.ok:
		record.status = "needs_revision"
		record.errors = reviewed.errors.duplicate()
		record.result = result.duplicate(true)
		record.review = {}
		run.status = "needs_revision"
		run.errors = reviewed.errors.duplicate()
		task_updated.emit(run_id, str(record.task.request_id), str(record.status))
		_emit_run(run)
		return {"ok":false, "errors":reviewed.errors, "run":run.duplicate(true)}
	record.result = result.duplicate(true)
	record.review = reviewed.duplicate(true)
	record.errors = []
	if result.status != "completed":
		record.status = str(result.status)
		run.status = "needs_revision"
		run.errors = ["%s Agent returned %s." % [record.role, result.status]]
	else:
		record.status = "completed"
		run.errors = []
	task_updated.emit(run_id, str(record.task.request_id), str(record.status))
	if record.status == "completed":
		if record.role == "validator":
			var composition_errors := _compose_main_draft(run)
			if composition_errors.is_empty():
				run.status = "ready_for_preview" if not run.draft.is_empty() else "completed_analysis"
			else:
				run.status = "needs_revision"
				run.errors = composition_errors
		elif _all_primary_tasks_complete(run):
			run.status = "validator_ready"
		else:
			run.status = "awaiting_agents"
	_emit_run(run)
	return {"ok":true, "errors":[], "run":run.duplicate(true),
		"validator_ready":run.status == "validator_ready"}

func preview_run(run_id: String) -> Dictionary:
	var run := _mutable_run(run_id)
	var errors := _current_errors(run)
	if not errors.is_empty():
		return _run_failure(run_id, errors)
	if run.status not in ["ready_for_preview", "previewed"] or run.draft.is_empty():
		return _run_failure(run_id, ["Authoring run is not ready for content preview."])
	var preview: Dictionary = _bridge().preview_content_draft(run.draft)
	if not preview.ok:
		run.status = "needs_revision"
		run.errors = preview.errors.duplicate()
		_emit_run(run)
		return {"ok":false, "errors":preview.errors, "run":run.duplicate(true)}
	run.preview = preview.duplicate(true)
	run.status = "previewed"
	_emit_run(run)
	return {"ok":true, "errors":[], "preview":preview.duplicate(true), "run":run.duplicate(true)}

func publish_run(run_id: String, preview_token: String) -> Dictionary:
	var run := _mutable_run(run_id)
	var errors := _current_errors(run)
	if not errors.is_empty():
		return _run_failure(run_id, errors)
	if run.status != "previewed" or run.preview.get("preview_token") != preview_token:
		return _run_failure(run_id, ["Published authoring run must match its reviewed preview token."])
	var publication: Dictionary = _bridge().publish_content_draft(run.draft, preview_token)
	if not publication.ok:
		run.status = "needs_revision"
		run.errors = publication.errors.duplicate()
		_emit_run(run)
		return {"ok":false, "errors":publication.errors, "run":run.duplicate(true)}
	run.publication = publication.duplicate(true)
	run.status = "published"
	_emit_run(run)
	return {"ok":true, "errors":[], "publication":publication.duplicate(true), "run":run.duplicate(true)}

func cancel_run(run_id: String) -> Dictionary:
	var run := _mutable_run(run_id)
	if run.is_empty():
		return _run_failure(run_id, ["Unknown authoring run."])
	if run.status == "published":
		return _run_failure(run_id, ["Published authoring runs cannot be cancelled."])
	run.status = "cancelled"
	_emit_run(run)
	return {"ok":true, "errors":[], "run":run.duplicate(true)}

func _plan_tasks(request: Dictionary, suffix: String) -> Array[Dictionary]:
	var registry = _registry()
	var requested: Array = request.requested_systems
	var context := _context_refs(registry)
	var records: Array[Dictionary] = []
	var primary_ids: Array[String] = []
	var quest_id := "agent_story_" + suffix
	var npc_id := "agent_npc_" + suffix
	if requested.any(func(id): return id in ["world", "map", "town"]):
		var world_task := _task(request, suffix, "world", [], context, false, 1,
			"生成严格 world-blueprint/1：世界背景、区域关系、初始城镇与可达地图；只引用 asset.world.* 白名单，由 Godot 编译，不生成代码或资源路径。")
		records.append(_task_record_value(world_task, "world", []))
		primary_ids.append(world_task.request_id)
	if requested.any(func(id): return id in ["main_quest", "side_quests", "affinity"]):
		var allowed := [{"target_type":"quest", "target_id":quest_id}]
		if registry.target_exists("dialogue", "innkeeper"):
			allowed.append({"target_type":"dialogue", "target_id":"innkeeper"})
		var narrative_task := _task(request, suffix, "narrative", allowed, context, true, 1,
			"创作可验证的主线/支线与条件对话；新任务 ID 使用 %s，并与现有 NPC 对话形成可达闭环。" % quest_id)
		records.append(_task_record_value(narrative_task, "narrative", []))
		primary_ids.append(narrative_task.request_id)
	if requested.any(func(id): return id in ["npcs", "affinity"]):
		var npc_task := _task(request, suffix, "npc", [
			{"target_type":"npc", "target_id":npc_id}, {"target_type":"dialogue", "target_id":npc_id}], context, true, 1,
			"创作不同于现有角色的新 NPC、身份、关系与条件对话；ID 使用 %s，只能复用已登记资产 ID。" % npc_id)
		records.append(_task_record_value(npc_task, "npc", []))
		primary_ids.append(npc_task.request_id)
	if requested.any(func(id): return id in ["items", "equipment", "shops"]):
		var allowed: Array[Dictionary] = []
		for ref in [{"target_type":"skill", "target_id":"skill.knight.lightning"}, {"target_type":"equipment", "target_id":"courtyard_blade"}]:
			if registry.target_exists(ref.target_type, ref.target_id): allowed.append(ref)
		var systems_task := _task(request, suffix, "systems", allowed, context, false, 2,
			"分析道具、装备、商店与战斗数值；只能提出白名单 Runtime Patch 或分析，不得直接应用。")
		records.append(_task_record_value(systems_task, "systems", []))
		primary_ids.append(systems_task.request_id)
	var validator_task := _task(request, suffix, "validator", [], context, false, 0,
		"等待其他子 Agent；随后检查 Schema、引用、冲突、任务可达性、权限与内容边界。")
	records.append(_task_record_value(validator_task, "validator", primary_ids))
	return records

func _restore_run(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok":false, "errors":["Persisted authoring run is not an object."]}
	var saved: Dictionary = value
	var run_id := str(saved.get("run_id", ""))
	var suffix := run_id.trim_prefix("run.authoring.")
	var suffix_pattern := RegEx.new()
	if not run_id.begins_with("run.authoring.") or suffix_pattern.compile("^[0-9]+_[0-9]+_[0-9]+$") != OK or suffix_pattern.search(suffix) == null or _runs.has(run_id):
		return {"ok":false, "errors":["Persisted authoring run_id is invalid or duplicated."]}
	var request = saved.get("request")
	var request_errors := validate_run_request(request)
	if not request_errors.is_empty():
		return {"ok":false, "errors":request_errors}
	var registry = _registry()
	var context_matches: bool = registry != null and str(saved.get("base_catalog_hash", "")) == registry.catalog_hash \
		and int(saved.get("base_content_revision", -1)) == registry.revision \
		and saved.get("content_context") == registry.content_context()
	var tasks := _plan_tasks(request, suffix)
	var run := {"schema_version":RUN_SCHEMA, "run_id":run_id,
		"status":"planned" if context_matches else "stale", "request":request.duplicate(true),
		"base_catalog_hash":str(saved.get("base_catalog_hash", "")),
		"base_content_revision":int(saved.get("base_content_revision", 0)),
		"content_context":saved.get("content_context", {}).duplicate(true), "tasks":tasks,
		"draft":{}, "world_bundle":{}, "analysis_report":[], "actionable_patches":[], "preview":{}, "publication":{},
		"errors":[], "warnings":[], "created_at":int(saved.get("created_at", 0))}
	_runs[run_id] = run
	_run_order.append(run_id)
	if not context_matches:
		run.errors = ["Content context changed while the authoring run was offline."]
		return {"ok":true, "errors":[]}
	var saved_tasks = saved.get("tasks")
	if not saved_tasks is Array or saved_tasks.size() != tasks.size():
		_runs.erase(run_id)
		_run_order.erase(run_id)
		return {"ok":false, "errors":["Persisted authoring run task plan is invalid."]}
	# Re-review every stored result. Never trust persisted task status, draft or review.
	for role in ["world", "narrative", "npc", "systems", "validator"]:
		for raw_record in saved_tasks:
			if not raw_record is Dictionary or str(raw_record.get("role", "")) != role:
				continue
			var record := _record_for_role(run, role)
			if record.is_empty(): continue
			var result = raw_record.get("result", {})
			if result is Dictionary and not result.is_empty():
				if role == "validator": record.task.objective = _validator_objective(run)
				record.status = "dispatched"
				submit_agent_result(run_id, result)
	# Restore unfinished queue positions only after all trustworthy results replayed.
	for raw_record in saved_tasks:
		if not raw_record is Dictionary: continue
		var record := _record_for_role(run, str(raw_record.get("role", "")))
		if record.is_empty() or record.status == "completed": continue
		var saved_status := str(raw_record.get("status", "planned"))
		if saved_status in ["planned", "dispatched", "needs_revision", "blocked"]:
			record.status = "planned" if record.role == "validator" and not _dependencies_complete(run, record.dependencies) else saved_status
			record.errors = _safe_string_array(raw_record.get("errors", []), 16, 500)
	var saved_status := str(saved.get("status", "planned"))
	if saved_status == "cancelled":
		run.status = "cancelled"
	elif saved_status == "previewed" and run.status == "ready_for_preview":
		run.warnings.append("The pre-restart preview token expired; preview the run again before publishing.")
	elif saved_status == "published":
		_restore_publication(run, saved.get("publication", {}))
	elif run.status not in ["ready_for_preview", "completed_analysis", "needs_revision"]:
		_recompute_resumed_status(run)
	return {"ok":true, "errors":[]}

func _record_for_role(run: Dictionary, role: String) -> Dictionary:
	for record: Dictionary in run.tasks:
		if record.role == role: return record
	return {}

func _safe_string_array(value: Variant, limit: int, maximum: int) -> Array[String]:
	var result: Array[String] = []
	if not value is Array: return result
	for entry in value:
		if entry is String and not entry.is_empty() and entry.length() <= maximum:
			result.append(entry)
			if result.size() >= limit: break
	return result

func _recompute_resumed_status(run: Dictionary) -> void:
	if _all_primary_tasks_complete(run):
		var validator := _record_for_role(run, "validator")
		run.status = "validator_ready" if validator.status == "planned" else "awaiting_validator"
	elif run.tasks.any(func(record): return record.status == "needs_revision"):
		run.status = "needs_revision"
	elif run.tasks.any(func(record): return record.status in ["dispatched", "blocked"]):
		run.status = "awaiting_agents"
	else:
		run.status = "planned"

func _restore_publication(run: Dictionary, value: Variant) -> void:
	if not value is Dictionary or run.draft.is_empty():
		run.warnings.append("Published state could not be verified after restart; review and publish again.")
		return
	var path := str(value.get("artifact_path", ""))
	var service = get_node_or_null("/root/ContentDraftService")
	var expected_path := str(service.publish_root).path_join(str(run.request.project_id)).path_join("published").path_join(str(run.draft.draft_id) + ".json") if service != null else ""
	var artifact = JSON.parse_string(FileAccess.get_file_as_string(path)) if path == expected_path and FileAccess.file_exists(path) else null
	if service != null and artifact is Dictionary and service.verify_published_artifact(artifact).is_empty() and artifact.get("draft") == run.draft:
		run.publication = value.duplicate(true)
		run.status = "published"
	else:
		run.warnings.append("Published artifact could not be verified after restart; review and publish again.")

func _task(request: Dictionary, suffix: String, role: String, allowed: Array, context: Array,
		allow_new_ids: bool, max_proposals: int, role_objective: String) -> Dictionary:
	var objective := "%s 题材=%s；主题=%s；基调=%s；规模=%s；内容边界=%s。%s" % [
		role_objective, request.genre, request.theme, request.tone, request.scope,
		request.content_policy, _constraints_text(request.constraints)]
	return {"schema_version":"agent-task/1", "request_id":"request.authoring.%s.%s" % [suffix, role],
		"project_id":str(request.project_id), "content_revision":_registry().revision,
		"agent_role":role, "objective":objective.left(1000), "allowed_targets":allowed.duplicate(true),
		"constraints":{"max_proposals":max_proposals, "allow_new_ids":allow_new_ids, "allow_generated_code":false},
		"context_refs":context.duplicate(true)}

func _task_record_value(task: Dictionary, role: String, dependencies: Array[String]) -> Dictionary:
	return {"role":role, "status":"planned", "task":task, "dependencies":dependencies.duplicate(),
		"result":{}, "review":{}, "errors":[]}

func _context_refs(registry) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ref in [{"target_type":"quest", "target_id":"courtyard_provisions"},
		{"target_type":"dialogue", "target_id":"innkeeper"},
		{"target_type":"npc", "target_id":"innkeeper"},
		{"target_type":"skill", "target_id":"skill.knight.lightning"}]:
		if registry.target_exists(ref.target_type, ref.target_id): result.append(ref)
	return result

func _task_bundle(run: Dictionary, record: Dictionary) -> Dictionary:
	var prior: Array[Dictionary] = []
	if record.role == "validator":
		for candidate: Dictionary in run.tasks:
			if candidate.role != "validator" and candidate.status == "completed":
				prior.append({"agent_role":candidate.role, "result":candidate.result.duplicate(true),
					"review":candidate.review.duplicate(true)})
	return {"run_id":str(run.run_id), "request_id":str(record.task.request_id),
		"agent_role":str(record.role), "task":record.task.duplicate(true),
		"prior_results":prior, "prompt":_agent_prompt(run, record, prior)}

func _agent_prompt(run: Dictionary, record: Dictionary, prior: Array[Dictionary]) -> String:
	var role_rules := {"world":"地图必须作为 world_blueprint deliverable；只能使用预置 asset.world.*，不得生成脚本或资源路径。",
		"narrative":"任务/对话变化必须放入 content_draft，且只能使用 allowed_targets。",
		"npc":"NPC/对话变化必须放入 content_draft；资产只能使用已有 asset.* ID。",
		"systems":"只可分析或提出白名单 runtime_patch；不得自动执行补丁。",
		"validator":"只审查全部上游结果；deliverables 必须为空，用 summary/evidence/warnings 给出结论。"}
	var boundary := "成熟内容仅限明确成年的自愿角色，禁止胁迫与性暴力。" if run.request.content_policy == "mature_consensual" else "遵守全年龄内容边界。"
	var revision_note := ("\n上轮结果被可信边界拒绝，请逐项修正：" + "；".join(record.get("errors", []))) if not record.get("errors", []).is_empty() else ""
	return "你是 %s 子 Agent。%s %s 只返回严格符合 agent-result/1 的 JSON，不要 Markdown，不要工具调用。任务：%s%s%s" % [
		record.role, role_rules.get(record.role, ""), boundary,
		JSON.stringify(record.task, "", true, true),
		("\n待验证的上游结果：" + JSON.stringify(prior, "", true, true)) if not prior.is_empty() else "", revision_note]

func _validator_objective(run: Dictionary) -> String:
	var summaries: Array[String] = []
	for record: Dictionary in run.tasks:
		if record.role != "validator" and record.status == "completed":
			summaries.append("%s:%s" % [record.role, str(record.result.get("summary", ""))])
	return ("复核全部子 Agent 结果的 Schema、授权目标、交叉引用、冲突、任务可达性、内容边界与生成代码禁令。上游摘要：" + " | ".join(summaries)).left(1000)

func _compose_main_draft(run: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var operations: Array[Dictionary] = []
	var patches: Array[Dictionary] = []
	var targets := {}
	var world_bundles:Array[Dictionary]=[]
	for record: Dictionary in run.tasks:
		if record.role == "validator": continue
		for world_bundle in record.review.get("world_bundles",[]):
			if world_bundle is Dictionary: world_bundles.append(world_bundle.duplicate(true))
		for draft in record.review.get("content_drafts", []):
			for operation in draft.get("operations", []):
				var key := str(operation.get("target_type", "")) + ":" + str(operation.get("target_id", ""))
				if targets.has(key):
					if targets[key] != operation:
						errors.append("Conflicting child Agent operations target " + key)
					continue
				targets[key] = operation.duplicate(true)
				operations.append(operation.duplicate(true))
		for patch in record.review.get("actionable_patches", []):
			patches.append(patch.duplicate(true))
	var requires_content_draft:bool = run.tasks.any(func(record): return record.role in ["narrative", "npc"])
	if operations.is_empty() and requires_content_draft:
		errors.append("No validated narrative or NPC content draft was produced.")
	if operations.size() > 64:
		errors.append("Merged Main Agent draft exceeds 64 operations.")
	if world_bundles.size()>1:
		errors.append("Main Agent received conflicting world blueprints.")
	if not errors.is_empty(): return errors
	run.world_bundle=world_bundles[0] if world_bundles.size()==1 else {}
	run.actionable_patches = patches
	if operations.is_empty():
		var report:Array[Dictionary]=[]
		for record:Dictionary in run.tasks:
			if record.role != "validator" and record.status == "completed":
				report.append({"agent_role":str(record.role), "summary":str(record.result.get("summary", "")),
					"deliverables":record.result.get("deliverables", []).duplicate(true),
					"evidence":record.result.get("evidence", []).duplicate(true), "warnings":record.result.get("warnings", []).duplicate(true)})
		run.analysis_report = report
		return []
	var suffix := str(run.run_id).trim_prefix("run.authoring.")
	var draft := {"schema_version":"content-draft/1", "draft_id":"draft.authoring." + suffix,
		"project_id":str(run.request.project_id), "base_catalog_hash":str(run.base_catalog_hash),
		"base_content_revision":int(run.base_content_revision), "author_role":"main",
		"summary":"Main Agent 汇总：%s（%s / %s）" % [run.request.theme, run.request.genre, run.request.scope],
		"operations":operations}
	var draft_service = get_node_or_null("/root/ContentDraftService")
	if draft_service == null:
		return ["ContentDraftService is unavailable."]
	errors.append_array(draft_service.validate_draft(draft))
	if errors.is_empty():
		run.draft = draft
	return errors

func _all_primary_tasks_complete(run: Dictionary) -> bool:
	for record: Dictionary in run.tasks:
		if record.role != "validator" and record.status != "completed": return false
	return true

func _dependencies_complete(run: Dictionary, dependencies: Array) -> bool:
	for request_id in dependencies:
		var record := _task_record(run, str(request_id))
		if record.is_empty() or record.status != "completed": return false
	return true

func _task_record(run: Dictionary, request_id: String) -> Dictionary:
	for record: Dictionary in run.get("tasks", []):
		if record.task.get("request_id") == request_id: return record
	return {}

func _mutable_run(run_id: String) -> Dictionary:
	return _runs.get(run_id, {})

func _current_errors(run: Dictionary) -> Array[String]:
	if run.is_empty(): return ["Unknown authoring run."]
	if run.status == "stale": return ["Authoring run targets a stale content context."]
	var registry = _registry()
	if registry == null or registry.catalog_hash != run.base_catalog_hash or registry.revision != run.base_content_revision or registry.content_context() != run.content_context:
		run.status = "stale"
		return ["Content context changed after the authoring run was planned."]
	return []

func _on_content_loaded(_bundle_id: String, _base_hash: String) -> void:
	for run_id in _run_order:
		var run: Dictionary = _runs[run_id]
		if run.status in TERMINAL_STATUSES: continue
		_current_errors(run)
		if run.status == "stale": _emit_run(run)

func _discard_oldest_terminal() -> bool:
	for run_id in _run_order:
		if _runs[run_id].status in TERMINAL_STATUSES:
			_runs.erase(run_id)
			_run_order.erase(run_id)
			return true
	return false

func _constraints_text(constraints: Array) -> String:
	return "附加限制=" + ("；".join(constraints) if not constraints.is_empty() else "无")

func _validate_text(value: Variant, maximum: int, label: String, errors: Array[String]) -> void:
	if not value is String or value.strip_edges().is_empty() or value.length() > maximum:
		errors.append("Authoring request %s must be non-empty text of at most %d characters." % [label, maximum])

func _scoped_id(value: String, prefix: String) -> bool:
	var expression := RegEx.new()
	return expression.compile("^" + prefix + "\\.[a-z0-9][a-z0-9_.-]+$") == OK and value.length() <= 128 and expression.search(value) != null

func _run_failure(run_id: String, errors: Array[String]) -> Dictionary:
	return {"ok":false, "errors":errors, "run_id":run_id,
		"run":get_run(run_id)}

func _emit_run(run: Dictionary) -> void:
	run_updated.emit(str(run.run_id), str(run.status))

func _registry():
	return get_node_or_null("/root/ContentRegistry")

func _bridge():
	return get_node_or_null("/root/WorkbenchBridge")
