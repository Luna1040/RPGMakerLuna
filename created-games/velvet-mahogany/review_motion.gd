extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.reset_bank()
	game.start_round()
	for i in 14:
		await create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/deal-playback-%02d.png"%i)
	quit()
