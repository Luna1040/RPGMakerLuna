extends SceneTree

# Run with a real display renderer and COMBAT_PREVIEW_OUTPUT_DIR set to an
# absolute review directory. Captures never enter res:// or user://.
const OUTPUT_ENV := "COMBAT_PREVIEW_OUTPUT_DIR"

var output_dir := ""

func _init() -> void:
	call_deferred("capture")

func prepare_view(game) -> void:
	game.player.invuln = 0.0
	game.room_intro_time = 0.0
	game.toast_time = 0.0
	game.shake = 0.0
	game.flash = 0.0
	game.queue_redraw()

func save_view(game, file_name: String) -> bool:
	prepare_view(game)
	await process_frame
	await process_frame
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("COMBAT_PREVIEW_FAIL: no viewport texture")
		return false
	var captured: Image = viewport_texture.get_image()
	if captured == null or captured.is_empty():
		push_error("COMBAT_PREVIEW_FAIL: renderer returned no image")
		return false
	captured.resize(1280, 720, Image.INTERPOLATE_NEAREST)
	var output_path := output_dir.path_join(file_name)
	var result := captured.save_png(output_path)
	if result != OK:
		push_error("COMBAT_PREVIEW_FAIL: " + output_path + ": " + error_string(result))
		return false
	print("COMBAT_PREVIEW_SAVED " + output_path)
	return true

func capture() -> void:
	if DisplayServer.get_name() == "headless":
		print("COMBAT_PREVIEW_SKIP headless dummy renderer cannot provide visual QA captures")
		quit(0)
		return
	output_dir = OS.get_environment(OUTPUT_ENV)
	if output_dir.is_empty() or not output_dir.is_absolute_path():
		push_error("COMBAT_PREVIEW_FAIL: set " + OUTPUT_ENV + " to an absolute review directory")
		quit(1)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK:
		push_error("COMBAT_PREVIEW_FAIL: cannot create work output directory: " + error_string(directory_error))
		quit(1)
		return
	root.size = Vector2i(320, 180)
	var game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	await process_frame

	game.start_dive()
	game.player.pos = Vector2(85, 121)
	game.aim_point = Vector2(150, 96)
	if not await save_view(game, "combat-01-security.png"):
		quit(1)
		return
	game.player.pos = Vector2(135, 105)
	var guard: Dictionary = game.enemies[0]
	guard.pos = Vector2(159, 105)
	guard.speed = 0.0
	guard.cool = 100.0
	game.normal_attack(Vector2.RIGHT)
	game.update_player_attack(game.BATON_HIT_TIME + 0.01)
	if not await save_view(game, "combat-01-baton-hit.png"):
		quit(1)
		return
	game.enemies.clear()
	game.captain_downed = true
	game.captain_pos = Vector2(244, 100)
	game.borrow_captain()
	game.player_attack_state = ""
	game.player_attack_elapsed = 0.0
	game.player.pos = Vector2(85, 121)
	if not await save_view(game, "combat-01-borrowed.png"):
		quit(1)
		return

	game.enter_room(1)
	game.player.pos = Vector2(115, 105)
	game.aim_point = Vector2(263, 89)
	if not await save_view(game, "combat-02-medical.png"):
		quit(1)
		return

	game.enter_room(2)
	game.player.pos = Vector2(80, 120)
	game.aim_point = Vector2(235, 88)
	var boss: Dictionary = game.enemies[0]
	boss.armed = true
	boss.pattern = 0
	boss.windup = 0.75
	boss.aim_pos = game.player.pos
	boss.action = "attack_windup"
	if not await save_view(game, "combat-03-root-boss-warning.png"):
		quit(1)
		return
	boss.armed = false
	game.resolve_boss_pattern(boss)
	if not await save_view(game, "combat-03-root-boss-pulse.png"):
		quit(1)
		return
	game.projectiles.clear()
	boss.pattern = 1
	boss.charge_dir = (game.player.pos - boss.pos).normalized()
	game.resolve_boss_pattern(boss)
	if not await save_view(game, "combat-03-root-boss-charge.png"):
		quit(1)
		return
	game.hazards.clear()
	boss.charge = 0.0
	boss.pattern = 2
	boss.aim_pos = game.player.pos
	game.resolve_boss_pattern(boss)
	if not await save_view(game, "combat-03-root-boss-rift.png"):
		quit(1)
		return

	print("COMBAT_PREVIEW_PASS eight_rendered_combat_frames_visual_review_still_required")
	quit(0)
