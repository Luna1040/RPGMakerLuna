extends Node2D
const WIDTH := 17
const TILE := 40.0
const ORIGIN := Vector2(44, 138)
const VIEW_ROWS := 15
const COLORS := [Color("e9ad63"), Color("6ad1c3"), Color("ba8de3"), Color("ef7e8f"), Color("7aaee9"), Color("bdcb6c")]
const NAMES := ["琥珀", "碧玉", "紫晶", "珊瑚", "蓝晶", "橄榄"]
const GOAL := 100
const CUT_LIMIT := 150
const LAYER_HEIGHT := 100
const AIR_HEIGHT := 5
const BLACK_BASE := 6
const PLAYER_FALL_INTERVAL := 0.105
const ROCK_FALL_INTERVAL := PLAYER_FALL_INTERVAL * 2.0
const FATIGUE_MAX := 999
var fatigue := 0
var crystals: Dictionary = {}
var crystal_level := 0
var crystal_offsets: Dictionary = {}
var falling_rocks: Dictionary = {}
var resistance_left := 0.0
var pressure_cells: Array[Vector2i] = []
var resume_state := "playing"
var burst_time := 0.0
var unstable: Dictionary = {}
var warning_delay_enabled := true
var mouse_target := Vector2i(-1, -1)
var rows: Dictionary = {}
var generated_to := 0
var retained_from := 0
var player := Vector2i(8, 0)
var visual_player := Vector2(8, 0)
var camera_row := 0.0
var seed_value := 0
var rng := RandomNumberGenerator.new()
var state := "briefing"
var challenge := false
var depth := 0
var cuts := 0
var broken := 0
var score := 0
var best_chain := 0
var last_chain := 0
var elapsed := 0.0
var attack_time := 0.0
var hit_pending := false
var attack_target := Vector2i.ZERO
var attack_direction := Vector2i.DOWN
var facing := Vector2i.DOWN
var fall_time := 0.0
var move_time := 0.0
var shards: Array[Dictionary] = []
var shake := 0.0
var toast := "每一刀，都通向更深的世界。"
var toast_time := 3.0
var milestone := 0
var level := 1
var level_start_cuts := 0
var gravity_time := 0.0
var gravity_dirty := true
var gravity_enabled := true
var collision_broken := 0
var rock_offsets: Dictionary = {}
const SAVE_LIMIT := 6
var save_dir := "user://expedition-saves"
var active_slot := -1
var started_at := ""
var last_played := ""
var menu_message := "选择新游戏或继续存档；共6个槽位，不翻页。"
var deleting_slot := -1
var font: Font = preload("res://font.ttf")

func _ready() -> void:
	reset()
	state = "menu"

func reset(fixed_seed: int = -1) -> void:
	seed_value = fixed_seed if fixed_seed >= 0 else int(Time.get_ticks_usec())
	rng.seed = seed_value
	rows.clear()
	generated_to = 0
	retained_from = 0
	player = Vector2i(8, 0)
	visual_player = Vector2(player)
	camera_row = 0
	depth = 0
	cuts = 0
	fatigue = 0
	crystals.clear()
	crystal_level = 0
	crystal_offsets.clear()
	falling_rocks.clear()
	resistance_left = 0
	pressure_cells.clear()
	resume_state = "playing"
	burst_time = 0
	unstable.clear()
	warning_delay_enabled = true
	mouse_target = Vector2i(-1, -1)
	broken = 0
	score = 0
	best_chain = 0
	last_chain = 0
	elapsed = 0
	attack_time = 0
	hit_pending = false
	facing = Vector2i.DOWN
	attack_direction = Vector2i.DOWN
	fall_time = 0
	move_time = 0
	shards.clear()
	shake = 0
	milestone = 0
	level = 1
	level_start_cuts = 0
	gravity_time = 0
	gravity_dirty = true
	gravity_enabled = true
	collision_broken = 0
	rock_offsets.clear()
	toast = "每一刀，都通向更深的世界。"
	toast_time = 3
	state = "briefing"
	rows[0] = PackedInt32Array()
	rows[0].resize(WIDTH)
	rows[0].fill(-1)
	ensure_rows(105)
	ensure_crystals(1)
	queue_redraw()

func ensure_rows(until_row: int) -> void:
	while generated_to < until_row:
		generated_to += 1
		var row := PackedInt32Array()
		row.resize(WIDTH)
		# Alternating palettes at 12-row seams bound connected components.
		var band := int((generated_to - 1) / 12) % 2
		for x in range(WIDTH):
			var patch_x := int(x / 3)
			var patch_y := int((generated_to - 1) / 3)
			var color_id := posmod(patch_x * 7 + patch_y * 11 + seed_value % 97, 3)
			if rng.randf() < 0.20: color_id = rng.randi_range(0, 2)
			if (generated_to - 1) % LAYER_HEIGHT < AIR_HEIGHT:
				row[x] = -1
			elif rng.randf() < 0.075:
				row[x] = BLACK_BASE + rng.randi_range(0, 8)
			else:
				row[x] = color_id + band * 3
		rows[generated_to] = row

func stone(cell: Vector2i) -> int:
	if cell.x < 0 or cell.x >= WIDTH or cell.y < retained_from: return -2
	if not rows.has(cell.y): return -2
	return rows[cell.y][cell.x]

