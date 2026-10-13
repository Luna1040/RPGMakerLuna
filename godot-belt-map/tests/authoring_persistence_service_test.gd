extends SceneTree
## B-09: atomic authoring checkpoints, backup recovery, secret exclusion and
## trusted rehydration of interrupted Agent jobs.

var failures:Array[String]=[]
var scratch_state:=""
var scratch_config:=""

func _initialize()->void:
	call_deferred("run")

func check(condition:bool,message:String)->void:
	if not condition: failures.append(message)

func run()->void:
	var registry=root.get_node_or_null("ContentRegistry")
	var bridge=root.get_node_or_null("WorkbenchBridge")
	var orchestrator=root.get_node_or_null("AuthoringOrchestrator")
	var transport=root.get_node_or_null("AgentTransportService")
	var persistence=root.get_node_or_null("AuthoringPersistenceService")
	check(registry!=null and bridge!=null and orchestrator!=null and transport!=null and persistence!=null,"B-09 Autoloads unavailable")
	if persistence==null:
		finish()
		return
	registry.load_base_content()
	scratch_state="user://authoring-state-test-"+str(Time.get_ticks_usec())+".json"
	scratch_config="user://authoring-state-transport-test-"+str(Time.get_ticks_usec())+".cfg"
	persistence.enable_for_test(scratch_state)
	persistence.clear_persisted_state()
	orchestrator.clear_state_for_restore()
	transport.clear_state_for_restore()
	transport.config_path=scratch_config
	var configured:Dictionary=transport.configure({"schema_version":"agent-transport-config/1","provider":"openai_compatible",
		"endpoint":"http://127.0.0.1:9999/v1/chat/completions","model":"checkpoint-model",
		"timeout_seconds":15,"max_retries":2,"max_concurrency":1},"session-super-secret-key")
	check(configured.get("ok",false),"persistence test transport config failed")
	transport.set_test_responder(func(bundle,attempt): return provider_response(bundle,attempt))

	var created:Dictionary=bridge.create_authoring_run({"schema_version":"authoring-run-request/1",
		"project_id":"project.rpgmakerluna.courtyard","genre":"western_fantasy","theme":"重启后继续的边境地图",
		"tone":"mystery","scope":"demo","content_policy":"general","requested_systems":["world","map"],
		"constraints":["只生成可审查的世界与地图分析"]})
	var run_id:=str(created.get("run",{}).get("run_id",""))
	check(created.get("ok",false) and not run_id.is_empty(),"checkpoint Run was not created")
	var started:Dictionary=bridge.run_authoring_agent_stage(run_id)
	check(started.get("ok",false) and started.get("jobs",[]).size()==1,"interrupted Agent job was not created")
	var first_save:Dictionary=persistence.flush_now()
	var second_save:Dictionary=persistence.flush_now()
	check(first_save.get("ok",false) and second_save.get("ok",false),"atomic checkpoint writes failed")
	check(FileAccess.file_exists(scratch_state) and FileAccess.file_exists(scratch_state+".bak"),"primary/backup checkpoint pair was not created")
	var persisted_text:=FileAccess.get_file_as_string(scratch_state)
	check("session-super-secret-key" not in persisted_text,"session API key leaked into checkpoint")
	check("Authorization" not in persisted_text and "Bearer " not in persisted_text,"Authorization header leaked into checkpoint")
	check("prompt" not in persisted_text.to_lower(),"Agent prompt leaked into checkpoint")
	check("preview_token" not in persisted_text,"ephemeral preview token leaked into checkpoint")

	transport.clear_session_api_key()
	transport.clear_test_responder()
	orchestrator.clear_state_for_restore()
	transport.clear_state_for_restore()
	var corrupt:=FileAccess.open(scratch_state,FileAccess.WRITE)
	corrupt.store_string("{\"format\":\"tampered\"}")
	corrupt.close()
	var restored:Dictionary=persistence.restore_now()
	check(restored.get("ok",false) and restored.get("recovered",false),"damaged primary did not recover from the valid backup")
	check(restored.get("restored_runs",0)==1 and restored.get("restored_jobs",0)==1,"interrupted Run/job counts were not restored")
	var resumed:Dictionary=bridge.get_authoring_run(run_id)
	check(resumed.get("status")=="awaiting_agents","restored Run was not returned to its safe waiting state")
	var jobs:Array[Dictionary]=bridge.list_authoring_agent_jobs(run_id)
	check(jobs.size()==1 and jobs[0].status=="queued","running job was not downgraded to a safe resumable queue")
	check(not jobs[0].has("bundle") and not jobs[0].has("prompt"),"restored public job exposed its regenerated private bundle")

	transport.set_test_responder(func(bundle,attempt): return provider_response(bundle,attempt))
	transport.set_session_api_key("new-session-secret-key")
	check(await wait_for_stage_jobs(bridge,run_id),"restored queued job did not continue after credentials were supplied")
	check(bridge.get_authoring_run(run_id).get("status")=="validator_ready","resumed result did not pass trusted review into the Validator gate")

	transport.clear_test_responder()
	transport.clear_session_api_key()
	persistence.clear_persisted_state()
	if FileAccess.file_exists(scratch_config): DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_config))
	finish()

func provider_response(bundle:Dictionary,_attempt:int)->Dictionary:
	var task:Dictionary=bundle.task
	var result:={"schema_version":"agent-result/1","request_id":str(task.request_id),"agent_role":str(task.agent_role),
		"status":"completed","summary":"完成重启恢复后的地图分析。","deliverables":[{"deliverable_id":"deliverable.persistence.world",
		"kind":"analysis","target_type":"quest","target_id":"courtyard_provisions","content":"恢复后仍保持边境庭院、旧驿道与安全返回路径。"}],
		"evidence":["任务由可信编排器重新生成并复核。"],"warnings":[]}
	return {"transport_ok":true,"response_code":200,"body":JSON.stringify({"choices":[{"message":{"content":JSON.stringify(result)}}]})}

func wait_for_stage_jobs(bridge,run_id:String)->bool:
	for _frame in range(240):
		await process_frame
		var jobs:Array[Dictionary]=bridge.list_authoring_agent_jobs(run_id)
		if not jobs.is_empty() and jobs.all(func(job): return job.status in ["completed","rejected","failed","cancelled"]): return true
	return false

func finish()->void:
	for message in failures: push_error(message)
	print("AUTHORING_PERSISTENCE_SERVICE_TEST %s · atomic checkpoint, backup recovery, secret exclusion, trusted resume" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
