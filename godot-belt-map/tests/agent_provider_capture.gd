extends SceneTree
## Visual-only B-10 fixture. It never contacts the displayed provider.

func _initialize()->void:
	call_deferred("run")

func run()->void:
	var bridge=root.get_node_or_null("WorkbenchBridge")
	var transport=root.get_node_or_null("AgentTransportService")
	var scratch:="user://agent-provider-capture.cfg"
	transport.config_path=scratch
	transport.configure({"schema_version":"agent-transport-config/1","provider":"openai_compatible","profile_id":"openai",
		"endpoint":"https://api.openai.com/v1/chat/completions","model":"configured-json-model",
		"timeout_seconds":45,"max_retries":2,"max_concurrency":2},"capture-session-key")
	transport._last_preflight={"status":"passed","ok":true,"latency_msec":684,"http_status":200,
		"message":"预检通过：鉴权、模型与严格 JSON 响应可用","checked_at":int(Time.get_unix_time_from_system())}
	transport._metric_counts={"completed":12,"rejected":1,"failed":1,"cancelled":0,"retried":2}
	transport._latency_samples.clear()
	for sample in [510,540,601,620,684,710,755,802,910,1010,1180,1320]: transport._latency_samples.append(sample)
	bridge.create_authoring_run({"schema_version":"authoring-run-request/1","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","theme":"供应商验收后的星潮边境","tone":"mystery","scope":"chapter",
		"content_policy":"general","requested_systems":["world","map","town","npcs","side_quests"],
		"constraints":["所有任务必须具有可达的接取与交付路径"]})
	var stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.runtime.persistence_enabled=false
	stage.runtime.autosave_armed=false
	stage.runtime.panel.open("authoring")
	await create_timer(.4).timeout
	stage.runtime.panel.scroll.scroll_vertical=85
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var path:="res://captures/agent-provider-acceptance.png"
	var result:=root.get_texture().get_image().save_png(path)
	transport.clear_session_api_key()
	if FileAccess.file_exists(scratch): DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	print("AGENT_PROVIDER_CAPTURE ",path," result=",result)
	stage.queue_free()
	await process_frame
	quit(0 if result==OK else 1)
