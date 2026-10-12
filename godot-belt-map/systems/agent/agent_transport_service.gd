extends Node
## Replaceable OpenAI-compatible transport for trusted authoring tasks.
## Credentials stay in environment/session memory. Provider output still passes
## through AuthoringOrchestrator and WorkbenchBridge before it is accepted.

signal configuration_changed(capabilities: Dictionary)
signal job_updated(job_id: String, status: String)
signal run_stage_finished(run_id: String, run_status: String)
signal preflight_updated(result: Dictionary)

const CONFIG_SCHEMA := "agent-transport-config/1"
const STATE_SCHEMA := "agent-transport-state/1"
const DEFAULT_CONFIG_PATH := "user://agent_transport.cfg"
const MAX_JOBS := 64
const MAX_RESPONSE_BYTES := 1024 * 1024
const ACTIVE_STATUSES := ["queued", "running", "retry_wait"]
const TERMINAL_STATUSES := ["completed", "rejected", "failed", "cancelled"]
const PROVIDER_PROFILES := {
	"custom":{"label":"自定义 OpenAI-compatible","endpoint":"","endpoint_locked":false},
	"openai":{"label":"OpenAI Chat Completions","endpoint":"https://api.openai.com/v1/chat/completions","endpoint_locked":true},
	"local":{"label":"本机 OpenAI-compatible","endpoint":"http://127.0.0.1:8080/v1/chat/completions","endpoint_locked":false}
}

var config_path := DEFAULT_CONFIG_PATH
var retry_base_seconds := 1.0
var _config := {"schema_version":CONFIG_SCHEMA, "provider":"openai_compatible", "profile_id":"custom", "endpoint":"", "model":"",
	"timeout_seconds":45, "max_retries":2, "max_concurrency":2}
var _session_api_key := ""
var _environment_api_key := ""
var _jobs:Dictionary={}
var _job_order:Array[String]=[]
var _active_request_ids:Dictionary={}
var _request_nodes:Dictionary={}
var _counter:=0
var _test_responder:Callable=Callable()
var _preflight_request:HTTPRequest
var _preflight_started_msec:=0
var _last_preflight:Dictionary={"status":"not_run","ok":false,"latency_msec":0,"http_status":0,"message":"尚未预检","checked_at":0}
var _metric_counts:Dictionary={"completed":0,"rejected":0,"failed":0,"cancelled":0,"retried":0}
var _latency_samples:Array[int]=[]

func _ready()->void:
	var environment_value:=OS.get_environment("RPG_AGENT_API_KEY").strip_edges()
	_environment_api_key=environment_value if environment_value.is_empty() or _validate_api_key(environment_value).is_empty() else ""
	load_config()
	set_process(true)

func validate_config(value:Variant)->Array[String]:
	var errors:Array[String]=[]
	if not value is Dictionary: return ["Agent transport config must be an object."]
	var candidate:Dictionary=value
	for key in candidate:
		if key not in ["schema_version","provider","profile_id","endpoint","model","timeout_seconds","max_retries","max_concurrency"]:
			errors.append("Agent transport config contains unsupported field: "+str(key))
	if candidate.get("schema_version")!=CONFIG_SCHEMA: errors.append("Unsupported agent transport config schema_version.")
	if candidate.get("provider")!="openai_compatible": errors.append("Agent transport provider must be openai_compatible.")
	var profile_id:=str(candidate.get("profile_id","custom"))
	if not PROVIDER_PROFILES.has(profile_id): errors.append("Agent transport profile_id is unsupported.")
	var endpoint:=str(candidate.get("endpoint","")).strip_edges()
	if not _valid_endpoint(endpoint):
		errors.append("Endpoint must be HTTPS, or HTTP on localhost, without query parameters or credentials.")
	if profile_id=="openai" and endpoint!=str(PROVIDER_PROFILES.openai.endpoint):
		errors.append("The OpenAI profile uses its fixed official Chat Completions endpoint.")
	if profile_id=="local" and not (endpoint.begins_with("http://127.0.0.1") or endpoint.begins_with("http://localhost")):
		errors.append("The local profile only accepts a localhost endpoint.")
	var model:=str(candidate.get("model","")).strip_edges()
	var model_pattern:=RegEx.new()
	if model_pattern.compile("^[A-Za-z0-9][A-Za-z0-9._:/-]{1,127}$")!=OK or model_pattern.search(model)==null:
		errors.append("Model must be a provider model id of 2 to 128 safe characters.")
	_validate_integer(candidate.get("timeout_seconds"),5,120,"timeout_seconds",errors)
	_validate_integer(candidate.get("max_retries"),0,3,"max_retries",errors)
	_validate_integer(candidate.get("max_concurrency"),1,4,"max_concurrency",errors)
	return errors

