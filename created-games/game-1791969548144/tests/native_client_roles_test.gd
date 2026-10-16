extends SceneTree

const FIXTURE := "res://tests/native-role-fixture.json"

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 var g=load("res://canosa.gd").new()
 g.save_store.path=FIXTURE
 root.add_child(g)
 assert(g.state=="characters")
 assert(g.native_actors.size()==9 and g.npcs.size()==16)
 for key in ["warrior","mage"]:
  var actor: Node=g.native_actors[key]
  assert(actor.sources.size()==4,"Body/head/hair/weapon must all be attached")
  for source in actor.sources:
   assert(source.instance.mesh.get_surface_count()==1)
   assert(source.instance.material_override.albedo_texture!=null)
 g.new_run()
 for i in range(7,16):
  assert(g.npcs[i].has("client_grid") and not g.npcs[i].name.is_empty())
  var path: Array[Vector2]=g.client_map.route(g.hero,g.npcs[i].pos,10)
  assert(not path.is_empty(),"Restored NPC must stand on reachable ground")
  g.hero=g.npcs[i].pos
  g.mouse_npc=i
  g.talk()
  assert(g.dialog_npc==i,"Must speak to clicked original NPC, even near another NPC")
  assert(g.dialog_text.contains(g.npcs[i].name))
  g.choose_dialog(0)
  assert(g.quest==0,"Restored role dialogues must not alter fallback main quest")
  g.close_dialog()
 assert(g.create_character(0,"战士原型","战士"))
 g.update_walk(g.hero-Vector2(10,0),0.1)
 assert(g.native_actors.warrior.moving and not g.native_actors.mage.moving)
 g.profession="法师"
 g.update_walk(g.hero-Vector2(10,0),0.1)
 assert(g.native_actors.mage.moving and not g.native_actors.warrior.moving)
 g.free()
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 print("PASS: native roles, attachments, nine reachable original NPCs, clicked dialogue, fallback quest preserved")
 quit()
