extends SceneTree

var game
var failed := false

func _init() -> void:
	call_deferred("run")

func require(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error("MIXER_FAIL: " + message)

func mouse_click(position: Vector2, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	game._unhandled_input(event)

func bottle_index(id: String) -> int:
	for i in range(game.mixer_drinks.size()):
		if game.mixer_drinks[i].id == id: return i
	return -1

func bottle_click(id: String, double_click := false) -> void:
	var index := bottle_index(id)
	if index < 0:
		require(false, "missing bottle " + id)
		return
	mouse_click(game.mix_bottle_rect(index).get_center(), double_click)

func pour_bottle(id: String) -> void:
	bottle_click(id)
	bottle_click(id, true)
	require(game.mix_pour_id == id, "double-click must start pouring " + id)
	var before_count: int = game.mix_added_ids.size()
	game.update_mixer(game.MIX_POUR_DURATION * 0.5)
	require(game.mix_added_ids.size() == before_count and game.mix_pour_id == id, "bottle must stay in the pour animation before " + id + " is added")
	game.update_mixer(game.MIX_POUR_DURATION * 0.5 + 0.01)
	require(game.mix_pour_id.is_empty() and game.mix_added_ids.size() == before_count + 1 and game.mix_added_ids.back() == id, "completed pour must add exactly one " + id)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	await process_frame
	game.open_mixer()
	require(game.phase == game.Phase.MIX and game.mixer_drinks.size() == 6, "mixer must expose six bottle choices")
	for id in ["still_sea", "empathy", "stable"]:
		require(game.state.is_drink_unlocked(id), "starter bottle must be unlocked: " + id)
	for id in ["reverse_fire", "anger", "overload"]:
		require(not game.state.is_drink_unlocked(id), "credit bottle must begin locked: " + id)
	for drink in game.mixer_drinks:
		require(game.mixer_bottle_textures.get(drink.id) != null, "pixel bottle art must load: " + drink.id)

	# A bare finish cannot start a run; one click only inspects the selected bottle.
	mouse_click(game.mix_finish_button_rect().get_center())
	require(game.phase == game.Phase.MIX and game.mix_added_ids.is_empty(), "empty glass must not finish")
	bottle_click("empathy")
	require(game.mix_selected_id == "empathy" and "显示隐藏叙事线索" in game.mix_message and game.mix_added_ids.is_empty() and game.mix_pour_id.is_empty(), "single click must display the bottle's effect without pouring")
	bottle_click("empathy", true)
	require(game.mix_pour_id == "empathy" and game.mix_added_ids.is_empty(), "double-click must start an animated pour before adding the ingredient")
	mouse_click(game.mix_finish_button_rect().get_center())
	require(game.phase == game.Phase.MIX and game.mix_pour_id == "empathy", "finish must wait for the pour animation")
	game.update_mixer(game.MIX_POUR_DURATION * 0.5)
	require(game.mix_added_ids.is_empty() and game.mix_pour_id == "empathy", "halfway through the animation the glass must still be empty")
	game.update_mixer(game.MIX_POUR_DURATION * 0.5 + 0.01)
	require(game.mix_added_ids == ["empathy"] and game.mix_pour_id.is_empty(), "animation completion must add empathy once")
	bottle_click("empathy", true)
	require(game.mix_added_ids == ["empathy"] and game.mix_pour_id.is_empty() and "同一种" in game.mix_message, "same bottle cannot be added twice")

	# Locked drinks can be inspected but cannot pour; cellar purchases use credits once.
	bottle_click("reverse_fire")
	bottle_click("reverse_fire", true)
	require(game.mix_selected_id == "reverse_fire" and game.mix_pour_id.is_empty() and game.mix_added_ids == ["empathy"] and "尚未解锁" in game.mix_message, "locked bottle must refuse pouring")
	mouse_click(game.mix_cellar_button_rect().get_center())
	require(game.mix_cellar_open, "cellar button must open the catalog")
	mouse_click(game.mix_cellar_card_rect(bottle_index("reverse_fire")).get_center())
	require(game.mix_selected_id == "reverse_fire" and "稀有" in game.mix_message, "cellar card must expose the locked bottle's quality")
	mouse_click(game.mix_cellar_buy_button_rect().get_center())
	require(not game.state.is_drink_unlocked("reverse_fire") and game.state.credits == 0 and "120" in game.mix_message, "insufficient credits must not unlock or debit")
	game.state.credits = 200
	mouse_click(game.mix_cellar_buy_button_rect().get_center())
	require(game.state.is_drink_unlocked("reverse_fire") and game.state.credits == 80, "purchase must debit the listed 120 credits and unlock reverse fire")
	mouse_click(game.mix_cellar_buy_button_rect().get_center())
	require(game.state.credits == 80 and game.state.unlocked_drinks.count("reverse_fire") == 1 and not game.state.buy_drink("reverse_fire"), "repeat purchase must not debit credits or duplicate an unlock")
	mouse_click(game.mix_back_rect().get_center())
	require(not game.mix_cellar_open and game.phase == game.Phase.MIX, "cellar back button must return to the glass")

	# Three unique bottles fit; a fourth unlocked bottle is refused.
	pour_bottle("reverse_fire")
	pour_bottle("stable")
	require(game.mix_added_ids == ["empathy", "reverse_fire", "stable"], "three distinct bottles must fill the glass in click order")
	bottle_click("still_sea")
	bottle_click("still_sea", true)
	require(game.mix_pour_id.is_empty() and game.mix_added_ids.size() == 3 and "最多" in game.mix_message, "fourth bottle must not exceed the three-drink cap")
	mouse_click(game.mix_finish_button_rect().get_center())
	require(game.phase == game.Phase.TRANSITION and game.cocktail_ids == ["empathy", "reverse_fire", "stable"], "three-bottle recipe must finish with exactly the poured ingredients")
	require(is_equal_approx(game.player.damage, 20.7) and is_equal_approx(game.paradox_factor, 0.7) and not game.anger_reward, "reverse fire and stable must apply only their chosen effects")
	game.update_transition(1.81)
	for enemy in game.enemies.duplicate():
		game.damage_enemy(enemy, 9999.0, Vector2.ZERO)
	game.check_room_clear()
	require(game.captain_downed and not game.room_clear, "first room must await captain possession after the fight")
	game.player.pos = game.captain_pos
	var borrow_key := InputEventKey.new()
	borrow_key.keycode = KEY_E
	borrow_key.pressed = true
	game._unhandled_input(borrow_key)
	require(game.player.form == "security_captain" and game.room_clear, "E must borrow the captain and complete room one")
	require(game.state.clues.has("zhou_fear") and is_equal_approx(game.state.paradox, 6.3), "empathy must reveal its clue while stable reduces room and borrowing paradox")

	# Unlocks and remaining credits survive a new run; one ingredient is enough.
	game.restart_demo()
	require(game.phase == game.Phase.TITLE and game.state.credits == 80 and game.state.is_drink_unlocked("reverse_fire") and game.cocktail_ids.is_empty(), "restart must preserve cellar ownership and credits but clear the last recipe")
	game.open_mixer()
	pour_bottle("still_sea")
	mouse_click(game.mix_finish_button_rect().get_center())
	require(game.phase == game.Phase.TRANSITION and game.cocktail_ids == ["still_sea"] and is_equal_approx(game.player.max_hp, 120.0) and is_equal_approx(game.player.damage, 18.0), "one-bottle recipe must finish and grant only its HP effect")

	# A two-bottle recipe exercises the remaining locked effects after earned ownership.
	game.restart_demo()
	game.state.credits = 440
	require(game.state.buy_drink("anger") and game.state.buy_drink("overload") and game.state.credits == 80, "drink prices must come from data and debit 140 plus 220 credits")
	game.restart_demo()
	require(game.state.credits == 80 and game.state.is_drink_unlocked("anger") and game.state.is_drink_unlocked("overload"), "later unlocked bottles must also persist across a restart")
	game.open_mixer()
	pour_bottle("anger")
	pour_bottle("overload")
	mouse_click(game.mix_finish_button_rect().get_center())
	require(game.phase == game.Phase.TRANSITION and game.cocktail_ids == ["anger", "overload"], "two-bottle recipe must finish without forcing a third choice")
	require(game.anger_reward and game.state.clues.has("overload_echo") and is_equal_approx(game.state.paradox, 20.0), "anger and overload must apply their reward and paradox effects")
	game.update_transition(1.81)
	require(game.enemies.size() == 4, "anger must add an enemy to the first memory room")

	if failed:
		quit(1)
		return
	print("MIXER_PASS inspect_double_click_delayed_pour_unique_three_cellar_purchase_recipes_effects_restart")
	quit(0)