func configure(value:Variant,session_api_key:String="")->Dictionary:
	if _active_job_count()>0:
		return {"ok":false,"errors":["Agent transport cannot be reconfigured while jobs are active."],"capabilities":capabilities()}
	if _preflight_request!=null and is_instance_valid(_preflight_request):
		return {"ok":false,"errors":["Agent transport cannot be reconfigured during provider preflight."],"capabilities":capabilities()}
	var errors:=validate_config(value)
	if not session_api_key.is_empty(): errors.append_array(_validate_api_key(session_api_key))
	if not errors.is_empty(): return {"ok":false,"errors":errors,"capabilities":capabilities()}
	_config=(value as Dictionary).duplicate(true)
	_config.profile_id=str(_config.get("profile_id","custom"))
	_config.endpoint=str(_config.endpoint).strip_edges()
	_config.model=str(_config.model).strip_edges()
	if not session_api_key.is_empty(): _session_api_key=session_api_key.strip_edges()
	var saved:=_save_config()
	if not saved.is_empty(): return {"ok":false,"errors":[saved],"capabilities":capabilities()}
	configuration_changed.emit(capabilities())
	_pump_if_ready()
	return {"ok":true,"errors":[],"capabilities":capabilities()}

func load_config()->Dictionary:
	if not FileAccess.file_exists(config_path): return {"ok":true,"loaded":false,"errors":[]}
	var file:=ConfigFile.new()
	var load_error:=file.load(config_path)
	if load_error!=OK: return {"ok":false,"loaded":false,"errors":["Could not read agent transport config."]}
	var candidate:={"schema_version":str(file.get_value("transport","schema_version","")),
		"provider":str(file.get_value("transport","provider","")),
		"profile_id":str(file.get_value("transport","profile_id","custom")),
		"endpoint":str(file.get_value("transport","endpoint","")),
		"model":str(file.get_value("transport","model","")),
		"timeout_seconds":file.get_value("transport","timeout_seconds",45),
		"max_retries":file.get_value("transport","max_retries",2),
		"max_concurrency":file.get_value("transport","max_concurrency",2)}
	var errors:=validate_config(candidate)
	if not errors.is_empty(): return {"ok":false,"loaded":false,"errors":errors}
	_config=candidate
	configuration_changed.emit(capabilities())
	return {"ok":true,"loaded":true,"errors":[]}

func set_session_api_key(value:String)->Dictionary:
	var errors:=_validate_api_key(value)
	if not errors.is_empty(): return {"ok":false,"errors":errors,"capabilities":capabilities()}
	_session_api_key=value.strip_edges()
	configuration_changed.emit(capabilities())
	_pump_if_ready()
	return {"ok":true,"errors":[],"capabilities":capabilities()}

func clear_session_api_key()->void:
	_session_api_key=""
	configuration_changed.emit(capabilities())

