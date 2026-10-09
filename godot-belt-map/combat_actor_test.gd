extends SceneTree
const Knight = preload("characters/first_knight/knight.gd")
var failed := false
var events: Array = []
var knight

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func tick(seconds: float) -> void:
	for i in range(int(ceil(seconds * 120.0))):
		knight._physics_process(1.0 / 120.0)

func run() -> void:
	knight = Knight.new()
	knight.equipment.persistence_enabled = false
	knight.use_local_input = false
	root.add_child(knight)
	knight.set_physics_process(false)
	for action in ["run", "dash_attack", "air_slash"]:
		for pair in knight.textures[action]:
			verify(pair[0] is Texture2D, "Missing imported texture: " + action)
	knight.attack_hitbox.connect(func(e): events.append(e))
	knight.set_running(true)
	knight.set_movement_axis(1.0)
	tick(0.02)
	verify(knight.state == "run", "Run does not select locomotion animation")
	verify(knight.position == Vector2.ZERO, "Externally controlled actor moved ground position")
	verify(knight.request_dash_attack(), "Ground locomotion rejects dash attack")
	verify(not knight.request_dash_attack(), "Repeated dash resets current attack")
	tick(0.20)
	verify(events.size() == 1 and events[0].action == "dash_attack", "Dash misses or duplicates hit event")
	tick(0.30)
	verify(events.size() == 1, "Dash damage repeats")
	knight.reset_character()
	events.clear()
	knight.clips.air_slash.hold_ms = 180.0
	knight.clips.air_slash.landing_start_ms = 300.0
	knight.set_airborne(true, 6.3)
	verify(knight.request_air_attack(), "Airborne actor rejects downward attack")
	verify(not knight.request_air_attack(), "Air attack can be restarted")
	tick(1.0)
	verify(events.is_empty() and knight.state == "air_slash", "Air slash impacts before landing")
	verify(is_equal_approx(knight.elapsed, 0.18), "Air attack ignores authored hold time")
	knight.notify_air_attack_landed(true)
	verify(is_equal_approx(knight.elapsed, 0.30), "Landing does not seek authored contact pose")
	knight.notify_air_attack_landed(true)
	verify(events.size() == 1 and events[0].shape == "radial", "Landing shockwave not emitted exactly once")
	knight.set_airborne(false, 0.0)
	tick(0.25)
	verify(knight.state == "stand", "Landing does not recover")
	knight.set_airborne(true, 6.3)
	knight.request_air_attack()
	knight.notify_air_attack_landed(false)
	verify(events.size() == 1 and knight.state == "stand", "Invalid landing deals damage")
	knight.reset_character()
	knight.set_airborne(true, 6.3)
	knight.request_cast()
	verify(knight.state == "cast" and knight.mana == 75.0, "Existing airborne K spell regressed")
	knight.reset_character()
	knight.mana = 10.0
	verify(not knight.request_skill("crescent") and knight.mana == 10.0 and knight.skill_cooldowns.crescent == 0.0, "Rejected skill spends mana or cooldown")
	knight.mana = 100.0
	knight.set_airborne(true, 6.3)
	verify(not knight.request_skill("crescent") and knight.mana == 100.0, "Airborne skill spends mana")
	knight.reset_character()
	for id in ["crescent", "rising", "trinity"]:
		knight.reset_character()
		events.clear()
		verify(knight.request_skill(id), "Valid skill rejected: " + id)
		var paid: float = knight.mana
		verify(not knight.request_skill(id) and knight.mana == paid, "Repeated skill paid twice")
		tick(1.1)
		verify(events.size() == (3 if id == "trinity" else 1), "Incorrect skill hit count: " + id)
		verify(not knight.request_skill(id), "Cooldown not enforced: " + id)
		if id == "rising":
			verify(events[0].launch, "Rising skill lacks launch tag")
		verify(is_equal_approx(float(events[0].depth_radius), float(knight.SKILLS[id].depth_radius)), "Skill depth does not match metadata")
		if id == "trinity":
			verify(events[2].damage > events[1].damage, "Trinity finisher lacks bonus damage")
	knight.reset_character()
	verify(knight.skill_cooldowns.trinity == 0.0 and not knight.running, "Reset leaves combat state")
	events.clear()
	knight.request_skill("trinity")
	tick(0.22)
	knight.apply_damage(5.0)
	tick(1.0)
	verify(events.size() == 1, "Interrupted multihit skill continues dealing damage")
	knight.reset_character()
	events.clear()
	knight.request_attack()
	tick(0.20)
	var mana_before: float = knight.mana
	verify(not knight.request_skill("crescent") and knight.mana == mana_before, "Normal attack can be cancelled into paid skill")
	knight.request_attack()
	tick(1.10)
	verify(events.size() == 2 and events[0].action == "attack1" and events[1].action == "attack2", "Normal combo regressed")
	print("COMBAT_ACTOR_TEST " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
