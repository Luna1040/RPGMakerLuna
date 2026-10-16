extends SceneTree
var game
func _initialize() -> void: call_deferred("run")
func run() -> void:
 game=load("res://main.tscn").instantiate()
 game.saves.directory="res://art-jobs/polish-09/test-saves-%d" % Time.get_ticks_usec()
 root.add_child(game)
 game.name_input.text="QA"
 game.select_slot(1)
 game.level=10
 game.hp=game.max_hp()
 for enabled in [false,true]:
  game.lightness=enabled
  game.hero.position=Vector3(0,0.05,40)
  game.navigate_to(Vector3(0,0,65))
  var start=game.hero.position
  var clock=load("res://art-jobs/polish-09/speed_clock.gd").new()
  root.add_child(clock)
  while clock.elapsed<0.5:
   await physics_frame
   await process_frame

  var elapsed=clock.elapsed
  clock.queue_free()
  var distance=Vector2(game.hero.position.x-start.x,game.hero.position.z-start.z).length()
  var expected=28.8 if enabled else 14.4
  if absf(distance/elapsed-expected)>2.0:
   push_error("FAIL speed actual=%f expected=%f" % [distance/elapsed,expected]); quit(1); return
  print("PASS measured movement speed: ",distance/elapsed)
 for name in ["country-grass","earth-road"]:
  var texture=game.Textures.image_texture(name)
  if texture==null or texture.get_width()!=1024: push_error("FAIL texture "+name); quit(1); return
 if game.monsters.size()!=60: push_error("FAIL monsters"); quit(1); return
 game.active_slot=0
 game.queue_free()
 print("PASS polish: physical normal/lightness movement, two decoded textures, sixty monsters")
 quit()
