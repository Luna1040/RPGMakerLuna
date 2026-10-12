extends SceneTree
## B-07: trusted Main Agent orchestration, strict child contracts, Validator gate,
## merged preview/publish isolation, and the in-game authoring console.

var failures:Array[String]=[]
var scratch_root:=""

func _initialize()->void:
	call_deferred("run")

func check(condition:bool,message:String)->void:
	if not condition: failures.append(message)

func run()->void:
	var registry=root.get_node_or_null("ContentRegistry")
	var drafts=root.get_node_or_null("ContentDraftService")
	var bridge=root.get_node_or_null("WorkbenchBridge")
	var orchestrator=root.get_node_or_null("AuthoringOrchestrator")
	check(registry!=null and registry.loaded,"ContentRegistry unavailable")
	check(drafts!=null and bridge!=null and orchestrator!=null,"authoring orchestration Autoloads unavailable")
	if registry==null or drafts==null or bridge==null or orchestrator==null:
		finish()
		return
	registry.load_base_content()
	var original_publish_root:String=drafts.publish_root
	scratch_root="user://authoring-orchestrator-test-"+str(Time.get_ticks_usec())
	drafts.publish_root=scratch_root
	drafts.clear_previews()

	var missing_boundaries:=request_fixture()
	missing_boundaries.content_policy="mature_consensual"
	missing_boundaries.constraints=[]
	var rejected:Dictionary=bridge.create_authoring_run(missing_boundaries)
	check(not rejected.get("ok",true) and rejected.get("errors",[]).size()==3,"mature policy was accepted without all three consent/age boundaries")
	var analysis_request:=request_fixture()
	analysis_request.theme="只规划边境世界与地图关系"
	analysis_request.requested_systems=["world","map"]
	var analysis_created:Dictionary=bridge.create_authoring_run(analysis_request)
	check(analysis_created.get("ok",false),"analysis-only Run was not created")
	if analysis_created.get("ok",false):
		var analysis_run_id:String=str(analysis_created.run.run_id)
		var analysis_dispatch:Dictionary=bridge.dispatch_authoring_tasks(analysis_run_id)
		check(analysis_dispatch.get("tasks",[]).size()==1 and analysis_dispatch.tasks[0].agent_role=="world","analysis-only Run dispatched an unexpected role")
		if not analysis_dispatch.get("tasks",[]).is_empty():
			var world_result:=base_result(analysis_dispatch.tasks[0].task)
			world_result.deliverables=[{"deliverable_id":"deliverable.test.world-analysis","kind":"analysis","target_type":"quest","target_id":"courtyard_provisions","content":"初始城镇位于星潮边界，旧驿道连接三处调查节点。"}]
			var analysis_primary:Dictionary=bridge.submit_authoring_result(analysis_run_id,world_result)
			check(analysis_primary.get("validator_ready",false),"analysis-only Run did not reach Validator gate")
			var analysis_validator:Dictionary=bridge.dispatch_authoring_tasks(analysis_run_id)
			if not analysis_validator.get("tasks",[]).is_empty():
				var analysis_finished:Dictionary=bridge.submit_authoring_result(analysis_run_id,base_result(analysis_validator.tasks[0].task))
				check(analysis_finished.get("ok",false) and analysis_finished.run.status=="completed_analysis","validated analysis-only Run incorrectly required a content draft")
				check(analysis_finished.run.analysis_report.size()==1,"analysis-only Run did not retain its reviewed report")

	var created:Dictionary=bridge.create_authoring_run(request_fixture())
	check(created.get("ok",false),"Main Agent run was not created: "+str(created.get("errors",[])))
	if not created.get("ok",false):
		drafts.publish_root=original_publish_root
		finish()
		return
	var run_id:String=str(created.run.run_id)
	check(created.run.tasks.size()==5,"Main Agent did not split World/Narrative/NPC/Systems/Validator")
	var dispatched:Dictionary=bridge.dispatch_authoring_tasks(run_id)
	check(dispatched.get("ok",false) and dispatched.tasks.size()==4,"primary child tasks were not dispatched together")
	check(not _roles(dispatched.tasks).has("validator"),"Validator was dispatched before its dependencies completed")

	var task_by_role:Dictionary={}
	for bundle in dispatched.get("tasks",[]): task_by_role[str(bundle.agent_role)]=bundle.task
	var forged:=base_result(task_by_role.world)
	forged.agent_role="systems"
	var forged_review:Dictionary=bridge.submit_authoring_result(run_id,forged)
	check(not forged_review.get("ok",true) and forged_review.run.status=="needs_revision","mismatched child role was not rejected into revision state")
	check(bridge.submit_authoring_result(run_id,base_result(task_by_role.world)).get("ok",false),"corrected World result was rejected")
	check(bridge.submit_authoring_result(run_id,narrative_result(task_by_role.narrative,registry)).get("ok",false),"Narrative draft was rejected")
	var npc_review:Dictionary=bridge.submit_authoring_result(run_id,npc_result(task_by_role.npc,registry))
	check(npc_review.get("ok",false),"NPC draft was rejected: "+str(npc_review.get("errors",[])))
	var primary_done:Dictionary=bridge.submit_authoring_result(run_id,base_result(task_by_role.systems))
	check(primary_done.get("ok",false) and primary_done.get("validator_ready",false),"Validator gate did not open after all primary tasks completed")

	var validator_dispatch:Dictionary=bridge.dispatch_authoring_tasks(run_id)
	check(validator_dispatch.get("ok",false) and validator_dispatch.tasks.size()==1,"Validator was not dispatched alone")
	if not validator_dispatch.get("tasks",[]).is_empty():
		var validator_bundle:Dictionary=validator_dispatch.tasks[0]
		check(validator_bundle.agent_role=="validator" and validator_bundle.prior_results.size()==4,"Validator did not receive all reviewed upstream results")
		var validator_result:=base_result(validator_bundle.task)
		validator_result.summary="Schema、引用、权限、冲突与内容边界均通过。"
		validator_result.evidence=["4 个上游结果均由 WorkbenchBridge 复核。"]
		var validated:Dictionary=bridge.submit_authoring_result(run_id,validator_result)
		check(validated.get("ok",false) and validated.run.status=="ready_for_preview","Validator did not unlock Main Agent composition: "+str(validated.get("errors",[])))
		check(validated.run.draft.get("operations",[]).size()==4,"Main Agent did not merge four authorized content operations")
		check(validated.run.get("actionable_patches",[]).is_empty(),"empty Systems result created an executable patch")

	var live_quest_id:String=_allowed_id(task_by_role.narrative,"quest")
	var live_npc_id:String=_allowed_id(task_by_role.npc,"npc")
	check(not registry.target_exists("quest",live_quest_id) and not registry.target_exists("npc",live_npc_id),"Agent validation mutated live content")
	var preview:Dictionary=bridge.preview_authoring_run(run_id)
	check(preview.get("ok",false) and preview.preview.operation_count==4,"merged authoring preview was not produced")
	check(not registry.target_exists("quest",live_quest_id),"authoring preview hot-mutated the active campaign")
	var token:String=str(preview.get("preview",{}).get("preview_token",""))
	var wrong_publish:Dictionary=bridge.publish_authoring_run(run_id,"wrong-token")
	check(not wrong_publish.get("ok",true),"authoring publish accepted an unreviewed token")
	var published:Dictionary=bridge.publish_authoring_run(run_id,token)
	check(published.get("ok",false),"reviewed authoring run was not published: "+str(published.get("errors",[])))
	var artifact_path:String=str(published.get("publication",{}).get("artifact_path",""))
	check(FileAccess.file_exists(artifact_path),"published Main Agent artifact is missing")
	check(not registry.target_exists("npc",live_npc_id),"publication hot-activated generated content")

	change_scene_to_file("res://stage.tscn")
	check(await wait_for_stage(),"stage did not open for authoring console check")
	var panel=current_scene.runtime.panel if current_scene!=null and current_scene.runtime!=null else null
	check(panel!=null,"authoring console panel is unavailable")
	if panel!=null:
		panel.open("authoring")
		await process_frame
		check(panel.heading.text=="通用动态 RPG 世界引擎 Prompt","authoring console title is incorrect")
		check(find_button(panel.body,"生成 Main Agent 计划")!=null,"authoring console form action is missing")
		check(has_text(panel.body,"Main Agent → World / Narrative / NPC / Systems → Validator"),"authoring console does not expose the Agent topology")
		check(has_text(panel.body,"已发布不可变内容产物"),"authoring console does not surface the published run state")

	cleanup(artifact_path)
	drafts.publish_root=original_publish_root
	drafts.clear_previews()
	finish()

