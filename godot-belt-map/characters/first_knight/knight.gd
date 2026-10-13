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
const LIGHTNING_SKILL_ID := "skill.knight.lightning"
const LIGHTNING_FALLBACK := {
	"id": LIGHTNING_SKILL_ID, "display_name": "雷光",
	"description": "向前释放雷光，命中后可在邻近目标之间弹射。",
	"action_profile_id": "action.knight.cast",
	"resource_cost": {"type":"mp", "amount":25.0}, "cooldown_seconds":2.4,
	"combat": {"base_damage":42.0, "depth_radius":0.65, "chain_count":1, "chain_radius_m":3.2,
		"tags":["magic", "lightning", "projectile"]},
	"presentation": {"vfx_id":"vfx.knight.lightning_projectile", "sfx_id":"sfx.knight.lightning_cast"}
}
const SKILLS := {
 "crescent": {"name":"月弧斩", "description":"前方宽弧斩击", "cost":18.0, "cooldown":4.0, "depth_radius":0.95},
 "rising": {"name":"破晓升龙", "description":"上挑并击飞前方目标", "cost":24.0, "cooldown":6.0, "depth_radius":0.70},
 "trinity": {"name":"幻影三连", "description":"连续三次斩击，末击更强", "cost":32.0, "cooldown":9.0, "depth_radius":0.75}
}
var skill_cooldowns := {"crescent":0.0, "rising":0.0, "trinity":0.0}
var running := false
var special_phase := 0
var air_attack_landed := false
var air_attack_recovery := 0.0
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
var progression_bonuses: Dictionary = {}
var run_bonuses: Dictionary = {}
## Tests and editor tools can inject a registry without adding the actor to a tree.
var content_registry_override: Node = null
## The map owns height/gravity. These values select an independent visual pose.
var airborne := false
var air_vertical_speed := 0.0
var air_elapsed := 0.0
var landing_remaining := 0.0
var air_launch_speed := 6.36
var jump_phase := "ground"
var jump_clip: Dictionary = {}
var jump_textures: Array = []

func set_airborne(active: bool, vertical_speed: float) -> void:
	if active and not airborne:
		air_elapsed = 0.0
		landing_remaining = 0.0
		air_launch_speed = maxf(absf(vertical_speed), 1.0)
	elif not active and airborne:
		landing_remaining = 0.18
	airborne = active
	air_vertical_speed = vertical_speed
	jump_phase = "rise" if airborne and vertical_speed > 1.0 else ("fall" if airborne and vertical_speed < -1.0 else ("apex" if airborne else ("land" if landing_remaining > 0.0 else "ground")))

func refresh_equipment() -> void:
	var bonus: Dictionary = equipment.bonuses()
	for source in [progression_bonuses, run_bonuses]:
		for key in source:
			if bonus.has(key): bonus[key] += float(source[key])
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

func get_lightning_skill() -> Dictionary:
	var registry := content_registry_override
	if registry == null:
		registry = get_node_or_null("/root/ContentRegistry")
	if registry != null:
		var definition: Dictionary = registry.get_skill(LIGHTNING_SKILL_ID)
		if not definition.is_empty():
			return definition
	return LIGHTNING_FALLBACK.duplicate(true)

func get_spell_mana_cost() -> float:
	return float(get_lightning_skill().get("resource_cost", {}).get("amount", 25.0))

func get_spell_cooldown() -> float:
	return float(get_lightning_skill().get("cooldown_seconds", 2.4))

func get_spell_damage() -> float:
	return float(get_lightning_skill().get("combat", {}).get("base_damage", 42.0)) + magic_bonus

func get_attack_reach(action: String) -> float:
	return (float(clips[action].get("range", 180)) + melee_reach_margin) * visual_scale / 0.62

func set_movement_axis(axis: float) -> void:
	movement_axis = clampf(axis, -1.0, 1.0)