func capabilities()->Dictionary:
	var config_errors:=validate_config(_config)
	var key_source:="session" if not _session_api_key.is_empty() else ("environment" if not _environment_api_key.is_empty() else "none")
	return {"schema_version":"agent-transport-capabilities/1","provider":"openai_compatible","profile_id":str(_config.get("profile_id","custom")),
		"configured":config_errors.is_empty(),"ready":config_errors.is_empty() and key_source!="none",
		"endpoint":str(_config.endpoint),"model":str(_config.model),
		"timeout_seconds":int(_config.timeout_seconds),"max_retries":int(_config.max_retries),
		"max_concurrency":int(_config.max_concurrency),"key_source":key_source,
		"config_path":config_path,"active_jobs":_active_job_count(),"retained_jobs":_job_order.size(),
		"allows_tools":false,"allows_generated_code":false,"preflight":_last_preflight.duplicate(true),"errors":config_errors}

func provider_profiles()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for profile_id in ["custom","openai","local"]:
		var profile:Dictionary=PROVIDER_PROFILES[profile_id]
		result.append({"profile_id":profile_id,"label":str(profile.label),"endpoint":str(profile.endpoint),
			"endpoint_locked":bool(profile.endpoint_locked)})
	return result

func start_preflight()->Dictionary:
	var caps:=capabilities()
	if not caps.ready: return {"ok":false,"started":false,"errors":["Configure an endpoint, model and session/environment key before preflight."]}
	if _preflight_request!=null and is_instance_valid(_preflight_request):
		return {"ok":false,"started":false,"errors":["A provider preflight is already running."]}
	_preflight_request=HTTPRequest.new()
	_preflight_request.timeout=float(_config.timeout_seconds)
	_preflight_request.body_size_limit=MAX_RESPONSE_BYTES
	add_child(_preflight_request)
	_preflight_request.request_completed.connect(_on_preflight_completed,CONNECT_ONE_SHOT)
	var headers:=PackedStringArray(["Content-Type: application/json","Accept: application/json",
		"Authorization: Bearer "+_api_key(),"User-Agent: RPGMakerLuna-AgentTransport/1"])
	_preflight_started_msec=Time.get_ticks_msec()
	_last_preflight={"status":"running","ok":false,"latency_msec":0,"http_status":0,"message":"正在进行真实 HTTP 预检","checked_at":int(Time.get_unix_time_from_system())}
	preflight_updated.emit(_last_preflight.duplicate(true))
	var error:=_preflight_request.request(str(_config.endpoint),headers,HTTPClient.METHOD_POST,JSON.stringify(_preflight_body()))
	if error!=OK:
		_complete_preflight(false,0,"无法启动供应商预检请求")
		return {"ok":false,"started":false,"errors":["Could not start provider preflight request."]}
	return {"ok":true,"started":true,"errors":[],"preflight":_last_preflight.duplicate(true)}

func preflight_status()->Dictionary:
	return _last_preflight.duplicate(true)

func metrics()->Dictionary:
	var samples:=_latency_samples.duplicate()
	samples.sort()
	var total:=int(_metric_counts.completed)+int(_metric_counts.rejected)+int(_metric_counts.failed)+int(_metric_counts.cancelled)
	var sum:=0
	for sample in samples: sum+=sample
	var p95:int=samples[mini(samples.size()-1,ceili(float(samples.size())*.95)-1)] if not samples.is_empty() else 0
	return {"schema_version":"agent-transport-metrics/1","counts":_metric_counts.duplicate(true),"terminal_jobs":total,
		"success_rate":float(_metric_counts.completed)/float(total) if total>0 else 0.0,
		"average_latency_msec":roundi(float(sum)/float(samples.size())) if not samples.is_empty() else 0,
		"p95_latency_msec":p95,"active_jobs":_active_job_count(),"preflight":_last_preflight.duplicate(true)}

