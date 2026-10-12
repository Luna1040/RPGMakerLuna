extends SceneTree
## B-06: installed campaign library -> in-game confirmation -> bootstrap launch.

const SaveStore = preload("res://systems/core/save_store.gd")

var failures: Array[String] = []
var scratch_root := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func make_draft(registry) -> Dictionary:
	var dialogue: Dictionary = registry.get_dialogue("innkeeper")
	dialogue.choices.append({"id":"manager_archive_order", "label":"接受：战役管理档案", "action":"accept",
		"quest":"manager_archive", "when":{"quest":{"id":"manager_archive", "status":["available"]}}})
	var quest := {"id":"manager_archive", "title":"战役管理档案", "description":"验证战役管理界面启动独立会话。",
		"npc":"innkeeper", "position":[6, 5], "requires":{}, "objectives":[
			{"id":"manager_clue", "kind":"flag", "flag":"supply_hint", "target":1, "label":"取得管理线索"}],
		"rewards":{"xp":10, "reputation":{"innkeeper":1}}}
	return {"schema_version":"content-draft/1", "draft_id":"draft.test.campaign-manager",
		"project_id":"project.rpgmakerluna.courtyard", "base_catalog_hash":registry.catalog_hash,
		"base_content_revision":registry.revision, "author_role":"narrative", "summary":"战役管理界面测试。",
		"operations":[
			{"op":"upsert", "target_type":"quest", "target_id":"manager_archive", "definition":quest},
			{"op":"upsert", "target_type":"dialogue", "target_id":"innkeeper", "definition":dialogue}]}

func run() -> void:
	var registry=root.get_node_or_null("ContentRegistry")
	var draft_service=root.get_node_or_null("ContentDraftService")
	var import_service=root.get_node_or_null("CampaignImportService")
	var session_service=root.get_node_or_null("CampaignSessionService")
	var bridge=root.get_node_or_null("WorkbenchBridge")
	check(registry!=null and registry.loaded,"ContentRegistry unavailable")
	check(draft_service!=null and import_service!=null and session_service!=null and bridge!=null,"campaign manager Autoloads unavailable")
	if registry==null or draft_service==null or import_service==null or session_service==null or bridge==null:
		finish()
		return
	registry.load_base_content()
	var original_publish_root:String=draft_service.publish_root
	var original_projects_root:String=import_service.projects_root
	scratch_root="user://campaign-manager-test-"+str(Time.get_ticks_usec())
	draft_service.publish_root=scratch_root
	import_service.projects_root=scratch_root
	draft_service.clear_previews()
	import_service.clear_previews()
	session_service.clear_launch_previews()

	var draft:=make_draft(registry)
	var draft_preview:Dictionary=draft_service.preview_draft(draft)
	var published:Dictionary=draft_service.publish_draft(draft,str(draft_preview.get("preview_token","")))
	check(published.get("ok",false),"manager test artifact could not be published")
	var request:={"schema_version":"campaign-import-request/1", "request_id":"request.test.campaign-manager",
		"project_id":"project.rpgmakerluna.courtyard", "draft_id":"draft.test.campaign-manager",
		"campaign_id":"campaign.test.manager", "display_name":"月痕试炼", "activation_policy":"new_campaign"}
	var import_preview:Dictionary=import_service.preview_import(request)
	var installed:Dictionary=import_service.install_campaign(request,str(import_preview.get("preview_token","")))
	check(installed.get("ok",false),"manager test campaign could not be installed: "+str(installed.get("errors",[])))

	var campaign_path:=str(installed.get("campaign_path",""))
	var save_namespace:=str(installed.get("save_namespace",""))
	if installed.get("ok",false):
		check(SaveStore.new(save_namespace).save_slot(2,{"marker":"campaign-manager"}),"campaign slot fixture could not be written")
	var broken_path:=scratch_root.path_join(str(request.project_id)).path_join("campaigns").path_join("campaign.test.broken")
	DirAccess.make_dir_recursive_absolute(broken_path)

	var invalid_query:Dictionary=bridge.list_campaigns("../outside")
	check(not invalid_query.get("ok",true) and invalid_query.get("campaigns",[]).is_empty(),"campaign library accepted a path-like project id")
	var library:Dictionary=bridge.list_campaigns(str(request.project_id))
	check(library.get("ok",false),"campaign library could not be listed")
	var official:=find_campaign(library.get("campaigns",[]),"campaign.official.courtyard")
	var custom:=find_campaign(library.get("campaigns",[]),str(request.campaign_id))
	var broken:=find_campaign(library.get("campaigns",[]),"campaign.test.broken")
	check(not official.is_empty() and official.get("available",false) and official.get("active",false),"official campaign library row is missing or inactive")
	check(not custom.is_empty() and custom.get("available",false),"installed custom campaign is missing from the library")
	check(custom.get("source_draft_id")==draft.draft_id,"campaign source draft was not exposed")
	var slot_two:=find_slot(custom.get("slots",[]),2)
	check(not slot_two.is_empty() and slot_two.get("exists",false) and slot_two.get("ok",false),"campaign save-slot summary was not isolated or readable")
	check(not broken.is_empty() and not broken.get("available",true) and not broken.get("errors",[]).is_empty(),"broken campaign package was not surfaced as unavailable")

	change_scene_to_file("res://stage.tscn")
	check(await wait_for_scene("res://stage.tscn"),"official stage did not open for campaign manager UI")
	var stage=current_scene
	var panel=stage.runtime.panel if stage!=null and stage.runtime!=null else null
	check(panel!=null,"campaign manager panel is unavailable")
	if panel!=null:
		panel.open("campaigns")
		check(panel.heading.text=="战役管理","campaign manager tab did not render")
		var preview_button=find_button(panel.body,"预览并开始 · 月痕试炼")
		check(preview_button!=null,"custom campaign launch button is missing")
		if preview_button!=null:
			preview_button.pressed.emit()
			await process_frame
			check(registry.is_official_context(),"campaign UI preview hot-switched the active registry")
			check(panel.campaign_launch_preview.get("campaign_id")==request.campaign_id,"campaign UI did not retain the reviewed launch preview")
			var confirm_button=find_button(panel.body,"确认结束当前会话并启动")
			check(confirm_button!=null,"campaign UI confirmation action is missing")
			if confirm_button!=null:
				confirm_button.pressed.emit()
				check(await wait_for_scene("res://stage.tscn",stage),"campaign manager did not traverse bootstrap into a new stage")
				check(registry.content_context().get("campaign_id")==request.campaign_id,"campaign manager launched the wrong content context")
				check(current_scene.runtime.saves.directory==save_namespace,"campaign manager stage used the wrong SaveStore")

	var custom_stage=current_scene
	var official_start:Dictionary=session_service.start_official_session()
	check(official_start.get("ok",false),"official cleanup session was not scheduled")
	check(await wait_for_scene("res://stage.tscn",custom_stage),"official cleanup stage did not open")
	check(registry.is_official_context(),"campaign manager test did not restore official content")

	cleanup(campaign_path,str(published.get("artifact_path","")),broken_path,str(request.project_id))
	draft_service.publish_root=original_publish_root
	import_service.projects_root=original_projects_root
	draft_service.clear_previews()
	import_service.clear_previews()
	session_service.clear_launch_previews()
	finish()

