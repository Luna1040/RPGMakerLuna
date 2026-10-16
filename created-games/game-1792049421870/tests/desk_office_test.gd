extends "res://tests/desk_test_driver.gd"
func _initialize() -> void:call_deferred("run")
func run() -> void:
	await spawn_game(123)
	check(game.office.get_parent()==game and game.office.name=="office_root","office isolated")
	check(game.props.size()==game.homes.size(),"no NPC gameplay props")
	var colliders:Array=game.office.find_children("*","CollisionObject3D",true,false)
	check(colliders.is_empty(),"no NPC ray collision theft")
	check(game.office.boss.get_node("body/arm1/elbow/wrist/hand").get_child_count()>=6,"articulated hands and fingers")
	var different:Array[float]=[]
	for seed_value in [1,7,19,42]:
		game.patrol.reset(seed_value);different.append(game.patrol.free_remaining)
		check(game.patrol.free_remaining>=20 and game.patrol.free_remaining<=30,"seed range")
	check(different[0]!=different[1] and different[1]!=different[2],"independent random intervals")
	for i in range(300):
		var p:Vector3=game.office.route_point(float(i)/299)
		for r in game.office.obstacles:check(not r.grow(.18).has_point(Vector2(p.x,p.z)),"route clears desks body radius")
	# Actual joints in world space, recursive reflection exclusion, smooth route + chair.
	for actor in [game.office.boss,game.office.coworker]:
		for side in [-1,1]:
			var wrist:Node3D=actor.get_node("body/arm"+str(side)+"/elbow/wrist")
			var keyboard:Vector3=game.office.coworker_keyboard if actor==game.office.coworker else Vector3(.42,.795,-1.94)
			check(absf(wrist.global_position.y-keyboard.y)<.04 and absf(wrist.global_position.z-keyboard.z)<.10,"hand at real keyboard")
			var shoe:Node3D=actor.get_node("body/leg"+str(side)+"/knee/ankle/shoe")
			check(absf(shoe.global_position.y-.07)<.01,"shoe sole grounded")
	for node in [game.office.boss,game.office.coworker,game.office.boss_chair]:
		for mesh in node.find_children("*","VisualInstance3D",true,false):check(mesh.layers==2,"dynamic subtree excluded from static probe")
	# Physical geometry + projections at the original frozen camera, normal limits.
	var camera_base:Transform3D=game.camera.transform
	game.office.pose("checking",0)
	var projection_record:Dictionary={}
	for label in ["default","left_up"]:
		if label=="left_up":game.camera.rotation=Vector3(-.4+deg_to_rad(10),deg_to_rad(15),0)
		var head:Vector3=game.office.boss.global_position+Vector3(0,1.60,0)
		var chest:Vector3=game.office.boss.global_position+Vector3(0,1.15,0)
		var hp:Vector2=game.camera.unproject_position(head);var cp:Vector2=game.camera.unproject_position(chest)
		projection_record[label]={"head":[hp.x,hp.y],"chest":[cp.x,cp.y],"camera":str(game.camera.transform)}
		check(not game.camera.is_position_behind(chest) and Rect2(20,20,1240,760).has_point(cp),"checking chest in normal "+label)
		if label=="left_up":check(Rect2(20,20,1240,760).has_point(hp),"checking head visible at normal left/up limit")
	game.camera.transform=camera_base
	var file:=FileAccess.open("user://desk-office-projection.json",FileAccess.WRITE);file.store_string(JSON.stringify(projection_record,"  "));file.close()
	for actor in [game.office.boss,game.office.coworker]:
		for path in ["body/head/face_contour","body/head/hair_cap","body/torso"]:
			var mesh:MeshInstance3D=actor.get_node(path)
			var arrays:Array=mesh.mesh.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_TANGENT].size()==arrays[Mesh.ARRAY_VERTEX].size()*4,"contour tangent frame "+path)
			for index in range(arrays[Mesh.ARRAY_VERTEX].size()):
				var vertex:Vector3=arrays[Mesh.ARRAY_VERTEX][index];var normal:Vector3=arrays[Mesh.ARRAY_NORMAL][index]
				if vertex.z>.045 and absf(vertex.x)<.025 and absf(normal.y)<.8:check(normal.z>0,"contour facial/chest normals point outward")
			for index in range(0,arrays[Mesh.ARRAY_VERTEX].size(),3):
				var a:Vector3=arrays[Mesh.ARRAY_VERTEX][index];var b:Vector3=arrays[Mesh.ARRAY_VERTEX][index+1];var c:Vector3=arrays[Mesh.ARRAY_VERTEX][index+2]
				var expected:Vector3=(arrays[Mesh.ARRAY_NORMAL][index]+arrays[Mesh.ARRAY_NORMAL][index+1]+arrays[Mesh.ARRAY_NORMAL][index+2]).normalized()
				check((c-a).cross(b-a).normalized().dot(expected)>.60,"contour front winding and finite normals")
	game.office.pose("free",0)
	var previous_yaw:float=game.office.boss.rotation.y
	game.phase="warning"
	for frame in range(721):
		game.phase_clock=float(frame)/60;game.office.pose("warning",float(frame)/720,1.0/60);game.office_audio.tick(1.0/60)
		check(absf(wrapf(game.office.boss.rotation.y-previous_yaw,-PI,PI))<.37,"no yaw snap")
		previous_yaw=game.office.boss.rotation.y
		if frame>150:
			var p:Vector3=game.office.boss.position;var chair:Vector3=game.office.boss_chair.position
			check(absf(p.x-chair.x)>.43 or absf(p.z-chair.z)>.37,"walking clears chair and body radius")
		check(game.office_audio.steps.global_position.distance_to(game.office.boss.global_position+Vector3(0,.065,0))<.001,"audio position same frame as boss")
	game.phase="checking";var steps_before:int=game.office_audio.step_count
	advance(.5);check(game.office_audio.step_count==steps_before and not game.office_audio.steps.playing,"checking footsteps stopped")
	game.phase="returning";game.phase_clock=0
	var prior_distance:float=game.office.boss.position.distance_to(game.camera.position)
	for frame in range(601):
		game.office.pose("returning",float(frame)/600,1.0/60)
		var distance:float=game.office.boss.position.distance_to(game.camera.position)
		if frame in [180,300,420]:check(distance>2,"return footsteps farther along route")
		if frame==600:check(distance>2.7,"returned footstep farther than inspection")
		prior_distance=distance
	game.phase="free";game.office.pose("free",0)
	game.patrol.reset(123)
	var remaining:float=game.patrol.free_remaining
	key(KEY_ESCAPE);advance(8);check(game.patrol.free_remaining==remaining and game.phase=="paused","pause patrol freezes")
	key(KEY_ESCAPE)
	game.office_audio.air.play();game.office_audio.typing.stream=game.office_audio.wav("key0");game.office_audio.typing.play();game.office_audio.steps.stream=game.office_audio.wav("step0");game.office_audio.steps.play()
	# 3D play() starts on the next audio/physics update; pause a real playback,
	# rather than querying the pending-play state before a playback exists.
	await physics_frame;await physics_frame
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT);advance(8)
	check(game.patrol.free_remaining==remaining and game.office_audio.muted and game.office_audio.air.stream_paused and game.office_audio.typing.stream_paused and game.office_audio.steps.stream_paused,"focus audio and patrol freeze")
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN);game.begin()
	# Warning cannot punish unfinished tasks, arrival requires physical hiding only.
	advance(remaining+.02);check(game.phase=="warning" and not game.pocket.won,"warning fair no failure")
	await hide_evidence()
	for visit in range(1,4):
		advance(12-game.phase_clock+.02)
		if visit<3:
			check(game.phase=="checking" and not game.pocket.won,"unfinished early check allowed")
			advance(4.05);check(game.phase=="returning","check returns")
			await click("drawer");check(not game.drawer_open,"returning refuses click")
			advance(game.patrol.RETURN+.1);check(game.phase=="free","back seat free")
			check(game.patrol.free_remaining>=20 and game.patrol.free_remaining<=30,"next range")
			advance(game.patrol.free_remaining+.01);check(game.phase=="warning","next warning")
		else:check(game.phase=="lost" and game.result_text.text.contains("任务未完成"),"third unfinished lists task failure")
	check(game.patrol.visit==3 and game.patrol.intervals.size()==3,"no fourth")
	await clean();await spawn_game(42)
	game._process(10000);check(game.phase=="warning","large delta no skipped check")
	game._process(10000);check(game.phase=="lost" and not game.result_text.text.contains("任务未完成"),"arrival exposed early no task blame")
	game.reset_game();await process_frame;await physics_frame
	game=current_scene;game.set_process(false);game.begin()
	check(game.patrol.visit==0 and game.patrol.intervals.size()==1 and game.visits_passed==0,"real restart resets patrol")
	check(game.office_audio.get_child_count()==3,"restart audio players not stacked")
	await clean()
	if failures.is_empty():print("DESK_OFFICE_PASS office_articulation_route random_seeds pause_focus first_two_unfinished third_requirement large_delta restart_audio");quit(0)
	else:print("DESK_OFFICE_FAILED ",failures);quit(1)
