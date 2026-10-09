extends SceneTree

func _initialize() -> void:
	call_deferred("preview")

func preview() -> void:
	var lab: Node2D = load("res://main.tscn").instantiate()
	root.add_child(lab)
	lab.paused = true
	while lab.baking:
		await process_frame
	lab.set_process(false)
	var config := {"body":"female","outfit":"dress","hair":"copper","weapon":"none","effects":false,"view":55.0}
	if "--male" in OS.get_cmdline_user_args():
		config = {"body":"male","outfit":"swim","hair":"short","weapon":"none","effects":false,"view":90.0}
	elif "--base" in OS.get_cmdline_user_args():
		config = {"body":"female","outfit":"none","hair":"none","weapon":"none","effects":false,"view":55.0}
	lab.config = config
	lab.action = "idle"
	lab.frame = 0
	lab.make_live()
	lab.sync_menus()
	await lab.ensure_baked()
	lab._process(0)
