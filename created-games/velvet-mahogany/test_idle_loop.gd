extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await create_timer(11.5).timeout
	if not game.motion.player.is_playing() or game.motion.action!="idle" or game.motion.player.stream_position>2.5:
		push_error("FAIL: idle loop did not wrap")
		quit(1)
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/idle-loop-wrap.png")
	print("PASS: idle loop wraps and keeps playing")
	quit()
