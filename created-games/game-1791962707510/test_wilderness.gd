extends SceneTree
var game: Node
var frames := 0
var failed := false
func _initialize() -> void:
	call_deferred("run")
func verify(ok: bool, detail: String) -> void:
	if not ok:
		failed=true
		push_error("FAIL: "+detail)
		quit(1)
		assert(ok,detail)
func wait(count: int) -> void:
	for i in range(count):
		await physics_frame
		frames+=1
func walk() -> void:
	for i in range(1600):
		await wait(1)
		verify(game.hero.position.y>=-0.15 and game.hero.position.y<0.9,"Ground constraints")
		for obstacle in game.obstacles:
			verify(not obstacle.has_point(Vector2(game.hero.position.x,game.hero.position.z)),"No new-wall penetration")
		if game.route_index>=game.route.size(): return
	print("TIMEOUT at=",game.hero.position," next=",game.route[game.route_index]," target=",game.click_target," hp=",game.hp)
	verify(false,"Click path timed out")
func run() -> void:
	Engine.time_scale=3
	game=load("res://wilderness_3d.tscn").instantiate()
	game.saves.directory="res://art-jobs/wilderness-06/test-saves-%d" % Time.get_ticks_usec()
	root.add_child(game)
	await wait(3)
	game.name_input.text="三门历练侠客"
	game.select_slot(1)
	await wait(3)
	verify(game.monsters.size()==6,"Six actual creatures")
	for i in range(6):
		verify(game.monsters[i].level==[3,5,7,11,10,12][i],"Monster levels")
		verify(game.monsters[i].aggressive==(i==5),"Only wolf aggressive")
		verify(game.monsters[i].visual.get_node("Leg0")!=null,"Real animal model")
	game.navigate_to(Vector3(-22,0,3))
	verify(not game.route.is_empty(),"West gate path exists")
	await walk()
	verify(game.hero.position.x < -20,"West gate actually traversed")
	verify(not game.monsters[0].aggro,"Passive cat does not initiate")
	game.hero.position=Vector3(-21,0.05,3)
	game.hero.velocity=Vector3.ZERO
	await wait(2)
	game.zoom=9
	game.update_camera(1,true)
	var mob: Dictionary=game.monsters[0]
	var screen: Vector2=game.camera.unproject_position(mob.body.position+Vector3(0,0.65,0))
	verify(game.pick_at(screen).get("collider")==mob.body,"Mouse ray picks monster")
	game.click_world(screen)
	verify(game.click_target=="monster:0","Mouse click creates attack target")
	for i in range(450):
		await wait(1)
		if mob.dead: break
	verify(mob.dead and game.exp_points==66,"Click approach -> attacks -> kill -> XP")
	var xp: int=game.exp_points
	game.attack_cd=0
	game.attack_monster(0)
	verify(game.exp_points==xp,"Dead target cannot award XP twice")
	var data: Dictionary=game.snapshot()
	verify(game.save_character(),"New world data saves")
	game.restore(data)
	verify(game.monsters[0].dead,"Dead timer survives load")
	verify(game.hero.position.x < -20,"Outdoor location survives load")
	game.monsters[0].respawn=0.1
	for i in range(120):
		await wait(1)
		if not game.monsters[0].dead: break
	verify(not game.monsters[0].dead,"Monster respawns")
	game.hp=40
	var here: Vector3=game.hero.position
	var key := InputEventKey.new()
	key.keycode=KEY_C
	key.ctrl_pressed=true
	key.pressed=true
	game._unhandled_input(key)
	verify(game.meditating,"Ctrl+C activates meditation")
	await wait(35)
	verify(game.hp>40 and game.hero.position.distance_to(here)<0.01,"Meditation heals while stationary")
	game.hp=game.max_hp()-1
	await wait(15)
	verify(game.hp==game.max_hp() and not game.meditating,"Meditation stops at full HP")
	game.hp=80
	game.toggle_meditation()
	game.navigate_to(Vector3(-20,0,4))
	verify(not game.meditating,"Movement cancels meditation")
	game.level=9
	game.exp_points=0
	game.begin_leap()
	verify(not game.lightness and game.movement_speed()==3.6,"Lv9 lightness locked")
	game.gain_experience(game.xp_needed())
	verify(game.level==10 and game.hp==345 and game.attack_power()==69 and game.defense_power()==20,"Level upgrade increases all stats")
	game.begin_leap()
	verify(game.lightness and game.movement_speed()==7.2,"Lv10 doubles speed")
	await wait(30)
	verify(game.leap_remaining==0 and game.hero_model.root.position.y==0,"Visual leap lands")
	verify(game.save_character(),"Lv10 save permitted")
	game.open_menu(false)
	game.select_slot(1)
	verify(game.level==10 and game.lightness,"Level and lightness restored")
	game.navigate_to(Vector3(23,0,5))
	await walk()
	verify(game.hero.position.x>22 and not game.monsters[4].aggro,"East gate traversed, bull passive")
	game.navigate_to(Vector3(0,0,18))
	await walk()
	verify(game.hero.position.z>17,"South gate traversed")
	game.hero.position=Vector3(-3,0.05,21)
	game.route.clear()
	await wait(8)
	verify(game.monsters[5].aggro,"Wolf initiates attack")
	game.hp=50
	game.toggle_meditation()
	game.hero.position=game.monsters[5].body.position+Vector3(0,0,1.2)
	game.monsters[5].cool=0
	game.monsters[5].wind=0
	for i in range(120):
		await wait(1)
		if not game.meditating: break
	verify(game.hp<70 and not game.meditating,"Wolf damage interrupts meditation after healing during windup")
	game.hp=0
	key.ctrl_pressed=false
	key.keycode=KEY_R
	game._unhandled_input(key)
	verify(game.hp==game.max_hp() and game.hero.position.z==3.5 and game.level==10,"Death retry returns town, retains level")
	for i in range(16):
		game.yaw=TAU*i/16
		game.update_camera(1,true)
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius=0.25
		query.shape=sphere
		query.transform=Transform3D(Basis.IDENTITY,game.camera.position)
		query.collision_mask=3
		verify(game.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"Expanded world 360 camera collision")
	game.open_menu(false)
	game.name_input.text="新侠客"
	game.select_slot(2)
	verify(game.level==1 and not game.lightness and game.hunt_kills==0 and game.hero.position.x==0,"New role does not inherit world")
	game.click_world(Vector2(400,185))
	verify(game.route.is_empty(),"XP UI click cannot move")
	var before: float=game.hp
	game.hero.position=Vector3(22,0.05,5)
	game.update_camera(1,true)
	game.navigate_to_actor(game.monsters[4].body,"monster:4")
	await walk()
	for i in range(120):
		await wait(1)
		if game.monsters[4].aggro: break
	verify(game.monsters[4].aggro,"Passive bull retaliates after attack")
	game.level=1
	game.exp_points=0
	game.gain_experience(250)
	verify(game.level==3 and game.exp_points==60 and game.max_hp()==170,"Multiple level thresholds retain surplus XP")
	game.active_slot=0
	game.queue_free()
	if not failed: print("PASS: three actual gate traversals, six monster levels/AI, ray-click attack/XP, level stats, meditation input/heal/interruption, Lv10 lightness, grounded landing, save/load/new role, death recovery, UI isolation; frames=",frames)
	quit(1 if failed else 0)
