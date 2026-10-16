extends SceneTree
func _initialize() -> void:
 root.hide()
 call_deferred("render_gallery")
func render_gallery() -> void:
 var vp := SubViewport.new()
 vp.size=Vector2i(640,480)
 vp.own_world_3d=true
 vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp)
 var environment := WorldEnvironment.new()
 var settings:=Environment.new()
 settings.background_mode=Environment.BG_COLOR
 settings.background_color=Color("c4d4d7")
 settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 settings.ambient_light_color=Color.WHITE
 settings.ambient_light_energy=0.65
 environment.environment=settings
 vp.add_child(environment)
 var sun:=DirectionalLight3D.new()
 sun.rotation_degrees=Vector3(-50,-30,0)
 sun.light_energy=0.9
 vp.add_child(sun)
 var camera:=Camera3D.new()
 vp.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=12
 camera.position=Vector3(11,9,13)
 camera.look_at(Vector3(0,2,0))
 var folder := "res://assets/client-xuanbo/"
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(folder+"source-manifest.json"))
 for info in manifest.models:
  var mesh=load(folder+info.asset) as Mesh
  assert(mesh!=null,info.asset)
  var model:=MeshInstance3D.new()
  model.mesh=mesh
  var dimensions=info.dimensions_m
  var factor=8.0/maxf(dimensions[0],dimensions[2])
  model.scale=Vector3.ONE*factor
  vp.add_child(model)
  for frame in range(4): await process_frame
  await RenderingServer.frame_post_draw
  assert(vp.get_texture().get_image().save_png("res://assets/client-xuanbo/preview_%03d.png" % info.archetype)==OK)
  model.queue_free()
  await process_frame
 print("GALLERY_PASS")
 quit()
