extends SceneTree
var game: Node
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, detail: String) -> void:
 if not ok:failed=true;push_error(detail)
func frames(n: int) -> void:
 for i in range(n):
  await physics_frame
  await process_frame
func run() -> void:
 game=load("res://main.tscn").instantiate()
 game.saves.directory="res://art-jobs/skills-13/test-saves-%d" % Time.get_ticks_usec()
 root.add_child(game)
 await frames(4)
 game.name_input.text="武功验收"
 game.select_slot(1)
 game.set_process(false)
 game.set_physics_process(false)
 game.get_node("GameMenus").toggle(3)
 game.get_node("GameMenus").close()
 check(not game.paused,"Skills menu closing restores gameplay")
 game.level=4
 check(is_equal_approx(game.movement_speed(),7.2),"Base movement half speed")
 check(not game.learn_skill("lightness"),"Level four locked")
 var ui: Node=game.get_node("GameMenus/SkillUI")
 var source: Button=ui.create_source("lightness")
 ui.add_child(source)
 check(source._get_drag_data(Vector2.ZERO)==null,"Unlearned icon cannot drag")
 game.level=5
 check(game.learn_skill("lightness"),"Level five learn")
 var drag: Variant=source._get_drag_data(Vector2.ZERO)
 check(drag is Dictionary and drag.id=="lightness","Learned icon draggable")
 check(ui.slots[1]._can_drop_data(Vector2.ZERO,drag),"Skill slot accepts drag")
 ui.slots[1]._drop_data(Vector2.ZERO,drag)
 check(game.skill_slots[1]=="lightness","Drop assigns slot two")
 check(not game.assign_skill(2,"cloud_step"),"Unlearned cloud cannot bind")
 var event:=InputEventKey.new()
 event.keycode=KEY_2
 event.pressed=true
 Input.parse_input_event(event)
 await frames(1)
 check(game.lightness and is_equal_approx(game.lightness_remaining,60),"Key two activates sixty second lightness")
 check(is_equal_approx(game.movement_speed(),14.4),"Buff twice base speed")
 ui._process(0)
 check(ui.buff.visible and ui.countdown.text=="60s","Right buff icon and countdown")
 game._process(1.2)
 ui._process(0)
 check(game.lightness_remaining<59 and ui.countdown.text=="59s","Timer progresses")
 game.hero.velocity=Vector3(7.2,0,0)
 var dust_before: int=game.kungfu_fx.dust_count
 game.kungfu_fx._process(0.1)
 check(game.kungfu_fx.dust_count>dust_before,"Moving buff emits native dust")
 game.hero.velocity=Vector3.ZERO
 dust_before=game.kungfu_fx.dust_count
 game.kungfu_fx._process(0.2)
 check(dust_before==game.kungfu_fx.dust_count,"Idle stops dust")
 game.lightness_remaining=0.02
 game._process(0.1)
 check(not game.lightness and is_equal_approx(game.movement_speed(),7.2),"Expiry restores speed")
 game.level=9
 check(not game.learn_skill("cloud_step"),"Level nine cloud locked")
 game.level=10
 check(game.learn_skill("cloud_step") and game.assign_skill(8,"cloud_step"),"Level ten learns cloud and slot nine")
 check(game.use_skill("cloud_step") and game.glide_remaining>0 and not game.lightness,"Cloud skill activation")
 check(game.kungfu_fx.puffs.size()>=6,"Client wind cast layers")
 game.use_skill("lightness")
 var saved: Dictionary=game.snapshot()
 game.skill_slots[8]=""
 game.restore(saved)
 check(game.skill_slots[8]=="cloud_step" and "cloud_step" in game.learned_skills,"Skills and slots restore")
 check(game.lightness_remaining>59 and game.lightness_remaining<=60,"Duration persists")
 check(game.save_character(true),"Save valid extended state")
 var data: Dictionary=game.saves.read_slot(1)
 check(data.created_at.ends_with("+08:00") and data.saved_at.ends_with("+08:00") and data.last_offline_at.ends_with("+08:00") and data.timezone=="UTC+08:00","All save stamps UTC plus eight")
 var old: Dictionary=data.duplicate(true)
 old.created_at="2026-10-14T07:34:05-08:00"
 old.saved_at="2026-10-14T20:48:48-08:00"
 old.last_offline_at="2026-10-14T20:48:48-08:00"
 old.timezone="UTC-08:00"
 var normalized: Dictionary=game.Saves.normalize_times(old)
 check(normalized.created_at=="2026-10-14T23:34:05+08:00" and normalized.saved_at=="2026-10-15T12:48:48+08:00","Old timezone migration preserves instant")
 game.active_slot=0
 game.queue_free()
 await frames(2)
 print("SKILLS_SAVE_PASS" if not failed else "SKILLS_SAVE_FAIL")
 quit(1 if failed else 0)
