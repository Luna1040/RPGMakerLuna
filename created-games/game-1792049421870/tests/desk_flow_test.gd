extends SceneTree
var game: Node3D
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:failures.append(label);push_error("DESK_TEST_FAIL "+label)
func settle(seconds: float=.65) -> void:
	await create_timer(seconds).timeout
	await physics_frame
func mouse(button: int, pressed: bool, pixel: Vector2) -> void:
	var e:=InputEventMouseButton.new();e.button_index=button;e.pressed=pressed;e.position=pixel;game._unhandled_input(e)
func click(id: String) -> void:
	var p:Vector3=game.drawer.global_position+Vector3(0,0,.27) if id=="drawer" else game.props[id].global_position+Vector3(0,.016,0)
	if id=="computer":p+=Vector3(0,.33,.03)
	var uv:Vector2=game.camera.unproject_position(p)
	check(game.pick_id(uv)==id,"ray click "+id+" got="+game.pick_id(uv))
	mouse(MOUSE_BUTTON_LEFT,true,uv)
func drag_item(id: String, destination: Vector3) -> void:
	var source:Vector3=game.props[id].global_position+Vector3(0,.015,0)
	var uv:Vector2=game.camera.unproject_position(source)
	check(game.pick_id(uv)==id,"ray drag source "+id+" actual="+game.pick_id(uv))
	mouse(MOUSE_BUTTON_RIGHT,true,uv)
	
	var cam:Transform3D=game.camera.transform
	var end:Vector2=game.camera.unproject_position(destination)
	var e:=InputEventMouseMotion.new();e.position=end;e.relative=end-uv;game._unhandled_input(e)
	for i in range(15):game._process(.016)
	check(game.camera.transform.is_equal_approx(cam),"drag freezes camera xyz basis")
	check(game.drag.id==id,"drag after movement "+id)
	mouse(MOUSE_BUTTON_RIGHT,false,end)
	for i in range(150):game._process(1.0/120)
	await settle(.05)
