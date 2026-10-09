extends CharacterBody2D
## Self-contained character. Map scenes consume events; they own targets/projectiles.
signal attack_hitbox(event: Dictionary)
signal spell_requested(event: Dictionary)
signal action_changed(action: String)
signal stats_changed(health: float, mana: float)
signal died
signal equipment_changed

@export var move_speed := 200.0
@export var input_enabled := true
@export var use_local_input := true
@export var visual_scale := 0.62
@export var melee_reach_margin := 24.0
var facing := 1
var health := 100.0
var mana := 100.0
var cast_cooldown := 0.0
var state := "stand"
var elapsed := 0.0
var inactivity := 0.0
var combo_buffered := false
var cast_buffered := false
var fired := false
var action_frame := 0
var clips: Dictionary = {}
var textures: Dictionary = {}
var body := Sprite2D.new()
var glow := Sprite2D.new()
var visual := Node2D.new()
var flash := 0.0
var defeated := false
var movement_axis := 0.0
var equipment = preload("equipment.gd").new()
var max_health := 100.0
var max_mana := 100.0
var attack_bonus := 0.0
var magic_bonus := 0.0
var defense := 0.0
var mana_regen := 7.0
var equipment_speed_bonus := 0.0

func refresh_equipment() -> void:
	var bonus: Dictionary = equipment.bonuses()
	max_health = 100.0 + bonus["health"]
	max_mana = 100.0 + bonus["mana"]
	attack_bonus = bonus["attack"]
	magic_bonus = bonus["magic"]
	defense = bonus["defense"]
	mana_regen = 7.0 + bonus["regen"]
	equipment_speed_bonus = bonus["speed"]
	# Capacity changes never heal/revive; excess resources are clamped.
	health = minf(health, max_health)
	mana = minf(mana, max_mana)
	stats_changed.emit(health, mana)
	equipment_changed.emit()

func get_effective_stats() -> Dictionary:
	return {"health":max_health,"mana":max_mana,"attack":attack_bonus,"magic":magic_bonus,"defense":defense,"speed":move_speed + equipment_speed_bonus,"regen":mana_regen}

func get_attack_damage(action: String) -> float:
	return float(clips[action].get("damage", 20)) + attack_bonus

func get_attack_reach(action: String) -> float:
	return (float(clips[action].get("range", 180)) + melee_reach_margin) * visual_scale / 0.62

func set_movement_axis(axis: float) -> void:
	movement_axis = clampf(axis, -1.0, 1.0)

func _ready() -> void:
	equipment.changed.connect(refresh_equipment)
	if "--smoke-test" in OS.get_cmdline_user_args() or "--equipment-test" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args() or "--capture-equipment" in OS.get_cmdline_user_args():
		equipment.persistence_enabled = false
	equipment.load_loadout()
	refresh_equipment()
	health = max_health
	mana = max_mana
	var asset_root: String = get_script().resource_path.get_base_dir() + "/assets/"
	clips = JSON.parse_string(FileAccess.get_file_as_string(asset_root + "animations.json"))
	for name in clips:
		textures[name] = []
		for frame in clips[name]["frames"]:
			var pair: Array = [load(asset_root + str(frame["file"])), null]
			if frame.has("fx"):
				pair[1] = load(asset_root + str(frame["fx"]))
			textures[name].append(pair)
	add_child(visual)
	visual.add_child(body)
	visual.add_child(glow)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = additive
	var collision := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 20
	shape.height = 90
	collision.shape = shape
	collision.position.y = -45
	add_child(collision)
	show_frame()
	stats_changed.emit(health, mana)

func change_action(next: String) -> void:
	if not clips.has(next):
		return
	state = next
	if next != "stand":
		inactivity = 0.0
	elapsed = 0.0
	fired = false
	action_frame = 0
	if next == "cast":
		mana -= 25.0
		cast_cooldown = 2.4
		stats_changed.emit(health, mana)
	action_changed.emit(state)

func request_attack() -> void:
	if defeated:
		return
	if state.begins_with("attack"):
		# A fresh press during the latter part of a swing queues one next strike.
		if elapsed >= 0.15:
			combo_buffered = true
	elif state in ["stand", "idle", "walk"]:
		combo_buffered = false
		change_action("attack1")
	inactivity = 0.0

func request_cast() -> void:
	if defeated or mana < 25.0 or cast_cooldown > 0.0:
		return
	if state in ["stand", "idle", "walk"]:
		change_action("cast")
	elif state.begins_with("attack"):
		cast_buffered = true
	inactivity = 0.0