func _ready() -> void:
	equipment.changed.connect(refresh_equipment)
	if "--combat-test" in OS.get_cmdline_user_args() or "--smoke-test" in OS.get_cmdline_user_args() or "--equipment-test" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args() or "--capture-equipment" in OS.get_cmdline_user_args():
		equipment.persistence_enabled = false
	equipment.load_loadout()
	refresh_equipment()
	health = max_health
	mana = max_mana
	var asset_root: String = get_script().resource_path.get_base_dir() + "/assets/"
	clips = JSON.parse_string(FileAccess.get_file_as_string(asset_root + "animations.json"))
	if FileAccess.file_exists(asset_root + "jump.json"):
		jump_clip = JSON.parse_string(FileAccess.get_file_as_string(asset_root + "jump.json"))
		for frame in jump_clip["frames"]:
			jump_textures.append(load(asset_root + str(frame["file"])))
	_register_combat_clips(asset_root)
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
	special_phase = 0
	if next == "cast":
		mana -= get_spell_mana_cost()
		cast_cooldown = get_spell_cooldown()
		stats_changed.emit(health, mana)
	action_changed.emit(state)

func request_attack() -> void:
	if defeated or airborne:
		return
	if state.begins_with("attack"):
		# A fresh press during the latter part of a swing queues one next strike.
		if elapsed >= 0.15:
			combo_buffered = true
	elif is_locomotion():
		combo_buffered = false
		change_action("attack1")
	inactivity = 0.0

func request_cast() -> void:
	if defeated or mana < get_spell_mana_cost() or cast_cooldown > 0.0:
		return
	if is_locomotion():
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
	airborne = false
	running = false
	air_attack_landed = false
	air_attack_recovery = 0.0
	air_elapsed = 0.0
	air_vertical_speed = 0.0
	inactivity = 0.0
	flash = 0.0
	movement_axis = 0.0
	velocity = Vector2.ZERO
	for id in skill_cooldowns:
		skill_cooldowns[id] = 0.0
	landing_remaining = 0.0
	jump_phase = "ground"
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
	if airborne:
		air_elapsed += delta
	else:
		landing_remaining = maxf(0.0, landing_remaining - delta)
	cast_cooldown = maxf(0.0, cast_cooldown - delta)
	for id in skill_cooldowns:
		skill_cooldowns[id] = maxf(0.0, float(skill_cooldowns[id]) - delta)
	flash = maxf(0.0, flash - delta)
	if not defeated:
		mana = minf(max_mana, mana + mana_regen * delta)
	var movement := 0.0
	if input_enabled and not defeated:
		movement = movement_axis
		if use_local_input:
			movement = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	velocity = Vector2.ZERO
	if is_locomotion() and not defeated:
		if movement != 0:
			facing = 1 if movement > 0 else -1
			velocity.x = movement * (move_speed + equipment_speed_bonus) * (1.8 if running and not airborne else 1.0)
			inactivity = 0.0
			var desired := "run" if running and not airborne else "walk"
			if state != desired:
				change_action(desired)
		else:
			inactivity += delta
			if state in ["walk", "run"]:
				change_action("stand")
			if state == "stand" and inactivity >= 4.0:
				change_action("idle")
				inactivity = 0.0
	if use_local_input:
		move_and_slide()
	elapsed += delta
	if _step_special(delta):
		show_frame()
		queue_redraw()
		return
	var clip: Dictionary = clips[state]
	if clip.has("event_ms") and not fired and elapsed * 1000.0 >= float(clip["event_ms"]):
		fired = true
		if state.begins_with("attack"):
			attack_hitbox.emit({"origin":global_position,"facing":facing,"range":get_attack_reach(state),"damage":get_attack_damage(state),"action":state})
		elif state == "cast":
			var release: Array = clip.get("release_offset",[165,-330])
			var offset := Vector2(float(release[0])*facing,float(release[1]))*visual_scale*float(clip.get("scale",1.0))
			var definition := get_lightning_skill()
			var combat: Dictionary = definition.get("combat", {})
			spell_requested.emit({"origin":global_position + offset, "facing":facing, "damage":get_spell_damage(),
				"skill_id":str(definition.get("id", LIGHTNING_SKILL_ID)),
				"depth_radius":float(combat.get("depth_radius", 0.65)),
				"chain_count":int(combat.get("chain_count", 1)),
				"chain_radius_m":float(combat.get("chain_radius_m", 0.0)),
				"vfx_id":str(definition.get("presentation", {}).get("vfx_id", "")),
				"sfx_id":str(definition.get("presentation", {}).get("sfx_id", ""))})
	var duration := float(clip["duration_ms"]) / 1000.0
	if elapsed >= duration:
		if defeated:
			elapsed = duration - 0.001
		elif state in ["stand", "walk", "run"]:
			elapsed = fmod(elapsed, duration)
		elif state.begins_with("attack") and combo_buffered:
			combo_buffered = false
			change_action("attack2" if state == "attack1" else ("attack3" if state == "attack2" else "attack1"))
		elif state.begins_with("attack") and cast_buffered and mana >= get_spell_mana_cost() and cast_cooldown <= 0:
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
	var frame_pivot: Array = clip["frames"][action_frame].get("pivot", clip["pivot"])
	var pivot := Vector2(float(frame_pivot[0]), float(frame_pivot[1]))
	var offset := Vector2(384,384) - pivot
	body.position = offset
	glow.position = offset
	visual.scale = Vector2(visual_scale * facing, visual_scale) * float(clip.get("scale", 1.0))
	body.modulate = Color(1.0,0.55,0.55) if flash > 0 else Color.WHITE
	# Full-body jump frames only replace locomotion. Air attacks, casting and hurt
	# keep their own animation/events instead of being interrupted by a pose.
	if not jump_textures.is_empty() and is_locomotion() and (airborne or landing_remaining > 0.0):
		_show_jump_frame()