func key(code: int, pressed: bool=true) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.pressed=pressed;game._unhandled_input(e)
func run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game);current_scene=game
	await settle(.15)
	game.begin();game.set_process(false);game.pocket.set_physics_process(false)
	check(game is Node3D,"original 3D project")
	check(ProjectSettings.get_setting("autoload/GameAssistant")=="*res://game_assistant.gd","bridge preserved")
	click("tools");await settle(.12)
	check(game.props.tools.global_position.y>.8,"pickup lifts before travel")
	await settle()
	game.action_button.pressed.emit();await settle()
	check(game.equipped,"explicit tweezer use button")
	click("board");await settle()
	check(game.inspecting=="board" and game.beads_placed==0,"left board inspect only")
	for i in range(12):key(KEY_SPACE);await settle(.3);check(game.beads_placed==i+1,"bead input release "+str(i))
	game.return_item();await settle()
	game.return_item();await settle()
	# Left folder click inspects instead of silently covering.
	click("folder");await settle()
	check(game.inspecting=="folder" and not game.covered,"left click is inspect only")
	check(not game.notice.text.contains("掌机") and not game.hint.text.contains("屏幕"),"folder has own inspect hint")
	mouse(MOUSE_BUTTON_RIGHT,true,Vector2(640,400))
	var rotate:=InputEventMouseMotion.new();rotate.relative=Vector2(35,12);game._unhandled_input(rotate);game._process(.1)
	check(game.target_inspect_rotation.y>.3,"inspection rotation responds")
	mouse(MOUSE_BUTTON_RIGHT,false,Vector2(640,400));game.return_item();await settle()
	await drag_item("folder",game.board.global_position+Vector3(-.09,0,0))
	check(game.drag.cover_ratio()<.97 and game.drag.cover_ratio()>.3,"partial physical coverage unsafe")
	await drag_item("folder",game.board.global_position)
	check(game.drag.cover_ratio()>=.97,"full coverage by drag")
	check(not game.is_safe(),"cover alone not safe")
	click("handheld");await settle()
	check(game.inspecting=="handheld","handheld real pickup")
	var center:Vector2=game.camera.unproject_position(game.props.handheld.to_global(Vector3(0,.0245,0)))
	check(game.screen_pointer(center)!=null,"screen ray maps to viewport")
	mouse(MOUSE_BUTTON_LEFT,true,center)
	check(game.pocket_playing,"screen click enters platform mode")
	var old_yaw:float=game.target_yaw;var old_count:int=game.beads_placed
	mouse(MOUSE_BUTTON_RIGHT,true,center);game._unhandled_input(rotate);mouse(MOUSE_BUTTON_RIGHT,false,center)
	check(game.target_yaw==old_yaw and game.beads_placed==old_count,"mode isolates world controls")
	key(KEY_D)
	for i in range(300):game.pocket.advance(1.0/60)
	check(game.pocket.dead,"real movement reaches spike danger")
	key(KEY_R);check(not game.pocket.dead and game.pocket.deaths==1,"retry returns to checkpoint")
	key(KEY_D)
	# Solve through input only: look ahead at dangerous floor/gap, jump with coyote buffer.
	for frame in range(3600):
		var p=game.pocket
		if p.dead:break
		if p.grounded:
			var floor_found:=false
			var ahead:float=p.player.x+38
			for platform in p.platforms:
				if platform.position.y==310 and ahead>=platform.position.x and ahead<=platform.end.x:floor_found=true
			var danger:=not floor_found
			for h in p.hazards:
				if h.position.x>p.player.x and h.position.x-p.player.x<52:danger=true
			if danger:key(KEY_SPACE)
		p.advance(1.0/60)
		if p.won:break
	check(game.pocket.won,"platform course won by movement/jump input")
	check(game.pocket.checkpoints_passed==2,"both real checkpoints reached")
	check(game.pocket.time_played>30 and game.pocket.time_played<50,"30–50 second course "+str(game.pocket.time_played))
	# Mouse equivalent toggles movement and jumps on the live viewport buttons.
	game.pocket.pointer(Vector2(240,340),true)
	check(game.pocket.mouse_axis==1,"mouse right movement toggles on")
	game.pocket.pointer(Vector2(460,340),true)
	check(game.pocket.jump_queued,"mouse jump preserves movement")
	game.pocket.pointer(Vector2(240,340),true)
	check(game.pocket.mouse_axis==0,"mouse direction toggles off")
	key(KEY_ESCAPE)
	var pos:Vector2=game.pocket.player
	game.pocket.advance(1)
	check(not game.pocket_playing and game.pocket.player==pos,"screen leave pauses progress")
	game.return_item();await settle()
	click("drawer");await settle()
	check(game.drawer_open and not game.tool_stowed,"drawer opens independently")
	var drawer_cam:Transform3D=game.camera.transform
	for p in [Vector3(-.17,-.047,-.21),Vector3(.17,-.047,.21),Vector3(0,0,.27)]:
		var uv:Vector2=game.camera.unproject_position(game.drawer.to_global(p))
		check(uv.x>15 and uv.x<1265 and uv.y>215 and uv.y<780,"drawer cavity and handle fully visible "+str(uv))
	check(game.objective.position.y<200 and not game.meter.visible,"drawer HUD clears cavity")
	await drag_item("handheld",game.drawer.to_global(Vector3(0,-.047,.060)))
	check(game.drag.stowed("handheld"),"console physically in inner volume")
	check(not game.is_safe(),"open drawer never safe")
	await drag_item("tools",game.drawer.to_global(Vector3(0,-.047,-.13)))
	check(game.drag.stowed("tools"),"tweezers physically in separate slot")
	# Check inner-volume rejection and closing clearance without setting hidden flags.
	var stored:Transform3D=game.props.handheld.transform
	game.props.handheld.position.x=.12
	check(not game.drag.can_close() and not game.is_safe(),"protruding controller blocks closure")
	click("drawer");await settle(.1)
	check(game.drawer_open,"unsafe close rejected")
	game.props.handheld.transform=stored
	click("drawer");await settle()
	check(not game.drawer_open and game.drag.stowed("handheld"),"closure moves contents together")
	check(game.camera.transform.is_equal_approx(game.drawer_camera_home),"closing restores original camera")
	check(not game.drag.begin("handheld",Vector2(640,400)),"closed drawer cannot drag hidden item")
	click("computer")
	check(game.is_safe(),"all actual evidence hidden")
	game.elapsed=game.FIRST_VISIT;game._process(.01)
	check(game.phase=="warning" and game.phase_clock<.1,"full fair warning")
	game._process(game.WARNING_SECONDS+.01);check(game.phase=="checking","safe boss entry")
	game._process(game.INSPECTION_SECONDS+.01)
	# Reopen, pick up through actual rays, return and stow again. No automatic collection.
	click("drawer");await settle()
	click("tools");await settle()
	check(game.inspecting=="tools" and game.props.tools.get_parent()==game,"open drawer left pickup inspects")
	game.return_item();await settle()
	check(game.drag.stowed("tools"),"inspect returns tool to drawer actual parent")
	click("handheld");await settle()
	check(game.inspecting=="handheld" and game.props.handheld.get_parent()==game,"stored console picks up with world transform")
	game.return_item();await settle()
	check(game.drag.stowed("handheld"),"inspect returns console to actual drawer position")
	click("drawer");await settle()
	game.elapsed=game.SECOND_VISIT;game._process(.01)
	game._process(game.WARNING_SECONDS+.01);game._process(game.INSPECTION_SECONDS+.01);game._process(.01)
	check(game.phase=="won","both tasks + two checks win")
	game.reset_game();await settle(.2);game=current_scene
	check(game.phase=="intro" and not game.pocket.won and game.beads_placed==0,"restart resets both tasks")
	game.begin();game.set_process(false);game.begin_warning();game._process(game.WARNING_SECONDS+.01)
	check(game.phase=="lost" and game.result_text.text.contains("掌机"),"unsafe failure lists evidence")
	if failures.is_empty():print("DESK_FLOW_PASS real_ray_input drag_partial_full_cover drawer_volume handheld_screen_input platform_danger_retry_checkpoints_win pause_modes fair_boss restart");quit(0)
	else:print("DESK_FLOW_FAILED ",failures);quit(1)
