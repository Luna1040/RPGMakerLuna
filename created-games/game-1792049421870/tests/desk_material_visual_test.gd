extends SceneTree
## Host-only hidden static review; no interactive game launch or old motion recorder.
const OUT := "res://art-jobs/input-v8-20261015/review/"
var view: SubViewport
var game: Node3D
func _initialize() -> void:
	root.title="Desk material + handheld hidden review"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	root.hide()
	call_deferred("run")
func wait(seconds: float=.70) -> void:await create_timer(seconds).timeout
func shot(name: String) -> void:
	for i in range(5):await process_frame
	RenderingServer.force_draw(true)
	var im:=view.get_texture().get_image()
	if im.is_empty():push_error("DESK_MATERIAL_VISUAL_FAIL empty");quit(1);return
	im.save_png(OUT+name+".png")
	print("DESK_MATERIAL_VISUAL_FRAME ",name)
func drag_to(item: String, position: Vector3) -> void:
	var source:Vector2=game.camera.unproject_position(game.props[item].global_position+Vector3(0,.015,0))
	var end:Vector2=game.camera.unproject_position(position)
	if not game.drag.begin(item,source):push_error("DESK_MATERIAL_VISUAL_FAIL drag "+item);quit(1);return
	game.drag.move(end)
	for i in range(20):game._process(.016);await process_frame
	game.drag.end(end)
	for i in range(120):game._process(1.0/120);await process_frame
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	view=SubViewport.new();view.size=Vector2i(1280,800);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.msaa_3d=Viewport.MSAA_4X
	root.add_child(view)
	game=load("res://main.tscn").instantiate();view.add_child(game)
	game.begin();game.set_process(false);game.pocket.set_physics_process(false)
	await shot("01-material-desktop")
	game.inspect_item("notes");await wait();await shot("02-paper-close")
	game.return_item();await wait()
	game.inspect_item("folder");await wait();await shot("03-linen-close")
	game.return_item();await wait()
	game.inspect_item("handheld");await wait();game.start_pocket()
	game.pocket.keys[KEY_D]=true
	for i in range(90):game.pocket.advance(1.0/60)
	game.pocket.queue_redraw();await shot("04-handheld-live-screen")
	game.stop_pocket();game.target_inspect_rotation=Vector3(.85,.40,.1);game._process(.03)
	await shot("05-handheld-detail")
	game.return_item();await wait()
	await drag_to("folder",game.board.global_position+Vector3(-.09,0,0));game.update_hud();await shot("06-partial-cover")
	await drag_to("folder",game.board.global_position);game.update_hud();await shot("07-full-cover")
	game.use_drawer();await wait()
	await drag_to("handheld",game.drawer.to_global(Vector3(0,-.047,.060)))
	await drag_to("tools",game.drawer.to_global(Vector3(0,-.047,-.13)))
	await shot("08-real-drawer-contents")
	game.use_drawer();await wait();await shot("09-closed-drawer")
	var renderer:=RenderingServer.get_video_adapter_name()
	await cleanup_render_scene()
	print("DESK_MATERIAL_VISUAL_RENDER_PASS renderer=",renderer," nine_frames hidden_subviewport; static review only")
	quit(0)

func cleanup_render_scene() -> void:
	game.release_render_targets()
	game.queue_free()
	game=null
	for i in range(3):await process_frame;RenderingServer.force_draw(true)
	view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	view.queue_free()
	view=null
	for i in range(4):await process_frame;RenderingServer.force_draw(true)
	print("DESK_RENDER_CLEANUP_PASS scene_and_viewport_freed_render_queue_drained")
