extends SceneTree
var knight: CharacterBody2D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	knight = load("res://characters/first_knight/knight.gd").new()
	knight.equipment.persistence_enabled = false
	knight.use_local_input = false
	root.add_child(knight)
	knight.set_physics_process(false)
	if knight.jump_textures.is_empty():
		push_error("Missing original jump frames")
		quit(1)
		return
	knight.set_airborne(true, 6.36)
	knight._physics_process(0.02)
	var first: Texture2D = knight.body.texture
	knight.set_airborne(true, 0.0)
	knight._physics_process(0.4)
	if knight.body.texture == first or knight.jump_phase != "apex":
		push_error("Jump did not progress to distinct apex pose")
		quit(1)
		return
	knight.set_airborne(true, -4.0)
	knight._physics_process(0.03)
	if knight.jump_phase != "fall":
		quit(1)
		return
	knight.request_air_attack()
	knight._physics_process(0.01)
	if knight.state != "air_slash" or knight.body.texture in knight.jump_textures:
		push_error("Jump override interrupted attack animation")
		quit(1)
		return
	knight.set_airborne(false, 0.0)
	knight.notify_air_attack_landed(true)
	knight._physics_process(0.10)
	if knight.state != "air_slash" or knight.body.texture in knight.jump_textures:
		push_error("Air attack landing recovery was overridden by jump pose")
		quit(1)
		return
	knight._physics_process(0.15)
	if knight.state != "stand":
		push_error("Air attack did not recover after landing")
		quit(1)
		return
	# A subsequent ordinary jump must still use its authored landing frames.
	knight.set_airborne(true, 6.36)
	knight._physics_process(0.02)
	knight.set_airborne(false, 0.0)
	knight._physics_process(0.05)
	if knight.body.texture not in knight.jump_textures:
		push_error("Landing pose missing")
		quit(1)
		return
	knight._physics_process(0.20)
	if knight.body.texture in knight.jump_textures:
		push_error("Jump pose did not release after landing")
		quit(1)
		return
	print("JUMP TEST PASS: unique apex, descent, landing, air attack preservation")
	quit(0)
