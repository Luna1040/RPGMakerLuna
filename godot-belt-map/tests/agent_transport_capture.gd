extends SceneTree
## Manual visual check for B-08 transport configuration and readiness. Uses a
## dummy session-only key and a temporary user:// config, then removes both.

func _initialize()->void:
	call_deferred("run")

func run()->void:
	var bridge=root.get_node_or_null("WorkbenchBridge")
	var transport=root.get_node_or_null("AgentTransportService")
	if bridge==null or transport==null:
		push_error("Agent transport services unavailable")
		quit(1)
		return
	var scratch:="user://agent-transport-capture.cfg"
	transport.config_path=scratch
	var configured:Dictionary=transport.configure({"schema_version":"agent-transport-config/1","provider":"openai_compatible",
		"endpoint":"https://gateway.example/v1/chat/completions","model":"rpg-json-agent",
		"timeout_seconds":45,"max_retries":2,"max_concurrency":2},"capture-session-key")
	if not configured.get("ok",false):
		push_error("Could not configure capture transport")
		quit(1)
		return
	bridge.create_authoring_run({"schema_version":"authoring-run-request/1","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","theme":"星潮侵蚀下的边境庭院","tone":"mystery","scope":"chapter",
		"content_policy":"general","requested_systems":["world","map","town","npcs","side_quests","equipment","shops"],
		"constraints":["所有任务必须具有可达的接取与交付路径"]})
	var stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.runtime.persistence_enabled=false
	stage.runtime.autosave_armed=false
	stage.runtime.panel.open("authoring")
	await create_timer(.4).timeout
	stage.runtime.panel.scroll.scroll_vertical=115
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var path:="res://captures/agent-transport.png"
	var result:=root.get_texture().get_image().save_png(path)
	transport.clear_session_api_key()
	if FileAccess.file_exists(scratch): DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	print("AGENT_TRANSPORT_CAPTURE ",path," result=",result)
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(0 if result==OK else 1)
