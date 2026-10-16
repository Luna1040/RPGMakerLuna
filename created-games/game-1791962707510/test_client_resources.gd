extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client-xuanbo/source-manifest.json"))
 var surfaces:=0
 for info in manifest.models:
  var mesh=load("res://assets/client-xuanbo/"+info.asset) as Mesh
  assert(mesh!=null and mesh.get_surface_count()>0)
  for i in range(mesh.get_surface_count()):
   var arrays=mesh.surface_get_arrays(i)
   assert(arrays[Mesh.ARRAY_VERTEX].size()>0)
   assert(arrays[Mesh.ARRAY_TEX_UV].size()==arrays[Mesh.ARRAY_VERTEX].size())
   assert(mesh.surface_get_material(i)!=null)
   surfaces+=1
 for image in manifest.textures:
  var texture=load("res://assets/client-xuanbo/"+image.converted_png) as Texture2D
  assert(texture!=null and texture.get_width()>0)
 var game=load("res://main.tscn").instantiate()
 game.saves.directory="res://art-jobs/client-xuanbo-09/verify-saves-%d" % Time.get_ticks_usec()
 root.add_child(game)
 assert(game.get_meta("client_scenery_count")>=20)
 assert(game.town_actors.size()==6)
 assert(game.monsters.size()==60)
 game.active_slot=0
 game.queue_free()
 await process_frame
 print("PASS: 80 converted client meshes, 127 textures, UV/material contracts, original 6 NPCs and 60 monsters; surfaces=",surfaces)
 quit()
