extends SceneTree
## B-08: safe config, memory-only credentials, async dispatch, retry/cancel,
## strict provider envelope parsing, trusted result review, and transport UI.

var failures:Array[String]=[]
var response_mode:="normal"
var scratch_config:=""

func _initialize()->void:
	call_deferred("run")

func check(condition:bool,message:String)->void:
	if not condition: failures.append(message)

func run()->void:
	var bridge=root.get_node_or_null("WorkbenchBridge")
	var transport=root.get_node_or_null("AgentTransportService")
	check(bridge!=null and transport!=null,"Agent transport Autoloads unavailable")
	if bridge==null or transport==null:
		finish()
		return
	var registry=root.get_node_or_null("ContentRegistry")
	registry.load_base_content()
	scratch_config="user://agent-transport-test-"+str(Time.get_ticks_usec())+".cfg"
	transport.config_path=scratch_config
	transport.retry_base_seconds=.01
	check(not transport.validate_config(config_fixture("http://example.com/v1/chat/completions")).is_empty(),"remote plaintext HTTP endpoint was accepted")
	check(not transport.validate_config(config_fixture("https://example.com/v1/chat/completions?key=secret")).is_empty(),"endpoint query credentials were accepted")
	var configured:Dictionary=transport.configure(config_fixture("http://127.0.0.1:9999/v1/chat/completions"),"session-test-key")
	check(configured.get("ok",false) and configured.capabilities.ready,"valid localhost transport config was rejected")
	check(configured.capabilities.key_source=="session","session-only credential source was not reported")
	check(FileAccess.file_exists(scratch_config),"safe transport config was not persisted")
	if FileAccess.file_exists(scratch_config):
		var persisted:=FileAccess.get_file_as_string(scratch_config)
		check("session-test-key" not in persisted and "api_key" not in persisted.to_lower(),"API key leaked into persisted transport config")
	check(transport.set_test_responder(_provider_response),"debug test responder could not be installed")

	var created:Dictionary=bridge.create_authoring_run(request_fixture("自动传输边境地图"))
	check(created.get("ok",false),"transport test Run was not created")
	var run_id:String=str(created.get("run",{}).get("run_id",""))
	var started:Dictionary=bridge.run_authoring_agent_stage(run_id)
	check(started.get("ok",false) and started.get("jobs",[]).size()==1,"World Agent transport job was not started")
	check(await wait_for_stage_jobs(bridge,run_id),"World Agent transport job did not finish")
	var after_world:Dictionary=bridge.get_authoring_run(run_id)
	check(after_world.get("status")=="validator_ready","transport bypassed or failed the Validator dependency gate")
	check(bridge.list_authoring_agent_jobs(run_id).size()==1,"Validator was automatically dispatched without user action")
	var validator_started:Dictionary=bridge.run_authoring_agent_stage(run_id)
	check(validator_started.get("jobs",[]).size()==1 and validator_started.jobs[0].agent_role=="validator","explicit Validator stage was not started")
	check(await wait_for_stage_jobs(bridge,run_id),"Validator transport job did not finish")
	check(bridge.get_authoring_run(run_id).get("status")=="completed_analysis","validated transport Run did not complete as analysis")

	response_mode="retry_once"
	var retry_created:Dictionary=bridge.create_authoring_run(request_fixture("限流重试地图"))
	var retry_run_id:String=str(retry_created.get("run",{}).get("run_id",""))
	var retry_started:Dictionary=bridge.run_authoring_agent_stage(retry_run_id)
	check(retry_started.get("jobs",[]).size()==1,"retry test job was not created")
	check(await wait_for_stage_jobs(bridge,retry_run_id),"retry test job did not reach a terminal state")
	var retry_jobs:Array[Dictionary]=bridge.list_authoring_agent_jobs(retry_run_id)
	check(not retry_jobs.is_empty() and retry_jobs[0].status=="completed" and retry_jobs[0].attempts==2,"HTTP 429 did not use bounded retry before success")
	check(not retry_jobs[0].has("bundle") and not retry_jobs[0].has("prompt") and not retry_jobs[0].has("api_key"),"public job metadata exposed private request content")
	response_mode="normal"
	bridge.cancel_authoring_run(retry_run_id)
	response_mode="fenced_json"
	var strict_created:Dictionary=bridge.create_authoring_run(request_fixture("严格 JSON 拒绝测试"))
	var strict_run_id:String=str(strict_created.get("run",{}).get("run_id",""))
	bridge.run_authoring_agent_stage(strict_run_id)
	check(await wait_for_stage_jobs(bridge,strict_run_id),"fenced JSON test did not finish")
	var strict_jobs:Array[Dictionary]=bridge.list_authoring_agent_jobs(strict_run_id)
	check(not strict_jobs.is_empty() and strict_jobs[0].status=="rejected","Markdown-fenced provider content was not rejected")
	check(bridge.get_authoring_run(strict_run_id).get("status")=="awaiting_agents","transport-format rejection falsely completed the Agent task")
	response_mode="normal"
	bridge.run_authoring_agent_stage(strict_run_id)
	check(await wait_for_stage_jobs(bridge,strict_run_id),"corrected strict JSON retry did not finish")
	check(bridge.get_authoring_run(strict_run_id).get("status")=="validator_ready","corrected strict JSON result did not recover the task")
	bridge.cancel_authoring_run(strict_run_id)

	var cancel_created:Dictionary=bridge.create_authoring_run(request_fixture("取消中的地图任务"))
	var cancel_run_id:String=str(cancel_created.get("run",{}).get("run_id",""))
	var cancel_started:Dictionary=bridge.run_authoring_agent_stage(cancel_run_id)
	check(cancel_started.get("jobs",[]).size()==1,"cancel test job was not created")
	var reconfigure_while_active:Dictionary=transport.configure(config_fixture("https://provider.example/v1/chat/completions"),"")
	check(not reconfigure_while_active.get("ok",true),"transport reconfigured while a job was active")
	if not cancel_started.get("jobs",[]).is_empty():
		var cancelled:Dictionary=bridge.cancel_authoring_agent_job(str(cancel_started.jobs[0].job_id))
		check(cancelled.get("ok",false) and cancelled.job.status=="cancelled","queued/running transport job was not cancelled")
	await process_frame
	check(bridge.get_authoring_run(cancel_run_id).get("status")=="awaiting_agents","job cancellation incorrectly marked the Agent task complete")
	bridge.cancel_authoring_run(cancel_run_id)
	var late_result:Dictionary=_agent_result_for_task(cancel_started.jobs[0].request_id,"world")
	check(not bridge.submit_authoring_result(cancel_run_id,late_result).get("ok",true),"late network result revived a cancelled authoring Run")

	var ui_created:Dictionary=bridge.create_authoring_run(request_fixture("控制台自动派发"))
	check(ui_created.get("ok",false),"UI fixture Run was not created")
	change_scene_to_file("res://stage.tscn")
	check(await wait_for_stage(),"stage did not open for transport UI check")
	var panel=current_scene.runtime.panel if current_scene!=null and current_scene.runtime!=null else null
	check(panel!=null,"transport console panel is unavailable")
	if panel!=null:
		panel.open("authoring")
		await process_frame
		var endpoint_field=panel.body.find_child("AgentTransportEndpoint",true,false)
		var key_field=panel.body.find_child("AgentTransportSessionKey",true,false)
		check(endpoint_field is LineEdit and endpoint_field.text=="http://127.0.0.1:9999/v1/chat/completions","transport endpoint was not rendered from safe config")
		check(key_field is LineEdit and key_field.secret and key_field.text.is_empty(),"session key was rendered back into the UI")
		check(find_button(panel.body,"运行当前就绪 Agent 阶段")!=null,"automatic Agent stage action is missing")
		check(has_text(panel.body,"密钥来源：本次会话内存"),"transport readiness/key source is not visible")

	transport.clear_test_responder()
	transport.clear_session_api_key()
	if FileAccess.file_exists(scratch_config): DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_config))
	finish()

