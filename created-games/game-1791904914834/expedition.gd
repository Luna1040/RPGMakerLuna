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
		level += 1
		cuts += 1
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
	attack_target = target
	attack_direction = facing
	attack_time = 0.34
	hit_pending = true

func resolve_hit() -> void:
	var id := stone(attack_target)
	if id >= BLACK_BASE:
		cuts += 1
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
	cuts += 1
	break_cells(group, false)
	toast = "%s连锁 × %d  ·  +%d 分" % [NAMES[color_id], last_chain, last_chain * 10 + maxi(0, last_chain - 1) * 5]
	toast_time = 2.4

func break_cells(group: Array[Vector2i], from_collision: bool) -> void:
	for cell in group:
		var id := stone(cell)
		if id < 0: continue
		var tint: Color = COLORS[id] if id < BLACK_BASE else Color("555555")
		rows[cell.y][cell.x] = -1
		rock_offsets.erase(cell)
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
		if supported: continue
		for cell in group:
			rows[cell.y][cell.x] = -1
			rock_offsets.erase(cell)
		var moved: Dictionary = {}
		for cell in group:
			var next: Vector2i = cell + Vector2i.DOWN
			rows[next.y][next.x] = id
			rock_offsets[next] = -TILE
			moved[next] = true
			moved_this_tick[next] = true
		changed = true
		var impact := false
		for cell in moved:
			var below: Vector2i = cell + Vector2i.DOWN
			if not moved.has(below) and stone(below) == id:
				impact = true
				break
		if impact and id < BLACK_BASE:
			var impact_group := cluster(first + Vector2i.DOWN)
			break_cells(impact_group, true)
			toast = "同色落石碰撞！连锁破碎 ×%d" % impact_group.size()
			toast_time = 3
	return changed

func step_down() -> bool:
	if state == "cleared": return false
	ensure_rows(maxi(player.y + 64, level * LAYER_HEIGHT + AIR_HEIGHT))
	if stone(player + Vector2i.DOWN) != -1: return false
	player.y += 1
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

func face_front() -> void:
	if state == "playing" and attack_time <= 0:
		facing = Vector2i.DOWN

func click_stone(position_in_game: Vector2) -> void:
	if state != "playing": return
	if not Rect2(ORIGIN, Vector2(WIDTH * TILE, VIEW_ROWS * TILE)).has_point(position_in_game): return
	var local := (position_in_game - ORIGIN) / TILE + Vector2(0, camera_row)
	var clicked := Vector2i(floori(local.x), floori(local.y))
	if clicked == player + facing and stone(clicked) >= 0:
		begin_attack()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state == "menu":
			menu_click(event.position)
		elif Rect2(790, 704, 180, 30).has_point(event.position): save_game()
		elif Rect2(990, 704, 210, 30).has_point(event.position): open_menu()
		elif state == "briefing": state = "playing"
		elif state == "playing": click_stone(event.position)
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
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
			if state == "playing": state = "paused"
			elif state == "paused": state = "playing"
		KEY_SPACE: begin_attack()
		KEY_UP, KEY_DOWN: face_front()
		KEY_LEFT: move_horizontal(-1)
		KEY_RIGHT: move_horizontal(1)

