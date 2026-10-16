extends SceneTree
func _initialize() -> void:
	root.hide()
	call_deferred("run")
func capture(viewport: SubViewport, filename: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png("res://art-jobs/city-08/"+filename+".png")==OK)
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,800)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game=load("res://city_3d.tscn").instantiate()
	game.saves.directory="res://art-jobs/city-08/render-saves-%d" % Time.get_ticks_usec()
	viewport.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.name_input.text="泫渤大城侠客"
	game.select_slot(1)
	game._process(0.001)
	game.zoom=48
	game.pitch=deg_to_rad(60)
	game.yaw=0.5
	game.update_camera(1,true)
	game.queue_redraw()
	await capture(viewport,"city-overview")
	game.hero.position=Vector3(0,0.05,-2.0)
	game.zoom=15
	game.yaw=0
	game.pitch=deg_to_rad(40)
	game.update_camera(1,true)
	game.queue_redraw()
	await capture(viewport,"temple-stairs")
	for index in range(6):
		var title: String=game.NPC_NAMES[index]
		var actor: Node3D=game.town_actors[title]
		game.hero.position=actor.position+Vector3(0,0.05,1.4)
		game.hero_model.root.hide()
		game.zoom=6
		game.pitch=deg_to_rad(28)
		game.yaw=0
		game.update_camera(1,true)
		game.queue_redraw()
		await capture(viewport,"npc-%d" % index)
	game.hero_model.root.show()
	for index in range(4):
		game.character.profession=["刀客","剑客","枪客","医生"][index]
		game.apply_profession_model()
		game.hero.position=Vector3(0,0.05,3.5)
		game.yaw=PI
		game.zoom=6
		game.update_camera(1,true)
		game.queue_redraw()
		await capture(viewport,"profession-%d-front" % index)
		game.yaw=PI/2
		game.update_camera(1,true)
		game.queue_redraw()
		await capture(viewport,"profession-%d-side" % index)
	for index in range(3):
		game.hero.position=[Vector3(-55,0.05,12),Vector3(63,0.05,36),Vector3(-8,0.05,70)][index]
		game.zoom=27
		game.yaw=0.7
		game.pitch=deg_to_rad(48)
		game._process(0.001)
		game.update_camera(1,true)
		game.queue_redraw()
		await capture(viewport,"field-%d" % index)
	game.active_slot=0
	game.queue_free()
	print("PASS: 19 isolated offscreen city/stair/NPC/profession/field screenshots; no interactive game launch")
	quit()