func ensure_crystals(for_level: int) -> void:
	if crystal_level == for_level: return
	crystals.clear()
	crystal_level = for_level
	crystal_offsets.clear()
	var item_rng := RandomNumberGenerator.new()
	item_rng.seed = seed_value + for_level * 7919
	var count := item_rng.randi_range(1, 2)
	while crystals.size() < count:
		var cell := Vector2i(item_rng.randi_range(0, WIDTH - 1), (for_level - 1) * LAYER_HEIGHT + item_rng.randi_range(10, 94))
		crystals[cell] = true

func collect_crystal() -> void:
	if not crystals.has(player): return
	crystals.erase(player)
	crystal_offsets.erase(player)
	var previous := fatigue
	fatigue = maxi(0, fatigue - 50)
	toast = "水晶已吸收 · 疲劳降低 %d" % (previous - fatigue)
	toast_time = 3

func register_cut() -> bool:
	cuts += 1
	fatigue = mini(FATIGUE_MAX, fatigue + 1)
	if fatigue >= FATIGUE_MAX:
		state = "lost"
		hit_pending = false
		attack_time = 0
		save_game()
		return false
	return true

func settle_crystals() -> bool:
	collect_crystal()
	var changed := false
	var ordered := crystals.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	for cell in ordered:
		if not crystals.has(cell) or stone(cell) != -1 or cell.y >= level * LAYER_HEIGHT: continue
		var below: Vector2i = cell + Vector2i.DOWN
		if stone(below) != -1 or crystals.has(below): continue
		crystals.erase(cell)
		crystal_offsets.erase(cell)
		crystals[below] = true
		crystal_offsets[below] = -TILE
		changed = true
		if below == player: collect_crystal()
	return changed

func with_enclosed_black(group: Array[Vector2i]) -> Array[Vector2i]:
	if group.is_empty(): return group
	var wall: Dictionary = {}
	var low := group[0]
	var high := group[0]
	var has_color := false
	for cell in group:
		wall[cell] = true
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
		if stone(cell) >= 0 and stone(cell) < BLACK_BASE: has_color = true
	if not has_color: return group
	low -= Vector2i.ONE
	high += Vector2i.ONE
	var pending: Array[Vector2i] = [low]
	var outside := {low: true}
	var index := 0
	while index < pending.size():
		var cell := pending[index]
		index += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if next.x < low.x or next.x > high.x or next.y < low.y or next.y > high.y or wall.has(next) or outside.has(next): continue
			outside[next] = true
			pending.append(next)
	var result := group.duplicate()
	for y in range(low.y + 1, high.y):
		for x in range(low.x + 1, high.x):
			var cell := Vector2i(x, y)
			if stone(cell) >= BLACK_BASE and not outside.has(cell) and not wall.has(cell): result.append(cell)
	return result

func begin_pressure() -> bool:
	var head := player + Vector2i.UP
	if stone(head) < 0 or state != "playing": return false
	var pending: Array[Vector2i] = [head]
	var members := {head: true}
	var index := 0
	while index < pending.size():
		var cell := pending[index]
		index += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if next.y >= player.y or next.y < (level - 1) * LAYER_HEIGHT or members.has(next) or stone(next) < 0: continue
			members[next] = true
			pending.append(next)
	for cell in pending:
		var below := cell + Vector2i.DOWN
		if not members.has(below) and below != player and stone(below) != -1: return false
	pressure_cells = pending
	resistance_left = 2.0
	state = "resisting"
	attack_time = 0
	hit_pending = false
	visual_player = Vector2(player)
	for cell in pending: rock_offsets.erase(cell)
	toast_time = 0
	mouse_target = Vector2i(-1, -1)
	return true

