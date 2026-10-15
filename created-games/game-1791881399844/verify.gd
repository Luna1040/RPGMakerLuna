extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var live_assistant = root.get_node("GameAssistant")
	assert(live_assistant.home_button != null and live_assistant.home_button.visible, "Standalone startup must retain lobby navigation")
	assert(live_assistant.panel != null, "Standalone startup must retain an Escape menu")
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
	# Attach the assistant script after entering the tree so tests do not read
	# bridge connection data or send requests to the running launcher.
	var assistant := CanvasLayer.new()
	root.add_child(assistant)
	assistant.set_script(load("res://game_assistant.gd"))
	assistant.add_home_navigation()
	assistant.add_offline_menu()
	assert(assistant.home_button.text == "返回游戏大厅" and assistant.home_button.visible)
	assert(assistant.home_button.focus_mode == Control.FOCUS_NONE, "Lobby button must not capture movement focus")
	assert(assistant.default_connection_path().replace("\\", "/").ends_with("/先锋技术调研/.game-assistant/connection.json"), "Wrong nested-project fallback path")
	for invalid in [null, [], {}, {"url": 1, "token": "test"}, {"url": "", "token": "test"}, {"url": "http://127.0.0.1", "token": ""}]:
		assert(not assistant.valid_connection(invalid), "Invalid connection accepted")
	assert(assistant.valid_connection({"url": "http://127.0.0.1:1", "token": "test-only"}))
	assert(assistant.home_request != assistant.action, "Lobby requests must be independent")
	assistant.home_button.disabled = true
	assistant.home_failed("测试连接失败")
	assert(not assistant.home_button.disabled and assistant.home_feedback.text == "测试连接失败")
	assert(assistant.menu_home_feedback.text == "测试连接失败", "Failure must remain visible inside the menu")
	assistant.go_home()
	assert(not assistant.home_button.disabled and assistant.home_feedback.text.contains("未连接大厅"), "Offline button must explain the problem without a request")
	assistant.home_button.disabled = true
	assistant.home_request.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(), '{"error":"请先完成或停止当前任务"}'.to_utf8_buffer())
	assert(not assistant.home_button.disabled and assistant.menu_home_feedback.text == "请先完成或停止当前任务", "Bridge rejection must be visible and retryable")
	assistant.home_button.disabled = true
	assistant.home_request.request_completed.emit(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	assert(not assistant.home_button.disabled and assistant.menu_home_feedback.text.contains("无法连接"), "Timeout must allow retry")
	assistant.home_request.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 502, PackedStringArray(), "bad gateway".to_utf8_buffer())
	assert(not assistant.home_button.disabled and assistant.menu_home_feedback.text.contains("无法连接"), "Non-JSON errors must allow retry")
	assistant.home_request.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{}".to_utf8_buffer())
	assert(assistant.menu_home_feedback.text.is_empty() and assistant.home_feedback.text.is_empty(), "Successful retry must clear the previous error")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	assistant._input(escape)
	assert(assistant.panel.visible and paused, "Escape must open the menu and pause")
	assistant._input(escape)
	assert(not assistant.panel.visible and not paused, "Escape must resume the game")
	assistant.free()
	print("PASS: scene, arrow movement, boundary, 10 pickups, victory, R restart")
	print("PASS: visible lobby button, independent request, failure retry, Escape menu and resume")
	print("PASS: offline menu, nested connection path, invalid connection handling, visible bridge rejection and timeout retry")
	quit()
