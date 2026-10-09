extends Node2D

var player := Vector2(320, 180)
var enemies: Array[Vector2] = []
var gems: Array[Vector2] = []
var score := 0
var hp := 5
var elapsed := 0.0
var spawn_clock := 0.0
var attack_clock := 0.0
var hurt_cooldown := 0.0
var dash_cooldown := 0.0
var dash_time := 0.0
var direction := Vector2.RIGHT

func _ready() -> void:
	print("DEMO_READY: pixel dungeon")
	for i in range(4):
		enemies.append(Vector2(80 + i * 140, 70))

func _physics_process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_R):
		get_tree().reload_current_scene()
		return
	if hp <= 0:
		queue_redraw()
		return
	elapsed += delta
	hurt_cooldown = maxf(0, hurt_cooldown - delta)
	dash_cooldown = maxf(0, dash_cooldown - delta)
	dash_time = maxf(0, dash_time - delta)
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	move += Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if move.length() > 0:
		direction = move.normalized()
	if Input.is_physical_key_pressed(KEY_SPACE) and dash_cooldown <= 0:
		dash_time = 0.16
		dash_cooldown = 1.2
	var velocity := direction * 400 if dash_time > 0 else move.limit_length() * 110
	player = (player + velocity * delta).clamp(Vector2(24, 48), Vector2(616, 310))
	spawn_clock += delta
	attack_clock += delta
	if spawn_clock >= 1.8 and enemies.size() < 35:
		spawn_clock = 0
		enemies.append(Vector2(randf_range(30, 610), 50 if randf() < 0.5 else 300))
	var attack := attack_clock > maxf(0.25, 0.8 - score * 0.01)
	if attack:
		attack_clock = 0
	for i in range(enemies.size() - 1, -1, -1):
		enemies[i] = enemies[i].move_toward(player, delta * minf(75, 30 + elapsed * 0.4))
		if attack and enemies[i].distance_to(player) < 60:
			gems.append(enemies[i])
			enemies.remove_at(i)
		elif enemies[i].distance_to(player) < 13 and hurt_cooldown <= 0 and dash_time <= 0:
			hp -= 1
			hurt_cooldown = 1
	for i in range(gems.size() - 1, -1, -1):
		if gems[i].distance_to(player) < 20:
			score += 1
			gems.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for x in range(1, 39):
		for y in range(3, 20):
			var shade := 0.105 if (x + y) % 2 == 0 else 0.125
			draw_rect(Rect2(x * 16, y * 16, 15, 15), Color(shade, shade + 0.01, shade + 0.045))
	draw_rect(Rect2(16, 40, 608, 280), Color(0.32, 0.28, 0.48), false, 4)
	for gem in gems:
		draw_rect(Rect2(gem.round() - Vector2(3, 3), Vector2(6, 6)), Color(0.2, 0.95, 0.78))
	for enemy in enemies:
		draw_rect(Rect2(enemy.round() - Vector2(6, 5), Vector2(12, 10)), Color(0.84, 0.29, 0.4))
		draw_rect(Rect2(enemy.round() + Vector2(1, -3), Vector2(2, 2)), Color.WHITE)
	var p := player.round()
	draw_rect(Rect2(p - Vector2(6, 1), Vector2(12, 10)), Color(0.28, 0.56, 1))
	draw_rect(Rect2(p - Vector2(5, 9), Vector2(10, 8)), Color(1, 0.8, 0.57))
	draw_rect(Rect2(p + Vector2(2, -7), Vector2(2, 2)), Color(0.12, 0.12, 0.2))
	if attack_clock < 0.1:
		draw_arc(p, 60, 0, TAU, 32, Color(0.65, 0.75, 1, 0.6), 2)
	draw_string(ThemeDB.fallback_font, Vector2(20, 344), "HP: %d   GEMS: %d   TIME: %ds   AUTO ATTACK + GEM COLLECTION" % [hp, score, int(elapsed)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 1))
	if hp <= 0:
		draw_string(ThemeDB.fallback_font, Vector2(220, 180), "GAME OVER - R to restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
