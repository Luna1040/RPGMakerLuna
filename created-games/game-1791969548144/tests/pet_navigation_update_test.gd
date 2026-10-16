extends SceneTree

func _initialize() -> void:
 var g=load("res://canosa.gd").new()
 g.new_run()
 for profession in ["战士","法师"]:
  g.profession=profession
  g.init_pets()
  for companion in g.pets:
   assert(companion.name==profession+"攻防型")
   assert(companion.type_id==(1071020 if profession=="战士" else 1071220))
   assert(companion.deployed)
 g.hero=Vector2(3500,1800)
 g.toggle_pet(1)
 g.take_hit(20)
 assert(g.hp==160 and g.pets[1].hp==120,"Recalled pet must not absorb damage")
 g.toggle_pet(1)
 g.take_hit(20)
 assert(g.hp==150 and g.pets[1].hp==110)
 g.toggle_pet(0)
 var saved: Dictionary=g.snapshot()
 assert(not saved.pets[0].deployed and saved.pets[1].deployed)
 assert(saved.pets[0].type_id==1071220)
 var fixture: String="res://tests/pet-update-fixture.json"
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(fixture+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture+suffix))
 g.save_store.path=fixture
 assert(g.save_store.create(0,"幻兽测试","法师",1704067200))
 assert(g.save_store.save_character(0,saved,false,1704067200))
 assert(g.load_character(0))
 assert(not g.pets[0].deployed and g.pets[1].deployed and g.pets[1].hp==110)
 # Legacy names are migrated to the two validated species without losing HP.
 saved.pets[0].erase("deployed")
 saved.pets[0].name="旧攻型幻兽"
 assert(g.save_store.save_character(0,saved,false,1704067200))
 assert(g.load_character(0) and g.pets[0].name=="法师攻防型" and g.pets[0].deployed)
 var map=load("res://client_canosa_map.gd").new()
 map.setup()
 var left:=Vector2(1500,1200)
 var right:=Vector2(3100,1200)
 assert(map.land(left) and map.land(right))
 assert(map.move_allowed(left,right,10)==left,"Swept move must not tunnel through central monument")
 var path: Array[Vector2]=map.route(left,right,10)
 assert(not path.is_empty(),"Must route around the monument")
 var previous:=left
 for point in path:
  assert(map.move_allowed(previous,point,10)==point)
  previous=point
 assert(g.dialog_button_rect(0).size==Vector2(430,34))
 g.free()
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(fixture+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture+suffix))
 print("PASS: two pet types, summon/recall effects, snapshot/legacy migration, swept collision, obstacle detour, compact dialogue")
 quit()
