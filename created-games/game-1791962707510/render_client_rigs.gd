extends SceneTree
func _initialize() -> void:
 root.hide()
 call_deferred("run")
func run() -> void:
 var vp:=SubViewport.new()
 vp.size=Vector2i(320,400)
 vp.own_world_3d=true
 vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp)
 var env:=WorldEnvironment.new()
 var e:=Environment.new()
 e.background_mode=Environment.BG_COLOR
 e.background_color=Color("c1ced4")
 e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 e.ambient_light_color=Color.WHITE
 e.ambient_light_energy=0.6
 env.environment=e
 vp.add_child(env)
 var light:=DirectionalLight3D.new()
 light.rotation_degrees=Vector3(-40,-25,0)
 light.light_energy=0.8
 vp.add_child(light)
 var camera:=Camera3D.new()
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=2.7
 camera.position=Vector3(0.8,1.3,4)
 vp.add_child(camera)
 camera.look_at(Vector3(0,0.95,0))
 for role in ["class_blade","class_sword","class_spear","npc_0","npc_1","npc_2","npc_3","npc_4","npc_5"]:
  var model=load("res://client_actor_rig.gd").make(vp,"res://assets/3d/"+role+".tscn")
  model.root.set_process(true)
  for frame in range(6): await process_frame
  await RenderingServer.frame_post_draw
  vp.get_texture().get_image().save_png("res://art-jobs/client-actors-10/rig-"+role+".png")
  model.root.queue_free()
  await process_frame
 print("RIG_GALLERY_PASS")
 quit()