func cluster(start: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var color_id := stone(start)
	if color_id < 0: return result
	if color_id >= BLACK_BASE:
		result.append(start)
		return result
	var pending: Array[Vector2i] = [start]
	var seen := {start: true}
	var index := 0
	while index < pending.size():
		var cell := pending[index]
		index += 1
		result.append(cell)
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if not seen.has(next) and stone(next) == color_id:
				seen[next] = true
				pending.append(next)
	return result

func begin_attack() -> void:
	if state == "cleared":
		if not register_cut(): return
		level += 1
		unstable.clear()
		falling_rocks.clear()
		rock_offsets.clear()
		mouse_target = Vector2i(-1, -1)
		level_start_cuts = cuts
		state = "playing"
		camera_row = (level - 1) * LAYER_HEIGHT
		visual_player = Vector2(player)
		shards.clear()
		attack_time = 0.34
		hit_pending = false
		facing = Vector2i.DOWN
		attack_direction = facing
		ensure_rows(level * LAYER_HEIGHT + AIR_HEIGHT)
		ensure_crystals(level)
		gravity_dirty = true
		toast = "进入第 %d 层 · 先下落 5 米，再穿过 95 排岩石" % level
		toast_time = 4
		return
	if state != "playing" or attack_time > 0 or stone(player + Vector2i.DOWN) == -1: return
	var target := player + facing
	if stone(target) < 0:
		toast = "面前没有石块。用方向键转向或移动。"
		toast_time = 2
		return
	if not register_cut(): return
	attack_target = target
	attack_direction = facing
	attack_time = 0.34
	hit_pending = true

func resolve_hit() -> void:
	var id := stone(attack_target)
	if id >= BLACK_BASE:
		last_chain = 0
		if id > BLACK_BASE:
			rows[attack_target.y][attack_target.x] = id - 1
			toast = "障碍石剩余 %d 刀 · 邻近障碍石不受影响" % (id - BLACK_BASE)
			shake = 1.5
		else:
			break_cells([attack_target], false)
			toast = "障碍石已破碎 · 只破坏这一块"
		toast_time = 2.5
		return
	var group := cluster(attack_target)
	if group.is_empty(): return
	var color_id := stone(attack_target)
	break_cells(group, false)
	toast = "%s连锁 × %d  ·  +%d 分" % [NAMES[color_id], last_chain, last_chain * 10 + maxi(0, last_chain - 1) * 5]
	toast_time = 2.4

func break_cells(group: Array[Vector2i], from_collision: bool) -> void:
	group = with_enclosed_black(group)
	for cell in group:
		var id := stone(cell)
		if id < 0: continue
		var tint: Color = COLORS[id] if id < BLACK_BASE else Color("555555")
		rows[cell.y][cell.x] = -1
		rock_offsets.erase(cell)
		unstable.erase(cell)
		if shards.size() < 160:
			shards.append({"pos": Vector2(cell) * TILE + Vector2.ONE * TILE / 2, "velocity": Vector2(rng.randf_range(-80, 80), rng.randf_range(-120, 10)), "life": 0.6, "color": tint})
	broken += group.size()
	if from_collision: collision_broken += group.size()
	last_chain = group.size()
	best_chain = maxi(best_chain, last_chain)
	var gained := last_chain * 10 + maxi(0, last_chain - 1) * 5
	score += gained
	shake = minf(5, 1 + last_chain * 0.12)
	gravity_dirty = true

func settle_rocks() -> bool:
	# Black stones fall individually and retain their remaining hit count.
	# Layer bottom is a structural boundary, so the next 5m gap stays empty.
	var bottom := level * LAYER_HEIGHT
	var top := (level - 1) * LAYER_HEIGHT + AIR_HEIGHT + 1
	var visited: Dictionary = {}
	var groups: Array = []
	for y in range(bottom, top - 1, -1):
		for x in range(WIDTH):
			var cell := Vector2i(x, y)
			var id := stone(cell)
			if id < 0 or visited.has(cell): continue
			var group := cluster(cell)
			for member in group: visited[member] = true
			groups.append(group)
	var changed := false
	var previous_falling := falling_rocks.duplicate()
	falling_rocks.clear()
	var pressure_candidate := false
	var moved_this_tick: Dictionary = {}
	for original in groups:
		var first: Vector2i = original[0]
		var id := stone(first)
		if id < 0: continue
		# A previous impact may have removed or merged this component.
		var group := cluster(first)
		var already_moved := false
		for cell in group:
			if moved_this_tick.has(cell): already_moved = true
		if already_moved: continue
		var members: Dictionary = {}
		for cell in group: members[cell] = true
		var supported := false
		for cell in group:
			var below: Vector2i = cell + Vector2i.DOWN
			if members.has(below): continue
			if cell.y >= bottom or below == player or stone(below) != -1:
				supported = true
				break
		if supported:
			for cell in group: unstable.erase(cell)
			var was_falling := false
			for cell in group:
				if previous_falling.has(cell): was_falling = true
			if was_falling and group.has(player + Vector2i.UP): pressure_candidate = true
			continue
		var ready := true
		for cell in group:
			if not unstable.has(cell): unstable[cell] = 1.0
			if float(unstable[cell]) > 0: ready = false
		if warning_delay_enabled and not ready:
			changed = true
			continue
		for cell in group:
			rows[cell.y][cell.x] = -1
			rock_offsets.erase(cell)
			unstable.erase(cell)
		var moved: Dictionary = {}
		for cell in group:
			var next: Vector2i = cell + Vector2i.DOWN
			rows[next.y][next.x] = id
			rock_offsets[next] = -TILE
			moved[next] = true
			moved_this_tick[next] = true
			falling_rocks[next] = true
			unstable[next] = 0.0
		changed = true
		var impact := false
		for cell in moved:
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + direction
				if not moved.has(neighbor) and stone(neighbor) == id:
					impact = true
					break
			if impact: break
		if impact and id < BLACK_BASE:
			var impact_group := cluster(first + Vector2i.DOWN)
			break_cells(impact_group, true)
			toast = "同色落石碰撞！连锁破碎 ×%d" % impact_group.size()
			toast_time = 3
		elif moved.has(player + Vector2i.UP): pressure_candidate = true
	if pressure_candidate and begin_pressure(): return true
	return changed

func step_down() -> bool:
	if state != "playing": return false
	ensure_rows(maxi(player.y + 64, level * LAYER_HEIGHT + AIR_HEIGHT))
	if stone(player + Vector2i.DOWN) != -1: return false
	player.y += 1
	collect_crystal()
	gravity_dirty = true
	depth = maxi(depth, player.y)
	if int(depth / 100) > milestone:
		milestone = int(depth / 100)
		toast = "抵达 %d 米！地心没有尽头，继续向下探索。" % (milestone * 100)
		toast_time = 4
	var keep_from := maxi(0, (level - 1) * LAYER_HEIGHT - AIR_HEIGHT)
	while retained_from < keep_from:
		rows.erase(retained_from)
		retained_from += 1
	if player.y >= level * LAYER_HEIGHT:
		state = "cleared"
		toast = "第 %d 层通关！再按一次空格挥刀，进入下一层。" % level
		toast_time = 5
		save_game()
	return true

func move_horizontal(direction: int) -> void:
	if state != "playing" or attack_time > 0: return
	facing = Vector2i(direction, 0)
	move_time = 0.13
	var next := player + Vector2i(direction, 0)
	if stone(next) == -1:
		player = next
		gravity_dirty = true
	elif stone(next) >= 0:
		var above := player + Vector2i.UP
		var landing := next + Vector2i.UP
		if stone(player + Vector2i.DOWN) >= 0 and landing.y >= (level - 1) * LAYER_HEIGHT and stone(above) == -1 and stone(landing) == -1:
			player = landing
			fall_time = 0
			gravity_dirty = true
	collect_crystal()

func face_front() -> void:
	if state == "playing" and attack_time <= 0:
		facing = Vector2i.DOWN

func face_up() -> void:
	if state == "playing" and attack_time <= 0: facing = Vector2i.UP

func click_stone(position_in_game: Vector2) -> void:
	if state != "playing" or attack_time > 0: return
	if not Rect2(ORIGIN, Vector2(WIDTH * TILE, VIEW_ROWS * TILE)).has_point(position_in_game): return
	var local := (position_in_game - ORIGIN) / TILE + Vector2(0, camera_row)
	var clicked := Vector2i(floori(local.x), floori(local.y))
	if (clicked - player).abs().x + (clicked - player).abs().y == 1 and stone(clicked) >= 0:
		facing = clicked - player
		begin_attack()
		mouse_target = Vector2i(-1, -1)
	elif clicked.x != player.x:
		mouse_target = clicked
		mouse_step()

func mouse_step() -> void:
	if mouse_target.x < 0 or state != "playing" or attack_time > 0 or move_time > 0: return
	var difference := mouse_target - player
	if absi(difference.x) + absi(difference.y) == 1 and stone(mouse_target) >= 0:
		facing = difference
		begin_attack()
		mouse_target = Vector2i(-1, -1)
		return
	if difference.x == 0:
		mouse_target = Vector2i(-1, -1)
		return
	var before := player
	move_horizontal(signi(difference.x))
	if player == before: mouse_target = Vector2i(-1, -1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state == "menu":
			menu_click(event.position)
		elif Rect2(790, 704, 180, 30).has_point(event.position): save_game()
		elif Rect2(990, 704, 210, 30).has_point(event.position): open_menu()
		elif state == "briefing": state = "playing"
		elif state == "playing": click_stone(event.position)
		elif state == "cleared" and Rect2(ORIGIN, Vector2(WIDTH * TILE, VIEW_ROWS * TILE)).has_point(event.position): begin_attack()
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE]: mouse_target = Vector2i(-1, -1)
	if state == "menu":
		if event.keycode == KEY_ESCAPE and active_slot >= 0: load_game(active_slot)
		return
	match event.keycode:
		KEY_S: save_game()
		KEY_M, KEY_R: open_menu()
		KEY_C:
			if state == "briefing": challenge = not challenge
		KEY_ENTER:
			if state == "briefing": state = "playing"
			elif state == "won":
				challenge = false
				state = "playing"
		KEY_ESCAPE:
			if state == "playing" or state == "resisting":
				resume_state = state
				state = "paused"
			elif state == "paused": state = resume_state
		KEY_SPACE: begin_attack()
		KEY_UP: face_up()
		KEY_DOWN: face_front()
		KEY_LEFT: move_horizontal(-1)
		KEY_RIGHT: move_horizontal(1)

func simulate(delta: float) -> void:
	if state == "resisting":
		elapsed += delta
		resistance_left = maxf(0, resistance_left - delta)
		if resistance_left <= 0:
			break_cells(pressure_cells, false)
			pressure_cells.clear()
			fatigue = mini(FATIGUE_MAX, fatigue + 20)
			burst_time = 0.7
			state = "lost" if fatigue >= FATIGUE_MAX else "playing"
			gravity_dirty = true
			save_game()
			toast_time = 0
		return
	if state != "playing": return
	for cell in unstable.keys(): unstable[cell] = maxf(0, float(unstable[cell]) - delta)
	burst_time = maxf(0, burst_time - delta)
	elapsed += delta
	toast_time = maxf(0, toast_time - delta)
	move_time = maxf(0, move_time - delta)
	shake = move_toward(shake, 0, delta * 16)
	if attack_time > 0:
		attack_time = maxf(0, attack_time - delta)
		if hit_pending and attack_time <= 0.20:
			hit_pending = false
			resolve_hit()
	fall_time += delta
	if fall_time >= PLAYER_FALL_INTERVAL:
		fall_time = fmod(fall_time, PLAYER_FALL_INTERVAL)
		step_down()
	gravity_time += delta
	if gravity_enabled and (gravity_dirty or not crystals.is_empty()) and gravity_time >= ROCK_FALL_INTERVAL and not hit_pending and state == "playing":
		gravity_time = fmod(gravity_time, ROCK_FALL_INTERVAL)
		gravity_dirty = settle_rocks()
		if state == "playing": settle_crystals()
	# Last cut may win after a long fall; only judge failure when landed.
	if challenge and cuts - level_start_cuts >= CUT_LIMIT and state == "playing" and not hit_pending and attack_time == 0 and stone(player + Vector2i.DOWN) >= 0:
		state = "lost"
	visual_player = visual_player.lerp(Vector2(player), minf(1, delta * 18))
	camera_row = lerpf(camera_row, clampf(visual_player.y - 4, (level - 1) * LAYER_HEIGHT, level * LAYER_HEIGHT - VIEW_ROWS + 1), minf(1, delta * 8))
	for cell in rock_offsets.keys():
		rock_offsets[cell] = move_toward(rock_offsets[cell], 0, delta * TILE / ROCK_FALL_INTERVAL)
		if rock_offsets[cell] == 0: rock_offsets.erase(cell)
	for cell in crystal_offsets.keys():
		crystal_offsets[cell] = move_toward(crystal_offsets[cell], 0, delta * TILE / ROCK_FALL_INTERVAL)
		if crystal_offsets[cell] == 0: crystal_offsets.erase(cell)
	for i in range(shards.size() - 1, -1, -1):
		shards[i].life -= delta
		shards[i].velocity.y += delta * 280
		shards[i].pos += shards[i].velocity * delta
		if shards[i].life <= 0: shards.remove_at(i)

func _process(delta: float) -> void:
	if state == "playing":
		if move_time <= 0:
			if Input.is_physical_key_pressed(KEY_LEFT): move_horizontal(-1)
			elif Input.is_physical_key_pressed(KEY_RIGHT): move_horizontal(1)
			else: mouse_step()
		if Input.is_physical_key_pressed(KEY_UP): face_up()
		elif Input.is_physical_key_pressed(KEY_DOWN): face_front()
		if Input.is_physical_key_pressed(KEY_SPACE): begin_attack()
		simulate(minf(delta, 0.05))
	elif state == "resisting": simulate(minf(delta, 0.05))
	queue_redraw()

func text_at(text: String, at: Vector2, size: int = 20, color: Color = Color("e0e9ef")) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func screen_pos(cell: Vector2) -> Vector2:
	return ORIGIN + (cell - Vector2(0, camera_row)) * TILE

func draw_explorer(at: Vector2) -> void:
	# Temporary character, awaiting reviewed generated assets.
	var shown_direction := attack_direction if attack_time > 0 else facing
	draw_set_transform(at + Vector2(0, 6), 0, Vector2(-0.75 if shown_direction == Vector2i.LEFT else 0.75, 0.75))
	var swing := attack_time > 0
	var bend := 5.0 + sin(elapsed * 35) if resistance_left > 0 else (sin((1 - attack_time / 0.34) * PI) * 3 if swing else 0.0)
	var body := Vector2(0, bend)
	draw_line(body + Vector2(-6, 6), body + Vector2(-7, 17), Color("a6b7c3"), 6)
	draw_line(body + Vector2(5, 6), body + Vector2(8, 17), Color("a6b7c3"), 6)
	draw_line(body + Vector2(-11, 17), body + Vector2(-3, 17), Color("e4b56d"), 4)
	draw_line(body + Vector2(4, 17), body + Vector2(12, 17), Color("e4b56d"), 4)
	draw_rect(Rect2(body + Vector2(-9, -10), Vector2(18, 20)), Color("438e9e"))
	draw_circle(body + Vector2(0, -18), 8, Color("f2c797"))
	draw_arc(body + Vector2(0, -19), 9, PI, TAU, 12, Color("eab15f"), 5)
	draw_circle(body + Vector2(0 if shown_direction == Vector2i.DOWN else 6, -23), 3, Color("fff1b3"))
	if shown_direction == Vector2i.DOWN:
		draw_circle(body + Vector2(-3, -18), 1, Color("182a35"))
		draw_circle(body + Vector2(3, -18), 1, Color("182a35"))
	var hand := body + Vector2(10, -4)
	if resistance_left > 0:
		for side in [-1, 1]:
			draw_line(body + Vector2(side * 7, -5), Vector2(side * 12, -27), Color("f2c797"), 5)
			draw_line(Vector2(side * 12, -27), Vector2(side * 5, -34), Color("f2c797"), 5)
	var angle := -0.9
	if swing: angle = lerpf(-2.1, 1.3 if shown_direction == Vector2i.DOWN else 0.0, clampf((0.34 - attack_time) / 0.14, 0, 1))
	if shown_direction == Vector2i.UP: angle = -PI / 2 if not swing else lerpf(-0.4, -2.0, clampf((0.34 - attack_time) / 0.14, 0, 1))
	var tip := hand + Vector2.from_angle(angle) * 29
	draw_line(body + Vector2(5, -6), hand, Color("f2c797"), 5)
	draw_line(hand - Vector2.from_angle(angle) * 4, hand + Vector2.from_angle(angle) * 4, Color("d9ab64"), 5)
	draw_line(hand + Vector2.from_angle(angle) * 5, tip, Color("ecf5fc"), 5)
	if swing and attack_time < 0.22:
		draw_arc(hand, 29, -1.5, 1.5 if shown_direction == Vector2i.DOWN else 0.2, 18, Color(0.8, 0.95, 1, 0.55), 2)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color("0c1420"))
	text_at("CORE / ENDLESS", Vector2(44, 36), 16, Color("6ad1c3"))
	text_at("地心探险", Vector2(44, 86), 38)
	text_at("一刀破岩，同色连锁。向下，永无止境。", Vector2(284, 82), 20, Color("96adbf"))
	draw_rect(Rect2(ORIGIN, Vector2(WIDTH * TILE, VIEW_ROWS * TILE)), Color("111f2a"))
	var begin_row := maxi(maxi(retained_from, (level - 1) * LAYER_HEIGHT), floori(camera_row))
	var target := player + facing
	var highlighted := cluster(target)
	for y in range(begin_row, mini(level * LAYER_HEIGHT + 1, ceili(camera_row) + VIEW_ROWS)):
		for x in range(WIDTH):
			var cell := Vector2i(x, y)
			var id := stone(cell)
			if id < 0: continue
			var p := screen_pos(Vector2(cell)) + Vector2(0, rock_offsets.get(cell, 0.0))
			p += warning_offset(cell)
			if p.y < ORIGIN.y or p.y + TILE > ORIGIN.y + VIEW_ROWS * TILE: continue
			if id >= BLACK_BASE:
				draw_rect(Rect2(p + Vector2(2, 2), Vector2(36, 36)), Color.BLACK)
				text_at(str(id - BLACK_BASE + 1), p + Vector2(13, 28), 24, Color.WHITE)
				if cell == target: draw_rect(Rect2(p + Vector2(2, 2), Vector2(36, 36)), Color("ffe2a0"), false, 3)
				continue
			var tint: Color = COLORS[id]
			draw_rect(Rect2(p + Vector2(2, 2), Vector2(36, 36)), tint.darkened(0.22))
			draw_line(p + Vector2(4, 5), p + Vector2(35, 5), tint.lightened(0.20), 2)
			draw_line(p + Vector2(8, 30), p + Vector2(19, 19), tint.darkened(0.38), 2)
			draw_line(p + Vector2(19, 19), p + Vector2(30, 23), tint.darkened(0.38), 2)
			draw_circle(p + Vector2(11, 11), 2, tint.lightened(0.4))
			if id % 3 == 1: draw_circle(p + Vector2(18, 11), 2, tint.lightened(0.4))
			if id % 3 == 2: draw_line(p + Vector2(8, 12), p + Vector2(19, 12), tint.lightened(0.4), 2)
			if cell in highlighted: draw_rect(Rect2(p + Vector2(2, 2), Vector2(36, 36)), Color(1, 1, 1, 0.45), false, 1)
			if cell == target: draw_rect(Rect2(p + Vector2(2, 2), Vector2(36, 36)), Color("ffe2a0"), false, 3)
	# Temporary collectible marker; generated crystal artwork is currently blocked.
	for cell in crystals:
		var center := screen_pos(Vector2(cell)) + Vector2.ONE * TILE / 2 + Vector2(0, crystal_offsets.get(cell, 0.0))
		if center.y < ORIGIN.y + 16 or center.y > ORIGIN.y + VIEW_ROWS * TILE - 16: continue
		draw_circle(center, 16, Color("173947"))
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -14), center + Vector2(10, 0), center + Vector2(0, 14), center + Vector2(-10, 0)]), Color("70f5ed"))
		draw_line(center + Vector2(0, -10), center + Vector2(-5, 0), Color.WHITE, 2)
	for shard in shards:
		var p: Vector2 = ORIGIN + shard.pos - Vector2(0, camera_row * TILE)
		if p.y < ORIGIN.y + 5 or p.y > ORIGIN.y + VIEW_ROWS * TILE - 5: continue
		var tint: Color = shard.color
		tint.a = shard.life / 0.6
		draw_rect(Rect2(p - Vector2.ONE * 3, Vector2.ONE * 6), tint)
	var at := screen_pos(visual_player) + Vector2.ONE * TILE / 2
	if shake > 0: at.x += sin(elapsed * 100) * shake
	draw_explorer(at)
	if resistance_left > 0:
		for cell in pressure_cells:
			var p := screen_pos(Vector2(cell))
			if p.y >= ORIGIN.y and p.y + TILE <= ORIGIN.y + VIEW_ROWS * TILE:
				draw_rect(Rect2(p + Vector2(3, 3), Vector2(34, 34)), Color(1, 0.45, 0.25, 0.5 + sin(elapsed * 20) * 0.2), false, 3)
		for side in [-1, 1]: draw_line(at + Vector2(side * 23, -38), at + Vector2(side * 16, -20), Color("ffb37e"), 3)
	if burst_time > 0: draw_arc(at, (0.7 - burst_time) * 100 + 20, PI, TAU, 24, Color(1, 0.8, 0.4, burst_time / 0.7), 3)
	draw_rect(Rect2(ORIGIN.x, 110, WIDTH * TILE, 28), Color("0c1420"))
	draw_rect(Rect2(ORIGIN.x, 738, WIDTH * TILE, 62), Color("0c1420"))
	text_at("↓ %d 米" % depth, Vector2(50, 775), 23, Color("e9ad63"))
	text_at(toast if toast_time > 0 else "金框：可砍目标；白框：同色连锁", Vector2(220, 775), 17, Color("b9cddd"))
	draw_rect(Rect2(762, 138, 470, 600), Color("172634"))
	text_at("第 %d 层 · %s" % [level, "限刀挑战" if challenge else "深入地心"], Vector2(790, 179), 25, Color("6ad1c3"))
	text_at("%d" % depth, Vector2(790, 253), 54)
	text_at("米 · 本层 %d / 100米" % (depth - (level - 1) * 100), Vector2(790, 282), 18, Color("96adbf"))
	text_at("得分  %d" % score, Vector2(790, 328), 23)
	text_at("疲劳 %d / 999" % fatigue, Vector2(990, 328), 20, Color("ef7e8f") if fatigue >= 900 else Color("6ad1c3"))
	text_at("连锁  ×%d     最佳  ×%d" % [last_chain, best_chain], Vector2(790, 371), 21, Color("e9ad63"))
	text_at("碎岩 %d · 本层挥刀 %d%s" % [broken, cuts - level_start_cuts, " /150" if challenge else ""], Vector2(790, 408), 19)
	var guide := ["↑ 向上砍；↓ 向下砍；← → 转向", "鼠标点击空地移动、邻近石块砍击", "空格砍击；一格高石块可翻上", "每刀疲劳 +1；达到999结束", "水晶无支撑会落；接触疲劳 -50", "彩石下落遇同色立即一起破碎", "同色石群包围的黑石一起炸碎", "岩石失去支撑：先摇晃1秒再落", "通关后空格或点击矿区进入下一层", "S 存档 · M / R 菜单 · Esc 暂停"]
	for i in range(guide.size()): text_at(guide[i], Vector2(790, 456 + i * 25), 18, Color("a9becd"))
	draw_rect(Rect2(790, 704, 180, 30), Color("285060"))
	text_at("手动存档 [S]", Vector2(805, 726), 18)
	draw_rect(Rect2(990, 704, 210, 30), Color("285060"))
	text_at("存档菜单 [M]", Vector2(1005, 726), 18)
	if state == "menu": draw_save_menu()
	elif state != "playing" and state != "resisting": draw_overlay()

