extends SceneTree
## Manual visual check for the 1280x800 campaign manager layout.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.runtime.persistence_enabled=false
	stage.runtime.autosave_armed=false
	stage.runtime.panel.open("campaigns")
	await create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var path:="res://captures/campaign-manager.png"
	var result:=root.get_texture().get_image().save_png(path)
	print("CAMPAIGN_MANAGER_CAPTURE ",path," result=",result)
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(0 if result==OK else 1)