func evaluate_cases(value:Variant)->Dictionary:
	if not value is Array or value.is_empty() or value.size()>32:
		return {"ok":false,"errors":["Evaluation suite must contain 1 to 32 cases."],"cases":[]}
	var reports:Array[Dictionary]=[]
	var passed:=0
	for index in range(value.size()):
		var entry=value[index]
		if not entry is Dictionary:
			reports.append({"index":index,"passed":false,"errors":["Evaluation case must be an object."]})
			continue
		var task=entry.get("task",{})
		var result=entry.get("result",{})
		var task_errors:Array[String]=_bridge().validate_agent_task(task) if _bridge()!=null else ["WorkbenchBridge is unavailable."]
		var review:Dictionary=_bridge().review_agent_result(task,result) if task_errors.is_empty() else {"ok":false,"errors":task_errors}
		var expected_ok:=bool(entry.get("expected_ok",true))
		var case_passed:=bool(review.get("ok",false))==expected_ok
		if case_passed: passed+=1
		reports.append({"index":index,"name":str(entry.get("name","case-%d" % index)),"passed":case_passed,
			"expected_ok":expected_ok,"review_ok":bool(review.get("ok",false)),"errors":review.get("errors",[]).duplicate()})
	return {"ok":passed==value.size(),"errors":[],"passed":passed,"total":value.size(),"pass_rate":float(passed)/float(value.size()),"cases":reports}

func run_ready_stage(run_id:String)->Dictionary:
	var caps:=capabilities()
	if not caps.ready:
		var errors:Array[String]=caps.errors.duplicate()
		if caps.key_source=="none": errors.append("Set RPG_AGENT_API_KEY or a session-only API key before dispatch.")
		return {"ok":false,"errors":errors,"jobs":[],"run_id":run_id}
	var bridge=_bridge()
	if bridge==null: return {"ok":false,"errors":["WorkbenchBridge is unavailable."],"jobs":[],"run_id":run_id}
	var dispatched:Dictionary=bridge.dispatch_authoring_tasks(run_id)
	if not dispatched.get("ok",false): return {"ok":false,"errors":dispatched.get("errors",[]),"jobs":[],"run_id":run_id}
	var bundles:Array=dispatched.get("tasks",[])
	if bundles.is_empty():
		var active:Dictionary=bridge.active_authoring_tasks(run_id)
		if not active.get("ok",false): return {"ok":false,"errors":active.get("errors",[]),"jobs":[],"run_id":run_id}
		bundles=active.get("tasks",[])
	var created:Array[Dictionary]=[]
	for value in bundles:
		if not value is Dictionary: continue
		var bundle:Dictionary=value
		var request_id:=str(bundle.get("request_id",""))
		if request_id.is_empty() or _active_request_ids.has(request_id): continue
		if _job_order.size()>=MAX_JOBS and not _discard_oldest_terminal():
			return {"ok":false,"errors":["Agent transport job capacity is full."],"jobs":created,"run_id":run_id}
		created.append(_enqueue(bundle))
	_pump()
	return {"ok":true,"errors":[],"jobs":created,"run_id":run_id,"idle":created.is_empty(),
		"run":bridge.get_authoring_run(run_id)}

func list_jobs(run_id:String="")->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for job_id in _job_order:
		var job:Dictionary=_jobs[job_id]
		if run_id.is_empty() or job.run_id==run_id: result.append(_public_job(job))
	return result

func get_job(job_id:String)->Dictionary:
	return _public_job(_jobs.get(job_id,{}))

func export_state()->Dictionary:
	## Bundles/prompts and credentials are deliberately absent. On restore each
	## request is rehydrated from the trusted orchestrator's active task bundle.
	var active:Array[Dictionary]=[]
	for job_id in _job_order:
		var job:Dictionary=_jobs[job_id]
		if job.status in ACTIVE_STATUSES:
			active.append({"run_id":str(job.run_id),"request_id":str(job.request_id),
				"agent_role":str(job.agent_role),"status":str(job.status),
				"attempts":int(job.attempts),"created_at":int(job.created_at)})
	return {"schema_version":STATE_SCHEMA,"active_jobs":active}

