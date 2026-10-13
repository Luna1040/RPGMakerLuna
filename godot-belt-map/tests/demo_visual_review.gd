extends SceneTree
var stage
func _initialize() -> void:
	call_deferred("run")
func settle() -> void:
	for i in 10: await process_frame
	while root.get_node("GameSession").busy: await process_frame
	stage=current_scene
	stage.runtime.persistence_enabled=false
	stage.set_physics_process(false)
func capture(name:String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures/demo-city")
	root.get_texture().get_image().save_png("res://captures/demo-city/"+name+".png")
func run() -> void:
	stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	current_scene=stage
	stage.runtime.persistence_enabled=false
	stage.runtime.travel("city")
	await settle()
	await create_timer(2.5).timeout
	stage.camera.position=Vector2(700,420)
	await capture("city-west")
	stage.camera.position=Vector2(2150,420)
	await capture("city-east")
	stage.runtime.open_npc(stage.townsfolk.residents[1])
	var dialogue=stage.runtime.panel.dialogue_view
	while not dialogue.at_choices: dialogue.advance()
	await capture("keyboard-dialogue")
	stage.runtime.panel.close()
	stage.runtime.use_portal(stage.runtime.portals.links[1])
	await settle()
	await create_timer(2.5).timeout
	stage.camera.position=Vector2(950,420)
	await capture("tower-room")
	print("DEMO_VISUAL PASS")
	quit()
