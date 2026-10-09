extends Node2D
var frames: Dictionary = {}
var raw: Dictionary = {}
var previous: Dictionary = {}
var show_raw := false
var light := true
var action := "attack"
var combat := true
var effects := true
var combat_bodies: Array = []
var combat_fx: Array = []
var timing: Dictionary = {}
var combat_index := 0
var fx_sprite := Sprite2D.new()
var elapsed := 0.0
var playing := true
var frame_index := 0
var font := ThemeDB.fallback_font

func _ready() -> void:
	timing = JSON.parse_string(FileAccess.get_file_as_string("res://../combat-v1/timing.json"))
	for i in range(timing["frames"].size()):
		combat_bodies.append(ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path("res://../combat-v1/body_%02d.png" % i))))
		combat_fx.append(ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path("res://../combat-v1/fx_%02d.png" % i))))
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	fx_sprite.material = additive
	fx_sprite.position = Vector2(820, 420)
	fx_sprite.scale = Vector2.ONE * (512.0 / 768.0)
	add_child(fx_sprite)
	for name in ["walk", "attack"]:
		frames[name] = []
		raw[name] = []
		previous[name] = []
		var selected: String = name + "-hq" if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://../review/" + name + "-hq")) else name
		var alpha_dir := ProjectSettings.globalize_path("res://../review/" + selected)
		var old_dir := alpha_dir
		var improved := ProjectSettings.globalize_path("res://../matte-v2/" + selected)
		if DirAccess.dir_exists_absolute(improved):
			alpha_dir = improved
		var raw_dir := ProjectSettings.globalize_path("res://../output/frames")
		for spec in [[alpha_dir, frames[name], ""], [raw_dir, raw[name], selected + "_"], [old_dir, previous[name], ""]]:
			var directory := DirAccess.open(spec[0])
			if directory == null:
				continue
			var files := directory.get_files()
			files.sort()
			for filename in files:
				if filename.ends_with(".png") and filename.begins_with(spec[2]):
					if spec[2] == "" and not filename.get_basename().is_valid_int():
						continue
					var image := Image.load_from_file(str(spec[0]) + "/" + filename)
					if image != null:
						spec[1].append(ImageTexture.create_from_image(image))
		print(name, ": new=", frames[name].size(), " old=", previous[name].size(), " raw=", raw[name].size())
	queue_redraw()

func _process(delta: float) -> void:
	if playing and frames[action].size() > 0:
		elapsed += delta
		frame_index = int(elapsed * 24.0) % frames[action].size()
		var cursor := fmod(elapsed * 1000.0, float(timing["duration_ms"]) + float(timing["idle_ms"]))
		combat_index = timing["frames"].size() - 1
		for i in range(timing["frames"].size()):
			cursor -= float(timing["frames"][i]["duration_ms"])
			if cursor < 0:
				combat_index = i
				break
	fx_sprite.visible = combat and action == "attack" and effects
	fx_sprite.texture = combat_fx[combat_index]
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_SPACE:
		playing = not playing
	elif event.keycode == KEY_B:
		light = not light
	elif event.keycode == KEY_R:
		show_raw = not show_raw
	elif event.keycode == KEY_T:
		combat = not combat
		elapsed = 0.0
	elif event.keycode == KEY_F:
		effects = not effects
	elif event.keycode == KEY_1 or event.keycode == KEY_2:
		action = "walk" if event.keycode == KEY_1 else "attack"
		elapsed = 0.0
		frame_index = 0
	elif event.keycode == KEY_RIGHT and frames[action].size() > 0:
		playing = false
		combat_index = (combat_index + 1) % combat_bodies.size()
		frame_index = (frame_index + 1) % frames[action].size()
		elapsed = frame_index / 24.0

func _draw() -> void:
	draw_string(font, Vector2(30, 36), "1 Walk  2 Attack  Space Pause  Right Step  B Background  T Timing  F FX  R Raw", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var active_combat := combat and action == "attack"
	var label := "LEFT: original 5.17s | RIGHT: attack %.3fs + additive FX" % (float(timing["duration_ms"]) / 1000.0) if active_combat else "LEFT: old matte | RIGHT: new matte"
	draw_string(font, Vector2(30, 69), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	for x in range(24, 1080, 24):
		for y in range(95, 745, 24):
			var c1 := Color("c7d5e7") if light else Color("263244")
			var c2 := Color("eef3f9") if light else Color("1c2534")
			draw_rect(Rect2(x, y, 24, 24), c1 if (x / 24 + y / 24) % 2 == 0 else c2)
	var left: Array = raw[action] if show_raw else (frames[action] if active_combat else previous[action])
	for spec in [[left, Vector2(24, 100), frame_index], [combat_bodies if active_combat else frames[action], Vector2(564, 100), combat_index if active_combat else frame_index]]:
		if spec[0].size() > spec[2]:
			var texture: Texture2D = spec[0][spec[2]]
			var factor: float = minf(512.0 / texture.get_width(), 640.0 / texture.get_height())
			var draw_size: Vector2 = texture.get_size() * factor
			var position: Vector2 = spec[1] + (Vector2(512, 640) - draw_size) * 0.5
			draw_texture_rect(texture, Rect2(position, draw_size), false)
	if frames[action].is_empty():
		draw_string(font, Vector2(60, 180), "Waiting for rendered frames...", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