func import_state(value:Variant)->Dictionary:
	if not value is Dictionary or value.get("schema_version")!=STATE_SCHEMA:
		return {"ok":false,"errors":["Unsupported agent transport state."],"restored":0}
	var values=value.get("active_jobs")
	if not values is Array or values.size()>MAX_JOBS:
		return {"ok":false,"errors":["Agent transport state exceeds its job limit."],"restored":0}
	_clear_jobs()
	var restored:=0
	var errors:Array[String]=[]
	var seen:Dictionary={}
	for entry in values:
		if not entry is Dictionary: continue
		var run_id:=str(entry.get("run_id",""))
		var request_id:=str(entry.get("request_id",""))
		if run_id.is_empty() or request_id.is_empty() or seen.has(request_id):
			errors.append("Persisted agent transport job identity is invalid or duplicated.")
			continue
		seen[request_id]=true
		var active:Dictionary=_bridge().active_authoring_tasks(run_id) if _bridge()!=null else {}
		var bundle:Dictionary={}
		for candidate in active.get("tasks",[]):
			if candidate is Dictionary and candidate.get("request_id")==request_id:
				bundle=candidate
				break
		if bundle.is_empty() or str(bundle.get("agent_role",""))!=str(entry.get("agent_role","")):
			errors.append("Persisted agent job no longer matches an active trusted task: "+request_id)
			continue
		var public_job:=_enqueue(bundle)
		var job:Dictionary=_jobs[public_job.job_id]
		job.attempts=mini(maxi(int(entry.get("attempts",0)),0),int(_config.max_retries)+1)
		job.created_at=maxi(int(entry.get("created_at",0)),0)
		restored+=1
	_pump_if_ready()
	return {"ok":errors.is_empty(),"errors":errors,"restored":restored}

func clear_state_for_restore()->bool:
	if not OS.is_debug_build(): return false
	_clear_jobs()
	return true

func cancel_job(job_id:String)->Dictionary:
	var job:Dictionary=_jobs.get(job_id,{})
	if job.is_empty(): return {"ok":false,"errors":["Unknown agent transport job."]}
	if job.status not in ACTIVE_STATUSES: return {"ok":false,"errors":["Agent transport job is already terminal."],"job":_public_job(job)}
	if _request_nodes.has(job_id):
		var request=_request_nodes[job_id]
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
		_request_nodes.erase(job_id)
	_finish_job(job,"cancelled",["Cancelled by the user."])
	_pump()
	return {"ok":true,"errors":[],"job":_public_job(job)}

func cancel_run_jobs(run_id:String)->Dictionary:
	var cancelled:=0
	for job_id in _job_order.duplicate():
		var job:Dictionary=_jobs[job_id]
		if job.run_id==run_id and job.status in ACTIVE_STATUSES:
			if cancel_job(job_id).get("ok",false): cancelled+=1
	return {"ok":true,"errors":[],"run_id":run_id,"cancelled":cancelled}

func set_test_responder(responder:Callable)->bool:
	if not OS.is_debug_build(): return false
	_test_responder=responder
	return true

func clear_test_responder()->void:
	_test_responder=Callable()

func _process(_delta:float)->void:
	var now:=Time.get_ticks_msec()
	var changed:=false
	for job_id in _job_order:
		var job:Dictionary=_jobs[job_id]
		if job.status=="retry_wait" and int(job.next_attempt_msec)<=now:
			job.status="queued"
			changed=true
	if changed: _pump()

func _enqueue(bundle:Dictionary)->Dictionary:
	_counter+=1
	var job_id:="job.agent.%d_%d_%d" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec(),_counter]
	var job:={"job_id":job_id,"run_id":str(bundle.get("run_id","")),"request_id":str(bundle.get("request_id","")),
		"agent_role":str(bundle.get("agent_role","")),"status":"queued","attempts":0,
		"created_at":int(Time.get_unix_time_from_system()),"updated_at":int(Time.get_unix_time_from_system()),
		"next_attempt_msec":0,"errors":[],"bundle":bundle.duplicate(true)}
	_jobs[job_id]=job
	_job_order.append(job_id)
	_active_request_ids[job.request_id]=job_id
	job_updated.emit(job_id,"queued")
	return _public_job(job)

