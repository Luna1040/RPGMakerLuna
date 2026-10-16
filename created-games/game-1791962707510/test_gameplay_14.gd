extends SceneTree
var game: Node
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, detail: String) -> void:
 if not ok:failed=true;push_error("FAIL "+detail)
func frames(n: int) -> void:
 for i in range(n):
  await physics_frame
  await process_frame
func run() -> void:
 game=load("res://main.tscn").instantiate()
 game.saves.directory="res://art-jobs/skills-14/test-saves-%d" % Time.get_ticks_usec()
 root.add_child(game)
 await frames(4)
 game.name_input.text="Gameplay14"
 game.select_slot(1)
 await frames(5)
 game.set_process(false)
 game.set_physics_process(false)
 var menus: Node=game.get_node("GameMenus")
 var ui: Node=menus.skill_ui
 game.level=4
 check(not game.learn_skill("lightness"),"Level four locked")
 game.level=5
 check(game.learn_skill("lightness"),"Level five learns lightness")
 game.level=9
 check(not game.learn_skill("cloud_step"),"Level nine cloud locked")
 game.level=10
 check(game.learn_skill("cloud_step"),"Level ten cloud learns")
 check(game.use_skill("lightness") and game.lightness_remaining==60,"Lightness lasts sixty seconds")
 check(is_equal_approx(game.movement_speed(),14.4),"Lightness double speed")
 game.use_skill("cloud_step")
 check(game.glide_remaining==0.9 and game.active_lightness=="lightness","Cloud instant motion does not replace timed buff")
 game.glide_remaining=0.3
 check(game.use_skill("cloud_step") and game.glide_remaining==0.9,"Immediate repeated cast")
 game.glide_remaining=0
 game.lightness=false
 game.lightness_remaining=0
 game.hp=game.max_hp()
 game.toggle_meditation()
 check(game.meditating,"Full HP meditation allowed")
 game._process(0.2)
 check(game.meditating,"Full HP remains sitting")
 game.kungfu_fx._process(0.2)
 check(is_instance_valid(game.kungfu_fx.meditation_ring),"Client meditation effect visible")
 var mob: Dictionary=game.monsters[0]
 game.hero.position=mob.body.position+Vector3(1,0,0)
 mob.wind=0.01
 mob.aim=game.hero.position
 game.update_monster(mob,0.02)
 check(game.meditating and game.hp<game.max_hp(),"Monster hit does not interrupt meditation")
 game.toggle_meditation()
 mob.aggro=false
 mob.wind=0
 game.selected_monster=-1
 var before: float=mob.hp
 game.update_camera(1,true)
 var screen: Vector2=game.camera.unproject_position(mob.body.position+Vector3(0,0.6,0))
 game.click_world(screen)
 check(game.selected_monster==0 and game.click_target=="" and mob.hp==before,"First click selects only")
 game.attack_cd=0
 check(game.use_skill("attack") and mob.hp<before,"Shortcut attack selected monster")
 game.click_target=""
 game.route.clear()
 game.attack_cd=0
 game.click_world(screen)
 check(game.click_target=="monster:0","Second click starts pursuit")
 game.click_target=""
 game.route.clear()
 game.potions=2
 game.hp=20
 check(game.assign_skill(8,"potion"),"Potion bind")
 var source: Button=ui.create_source("potion")
 ui.add_child(source)
 var data: Variant=source._get_drag_data(Vector2.ZERO)
 check(data is Dictionary and ui.slots[8]._can_drop_data(Vector2.ZERO,data),"Medicine drag accepted")
 var event:=InputEventKey.new()
 event.keycode=KEY_9
 event.pressed=true
 Input.parse_input_event(event)
 await process_frame
 check(game.potions==1 and game.hp==80,"Key nine consumes medicine and heals")
 menus.toggle(1)
 check(menus.bag_slots.size()==40,"Forty bag slots")
 for i in range(1,40):check(menus.bag_slots[i].text=="","Empty bag has no index")
 menus.close()
 game.training_state=0
 menus.toggle(2)
 menus.guide_quest()
 check(not game.paused and game.click_target=="master" and not game.route.is_empty(),"Quest guide routes to master")
 game.click_target=""
 game.route.clear()
 # Actual south doorway traversal in both directions through x=0.75,z=22.
 Engine.time_scale=3
 game.set_physics_process(true)
 for pair in [[Vector3(0.75,0.05,18.5),Vector3(0.75,0.05,27)],[Vector3(0.75,0.05,27),Vector3(0.75,0.05,18.5)],[Vector3(0.75,0.05,18.5),Vector3(0.75,0.05,39)]]:
  game.hero.position=pair[0]
  game.hero.velocity=Vector3.ZERO
  game.navigate_to(pair[1])
  check(not game.route.is_empty(),"South route exists")
  var closest:=100.0
  for i in range(420):
   await frames(1)
   closest=minf(closest,Vector2(game.hero.position.x-0.75,game.hero.position.z-22).length())
   if game.route_index>=game.route.size():break
  print("SOUTH END ",game.hero.position," CENTER ",closest)
  check(Vector2(game.hero.position.x-pair[1].x,game.hero.position.z-pair[1].z).length()<1,"South passage reached endpoint")
  check(closest<1.2,"South route passes doorway instead of detour")
 # Open field: two-stage displacement and immediate recast.
 game.hero.position=Vector3(-48,0.05,-18)
 game.hero.velocity=Vector3.ZERO
 game.hero_model.root.rotation.y=-PI/2
 game.use_skill("cloud_step")
 var start: Vector3=game.hero.position
 for i in range(30):await frames(1)
 print("GLIDE_DISTANCE ",game.hero.position.distance_to(start))
 check(game.hero.position.distance_to(start)>15,"Glide travels substantial distance")
 check(game.glide_remaining<=0,"Glide has no continuing duration")
 game.set_physics_process(false)
 game.hp=game.max_hp()
 var snap: Dictionary=game.snapshot()
 check(game.saves.valid_progress(snap),"Potion bindings survive save schema")
 game.restore(snap)
 check(game.skill_slots[8]=="potion","Potion binding restored")
 game.active_slot=0
 game.queue_free()
 print("GAMEPLAY_14_FAIL" if failed else "GAMEPLAY_14_PASS")
 quit(1 if failed else 0)
