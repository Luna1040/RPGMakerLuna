extends Node3D

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1b1917")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8e8376")
	env.ambient_light_energy = 0.55
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34, -28, 0)
	key.light_color = Color("e4d8c3")
	key.light_energy = 1.1
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.4, 2.7, 1.8)
	rim.light_color = Color("ad6c45")
	rim.light_energy = 2.2
	rim.omni_range = 6.0
	add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var floor := PlaneMesh.new()
	floor.size = Vector2(12, 12)
	floor_mesh.mesh = floor
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("3c3830")
	floor_mat.roughness = 0.93
	floor_mesh.material_override = floor_mat
	floor_mesh.position.y = -0.03
	add_child(floor_mesh)
	var actor := (load("res://assets/creatures/the_stalker/Run.fbx") as PackedScene).instantiate() as Node3D
	actor.name = "The Stalker"
	add_child(actor)
	var player := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player and player.has_animation("Run"):
		player.play("Run")
	var camera := Camera3D.new()
	camera.position = Vector3(3.3, 1.65, 4.6)
	camera.fov = 48
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)
