extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var demo: Node2D = load("res://main.tscn").instantiate()
	root.add_child(demo)
	var data: Dictionary = demo.manifest
	assert(data.animations.walk.frames.size() == 4)
	assert(data.animations.slash.frames.size() == 6)
	var dimensions := {}
	for action in data.animations.values():
		for record in action.frames:
			for layer in record.layers.values():
				var image := Image.load_from_file(layer.path)
				assert(image.get_size() == Vector2i(int(layer.size[0]),int(layer.size[1])))
				assert(image.get_used_rect() == Rect2i(Vector2i.ZERO,image.get_size()))
				var o := Vector2i(int(layer.offset[0]),int(layer.offset[1]))
				assert(o.x > -80 and o.x + image.get_width() < 112)
				assert(o.y > -104 and o.y + image.get_height() < 24)
			dimensions[str(record.layers.body.size)] = true
	assert(dimensions.size() >= 3) # Real variable frame widths, no square-cell assumption.
	var walk: Array = data.animations.walk.frames
	var first := Image.load_from_file(walk[0].layers.body.path)
	var opposite := Image.load_from_file(walk[2].layers.body.path)
	assert(first.get_data() != opposite.get_data())
	assert(first.get_size().y == opposite.get_size().y)
	# Both grounded contact frames terminate on the shared floor y=0.
	assert(int(walk[0].layers.body.offset[1])+first.get_height() == 0)
	assert(int(walk[2].layers.body.offset[1])+opposite.get_height() == 0)
	var hero = demo.hero
	var origin: Vector2 = hero.position
	Input.action_press("ui_right")
	demo._physics_process(0.1)
	Input.action_release("ui_right")
	assert(hero.position.x > origin.x and hero.animation == "walk")
	demo.start_attack()
	var locked: Vector2 = hero.position
	Input.action_press("ui_right")
	demo._physics_process(0.01)
	Input.action_release("ui_right")
	assert(hero.position == locked)
	var action_before: String = hero.animation
	var frame_before: int = hero.frame
	# Equipment replacement must preserve action state and anchors.
	for slot in ["outfit","boots","weapon","hair"]:
		demo.selectors[slot].select(1)
		demo.selectors[slot].item_selected.emit(1)
	assert(hero.animation == action_before and hero.frame == frame_before)
	assert(hero.active_layers().has("torso_scout"))
	assert(hero.hair == "copper" and demo.slash_actor.boots == "scout")
	var blade: Dictionary = data.weapons.gold
	var size := Image.load_from_file(blade.path).get_size()
	var reached := {}
	for i in range(90):
		if hero.animation == "slash":
			reached[hero.frame] = true
			assert(Image.load_from_file(data.weapons[hero.weapon].path).get_size() == size)
			assert(hero.scale == Vector2(3,3))
		hero.tick(0.01)
	assert(reached.size() == 6)
	assert(hero.animation == "idle")
	assert(demo.swing_count == 1) # Frame event fires once, not once per physics tick.
	hero.play("slash",true)
	hero.paused = true
	hero.tick(1.0)
	assert(hero.frame == 0)
	hero.paused = false
	hero.facing = -1
	hero.tick(0.1)
	assert(hero.current_record().attachments.hand == data.animations.slash.frames[0].attachments.hand)
	if "--preview" in OS.get_cmdline_user_args():
		demo.paused = true
		for actor in demo.actors:
			actor.paused = true
			actor.frame = 2 if actor.animation != "idle" else 0
			actor.debug_bounds = true
			actor.queue_redraw()
		demo.slash_actor.play("slash",true)
		demo.slash_actor.frame = 2
		hero.play("slash",true)
		hero.frame = 3
		return
	print("WARDROBE_TEST_PASS: cropped layers, shared floor, opposite strides, action-preserving equipment, fixed weapon size, attack lock and one-shot events")
	demo.queue_free()
	await process_frame
	quit()
