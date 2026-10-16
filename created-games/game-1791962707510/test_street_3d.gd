extends SceneTree

var game: Node
var frames := 0

func _initialize() -> void:
	call_deferred("run_checks")

func wait_frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		frames += 1

func walk_until_done(limit: int = 1000) -> void:
	for i in range(limit):
		await wait_frames(1)
		assert(game.hero.position.y > -0.2 and game.hero.position.y < 1.0,"Grounded body stays below visual leap")
		for obstacle in game.obstacles:
			assert(not obstacle.has_point(Vector2(game.hero.position.x,game.hero.position.z)),"No wall or building penetration")
		if game.route_index>=game.route.size(): return
	assert(false,"Path timed out")

func run_checks() -> void:
	game = load("res://street_3d.tscn").instantiate()
	game.saves.directory="res://art-jobs/3d-test-%d" % Time.get_ticks_usec()
	root.add_child(game)
	await wait_frames(3)
	assert(game.world is Node3D and game.hero is CharacterBody3D and game.camera is Camera3D)
	assert(game.slot_buttons.size()==6)
	game.name_input.text="江湖三维侠客"
	game.select_slot(1)
	await wait_frames(3)
	assert(game.active_slot==1 and game.hero.position.y>=-0.1)
	# World picking uses actual physics colliders, not hard-coded screen targets.
	var screen: Vector2 = game.camera.unproject_position(game.master.position+Vector3(0,1.1,0))
	var picked: Dictionary = game.pick_at(screen)
	assert(not picked.is_empty() and picked.collider==game.master,"NPC ray picking")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = screen
	game._unhandled_input(mouse)
	assert(game.click_target=="master")
	await walk_until_done()
	await wait_frames(5)
	assert(game.training_state==1 and game.hero.position.distance_to(game.master.position)<1.8,"NPC click -> path -> proximity dialogue")
	game.dialogue.hide()
	var old_route = game.route.duplicate()
	game.click_world(Vector2(40,40))
	assert(game.route==old_route,"HUD click cannot move hero")
	mouse.button_index=MOUSE_BUTTON_RIGHT
	mouse.position=Vector2(700,350)
	game._unhandled_input(mouse)
	assert(game.dragging)
	var initial_yaw: float=game.yaw
	var motion := InputEventMouseMotion.new()
	motion.relative=Vector2(50,25)
	game._input(motion)
	assert(game.yaw!=initial_yaw and game.route==old_route,"Right drag only changes orbit")
	mouse.pressed=false
	game._input(mouse)
	assert(not game.dragging)
	# A courtyard wall blocks the straight route; navigate around its end.
	game.hero.position=Vector3(-2,0.05,3)
	game.hero.velocity=Vector3.ZERO
	game.navigate_to(Vector3(-8,0,3))
	var went_around := false
	for point in game.route:
		if point.y < -0.1 or point.y > 6: went_around=true
	assert(went_around,"A* routes around courtyard wall")
	await walk_until_done()
	assert(Vector2(game.hero.position.x,game.hero.position.z).distance_to(Vector2(-8,3))<0.3)
	# Walk a physical slope and arrive on the raised terrace.
	game.hero.position=Vector3(9.5,0.05,8)
	game.hero.velocity=Vector3.ZERO
	game.navigate_to(Vector3(9.5,0.6,3))
	await walk_until_done()
	await wait_frames(10)
	assert(game.hero.position.y>0.5 and game.hero.position.y<0.75,"Walkable ramp floor height")
	# Leap changes only visual height; physics body remains grounded.
	var ground_y: float = game.hero.position.y
	game.begin_leap()
	await wait_frames(18)
	assert(game.hero_model.root.position.y>0.4 and abs(game.hero.position.y-ground_y)<0.08)
	game.begin_leap()
	await wait_frames(65)
	assert(game.leap_remaining==0 and abs(game.hero_model.root.position.y)<0.01,"Leap returns to floor")
	assert(abs(game.shadow.position.y-game.hero.position.y-0.065)<0.02)
	game.hero.position=Vector3(-9,0.05,9.5)
	game.hero.velocity=Vector3.ZERO
	await wait_frames(3)
	game.navigate_to(Vector3(-9,0.45,6.75))
	await walk_until_done()
	await wait_frames(5)
	assert(game.hero.position.y>0.4 and game.hero.position.y<0.6,"Traversable 15 cm steps; no free vertical flight")
	# Complete orbit, pitch/zoom clamps, retained angle after release.
	var angle: float = game.yaw
	game.rotate_camera(Vector2(TAU/0.006,0))
	assert(abs(wrapf(game.yaw-angle,-PI,PI))<0.001)
	game.rotate_camera(Vector2(100,99999))
	assert(is_equal_approx(game.pitch,deg_to_rad(68)))
	game.rotate_camera(Vector2(0,-99999))
	assert(is_equal_approx(game.pitch,deg_to_rad(28)))
	game.zoom_camera(-999)
	assert(game.zoom==6)
	game.zoom_camera(999)
	assert(game.zoom==20)
	game.dragging=false
	angle=game.yaw
	await wait_frames(2)
	assert(game.yaw==angle)
	# Face camera toward the hall: shape sweep must shorten before its roof/wall.
	game.hero.position=Vector3(0,0.05,-1.6)
	game.camera_anchor=game.hero.position+Vector3(0,1.3,0)
	game.yaw=PI
	game.pitch=deg_to_rad(28)
	game.zoom=20
	await wait_frames(2)
	game.update_camera(1,true)
	assert(game.actual_zoom<10,"Camera sphere sweep avoids the hall")
	assert(game.camera.position.y>0.4,"Camera cannot go underground")
	for i in range(16):
		game.yaw=TAU*i/16
		game.update_camera(1,true)
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius=0.24
		query.shape=sphere
		query.transform=Transform3D(Basis.IDENTITY,game.camera.position)
		query.collision_mask=3
		assert(game.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"No camera intersection throughout 360 orbit")
	# Real enemy click travels to range and resolves repeated attacks.
	game.hero.position=Vector3(0,0.05,3.5)
	game.camera_anchor=game.hero.position+Vector3(0,1.3,0)
	game.yaw=0
	game.pitch=deg_to_rad(48)
	game.zoom=13
	game.update_camera(1,true)
	await wait_frames(2)
	screen=game.camera.unproject_position(game.practice.position+Vector3(0,1.1,0))
	picked=game.pick_at(screen)
	assert(not picked.is_empty() and picked.collider==game.practice)
	game.click_world(screen)
	for i in range(800):
		await wait_frames(1)
		if game.enemy_health<=0: break
	assert(game.enemy_health==0 and game.practice_hits>0 and game.training_state==2,"Click enemy -> approach -> normal attack")
	game.navigate_to(game.master.position+Vector3(0,0,1.3),"master")
	await walk_until_done()
	await wait_frames(10)
	assert(game.training_rewarded and game.training_state==3 and game.coins==50)
	game.talk_master()
	assert(game.coins==50,"Reward is idempotent")
	# Retain a legacy save with an in-progress quest and enemy state.
	var legacy = load("res://town_game.gd").new()
	legacy.reset_game()
	legacy.stage=2
	legacy.quest_accepted=true
	legacy.spawn_wave()
	legacy.enemies[0].hp=31
	legacy.level=3
	legacy.coins=81
	var data: Dictionary=legacy.snapshot()
	legacy.free()
	game.restore(data)
	assert(game.stage==2 and game.enemies[0].hp==31 and game.quest_accepted and game.level==3)
	assert(game.snapshot().legacy2d==data,"Old complete quest data retained verbatim")
	game.training_state=1
	game.enemy_health=64
	game.yaw=1.7
	game.hero.position=Vector3(3,0.05,4)
	assert(game.save_character())
	var record: Dictionary=game.saves.read_slot(1)
	assert(record.name=="江湖三维侠客" and record.level==3 and record.progress.world3d.enemy_hp==64)
	assert(record.progress.legacy2d==JSON.parse_string(JSON.stringify(data)),"Legacy record survives JSON numeric normalization")
	game.restore(record.progress)
	assert(game.enemy_health==64 and abs(game.yaw-1.7)<0.001 and game.hero.position.x==3)
	assert(game.map_position(Vector3(-15,0,-12))==Vector2(1053,54))
	assert(game.map_position(Vector3(15,0,12))==Vector2(1233,184))
	print("PASS 3D: physics ray clicks, NPC approach/dialogue, enemy approach/attack, wall detour, ramp grounding, leap landing, 360 orbit, pitch/zoom limits, camera roof collision, HUD isolation, minimap, reward once, legacy quest preservation, six-slot disk roundtrip")
	print("PHYSICS_FRAMES: ",frames)
	print("TEST_ARTIFACTS: ",game.saves.directory)
	game.active_slot=0
	game.queue_free()
	quit(0)
