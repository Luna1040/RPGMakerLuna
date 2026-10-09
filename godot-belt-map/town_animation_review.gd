extends SceneTree
## Render the actual runtime NPC/fountain nodes as a repeatable visual review.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	stage.camera.enabled = false
	stage.hide()
	for child in stage.get_children():
		if child is CanvasLayer: child.hide()
	root.canvas_transform = Transform2D.IDENTITY
	RenderingServer.set_default_clear_color(Color("152331"))
	var showcase := Node2D.new()
	root.add_child(showcase)
	for i in stage.townsfolk.residents.size():
		var npc: Dictionary = stage.townsfolk.residents[i]
		npc.root.reparent(showcase)
		npc.root.position = Vector2(190+i*310,530)
	var fountain = stage.sorting.get_node("pool")
	fountain.reparent(showcase)
	fountain.position = Vector2(965,530)
	var water = fountain.get_child(1)
	water.set_process(false)
	var title := Label.new()
	title.text = "旅店主人 · 招手迎客       铁匠 · 擦拭检查锤具       喷泉 · 水流 / 水花 / 波纹"
	title.position = Vector2(80,125)
	title.add_theme_font_size_override("font_size",24)
	showcase.add_child(title)
	DirAccess.make_dir_recursive_absolute("res://captures/town-motion")
	for i in 52:
		stage.townsfolk.step(.125,Vector2.ZERO,0)
		water._process(.125)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/town-motion/%03d.png" % i)
	print("TOWN_REVIEW_CAPTURE PASS")
	quit()
