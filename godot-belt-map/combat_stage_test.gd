extends RefCounted
const Sprint = preload("sprint_input.gd")
var failures: Array[String] = []
var s

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func tick(seconds: float) -> void:
	for i in int(ceil(seconds*120)):
		s._physics_process(1.0/120)

func key(code: int, pressed: bool=true, echo: bool=false) -> void:
	var e := InputEventKey.new()
	e.keycode=code
	e.physical_keycode=code
	e.pressed=pressed
	e.echo=echo
	s._input(e)
	s._unhandled_key_input(e)

func reset_at(foot: Vector2) -> void:
	s.interface.close_panels()
	s.sprint.reset()
	s.knight.reset_character()
	s.foot=foot
	s.height_z=0
	s.grounded=true
	s.vertical_speed=0
	s.platform=""
	s.last_safe=foot
	s.hit_pause=0
	s.test_input=Vector2.ZERO
	tick(.02)

func run(stage) -> bool:
	s=stage
	s.set_physics_process(false)
	s.testing_motion=true
	var input := Sprint.new()
	input.register_key(KEY_D,true)
	input.register_key(KEY_D,true,true)
	input.register_key(KEY_RIGHT,true)
	check(not input.active,"Holding or alias key must not become double tap")
	input.reset()
	input.register_key(KEY_D,true)
	input.register_key(KEY_D,false)
	input.step(.5,Vector2.ZERO)
	input.register_key(KEY_D,true)
	check(input.active,"Distinct double tap did not sprint")
	input.register_key(KEY_D,false)
	check(not input.active,"Release did not stop sprint")
	input.reset()
	input.register_key(KEY_W,true)
	input.register_key(KEY_W,false)
	input.step(.51,Vector2.ZERO)
	input.register_key(KEY_W,true)
	check(not input.active,"Slow repeated presses start sprint")
	reset_at(Vector2(3.0,8.3))
	s.test_input=Vector2.RIGHT
	tick(.2)
	var walked: float=s.foot.x-3.0
	reset_at(Vector2(3.0,8.3))
	key(KEY_D)
	key(KEY_D,false)
	tick(.08)
	key(KEY_D)
	s.test_input=Vector2.RIGHT
	tick(.2)
	check(absf((s.foot.x-3.0)/walked-1.8)<.03 and s.knight.state=="run","Sprint speed or animation state incorrect")
	key(KEY_J)
	check(s.knight.state=="dash_attack","Running J did not enter dash attack")
	var dash_start: float=s.foot.x
	tick(.65)
	check(s.foot.x>dash_start+1.0,"Dash attack did not move forward")
	# Swept movement must still stop against a crate at sprint/dash speed.
	reset_at(Vector2(7.3,5.85))
	s.knight.request_dash_attack()
	tick(.14)
	check(s.foot.x<7.69,"Dash tunneled through an unbroken crate")
	reset_at(Vector2(6.4,8.3))
	key(KEY_SPACE)
	tick(.22)
	var hits_before: int=s.practice.total_hits
	key(KEY_J)
	check(s.knight.state=="air_slash","Airborne J did not become downward slash")
	key(KEY_J)
	tick(.9)
	check(s.grounded and s.practice.total_hits==hits_before+1,"Downward slash must land and hit once")
	# Deliberately falling into water must cancel the impact after restoring bank.
	reset_at(Vector2(13.5,5))
	s.foot=Vector2(16,5)
	s.height_z=.8
	s.grounded=false
	s.knight.set_airborne(true,0)
	key(KEY_J)
	var events_before: int=s.attacks
	tick(.8)
	check(s.grounded and s.foot.x<14.3 and s.attacks==events_before,"Invalid water landing emitted a ground impact")
	for id: String in ["crescent","rising","trinity"]:
		reset_at(Vector2(5.6,8.3))
		for target: Dictionary in s.practice.targets:
			target.reaction.reset()
			target.hp=1000.0
		var count_before: int=s.practice.total_hits
		var mana_before: float=s.knight.mana
		s.use_skill(id)
		check(s.knight.state=="skill_"+id,"Skill not started: "+id)
		check(is_equal_approx(s.knight.mana,mana_before-float(s.knight.SKILLS[id].cost)),"Skill cost incorrect: "+id)
		s.use_skill(id)
		check(is_equal_approx(s.knight.mana,mana_before-float(s.knight.SKILLS[id].cost)),"Repeated skill press charged twice")
		tick(.4)
		if id=="rising":
			check(s.practice.targets[0].reaction.airborne(),"Rising skill did not launch target")
		tick(.85)
		check(s.practice.total_hits-count_before==(3 if id=="trinity" else 1),"Wrong actual target hit count for "+id)
	reset_at(Vector2(5.6,8.3))
	for target: Dictionary in s.practice.targets:
		target.reaction.reset()
		target.hp=1000.0
	s.use_skill("rising")
	tick(.78)
	var combo_hits: int=s.practice.total_hits
	s.use_skill("trinity")
	tick(1.05)
	check(s.practice.total_hits==combo_hits+3 and s.practice.targets[0].reaction.air_hits>0,"Rising into trinity must sustain an aerial combo")
	reset_at(Vector2(5.6,8.3))
	s.knight.mana=0
	s.use_skill("trinity")
	check(s.knight.state=="stand" and s.knight.skill_cooldowns.trinity==0,"Insufficient MP consumed cooldown")
	reset_at(Vector2(6.0,4.4))
	s.interact()
	key(KEY_D)
	key(KEY_D,false)
	key(KEY_D)
	key(KEY_1)
	check(not s.sprint.active and s.knight.skill_cooldowns.crescent==0,"Modal allowed sprint/skill")
	s.interface.close_panels()
	for message in failures: push_error(message)
	print("COMBAT_STAGE_TEST ","PASS" if failures.is_empty() else "FAIL"," · double-tap, speed, swept dash, landing slam, water cancel, skill costs/CD/hits/launch, modal focus")
	return failures.is_empty()
