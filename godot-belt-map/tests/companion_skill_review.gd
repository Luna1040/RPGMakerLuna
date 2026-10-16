extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	current_scene=stage
	stage.runtime.persistence_enabled=false
	stage.runtime.panel.close()
	await create_timer(1).timeout
	stage.set_physics_process(false)
	var service=stage.runtime.encounters
	service.set_companion_enabled(true)
	service.companion_foot=stage.foot+Vector2(1,0)
	service.companion_shield=38
	service.companion_shield_left=6
	service._update_companion_view()
	service.companion_effects.append_array([{"foot":stage.foot,"kind":"heal","life":0.9},{"foot":stage.foot+Vector2(3,0),"kind":"smite","life":0.9},{"foot":service.companion_foot,"kind":"label","text":"圣光裁决","life":1.1}])
	service.queue_redraw()
	await RenderingServer.frame_post_draw
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="): root.get_texture().get_image().save_png(arg.trim_prefix("--review-output="))
	quit()
