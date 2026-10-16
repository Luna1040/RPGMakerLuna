extends Control
## Full-scene H3 clips. Gameplay remains the sole authority for cards and chips.
signal release_event(action: String)
var player: VideoStreamPlayer
var clips := {}
var action := "idle"
var release_seconds := {"deal": 1.65, "payout": 2.8}
var elapsed := 0.0
var released := false
var action_running := false
var generation := 0
var transition: TextureRect
var transition_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	player = VideoStreamPlayer.new()
	player.expand = true
	player.size = Vector2(1280,720)
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.volume_db = -80
	add_child(player)
	transition = TextureRect.new()
	transition.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	transition.size = Vector2(1280,720)
	transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition.hide()
	add_child(transition)
	for name in ["idle", "deal", "payout"]:
		var path: String = "res://assets/dealer/" + name + ".ogv"
		if ResourceLoader.exists(path): clips[name] = load(path)
	player.finished.connect(_finished)
	play_idle()

func _process(delta: float) -> void:
	if not action_running: return
	elapsed += delta
	if not released and elapsed >= float(release_seconds.get(action, 1.65)):
		released = true
		release_event.emit(action)

func play_idle() -> void:
	_crossfade()
	action = "idle"
	action_running = false
	if clips.has("idle"):
		player.stream = clips.idle
		player.loop = true
		player.play()
		player.show()
	else: player.hide()

func begin(name: String) -> void:
	generation += 1
	if not clips.has(name): return
	_crossfade()
	player.stop()
	action = name
	elapsed = 0.0
	released = false
	action_running = true
	player.stream = clips[name]
	player.loop = false
	player.show()
	player.play()
	var ticket := generation
	while action_running and not released and ticket == generation:
		await get_tree().process_frame

func complete() -> void:
	while action_running: await get_tree().process_frame

func _finished() -> void:
	if action_running:
		if not released:
			released = true
			release_event.emit(action)
		play_idle()

func _crossfade() -> void:
	if not player.stream: return
	var texture := player.get_video_texture()
	if not texture: return
	var frame := texture.get_image()
	if not frame or frame.is_empty(): return
	if transition_tween: transition_tween.kill()
	transition.texture = ImageTexture.create_from_image(frame)
	transition.modulate.a = 1.0
	transition.show()
	transition_tween = create_tween()
	transition_tween.tween_interval(0.12)
	transition_tween.tween_property(transition,"modulate:a",0.0,0.2)
	transition_tween.tween_callback(transition.hide)
