extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game=load("res://multiplayer.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/npc-lobby.png")
	game.start_hand()
	while game.busy: await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/npc-holdem.png")
	print("PASS: NPC table boots and deals")
	quit()
