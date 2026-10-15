extends SceneTree
func _initialize() -> void:
	root.hide()
	call_deferred("run")
func capture(viewport: SubViewport, name: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png("res://art-jobs/wilderness-06/"+name+".png")==OK)
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,800)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game=load("res://wilderness_3d.tscn").instantiate()
	game.saves.directory="res://art-jobs/wilderness-06/render-saves-%d" % Time.get_ticks_usec()
	viewport.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.name_input.text="江湖侠客"
	game.select_slot(1)
	game.zoom=20
	game.yaw=0.55
	game.update_camera(1,true)
	game.queue_redraw()
	await capture(viewport,"town-three-gates")
	for gate_data in [["gate-west",Vector3(-14,0.05,3),PI/2],["gate-east",Vector3(14,0.05,0),-PI/2],["gate-south",Vector3(0,0.05,11),PI]]:
		game.hero.position=gate_data[1]
		game.yaw=gate_data[2]
		game.zoom=10
		game.pitch=deg_to_rad(28)
		game.update_camera(1,true)
		game.queue_redraw()
		await capture(viewport,gate_data[0])
	game.hero.position=Vector3(0,0.05,3.5)
	game.yaw=PI
	game.zoom=6
	game.pitch=deg_to_rad(28)
	game.update_camera(1,true)
	game.queue_redraw()
	await capture(viewport,"refined-hero-front")
	game.yaw=PI/2
	game.update_camera(1,true)
	game.queue_redraw()
	await capture(viewport,"refined-hero-side")
	game.yaw=0
	game.update_camera(1,true)
	game.queue_redraw()
	await capture(viewport,"refined-hero-back")
	for i in range(6):
		var mob: Dictionary=game.monsters[i]
		game.hero.position=mob.home+Vector3(2,0.05,3)
		game.region=["西郊 · 青草坡","西郊 · 青草坡","西郊 · 青草坡","东郊 · 野牛林","东郊 · 野牛林","南郊 · 灰狼谷"][i]
		game.yaw=0.7
		game.zoom=8
		game.pitch=deg_to_rad(38)
		game.update_camera(1,true)
		game.queue_redraw()
		await capture(viewport,"monster-%d" % i)
	game.hero.position=Vector3(-20,0.05,4)
	game.region="西郊 · 青草坡"
	game.yaw=PI
	game.zoom=6
	game.update_camera(1,true)
	game.hp=50
	game.toggle_meditation()
	game._process(0.01)
	game.queue_redraw()
	await capture(viewport,"meditation")
	game.meditating=false
	game.level=10
	game.hp=game.max_hp()
	game.begin_leap()
	game._process(0.2)
	game.queue_redraw()
	await capture(viewport,"lightness-lv10")
	game.active_slot=0
	game.queue_free()
	print("PASS: 15 isolated offscreen 3D screenshots; no playable game launch/restart")
	quit(0)
