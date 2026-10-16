extends SceneTree
const OUT:="res://art-jobs/input-v8-20261015/review/"
var view:SubViewport
var game:Node3D
var failures:Array[String]=[]
var preview:=Transform3D.IDENTITY
func check(ok:bool,message:String) -> void:
	if not ok:failures.append(message);push_error("DESK_INPUT_VISUAL_FAIL "+message)
func _initialize() -> void:
	root.hide();DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true);call_deferred("run")
func button(index:int,pressed:bool,p:Vector2) -> void:
	var e:=InputEventMouseButton.new();e.button_index=index;e.pressed=pressed;e.position=p;game._unhandled_input(e)
func move(p:Vector2,relative:Vector2=Vector2.ZERO) -> void:
	var e:=InputEventMouseMotion.new();e.position=p;e.relative=relative;game._unhandled_input(e)
func shot(name:String) -> void:
	RenderingServer.force_draw(true)
	view.get_texture().get_image().save_png(OUT+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"motion/")
	view=SubViewport.new();view.size=Vector2i(1280,800);view.own_world_3d=true;view.msaa_3d=Viewport.MSAA_4X
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	game=load("res://main.tscn").instantiate();view.add_child(game);game.begin();game.set_process(false);game.pocket.set_physics_process(false)
	await create_timer(.2).timeout
	for i in range(20):game._process(.016);await process_frame
	await shot("01-input-desktop")
	game.use_drawer();await create_timer(.7).timeout
	var start:Vector2=game.camera.unproject_position(game.props.handheld.global_position+Vector3(0,.015,0))
	var valid:Vector2=game.camera.unproject_position(game.drawer.to_global(Vector3(0,-.047,.06)))
	var invalid:Vector2=game.camera.unproject_position(game.drawer.to_global(Vector3(.15,-.047,.06)))
	button(MOUSE_BUTTON_RIGHT,true,start)
	for frame in range(100):
		var pos:=start.lerp(valid,clampf(float(frame)/35,0,1))
		if frame>=38 and frame<50:pos=valid.lerp(invalid,float(frame-38)/12)
		elif frame>=50 and frame<62:pos=invalid.lerp(valid,float(frame-50)/12)
		elif frame>=62:pos=valid
		if frame<66:move(pos,pos-start)
		if frame==65:
			check(not game.drag.id.is_empty() and game.drag.solution.get("legal",false),"valid ghost before release")
			preview=game.drag.solution.get("transform",Transform3D.IDENTITY)
			await shot("04-preview-valid")
			button(MOUSE_BUTTON_RIGHT,false,valid)
		game._process(1.0/60)
		await process_frame
		RenderingServer.force_draw(true)
		view.get_texture().get_image().save_png(OUT+"motion/frame-%04d.png"%frame)
		if frame==49:
			check(not game.drag.solution.get("legal",true),"invalid ghost is red")
			await shot("03-preview-invalid")
		if frame==30:await shot("02-drag-cavity")
	for i in range(80):game._process(1.0/120);await process_frame
	await shot("05-settled-cavity")
	check(game.drag.stowed("handheld") and game.props.handheld.global_transform.is_equal_approx(preview),"console settles at shown preview in cavity")
	var original:Transform3D=game.props.handheld.transform
	await physics_frame
	var source:Vector2=game.camera.unproject_position(game.props.handheld.global_position+Vector3(0,.015,0))
	button(MOUSE_BUTTON_LEFT,true,source);await create_timer(.5).timeout
	await shot("06-inspect-from-cavity")
	button(MOUSE_BUTTON_RIGHT,true,Vector2(640,400));game._process(.06);button(MOUSE_BUTTON_RIGHT,false,Vector2(640,400))
	await create_timer(.5).timeout
	await shot("07-return-original-cavity")
	check(game.props.handheld.get_parent()==game.drawer and game.props.handheld.transform.is_equal_approx(original),"inspect returns original cavity parent and pose")
	var adapter:=RenderingServer.get_video_adapter_name()
	game.release_render_targets();game.queue_free();game=null
	for i in range(3):await process_frame;RenderingServer.force_draw(true)
	view.queue_free();view=null
	for i in range(4):await process_frame;RenderingServer.force_draw(true)
	if failures.is_empty():
		print("DESK_INPUT_VISUAL_PASS ",adapter," seven_stills 100_actual_motion_frames 60Hz_scripted automatic_not_human_FPS");quit(0)
	else:print("DESK_INPUT_VISUAL_FAILED ",failures);quit(1)