func _pump()->void:
	while _running_count()<int(_config.max_concurrency):
		var next:Dictionary={}
		for job_id in _job_order:
			var candidate:Dictionary=_jobs[job_id]
			if candidate.status=="queued":
				next=candidate
				break
		if next.is_empty(): return
		_start_job(next)

func _pump_if_ready()->void:
	if capabilities().ready: _pump()

func _clear_jobs()->void:
	for job_id in _request_nodes.keys():
		var request=_request_nodes[job_id]
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_request_nodes.clear()
	_jobs.clear()
	_job_order.clear()
	_active_request_ids.clear()

func _start_job(job:Dictionary)->void:
	job.status="running"
	job.attempts=int(job.attempts)+1
	job.updated_at=int(Time.get_unix_time_from_system())
	job.errors=[]
	job.started_msec=Time.get_ticks_msec()
	job_updated.emit(str(job.job_id),"running")
	if _test_responder.is_valid():
		call_deferred("_complete_test_job",str(job.job_id))
		return
	var request:=HTTPRequest.new()
	request.timeout=float(_config.timeout_seconds)
	request.body_size_limit=MAX_RESPONSE_BYTES
	add_child(request)
	_request_nodes[job.job_id]=request
	request.request_completed.connect(_on_request_completed.bind(str(job.job_id)),CONNECT_ONE_SHOT)
	var headers:=PackedStringArray(["Content-Type: application/json","Accept: application/json",
		"Authorization: Bearer "+_api_key(),"User-Agent: RPGMakerLuna-AgentTransport/1"])
	var error:=request.request(str(_config.endpoint),headers,HTTPClient.METHOD_POST,JSON.stringify(_provider_body(job.bundle)))
	if error!=OK:
		request.queue_free()
		_request_nodes.erase(job.job_id)
		_retry_or_finish(job,"Could not start provider request.",true)

func _complete_test_job(job_id:String)->void:
	var job:Dictionary=_jobs.get(job_id,{})
	if job.is_empty() or job.status!="running": return
	var response=_test_responder.call(job.bundle.duplicate(true),int(job.attempts))
	if not response is Dictionary:
		_retry_or_finish(job,"Test responder returned an invalid envelope.",false)
		return
	_handle_response(job,int(response.get("response_code",200)),str(response.get("body","")),bool(response.get("transport_ok",true)))

func _on_request_completed(result:int,response_code:int,_headers:PackedStringArray,body:PackedByteArray,job_id:String)->void:
	var job:Dictionary=_jobs.get(job_id,{})
	if _request_nodes.has(job_id):
		var request=_request_nodes[job_id]
		if is_instance_valid(request): request.queue_free()
		_request_nodes.erase(job_id)
	if job.is_empty() or job.status!="running": return
	_handle_response(job,response_code,body.get_string_from_utf8(),result==HTTPRequest.RESULT_SUCCESS)

func _handle_response(job:Dictionary,response_code:int,body:String,transport_ok:bool)->void:
	if not transport_ok:
		_retry_or_finish(job,"Provider request failed before a complete response.",true)
		return
	if response_code<200 or response_code>=300:
		var retryable:=response_code in [408,425,429] or response_code>=500
		_retry_or_finish(job,"Provider returned HTTP %d." % response_code,retryable)
		return
	if body.to_utf8_buffer().size()>MAX_RESPONSE_BYTES:
		_retry_or_finish(job,"Provider response exceeded the 1 MiB limit.",false)
		return
	var envelope_parse:=_parse_json(body)
	if not envelope_parse.ok:
		_retry_or_finish(job,"Provider response was not valid JSON.",false)
		return
	var envelope=envelope_parse.value
	var content=""
	if envelope is Dictionary:
		var choices=envelope.get("choices",[])
		if choices is Array and not choices.is_empty() and choices[0] is Dictionary:
			var message=choices[0].get("message",{})
			if message is Dictionary and message.get("content") is String: content=str(message.content)
	if content.is_empty():
		_retry_or_finish(job,"Provider response did not contain choices[0].message.content.",false)
		return
	var stripped:=content.strip_edges()
	if not stripped.begins_with("{") or not stripped.ends_with("}"):
		_finish_job(job,"rejected",["Provider content was not a strict JSON object; Markdown fences are not accepted."])
		_pump()
		return
	var result_parse:=_parse_json(stripped)
	var result_value=result_parse.value
	if not result_parse.ok or not result_value is Dictionary:
		_finish_job(job,"rejected",["Provider content was not a strict JSON object; Markdown fences are not accepted."])
		_pump()
		return
	var reviewed:Dictionary=_bridge().submit_authoring_result(str(job.run_id),result_value)
	if not reviewed.get("ok",false):
		_finish_job(job,"rejected",reviewed.get("errors",["Agent result failed trusted review."]))
	else:
		_finish_job(job,"completed",[])
	_pump()

