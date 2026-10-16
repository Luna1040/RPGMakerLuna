extends SceneTree
var game:Node3D
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,msg:String) -> void:
	if not ok:failures.append(msg);push_error("DESK_INPUT_FAIL "+msg)
func wait(t:float=.5) -> void:await create_timer(t).timeout;await physics_frame
func button(index:int,pressed:bool,p:Vector2) -> void:
	var e:=InputEventMouseButton.new();e.button_index=index;e.pressed=pressed;e.position=p;game._unhandled_input(e)
func move(p:Vector2,rel:Vector2=Vector2.ZERO) -> void:
	var e:=InputEventMouseMotion.new();e.position=p;e.relative=rel;game._unhandled_input(e)
func point(id:String) -> Vector2:return game.camera.unproject_position(game.props[id].global_position+Vector3(0,.015,0))
func tick(seconds:float,hz:int=60) -> void:
	for i in range(int(seconds*hz)):game._process(1.0/hz)
func right_tap(p:Vector2) -> void:button(MOUSE_BUTTON_RIGHT,true,p);tick(.05);button(MOUSE_BUTTON_RIGHT,false,p)
func run() -> void:
	game=load("res://main.tscn").instantiate();root.add_child(game);current_scene=game;await wait(.15)
	game.begin();game.set_process(false);game.pocket.set_physics_process(false)
	var base:Transform3D=game.camera.transform
	move(Vector2(650,405));tick(.2)
	check(game.camera.transform.is_equal_approx(base),"small stable centre")
	move(Vector2(1130,630));tick(.2)
	check(game.camera.transform.basis!=base.basis,"mouse follows without right button")
	check(absf(game.camera.rotation.z)<.025,"no head roll")
	var stopped:Transform3D=game.camera.transform;tick(.25)
	check(game.camera.global_position==stopped.origin,"stationary no head translation")
	for i in range(20):button(MOUSE_BUTTON_WHEEL_UP,true,Vector2(600,400))
	tick(.35)
	check(game.controls.target_dolly==.26 and game.camera.position.y>1.09,"dolly forward clamped above desk")
	check(game.camera.fov==54,"fixed FOV dolly")
	for i in range(30):button(MOUSE_BUTTON_WHEEL_DOWN,true,Vector2(600,400))
	tick(.35);check(game.controls.target_dolly==-.24,"dolly back clamp")
	button(MOUSE_BUTTON_LEFT,true,point("mug"));await wait()
	check(game.inspecting=="mug","left selects inspect")
	var camera_locked:Transform3D=game.camera.transform
	button(MOUSE_BUTTON_LEFT,true,Vector2(40,350));move(Vector2(200,650));tick(.1)
	check(game.inspecting=="mug" and game.camera.transform.is_equal_approx(camera_locked),"left does not put back; inspection camera lock")
	var distance:float=game.target_inspect_distance
	button(MOUSE_BUTTON_WHEEL_UP,true,Vector2(640,400))
	check(game.target_inspect_distance<distance and game.camera.transform.is_equal_approx(camera_locked),"inspection wheel affects item only")
	button(MOUSE_BUTTON_RIGHT,true,Vector2(640,400));tick(.25);button(MOUSE_BUTTON_RIGHT,false,Vector2(640,400));await wait(.05)
	check(game.inspecting=="mug","long hold release stays")
	button(MOUSE_BUTTON_RIGHT,true,Vector2(640,400));move(Vector2(660,410),Vector2(20,10));tick(.10);button(MOUSE_BUTTON_RIGHT,false,Vector2(660,410))
	check(game.inspecting=="mug" and game.target_inspect_rotation.y>.15,"rotation release stays")
	right_tap(Vector2(640,400));await wait();check(game.inspecting.is_empty(),"short tap returns on release")
	# Desk short tap never lifts or relocates.
	var desk_home:Transform3D=game.props.handheld.transform
	right_tap(point("handheld"));tick(.2)
	check(game.props.handheld.transform.is_equal_approx(desk_home) and game.drag.id.is_empty(),"desk tap no lift")
	# Valid preview transform equals settled transform, then inspect returns actual drop.
	var source:=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source)
	var dest:Vector2=game.camera.unproject_position(Vector3(.72,.763,.41));move(dest,dest-source);tick(.22)
	check(game.drag.solution.legal,"legal desk ghost")
	var preview:Transform3D=game.drag.solution.transform
	var frozen:Transform3D=game.camera.transform
	var zoom:float=game.controls.target_dolly
	button(MOUSE_BUTTON_WHEEL_UP,true,dest);tick(.1)
	check(game.camera.transform.is_equal_approx(frozen) and game.controls.target_dolly==zoom,"drag freezes camera xyz and zoom")
	button(MOUSE_BUTTON_RIGHT,false,dest);tick(1)
	check(game.drag.id.is_empty() and game.props.handheld.global_transform.is_equal_approx(preview),"preview matches legal release")
	button(MOUSE_BUTTON_LEFT,true,point("handheld"));await wait();right_tap(Vector2(640,400));await wait()
	check(game.props.handheld.global_transform.is_equal_approx(preview),"inspect returns new actual location")
	# Invalid preview and focus interruption return to actual grab parent/transform.
	source=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source);dest=game.camera.unproject_position(Vector3(-.95,.763,-.4));move(dest,dest-source);tick(.2)
	check(not game.drag.solution.legal,"invalid ghost is red")
	button(MOUSE_BUTTON_RIGHT,false,dest);tick(1)
	check(game.props.handheld.global_transform.is_equal_approx(preview),"invalid release returns actual origin")
	source=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source);move(source+Vector2(30,10),Vector2(30,10));tick(.1)
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT);tick(1)
	check(game.drag.id.is_empty() and game.props.handheld.global_transform.is_equal_approx(preview) and game.phase=="paused","focus loss cancels safely and pauses")
	game.begin();game.controls.focused=true
	# Compare continuous reverse trajectories across frame rates; restore actual start each run.
	var results:Array[Vector3]=[]
	for hz in [30,60,120]:
		game.props.handheld.global_transform=preview
		source=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source)
		dest=game.camera.unproject_position(Vector3(.72,.763,.26));move(dest,dest-source)
		var prev:Vector3=game.props.handheld.global_position
		for frame in range(hz):
			if frame==hz/2:move(source,source-dest)
			game._process(1.0/hz)
			var now:Vector3=game.props.handheld.global_position
			check(now.distance_to(prev)<.09,"no xyz discontinuity hz"+str(hz))
			check(now.y>=.7629,"no table penetration hz"+str(hz));prev=now
		results.append(prev)
		button(MOUSE_BUTTON_RIGHT,false,source);tick(1,hz)
	check(results[0].distance_to(results[2])<.004 and results[1].distance_to(results[2])<.004,"30 60 120 Hz consistent reversal")
	# Open cavity route: complete enter/exit/reverse and release, every axis and rate.
	game.use_drawer();await wait(.7)
	var cavity_results:Array[Vector3]=[]
	for hz in [30,60,120]:
		game.props.handheld.global_transform=preview
		if game.props.handheld.get_parent()!=game:game.props.handheld.reparent(game,true)
		await physics_frame
		source=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source)
		dest=game.camera.unproject_position(game.drawer.to_global(Vector3(0,-.047,.06)))
		move(dest,dest-source)
		var previous:Vector3=game.props.handheld.global_position
		var locked_camera:Transform3D=game.camera.transform
		for frame in range(hz*2):
			game._process(1.0/hz)
			var now:Vector3=game.props.handheld.global_position
			check(now.distance_to(previous)<.12,"cavity xyz no jump "+str(hz))
			if now.y<.785:check(game.drag.fully_inside("handheld",game.props.handheld.global_transform) or now.z<.60,"no lip penetration "+str(hz))
			check(game.camera.transform.is_equal_approx(locked_camera),"cavity camera xyz basis locked")
			previous=now
		cavity_results.append(previous)
		var drop:Transform3D=game.drag.solution.transform
		check(game.drag.solution.legal,"cavity green preview hz "+str(hz))
		button(MOUSE_BUTTON_RIGHT,false,dest);tick(1,hz)
		check(game.drag.stowed("handheld") and game.props.handheld.global_transform.is_equal_approx(drop),"cavity preview release parent matches "+str(hz))
		var local_return:Transform3D=game.props.handheld.transform
		await physics_frame
		button(MOUSE_BUTTON_LEFT,true,point("handheld"));await wait();right_tap(Vector2(640,400));await wait()
		check(game.props.handheld.get_parent()==game.drawer and game.props.handheld.transform.is_equal_approx(local_return),"drawer inspect actual parent and pose return")
		# Early release/cancel must not strand an item below the rim.
		source=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source)
		dest=game.camera.unproject_position(Vector3(.70,.763,.40));move(dest,dest-source);tick(.08,hz)
		var quick_drop:Transform3D=game.drag.solution.transform
		button(MOUSE_BUTTON_RIGHT,false,dest);tick(2,hz)
		check(game.drag.id.is_empty() and game.props.handheld.get_parent()==game and game.props.handheld.global_transform.is_equal_approx(quick_drop),"early cavity exit release settles "+str(hz))
		await physics_frame
		source=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source)
		dest=game.camera.unproject_position(game.drawer.to_global(Vector3(0,-.047,.06)));move(dest,dest-source);tick(.08,hz)
		quick_drop=game.drag.solution.transform
		button(MOUSE_BUTTON_RIGHT,false,dest);tick(2,hz)
		check(game.drag.id.is_empty() and game.drag.stowed("handheld") and game.props.handheld.global_transform.is_equal_approx(quick_drop),"early cavity entry release settles "+str(hz))
		await physics_frame
		var cancel_origin:Transform3D=game.props.handheld.transform
		source=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source)
		dest=game.camera.unproject_position(Vector3(.70,.763,.40));move(dest,dest-source);tick(.08,hz)
		game._notification(Node.NOTIFICATION_WM_MOUSE_EXIT);tick(2,hz)
		check(game.drag.id.is_empty() and game.props.handheld.get_parent()==game.drawer and game.props.handheld.transform.is_equal_approx(cancel_origin) and game.controls.right_mode.is_empty(),"mouse exit cancels cavity drag and releases inputs "+str(hz))
		game._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
		await physics_frame
		source=point("handheld");button(MOUSE_BUTTON_RIGHT,true,source)
		dest=game.camera.unproject_position(Vector3(.70,.763,.40));move(dest,dest-source)
		previous=game.props.handheld.global_position
		for frame in range(hz*2):
			game._process(1.0/hz)
			var now:Vector3=game.props.handheld.global_position
			check(now.distance_to(previous)<.12,"cavity exit continuous "+str(hz))
			if now.y<.785:check(game.drag.fully_inside("handheld",game.props.handheld.global_transform) or now.z<.60,"exit clears lip "+str(hz))
			previous=now
		button(MOUSE_BUTTON_RIGHT,false,dest);tick(1,hz)
		check(game.props.handheld.get_parent()==game,"drawer exit returns to desk")
	check(cavity_results[0].distance_to(cavity_results[2])<.006,"cavity 30 60 120Hz independent")
	game.use_drawer();await wait(.7)
	# Pause isolates game inputs and wheel. Running right tap returns after pause.
	button(MOUSE_BUTTON_LEFT,true,point("handheld"));await wait()
	var screen:Vector2=game.camera.unproject_position(game.props.handheld.to_global(Vector3(0,.0245,0)))
	button(MOUSE_BUTTON_LEFT,true,screen)
	check(game.pocket_playing,"left screen plays")
	var item_distance:float=game.target_inspect_distance
	button(MOUSE_BUTTON_WHEEL_UP,true,screen);button(MOUSE_BUTTON_RIGHT,true,screen);tick(.25);button(MOUSE_BUTTON_RIGHT,false,screen)
	check(game.pocket_playing and game.target_inspect_distance==item_distance,"pocket hold no rotate or zoom")
	right_tap(screen);await wait()
	check(not game.pocket_playing and game.inspecting.is_empty(),"pocket short tap pauses and returns")
	button(MOUSE_BUTTON_LEFT,true,point("handheld"));await wait()
	screen=game.camera.unproject_position(game.props.handheld.to_global(Vector3(0,.0245,0)))
	button(MOUSE_BUTTON_LEFT,true,screen)
	var shortcut:=InputEventKey.new();shortcut.keycode=KEY_Q;shortcut.pressed=true;game._unhandled_input(shortcut);await wait()
	check(not game.pocket_playing and game.inspecting.is_empty(),"Q shortcut pauses and returns running handheld")
	game.release_render_targets();game.queue_free();await wait(.1)
	if failures.is_empty():print("DESK_INPUT_PASS click_inspect tap_hold_rotation actual_return focus_release camera_deadzone_dolly_lock preview_release reverse_30_60_120");quit(0)
	else:print("DESK_INPUT_FAILED ",failures);quit(1)
