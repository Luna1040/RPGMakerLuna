extends SceneTree

var game
var failed := false

func _init() -> void:
	call_deferred("run")

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func bar_e() -> void:
	key(KEY_E)
	require(game.bar_action_active, "bar E must start a visible character gesture")
	game.update_bar(game.BAR_INTERACT_DURATION)

func mouse_move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	game._unhandled_input(event)

func mouse_click(position: Vector2, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	game._unhandled_input(event)

func pour_bottle(id: String) -> void:
	for i in range(game.mixer_drinks.size()):
		if game.mixer_drinks[i].id == id:
			var bottle_center: Vector2 = game.mix_bottle_rect(i).get_center()
			mouse_click(bottle_center)
			mouse_click(bottle_center, true)
			require(game.mix_pour_id == id, "double-click must start pouring " + id)
			game.update_mixer(game.MIX_POUR_DURATION)
			require(game.mix_pour_id.is_empty() and id in game.mix_added_ids, "pour must add " + id + " after its animation")
			return
	require(false, "missing bottle " + id)

func require(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error("P0_FLOW_FAIL: " + message)

func kill_all() -> void:
	for enemy in game.enemies.duplicate():
		game.damage_enemy(enemy, 9999.0, Vector2.RIGHT)
	game.check_room_clear()

func run() -> void:
	var packed: PackedScene = load("res://main.tscn")
	game = packed.instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	await process_frame

	# Title -> bar -> full contract dialogue through actual key dispatch.
	require(game.phase_name() == "TITLE", "formal entry must be the title")
	key(KEY_DOWN); key(KEY_ENTER)
	require(game.phase_name() == "TITLE", "disabled title buttons must not enter gameplay")
	key(KEY_UP)
	key(KEY_ENTER)
	require(game.phase_name() == "BAR", "Enter must open walkable bar")
	require(game.BAR_WORLD_SIZE == Vector2(768,432) and game.bar_camera_origin() == Vector2.ZERO, "bar must show its complete 768x432 world")
	require(game.BAR_VIEW_SIZE == game.BAR_WORLD_SIZE and is_equal_approx(game.BAR_VIEW_SCALE,5.0/12.0), "bar viewport must expose the whole room")
	require(game.bar_position_walkable(Vector2(384,280)), "bar must expose a real walkable employee gap")
	require(game.bartender_texture != null and game.zhou_texture != null, "generated bartender and Zhou sprites must load")

	# Mouse hotspot is available immediately: no Zhou dialogue gate.
	game.bar_player = game.BAR_MIX_POS
	var hotspot_screen: Vector2 = game.bar_world_to_screen(game.BAR_MIX_HOTSPOT.get_center())
	mouse_move(hotspot_screen)
	require(game.mix_hotspot_hovered and game.interaction_hint == "开始调制", "counter hover must show exact mixing copy")
	mouse_click(hotspot_screen)
	require(game.bar_action_active and game.phase_name() == "BAR", "counter click must play a visible reach before opening mixer")
	game.update_bar(game.BAR_INTERACT_DURATION)
	require(game.phase_name() == "MIX", "counter hotspot click must open mixer before dialogue")
	key(KEY_ESCAPE)
	require(game.phase_name() == "BAR", "mixer back input must return to the bar")
	game.interaction_hint = ""
	game.bar_player = game.BAR_MIX_POS
	key(KEY_E)
	require(game.bar_action_active, "E near counter must start the interaction animation")
	game.update_bar(game.BAR_INTERACT_DURATION)
	require(game.phase_name() == "MIX", "E near counter must also open mixer without dialogue gate")
	key(KEY_ESCAPE)
	require(game.phase_name() == "BAR", "E-entered mixer must also return to the bar")
	game.bar_player = Vector2(278, 142)
	game.update_bar(0.0)
	require(not "潜航" in game.interaction_hint and not "终端" in game.interaction_hint, "removed dive-machine position must have no old guidance")

	# Dialogue remains as optional story content.
	game.update_bar(4.0)
	require(game.zhou_arrived and game.zhou_pos == game.BAR_ZHOU_POS, "Zhou must walk in from outside before his dialogue opens")
	game.bar_player = game.BAR_ZHOU_POS
	bar_e()
	require(game.phase_name() == "DIALOGUE", "E near Zhou must open dialogue")
	require(game.zhou_action_active, "Zhou must gesture as dialogue opens")
	key(KEY_ENTER) # arrival -> request
	key(KEY_2)     # ask about the body
	key(KEY_ENTER) # body -> warning
	key(KEY_ENTER) # warning -> accepted
	key(KEY_ENTER) # accepted -> end
	require(game.phase_name() == "BAR" and game.bar_stage == "mix_ready", "dialogue must unlock mixing")

	# Three unlocked bottles: one click inspects, double-click pours, then finish.
	game.bar_player = game.BAR_MIX_POS
	bar_e()
	require(game.phase_name() == "MIX", "E near counter must be an equivalent mixer entry")
	for id in ["still_sea", "empathy", "stable"]: pour_bottle(id)
	mouse_click(game.mix_finish_button_rect().get_center())
	require(game.phase_name() == "TRANSITION" and game.cocktail_ids == ["still_sea", "empathy", "stable"], "three poured bottles must become run effects and start memory transition")
	require(is_equal_approx(game.player.max_hp, 120.0) and is_equal_approx(game.paradox_factor, 0.7), "still sea and stable must apply their actual gameplay effects")
	game.update_transition(1.81)
	require(game.phase_name() == "ROOM" and game.room_index == 0, "memory transition must automatically enter room one")

	# The heroine starts with a baton. J must play its windup and land one
	# close-range hit at the action event; no gunshot exists before borrowing.
	require(game.player.form == "heroine", "first room must start in the blue-green-haired heroine form")
	var target: Dictionary = game.enemies[0]
	target.pos = game.player.pos + Vector2(20, 0)
	target.speed = 0.0
	target.cool = 100.0
	var hp_before: float = target.hp
	key(KEY_J)
	require(game.player_attack_state == "baton" and game.projectiles.is_empty(), "J must start a baton action without firing")
	game.update_room(game.BATON_HIT_TIME * 0.5)
	require(is_equal_approx(target.hp, hp_before), "baton must not deal damage before its hit event")
	game.update_room(game.BATON_HIT_TIME * 0.5 + 0.02)
	require(target.hp < hp_before and game.player_attack_event_done, "baton hit event must damage the nearby enemy")
	require(game.projectiles.is_empty(), "heroine baton attacks must remain melee-only")

	# The first captain is borrowed before the medical exit can open. The
	# cafeteria remains visible as an intentional, disabled demo branch.
	kill_all()
	require(game.captain_downed and not game.door_visible, "captain defeat must await borrowing before the medical door opens")
	game.player.pos = game.captain_pos
	key(KEY_E)
	require(game.borrowed and game.player.form == "security_captain", "E near the downed captain must switch form")
	require(game.door_visible, "borrowing the captain must open the medical exit")
	game.player.pos = Vector2(60, 120)
	game.update_room(0.5)
	game.projectiles.clear()
	key(KEY_J)
	require(game.player_attack_state == "gun" and game.projectiles.is_empty(), "captain J must start a gun action with a short windup")
	game.update_room(game.GUN_SHOT_TIME + 0.02)
	require(game.projectiles.size() > 0, "captain gun action must fire at its animation event")
	game.player.pos = Vector2(17,78); key(KEY_E)
	require(game.phase_name() == "ROOM" and game.room_index == 0, "cafeteria demo exit must not enter another room")
	game.player.pos = Vector2(302,96); key(KEY_E)
	require(game.phase_name() == "UPGRADE" and game.pending_room_index == 1, "medical exit must lead to a three-choice upgrade")
	key(KEY_1)
	require(game.phase_name() == "ROOM" and game.room_index == 1 and game.player.form == "security_captain", "upgrade must enter the medical room while keeping captain form")

	# The medic grants one buff reroll, not another body swap.
	kill_all()
	require(game.state.buff_rerolls == 1 and game.state.medical_reroll_claimed, "medic defeat must grant exactly one buff reroll")
	require(game.door_visible and game.player.form == "security_captain", "medical room clear must keep the captain form and reveal the root exit")
	game.player.pos = Vector2(302,96); key(KEY_E)
	require(game.phase_name() == "UPGRADE" and game.pending_room_index == 2, "medical exit must show the upgrade choice before the boss")
	key(KEY_R)
	require(game.state.buff_rerolls == 0 and game.phase_name() == "UPGRADE", "R must consume the earned buff reroll")
	key(KEY_1)
	require(game.phase_name() == "ROOM" and game.room_index == 2, "upgrade must enter the boss room")

	# Boss -> anchor -> one ending -> changed bar -> settlement -> facility -> ending.
	kill_all()
	require(game.anchor_ready, "boss defeat must expose causal anchor")
	game.player.pos = Vector2(284,88); key(KEY_E)
	require(game.phase_name() == "CAUSAL", "anchor interaction must open causal choice")
	key(KEY_2)
	require(game.phase_name() == "RETURN_BAR" and game.state.ending_id() == "shot_preserved", "causal choice must return to changed bar")
	require(game.state.causal_count() == 1, "only one causal flag may be true")
	game.bar_player = game.BAR_COMMS_POS; bar_e()
	require(game.phase_name() == "SETTLEMENT" and game.state.reward_claimed, "bar communicator must settle and pay once")
	var credits_after: int = game.state.credits
	game.prepare_settlement()
	require(game.state.credits == credits_after, "reopening settlement must not duplicate reward")
	key(KEY_ENTER); key(KEY_1)
	require(game.phase_name() == "RETURN_BAR" and game.state.facility == "bar_counter", "facility choice must immediately return to upgraded bar")
	game.bar_player = game.BAR_COMMS_POS; bar_e()
	require(game.phase_name() == "CREDITS", "upgraded bar communicator must reach ending")

	# Pure state invariants: all three endings are mutually exclusive; reward is idempotent.
	var RunStateScript = load("res://run_state.gd")
	var isolated = RunStateScript.new()
	for id in isolated.ENDING_IDS:
		isolated.choose_ending(id)
		require(isolated.ending_id() == id and isolated.causal_count() == 1, "ending flags must stay mutually exclusive: " + id)
	var first: int = isolated.claim_reward(80)
	var second: int = isolated.claim_reward(80)
	require(first > 0 and second == 0 and isolated.credits == first, "reward claim must be idempotent")

	if failed:
		quit(1)
		return
	print("P0_FLOW_PASS title_bar_arrival_hover_click_bottle_mix_transition_baton_captain_two_exits_medic_reroll_boss_endings_reward_upgrade")
	quit(0)
