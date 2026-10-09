extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	for npc: Dictionary in stage.townsfolk.residents:
		check(npc.idle_frames.size() >= 30, "NPC missing occupational animation: "+npc.id)
		for frame in npc.idle_frames:
			check(frame != null, "NPC texture missing: "+npc.id)
		var original_position: Vector2 = npc.root.position
		var seen := {}
		for i in 80:
			stage.townsfolk.step(.125,Vector2.ZERO,0)
			seen[npc.sprite.texture.resource_path] = true
			check(npc.root.position == original_position,"NPC feet/collider drift")
		check(seen.size() >= 30,"NPC timeline did not advance")
	var fountain = stage.sorting.get_node("pool")
	var water = fountain.get_child(1)
	var before: float = water.water_material.get_shader_parameter("water_time")
	water._process(.5)
	check(float(water.water_material.get_shader_parameter("water_time")) > before,"Fountain shader time did not advance")
	for error in failures: push_error(error)
	print("TOWN_ANIMATION_TEST ", "PASS" if failures.is_empty() else "FAIL", " · NPC frames/timeline/fixed roots, fountain water clock")
	quit(0 if failures.is_empty() else 1)
