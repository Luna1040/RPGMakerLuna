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
func npc(title: String) -> void:
 game.dialogue.hide()
 game.talk_town_npc(title)
 game.dialogue.hide()
func kill_mob(index: int) -> void:
 var mob: Dictionary=game.monsters[index]
 game.hero.position=mob.body.position+Vector3(1.2,0,0)
 game.hero.velocity=Vector3.ZERO
 mob.hp=1
 game.attack_cd=0
 game.attack_monster(index)
func run() -> void:
 game=load("res://main.tscn").instantiate()
 game.saves.directory="res://art-jobs/progression-15/test-saves-%d" % Time.get_ticks_usec()
 root.add_child(game)
 await frames(4)
 game.name_input.text="Progression15"
 game.select_slot(1)
 await frames(4)
 game.set_process(false)
 game.set_physics_process(false)
 game.level=9
 game.exp_points=0
 game._process(0.01)
 check(game.promotion_stage==0,"No early pigeon")
 game.gain_experience(game.xp_needed())
 game._process(0.01)
 check(game.level==10 and game.promotion_stage==1,"Level ten sends pigeon")
 var ui: Node=game.progression_ui
 ui._process(0)
 check(ui.mail.visible and ui.mail.icon!=null,"Pigeon indicator exists")
 ui.mail.pressed.emit()
 check(game.promotion_stage==2 and ui.letter.visible and game.paused,"Pigeon opens letter and marks read")
 ui.open_letter()
 ui.close_letter()
 check(not game.paused,"Closing letter restores play")
 check(not game.learn_skill("blade_10"),"Promotion required for profession skill")
 # Route to the master, invoking the real proximity interaction and offer.
 game.set_process(true)
 game.set_physics_process(true)
 Engine.time_scale=3
 game.guide_promotion()
 for i in range(700):
  await frames(1)
  if ui.letter.visible:break
 check(ui.letter.visible and game.hero.position.distance_to(game.master.position)<1.8,"Actual route reaches promotion NPC and opens offer")
 game.accept_promotion()
 check(game.promotion_stage==3 and not game.paused,"Accept first promotion")
 game.set_process(false)
 game.set_physics_process(false)
 npc(game.NPC_NAMES[5])
 check(game.promotion_stage==4,"Yin requests meal")
 npc(game.NPC_NAMES[1])
 check(game.promotion_stage==5,"Jin requests boar leg")
 kill_mob(3)
 check(game.promotion_stage==6 and game.promotion_boar==1,"Real boar kill grants quest leg")
 npc(game.NPC_NAMES[1])
 npc(game.NPC_NAMES[5])
 check(game.promotion_stage==8,"Meal delivers armor")
 npc(game.NPC_NAMES[4])
 npc(game.NPC_NAMES[3])
 check(game.promotion_stage==10,"Weapon quest requests wolf bones")
 var wolves: Array=[]
 for i in range(game.monsters.size()):
  if game.monsters[i].species==game.monsters[5].species:wolves.append(i)
 for index in wolves.slice(0,3):kill_mob(index)
 check(game.promotion_stage==11 and game.promotion_bones==3,"Three actual wolf kills grant bones")
 var intermediate: Dictionary=game.snapshot()
 game.restore(intermediate)
 await frames(3)
 check(game.promotion_stage==11 and game.promotion_bones==3,"Mid-quest save restores exact stage")
 npc(game.NPC_NAMES[3])
 npc(game.NPC_NAMES[4])
 check(game.promotion_stage==13,"Medicine delivers weapon")
 var before_coins: int=game.coins
 game.talk_master()
 check(game.promotion_stage==14 and game.coins==before_coins+10000,"Promotion reward")
 game.dialogue.hide()
 game.talk_master()
 game.dialogue.hide()
 check(game.coins==before_coins+10000,"Reward cannot repeat")
 check(game.max_qi()==150 and game.rank_title()!= "","Promotion stats and rank")
 var roles: Array=[game.Saves.PROFESSIONS[0],game.Saves.PROFESSIONS[1],game.Saves.PROFESSIONS[2]]
 var ids: Array=["blade_10","sword_10","spear_10"]
 for i in range(3):
  game.character.profession=roles[i]
  game.apply_profession_model()
  await frames(2)
  check(game.hero_model.root.skeletons.size()==5,"Five skinned model parts")
  if i==0:check("HMK00020" in game.hero_model.root.get_meta("model_stems"),"Blade corrected matching head mesh")
  check(game.learn_skill(ids[i]),"Profession level ten skill learns "+ids[i])
  check(not game.learn_skill(ids[(i+1)%3]),"Other profession learning rejected")
  check(game.assign_skill(2,ids[i]),"Profession skill binds")
  var mob: Dictionary=game.monsters[0]
  game.reset_monster(mob)
  game.hero.position=mob.body.position+Vector3(1.2,0,0)
  game.hero.velocity=Vector3.ZERO
  game.selected_monster=0
  game.click_target=""
  game.route.clear()
  game.martial_cd=0
  game.strike_timer=0
  game.qi=4
  check(not game.use_skill(ids[i]),"Insufficient mana rejected")
  game.qi=100
  var before: float=mob.hp
  var key:=InputEventKey.new()
  key.keycode=KEY_3
  key.pressed=true
  Input.parse_input_event(key)
  await process_frame
  check(game.strike_timer>0 and mob.hp==before and game.qi==100-int(preload("res://kungfu_data.gd").DATA[ids[i]].cost),"Real key starts windup and consumes profession inner power, not immediate damage")
  game._process(0.1)
  check(mob.hp==before,"Before hit event no damage")
  game._process(0.32)
  check(mob.hp<before,"Native skill hit event damages selected monster")
  check(not game.use_skill(ids[i]),"Martial cooldown enforced")
  game.hero_model.root._process(0.04)
  var skeleton: Skeleton3D=game.hero_model.root.skeletons[0]
  var hand: int=skeleton.find_bone("Bip01_R_Hand")
  check(skeleton.get_bone_pose_rotation(hand).is_finite(),"Native ANI pose finite")
 for skeleton in game.hero_model.root.skeletons:
  for bone in range(skeleton.get_bone_count()):
   check(skeleton.get_bone_pose_rotation(bone).is_finite() and skeleton.get_bone_pose_position(bone).is_finite(),"All native bone poses finite")
 game.queued_skill="spear_10"
 game.queued_target=0
 game.select_monster(1)
 check(game.queued_skill.is_empty(),"Changing target cancels queued skill")
 var full: Dictionary=game.snapshot()
 check(game.saves.valid_progress(full),"Extended progress schema valid")
 game.restore(full)
 await frames(3)
 check(game.skill_slots[2]=="spear_10" and game.promotion_stage==14,"Skill and promotion reload")
 game.hero.position=Vector3(-55,0.05,3)
 var dead_at: Vector3=game.hero.position
 game.hp=0
 game._process(0.01)
 check(ui.death.visible and game.paused,"Death shows blocking return popup")
 var r:=InputEventKey.new()
 r.keycode=KEY_R
 r.pressed=true
 game._unhandled_input(r)
 check(game.hp==0 and game.hero.position==dead_at,"R cannot bypass confirmation")
 var escape:=InputEventKey.new()
 escape.keycode=KEY_ESCAPE
 escape.pressed=true
 Input.parse_input_event(escape)
 await process_frame
 check(ui.death.visible and game.hp==0,"Escape cannot dismiss death confirmation")
 ui.death_confirm.pressed.emit()
 check(game.hp==game.max_hp() and not ui.death.visible and not game.paused,"Confirmation revives")
 check(absf(game.hero.position.x)<36 and game.hero.position.z<28.8 and game.promotion_stage==14,"Confirmed return preserves promotion")
 game.active_slot=0
 game.queue_free()
 await frames(2)
 print("PROGRESSION_15_FAIL" if failed else "PROGRESSION_15_PASS")
 quit(1 if failed else 0)