func draw_overlay() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.02, 0.04, 0.08, 0.87))
	draw_rect(Rect2(252, 222, 776, 358), Color("1b303f"))
	var title := "持刀，向地心出发"
	var lines := ["每层100米：先落5米，再砍穿95排岩石。", "方向键转向；空格或点击金框石块砍；黑石须多刀。", "模式：%s  ·  C 切换" % ("挑战：每层最多150刀" if challenge else "逐层探索：无刀数限制"), "按 Enter 或点击开始     R 重来"]
	if state == "paused":
		title = "探索已暂停"
		lines = ["深度 %d 米 · 得分 %d" % [depth, score], "按 Esc 继续探索", "按 R 重新开始"]
	elif state == "cleared":
		title = "第 %d 层通关 · 穿过95排岩石" % level
		lines = ["深度 %d 米 · 本层 %d 刀 · %d 分" % [depth, cuts - level_start_cuts, score], "再按一次空格挥刀，进入第 %d 层" % (level + 1), "下一层先落5米；R 可重新开始"]
	elif state == "lost":
		title = "探索结束 · 疲劳达到999" if fatigue >= FATIGUE_MAX else "挑战结束 · 刀数用尽"
		lines = ["本次深入 %d 米，得分 %d · 疲劳 %d" % [depth, score, fatigue], "寻找水晶可降低50点疲劳，利用同色连锁节省挥刀。", "按 M / R 返回存档菜单，选择空槽开始新游戏"]
	text_at(title, Vector2(290, 290), 33, Color("6ad1c3"))
	for i in range(lines.size()): text_at(lines[i], Vector2(290, 356 + i * 48), 21)

