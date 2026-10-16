extends SceneTree

func _initialize() -> void:
	var script = load("res://jianghu.gd")
	if script == null:
		quit(1)
		return
	var game = script.new()
	game.reset_game()
	assert(game.stage == 0 and game.hp == 120 and game.state == "play")
	game.player = Vector2(410,400)
	game.interact()
	assert(game.stage == 1 and game.enemies.size() == 4)
	game.player = Vector2(600,400)
	game.facing = Vector2.RIGHT
	game.enemies[0].pos = Vector2(650,400)
	var health = game.enemies[0].hp
	game.strike(false)
	assert(game.enemies[0].hp < health)
	var after = game.enemies[0].hp
	game.strike(false)
	assert(game.enemies[0].hp == after, "Cooldown prevents duplicate attacks")
	game.strike(true)
	assert(game.qi == 70 and game.skill_cd == 4)
	game.hp = 30
	game.heal()
	assert(game.hp == 95 and game.potions == 2)
	game.dash()
	assert(game.invincible > 0 and game.dash_cd > 0)
	for wave in range(1,4):
		for e in game.enemies: e.hp = 0
		game.remove_dead()
		assert(game.enemies.is_empty())
		game.player.x = 1150
		game.interact()
	assert(game.state == "win" and game.kills == 12)
	game.reset_game()
	game.hp = 0
	game._process(0.01)
	assert(game.state == "lose")
	game.reset_game()
	assert(game.kills == 0 and game.enemies.is_empty() and game.potions == 3)
	game.player = Vector2(410,400)
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_E
	game._unhandled_input(event)
	assert(game.stage == 1)
	game.player = Vector2(600,400)
	game.facing = Vector2.RIGHT
	game.enemies[0].pos = Vector2(650,400)
	var before = game.enemies[0].hp
	event.keycode = KEY_J
	game._unhandled_input(event)
	assert(game.enemies[0].hp < before, "Keyboard input reaches hit resolution")
	event.keycode = KEY_ESCAPE
	game._unhandled_input(event)
	assert(game.paused)
	var clock_before = game.elapsed
	game._process(1.0)
	assert(game.elapsed == clock_before)
	game._unhandled_input(event)
	assert(not game.paused)
	game.player = Vector2(650,400)
	game.enemies[0].target = game.player
	game.enemies[0].wind = 0.05
	var hp_before = game.hp
	game._process(0.1)
	assert(game.hp < hp_before, "Telegraphed enemy attack resolves damage")
	game.free()
	print("PASS: quest, keyboard-hit chain, cooldown, qi, potion, dash, enemy damage, pause, three waves, win, lose, restart")
	quit(0)
