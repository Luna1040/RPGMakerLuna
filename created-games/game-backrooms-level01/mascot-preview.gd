extends "res://main.gd"

var preview_time := 0.0


func _ready() -> void:
	super._ready()
	get_window().size = Vector2i(1180, 800)
	get_node("HUD").hide()
	title_overlay.hide()
	game_started = false
	set_physics_process(false)
	for child in get_children():
		if child is Node3D and child != player:
			child.visible = false
	var preview_environment := get_world_3d().environment
	preview_environment.background_mode = Environment.BG_COLOR
	preview_environment.background_color = Color("202630")
	preview_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	preview_environment.ambient_light_color = Color("777f8c")
	preview_environment.ambient_light_energy = 0.26
	mascot_jumpscare.visible = true
	mascot_jumpscare.position = Vector3(0.0, 0.0, -2.4)
	mascot_jumpscare.scale = Vector3.ONE * 0.03
	mascot_jumpscare.rotation = Vector3.ZERO
	_play_sfx("mascot", -2.0)
	horror_hit_player.play()
	set_process(true)


func _process(delta: float) -> void:
	preview_time += delta
	var approach := clampf(preview_time / 0.58, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - approach, 3.0)
	mascot_jumpscare.scale = Vector3.ONE * lerpf(0.03, 0.85, eased)
	mascot_jumpscare.position = Vector3(0.0, 0.0, lerpf(-2.4, -1.35, eased))
	var shake := 1.0 if preview_time < 1.25 else 0.0
	mascot_jumpscare.rotation.z = sin(preview_time * 28.0) * 0.05 * shake
	mascot_jumpscare.rotation.y = sin(preview_time * 15.0) * 0.08 * shake