func find_campaign(campaigns:Array,campaign_id:String)->Dictionary:
	for campaign in campaigns:
		if campaign is Dictionary and campaign.get("campaign_id")==campaign_id:
			return campaign
	return {}

func find_slot(slots:Array,slot_id:int)->Dictionary:
	for slot in slots:
		if slot is Dictionary and int(slot.get("slot",0))==slot_id:
			return slot
	return {}

func find_button(parent:Node,text:String):
	for candidate in parent.find_children("*","Button",true,false):
		if candidate.text==text:
			return candidate
	return null

func wait_for_scene(path:String,previous=null)->bool:
	for _frame in range(120):
		await process_frame
		if current_scene!=null and current_scene!=previous and str(current_scene.scene_file_path)==path:
			return true
	return false

func cleanup(campaign_path:String,artifact_path:String,broken_path:String,project_id:String)->void:
	for suffix in ["",".bak",".tmp",".bak.tmp"]:
		var save_path:String=campaign_path.path_join("saves").path_join("slot_2.json")+suffix
		if FileAccess.file_exists(save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	for path in [campaign_path.path_join("saves"),campaign_path.path_join("manifest.json"),campaign_path.path_join("content.json"),artifact_path]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var project_path:=scratch_root.path_join(project_id)
	for path in [campaign_path,broken_path,project_path.path_join("campaigns"),project_path.path_join("published"),project_path,scratch_root]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish()->void:
	for message in failures: push_error(message)
	print("CAMPAIGN_MANAGER_UI_TEST %s · library, invalid-package guard, slot summary, confirmation, bootstrap launch" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
