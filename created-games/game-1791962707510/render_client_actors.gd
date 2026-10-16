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
 camera.size=3
 camera.position=Vector3(0.8,1.7,4)
 camera.look_at(Vector3(0,1.1,0))
 vp.add_child(camera)
 var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client-actors/source-manifest.json"))
 for info in manifest:
  var node:=MeshInstance3D.new()
  node.mesh=load("res://assets/client-actors/"+info.name+".obj")
  for i in range(node.mesh.get_surface_count()):
   var material: StandardMaterial3D=node.mesh.surface_get_material(i).duplicate()
   material.cull_mode=BaseMaterial3D.CULL_DISABLED
   material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
   node.set_surface_override_material(i,material)
  vp.add_child(node)
  for frame in range(3): await process_frame
  await RenderingServer.frame_post_draw
  vp.get_texture().get_image().save_png("res://art-jobs/client-actors-10/"+info.name+".png")
  node.queue_free()
  await process_frame
 print("ACTOR_GALLERY_PASS: ",manifest.size())
 quit()
