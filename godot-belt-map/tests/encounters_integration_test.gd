extends SceneTree
## Run with --script tests/encounters_integration_test.gd -- --foundations.
## Exercises the real stage, actor events and composition root, including scene handoff.
var failures: Array[String] = []
var stage
var runtime
var encounters
var seed_value := 8301

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func adopt() -> void:
	stage = current_scene
	stage.set_physics_process(false)
	stage.testing_motion = true
	stage.test_input = Vector2.ZERO
	runtime = stage.runtime
	runtime.persistence_enabled = false
	encounters = runtime.encounters

func advance(seconds: float) -> void:
	for i in int(ceil(seconds*60.0)):
		stage._physics_process(1.0/60.0)

func fresh_battle() -> Dictionary:
	stage.interface.close_panels()
	stage.knight.reset_character()
	stage.hit_pause = 0
	stage.foot = Vector2(21,4)
	stage.height_z = 0
	stage.grounded = true
	stage.vertical_speed = 0
	stage.sprint.reset()
	stage.test_input = Vector2.ZERO
	for shot in stage.projectiles: shot.node.queue_free()
	stage.projectiles.clear()
	encounters.clear()
	seed_value += 1
	runtime.run_state = {"phase":"ready","wave":0,"seed":seed_value,"boons":[],"offers":[]}
	runtime.death_pending = false
	check(runtime.start_wave(),"root must start a wave in ruins")
	for i in encounters.enemies.size():
		var enemy: Dictionary = encounters.enemies[i]
		enemy.foot = Vector2(22+i,4+i*1.8)
		enemy.home = enemy.foot
		enemy.state = "recover"
		enemy.timer = 999.0
	stage._physics_process(0.001)
	return encounters.enemies[0]

func event_count(kind: String) -> int:
	var count := 0
	for event: Dictionary in runtime.events.trace:
		if event.kind == kind: count += 1
	return count

