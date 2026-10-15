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
	game.launch()
	game.player=Vector2(500,460)
	game.trigger_scan()
	await create_timer(.3).timeout
	await capture("res://flight-preview.png")
	quit()
