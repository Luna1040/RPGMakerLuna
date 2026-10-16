extends SceneTree

const Data = preload("res://game_data.gd")

var game
var failed := false

func _init() -> void:
	call_deferred("run")

func require(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error("COMBAT_STAGE_FAIL: " + message)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func enemy_of_type(id: String) -> Dictionary:
	for enemy in game.enemies:
		if enemy.type == id: return enemy
	return {}

func exit_by(room: int, id: String) -> Dictionary:
	for exit_spec in Data.ROOMS[room].exits:
		if exit_spec.id == id: return exit_spec
	return {}

func upgrade_ids() -> Array[String]:
	var ids: Array[String] = []
	for option in game.upgrade_options: ids.append(option.id)
	return ids

func clear_enemies() -> void:
	for enemy in game.enemies.duplicate():
		game.damage_enemy(enemy, 9999.0, Vector2.ZERO)
	game.check_room_clear()

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	await process_frame
	game.start_dive()

	# Three authored maps, distinct portrait identities, and the first room's
	# two clearly different exits are the playable demo's scene contract.
	require(Data.ROOMS.size() == 3, "demo must contain exactly three authored combat stages")
	var map_ids: Array[String] = []
	for room in Data.ROOMS: map_ids.append(room.map_id)
	require(map_ids[0] != map_ids[1] and map_ids[1] != map_ids[2] and map_ids[0] != map_ids[2], "combat stages must use different maps")
	for map_id in map_ids:
		require(game.combat_map_textures.has(map_id) and game.combat_map_textures[map_id] != null, map_id + " map art must import")
	for role in ["heroine", "guard", "captain", "captain_melee", "medic", "corrector"]:
		require(game.combat_portraits.has(role) and game.combat_portraits[role] != null, role + " portrait must import")
		var actions: Dictionary = game.combat_sprites.get(role, {})
		for action in ["idle", "attack_windup", "attack_hit", "hurt"]:
			require(actions.has(action) and actions[action] != null, role + " " + action + " frame must import")
	for role in ["heroine", "guard", "captain", "captain_melee", "medic"]:
		var actions: Dictionary = game.combat_sprites.get(role, {})
		for action in ["walk_a", "walk_b"]:
			require(actions.has(action) and actions[action] != null, role + " walking frame must import: " + action)
	require(game.portrait_key_for_enemy("melee") == "guard", "ordinary enemies must share the guard portrait")
	require(game.portrait_key_for_enemy("security_captain") == "captain_melee", "unborrowed captain must display the melee portrait")
	require(game.portrait_key_for_enemy("medic") == "medic" and game.portrait_key_for_enemy("boss") == "corrector", "medical and final bosses need their own portraits")
	var medical_exit := exit_by(0, "medical")
	var cafeteria_exit := exit_by(0, "cafeteria")
	require(not medical_exit.is_empty() and medical_exit.enabled and medical_exit.target == "medical", "first room needs an enabled medical exit")
	require(not cafeteria_exit.is_empty() and not cafeteria_exit.enabled and cafeteria_exit.target == "cafeteria", "first room needs a visible disabled cafeteria exit")
	for id in ["melee", "security_captain", "medic", "boss"]:
		require(not str(Data.CHARACTERS[id].get("portrait_id", "")).is_empty(), id + " needs a portrait identity")
	require(Data.CHARACTERS.melee.portrait_id != Data.CHARACTERS.security_captain.portrait_id and Data.CHARACTERS.security_captain.portrait_id != Data.CHARACTERS.medic.portrait_id and Data.CHARACTERS.medic.portrait_id != Data.CHARACTERS.boss.portrait_id, "ordinary enemies may share a portrait, bosses must have distinct portraits")
	require(game.phase_name() == "ROOM" and game.room_index == 0 and game.player.form == "heroine", "dive must enter the security stage as the heroine")
	for enemy in game.enemies:
		require(Data.CHARACTERS[enemy.type].attack_style == "melee", "all first-stage enemies, including captain, must fight in melee")

	# Real J input must first show a baton action, then land exactly one nearby
	# hit at its event. A distant target remains unharmed and no bullet appears.
	var foe := enemy_of_type("melee")
	var captain := enemy_of_type("security_captain")
	require(not foe.is_empty() and not captain.is_empty(), "security stage must contain common enemies and the captain")
	if foe.is_empty() or captain.is_empty():
		quit(1)
		return
	for enemy in game.enemies:
		enemy.speed = 0.0
		enemy.cool = 100.0
	foe.pos = game.player.pos + Vector2(22, 0)
	var foe_hp: float = foe.hp
	key(KEY_J)
	require(game.player_attack_state == "baton" and not game.player_attack_event_done, "J must begin the heroine's baton action")
	require(game.projectiles.is_empty() and is_equal_approx(foe.hp, foe_hp), "baton may not spawn a bullet or hit on keydown")
	game.update_room(game.BATON_HIT_TIME * 0.45)
	require(is_equal_approx(foe.hp, foe_hp), "baton windup must precede damage")
	game.update_room(game.BATON_HIT_TIME * 0.60)
	require(foe.hp < foe_hp and game.player_attack_event_done, "the baton event must strike the nearby target")
	var hp_after_hit: float = foe.hp
	game.update_room(0.20)
	require(is_equal_approx(foe.hp, hp_after_hit), "one baton press must not hit the same enemy twice")
	game.update_room(0.40)
	foe.pos = game.player.pos + Vector2(80, 0)
	foe_hp = foe.hp
	game.attack_cd = 0.0
	key(KEY_J)
	require(game.player_attack_state == "baton", "second J press must start another baton action")
	game.update_room(game.BATON_HIT_TIME + 0.04)
	require(is_equal_approx(foe.hp, foe_hp) and game.projectiles.is_empty(), "baton must miss a distant enemy without firing")

	# A common guard and the captain telegraph close attacks. Their actual hit
	# can hurt the player, but neither enemy fires during stage one.
	game.update_room(0.35)
	foe.pos = game.player.pos + Vector2(13, 0)
	foe.cool = 0.0
	foe.armed = false
	foe.windup = 0.0
	game.player.invuln = 0.0
	var player_hp: float = game.player.hp
	game.update_room(0.02)
	require(foe.armed and is_equal_approx(game.player.hp, player_hp), "guard melee must telegraph before damage")
	game.update_room(0.52)
	require(game.player.hp < player_hp and player_hp - game.player.hp <= foe.damage + 0.01, "guard melee should land one bounded hit")
	require(game.projectiles.is_empty(), "first-stage guards must not shoot")
	game.enemies = [captain]
	captain.pos = game.player.pos + Vector2(13, 0)
	captain.speed = 0.0
	captain.cool = 0.0
	captain.armed = false
	captain.windup = 0.0
	game.player.invuln = 0.0
	player_hp = game.player.hp
	game.update_room(0.02)
	require(captain.armed and is_equal_approx(game.player.hp, player_hp), "captain's melee attack must show a windup")
	game.update_room(0.65)
	require(game.player.hp < player_hp and player_hp - game.player.hp <= captain.damage + 0.01, "captain must remain a bounded melee threat")
	require(game.projectiles.is_empty(), "captain may not use a gun before possession")

	# Defeating the captain alone does not open the medical path. Once E borrows
	# his body, the same J input becomes a delayed gunshot that can hit a target.
	game.damage_enemy(captain, 9999.0, Vector2.ZERO)
	game.check_room_clear()
	require(game.captain_downed and not game.door_visible, "medical route must wait for captain possession")
	game.player.pos = medical_exit.pos
	key(KEY_E)
	require(game.phase_name() == "ROOM" and game.room_index == 0, "medical exit cannot be used before borrowing")
	game.player.pos = game.captain_pos
	key(KEY_E)
	require(game.borrowed and game.player.form == "security_captain" and game.door_visible, "E must change form and unlock the medical exit")
	game.player.pos = Vector2(48, 112)
	game.last_move = Vector2.RIGHT
	game.update_room(0.50)
	game.projectiles.clear()
	game.attack_cd = 0.0
	key(KEY_J)
	require(game.player_attack_state == "gun" and game.projectiles.is_empty(), "captain J must begin a gun animation before firing")
	game.update_room(game.GUN_SHOT_TIME * 0.45)
	require(game.projectiles.is_empty(), "gun muzzle event must not happen early")
	game.update_room(game.GUN_SHOT_TIME * 0.65)
	require(game.projectiles.size() > 0 and game.player_attack_event_done, "gun action must create a shot at its event")
	if game.projectiles.is_empty():
		quit(1)
		return
	var shot: Dictionary = game.projectiles[0]
	var gun_target: Dictionary = game.make_enemy({"type":"melee", "pos":shot.pos + shot.vel.normalized() * 32.0})
	gun_target.speed = 0.0
	gun_target.cool = 100.0
	game.enemies = [gun_target]
	var gun_target_hp: float = gun_target.hp
	for _step in range(20):
		game.update_projectiles(0.02)
		if gun_target.hp < gun_target_hp: break
	require(gun_target.hp < gun_target_hp, "gunshot must travel, collide, and damage a target")
	game.enemies.clear()

	game.player.pos = cafeteria_exit.pos
	key(KEY_E)
	require(game.phase_name() == "ROOM" and game.room_index == 0, "disabled cafeteria route must never change stage")
	game.player.pos = medical_exit.pos
	key(KEY_E)
	require(game.phase_name() == "UPGRADE" and game.pending_room_index == 1, "enabled medical exit must open the first upgrade choice")
	var initial_choices := upgrade_ids()
	key(KEY_R)
	require(game.state.buff_rerolls == 0 and upgrade_ids() == initial_choices, "no buff reroll is available before defeating the medic")
	key(KEY_1)
	require(game.phase_name() == "ROOM" and game.room_index == 1 and game.player.form == "security_captain", "first upgrade must enter the medical room in captain form")

	# The medic drops exactly one refresh. R changes the next three upgrade
	# choices once; a second R cannot consume another or reshuffle them again.
	var medic := enemy_of_type("medic")
	require(not medic.is_empty(), "second stage must contain its medic mini-boss")
	if medic.is_empty():
		quit(1)
		return
	game.damage_enemy(medic, 9999.0, Vector2.ZERO)
	require(game.state.medical_reroll_claimed and game.state.buff_rerolls == 1, "medic defeat must award one buff refresh")
	game.damage_enemy(medic, 9999.0, Vector2.ZERO)
	require(game.state.buff_rerolls == 1, "medic refresh must not be awarded twice")
	clear_enemies()
	require(game.door_visible, "medical room clear must reveal the root entrance")
	game.player.pos = Vector2(302, 96)
	key(KEY_E)
	require(game.phase_name() == "UPGRADE" and game.pending_room_index == 2, "root entrance must present the second buff choice")
	var before_refresh := upgrade_ids()
	key(KEY_R)
	var after_refresh := upgrade_ids()
	require(game.state.buff_rerolls == 0 and after_refresh.size() == 3 and after_refresh != before_refresh, "R must consume one refresh and replace the three options")
	key(KEY_R)
	require(game.state.buff_rerolls == 0 and upgrade_ids() == after_refresh, "R with no refreshes must leave the choices unchanged")
	key(KEY_1)
	require(game.phase_name() == "ROOM" and game.room_index == 2, "second upgrade must enter the third-stage boss arena")

	# Boss attacks must announce themselves before release. All authored
	# direct, projectile, and area damage stays low enough for a demo showcase.
	var boss := enemy_of_type("boss")
	require(not boss.is_empty() and Data.CHARACTERS.boss.damage <= 5.0, "third stage needs a demo-damage boss")
	if boss.is_empty():
		quit(1)
		return
	var observed_patterns: Array = []
	for _pattern in range(3):
		game.enemies = [boss]
		game.projectiles.clear()
		game.hazards.clear()
		boss.charge = 0.0
		boss.armed = false
		boss.windup = 0.0
		boss.cool = 0.0
		game.player.invuln = 0.0
		player_hp = game.player.hp
		game.update_room(0.01)
		require(boss.armed and boss.windup > 0.0 and is_equal_approx(game.player.hp, player_hp), "each boss pattern must telegraph before damage")
		if not (boss.pattern in observed_patterns): observed_patterns.append(boss.pattern)
		var remaining_windup: float = boss.windup
		game.update_room(remaining_windup + 0.02)
		require(player_hp - game.player.hp <= 5.01, "one boss release may not cause a high-damage hit")
		var expected_fx: String = ["boss_halo", "boss_charge", "boss_rift"][boss.pattern]
		require(game.combat_fx_kind == expected_fx and game.combat_fx_time > 0.0, "each boss pattern must trigger its own visible effect state")
		match boss.pattern:
			0:
				require(game.projectiles.any(func(shot): return shot.kind == "boss_pulse"), "halo release must launch radial pulse projectiles")
			1:
				require(boss.charge > 0.0, "charge release must launch the boss lunge")
			2:
				require(game.hazards.any(func(hazard): return hazard.kind == "rift" and hazard.damage <= 5.0), "rift release must place low-damage hazards")
		for enemy_shot in game.projectiles:
			if enemy_shot.enemy: require(enemy_shot.damage <= 5.0, "boss projectile damage must stay demo-friendly")
	require(observed_patterns.size() == 3, "boss must cycle through three distinct attack patterns")
	game.enemies = [boss]
	game.damage_enemy(boss, 9999.0, Vector2.ZERO)
	game.check_room_clear()
	require(game.anchor_ready, "boss defeat must reveal the causal anchor")
	game.player.pos = Vector2(284, 88)
	key(KEY_E)
	require(game.phase_name() == "CAUSAL", "anchor must remain interactable after the new boss fight")

	if failed:
		quit(1)
		return
	print("COMBAT_STAGE_PASS baton_event_first_room_melee_captain_borrow_gun_two_exits_medical_reroll_three_boss_patterns_anchor")
	quit(0)
