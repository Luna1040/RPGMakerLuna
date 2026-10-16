extends SceneTree
const FIXTURE:="res://tests/field-update-fixture.json"
func _initialize() -> void: call_deferred("run")
func clean() -> void:
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
func run() -> void:
 clean()
 var store=load("res://character_saves.gd").new()
 store.path=FIXTURE
 assert(store.utc_plus_8(1704067200)=="2024-01-01T08:00:00+08:00")
 var legacy={"version":1,"timezone":"UTC-08:00","slots":[{"name":"旧中文角色","class":"战士","created_at":"2023-12-31T16:00:00-08:00","offline_at":"2023-12-31T17:00:00-08:00","last_seen_at":"2023-12-31T17:00:00-08:00","level":1,"snapshot":{}},null,null,null,null,null]}
 var file=FileAccess.open(FIXTURE,FileAccess.WRITE)
 file.store_string(JSON.stringify(legacy))
 file.close()
 assert(store.read_slots())
 assert(store.slots[0].created_at=="2024-01-01T08:00:00+08:00")
 assert(store.slots[0].offline_at=="2024-01-01T09:00:00+08:00")
 assert(store.write_slots())
 assert(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)).timezone=="UTC+08:00")
 assert(store.read_slots() and store.slots[0].name=="旧中文角色")
 var g=load("res://canosa.gd").new()
 g.save_store.path=FIXTURE
 root.add_child(g)
 g.new_run()
 assert(g.enemy_actors.size()==36)
 for kind in range(3):
  var expected_names:=["鹿角兽","巨杰士","猎杀兽"]
  var count:=0
  for enemy in g.enemies:
   if enemy.kind==kind:
    count+=1
    assert(enemy.name==expected_names[kind] and enemy.level==[1,5,7][kind])
  assert(count==12)
 for actor in g.enemy_actors:
  assert(actor.clips.has("walk") and actor.clips.has("attack") and actor.sources.size()>0)
  assert(actor.clips.walk.frames.size()>1 and actor.clips.attack.frames.size()>1)
 var starts: Array=[]
 for enemy in g.enemies: starts.append(enemy.pos)
 seed(7531)
 for step in range(300): g._process(0.1)
 var moved:=0
 for i in range(36):
  var enemy: Dictionary=g.enemies[i]
  if enemy.pos.distance_to(starts[i])>5: moved+=1
  assert(enemy.pos.distance_to(enemy.spawn)<=enemy.activity_radius+0.1)
  assert(not g.safe(enemy.pos) and g.client_map.land(enemy.pos))
 assert(moved>=25,"Idle monsters must wander, including while player is in town")
 var path: Array[Vector2]=g.client_map.route(g.map_spawn(),Vector2(5000,2400),1)
 assert(not path.is_empty())
 var previous: Vector2=g.map_spawn()
 for point in path:
  assert(g.client_map.move_allowed(previous,point,1)==point)
  previous=point
 for i in range(5):
  g.hero=g.npcs[i].pos
  g.mouse_npc=i
  g.talk()
  g.choose_dialog(0)
  g.close_dialog()
 assert(g.level==5 and g.quest==5)
 var enemy: Dictionary=g.enemies[12]
 g.hero=enemy.pos+Vector2(35,0)
 g.mouse_enemy=12
 g.strike(false)
 assert(g.native_actors.warrior.attack_serial>0)
 g._process(0.1)
 assert(g.enemy_actors[12].attack_serial>0,"Enemy contact must trigger attack animation")
 var home: Vector2=enemy.spawn
 g.hero=home+Vector2(600,0)
 for step in range(50): g._process(0.1)
 assert(not enemy.aggro and enemy.pos.distance_to(home)<=enemy.activity_radius+0.1)
 g.free()
 clean()
 print("PASS: UTC+8 legacy migration/Chinese, level-five quest, level-one exit, 36 native monsters, bounded random wander, player/enemy attack triggers")
 quit()
