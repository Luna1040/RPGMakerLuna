extends Node2D

var phase: int = 0
var playing: bool = false
var overlay: bool = false
var light: bool = false
var refined: bool = true
var elapsed: float = 0.0
var assets: Dictionary = {}
var font: SystemFont
const PHASES = ["A", "M", "B"]

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Arial"])
	for route in ["gpt", "controlnet", "refined"]:
		for p in PHASES:
			for variant in ["raw", "overlay"]:
				var filename: String = "%s-%s.png" % [route, p]
				if route == "controlnet":
					filename = "controlnet-%s-rgba.png" % p
				if route == "refined":
					filename = "local-refined-%s-rgba.png" % p
				if variant == "overlay":
					filename = "%s-%s-overlay.png" % [route, p]
				var path := ProjectSettings.globalize_path("res://../" + filename)
				if FileAccess.file_exists(path):
					var im := Image.load_from_file(path)
					assets[route + p + variant] = ImageTexture.create_from_image(im)
	queue_redraw()

func _process(delta: float) -> void:
	if playing:
		elapsed += delta
		if elapsed >= 0.55:
			elapsed = 0.0
			phase = (phase + 1) % 3
			queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: playing = not playing
			KEY_RIGHT: phase = (phase + 1) % 3
			KEY_LEFT: phase = (phase + 2) % 3
			KEY_O: overlay = not overlay
			KEY_B: light = not light
			KEY_T: refined = not refined
		queue_redraw()

func _draw() -> void:
	if font == null:
		return
	draw_rect(Rect2(0, 0, 1120, 680), Color("141c29"))
	draw_string(font, Vector2(25, 36), "姿势约束实验 · 三关键帧，尚非完成动画", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color.WHITE)
	draw_string(font, Vector2(25, 66), "空格 播放/暂停   ← → 切帧   O 骨架叠加   B 深浅背景   T 本地底稿/重绘     当前：" + PHASES[phase], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("bdcada"))
	for idx in range(2):
		var route: String = ["gpt", "refined" if refined else "controlnet"][idx]
		var origin := Vector2(25 + idx * 550, 115)
		for y in range(0, 512, 16):
			for x in range(0, 512, 16):
				var parity := (x / 16 + y / 16) % 2
				var colors := [Color("202735"), Color("2e3848")]
				if light:
					colors = [Color("eeeeee"), Color("cccccc")]
				draw_rect(Rect2(origin + Vector2(x, y), Vector2(16, 16)), colors[parity])
		var key: String = route + PHASES[phase] + ("overlay" if overlay else "raw")
		if assets.has(key):
			draw_texture_rect(assets[key], Rect2(origin, Vector2(512, 512)), false)
		else:
			draw_string(font, origin + Vector2(150, 240), "该帧尚未生成", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		var title: String = ["GPT：母版＋骨架参考／透明 PNG", "本地：ControlNet→Flux 重绘→抠图" if refined else "本地底稿：SDXL＋ControlNet→抠图"][idx]
		draw_string(font, origin + Vector2(0, -15), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, Vector2(25, 658), "对照原始画布；未逐帧居中或修正剑长。循环末尾直接重置到 A。", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f3c482"))
