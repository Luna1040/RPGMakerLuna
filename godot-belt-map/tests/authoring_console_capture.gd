extends SceneTree
## Manual visual check for the trusted authoring console. Creates only an
## in-memory Run and a screenshot; it never publishes content or writes saves.

func _initialize()->void:
	call_deferred("run")

func run()->void:
	var bridge=root.get_node_or_null("WorkbenchBridge")
	if bridge==null:
		push_error("WorkbenchBridge unavailable")
		quit(1)
		return
	var request:={"schema_version":"authoring-run-request/1","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","theme":"星潮侵蚀下的边境庭院","tone":"mystery","scope":"chapter",
		"content_policy":"general","requested_systems":["world","map","town","npcs","main_quest","side_quests","affinity","items","equipment","shops"],
		"constraints":["保留现有苍石庭院角色资产白名单","所有任务必须具有可达的接取与交付路径"]}
	var created:Dictionary=bridge.create_authoring_run(request)
	if not created.get("ok",false):
		push_error("Could not create capture run: "+str(created.get("errors",[])))
		quit(1)
		return
	bridge.dispatch_authoring_tasks(str(created.run.run_id))
	var stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.runtime.persistence_enabled=false
	stage.runtime.autosave_armed=false
	stage.runtime.panel.open("authoring")
	await create_timer(.4).timeout
	stage.runtime.panel.scroll.scroll_vertical=455
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var path:="res://captures/authoring-console.png"
	var result:=root.get_texture().get_image().save_png(path)
	print("AUTHORING_CONSOLE_CAPTURE ",path," result=",result)
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(0 if result==OK else 1)
