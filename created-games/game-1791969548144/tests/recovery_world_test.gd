extends SceneTree
const FIXTURE:="res://tests/recovery-world-fixture.json"
func _initialize() -> void: call_deferred("run")
func clean() -> void:
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
func run() -> void:
 clean()
 var g=load("res://canosa.gd").new()
 g.save_store.path=FIXTURE
 root.add_child(g)
 g.new_run()
 assert(g.pet_actors.size()==2)
 assert(g.pet_actors[0].actor_id=="petwarrior")
 assert(g.enemies[0].model=="mob400" and g.enemies[12].model=="mob401" and g.enemies[24].model=="mob402")
 var map: RefCounted=g.client_map
 var start:=Vector2(6800,6030)
 var finish:=Vector2(7480,6500)
 var path: Array[Vector2]=map.route(start,finish,1)
 print("Bridge path: ",path.size())
 assert(not path.is_empty(),"Southeast bridge must connect both banks")
 var previous:=start
 for point in path:
  assert(map.move_allowed(previous,point,1)==point,"No water rejection across bridge")
  previous=point
 assert(map.clearance(Vector2(7132,6222)),"Existing player on bridge must remain valid")
 assert(not map.route(finish,map.PORTAL,1).is_empty(),"Lower-right portal must be reachable from the south bank")
 assert(g.create_character(0,"回城测试","战士"))
 g.level=17
 g.quest=3
 g.gold=987
 g.potions=2
 g.pets[0].level=7
 g.pets[0].exp=31
 g.pets[1].deployed=false
 g.hero=map.PORTAL
 g.world_travel.armed=true
 g._process(0.1)
 assert(g.state=="travel" and g.world_travel.portal_dialog.visible)
 g.world_travel.confirm_portal()
 assert(g.current_region==2000 and g.client_map.SIZE==Vector2(9216,5888))
 assert(g.enemies.is_empty() and g.npcs.is_empty() and g.safe(g.hero))
 assert(g.client_map.land(g.hero))
 assert(g.snapshot().region_id==2000 and g.snapshot().map_id=="client_treecity")
 assert(g.level==17 and g.quest==3 and g.gold==987 and g.pets[0].exp==31)
 for point in [Vector2(.235,.82),Vector2(.49,.72),Vector2(.61,.40),Vector2(.711,.65)]:
  var target: Vector2=point*g.map_size()
  var city_path: Array[Vector2]=g.client_map.route(g.map_spawn(),target,1)
  print("Tree platform ",point," path ",city_path.size())
  assert(not city_path.is_empty(),"Tree leaf platforms and branch bridges must be connected")
 assert(g.save_progress())
 assert(g.load_character(0) and g.current_region==2000 and g.level==17 and g.gold==987)
 g.world_travel.switch_region(1000)
 assert(g.enemies.size()==36 and g.npcs.size()==16)
 g.hero=Vector2(5000,2400)
 g.hp=0
 g._process(0)
 assert(g.state=="dead" and g.world_travel.death_dialog.visible)
 var before: Dictionary=g.snapshot()
 var event=InputEventKey.new()
 event.pressed=true
 event.keycode=KEY_R
 g._unhandled_input(event)
 assert(g.state=="dead" and g.level==17,"Death must not invoke fresh-character restart")
 g.world_travel.resurrect()
 assert(g.state=="play" and g.hp==180 and g.hero==g.map_spawn())
 assert(g.level==17 and g.quest==3 and g.gold==987 and g.potions==2)
 assert(g.pets[0].level==7 and g.pets[0].exp==31 and not g.pets[1].deployed)
 assert(g.save_store.slots[0].snapshot.hp==180)
 var after: Dictionary=g.snapshot()
 for key in before:
  if key not in ["hp","position"]: assert(before[key]==after[key],"Resurrection must preserve "+key)
 g.hp=0
 g._process(0)
 assert(g.save_progress())
 assert(g.load_character(0) and g.state=="dead" and g.world_travel.death_dialog.visible)
 g.world_travel.resurrect()
 assert(g.hp==180 and g.level==17)
 g.free()
 clean()
 print("PASS: native pets and corrected monsters, bridge/portal route, tree city platforms, region persistence, death confirmation and attribute-preserving resurrection")
 quit()
