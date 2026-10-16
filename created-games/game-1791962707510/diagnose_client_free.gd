extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var game=load("res://main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.hide()
 await process_frame
 for child in game.world.get_children():
  print("FREE_NODE ",child.name," ",child.get_class()," ",child.scene_file_path)
  child.free()
  await process_frame
 game.active_slot=0
 game.free()
 print("FREE_DIAG_DONE")
 quit()