func _retry_or_finish(job:Dictionary,error_message:String,retryable:bool)->void:
	if retryable and int(job.attempts)<=int(_config.max_retries):
		_metric_counts.retried=int(_metric_counts.retried)+1
		job.status="retry_wait"
		job.errors=[error_message]
		job.updated_at=int(Time.get_unix_time_from_system())
		var delay_ms:=int(maxf(.01,retry_base_seconds)*1000.0*pow(2.0,float(int(job.attempts)-1)))
		job.next_attempt_msec=Time.get_ticks_msec()+delay_ms
		job_updated.emit(str(job.job_id),"retry_wait")
	else:
		_finish_job(job,"failed",[error_message])
	_pump()

func _finish_job(job:Dictionary,status:String,errors:Array)->void:
	job.status=status
	job.errors=errors.duplicate()
	job.updated_at=int(Time.get_unix_time_from_system())
	job.next_attempt_msec=0
	job.latency_msec=maxi(0,Time.get_ticks_msec()-int(job.get("started_msec",Time.get_ticks_msec())))
	_metric_counts[status]=int(_metric_counts.get(status,0))+1
	_latency_samples.append(int(job.latency_msec))
	if _latency_samples.size()>128: _latency_samples.pop_front()
	_active_request_ids.erase(str(job.request_id))
	job_updated.emit(str(job.job_id),status)
	if not _has_active_run_job(str(job.run_id)):
		var run:Dictionary=_bridge().get_authoring_run(str(job.run_id)) if _bridge()!=null else {}
		run_stage_finished.emit(str(job.run_id),str(run.get("status","unknown")))

func _provider_body(bundle:Dictionary)->Dictionary:
	return {"model":str(_config.model),"temperature":0.2,"response_format":{"type":"json_object"},
		"messages":[{"role":"system","content":"你是受限 RPG 子 Agent。禁止工具调用、代码执行和资源路径；只返回严格 agent-result/1 JSON。"},
			{"role":"user","content":str(bundle.get("prompt",""))}]}

func _preflight_body()->Dictionary:
	return {"model":str(_config.model),"temperature":0,"response_format":{"type":"json_object"},
		"messages":[{"role":"system","content":"Return one strict JSON object and no Markdown."},
			{"role":"user","content":"Provider preflight. Return exactly {\"ok\":true,\"service\":\"rpg-agent\"}."}]}

func _on_preflight_completed(result:int,response_code:int,_headers:PackedStringArray,body:PackedByteArray)->void:
	if result!=HTTPRequest.RESULT_SUCCESS:
		_complete_preflight(false,response_code,"供应商预检未收到完整响应")
		return
	if response_code<200 or response_code>=300:
		_complete_preflight(false,response_code,"供应商预检返回 HTTP %d" % response_code)
		return
	var envelope_parse:=_parse_json(body.get_string_from_utf8())
	var content=""
	if envelope_parse.ok and envelope_parse.value is Dictionary:
		var choices=envelope_parse.value.get("choices",[])
		if choices is Array and not choices.is_empty() and choices[0] is Dictionary:
			var message=choices[0].get("message",{})
			if message is Dictionary and message.get("content") is String: content=str(message.content)
	var parsed:=_parse_json(content.strip_edges())
	var accepted:bool=parsed.ok and parsed.value is Dictionary and parsed.value.get("ok")==true
	_complete_preflight(accepted,response_code,"预检通过：鉴权、模型与严格 JSON 响应可用" if accepted else "预检响应不符合严格 JSON 探针合同")

