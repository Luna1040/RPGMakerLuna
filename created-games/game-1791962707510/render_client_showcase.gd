extends SceneTree
func _initialize() -> void:
 root.hide()
 call_deferred("run")
func run() -> void:
 var viewport:=SubViewport.new()
 viewport.size=Vector2i(1440,900)
 viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(viewport)
 var game=load("res://main.tscn").instantiate()
 game.saves.directory="res://art-jobs/client-xuanbo-09/showcase-saves-%d" % Time.get_ticks_usec()
 viewport.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.set_process_input(false)
 game.set_process_unhandled_input(false)
 game.visible=false
 game.active_slot=0
 var camera: Camera3D=game.camera
 for spec in [["client-overview",Vector3(38,37,38),Vector3(0,0,-6)],["client-hall",Vector3(13,10,-2),Vector3(0,3,-16)],["client-shops",Vector3(7,12,5),Vector3(20,2,-12)],["client-gate",Vector3(27,10,13),Vector3(35,2,0)]]:
  camera.position=spec[1]
  camera.look_at(spec[2])
  for i in range(8): await process_frame
  for control in viewport.find_children("*","CanvasItem",true,false): control.visible=false
  await process_frame
  await RenderingServer.frame_post_draw
  assert(viewport.get_texture().get_image().save_png("res://art-jobs/client-xuanbo-09/"+spec[0]+".png")==OK)
 print("CLIENT_SHOWCASE_PASS; scenery=",game.get_meta("client_scenery_count"))
 game.queue_free()
 quit()
