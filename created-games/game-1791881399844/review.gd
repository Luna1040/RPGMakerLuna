extends SceneTree
func _initialize() -> void: call_deferred("run")
func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	game.save_enabled=false; game.save_path="user://starlight-review-no-save.json"
	root.add_child(game); current_scene=game
	await create_timer(.3).timeout
	await capture("res://cover.png")
	game.launch(); game.player=Vector2(500,460); game.trigger_scan()
	await create_timer(.3).timeout
	await capture("res://flight-preview.png")
	for region in [1,2]:
		game.bank_cargo(); game.gates=3; game.selected_sector=region; game.launch(); game.player=Vector2(440,500)
		await create_timer(.2).timeout
		await capture("res://region-%d-preview.png" % region)
	game.bank_cargo(); game.selected_sector=0; game.gates=3
	game.gate_open_index=2; game.gate_open_left=5
	game.set_process(false)
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		for i in 48:
			game._process(.125)
			await capture(output.path_join("%03d.png" % i))
	quit()
