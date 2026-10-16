extends SceneTree
var game:Node3D
var failures:Array[String]=[]
func check(ok:bool,msg:String) -> void:
	if not ok:failures.append(msg);push_error("DESK_V9_FAIL "+msg)
func spawn_game(seed_value:int=91) -> void:
	game=load("res://main.tscn").instantiate();root.add_child(game);current_scene=game
	await physics_frame;await physics_frame
	game.begin();game.set_process(false);game.patrol.reset(seed_value)
func advance(seconds:float) -> void:
	var left:=seconds
	while left>.000001:
		var dt:=minf(left,1.0/60);left-=dt
		for tween in get_processed_tweens():
			if tween.is_running():tween.custom_step(dt)
		game._process(dt)
func button(index:int,pressed:bool,pos:Vector2) -> void:
	var e:=InputEventMouseButton.new();e.button_index=index;e.pressed=pressed;e.position=pos;game._unhandled_input(e)
func key(code:int,pressed:bool=true) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.pressed=pressed;game._unhandled_input(e)
func click(id:String) -> void:
	await physics_frame;await physics_frame
	var p:Vector3=game.drawer.global_position+Vector3(0,0,.27) if id=="drawer" else game.props[id].global_position+Vector3(0,.016,0)
	if id=="computer":p+=Vector3(0,.33,.03)
	var pos:Vector2=game.camera.unproject_position(p)
	check(game.pick_id(pos)==id,"ray click "+id+" actual="+game.pick_id(pos));button(MOUSE_BUTTON_LEFT,true,pos)
	advance(.60)
func drag_to(id:String,destination:Vector3) -> void:
	await physics_frame;await physics_frame
	var pos:Vector2=game.camera.unproject_position(game.props[id].global_position+Vector3(0,.015,0))
	check(game.pick_id(pos)==id,"ray drag "+id);button(MOUSE_BUTTON_RIGHT,true,pos)
	var dest:Vector2=game.camera.unproject_position(destination)
	var event:=InputEventMouseMotion.new();event.position=dest;event.relative=dest-pos;game._unhandled_input(event)
	var locked:Transform3D=game.camera.transform;advance(.35)
	check(game.drag.id==id,"begin move "+id)
	check(game.camera.transform.is_equal_approx(locked),"drag camera locked")
	button(MOUSE_BUTTON_RIGHT,false,dest);advance(1.35)
	check(game.drag.id.is_empty(),"settled "+id)
func hide_evidence() -> void:
	key(KEY_Q);advance(.50)
	if game.equipped:key(KEY_Q);advance(.50)
	await drag_to("folder",game.board.global_position)
	if not game.drawer_open:await click("drawer")
	await drag_to("handheld",game.drawer.to_global(Vector3(0,-.047,.060)))
	await drag_to("tools",game.drawer.to_global(Vector3(0,-.041,-.13)))
	await click("drawer")
	if not game.working:await click("computer")
	check(game.is_safe(),"physical hide safety")
func resume_play() -> void:
	await click("drawer")
	await drag_to("handheld",game.global_transform*game.homes.handheld.origin)
	await drag_to("tools",game.global_transform*game.homes.tools.origin)
	await click("drawer")
	await drag_to("folder",game.global_transform*game.homes.folder.origin)
	await click("handheld")
	var pos:Vector2=game.camera.unproject_position(game.props.handheld.to_global(Vector3(0,.0245,0)));button(MOUSE_BUTTON_LEFT,true,pos)
func clean() -> void:
	game.release_render_targets();game.queue_free();game=null
	await process_frame;await process_frame
