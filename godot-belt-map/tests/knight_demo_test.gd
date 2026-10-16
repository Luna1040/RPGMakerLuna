extends SceneTree
var failures: Array[String] = []
var stage
var runtime

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func adopt() -> void:
	stage = current_scene
	stage.set_physics_process(false)
	stage.testing_motion = true
	stage.test_input = Vector2.ZERO
	runtime = stage.runtime
	runtime.persistence_enabled = false
	runtime.panel.close()
func settle() -> void:
	for i in 5: await process_frame
	adopt()
func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	stage._unhandled_key_input(event)
func run() -> void:
	stage = load("res://stage.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	adopt()
	check(runtime.adventure.validation_errors.is_empty(),"Adventure catalog valid")
	var settings = preload("res://systems/game_settings.gd").new()
	settings.keys.skill2=KEY_Z
	settings.keys.skill3=KEY_W
	var settings_path := "user://demo-key-migration-test.cfg"
	settings.save_settings(settings_path)
	settings.load_settings(settings_path)
	check(settings.keys.skill2==KEY_W and settings.keys.skill3==KEY_A,"Old default keys migrate without collision")
	DirAccess.remove_absolute(settings_path)
	runtime.controls.keys = runtime.controls.DEFAULTS.duplicate()
	key(KEY_W)
	check(stage.knight.state == "skill_rising","W activates uppercut")
	var hp: float = stage.knight.health
	stage.knight.apply_damage(12)
	check(stage.knight.health < hp and stage.knight.state == "skill_rising","Super armor takes damage but keeps attack")
	stage.knight.elapsed = .5
	stage.knight.apply_damage(12)
	check(stage.knight.state == "hurt","Recovery is interruptible")
	stage.knight.reset_character()
	stage.knight.request_attack()
	stage.knight.fired = true
	check(stage.knight.request_skill("rising"),"Basic hit cancels into uppercut")
	stage.knight.reset_character()
	for kind in ["melee","ranged","elite","boss"]:
		var enemy: Dictionary = runtime.encounters._spawn(kind,Vector2(21,5))
		runtime.encounters._apply_hit(enemy,{"damage":1,"launch":true})
		check(enemy.reaction.airborne(),kind+" launches")
		runtime.encounters._apply_hit(enemy,{"damage":9999,"launch":true})
		var before: float = enemy.reaction.height
		runtime.encounters.step(.12)
		check(enemy.state == "dead" and enemy.reaction.height > before,kind+" lethal launch retains motion")
	runtime.encounters.clear()
	check(runtime.adventure.accept_quest("frost_patrol"),"Accept frost quest")
	check(runtime.adventure.accept_quest("ember_patrol"),"Accept ember quest")
	check(runtime.adventure.accept_quest("frost_captain"),"Accept frost boss quest")
	check(runtime.adventure.accept_quest("ember_judge"),"Accept ember boss quest")
	runtime.adventure.record_event("enemy_killed",{"id":"wrong-zone","zone":"ruins"})
	check(int(runtime.adventure.quests.frost_patrol.counts.get("objective",0))==0,"Zone objectives reject unrelated kills")
	check(runtime.travel("city"),"Travel to city")
	await settle()
	for zone in ["frost","ember"]:
		var link: Dictionary = {}
		for candidate in stage.contract.portals:
			if candidate.target == zone: link=candidate
		check(not link.is_empty(),"City portal exists: "+zone)
		check(runtime.use_portal(link),"Enter "+zone)
		await settle()
		for room in 3:
			check(runtime.zone==zone and int(stage.contract.room)==room,"Correct dungeon room")
			check(runtime.encounters.active,"Room encounter starts automatically")
			for enemy in runtime.encounters.enemies:
				check(stage.bounds.has_point(enemy.foot),"Enemy spawn inside bounds")
				runtime.encounters._apply_hit(enemy,{"damage":9999,"launch":true})
			runtime.encounters._check_cleared()
			check(not runtime.encounters.active,"Clear room opens exits")
			var exit_link: Dictionary = {}
			for candidate in stage.contract.portals:
				if candidate.target == ("room" if room<2 else "return"): exit_link=candidate
			check(runtime.use_portal(exit_link),"Advance/return portal works")
			await settle()
		check(runtime.zone=="city","Dungeon returns to city")
	for id in ["frost_patrol","ember_patrol","frost_captain","ember_judge"]:
		check(runtime.adventure._status(id)=="ready",id+" objectives complete")
		check(runtime.adventure.claim_quest(id).ok,id+" reward paid")
		check(not runtime.adventure.claim_quest(id).ok,id+" duplicate claim rejected")
	check(runtime.adventure._status("dawn_finale")=="available","Both branches unlock finale")
	runtime.panel.open("journal")
	runtime.panel.quest_filter="all"
	runtime.panel.refresh()
	check(runtime.panel.body.get_child_count()>5,"Task cards render")
	key(KEY_F9)
	check(runtime.panel.tab=="demo" and runtime.panel.is_open(),"F9 opens fast travel from journal")
	key(KEY_F9)
	check(not runtime.panel.is_open(),"F9 closes fast travel")
	var kills_before: int = int(runtime.adventure.quests.frost_patrol.counts.get("objective",0))
	for target in ["frost","ember","ruins","forest"]:
		check(runtime.demo_travel(target,2),"Demo boss teleport accepted")
		await settle()
		check(runtime.zone==target and int(stage.contract.room)==2,"Boss destination correct")
		check(runtime.encounters.active and runtime.encounters.enemies[0].kind=="boss","Boss starts immediately")
		check(stage.knight.health==stage.knight.max_health,"Teleport restores health")
	check(int(runtime.adventure.quests.frost_patrol.counts.get("objective",0))==kills_before,"Teleport awards no skipped kills")
	check(runtime.demo_travel("city"),"Can leave active battle for city")
	await settle()
	check(runtime.zone=="city" and not runtime.encounters.active,"Town teleport exits combat")
	var coins_before: int=int(stage.loot.materials.get("旧铜币",0))
	stage.loot.spawn_drop("旧铜币",7,Vector2(28,8),false)
	stage.loot._process(.61)
	check(stage.loot.drops.is_empty() and int(stage.loot.materials.get("旧铜币",0))==coins_before+7,"Distant loot automatically collected")
	for target in ["frost","ember","ruins","forest"]:
		check(runtime.demo_travel(target,2),"Enter final room for automatic completion")
		await settle()
		var gold_before: int=int(stage.loot.materials.get("旧铜币",0))
		var expected_gold: int=0
		for enemy in runtime.encounters.enemies: expected_gold+=int(enemy.reward_gold)
		var boss: Dictionary=runtime.encounters.enemies[0]
		runtime.encounters._apply_hit(boss,{"damage":99999})
		runtime.encounters._check_cleared()
		check(runtime.run_state.phase=="victory","Boss defeat clears remaining minions")
		for enemy in runtime.encounters.enemies:
			check(enemy.state=="dead" and enemy.rewarded,"Every minion dies and rewards once")
			runtime.encounters._apply_hit(enemy,{"damage":99999})
		check(stage.loot.drops.is_empty(),"Final room loot collected before return")
		check(int(stage.loot.materials.get("旧铜币",0))==gold_before+expected_gold,"Boss and minion gold granted exactly once")
		check(stage.knight.equipment.owned.has("arcane_sword"),"Boss equipment delivered to inventory")
		runtime.step(4.9)
		check(not runtime.transitioning and runtime.zone==target,"No premature return before five seconds")
		runtime.step(.11)
		await settle()
		check(runtime.zone=="city","Automatic return after five seconds")
	print("KNIGHT DEMO TEST ","PASS" if failures.is_empty() else "FAIL", " · controls, armor, all enemy launch, two dungeons, rewards and journal")
	quit(0 if failures.is_empty() else 1)
