extends SceneTree
func _initialize() -> void:
	call_deferred("review")
func review() -> void:
	var home=load("res://home.tscn").instantiate()
	root.add_child(home)
	current_scene=home
	await create_timer(2).timeout
	assert(home.cards.get_child_count()>0,"Existing game must appear")
	assert(home.selected_id=="")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../.game-assistant/home-review.png"))
	print("CREATOR_HOME PASS")
	quit()
