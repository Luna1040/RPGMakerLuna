extends SceneTree

func _initialize() -> void:
	call_deferred("check_animation")

func check_animation() -> void:
	var demo: Node2D = load("res://main.tscn").instantiate()
	root.add_child(demo)
	assert(demo.frames.get_frame_count("walk") == 8)
	assert(demo.frames.get_frame_count("slash") == 8)
	assert(demo.frames.get_animation_loop("walk"))
	assert(not demo.frames.get_animation_loop("slash"))
	var initial: Vector2 = demo.hero_position
	Input.action_press("ui_right")
	demo._physics_process(0.2)
	Input.action_release("ui_right")
	assert(demo.hero_position.x > initial.x)
	assert(demo.hero.animation == "walk")
	demo._physics_process(0.01)
	assert(demo.hero.animation == "idle")
	demo.start_attack()
	assert(demo.attacking and demo.hero.animation == "slash")
	var attack_frame: int = demo.hero.frame
	demo.start_attack()
	assert(demo.hero.frame == attack_frame)
	var reached_frames := {}
	for i in range(90):
		await process_frame
		if demo.hero.animation == "slash":
			reached_frames[demo.hero.frame] = true
	assert(reached_frames.size() >= 6)
	assert(not demo.attacking)
	assert(demo.hero.animation == "idle")
	print("KNIGHT_TEST_PASS: eight-frame walk/slash, movement, attack lock, animation completion")
	demo.queue_free()
	await process_frame
	quit()
