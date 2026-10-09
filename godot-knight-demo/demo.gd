extends Node2D

var walk_preview: AnimatedSprite2D
var slash_preview: AnimatedSprite2D
var hero: AnimatedSprite2D
var frames: SpriteFrames
var offsets: Dictionary = {}
var hero_position := Vector2(480, 470)
var attacking := false
var preview_pause := 0.0
var timer := 0.0

func _ready() -> void:
	frames = build_frames()
	walk_preview = make_actor(Vector2(235, 270))
	slash_preview = make_actor(Vector2(707, 270))
	hero = make_actor(hero_position)
	walk_preview.play("walk")
	slash_preview.play("slash")
	slash_preview.animation_finished.connect(func() -> void: preview_pause = 0.65)
	hero.animation_finished.connect(func() -> void:
		attacking = false
		hero.play("idle")
	)
	hero.play("idle")
	print("KNIGHT_READY walk=%d slash=%d" % [frames.get_frame_count("walk"), frames.get_frame_count("slash")])

func build_frames() -> SpriteFrames:
	var attack_atlas: Texture2D = load("res://assets/princess-knight-atlas-v2.png")
	var walk_atlas: Texture2D = load("res://assets/princess-knight-walk-v3.png")
	var result := SpriteFrames.new()
	result.remove_animation("default")
	for animation_name in ["idle", "walk", "slash"]:
		offsets[animation_name] = []
		result.add_animation(animation_name)
		result.set_animation_speed(animation_name, 5 if animation_name == "walk" else 9)
		result.set_animation_loop(animation_name, animation_name != "slash")
		var count := 1 if animation_name == "idle" else (4 if animation_name == "walk" else 6)
		for i in range(count):
			# Discard contaminated recovery cells. End on the clean preparation frame.
			var index: int = [8, 9, 10, 11, 13, 8][i] if animation_name == "slash" else i
			var atlas: Texture2D = attack_atlas if animation_name == "slash" else walk_atlas
			var pixels := atlas.get_image()
			var columns := 4 if animation_name == "slash" else 2
			var texture := AtlasTexture.new()
			texture.atlas = atlas
			var col: int = index % columns
			var row: int = floori(index / float(columns))
			var start := Vector2i(floori(col * atlas.get_width() / float(columns)), floori(row * atlas.get_height() / float(columns)))
			var end := Vector2i(floori((col + 1) * atlas.get_width() / float(columns)), floori((row + 1) * atlas.get_height() / float(columns)))
			if animation_name == "slash" and index == 13:
				start.x += 30 # Exclude sword fragments bleeding in from the adjacent cell.
			var cell := Vector2(end - start)
			texture.region = Rect2(Vector2(start), cell)
			# Compute foot anchor from the central lower body, excluding the outer sword arc.
			var baseline := int(cell.y * 0.88)
			for y in range(int(cell.y) - 1, int(cell.y * 0.7), -1):
				var solid := 0
				for x in range(int(cell.x * 0.20), int(cell.x * 0.59)):
					if pixels.get_pixel(start.x + x, start.y + y).a > 0.7:
						solid += 1
				if solid > 6:
					baseline = y
					break
			offsets[animation_name].append(Vector2(cell.x * 0.05 - (15 if animation_name == "slash" and index == 13 else 0), cell.y / 2.0 - baseline))
			var duration := 1.0
			if animation_name == "slash":
				duration = [1.3, 1.2, 1.4, 0.8, 1.0, 1.6][i]
			result.add_frame(animation_name, texture, duration)
	return result

func make_actor(anchor: Vector2) -> AnimatedSprite2D:
	var actor := AnimatedSprite2D.new()
	actor.sprite_frames = frames
	actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var cell := frames.get_frame_texture("walk", 0).get_size()
	actor.scale = Vector2.ONE * (150.0 / cell.y)
	actor.offset = Vector2(cell.x * 0.05, -cell.y * 0.35)
	actor.position = anchor
	actor.frame_changed.connect(func() -> void: update_anchor(actor))
	actor.animation_changed.connect(func() -> void: update_anchor(actor))
	add_child(actor)
	update_anchor(actor)
	return actor

func update_anchor(actor: AnimatedSprite2D) -> void:
	if offsets.has(actor.animation):
		var atlas_texture := frames.get_frame_texture(actor.animation, actor.frame) as AtlasTexture
		actor.scale = Vector2.ONE * (150.0 / (atlas_texture.atlas.get_height() / (4.0 if actor.animation == "slash" else 2.0)))
		actor.offset = offsets[actor.animation][mini(actor.frame, offsets[actor.animation].size() - 1)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		start_attack()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		start_attack()

func start_attack() -> void:
	if attacking:
		return
	attacking = true
	hero.play("slash")
	queue_redraw()

func _physics_process(delta: float) -> void:
	timer += delta
	if preview_pause > 0:
		preview_pause -= delta
		if preview_pause <= 0:
			slash_preview.play("slash")
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	move += Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if not attacking:
		hero_position = (hero_position + move.limit_length() * 100 * delta).clamp(Vector2(110, 450), Vector2(850, 510))
		if move.x != 0:
			hero.flip_h = move.x < 0
		hero.play("walk" if move.length() > 0 else "idle")
	hero.position = hero_position.round()
	queue_redraw()

func text_at(at: Vector2, content: String, size: int = 18, color: Color = Color(0.77, 0.83, 0.94)) -> void:
	draw_string(ThemeDB.fallback_font, at, content, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	for x in range(0, 960, 24):
		for y in range(96, 535, 24):
			draw_rect(Rect2(x, y, 23, 23), Color(0.06, 0.08, 0.12))
	draw_rect(Rect2(24, 94, 440, 192), Color(0.13, 0.17, 0.25), false, 2)
	draw_rect(Rect2(496, 94, 440, 192), Color(0.13, 0.17, 0.25), false, 2)
	draw_rect(Rect2(24, 320, 912, 213), Color(0.17, 0.21, 0.3), false, 2)
	text_at(Vector2(28, 39), "PRINCESS KNIGHT", 26, Color(0.93, 0.85, 0.59))
	text_at(Vector2(29, 68), "AI GENERATED SPRITE ATLAS / GODOT ANIMATEDSPRITE2D", 15)
	text_at(Vector2(43, 122), "WALK  /  4 KEYFRAMES  /  5 FPS", 16)
	text_at(Vector2(515, 122), "SWORD SLASH  /  6 KEYFRAMES", 16)
	text_at(Vector2(43, 346), "PLAYABLE TEST AREA", 15, Color(0.93, 0.85, 0.59))
	for anchor in [Vector2(235, 270), Vector2(707, 270), hero_position]:
		draw_ground_shadow(anchor)
	text_at(Vector2(29, 562), "WASD / ARROWS: WALK     SPACE / LEFT CLICK: SWORD SLASH", 17)
	text_at(Vector2(29, 587), "State: " + ("ATTACK" if attacking else "MOVE / IDLE") + "  |  Horizontal direction mirrored", 14)

func draw_ground_shadow(at: Vector2) -> void:
	var points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * i / 24.0
		points.append(at + Vector2(cos(angle) * 29, sin(angle) * 6))
	draw_colored_polygon(points, Color(0.025, 0.033, 0.05, 0.7))
