extends SceneTree
## Isolated, noninteractive screenshots; all demo records stay in the project QA directory.

func _initialize() -> void:
	root.hide()
	call_deferred("render_checks")

func capture(viewport: SubViewport, name: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png("res://art-jobs/chibi-05/%s.png" % name)==OK)

func render_checks() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,800)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	game.saves.directory="res://art-jobs/chibi-05/render-demo-%d" % Time.get_ticks_usec()
	viewport.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.name_input.text="刀客预览"
	game.select_slot(1)
	game.zoom=19
	for i in range(3):
		game.yaw=[0.0,1.25,PI][i]
		game.update_camera(1,true)
		game.queue_redraw()
		await capture(viewport,"scene-%d" % i)
	game.yaw=PI
	game.pitch=deg_to_rad(32)
	game.zoom=6
	game.update_camera(1,true)
	game.queue_redraw()
	await capture(viewport,"character-close")
	game.yaw=0
	game.pitch=deg_to_rad(48)
	game.zoom=19
	game.update_camera(1,true)
	game.open_menu(false)
	await capture(viewport,"roster")
	game.ask_delete(1)
	await capture(viewport,"delete-confirm")
	game.delete_dialog.get_cancel_button().pressed.emit()
	game.menu.hide()
	game.paused=false
	game.talk_master()
	await capture(viewport,"master-dialogue")
	game.dialogue.hide()
	game.talk_town_npc("金香玉")
	await capture(viewport,"inn-dialogue")
	game.dialogue.hide()
	game.character.profession="医生"
	game.apply_profession_model()
	game.yaw=PI
	game.pitch=deg_to_rad(32)
	game.zoom=6
	game.update_camera(1,true)
	game.queue_redraw()
	await capture(viewport,"doctor-close")
	game.active_slot=0
	game.queue_free()
	print("PASS: nine Q-style scene/UI screenshots, isolated demo saves, no playable game restart")
	quit(0)