func slot_path(slot: int) -> String:
	return save_dir.path_join("slot_%d.json" % slot)

func read_slot(slot: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)): return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null: return {"invalid": true}
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version", 0) != 1: return {"invalid": true}
	return data

func new_game(slot: int) -> bool:
	if slot < 0 or slot >= SAVE_LIMIT or FileAccess.file_exists(slot_path(slot)): return false
	reset()
	active_slot = slot
	started_at = Time.get_datetime_string_from_system(false, true)
	state = "playing"
	return save_game()

func save_game() -> bool:
	if active_slot < 0 or state == "menu": return false
	last_played = Time.get_datetime_string_from_system(false, true)
	var data := {"version": 1, "started_at": started_at, "last_played": last_played, "rows": {}, "rng_state": str(rng.state), "fatigue": fatigue, "crystals": [], "crystal_level": crystal_level, "gravity_time": gravity_time}
	for cell in crystals: data.crystals.append([cell.x, cell.y])
	data["resistance_left"] = resistance_left
	data["pressure_cells"] = []
	for cell in pressure_cells: data.pressure_cells.append([cell.x, cell.y])
	data["resume_state"] = resume_state
	data["falling_rocks"] = []
	data["unstable"] = []
	for cell in unstable: data.unstable.append([cell.x, cell.y, unstable[cell]])
	for cell in falling_rocks: data.falling_rocks.append([cell.x, cell.y])
	for field in ["seed_value", "generated_to", "retained_from", "state", "challenge", "depth", "cuts", "broken", "score", "best_chain", "last_chain", "elapsed", "level", "level_start_cuts", "milestone", "attack_time", "hit_pending", "fall_time", "gravity_dirty", "collision_broken"]:
		data[field] = get(field)
	for field in ["player", "facing", "attack_target", "attack_direction"]:
		var value: Vector2i = get(field)
		data[field] = [value.x, value.y]
	for y in rows: data.rows[str(y)] = Array(rows[y])
	var error := DirAccess.make_dir_recursive_absolute(save_dir)
	if error != OK:
		toast = "存档失败：无法创建目录（%d）" % error
		toast_time = 5
		return false
	var file := FileAccess.open(slot_path(active_slot) + ".tmp", FileAccess.WRITE)
	if file == null:
		toast = "存档失败：无法写入文件"
		toast_time = 5
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	error = DirAccess.rename_absolute(slot_path(active_slot) + ".tmp", slot_path(active_slot))
	toast = "存档 %d 已保存 · %d 米" % [active_slot + 1, depth] if error == OK else "存档失败：无法替换文件"
	toast_time = 4
	return error == OK

