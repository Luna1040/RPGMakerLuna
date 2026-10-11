extends SceneTree
## Manual visual check: Godot --path . --script res://tests/roster_capture.gd -- --foundations --page=serin
## Uses an isolated runtime and never writes gameplay saves or settings.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var page:="serin"
	var action:="portrait"
	var light:=false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--page="): page=argument.trim_prefix("--page=")
		if argument.begins_with("--action="): action=argument.trim_prefix("--action=")
		if argument=="--light": light=true
	if page not in ["scout","caster","elite","boss","serin","party"]:
		push_error("Unknown roster capture page")
		quit(1)
		return
	var stage=load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	stage.runtime.persistence_enabled=false
	stage.runtime.autosave_armed=false
	stage._physics_process(0)
	if page=="party":
		stage.runtime.companion_recruited=true
		stage.runtime.encounters.set_companion_enabled(true)
		var state:Dictionary=stage.runtime.encounters.companion_snapshot()
		state.hp=81.0
		state.mp=46.0
		state.heal_cooldown=4.0
		stage.runtime.encounters.restore_companion(state)
		stage.runtime.panel.close()
	else:
		stage.runtime.panel.roster_id=page
		stage.runtime.panel.open("roster")
		var roster=stage.runtime.panel.body.get_child(0)
		roster.light_background=light
		if not roster.select_action(action):
			push_error("Requested preview action is not ready: "+page+"/"+action)
			stage.queue_free()
			await process_frame
			quit(1)
			return
	await create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	var path:="res://captures/roster-"+page+".png"
	if action!="portrait": path="res://captures/roster-"+page+"-"+action+("-light" if light else "-dark")+".png"
	var result:=root.get_texture().get_image().save_png(path)
	print("ROSTER_CAPTURE ",path," result=",result)
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(0 if result==OK else 1)