func run() -> void:
	stage = preload("res://stage.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	adopt()
	check(runtime != null,"--foundations must enable composition root")
	if runtime == null:
		quit(1)
		return
	check(not encounters.companion_enabled,"unrecruited ally must remain disabled")
	check(runtime.adventure.accept_quest("courtyard_menace"),"enemy quest should accept in town")
	check(runtime.adventure.accept_quest("clearance_waves"),"wave quest should accept in town")
	check(runtime.start_trial(seed_value),"town to ruins scene route should begin")
	await process_frame
	await process_frame
	adopt()
	check(runtime.zone == "ruins" and stage.contract.zone_id == "ruins","scene handoff must use ruins contract and state")
	check(stage.townsfolk.residents.is_empty(),"ruins must not retain town NPCs")
	check(stage.practice.targets.is_empty(),"ruins must not retain practice targets")
	check(stage.interface.is_modal(),"ruins arrival should open pre-wave menu")
	check(runtime.start_wave(),"arrival ready state must start wave one")
	for enemy: Dictionary in encounters.enemies:
		check(stage.bounds.has_point(enemy.foot) and not stage.Physics.blocked(stage.volumes,enemy.foot,0),"spawn must be walkable within map")
		check(absf(stage.project(enemy.foot).x-stage.camera.position.x) <= 640,"spawn must fit arrival horizontal camera")
	check(not stage.interface.is_modal() and runtime.run_state.phase == "combat","wave start should close menu and begin combat")
	# Exercise actor events in BOTH new dungeon regions, not just the old east arena.
	for zone_name in ["ruins", "forest"]:
		stage.contract.zone_id = zone_name
		for action in ["attack", "crescent", "rising", "trinity", "magic"]:
			var target: Dictionary = fresh_battle()
			stage.foot = Vector2(5,7) if zone_name == "ruins" else Vector2(16,7)
			target.foot = stage.foot + Vector2(1,0)
			target.home = target.foot
			if action == "attack": stage.context_attack()
			elif action == "magic": stage.use_spell()
			else: stage.use_skill(action)
			advance(0.4 if action == "rising" else 1.1)
			check(target.hp < target.max_hp, zone_name+": real "+action+" must damage enemy")
			if action == "rising": check(target.reaction.airborne(), zone_name+": uppercut launches")
			if action == "magic": check(target.reaction.shock_left > 0, zone_name+": spell shocks")
		var mobile: Dictionary = fresh_battle()
		stage.foot = Vector2(5,7) if zone_name == "ruins" else Vector2(16,7)
		mobile.foot = stage.foot + Vector2(2.5,0)
		mobile.home = mobile.foot
		mobile.state = "idle"
		mobile.timer = 0
		var before_hp: float = stage.knight.health
		advance(4.0)
		check(mobile.attacks > 0 and stage.knight.health < before_hp, zone_name+": enemy must approach and damage player")
	stage.contract.zone_id = "ruins"
	var enemy: Dictionary = fresh_battle()
	stage.context_attack()
	advance(0.6)
	check(enemy.hp < enemy.max_hp,"real J animation event must damage an encounter enemy")
	enemy = fresh_battle()
	enemy.foot = Vector2(23,4)
	stage.sprint.active = true
	stage.context_attack()
	check(stage.knight.state == "dash_attack","context attack while sprinting must choose dash")
	advance(0.42)
	check(enemy.hp < enemy.max_hp,"dash animation must damage real encounter enemy")
	check(stage.foot.x > 21.4,"dash attack must translate hero in real stage")
	enemy = fresh_battle()
	stage.use_skill("rising")
	advance(0.4)
	check(enemy.reaction.airborne(),"real rising skill must launch encounter enemy")
	enemy = fresh_battle()
	enemy.foot = Vector2(23,4)
	stage.use_spell()
	advance(0.95)
	check(enemy.hp < enemy.max_hp,"real cast release height must hit grounded encounter enemy")
	check(enemy.reaction.shock_left > 0,"actual player spell must apply shock")
	enemy = fresh_battle()
	enemy.foot = Vector2(23.3,4)
	var wall := {"id":"integration-wall","kind":"wall","x":22.15,"depth":3.0,"width":0.4,"depth_size":2.0,"base_z":0.0,"height":3.0,"solid":true,"standable":false}
	stage.volumes.append(wall)
	stage.use_spell()
	advance(1.0)
	check(enemy.hp == enemy.max_hp and stage.projectiles.is_empty(),"real moving spell must be absorbed by a wall before reaching enemy")
	stage.volumes.erase(wall)
	enemy = fresh_battle()
	enemy.state = "chase"
	stage.context_attack()
	advance(0.03)
	runtime.panel.open("adventure")
	var health: float = stage.knight.health
	var enemy_hp: float = enemy.hp
	var clock: float = enemy.clock
	var elapsed: float = stage.knight.elapsed
	advance(3.0)
	check(stage.knight.health == health and enemy.hp == enemy_hp,"modal must freeze both outgoing and incoming damage")
	check(enemy.clock == clock and stage.knight.elapsed == elapsed,"modal must freeze actor and encounter clocks")
	runtime.panel.close()
	advance(0.5)
	check(enemy.clock > clock and stage.knight.elapsed != elapsed,"closing modal must resume combat")
	enemy = fresh_battle()
	enemy.state = "chase"
	stage.foot = Vector2(-2,4)
	for tick in 180: encounters._step_enemy(enemy,1.0/60.0)
	check(enemy.state in ["idle","return"],"enemy should leash back when hero leaves dungeon bounds")
	check(enemy.foot.x > 18.5,"leashed enemy must not chase into town half")
	fresh_battle()
	for wave in range(1,4):
		if wave > 1:
			check(runtime.run_state.phase == "boon","cleared non-final wave must offer boon")
			check(runtime.choose_boon(runtime.run_state.offers[0]),"valid boon should prepare next wave")
			check(runtime.start_wave(),"next wave should start after boon")
		for victim: Dictionary in encounters.enemies.duplicate():
			if victim.state == "dead": continue
			stage.foot = victim.foot-Vector2(0.6,0)
			stage.on_attack({"action":"attack1","facing":1,"range":200,"damage":9999})
		check(not encounters.active,"defeating all enemies should stop wave")
	check(runtime.run_state.phase == "victory","third wave should produce victory state")
	check(runtime.adventure.quests.courtyard_menace.counts.enemies == 3,"unique real enemy kills should complete quest")
	check(runtime.adventure.quests.clearance_waves.counts.waves == 3,"three actual wave clears should complete quest")
	check(event_count("boss_killed") == 1,"one actual boss must publish one boss identity")
	var identities: Array = []
	for event: Dictionary in runtime.events.trace:
		if event.kind == "enemy_killed":
			check(event.data.id not in identities,"enemy quest event identity must be unique within run")
			identities.append(event.data.id)
	check(runtime.progression.xp > 0 or runtime.progression.level > 1,"kills should grant progression XP")
	check(not stage.loot.drops.is_empty(),"kills should spawn tangible loot")
	enemy = fresh_battle()
	enemy.state = "telegraph"
	enemy.timer = 0.01
	enemy.attack_origin = enemy.foot
	enemy.attack_facing = -1
	enemy.attack_variant = "melee"
	stage.knight.health = 1
	stage._physics_process(0.02)
	check(stage.knight.defeated and runtime.death_pending,"actual hostile strike should queue hero defeat")
	stage._physics_process(0.02)
	check(runtime.run_state.phase == "defeat" and stage.interface.is_modal(),"next stage step must show defeat menu")
	check(not encounters.active and encounters.enemies.is_empty(),"defeat processing must clear hostile actors")
	check(event_count("player_died") == 1,"hero defeat must be published once")
	fresh_battle()
	stage.knight.apply_damage(9999)
	runtime.panel.open("adventure")
	stage._physics_process(0.02)
	check(runtime.run_state.phase == "defeat" and not runtime.death_pending,"opening a menu between death and next tick must not suppress defeat processing")
	for message in failures: push_error(message)
	print("ENCOUNTERS_INTEGRATION_TEST ","PASS" if failures.is_empty() else "FAIL"," · real scene route, camera/spawns, attack/dash/launch/cast, modal freeze, leash, three-wave quest and loot, defeat modal")
	stage.queue_free()
	await process_frame
	# AudioStreamPlayer.stop() is handed to the audio mixer thread. This test
	# simulates many seconds without wall-clock waits; allow pending stop/free
	# requests to finish before tearing down the engine's audio driver.
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)
