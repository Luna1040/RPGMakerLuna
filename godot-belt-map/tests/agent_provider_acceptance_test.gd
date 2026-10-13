extends SceneTree
## B-10: provider profiles, a real localhost HTTP request/response, strict
## preflight parsing, offline contract evaluation and safe observability.

var failures:Array[String]=[]
var server:=TCPServer.new()
var peer:StreamPeerTCP
var request_text:=""
var responded:=false
var scratch_config:=""

func _initialize()->void:
	call_deferred("run")

func check(condition:bool,message:String)->void:
	if not condition: failures.append(message)

func run()->void:
	var registry=root.get_node_or_null("ContentRegistry")
	var bridge=root.get_node_or_null("WorkbenchBridge")
	var transport=root.get_node_or_null("AgentTransportService")
	registry.load_base_content()
	transport.clear_state_for_restore()
	transport.clear_session_api_key()
	scratch_config="user://agent-provider-acceptance-"+str(Time.get_ticks_usec())+".cfg"
	transport.config_path=scratch_config
	var profiles:Array[Dictionary]=bridge.agent_provider_profiles()
	check(profiles.size()==3 and profiles.any(func(value): return value.profile_id=="openai" and value.endpoint_locked),"provider profiles are incomplete")
	var wrong_openai:=config_fixture("openai","https://example.com/v1/chat/completions")
	check(not transport.validate_config(wrong_openai).is_empty(),"OpenAI profile accepted a non-official endpoint")

	var port:=find_port()
	check(port>0,"could not open local HTTP acceptance server")
	if port<=0:
		finish()
		return
	var endpoint:="http://127.0.0.1:%d/v1/chat/completions" % port
	var configured:Dictionary=transport.configure(config_fixture("local",endpoint),"provider-acceptance-secret")
	check(configured.get("ok",false) and configured.capabilities.profile_id=="local","local provider profile was rejected")
	var started:Dictionary=bridge.start_agent_transport_preflight()
	check(started.get("ok",false) and started.get("started",false),"real HTTP preflight did not start")
	for _frame in range(360):
		serve_http_once()
		await process_frame
		if transport.preflight_status().get("status") in ["passed","failed"]: break
	var preflight:Dictionary=transport.preflight_status()
	check(responded and preflight.get("ok",false),"real localhost HTTP preflight did not pass: "+str(preflight))
	check("Authorization: Bearer provider-acceptance-secret" in request_text,"preflight did not authenticate the real HTTP request")
	check("Provider preflight" in request_text and "response_format" in request_text,"preflight did not send the strict JSON probe")
	check("provider-acceptance-secret" not in JSON.stringify(preflight),"preflight result leaked its credential")

	var created:Dictionary=bridge.create_authoring_run(request_fixture("供应商离线评测"))
	var run_id:=str(created.get("run",{}).get("run_id",""))
	var dispatched:Dictionary=bridge.dispatch_authoring_tasks(run_id)
	var task:Dictionary=dispatched.get("tasks",[])[0].task
	var valid:=agent_result(task,"world")
	var invalid:=valid.duplicate(true)
	invalid.agent_role="systems"
	var evaluation:Dictionary=bridge.evaluate_agent_transport_cases([
		{"name":"valid-world-contract","task":task,"result":valid,"expected_ok":true},
		{"name":"role-escalation-rejected","task":task,"result":invalid,"expected_ok":false}])
	check(evaluation.get("ok",false) and evaluation.get("passed",0)==2,"offline provider evaluation did not distinguish valid and escalated results")

	transport.set_test_responder(func(bundle,_attempt):
		return {"transport_ok":true,"response_code":200,"body":JSON.stringify({"choices":[{"message":{"content":JSON.stringify(agent_result(bundle.task,str(bundle.agent_role)))}}]})})
	var automated:Dictionary=bridge.run_authoring_agent_stage(run_id)
	check(automated.get("ok",false),"metric fixture job did not start")
	check(await wait_for_jobs(bridge,run_id),"metric fixture job did not finish")
	var metrics:Dictionary=bridge.agent_transport_metrics()
	check(metrics.get("terminal_jobs",0)>=1 and metrics.get("counts",{}).get("completed",0)>=1,"completed job was not reflected in transport metrics")
	check(metrics.has("average_latency_msec") and metrics.has("p95_latency_msec") and metrics.has("success_rate"),"bounded latency/success metrics are incomplete")
	check("provider-acceptance-secret" not in JSON.stringify(metrics),"metrics leaked provider credentials")

	transport.clear_test_responder()
	transport.clear_session_api_key()
	server.stop()
	if FileAccess.file_exists(scratch_config): DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_config))
	finish()

func find_port()->int:
	for port in range(18731,18761):
		if server.listen(port,"127.0.0.1")==OK: return port
	return 0

func serve_http_once()->void:
	if peer==null and server.is_connection_available(): peer=server.take_connection()
	if peer==null or responded: return
	var available:=peer.get_available_bytes()
	if available>0: request_text+=peer.get_utf8_string(available)
	if "\r\n\r\n" not in request_text: return
	var probe:=JSON.stringify({"ok":true,"service":"rpg-agent"})
	var body:=JSON.stringify({"choices":[{"message":{"content":probe}}]})
	var response:="HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.to_utf8_buffer().size(),body]
	peer.put_data(response.to_utf8_buffer())
	responded=true

func config_fixture(profile_id:String,endpoint:String)->Dictionary:
	return {"schema_version":"agent-transport-config/1","provider":"openai_compatible","profile_id":profile_id,
		"endpoint":endpoint,"model":"acceptance-json-model","timeout_seconds":15,"max_retries":1,"max_concurrency":1}

func request_fixture(theme:String)->Dictionary:
	return {"schema_version":"authoring-run-request/1","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","theme":theme,"tone":"mystery","scope":"demo","content_policy":"general",
		"requested_systems":["world","map"],"constraints":["只生成可审查的世界与地图分析"]}

func agent_result(task:Dictionary,role:String)->Dictionary:
	return {"schema_version":"agent-result/1","request_id":str(task.request_id),"agent_role":role,"status":"completed",
		"summary":"供应商合同评测结果。","deliverables":[{"deliverable_id":"deliverable.provider.world","kind":"analysis",
		"target_type":"quest","target_id":"courtyard_provisions","content":"边境庭院与旧驿道保持可达闭环。"}],
		"evidence":["仅返回合同内 JSON。"],"warnings":[]}

func wait_for_jobs(bridge,run_id:String)->bool:
	for _frame in range(240):
		await process_frame
		var jobs:Array[Dictionary]=bridge.list_authoring_agent_jobs(run_id)
		if not jobs.is_empty() and jobs.all(func(job): return job.status in ["completed","rejected","failed","cancelled"]): return true
	return false

func finish()->void:
	for message in failures: push_error(message)
	print("AGENT_PROVIDER_ACCEPTANCE_TEST %s · profiles, real HTTP preflight, offline eval, bounded metrics" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