func load_game(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty() or data.has("invalid"):
		menu_message = "存档无法读取，可删除后重新创建。"
		return false
	reset(int(data.seed_value))
	for field in ["generated_to", "retained_from", "state", "challenge", "depth", "cuts", "broken", "score", "best_chain", "last_chain", "elapsed", "level", "level_start_cuts", "milestone", "attack_time", "hit_pending", "fall_time", "gravity_dirty", "collision_broken"]:
		set(field, data[field])
	for field in ["player", "facing", "attack_target", "attack_direction"]:
		set(field, Vector2i(int(data[field][0]), int(data[field][1])))
	rows.clear()
	for y in data.rows: rows[int(y)] = PackedInt32Array(data.rows[y])
	rng.state = int(data.rng_state)
	fatigue = clampi(int(data.get("fatigue", 0)), 0, FATIGUE_MAX)
	gravity_time = float(data.get("gravity_time", 0.0))
	resistance_left = float(data.get("resistance_left", 0.0))
	pressure_cells.clear()
	for cell in data.get("pressure_cells", []): pressure_cells.append(Vector2i(int(cell[0]), int(cell[1])))
	resume_state = data.get("resume_state", "playing")
	falling_rocks.clear()
	unstable.clear()
	for item in data.get("unstable", []): unstable[Vector2i(int(item[0]), int(item[1]))] = float(item[2])
	for cell in data.get("falling_rocks", []): falling_rocks[Vector2i(int(cell[0]), int(cell[1]))] = true
	if not data.has("fatigue") and hit_pending: cuts += 1
	crystals.clear()
	crystal_level = int(data.get("crystal_level", 0))
	if data.has("crystals"):
		for cell in data.crystals: crystals[Vector2i(int(cell[0]), int(cell[1]))] = true
	else:
		ensure_crystals(level)
	active_slot = slot
	started_at = data.started_at
	last_played = data.last_played
	visual_player = Vector2(player)
	camera_row = clampf(player.y - 4, (level - 1) * LAYER_HEIGHT, level * LAYER_HEIGHT - VIEW_ROWS + 1)
	if state == "paused": state = resume_state
	elif state == "briefing": state = "playing"
	if fatigue >= FATIGUE_MAX: state = "lost"
	deleting_slot = -1
	save_game()
	return true

func warning_offset(cell: Vector2i) -> Vector2:
	if not unstable.has(cell) or float(unstable[cell]) <= 0: return Vector2.ZERO
	var intensity := 1.0 + (1.0 - float(unstable[cell])) * 2.0
	return Vector2(sin(elapsed * 33.0) * intensity, sin(elapsed * 21.0) * 0.8)

func delete_game(slot: int) -> bool:
	var error := DirAccess.remove_absolute(slot_path(slot))
	if error != OK: return false
	if active_slot == slot: active_slot = -1
	deleting_slot = -1
	return true

func open_menu() -> void:
	if active_slot >= 0 and state != "menu" and not save_game(): return
	state = "menu"
	deleting_slot = -1

func menu_click(at: Vector2) -> void:
	for slot in range(SAVE_LIMIT):
		var y := 180 + slot * 86
		if Rect2(880, y, 170, 70).has_point(at) and FileAccess.file_exists(slot_path(slot)):
			if deleting_slot == slot:
				menu_message = "存档已删除。" if delete_game(slot) else "删除失败。"
			else:
				deleting_slot = slot
			return
		if Rect2(110, y, 750, 70).has_point(at):
			deleting_slot = -1
			if FileAccess.file_exists(slot_path(slot)): load_game(slot)
			else: new_game(slot)
			return

func draw_save_menu() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color("0c1420"))
	text_at("地心探险 · 本地存档", Vector2(110, 85), 36, Color("6ad1c3"))
	var full := true
	for slot in range(SAVE_LIMIT):
		if not FileAccess.file_exists(slot_path(slot)): full = false
	text_at("存档已满，请删除一个存档后开始新游戏。" if full else menu_message, Vector2(110, 130), 20)
	for slot in range(SAVE_LIMIT):
		var y := 180 + slot * 86
		var data := read_slot(slot)
		draw_rect(Rect2(110, y, 750, 70), Color("1b303f"))
		if data.is_empty():
			text_at("%d · 新游戏（空槽位）" % (slot + 1), Vector2(130, y + 43), 24)
		else:
			text_at("%d · %s" % [slot + 1, "存档损坏" if data.has("invalid") else "继续探索 · %d 米" % int(data.depth)], Vector2(130, y + 29), 22)
			if not data.has("invalid"):
				text_at("开始 %s   最后游玩 %s" % [data.started_at, data.last_played], Vector2(130, y + 56), 17)
			draw_rect(Rect2(880, y, 170, 70), Color("623741"))
			text_at("确认删除" if deleting_slot == slot else "删除存档", Vector2(905, y + 43), 21)
	text_at("点击槽位开始/继续；删除需再次点击确认。游戏中 S 保存、M 返回此页。", Vector2(110, 745), 18)
