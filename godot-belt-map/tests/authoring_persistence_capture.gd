extends SceneTree
## Visual acceptance for B-09. Uses disposable user:// state/config paths.

func _initialize()->void:
	call_deferred("run")

func run()->void:
	var bridge=root.get_node_or_null("WorkbenchBridge")
	var transport=root.get_node_or_null("AgentTransportService")
	var persistence=root.get_node_or_null("AuthoringPersistenceService")
	var scratch_state:="user://authoring-persistence-capture.json"
	var scratch_config:="user://authoring-persistence-capture.cfg"
	persistence.enable_for_test(scratch_state)
	persistence.clear_persisted_state()
	transport.config_path=scratch_config
	transport.configure({"schema_version":"agent-transport-config/1","provider":"openai_compatible",
		"endpoint":"https://gateway.example/v1/chat/completions","model":"rpg-json-agent",
		"timeout_seconds":45,"max_retries":2,"max_concurrency":2},"capture-session-key")
	bridge.create_authoring_run({"schema_version":"authoring-run-request/1","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","theme":"可断点续作的星潮边境","tone":"mystery","scope":"chapter",
		"content_policy":"general","requested_systems":["world","map","town","npcs","side_quests","equipment","shops"],
		"constraints":["所有任务必须具有可达的接取与交付路径"]})
	persistence.flush_now()
	var stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.runtime.persistence_enabled=false
	stage.runtime.autosave_armed=false
	stage.runtime.panel.open("authoring")
	await create_timer(.4).timeout
	stage.runtime.panel.scroll.scroll_vertical=105
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var path:="res://captures/authoring-persistence.png"
	var result:=root.get_texture().get_image().save_png(path)
	transport.clear_session_api_key()
	persistence.persistence_enabled=false
	for target in [scratch_state,scratch_state+".bak",scratch_config]:
		if FileAccess.file_exists(target): DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	print("AUTHORING_PERSISTENCE_CAPTURE ",path," result=",result)
	stage.queue_free()
	await process_frame
	quit(0 if result==OK else 1)
