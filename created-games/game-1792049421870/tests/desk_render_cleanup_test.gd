extends SceneTree
## Render target lifetime regression. Headless checks node/resource teardown;
## a host graphical run additionally drains actual Metal/GL work before process exit.
func _initialize() -> void:
	if DisplayServer.get_name()!="headless":root.hide()
	call_deferred("run")
func drain(frames: int) -> void:
	for i in range(frames):
		await process_frame
		if DisplayServer.get_name()!="headless":RenderingServer.force_draw(true)
func run() -> void:
	for cycle in range(3):
		var view:=SubViewport.new()
		view.size=Vector2i(1280,800)
		view.own_world_3d=true
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var game:Node3D=load("res://main.tscn").instantiate()
		view.add_child(game)
		game.begin()
		await drain(8)
		var game_ref:WeakRef=weakref(game)
		var view_ref:WeakRef=weakref(view)
		var pocket_ref:WeakRef=weakref(game.pocket_view)
		var material:StandardMaterial3D=game.pocket_screen_material
		game.release_render_targets()
		if material.albedo_texture!=null:
			push_error("DESK_RENDER_CLEANUP_FAIL viewport texture still bound");quit(1);return
		material=null
		game.queue_free();game=null
		await drain(3)
		view.render_target_update_mode=SubViewport.UPDATE_DISABLED
		view.queue_free();view=null
		await drain(4)
		if game_ref.get_ref()!=null or pocket_ref.get_ref()!=null or view_ref.get_ref()!=null:
			push_error("DESK_RENDER_CLEANUP_FAIL live scene node after drain");quit(1);return
	print("DESK_RENDER_CLEANUP_PASS three_scene_cycles viewport_texture_unbound nodes_freed driver=",DisplayServer.get_name())
	quit(0)
