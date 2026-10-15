extends SceneTree
var destination := "user://"
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination.path_join(name+".png"))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="): destination=arg.trim_prefix("--review-output=")
	var stage = load("res://stage.tscn").instantiate()
	root.add_child(stage)
	current_scene=stage
	stage.runtime.persistence_enabled=false
	stage.runtime.panel.quest_filter="available"
	stage.runtime.panel.open("journal")
	await create_timer(.5).timeout
	await capture("demo-journal")
	for zone in ["frost","ember"]:
		stage=current_scene
		stage.runtime.panel.close()
		stage.runtime.encounters.clear()
		stage.runtime.run_state={"phase":"ready","wave":0,"seed":887,"boons":[],"offers":[],"rooms":true,"room":0,"return_zone":"city"}
		stage.runtime.travel(zone)
		await create_timer(3).timeout
		stage=current_scene
		stage.runtime.persistence_enabled=false
		stage.runtime.panel.close()
		stage.runtime.encounters.clear()
		stage.foot=Vector2(9,7.5)
		stage.runtime.adventure.accept_quest("frost_patrol" if zone=="frost" else "ember_patrol")
		await create_timer(1).timeout
		await capture("demo-"+zone)
	quit()