func apply_damage(amount: float, _from_position := Vector2.ZERO) -> void:
	if defeated or amount <= 0 or state == "hurt":
		return
	health = maxf(0.0, health - maxf(minf(1.0, amount), amount - defense))
	combo_buffered = false
	cast_buffered = false
	flash = 0.16
	change_action("hurt")
	stats_changed.emit(health, mana)
	if health == 0:
		defeated = true
		died.emit()

func reset_character() -> void:
	health = max_health
	mana = max_mana
	cast_cooldown = 0.0
	defeated = false
	combo_buffered = false
	cast_buffered = false
	change_action("stand")
	stats_changed.emit(health, mana)

func _unhandled_key_input(event: InputEvent) -> void:
	if not input_enabled or not use_local_input or not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_J:
		request_attack()
	elif event.keycode == KEY_K:
		request_cast()

func _physics_process(delta: float) -> void:
	if clips.is_empty():
		return
	cast_cooldown = maxf(0.0, cast_cooldown - delta)
	flash = maxf(0.0, flash - delta)
	if not defeated:
		mana = minf(max_mana, mana + mana_regen * delta)
	var movement := 0.0
	if input_enabled and not defeated:
		movement = movement_axis
		if use_local_input:
			movement = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	velocity = Vector2.ZERO
	if state in ["stand", "idle", "walk"] and not defeated:
		if movement != 0:
			facing = 1 if movement > 0 else -1
			velocity.x = movement * (move_speed + equipment_speed_bonus)
			inactivity = 0.0
			if state != "walk":
				change_action("walk")
		else:
			inactivity += delta
			if state == "walk":
				change_action("stand")
			if state == "stand" and inactivity >= 4.0:
				change_action("idle")
				inactivity = 0.0
	move_and_slide()
	elapsed += delta
	var clip: Dictionary = clips[state]
	if clip.has("event_ms") and not fired and elapsed * 1000.0 >= float(clip["event_ms"]):
		fired = true
		if state.begins_with("attack"):
			attack_hitbox.emit({"origin":global_position,"facing":facing,"range":get_attack_reach(state),"damage":get_attack_damage(state),"action":state})
		elif state == "cast":
			var release: Array = clip.get("release_offset",[165,-330])
			var offset := Vector2(float(release[0])*facing,float(release[1]))*visual_scale*float(clip.get("scale",1.0))
			spell_requested.emit({"origin":global_position + offset,"facing":facing,"damage":42.0 + magic_bonus})
	var duration := float(clip["duration_ms"]) / 1000.0
	if elapsed >= duration:
		if defeated:
			elapsed = duration - 0.001
		elif state in ["stand", "walk"]:
			elapsed = fmod(elapsed, duration)
		elif state.begins_with("attack") and combo_buffered:
			combo_buffered = false
			change_action("attack2" if state == "attack1" else ("attack3" if state == "attack2" else "attack1"))
		elif state.begins_with("attack") and cast_buffered and mana >= 25.0 and cast_cooldown <= 0:
			cast_buffered = false
			change_action("cast")
		else:
			cast_buffered = false
			change_action("stand")
	show_frame()
	queue_redraw()

func show_frame() -> void:
	if clips.is_empty():
		return
	var clip: Dictionary = clips[state]
	var cursor := elapsed * 1000.0
	action_frame = clip["frames"].size() - 1
	for i in range(clip["frames"].size()):
		cursor -= float(clip["frames"][i]["duration_ms"])
		if cursor < 0:
			action_frame = i
			break
	body.texture = textures[state][action_frame][0]
	glow.texture = textures[state][action_frame][1]
	var pivot := Vector2(float(clip["pivot"][0]), float(clip["pivot"][1]))
	var offset := Vector2(384,384) - pivot
	body.position = offset
	glow.position = offset
	visual.scale = Vector2(visual_scale * facing, visual_scale) * float(clip.get("scale", 1.0))
	body.modulate = Color(1.0,0.55,0.55) if flash > 0 else Color.WHITE

func _draw() -> void:
	if state == "cast" and not fired and elapsed > 0.18:
		var pulse := sin(elapsed * 15.0) * 3.0
		draw_arc(Vector2(40 * facing,-190), 17 + pulse, 0, TAU, 40, Color(0.4,0.8,1.0,0.7), 2.0)