func config_fixture(endpoint:String)->Dictionary:
	return {"schema_version":"agent-transport-config/1","provider":"openai_compatible","endpoint":endpoint,
		"model":"test-json-model","timeout_seconds":15,"max_retries":2,"max_concurrency":2}

func request_fixture(theme:String)->Dictionary:
	return {"schema_version":"authoring-run-request/1","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","theme":theme,"tone":"mystery","scope":"demo","content_policy":"general",
		"requested_systems":["world","map"],"constraints":["只生成可审查的世界与地图分析"]}

func _provider_response(bundle:Dictionary,attempt:int)->Dictionary:
	if response_mode=="retry_once" and attempt==1:
		return {"transport_ok":true,"response_code":429,"body":"{\"error\":\"rate limited\"}"}
	var task:Dictionary=bundle.task
	var result:={"schema_version":"agent-result/1","request_id":str(task.request_id),"agent_role":str(task.agent_role),
		"status":"completed","summary":"完成严格合同内的地图分析。","deliverables":[],
		"evidence":["未生成代码、工具调用或资源路径。"],"warnings":[]}
	if task.agent_role=="world":
		result.deliverables=[{"deliverable_id":"deliverable.transport.world-analysis","kind":"analysis",
			"target_type":"quest","target_id":"courtyard_provisions","content":"边境庭院连接旧驿道、星潮观测点与安全返回路径。"}]
	if response_mode=="fenced_json":
		return {"transport_ok":true,"response_code":200,"body":JSON.stringify({"choices":[{"message":{"content":"```json\n"+JSON.stringify(result)+"\n```"}}]})}
	return {"transport_ok":true,"response_code":200,"body":JSON.stringify({"choices":[{"message":{"content":JSON.stringify(result)}}]})}

func _agent_result_for_task(request_id:String,role:String)->Dictionary:
	return {"schema_version":"agent-result/1","request_id":request_id,"agent_role":role,"status":"completed",
		"summary":"迟到结果。","deliverables":[],"evidence":[],"warnings":[]}

func wait_for_stage_jobs(bridge,run_id:String)->bool:
	for _frame in range(240):
		await process_frame
		var jobs:Array[Dictionary]=bridge.list_authoring_agent_jobs(run_id)
		if not jobs.is_empty() and jobs.all(func(job): return job.status in ["completed","rejected","failed","cancelled"]): return true
	return false

func wait_for_stage()->bool:
	for _frame in range(120):
		await process_frame
		if current_scene!=null and str(current_scene.scene_file_path)=="res://stage.tscn": return true
	return false

func find_button(parent:Node,text:String):
	for candidate in parent.find_children("*","Button",true,false):
		if candidate.text==text: return candidate
	return null

func has_text(parent:Node,needle:String)->bool:
	for candidate in parent.find_children("*","Label",true,false):
		if needle in str(candidate.text): return true
	return false

func finish()->void:
	for message in failures: push_error(message)
	print("AGENT_TRANSPORT_SERVICE_TEST %s · safe config, memory key, async stages, bounded retry, cancel, trusted review, UI" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
