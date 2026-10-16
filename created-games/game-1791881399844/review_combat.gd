extends SceneTree
func _initialize() -> void: call_deferred("run")
func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var g=load("res://main.tscn").instantiate()
	g.save_enabled=false; g.save_path="user://shooter-review-unused.json"
	root.add_child(g); current_scene=g; g.set_process(false)
	g.launch(); g.player=Vector2(320,440); g.hazards.clear(); g.stars.clear()
	var c=g.combat
	c.muted=true
	for k in 3: c.spawn(k,Vector2(700+k*65,280+k*130))
	for i in 100:
		g.hit_cd=10; g._process(.02)
	g.hit_cd=0; g.queue_redraw()
	await snap("res://shooter-preview.png")
	c.choice=true; g.queue_redraw()
	await snap("res://weapon-preview.png")
	c.choice=false; c.enemies.clear(); c.bullets.clear(); c.elapsed=150; c.choices_taken=3; c.rank=4
	g.hit_cd=10; c.step(.01); c.choice=false
	for i in 100:
		g.hit_cd=10; g._process(.02)
	g.hit_cd=0; g.queue_redraw()
	await snap("res://boss-preview.png")
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		c.enemies[0].hp=c.enemies[0].max*.45
		for i in 144:
			for j in 2:
				g.hit_cd=10; g._process(1.0/24.0)
			g.hit_cd=0; g.queue_redraw()
			await snap(output.path_join("%03d.png" % i))
	quit()
