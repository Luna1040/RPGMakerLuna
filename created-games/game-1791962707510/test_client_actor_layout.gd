extends SceneTree
var game: Node
var failed:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
 if not ok:
  failed=true
  push_error("FAIL: "+title)
func wait_frames(n: int) -> void:
 for i in range(n):
  await physics_frame
  await process_frame
func walk() -> void:
 for i in range(1400):
  await wait_frames(1)
  if game.route_index>=game.route.size(): return
  if i%300==0: print("WALK ",game.hero.position," -> ",game.click_target)
 check(false,"Route timeout "+game.click_target+" at "+str(game.hero.position))
 game.route.clear()
func run() -> void:
 Engine.time_scale=4
 game=load("res://main.tscn").instantiate()
 game.saves.directory="res://art-jobs/client-actors-10/test-saves-%d" % Time.get_ticks_usec()
 root.add_child(game)
 await wait_frames(3)
 check(game.Saves.PROFESSIONS==["刀客","剑客","枪客"],"Only three professions")
 check(game.profession_input.item_count==3,"Three roster choices")
 game.name_input.text="客户端验收"
 game.select_slot(1)
 await wait_frames(4)
 check(game.get_meta("original_layout",false),"Original client layout active")
 check(game.get_meta("client_scenery_count",0)>200,"Restored scenery instances")
 check(game.town_actors.size()==6 and game.monsters.size()==60,"Six NPC and 60 monsters")
 for role in ["刀客","剑客","枪客"]:
  game.character.profession=role
  game.apply_profession_model()
  await wait_frames(2)
  check(game.hero_model.root.get_meta("client_skinned",false),"Imported rig "+role)
  check(game.hero_model.root.skeletons.size()==5,"Body, hair, face, arms, feet "+role)
 var old: Dictionary=game.character.duplicate(true)
 old.slot=2
 old.profession="医生"
 old.level=13
 old.progress=game.snapshot()
 check(game.saves.write_slot(2,old),"Legacy doctor record remains readable")
 var migrated: Dictionary=game.saves.read_slot(2)
 check(migrated.profession=="刀客" and migrated.level==13 and migrated.original_profession=="医生","Doctor migration preserves level and progress")
 game.character.profession="刀客"
 game.apply_profession_model()
 for title in game.NPC_NAMES:
  var actor: Node3D=game.town_actors[title]
  check(actor.get_meta("model",{}).get("root",null)!=null or title=="泫渤派门主","NPC rig "+title)
  game.navigate_to_actor(actor,"master" if title=="泫渤派门主" else "npc:"+title)
  check(game.route.size()>0,"NPC route exists "+title)
  await walk()
  await wait_frames(25)
  check(game.dialogue.visible,"NPC dialogue "+title+" at "+str(actor.position)+" hero "+str(game.hero.position))
  game.dialogue.hide()
 for destination in [Vector3(-49,0,3),Vector3(49,0,0),Vector3(0,0,39)]:
  game.navigate_to(destination)
  check(game.route.size()>0,"Field route exists "+str(destination))
  await walk()
  check(Vector2(game.hero.position.x-destination.x,game.hero.position.z-destination.z).length()<1.2,"Field reached "+str(destination))
 print("RESTORED_SCENERY_INSTANCES=",game.get_meta("client_scenery_count"))
 game.active_slot=0
 game.queue_free()
 print("CLIENT_ACTOR_LAYOUT_", "FAIL" if failed else "PASS")
 quit(1 if failed else 0)
