extends Node2D

const TARGET := 10
const SPEED := 340.0
const PLAYER_RADIUS := 18.0
const FIELD := Rect2(40, 164, 1200, 554)
const GOLD := Color("ffd56a")
const CYAN := Color("58e4ed")
const STAR_POSITIONS := [
	Vector2(170, 260), Vector2(400, 230), Vector2(650, 280),
	Vector2(900, 230), Vector2(1120, 300), Vector2(250, 470),
	Vector2(490, 540), Vector2(770, 480), Vector2(1030, 550),
	Vector2(650, 650)
]

var player := Vector2(640, 410)
var stars: Array[Vector2] = []
var collected := 0
var won := false
var elapsed := 0.0
var animation_time := 0.0
var flash := 0.0
var bursts: Array[Dictionary] = []
var ui_font: Font = preload("res://font.ttf")

func _ready() -> void:
	reset_game()

func reset_game() -> void:
	player = Vector2(640, 410)
	stars.clear()
	for point in STAR_POSITIONS:
		stars.append(point)
	collected = 0
	won = false
	elapsed = 0.0
	flash = 0.0
	bursts.clear()
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		reset_game()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	animation_time += delta
	flash = maxf(0.0, flash - delta)
	for index in range(bursts.size() - 1, -1, -1):
		bursts[index]["life"] -= delta
		if bursts[index]["life"] <= 0.0:
			bursts.remove_at(index)
	if not won:
		elapsed += delta
		var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		player += direction * SPEED * delta
		player.x = clampf(player.x, FIELD.position.x + PLAYER_RADIUS, FIELD.end.x - PLAYER_RADIUS)
		player.y = clampf(player.y, FIELD.position.y + PLAYER_RADIUS, FIELD.end.y - PLAYER_RADIUS)
		for index in range(stars.size() - 1, -1, -1):
			if player.distance_to(stars[index]) <= PLAYER_RADIUS + 13.0:
				bursts.append({"position": stars[index], "life": 0.5})
				stars.remove_at(index)
				collected += 1
				flash = 0.45
				if collected == TARGET:
					won = true
	queue_redraw()

func text_at(value: String, at: Vector2, size: int, color: Color) -> void:
	draw_string(ui_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func centered(value: String, y: float, size: int, color: Color) -> void:
	var width := ui_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text_at(value, Vector2((1280.0 - width) * 0.5, y), size, color)

func draw_star(at: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(10):
		var angle := -PI / 2.0 + index * PI / 5.0
		var length := radius if index % 2 == 0 else radius * 0.44
		points.append(at + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, color)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color("08162e"))
	text_at("星光采集", Vector2(44, 66), 36, Color("eef7ff"))
	text_at("驾驶青色光球，收集场上的全部 10 颗星点。", Vector2(46, 108), 20, Color("9eb4d0"))
	text_at("%02d / 10" % collected, Vector2(1024, 72), 36, GOLD if flash > 0 else CYAN)
	text_at("已收集星点", Vector2(1026, 104), 18, Color("9eb4d0"))
	draw_rect(Rect2(44, 132, 1192, 4), Color("203755"))
	if collected > 0:
		draw_rect(Rect2(44, 132, 1192.0 * collected / TARGET, 4), GOLD)
	draw_style_box(field_style(), FIELD)
	for x in range(80, 1240, 40):
		for y in range(200, 718, 40):
			draw_circle(Vector2(x, y), 1.0, Color("1b3050"))
	for index in range(stars.size()):
		var at := stars[index]
		var pulse := 1.0 + sin(animation_time * 3.0 + index) * 0.10
		draw_circle(at, 25.0 * pulse, Color(1.0, 0.78, 0.3, 0.07))
		draw_star(at, 13.0 * pulse, GOLD)
	for burst in bursts:
		var progress: float = 1.0 - float(burst["life"]) / 0.5
		var at: Vector2 = burst["position"]
		draw_arc(at, 15.0 + progress * 38.0, 0, TAU, 40, Color(1, 0.84, 0.42, 1.0 - progress), 2.0, true)
	draw_circle(player + Vector2(0, 5), 22, Color(0, 0, 0, 0.22))
	draw_circle(player, 28, Color(0.3, 0.9, 0.95, 0.09))
	draw_circle(player, PLAYER_RADIUS, CYAN)
	draw_circle(player + Vector2(-5, -6), 5, Color("c6fbff"))
	text_at("↑ ↓ ← →  移动", Vector2(46, 765), 22, Color("e0edff"))
	text_at("R  重新开始", Vector2(300, 765), 22, Color("e0edff"))
	text_at("用时  %.1f 秒" % elapsed, Vector2(1040, 765), 20, Color("9eb4d0"))
	if won:
		draw_rect(Rect2(0, 164, 1280, 554), Color(0.02, 0.06, 0.13, 0.86))
		draw_star(Vector2(640, 320), 35, GOLD)
		centered("收集完成！", 412, 48, Color("eef7ff"))
		centered("10 / 10 颗星点 · 用时 %.1f 秒" % elapsed, 462, 24, GOLD)
		centered("按 R 再玩一次", 525, 24, CYAN)

func field_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0c1d38")
	style.border_color = Color("294366")
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	return style
