extends SceneTree
var game: Node
var failed := false
var frames := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, detail: String) -> void:
	if not ok:
		failed=true
		push_error("FAIL: "+detail)
		quit(1)
func wait(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
		frames+=1
func walk(limit: int=2400) -> void:
	for i in range(limit):
		await wait(1)
		if game.route_index>=game.route.size(): return
		check(game.hero.position.y>=-0.15 and game.hero.position.y<1.4,"Ground bounds")
	print("TIMEOUT hero=",game.hero.position," target=",game.click_target," next=",game.route[game.route_index])
	check(false,"Route completed")
func run() -> void:
	Engine.time_scale=3
	game=load("res://city_3d.tscn").instantiate()
	game.saves.directory="res://art-jobs/city-08/test-saves-%d" % Time.get_ticks_usec()
	root.add_child(game)
	await wait(3)
	game.name_input.text="大城剑客"
	game.profession_input.select(1)
	game.select_slot(1)
	await wait(3)
	var counts := {}
	for mob in game.monsters:
		counts[mob.species]=counts.get(mob.species,0)+1
		check(game.walkable(Vector2(mob.home.x,mob.home.z)),"Every spawn on real ground")
		check(not game.grid.is_point_solid(game.cell_for(mob.home)),"Spawn not inside scenery")
	check(game.monsters.size()==60,"Sixty monsters")
	check(game.hero_model.root.get_meta("client_skinned",false),"Original client skinned actor active")
	for count in counts.values(): check(count==10,"Ten monsters per species")
	check(game.CITY_AREAS[0].get_area()>5000*0.8,"City enlarged")
	game.navigate_to_actor(game.master,"master")
	await walk()
	for i in range(30):
		await wait(1)
		if game.dialogue.visible: break
	check(game.dialogue.visible,"Restored town patriarch approach")
	game.dialogue.hide()
	for title in ["金香玉","韦大宝","平十指","刀剑笑","银娇龙"]:
		game.navigate_to_actor(game.town_actors[title],"npc:"+title)
		await walk()
		for i in range(30):
			await wait(1)
			if game.dialogue.visible: break
		check(game.dialogue.visible and game.dialogue_text.text.begins_with(title),"Distinct NPC reachable: "+title)
		game.dialogue.hide()
		game.update_camera(1,true)
		var screen: Vector2=game.camera.unproject_position(game.town_actors[title].position+Vector3(0,1.1,0))
		check(game.pick_at(screen).get("collider")==game.town_actors[title],"New NPC model ray collider: "+title)
	game.level=13
	game.hp=game.max_hp()
	game.exp_points=228
	game.coins=338
	game.lightness=true
	game.training_rewarded=true
	check(game.save_character(),"Sixty records save")
	check(not game.saves.read_slot(1).is_empty(),"Sixty records parse from JSON: "+game.saves.error)
	game.open_menu(false)
	game.select_slot(1)
	check(not game.menu.visible,"Restored role closes roster: "+game.menu_status.text)
	check(game.level==13 and game.exp_points==228 and game.coins==338 and game.lightness and game.training_rewarded,"High-level old character data preserved")
	# A pre-city six-monster save must remain readable and migrate one time.
	var old: Dictionary=game.snapshot()
	old.erase("city")
	old.wilderness.version=1
	old.wilderness.monsters=old.wilderness.monsters.slice(0,6)
	old.world3d.position=[4.0,0.05,2.0]
	var legacy: Dictionary=game.character.duplicate(true)
	legacy.progress=old
	check(game.saves.write_slot(2,legacy.merged({"slot":2},true)),"Old six-monster record accepted")
	game.restore(old)
	check(game.hero.position.distance_to(Vector3(9.5,0.05,5))<0.6,"Old position scales once")
	var current: Dictionary=game.snapshot()
	game.restore(current)
	check(game.hero.position.distance_to(Vector3(9.5,0.05,5))<0.6,"Reload does not double scale")
	game.navigate_to(Vector3(-49,0,3))
	await walk()
	check(game.hero.position.x < -45,"West gate traversed into large field")
	check(not game.monsters[0].aggro,"Cats passive")
	var before_hunt: int=game.hunt_kills
	game.navigate_to_actor(game.monsters[0].body,"monster:0")
	await walk()
	for i in range(150):
		await wait(1)
		if game.hunt_kills>before_hunt: break
	print("HUNT hero=",game.hero.position," mob=",game.monsters[0].body.position," hp=",game.monsters[0].hp," kills=",game.hunt_kills," target=",game.click_target," attack_cd=",game.attack_cd," hero_hp=",game.hp," paused=",game.paused," menu=",game.menu.visible," dialogue=",game.dialogue.visible," active=",game.active_slot," processing=",game.is_processing())
	check(game.hunt_kills>before_hunt,"Real hunt with scaled map")
	game.click_target=""
	game.navigate_to(Vector3(49,0,0))
	await walk()
	check(game.hero.position.x>45,"East gate traversed")
	game.navigate_to(Vector3(0,0,39))
	await walk()
	check(game.hero.position.z>35,"South gate traversed")
	game.hero.position=game.monsters[5].home+Vector3(0,0,-5)
	game.hero.velocity=Vector3.ZERO
	game.route.clear()
	await wait(20)
	check(game.monsters[5].aggro,"Wolf remains aggressive")
	game.hero.position=Vector3(0,0.05,3.5)
	game.route.clear()
	for index in range(16):
		game.yaw=TAU*index/16
		game.update_camera(1,true)
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius=0.25
		query.shape=sphere
		query.transform=Transform3D(Basis.IDENTITY,game.camera.position)
		query.collision_mask=3
		check(game.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"New city 360 camera collision")
	game.active_slot=0
	game.queue_free()
	if not failed: print("PASS: 60 monsters / 10 each, enlarged city/fields, restored client town patriarch approach, all six distinct NPCs reachable, three gates, actual hunt/AI, Lv13 experience/coins/task/lightness preservation, six-to-sixty save migration and no double coordinate scaling; frames=",frames)
	quit(1 if failed else 0)
