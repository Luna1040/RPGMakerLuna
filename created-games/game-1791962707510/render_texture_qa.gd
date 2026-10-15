extends SceneTree
## Noninteractive offscreen render of the exact scene. Does not load or write player saves.

func _initialize() -> void:
	root.hide()
	call_deferred("render_checks")

func render_checks() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	game.saves.directory="res://art-jobs/textures-04/qa-empty-save-namespace"
	viewport.add_child(game)
	game.menu.hide()
	game.paused=false
	game.active_slot=0
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.zoom=20
	game.pitch=deg_to_rad(48)
	game.hero.position=Vector3(0,0.05,3.5)
	var angles := [0.0,1.5,PI]
	for i in range(angles.size()):
		game.yaw=angles[i]
		game.camera_anchor=game.hero.position+Vector3(0,1.3,0)
		game.update_camera(1,true)
		game.queue_redraw()
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		assert(image != null and not image.is_empty())
		assert(image.save_png("res://art-jobs/textures-04/scene-%d.png" % i)==OK)
	# Close overhead ground view makes texture scale and repeat junctions inspectable.
	game.yaw=0
	game.pitch=deg_to_rad(68)
	game.zoom=6
	game.update_camera(1,true)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png("res://art-jobs/textures-04/ground-close.png")==OK)
	game.active_slot=0
	game.queue_free()
	print("PASS: four offscreen scene screenshots rendered without a playable session or player save access")
	quit(0)