func request_fixture()->Dictionary:
	return {"schema_version":"authoring-run-request/1","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","theme":"被星潮侵蚀的边境庭院","tone":"mystery","scope":"chapter",
		"content_policy":"general","requested_systems":["world","map","town","npcs","side_quests","affinity","equipment","shops"],
		"constraints":["保持当前苍石庭院美术资产白名单"]}

func base_result(task:Dictionary)->Dictionary:
	return {"schema_version":"agent-result/1","request_id":str(task.request_id),"agent_role":str(task.agent_role),
		"status":"completed","summary":"完成授权范围内的工作。","deliverables":[],"evidence":["严格使用任务上下文。"],"warnings":[]}

func narrative_result(task:Dictionary,registry)->Dictionary:
	var quest_id:String=_allowed_id(task,"quest")
	var dialogue:Dictionary=registry.get_dialogue("innkeeper")
	dialogue.choices.append({"id":"accept_"+quest_id,"label":"接受：星潮来信","action":"accept","quest":quest_id,
		"when":{"quest":{"id":quest_id,"status":["available"]}}})
	var quest:={"id":quest_id,"title":"星潮来信","description":"调查庭院边界新出现的星潮印记。","npc":"innkeeper","position":[5,4],"requires":{},
		"objectives":[{"id":"star_mark","kind":"flag","flag":"supply_hint","target":1,"label":"向艾琳核对旧账簿"}],
		"rewards":{"xp":18,"reputation":{"innkeeper":1}}}
	var draft:={"schema_version":"content-draft/1","draft_id":"draft.test.authoring-narrative","project_id":str(task.project_id),
		"base_catalog_hash":registry.catalog_hash,"base_content_revision":registry.revision,"author_role":"narrative","summary":"新增星潮支线与接取入口。",
		"operations":[{"op":"upsert","target_type":"quest","target_id":quest_id,"definition":quest},
			{"op":"upsert","target_type":"dialogue","target_id":"innkeeper","definition":dialogue}]}
	var result:=base_result(task)
	result.summary="任务与对话闭环完成。"
	result.deliverables=[{"deliverable_id":"deliverable.test.authoring-narrative","kind":"content_draft","payload":draft}]
	return result