func _complete_preflight(ok:bool,http_status:int,message:String)->void:
	_last_preflight={"status":"passed" if ok else "failed","ok":ok,
		"latency_msec":maxi(0,Time.get_ticks_msec()-_preflight_started_msec),"http_status":http_status,
		"message":message,"checked_at":int(Time.get_unix_time_from_system())}
	if _preflight_request!=null and is_instance_valid(_preflight_request): _preflight_request.queue_free()
	_preflight_request=null
	preflight_updated.emit(_last_preflight.duplicate(true))

func _parse_json(text:String)->Dictionary:
	var parser:=JSON.new()
	var error:=parser.parse(text)
	return {"ok":error==OK,"value":parser.data if error==OK else null}

func _public_job(job:Dictionary)->Dictionary:
	if job.is_empty(): return {}
	return {"job_id":str(job.job_id),"run_id":str(job.run_id),"request_id":str(job.request_id),
		"agent_role":str(job.agent_role),"status":str(job.status),"attempts":int(job.attempts),
		"created_at":int(job.created_at),"updated_at":int(job.updated_at),"latency_msec":int(job.get("latency_msec",0)),"errors":job.errors.duplicate()}

func _save_config()->String:
	var file:=ConfigFile.new()
	for key in ["schema_version","provider","profile_id","endpoint","model","timeout_seconds","max_retries","max_concurrency"]:
		file.set_value("transport",key,_config[key])
	var error:=file.save(config_path)
	return "Could not save agent transport config." if error!=OK else ""

func _valid_endpoint(value:String)->bool:
	var expression:=RegEx.new()
	var pattern:="^(https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?/[A-Za-z0-9_./-]+|http://(localhost|127\\.0\\.0\\.1)(?::[0-9]{1,5})?/[A-Za-z0-9_./-]+)$"
	return value.length()<=512 and expression.compile(pattern)==OK and expression.search(value)!=null

func _validate_api_key(value:String)->Array[String]:
	var cleaned:=value.strip_edges()
	if cleaned.length()<8 or cleaned.length()>512 or "\n" in cleaned or "\r" in cleaned:
		return ["Session API key must contain 8 to 512 characters without line breaks."]
	return []

func _validate_integer(value:Variant,minimum:int,maximum:int,label:String,errors:Array[String])->void:
	if not (value is int or value is float) or not is_finite(float(value)) or floorf(float(value))!=float(value) or int(value)<minimum or int(value)>maximum:
		errors.append("Agent transport %s must be an integer from %d to %d." % [label,minimum,maximum])

func _active_job_count()->int:
	var count:=0
	for job_id in _job_order:
		if _jobs[job_id].status in ACTIVE_STATUSES: count+=1
	return count

func _running_count()->int:
	var count:=0
	for job_id in _job_order:
		if _jobs[job_id].status=="running": count+=1
	return count

func _has_active_run_job(run_id:String)->bool:
	for job_id in _job_order:
		var job:Dictionary=_jobs[job_id]
		if job.run_id==run_id and job.status in ACTIVE_STATUSES: return true
	return false

func _discard_oldest_terminal()->bool:
	for job_id in _job_order:
		if _jobs[job_id].status in TERMINAL_STATUSES:
			_jobs.erase(job_id)
			_job_order.erase(job_id)
			return true
	return false

func _api_key()->String:
	return _session_api_key if not _session_api_key.is_empty() else _environment_api_key

func _bridge():
	return get_node_or_null("/root/WorkbenchBridge")