func simulate(delta: float) -> void:
	if state != "playing": return
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
	if fall_time >= 0.105:
		fall_time = 0
		step_down()
	gravity_time += delta
	if gravity_enabled and gravity_dirty and gravity_time >= 0.105 and not hit_pending and state == "playing":
		gravity_time = 0
		gravity_dirty = settle_rocks()
	# Last cut may win after a long fall; only judge failure when landed.
	if challenge and cuts - level_start_cuts >= CUT_LIMIT and state == "playing" and not hit_pending and attack_time == 0 and stone(player + Vector2i.DOWN) >= 0:
		state = "lost"
	visual_player = visual_player.lerp(Vector2(player), minf(1, delta * 18))
	camera_row = lerpf(camera_row, clampf(visual_player.y - 4, (level - 1) * LAYER_HEIGHT, level * LAYER_HEIGHT - VIEW_ROWS + 1), minf(1, delta * 8))
	for cell in rock_offsets.keys():
		rock_offsets[cell] = move_toward(rock_offsets[cell], 0, delta * TILE / 0.105)
		if rock_offsets[cell] == 0: rock_offsets.erase(cell)
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
		if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_UP): face_front()
		if Input.is_physical_key_pressed(KEY_SPACE): begin_attack()
		simulate(minf(delta, 0.05))
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
	var bend := sin((1 - attack_time / 0.34) * PI) * 3 if swing else 0.0
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
	var angle := -0.9
	if swing: angle = lerpf(-2.1, 1.3 if shown_direction == Vector2i.DOWN else 0.0, clampf((0.34 - attack_time) / 0.14, 0, 1))
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
	for shard in shards:
		var p: Vector2 = ORIGIN + shard.pos - Vector2(0, camera_row * TILE)
		if p.y < ORIGIN.y + 5 or p.y > ORIGIN.y + VIEW_ROWS * TILE - 5: continue
		var tint: Color = shard.color
		tint.a = shard.life / 0.6
		draw_rect(Rect2(p - Vector2.ONE * 3, Vector2.ONE * 6), tint)
	var at := screen_pos(visual_player) + Vector2.ONE * TILE / 2
	if shake > 0: at.x += sin(elapsed * 100) * shake
	draw_explorer(at)
	draw_rect(Rect2(ORIGIN.x, 110, WIDTH * TILE, 28), Color("0c1420"))
	draw_rect(Rect2(ORIGIN.x, 738, WIDTH * TILE, 62), Color("0c1420"))
	text_at("↓ %d 米" % depth, Vector2(50, 775), 23, Color("e9ad63"))
	text_at(toast if toast_time > 0 else "金框：可砍目标；白框：同色连锁", Vector2(220, 775), 17, Color("b9cddd"))
	draw_rect(Rect2(762, 138, 470, 600), Color("172634"))
	text_at("第 %d 层 · %s" % [level, "限刀挑战" if challenge else "深入地心"], Vector2(790, 179), 25, Color("6ad1c3"))
	text_at("%d" % depth, Vector2(790, 253), 54)
	text_at("米 · 本层 %d / 100米" % (depth - (level - 1) * 100), Vector2(790, 282), 18, Color("96adbf"))
	text_at("得分  %d" % score, Vector2(790, 328), 23)
	text_at("连锁  ×%d     最佳  ×%d" % [last_chain, best_chain], Vector2(790, 371), 21, Color("e9ad63"))
	text_at("碎岩 %d · 本层挥刀 %d%s" % [broken, cuts - level_start_cuts, " /150" if challenge else ""], Vector2(790, 408), 19)
	var guide := ["面向：%s" % ("左边 ←" if facing == Vector2i.LEFT else ("右边 →" if facing == Vector2i.RIGHT else "正前方 ↓")), "← → 移动转向；↑ ↓ 面向前方", "空格 / 点击金框石块 · 砍", "每层：5米空区 + 95排石头", "通关后再按空格挥刀进入下一层", "黑石数字 = 剩余刀数；独立下落", "同色整体无支撑时会下落", "彩石撞到同色石头一起破碎", "长按空格连砍；Esc 暂停", "S 手动存档 · M / R 存档菜单"]
	for i in range(guide.size()): text_at(guide[i], Vector2(790, 456 + i * 25), 18, Color("a9becd"))
	draw_rect(Rect2(790, 704, 180, 30), Color("285060"))
	text_at("手动存档 [S]", Vector2(805, 726), 18)
	draw_rect(Rect2(990, 704, 210, 30), Color("285060"))
	text_at("存档菜单 [M]", Vector2(1005, 726), 18)
	if state == "menu": draw_save_menu()
	elif state != "playing": draw_overlay()

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
		title = "挑战结束 · 刀数用尽"
		lines = ["本次深入 %d 米，得分 %d" % [depth, score], "尝试寻找更大的同色连锁，节省挥刀次数。", "按 R 重来；开始前按 C 可切换无限模式"]
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
	var data := {"version": 1, "started_at": started_at, "last_played": last_played, "rows": {}, "rng_state": str(rng.state)}
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
	active_slot = slot
	started_at = data.started_at
	last_played = data.last_played
	visual_player = Vector2(player)
	camera_row = clampf(player.y - 4, (level - 1) * LAYER_HEIGHT, level * LAYER_HEIGHT - VIEW_ROWS + 1)
	if state == "paused" or state == "briefing": state = "playing"
	deleting_slot = -1
	save_game()
	return true

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