func _show_jump_frame() -> void:
	var sequence: Array
	var fraction := 0.0
	if not airborne:
		sequence = jump_clip["land"]
		fraction = 1.0 - landing_remaining / 0.18
	elif air_elapsed < 0.10:
		sequence = jump_clip["takeoff"]
		fraction = air_elapsed / 0.10
	elif air_vertical_speed > 1.0:
		sequence = jump_clip["rise"]
		fraction = clampf(1.0 - air_vertical_speed / air_launch_speed, 0.0, 1.0)
	elif air_vertical_speed >= -1.0:
		sequence = jump_clip["apex"]
		fraction = clampf((1.0 - air_vertical_speed) / 2.0, 0.0, 1.0)
	else:
		sequence = jump_clip["fall"]
		fraction = clampf((-air_vertical_speed - 1.0) / maxf(1.0, air_launch_speed - 1.0), 0.0, 1.0)
	var index := int(sequence[mini(int(fraction * sequence.size()), sequence.size() - 1)])
	var frame: Dictionary = jump_clip["frames"][index]
	body.texture = jump_textures[index]
	glow.texture = null
	var pivot: Array = frame.get("pivot", jump_clip["pivot"])
	body.position = Vector2(384, 384) - Vector2(float(pivot[0]), float(pivot[1]))
	glow.position = body.position
	visual.scale = Vector2(visual_scale * facing, visual_scale) * float(jump_clip.get("scale", 1.0))

func _draw() -> void:
	if state == "cast" and not fired and elapsed > 0.18:
		var pulse := sin(elapsed * 15.0) * 3.0
		draw_arc(Vector2(40 * facing,-190), 17 + pulse, 0, TAU, 40, Color(0.4,0.8,1.0,0.7), 2.0)

func is_locomotion() -> bool:
	return state in ["stand", "idle", "walk", "run"]

func set_running(active: bool) -> void:
	running = active

func request_dash_attack() -> bool:
	if defeated or airborne or not is_locomotion():
		return false
	combo_buffered = false
	cast_buffered = false
	change_action("dash_attack")
	return true

func request_air_attack() -> bool:
	if defeated or not airborne or not is_locomotion():
		return false
	combo_buffered = false
	cast_buffered = false
	air_attack_landed = false
	air_attack_recovery = 0.0
	change_action("air_slash")
	return true

func notify_air_attack_landed(valid: bool = true) -> void:
	if state != "air_slash" or air_attack_landed:
		return
	air_attack_landed = true
	if not valid:
		change_action("stand")
		return
	air_attack_recovery = 0.22
	elapsed = float(clips["air_slash"].get("landing_start_ms", 250.0)) / 1000.0
	fired = true
	_emit_special_hit(58.0, 190.0, "radial", "", 0)

func request_skill(id: String) -> bool:
	if not SKILLS.has(id) or defeated or airborne or not is_locomotion():
		return false
	var meta: Dictionary = SKILLS[id]
	if mana < float(meta["cost"]) or float(skill_cooldowns[id]) > 0.0:
		return false
	mana -= float(meta["cost"])
	skill_cooldowns[id] = float(meta["cooldown"])
	combo_buffered = false
	cast_buffered = false
	change_action("skill_" + id)
	stats_changed.emit(health, mana)
	return true

