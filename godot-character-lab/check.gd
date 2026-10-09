extends SceneTree

func _initialize() -> void:
	call_deferred("check_lab")

func check_lab() -> void:
	var lab: Node2D = load("res://main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process(false)
	lab.paused = true
	var actor = lab.model_actor
	var report := {"ai_floor_errors":{},"rendered":false,"fixed_bones":true,"fixed_weapon":true}
	for layer in ["skin","armor","hair"]:
		assert(lab.ai_actor.pixels[layer].get_format() == Image.FORMAT_RGBA8)
		assert(lab.ai_actor.pixels[layer].get_pixel(0,0).a == 0)
		assert(lab.ai_actor.measurements[layer].size() == 9)
		var errors := []
		for item in lab.ai_actor.measurements[layer]:
			errors.append(item.foot_error)
		if layer != "hair":
			report.ai_floor_errors[layer] = errors
	assert(lab.ai_actor.textures.sword.get_width() > 30)
	assert(lab.data.weapons.steel.scale == 1)
	var baseline: Vector2 = actor.camera.unproject_position(Vector3.ZERO)
	var weapon_mesh: Mesh = actor.meshes.blade.mesh
	for action_ in ["idle","walk","slash"]:
		for frame_ in range(lab.data.animations[action_].frames.size()):
			for blend in [0.0,.5,.99]:
				actor.set_pose(action_,frame_,blend)
				for side in ["near","far"]:
					assert(is_equal_approx(actor.meshes[side+"_thigh"].basis.y.length(),.41))
					assert(is_equal_approx(actor.meshes[side+"_calf"].basis.y.length(),.41))
				assert(is_equal_approx(actor.meshes.near_upper_arm.basis.y.length(),.36))
				assert(is_equal_approx(actor.meshes.near_forearm.basis.y.length(),.33))
				assert(actor.weapon_root.scale.is_equal_approx(Vector3.ONE))
				assert(actor.meshes.blade.mesh == weapon_mesh)
				assert(actor.camera.unproject_position(Vector3.ZERO).is_equal_approx(baseline))
	lab.play("slash")
	lab.frame = 2
	lab.apply_pose()
	var weapon_position: Vector3 = actor.weapon_root.position
	lab.cycle_outfit()
	lab.cycle_hair()
	assert(lab.frame == 2 and lab.action == "slash")
	assert(actor.weapon_root.position.is_equal_approx(weapon_position))
	assert(actor.outfit == "scout" and actor.hair == "copper")
	for actor_ in [lab.skin_actor,lab.ai_actor,actor]:
		actor_.facing = -1
	lab.apply_pose()
	assert(actor.display.scale.x == -1)
	lab.next_frame()
	assert(lab.paused and lab.frame == 3)
	if DisplayServer.get_name() != "headless":
		report.rendered = true
		actor.facing = 1
		actor.outfit = "knight"
		actor.hair = "gold"
		actor.camera_angle = 18.0
		actor.set_pose("walk",0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var first: Image = actor.viewport.get_texture().get_image()
		assert(first.get_pixel(0,0).a == 0)
		var bounds := first.get_used_rect()
		assert(bounds.size.x > 15 and bounds.size.y > 50)
		assert(bounds.position.x > 0 and bounds.end.x < 128 and bounds.position.y > 0 and bounds.end.y < 128)
		actor.set_pose("walk",1)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var second: Image = actor.viewport.get_texture().get_image()
		assert(first.get_data() != second.get_data())
		await lab.bake_frames()
		var baked: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://exports/baked/frames.json"))
		var count := 0
		for records in baked.animations.values():
			for record in records:
				var png := Image.load_from_file(record.path)
				assert(png.get_size() == Vector2i(record.size[0],record.size[1]))
				assert(png.get_used_rect() == Rect2i(Vector2i.ZERO,png.get_size()))
				count += 1
		assert(count == 11)
		report.baked_frames = count
	if "--preview" in OS.get_cmdline_user_args():
		lab.play("slash")
		lab.frame = 2
		lab.ai_actor.facing = 1
		lab.skin_actor.facing = 1
		actor.facing = 1
		lab.apply_pose()
		lab._process(0)
		return
	var file := FileAccess.open("res://verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("CHARACTER_LAB_TEST_PASS: real transparent AI overlays, fixed bone lengths, fixed weapon mesh, pose-preserving wardrobe, mirror and 3D PNG baking")
	lab.queue_free()
	await process_frame
	quit()
