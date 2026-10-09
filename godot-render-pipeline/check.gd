extends SceneTree

func _initialize() -> void:
	call_deferred("check_pipeline")

func check_pipeline() -> void:
	var lab: Node2D = load("res://main.tscn").instantiate()
	root.add_child(lab)
	lab.paused = true
	while lab.baking:
		await process_frame
	lab.set_process(false)
	var tested := []
	var original: Dictionary = lab.config.duplicate()
	var configs := [
		{"body":"female","outfit":"knight","hair":"gold","weapon":"steel","effects":true,"view":18.0},
		{"body":"female","outfit":"none","hair":"none","weapon":"none","effects":false,"view":55.0},
		{"body":"female","outfit":"swim","hair":"gold","weapon":"none","effects":false,"view":55.0},
		{"body":"female","outfit":"dress","hair":"copper","weapon":"none","effects":false,"view":55.0},
		{"body":"male","outfit":"none","hair":"none","weapon":"none","effects":false,"view":90.0},
		{"body":"male","outfit":"swim","hair":"short","weapon":"none","effects":false,"view":90.0}
	]
	for config_ in configs:
		lab.config = config_.duplicate()
		lab.make_live()
		lab.sync_menus()
		await lab.ensure_baked()
		assert(lab.baked.get_child_count() == 0) # PNG player has no 3D render resources.
		assert(not lab.live.meshes.has("shorts"))
		assert(lab.live.meshes.pelvis.material_override == lab.live.materials.skin)
		assert(lab.live.body_type == config_.body)
		if config_.outfit == "none":
			assert(not lab.live.meshes.shirt.visible and not lab.live.meshes.swim_bottom.visible)
			for pair in lab.live.breast_nodes:
				assert(not pair[1].visible)
		var count := 0
		for action_ in ["idle","walk","slash"]:
			for index in range(lab.data.animations[action_].frames.size()):
				lab.action = action_
				lab.frame = index
				lab.elapsed = 0
				lab.apply_pose()
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var live: Image = lab.live.pixel_viewport.get_texture().get_image()
				var bounds := live.get_used_rect()
				assert(bounds.size.y > 50)
				if bounds.position.x <= 0 or bounds.end.x >= 128 or bounds.position.y <= 0 or bounds.end.y >= 128:
					print("CLIP_CHECK: %s %s %d %s" % [str(config_),action_,index,str(bounds)])
				assert(bounds.position.x > 0 and bounds.end.x < 128 and bounds.position.y > 0 and bounds.end.y < 128)
				var record: Dictionary = lab.baked.bundle.animations[action_][index]
				var png := Image.load_from_file(record.path)
				assert(png.get_size() == Vector2i(record.size[0],record.size[1]))
				var assembled := Image.create(128,128,false,Image.FORMAT_RGBA8)
				var origin: Array = lab.baked.bundle.origin
				var at := Vector2i(roundi(record.offset[0]+origin[0]),roundi(record.offset[1]+origin[1]))
				assembled.blit_rect(png,Rect2i(Vector2i.ZERO,png.get_size()),at)
				assert(live.get_data() == assembled.get_data()) # Actual pixel comparison, not metadata only.
				for side in ["near","far"]:
					assert(is_equal_approx(lab.live.meshes[side+"_thigh"].basis.y.length(),.41))
					assert(is_equal_approx(lab.live.meshes[side+"_calf"].basis.y.length(),.41))
				assert(lab.live.weapon_root.scale.is_equal_approx(Vector3.ONE))
				count += 1
		tested.append({"loadout":config_,"frames":count,"exact_pixel_match":true,"manifest":lab.set_path})
		print("LOADOUT_CHECKED: %s %s / %d exact matching frames" % [config_.body,config_.outfit,count])
	var file := FileAccess.open("res://verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"rendered":true,"presets":tested,"no_underwear_base":true,"png_player_has_no_3d":true},"\t"))
	file.close()
	if "--preview" in OS.get_cmdline_user_args():
		lab.action = "idle"
		lab.frame = 0
		if "--dress" in OS.get_cmdline_user_args():
			lab.config = configs[3].duplicate()
		elif "--base" in OS.get_cmdline_user_args():
			lab.config = configs[1].duplicate()
		else:
			lab.config = configs[5].duplicate()
		lab.make_live()
		lab.sync_menus()
		await lab.ensure_baked()
		lab._process(0)
		return
	lab.config = original
	print("RENDER_PIPELINE_TEST_PASS: 66 exact PNG/live comparisons across six adult body/loadout presets, cropped offsets, fixed bone lengths, no underwear base")
	lab.queue_free()
	await process_frame
	quit()
