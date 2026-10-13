extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.reset_game()
	assert(game.stars.size() == 10 and game.collected == 0 and not game.won)
	var start: Vector2 = game.player
	Input.action_press("ui_right")
	game._process(0.1)
	Input.action_release("ui_right")
	assert(is_equal_approx(game.player.x - start.x, 34.0), "Arrow movement failed")
	Input.action_press("ui_left")
	game._process(10.0)
	Input.action_release("ui_left")
	assert(game.player.x == game.FIELD.position.x + game.PLAYER_RADIUS, "Boundary failed")
	game.reset_game()
	for point in game.STAR_POSITIONS:
		game.player = point
		game._process(0.016)
	assert(game.collected == 10 and game.stars.is_empty() and game.won, "Win failed")
	var finish: Vector2 = game.player
	var finish_time: float = game.elapsed
	Input.action_press("ui_right")
	game._process(0.2)
	Input.action_release("ui_right")
	assert(game.player == finish and game.elapsed == finish_time, "Win freeze failed")
	var restart := InputEventKey.new()
	restart.keycode = KEY_R
	restart.pressed = true
	game._unhandled_key_input(restart)
	assert(game.collected == 0 and game.stars.size() == 10 and not game.won and game.elapsed == 0.0, "R restart failed")
	game.free()
	print("PASS: scene, arrow movement, boundary, 10 pickups, victory, R restart")
	quit()
