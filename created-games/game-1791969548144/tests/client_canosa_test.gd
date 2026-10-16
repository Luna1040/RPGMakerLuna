extends SceneTree

func _initialize() -> void:
 var map=load("res://client_canosa_map.gd").new()
 map.setup()
 assert(map.tiles.size()==9)
 assert(map.tiles[0].get_size()==Vector2(4096,4096))
 assert(map.tiles[8].get_size()==Vector2(664,2048))
 var g=load("res://canosa.gd").new()
 g.client_map=map
 for i in range(g.npcs.size()): g.npcs[i].pos=map.NPC_POS[i]
 g.new_run()
 assert(g.hero==map.SPAWN and g.safe(g.hero))
 assert(g.enemies.size()==36)
 for e in g.enemies: assert(not g.safe(e.pos) and map.land(e.pos))
 var p:=Vector2(3000,1900)
 assert(g.world_pos(g.screen_pos(p)).distance_to(p)<0.01)
 for i in range(5):
  assert(map.land(g.npcs[i].pos) and g.safe(g.npcs[i].pos))
  var path: Array[Vector2]=map.route(g.hero,g.npcs[i].pos,g.level)
  print("NPC ",i," route nodes ",path.size())
  assert(not path.is_empty(),"Every starter NPC must be reachable")
  for point in path: assert(map.safe(point))
  g.navigate(g.npcs[i].pos)
  g.mouse_npc=i
  for step in range(1800):
   if g.dialog_npc>=0: break
   g._process(1.0/60)
  if g.dialog_npc!=i: print("STUCK ",g.hero," next ",g.route," target ",g.npcs[i].pos)
  assert(g.dialog_npc==i,"Real movement route must reach and open the NPC")
  g.choose_dialog(0)
  g.close_dialog()
 assert(g.level==5)
 var out_path: Array[Vector2]=map.route(map.SPAWN,Vector2(5000,2400),10)
 assert(not out_path.is_empty(),"Outdoor gate path must be connected")
 assert(not map.route(map.SPAWN,Vector2(5000,2400),1).is_empty())
 var previous: Vector2=map.SPAWN
 for point in out_path:
  assert(map.land(point))
  if map.safe(previous)!=map.safe(point): assert(point.distance_to(map.GATE)<420)
  previous=point
 assert(g.snapshot().map_id=="client_chamgw26")
 var fixture: String="res://tests/client-map-save-fixture.json"
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(fixture+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture+suffix))
 g.save_store.path=fixture
 assert(g.save_store.create(0,"旧地图角色","战士",1704067200))
 assert(g.save_store.save_character(0,{"level":9,"quest":4,"hp":150,"gold":123,"position":[1200,1700]},true,1704067200))
 assert(g.load_character(0))
 assert(g.hero==map.SPAWN and g.level==9 and g.quest==4 and g.hp==150 and g.gold==123)
 assert(g.save_progress())
 assert(g.save_store.slots[0].snapshot.map_id=="client_chamgw26")
 g.hero=Vector2(5000,2400)
 g.new_run()
 assert(g.hero==map.SPAWN and g.quest==0)
 g.free()
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(fixture+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture+suffix))
 print("PASS: original 9-tile map, dimensions, world projection, all NPC routes, safe boundary, level gate, 36 monsters, reset")
 quit()
