extends SceneTree

func _initialize() -> void:
	var dungeon: Node2D = load("res://main.tscn").instantiate()
	root.add_child(dungeon)
	var initial: Vector2 = dungeon.player
	Input.action_press("ui_right")
	dungeon._physics_process(0.5)
	Input.action_release("ui_right")
	if dungeon.player.x <= initial.x:
		push_error("Movement did not advance player")
		quit(1)
		return
	dungeon.enemies.clear()
	dungeon.enemies.append(dungeon.player + Vector2(30, 0))
	dungeon.attack_clock = 1
	dungeon._physics_process(0.01)
	if dungeon.enemies.size() != 0 or dungeon.gems.size() != 1:
		push_error("Automatic attack did not drop a gem")
		quit(1)
		return
	dungeon.player = dungeon.gems[0]
	dungeon._physics_process(0.01)
	if dungeon.score != 1:
		push_error("Gem collection did not increase score")
		quit(1)
		return
	print("DEMO_GAMEPLAY_PASS: movement, attack, gem collection")
	dungeon.free()
	quit()