func npc_result(task:Dictionary,registry)->Dictionary:
	var npc_id:String=_allowed_id(task,"npc")
	var npc:Dictionary=registry.get_npc("innkeeper")
	npc.id=npc_id
	npc.display_name="星潮测绘师 · 洛弥"
	npc.position_m=[10.5,5.0]
	npc.ambient_lines=["星潮每晚都在改变边界，我需要一位敢走出灯火的人。"]
	var dialogue:Dictionary=registry.get_dialogue("innkeeper")
	dialogue.name="洛弥 · 星潮测绘师"
	dialogue.greeting="地图上没有永恒的道路，但每条路都留下代价。"
	dialogue.variants=[]
	dialogue.choices=[{"id":"lomi_journal","label":"查看当前线索","action":"journal"}]
	var draft:={"schema_version":"content-draft/1","draft_id":"draft.test.authoring-npc","project_id":str(task.project_id),
		"base_catalog_hash":registry.catalog_hash,"base_content_revision":registry.revision,"author_role":"npc","summary":"新增测绘师 NPC 与基础对话。",
		"operations":[{"op":"upsert","target_type":"npc","target_id":npc_id,"definition":npc},
			{"op":"upsert","target_type":"dialogue","target_id":npc_id,"definition":dialogue}]}
	var result:=base_result(task)
	result.summary="NPC 建模数据与对话完成。"
	result.deliverables=[{"deliverable_id":"deliverable.test.authoring-npc","kind":"content_draft","payload":draft}]
	return result

func _allowed_id(task:Dictionary,target_type:String)->String:
	for ref in task.get("allowed_targets",[]):
		if ref is Dictionary and ref.get("target_type")==target_type: return str(ref.target_id)
	return ""

func _roles(bundles:Array)->Array[String]:
	var result:Array[String]=[]
	for bundle in bundles: result.append(str(bundle.agent_role))
	return result

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

func cleanup(artifact_path:String)->void:
	if not artifact_path.is_empty() and FileAccess.file_exists(artifact_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(artifact_path))
	var published_dir:=scratch_root.path_join("project.rpgmakerluna.courtyard").path_join("published")
	for path in [published_dir,published_dir.get_base_dir(),scratch_root]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish()->void:
	for message in failures: push_error(message)
	print("AUTHORING_ORCHESTRATOR_TEST %s · trusted planning, child contracts, Validator gate, preview isolation, console UI" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
