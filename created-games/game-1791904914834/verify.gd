extends SceneTree
var failures := 0
var passes := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func key(game: Node, code: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	game._unhandled_input(event)

func click(game: Node, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	game._unhandled_input(event)

func fixture(game: Node) -> void:
	game.reset(42)
	game.challenge = false
	game.state = "playing"
	game.player = Vector2i(8, 5)
	game.visual_player = Vector2(game.player)
	for y in range(1, 106): game.rows[y].fill(-1)
	game.gravity_dirty = false
	game.warning_delay_enabled = false # Isolate existing mechanics from the new pre-fall timer.

func cut(game: Node) -> void:
	key(game, KEY_SPACE)
	game.simulate(0.35)

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://expedition.gd")
	check(not source.contains("?") and not source.contains(char(0xfffd)), "UI source contains no encoding replacement characters")
	var ui_font: Font = load("res://font.ttf")
	var glyphs_ok := true
	for index in range(source.length()):
		var code := source.unicode_at(index)
		if code >= 0x4e00 and code <= 0x9fff and not ui_font.has_char(code): glyphs_ok = false
	check(glyphs_ok, "current font covers every Chinese character in UI source")
	var game = load("res://expedition.gd").new()
	game.reset(42)
	check(game.state == "briefing" and game.player.y == 0, "starts at depth zero")
	var exact_rows := true
	for y in range(1, 101):
		for x in range(game.WIDTH):
			if (y <= 5) != (game.stone(Vector2i(x, y)) == -1): exact_rows = false
	check(exact_rows, "layer consists of exactly five air rows and 95 full rock rows")
	game.ensure_rows(205)
	check(game.stone(Vector2i(8, 101)) == -1 and game.stone(Vector2i(8, 105)) == -1 and game.stone(Vector2i(8, 106)) >= 0 and game.stone(Vector2i(8, 200)) >= 0, "second layer repeats 5 plus 95 layout")
	var obstacle_count := 0
	var strengths := {}
	for y in range(6, 101):
		for x in range(game.WIDTH):
			var id: int = game.stone(Vector2i(x, y))
			if id >= game.BLACK_BASE:
				obstacle_count += 1
				strengths[id - game.BLACK_BASE + 1] = true
	check(obstacle_count > 0 and strengths.size() == 9, "random black obstacles include strengths one through nine")
	key(game, KEY_ENTER)
	for tick in range(8): game.simulate(0.11)
	check(game.player.y == 5 and game.cuts == 0, "initial automatic five-meter fall lands on stone without cutting")
	fixture(game)
	game.rows[6][8] = 0
	game.rows[6][9] = 0
	game.rows[7][9] = 0
	game.rows[8][8] = 0
	game.rows[6][11] = 0
	game.gravity_enabled = false
	check(game.cluster(Vector2i(8, 6)).size() == 3, "four-way cluster excludes diagonal and disconnected stones")
	cut(game)
	check(game.last_chain == 3 and game.cuts == 1 and game.score == 40 and game.player.y == 6, "Space hit destroys connected color group and allows one grid fall")
	check(game.stone(Vector2i(8, 8)) == 0 and game.stone(Vector2i(11, 6)) == 0, "disconnected colors survive hit")
	fixture(game)
	game.rows[6][8] = 8 # black strength 3
	game.rows[6][9] = 8
	game.rows[7][8] = 0
	game.gravity_enabled = false
	cut(game)
	check(game.stone(Vector2i(8, 6)) == 7 and game.stone(Vector2i(9, 6)) == 8 and game.player.y == 5, "first obstacle hit decrements only targeted three to two")
	cut(game)
	check(game.stone(Vector2i(8, 6)) == 6 and game.broken == 0, "second obstacle hit leaves one; no premature destruction")
	cut(game)
	check(game.stone(Vector2i(8, 6)) == -1 and game.stone(Vector2i(9, 6)) == 8 and game.stone(Vector2i(8, 7)) == 0 and game.broken == 1, "third hit breaks only targeted obstacle; no black or color chain")
	fixture(game)
	game.rows[6][8] = 14
	game.rows[7][8] = 6
	game.gravity_enabled = false
	for hit in range(8): cut(game)
	check(game.stone(Vector2i(8, 6)) == 6 and game.cuts == 8, "strength nine survives eight hits with one remaining")
	cut(game)
	check(game.stone(Vector2i(8, 6)) == -1 and game.cuts == 9, "strength nine breaks on ninth hit")
	fixture(game)
	game.rows[10][3] = 0
	game.rows[10][4] = 0
	game.rows[11][3] = 6
	for y in range(12, 101): game.rows[y][3] = 6
	check(not game.settle_rocks() and game.stone(Vector2i(4, 10)) == 0, "one bottom support holds entire horizontal color component")
	game.rows[11][3] = -1
	check(game.settle_rocks() and game.stone(Vector2i(3, 11)) == 0 and game.stone(Vector2i(4, 11)) == 0 and game.stone(Vector2i(3, 10)) == -1, "removing final support drops component rigidly one cell")
	fixture(game)
	game.rows[10][3] = 0
	game.rows[10][4] = 0
	game.rows[11][4] = 0
	game.settle_rocks()
	check(game.stone(Vector2i(3, 11)) == 0 and game.stone(Vector2i(4, 11)) == 0 and game.stone(Vector2i(4, 12)) == 0, "L-shaped component retains geometry while falling")
	fixture(game)
	game.rows[10][3] = 0
	game.rows[10][4] = 0
	game.rows[12][3] = 0
	game.rows[12][4] = 0
	game.rows[13][3] = 6
	for y in range(14, 101): game.rows[y][3] = 6
	game.settle_rocks()
	check(game.stone(Vector2i(3, 11)) == -1 and game.stone(Vector2i(4, 12)) == -1 and game.collision_broken == 4 and game.cuts == 0, "falling component hits same color and destroys both clusters without a cut")
	check(game.stone(Vector2i(3, 13)) == 6, "collision does not damage black obstacle")
	fixture(game)
	game.rows[10][3] = 0
	game.rows[12][3] = 1
	game.rows[13][3] = 6
	for y in range(14, 101): game.rows[y][3] = 6
	game.settle_rocks()
	check(game.stone(Vector2i(3, 11)) == 0 and game.stone(Vector2i(3, 12)) == 1 and game.collision_broken == 0, "falling color lands on different color without breaking")
	check(not game.settle_rocks(), "landed stack stays supported")
	fixture(game)
	game.rows[10][3] = 9
	check(game.settle_rocks() and game.stone(Vector2i(3, 11)) == 9, "unsupported black obstacle falls with hit count intact")
	game.rows[13][3] = 9
	for y in range(14, 101): game.rows[y][3] = 6
	game.settle_rocks()
	check(game.stone(Vector2i(3, 12)) == 9 and game.stone(Vector2i(3, 13)) == 9 and game.collision_broken == 0, "black stones land on matching black without breaking or merging")
	game.rows[100][3] = 0
	game.settle_rocks()
	check(game.stone(Vector2i(3, 100)) == 0 and game.stone(Vector2i(3, 101)) == -1, "layer boundary preserves next five-meter air gap")
	fixture(game)
	game.player = Vector2i(3, 11)
	game.rows[10][3] = 0
	game.settle_rocks()
	check(game.stone(Vector2i(3, 11)) == -1 and game.stone(Vector2i(3, 10)) == 0, "falling rocks cannot overwrite player")
	fixture(game)
	game.player.y = 99
	game.rows[100][8] = 0
	game.gravity_enabled = false
	cut(game)
	check(game.state == "cleared" and game.depth == 100 and game.level == 1, "breaking final 95th rock row completes first level at 100 meters")
	var cuts_at_clear: int = game.cuts
	game.simulate(1)
	check(game.player.y == 100 and game.cuts == cuts_at_clear, "completion waits for another slash; no automatic layer skipping")
	key(game, KEY_SPACE)
	check(game.level == 2 and game.state == "playing" and game.cuts == cuts_at_clear + 1, "one additional Space slash enters second layer")
	game.rows[106][8] = 6
	for tick in range(6): game.simulate(0.11)
	check(game.player.y == 105 and game.stone(Vector2i(8, 106)) == 6, "next level falls five meters then stands on next rock section")
	fixture(game)
	game.player = Vector2i(8, 6)
	game.gravity_enabled = false
	game.rows[7][8] = 6
	game.rows[6][7] = 1
	game.rows[5][7] = 1 # A two-high wall cannot be climbed.
	game.rows[6][9] = 2
	key(game, KEY_LEFT)
	check(game.facing == Vector2i.LEFT and not game.hit_pending and game.player.x == 8, "left arrow turns at wall without attacking")
	key(game, KEY_SPACE)
	check(game.attack_target == Vector2i(7, 6), "Space targets immediate facing-left stone")
	key(game, KEY_RIGHT)
	check(game.facing == Vector2i.LEFT, "cannot retarget active slash")
	game.simulate(0.4)
	key(game, KEY_DOWN)
	check(game.facing == Vector2i.DOWN and not game.hit_pending, "down arrow selects front and does not slash")
	for code in [KEY_Q, KEY_E, KEY_S]: key(game, code)
	check(not game.hit_pending, "obsolete keys do not attack")
	game.camera_row = 2.5
	click(game, Vector2(1100, 450))
	check(not game.hit_pending, "click sidebar does not attack")
	click(game, game.screen_pos(Vector2(8, 7)) + Vector2.ONE * 20)
	check(game.hit_pending and game.attack_target == Vector2i(8, 7), "fractional camera click correctly targets facing adjacent obstacle")
	var before: float = game.elapsed
	key(game, KEY_ESCAPE)
	game.simulate(3)
	check(game.state == "paused" and game.elapsed == before, "pause freezes character and stone simulation")
	fixture(game)
	game.challenge = true
	game.cuts = 150
	game.rows[6][8] = 6
	game.simulate(0.11)
	check(game.state == "lost", "optional per-layer challenge fails after 150 cuts when grounded")
	key(game, KEY_R)
	check(game.state == "menu", "R returns to save menu instead of discarding progress")
	game.reset(42)
	game.challenge = false
	game.state = "playing"
	# Deep generation test advances at each explicit checkpoint.
	for y in range(1, 20001):
		if game.state == "cleared": game.begin_attack()
		game.ensure_rows(y + 1)
		game.rows[y][8] = -1
		if not game.step_down():
			check(false, "stress descent unexpectedly blocked")
			break
	check(game.depth == 20000 and game.level == 200 and game.state == "cleared", "200 explicit hundred-meter levels reachable")
	check(game.rows.size() <= 175 and game.retained_from > 19000, "active layer retained but world memory remains bounded")
	game.reset(231)
	game.challenge = false
	game.state = "playing"
	for frame in range(3000):
		game.begin_attack()
		game.simulate(0.05)
		if game.state == "cleared": break
	check(game.state == "cleared" and game.depth == 100 and game.cuts > 0, "full generated layer playable with live obstacles, falling groups and repeated cuts")
	var before_clear: int = game.cuts
	game._process(0.05)
	check(game.state == "cleared" and game.cuts == before_clear, "frame update cannot auto-advance cleared stage")
	key(game, KEY_SPACE)
	for tick in range(7): game.simulate(0.11)
	check(game.level == 2 and game.player.y == 105, "real cleared world transitions and lands five meters into level two")
	game.save_dir = "res://art-jobs/mouse-warning-20261014/test-saves"
	for slot in range(game.SAVE_LIMIT):
		if FileAccess.file_exists(game.slot_path(slot)): game.delete_game(slot)
	check(game.new_game(0), "new game creates a durable local slot")
	var start: String = game.started_at
	game.rows[6][8] = 9
	game.attack_target = Vector2i(8, 6)
	game.attack_direction = Vector2i.DOWN
	game.attack_time = 0.25
	game.hit_pending = true
	game.depth = 5
	game.player.y = 5
	game.cuts = 27
	var rng_state: int = game.rng.state
	check(game.save_game(), "manual save succeeds including pending slash")
	game.reset(7)
	check(game.load_game(0) and game.depth == 5 and game.cuts == 27 and game.stone(Vector2i(8, 6)) == 9 and game.hit_pending and game.rng.state == rng_state, "save round trip restores rocks, position, cuts, RNG and pending hit")
	check(game.started_at == start and not game.last_played.is_empty(), "save records original start and last-played timestamps")
	game.gravity_enabled = false
	game.simulate(0.1)
	check(game.stone(Vector2i(8, 6)) == 8 and game.cuts == 27, "restored pending hit resolves once without counting saved slash twice")
	game.player.y = 99
	game.rows[100][8] = -1
	game.step_down()
	check(game.read_slot(0).depth == 100 and game.read_slot(0).state == "cleared", "hundred-meter completion automatically saves cleared checkpoint")
	game.open_menu()
	check(game.load_game(0) and game.state == "cleared" and game.level == 1, "loading completed checkpoint still waits for deliberate next slash")
	game.begin_attack()
	check(game.level == 2 and game.camera_row == 100, "next slash switches to separate layer viewport")
	for slot in range(1, game.SAVE_LIMIT): check(game.new_game(slot), "create slot %d" % slot)
	check(not game.new_game(0) and not game.new_game(6), "full slots cannot be overwritten or exceed one-page limit")
	game.state = "menu"
	game.menu_click(Vector2(1040, 200))
	check(FileAccess.file_exists(game.slot_path(0)), "first delete click only requests confirmation")
	game.menu_click(Vector2(1040, 200))
	check(not FileAccess.file_exists(game.slot_path(0)) and game.new_game(0), "confirmed delete frees slot for new game")
	for slot in range(game.SAVE_LIMIT): game.delete_game(slot)
	game.active_slot = -1
	fixture(game)
	game.player = Vector2i(8, 10)
	game.rows[11][8] = 6
	game.rows[10][9] = 0
	key(game, KEY_RIGHT)
	check(game.player == Vector2i(9, 9) and game.facing == Vector2i.RIGHT and game.fatigue == 0, "right movement climbs one-high obstacle without a cut or fatigue")
	fixture(game)
	game.player = Vector2i(8, 10)
	game.rows[11][8] = 6
	game.rows[10][7] = 6
	key(game, KEY_LEFT)
	check(game.player == Vector2i(7, 9), "left movement can climb black single-height obstacle")
	fixture(game)
	game.player = Vector2i(8, 10)
	game.rows[11][8] = 6
	game.rows[10][9] = 0
	game.rows[9][8] = 1
	key(game, KEY_RIGHT)
	check(game.player == Vector2i(8, 10), "overhead obstruction prevents climbing through ceiling")
	fixture(game)
	game.rows[10][3] = 0
	game.rows[11][4] = 0
	for y in range(12, 101): game.rows[y][4] = 6
	game.settle_rocks()
	check(game.stone(Vector2i(3, 11)) == -1 and game.stone(Vector2i(4, 11)) == -1 and game.collision_broken == 2, "falling color touching same color on its side destroys both immediately")
	fixture(game)
	game.rows[10][3] = 9
	game.gravity_dirty = true
	game.simulate(game.PLAYER_FALL_INTERVAL)
	check(game.player.y == 6 and game.stone(Vector2i(3, 10)) == 9, "first interval moves player but not rock")
	game.simulate(game.PLAYER_FALL_INTERVAL)
	check(game.player.y == 7 and game.stone(Vector2i(3, 11)) == 9, "two player intervals move rock exactly one cell")
	fixture(game)
	game.gravity_enabled = false
	game.rows[6][8] = 9
	game.begin_attack()
	check(game.fatigue == 1 and game.cuts == 1, "starting a real slash adds exactly one fatigue")
	game.begin_attack()
	check(game.fatigue == 1, "repeat input during slash cannot add fatigue")
	game.simulate(0.35)
	check(game.fatigue == 1 and game.cuts == 1, "hit resolution does not count fatigue or cut twice")
	fixture(game)
	game.begin_attack()
	check(game.fatigue == 0, "invalid empty-target slash costs no fatigue")
	fixture(game)
	game.rows[6][8] = 9
	game.fatigue = 998
	game.begin_attack()
	var ended_position: Vector2i = game.player
	game.simulate(1)
	key(game, KEY_RIGHT)
	check(game.fatigue == 999 and game.state == "lost" and game.player == ended_position and not game.hit_pending, "999 fatigue ends game immediately and freezes further movement")
	fixture(game)
	game.crystals.clear()
	game.crystals[Vector2i(8, 6)] = true
	game.fatigue = 80
	game.step_down()
	check(game.fatigue == 30 and game.crystals.is_empty(), "falling onto crystal consumes it and removes fifty fatigue")
	game.collect_crystal()
	check(game.fatigue == 30, "consumed crystal cannot heal twice")
	fixture(game)
	game.crystals.clear()
	game.crystals[Vector2i(9, 5)] = true
	game.fatigue = 20
	key(game, KEY_RIGHT)
	check(game.fatigue == 0 and game.crystals.is_empty(), "horizontal pickup clamps fatigue at zero")
	fixture(game)
	game.player = Vector2i(8, 10)
	game.rows[11][8] = 6
	game.rows[10][9] = 0
	game.crystals.clear()
	game.crystals[Vector2i(9, 9)] = true
	game.fatigue = 70
	key(game, KEY_RIGHT)
	check(game.fatigue == 20 and game.crystals.is_empty(), "climbing onto crystal also consumes recovery")
	game.reset(42)
	var crystal_counts_ok := true
	for stage in range(1, 201):
		game.ensure_crystals(stage)
		if game.crystals.size() < 1 or game.crystals.size() > 2: crystal_counts_ok = false
		for cell in game.crystals:
			if cell.y <= (stage - 1) * 100 + 5 or cell.y >= stage * 100: crystal_counts_ok = false
	check(crystal_counts_ok, "each of 200 layers generates one or two unique crystals inside its own rocky section")
	game.new_game(0)
	game.fatigue = 123
	game.crystals.clear()
	game.crystals[Vector2i(8, 20)] = true
	game.gravity_time = 0.15
	game.save_game()
	game.reset(10)
	game.load_game(0)
	check(game.fatigue == 123 and game.crystals.has(Vector2i(8, 20)) and is_equal_approx(game.gravity_time, 0.15), "save restores fatigue, remaining crystals and slowed gravity timer")
	game.crystals.clear()
	game.save_game()
	game.load_game(0)
	game.ensure_crystals(1)
	check(game.crystals.is_empty(), "loading a depleted layer never respawns consumed crystals")
	var legacy: Dictionary = game.read_slot(0)
	for field in ["fatigue", "crystals", "crystal_level", "gravity_time"]: legacy.erase(field)
	var legacy_file := FileAccess.open(game.slot_path(0), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	check(game.load_game(0) and game.fatigue == 0 and game.crystals.size() >= 1, "older saves migrate with zero fatigue and current-layer crystals")
	game.state = "cleared"
	game.fatigue = 50
	game.begin_attack()
	check(game.level == 2 and game.fatigue == 51 and game.crystal_level == 2 and game.crystals.size() >= 1, "transition slash costs fatigue and generates next-layer supplies")
	game.fatigue = 999
	game.state = "lost"
	game.save_game()
	game.load_game(0)
	check(game.fatigue == 999 and game.state == "lost", "reloading terminal fatigue cannot revive ended game")
	game.delete_game(0)
	game.active_slot = -1
	fixture(game)
	game.crystals.clear()
	game.crystals[Vector2i(3, 10)] = true
	check(game.settle_crystals() and game.crystals.has(Vector2i(3, 11)), "unsupported crystal drops one cell")
	game.rows[12][3] = 6
	check(not game.settle_crystals() and game.crystals.has(Vector2i(3, 11)), "supported crystal stops above stone")
	game.rows[12][3] = -1
	game.settle_crystals()
	check(game.crystals.has(Vector2i(3, 12)), "crystal resumes falling after support is removed")
	game.crystals.clear()
	game.crystals[Vector2i(8, 4)] = true
	game.fatigue = 80
	game.settle_crystals()
	check(game.crystals.is_empty() and game.fatigue == 30, "falling crystal touching player is consumed automatically")
	game.crystals[Vector2i(3, 100)] = true
	game.settle_crystals()
	check(game.crystals.has(Vector2i(3, 100)), "crystals cannot fall into another layer")
	fixture(game)
	for y in range(10, 13):
		for x in range(2, 5): game.rows[y][x] = 0
	game.rows[11][3] = 14
	game.rows[11][6] = 9
	var ring: Array[Vector2i] = game.cluster(Vector2i(2, 10))
	game.break_cells(ring, false)
	check(game.stone(Vector2i(3, 11)) == -1 and game.broken == 9, "closed same-color ring simultaneously explodes enclosed strength-nine black stone")
	check(game.stone(Vector2i(6, 11)) == 9, "external black stone is not damaged by enclosed explosion")
	fixture(game)
	for y in range(10, 13):
		for x in range(2, 5): game.rows[y][x] = 0
	game.rows[11][3] = 14
	game.rows[10][3] = -1
	game.break_cells(game.cluster(Vector2i(2, 10)), false)
	check(game.stone(Vector2i(3, 11)) == 14, "open ring does not count as enclosing black stone")
	fixture(game)
	game.gravity_enabled = false
	game.player = Vector2i(8, 10)
	game.rows[11][8] = 6
	game.rows[9][8] = 0
	key(game, KEY_UP)
	key(game, KEY_SPACE)
	check(game.facing == Vector2i.UP and game.attack_target == Vector2i(8, 9), "up arrow and Space target exactly one overhead cell")
	game.simulate(0.35)
	check(game.stone(Vector2i(8, 9)) == -1 and game.fatigue == 1, "overhead slash breaks target and adds one fatigue")
	game.rows[9][8] = 6
	game.camera_row = 5
	click(game, game.screen_pos(Vector2(8, 9)) + Vector2.ONE * 20)
	check(game.hit_pending and game.attack_direction == Vector2i.UP, "mouse click supports facing overhead target")
	fixture(game)
	game.player = Vector2i(8, 12)
	for y in range(13, 101): game.rows[y][8] = 6
	game.rows[10][8] = 0
	game.settle_rocks()
	check(game.state == "resisting" and game.resistance_left == 2.0 and game.stone(Vector2i(8, 11)) == 0, "falling rock with player as sole support starts full two-second resistance")
	key(game, KEY_RIGHT)
	key(game, KEY_SPACE)
	game.simulate(1.9)
	check(game.player == Vector2i(8, 12) and game.stone(Vector2i(8, 11)) == 0 and game.fatigue == 0, "resistance locks movement and attacks and does not break rock early")
	game.simulate(0.11)
	check(game.state == "playing" and game.stone(Vector2i(8, 11)) == -1 and game.fatigue == 20 and game.burst_time > 0 and not game.shards.is_empty(), "two seconds complete with rock burst and exactly twenty fatigue")
	game.simulate(0.1)
	check(game.fatigue == 20, "completed resistance cannot apply fatigue twice")
	fixture(game)
	game.player = Vector2i(8, 12)
	game.rows[10][8] = 0
	game.rows[10][9] = 0
	for y in range(12, 101): game.rows[y][9] = 6
	game.settle_rocks()
	check(game.state == "playing" and game.resistance_left == 0 and game.stone(Vector2i(8, 11)) == 0, "other bottom support prevents player-pressure event")
	fixture(game)
	game.player = Vector2i(8, 12)
	game.rows[11][8] = 9
	game.settle_rocks()
	check(game.state == "playing", "static rock above head does not count as a falling impact")
	fixture(game)
	game.player = Vector2i(8, 12)
	for y in range(13, 101): game.rows[y][8] = 6
	game.rows[10][8] = 14
	game.rows[9][8] = 9
	game.settle_rocks()
	check(game.state == "resisting" and game.pressure_cells.size() == 2, "complete stacked black-rock descent is captured before resistance starts")
	game.simulate(2.01)
	check(game.stone(Vector2i(8, 11)) == -1 and game.stone(Vector2i(8, 10)) == -1 and game.fatigue == 20, "all rocks in overhead stack burst together with one fatigue penalty")
	fixture(game)
	game.player = Vector2i(8, 12)
	for y in range(13, 101): game.rows[y][8] = 6
	game.rows[10][8] = 14
	game.fatigue = 990
	game.settle_rocks()
	key(game, KEY_ESCAPE)
	game.simulate(1)
	check(game.state == "paused" and game.resistance_left == 2, "pause freezes pressure countdown")
	key(game, KEY_ESCAPE)
	game.simulate(2.01)
	check(game.state == "lost" and game.fatigue == 999 and game.stone(Vector2i(8, 11)) == -1, "pressure burst destroys black rock and can end game at fatigue limit")
	game.new_game(0)
	game.player = Vector2i(8, 12)
	game.warning_delay_enabled = false
	for y in range(1, 106): game.rows[y].fill(-1)
	for y in range(13, 101): game.rows[y][8] = 6
	game.rows[10][8] = 0
	game.settle_rocks()
	game.simulate(0.7)
	game.save_game()
	game.open_menu()
	game.load_game(0)
	check(game.state == "resisting" and is_equal_approx(game.resistance_left, 1.3) and game.pressure_cells.has(Vector2i(8, 11)), "save resumes remaining resistance time and overhead rock group")
	game.simulate(1.31)
	check(game.fatigue == 20 and game.state == "playing", "restored pressure event completes exactly once")
	game.delete_game(0)
	game.active_slot = -1
	fixture(game)
	game.rows[6][8] = 6
	game.rows[5][9] = 9
	game.facing = Vector2i.DOWN
	click(game, game.screen_pos(Vector2(9, 5)) + Vector2.ONE * 20)
	check(game.hit_pending and game.facing == Vector2i.RIGHT and game.attack_target == Vector2i(9, 5), "mouse independently turns and attacks adjacent side stone")
	fixture(game)
	game.rows[6][8] = 6
	game.rows[6][9] = 6
	game.rows[6][10] = 6
	click(game, game.screen_pos(Vector2(10, 5)) + Vector2.ONE * 20)
	check(game.player.x == 9 and game.mouse_target.x == 10 and game.fatigue == 0, "click empty ground begins horizontal movement without fatigue")
	game.simulate(0.15)
	game.mouse_step()
	check(game.player.x == 10, "mouse movement continues toward selected destination")
	key(game, KEY_LEFT)
	check(game.mouse_target.x == -1, "keyboard movement cancels queued mouse movement")
	fixture(game)
	game.rows[6][8] = 6
	game.rows[5][9] = 0
	click(game, game.screen_pos(Vector2(9, 4)) + Vector2.ONE * 20)
	check(game.player == Vector2i(9, 4), "clicking clear tile above a one-high obstacle climbs it")
	game.state = "cleared"
	click(game, Vector2(200, 300))
	check(game.level == 2 and game.state == "playing", "mouse can deliberately enter next layer from cleared screen")
	fixture(game)
	game.warning_delay_enabled = true
	game.gravity_enabled = false
	game.rows[10][3] = 9
	game.settle_rocks()
	check(game.stone(Vector2i(3, 10)) == 9 and game.unstable.get(Vector2i(3, 10), 0) == 1.0, "unsupported black rock starts one-second warning in original cell")
	game.simulate(0.99)
	game.settle_rocks()
	check(game.stone(Vector2i(3, 10)) == 9 and game.warning_offset(Vector2i(3, 10)) != Vector2.ZERO, "rock remains in place and visibly wobbles before full second")
	key(game, KEY_ESCAPE)
	var remaining: float = game.unstable[Vector2i(3, 10)]
	game.simulate(3)
	check(is_equal_approx(game.unstable[Vector2i(3, 10)], remaining), "pause freezes unstable-rock warning timer")
	key(game, KEY_ESCAPE)
	game.simulate(0.02)
	game.settle_rocks()
	check(game.stone(Vector2i(3, 11)) == 9 and game.warning_offset(Vector2i(3, 11)) == Vector2.ZERO, "one full second releases rock and stops warning wobble")
	game.settle_rocks()
	check(game.stone(Vector2i(3, 12)) == 9, "continuous fall does not restart one-second delay at every cell")
	fixture(game)
	game.warning_delay_enabled = true
	game.rows[10][3] = 0
	game.rows[10][4] = 0
	game.settle_rocks()
	check(game.unstable.has(Vector2i(3, 10)) and game.unstable.has(Vector2i(4, 10)), "whole unsupported color component warns together")
	game.rows[11][3] = 6
	game.rows[12][3] = 6
	game.rows[13][3] = 6
	for y in range(14, 101): game.rows[y][3] = 6
	game.settle_rocks()
	check(not game.unstable.has(Vector2i(3, 10)) and not game.unstable.has(Vector2i(4, 10)), "restored support cancels warning for entire component")
	check(not source.contains("抵抗落石 %.1f") and not source.contains("落石压顶！") and not source.contains("顶开落石！"), "pressure effect contains no countdown or event-description text")
	game.new_game(0)
	for y in range(1, 106): game.rows[y].fill(-1)
	game.rows[10][3] = 9
	game.gravity_enabled = false
	game.settle_rocks()
	game.simulate(0.4)
	game.save_game()
	game.load_game(0)
	check(is_equal_approx(game.unstable.get(Vector2i(3, 10), 0), 0.6) and game.mouse_target.x == -1, "save restores remaining warning and never resumes stale mouse movement")
	game.gravity_enabled = false
	game.simulate(0.61)
	game.settle_rocks()
	check(game.stone(Vector2i(3, 11)) == 9, "restored warning expires normally before rock falls")
	game.delete_game(0)
	game.free()
	print("VERIFICATION PASS: %d checks" % passes if failures == 0 else "VERIFICATION FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
