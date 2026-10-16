extends SceneTree
const OUT := "res://art-jobs/finish-v6-20261015/"
var view: SubViewport
var game: Node3D
func _initialize() -> void:
	root.hide()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	call_deferred("run")
func percentile(values: Array[float], fraction: float) -> float:
	var sorted:=values.duplicate();sorted.sort();return sorted[int((sorted.size()-1)*fraction)]
func run() -> void:
	view=SubViewport.new();view.size=Vector2i(1280,800);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.msaa_3d=Viewport.MSAA_4X;root.add_child(view)
	game=load("res://main.tscn").instantiate();view.add_child(game);game.begin();game.set_process(false)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	for i in range(90):await process_frame;RenderingServer.force_draw(true)
	var samples:Array[float]=[]
	var gpu:Array[float]=[]
	for i in range(180):
		var start:=Time.get_ticks_usec()
		await process_frame
		RenderingServer.force_draw(true)
		samples.append((Time.get_ticks_usec()-start)/1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
	var method:=RenderingServer.get_current_rendering_method()
	var gpu_median:=percentile(gpu,.5)
	var report:Dictionary={"renderer":RenderingServer.get_video_adapter_name(),"method":method,"size":"1280x800 4xMSAA","warmup":90,"samples":180,"frame_wall_median_ms":percentile(samples,.5),"frame_wall_p95_ms":percentile(samples,.95),"gpu_median_ms":gpu_median if gpu_median>0 else null,"gpu_timing_valid":gpu_median>0,"scope":"hidden offscreen desktop process-frame/vsync plus synchronous force_draw; no frame readback during samples; not human play FPS"}
	var file:=FileAccess.open(OUT+"benchmark-"+method+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	view.get_texture().get_image().save_png(OUT+"benchmark-"+method+".png")
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),false)
	game.release_render_targets()
	game.queue_free()
	game=null
	for i in range(3):await process_frame;RenderingServer.force_draw(true)
	view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	view.queue_free()
	view=null
	for i in range(4):await process_frame;RenderingServer.force_draw(true)
	print("DESK_RENDER_CLEANUP_PASS scene_and_viewport_freed_render_queue_drained")
	print("DESK_RENDER_BENCHMARK_PASS ",JSON.stringify(report))
	quit(0)
