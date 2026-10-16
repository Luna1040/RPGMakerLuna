extends SceneTree
const OUT:="res://art-jobs/office-v9-20261016/review/"
var view:SubViewport
var game:Node3D
func _initialize() -> void:
	root.hide();DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true);call_deferred("run")
func shot(id:String) -> void:
	RenderingServer.force_draw(true);view.get_texture().get_image().save_png(OUT+id+".png")
func wait(t:float=.6) -> void:await create_timer(t).timeout;await physics_frame
func input_left(id:String) -> void:
	var p:Vector2=game.camera.unproject_position(game.props[id].global_position+Vector3(0,.016,0))
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true;e.position=p;game._unhandled_input(e)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"motion/")
	view=SubViewport.new();view.size=Vector2i(1280,800);view.own_world_3d=true;view.msaa_3d=Viewport.MSAA_4X;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	# Only capture copy suppresses OS focus callbacks; production remains unchanged.
	var source:=FileAccess.get_file_as_string("res://desk_game.gd")
	source=source.substr(0,source.find("func _notification(what:"))+"func _notification(_what:int) -> void:\n\tpass\n"
	var script:=GDScript.new();script.source_code=source
	if script.reload()!=OK:push_error("DESK_OFFICE_VISUAL_FAIL capture script parse");quit(1);return
	game=Node3D.new();game.set_script(script);view.add_child(game);game.begin();game.set_process(false);game.patrol.enabled=false
	await wait(.4)
	# Freeze the actual initial camera; do not tick a host-sized pointer first.
	game.controls.pointer_origin=game.controls.pointer
	await shot("01-office-desktop-anime")
	var base:Transform3D=game.camera.transform
	game.controls.pointer=game.controls.pointer_origin+Vector2(620,-70)
	for i in range(30):game._process(1.0/60)
	await shot("02-right-coworker")
	var detail_pose:=Transform3D(Basis.IDENTITY,Vector3(2.85,1.45,-.10)).looking_at(Vector3(1.89,.80,-1.76),Vector3.UP)
	game.camera.transform=detail_pose;await shot("02b-seated-joints-feet")
	game.camera.transform=base;game.controls.rebase();await shot("03-boss-behind-own-screen")
	game.camera.transform=base;game.controls.rebase()
	game.patrol.enabled=true;game.phase="warning";game.phase_clock=0
	for frame in range(120):
		game._process((12.0-.001)/120)
		await process_frame;RenderingServer.force_draw(true);view.get_texture().get_image().save_png(OUT+"motion/frame-%04d.png"%frame)
		if frame==24:await shot("04-boss-standing")
		if frame==76:await shot("05-boss-walking")
	await shot("06-boss-arrival-default")
	game.camera.rotation=Vector3(-.4+deg_to_rad(10),deg_to_rad(15),0)
	await shot("06b-boss-arrival-normal-left-up")
	game.camera.transform=base;game.controls.rebase()
	game.phase="returning";game.phase_clock=0
	for frame in range(101):
		game._process(.1)
		await process_frame;RenderingServer.force_draw(true);view.get_texture().get_image().save_png(OUT+"motion/return-%04d.png"%frame)
		if frame==50:await shot("07-boss-returning")
	game.office.pose("free",0);game.phase="free";game.patrol.enabled=false
	for id in ["handheld","mug","tools"]:
		await physics_frame;input_left(id);await wait();game._process(.01);await shot("08-close-"+id)
		if id=="handheld":
			game.start_pocket();var e:=InputEventKey.new();e.keycode=KEY_D;e.pressed=true;game._unhandled_input(e)
			game._process(.08);await shot("10-pocket-frame-a")
			var first:PackedByteArray=game.pocket_view.get_texture().get_image().get_data()
			for frame in range(35):game._process(1.0/60)
			await shot("11-pocket-frame-b")
			var second:PackedByteArray=game.pocket_view.get_texture().get_image().get_data()
			if first==second:push_error("DESK_OFFICE_VISUAL_FAIL live viewport unchanged");quit(1);return
			game.stop_pocket()
		game.target_inspect_rotation.y+=.55;game._process(.15);await shot("09-rotated-"+id)
		game.return_item();await wait()
	var adapter:=RenderingServer.get_video_adapter_name()
	game.release_render_targets();game.queue_free();game=null
	for i in range(3):await process_frame;RenderingServer.force_draw(true)
	view.queue_free();view=null
	for i in range(4):await process_frame;RenderingServer.force_draw(true)
	print("DESK_OFFICE_VISUAL_PASS ",adapter," stills 120_approach_101_return_frames_unified_process scripted_side_anatomy_diagnostic_separate_from_normal_camera live_viewport_pixels_changed scripted_not_FPS_audio_not_reviewed");quit(0)