func _emit_special_hit(damage: float, reach: float, shape_name: String, skill: String, phase: int) -> void:
	attack_hitbox.emit({"origin":global_position, "facing":facing,
		"range":(reach + melee_reach_margin) * visual_scale / 0.62,
		"damage":damage + attack_bonus, "action":state, "skill":skill,
		"shape":shape_name, "phase":phase, "launch":skill == "rising",
		"depth_radius":1.2 if shape_name == "radial" else float(SKILLS.get(skill, {}).get("depth_radius", 0.6))})

func _step_special(delta: float) -> bool:
	if state == "air_slash":
		if air_attack_landed:
			air_attack_recovery -= delta
			var landing_start := float(clips["air_slash"].get("landing_start_ms", 250.0)) / 1000.0
			var animation_end := float(clips["air_slash"]["duration_ms"]) / 1000.0
			elapsed = lerpf(landing_start, animation_end, clampf(1.0 - air_attack_recovery / 0.22, 0.0, 1.0))
			if air_attack_recovery <= 0.0:
				change_action("stand")
		else:
			# Hold the downward pose until the map resolves an actual landing.
			elapsed = minf(elapsed, float(clips["air_slash"].get("hold_ms", 250.0)) / 1000.0)
		return true
	var schedule: Array = []
	var damages: Array = []
	var reach := 240.0
	var skill := ""
	var duration := 0.42
	if state == "dash_attack":
		schedule = [0.16]
		damages = [42.0]
	elif state.begins_with("skill_"):
		skill = state.trim_prefix("skill_")
		match skill:
			"crescent":
				schedule = [0.22]
				damages = [55.0]
				reach = 300.0
				duration = 0.56
			"rising":
				schedule = [0.24]
				damages = [65.0]
				reach = 230.0
				duration = 0.70
			"trinity":
				schedule = [0.18, 0.42, 0.70]
				damages = [24.0, 24.0, 48.0]
				reach = 265.0
				duration = 0.95
	else:
		return false
	while special_phase < schedule.size() and elapsed >= float(schedule[special_phase]):
		_emit_special_hit(float(damages[special_phase]), reach, "fan", skill, special_phase)
		special_phase += 1
	if elapsed >= duration:
		change_action("stand")
	return true

func _register_combat_clips(asset_root: String) -> void:
	var aliases := {"run":["walk",0.58], "dash_attack":["attack2",0.42],
		"air_slash":["attack1",0.40], "skill_crescent":["attack1",0.56],
		"skill_rising":["attack3",0.70], "skill_trinity":["attack1",0.95]}
	for key in aliases:
		var source: Dictionary = clips[aliases[key][0]].duplicate(true)
		var factor := float(aliases[key][1]) * 1000.0 / float(source["duration_ms"])
		for frame in source["frames"]:
			frame["duration_ms"] = float(frame["duration_ms"]) * factor
		source["duration_ms"] = float(aliases[key][1]) * 1000.0
		source.erase("event_ms")
		clips[key] = source
	# Reordered authored full-body swings give each trinity hit a whole pose.
	var tri: Dictionary = clips["skill_trinity"]
	tri["frames"] = []
	for source_name in ["attack1", "attack2", "attack3"]:
		var src: Dictionary = clips[source_name]
		var factor := (950.0 / 3.0) / float(src["duration_ms"])
		for frame in src["frames"]:
			var copy: Dictionary = frame.duplicate(true)
			copy["duration_ms"] = float(copy["duration_ms"]) * factor
			tri["frames"].append(copy)
	if FileAccess.file_exists(asset_root + "combat-motion.json"):
		var authored = JSON.parse_string(FileAccess.get_file_as_string(asset_root + "combat-motion.json"))
		if authored is Dictionary:
			if authored.has("clips"):
				authored = authored["clips"]
			for key in authored:
				var target: String = "air_slash" if key == "air_attack" else str(key)
				if key == "air_slash" or key == "run" or key == "dash_attack" or key == "air_attack":
					if authored[key] is Dictionary and authored[key].has("frames"):
						clips[target] = authored[key]
