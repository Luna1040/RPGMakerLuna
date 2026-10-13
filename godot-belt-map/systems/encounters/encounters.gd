extends Node2D
## Explicitly stepped combat service. Logical feet/depth/z stay independent of artwork.
## No gameplay timer or tween runs while the map is paused by an inventory/modal.
signal enemy_defeated(data: Dictionary)
signal wave_cleared(wave: int)
signal notice(text: String)
signal companion_changed(status: Dictionary)

const Physics = preload("res://belt_physics.gd")
const Query = preload("res://combat_query.gd")
const Reactions = preload("res://dummy_reactions.gd")
const EnemyArt = preload("enemy_art.gd")
const CompanionArt = preload("roster_actor_view.gd")
const ARENA := Rect2(18.65,2.5,5.65,6.2)
const DEFINITIONS := {
	# Scout source64: steel tip x727, pivot334, scale0.504237 => 1.651 m.
	# Keep about 12 screen pixels beyond that visible tip, shared by warning/damage.
	"melee":{"hp":74.0,"speed":1.3,"damage":9.0,"range":1.75,"windup":0.6,"cooldown":1.35,"label":"灰誓斥候"},
	"ranged":{"hp":58.0,"speed":0.95,"damage":8.0,"range":5.2,"windup":0.9,"cooldown":2.1,"label":"灰誓咒术师"},
	"elite":{"hp":145.0,"speed":1.1,"damage":13.0,"range":2.4,"windup":0.8,"cooldown":1.65,"label":"灰誓重卫"},
	"boss":{"hp":360.0,"speed":0.9,"damage":18.0,"range":2.2,"windup":1.1,"cooldown":2.0,"label":"陨星执政官"}
}
var stage
var enemies: Array[Dictionary] = []
var hostile_projectiles: Array[Dictionary] = []
var floating_numbers: Array[Dictionary] = []
var wave := 0
var active := false
var cleared := false
var run_seed := 1
var rng := RandomNumberGenerator.new()
var companion_mode := "follow"
var companion_enabled := false
var companion_foot := Vector2.ZERO
var companion_guard := Vector2.ZERO
var companion_cooldown := 0.0
var companion_action := "stand"
var companion_elapsed := 0.0
var companion_facing := 1
var companion_hits := 0
var companion_target_id := ""
var companion_hit_fired := false
const COMPANION_MAX_HP := 140.0
const COMPANION_MAX_MP := 80.0
var companion_hp := COMPANION_MAX_HP
var companion_mp := COMPANION_MAX_MP
var companion_dead := false
var companion_shield := 0.0
var companion_shield_left := 0.0
var companion_heal_cooldown := 0.0
var companion_ward_cooldown := 0.0
var companion_hurt_left := 0.0
var companion_invuln_left := 0.0
var companion_cast := ""
var companion_heal_target := ""
var companion_projectiles: Array[Dictionary] = []
var companion_effects: Array[Dictionary] = []
var companion_view: Node2D
var companion_root := Node2D.new()
var companion_sprite := Sprite2D.new()
var companion_label := Label.new()
var companion_path: Array[Vector2] = []
var companion_path_timer := 0.0
var _serial := 0
var _clock := 0.0
var _spell_clips: Dictionary = {}

func setup(map_stage) -> void:
	stage = map_stage
	z_index = 1
	companion_foot = _free_point(stage.foot + Vector2(-0.8,0.5))
	companion_guard = companion_foot
	stage.sorting.add_child(companion_root)
	companion_root.name = "CompanionSerin"
	companion_root.add_child(companion_sprite)
	companion_root.add_child(companion_label)
	companion_label.text = "瑟琳 · 战牧"
	companion_label.position = Vector2(-60,-260)
	companion_label.add_theme_font_size_override("font_size",15)
	companion_label.add_theme_color_override("font_color",Color("8ce8eb"))
	companion_label.add_theme_color_override("font_shadow_color",Color("12242e"))
	companion_label.add_theme_constant_override("shadow_offset_x",2)
	companion_label.add_theme_constant_override("shadow_offset_y",2)
	companion_sprite.modulate = Color.WHITE
	replace_companion_view(CompanionArt.new())
	_update_companion_view()
	companion_root.visible = companion_enabled

func set_companion_enabled(enabled: bool) -> void:
	companion_enabled = enabled
	companion_root.visible = enabled
	companion_target_id = ""
	companion_cast = ""
	if not enabled:
		companion_projectiles.clear()
	_change_companion_action("dead" if companion_dead else "stand")
	if enabled and stage != null:
		companion_foot = _free_point(stage.foot + Vector2(-0.8,0.55))
		companion_guard = companion_foot
		companion_path.clear()
		companion_cooldown = maxf(0.25,companion_cooldown)
		_update_companion_view()
	companion_changed.emit(companion_status())

func begin_wave(number: int, seed_value: int = 1) -> bool:
	if stage == null or number < 1 or number > 3 or active:
		return false
	_clear_enemies()
	wave = number
	run_seed = seed_value
	rng.seed = seed_value + number * 104729
	active = true
	cleared = false
	var roster: Array = {1:["melee","melee","ranged"],2:["elite","melee","ranged","melee"],3:["boss","ranged","melee"]}[wave]
	var points := [Vector2(22.0,4.2),Vector2(23.3,7.9),Vector2(23.2,3.0),Vector2(21.6,8.0)]
	if "contract" in stage and stage.contract.has("encounter_points"):
		points=[]
		for point in stage.contract.encounter_points: points.append(Vector2(point[0],point[1]))
	for i in roster.size():
		var p: Vector2 = points[i] + Vector2(rng.randf_range(-0.15,0.15),rng.randf_range(-0.15,0.15))
		_spawn(str(roster[i]),_free_point(p))
	notice.emit("东庭试炼 · 第 %d / 3 波，红圈出现后闪避或跳跃。" % wave)
	queue_redraw()
	return true

func _spawn(kind: String, p: Vector2, stable_id: String = "") -> Dictionary:
	var definition: Dictionary = DEFINITIONS[kind]
	_serial += 1
	var enemy := {"id":stable_id if not stable_id.is_empty() else "wave%d-%s-%d" % [wave,kind,_serial],
		"kind":kind,"label":definition.label,"foot":p,"home":p,"hp":definition.hp,"max_hp":definition.hp,
		"state":"idle","timer":rng.randf_range(0.1,0.55),"cooldown":0.0,"facing":-1.0,
		"clock":0.0,"flash":0.0,"reaction":Reactions.new(),"art":EnemyArt.new(),
		"hurt_left":0.0,"hurt_elapsed":0.0,"death_elapsed":0.0,"attack_active":false,"attack_elapsed":0.0,
		"attack_windup":float(definition.windup),"attack_recovery":0.86 if kind == "boss" else 0.54,
		"aim":p,"attack_origin":p,"attack_facing":-1.0,"attack_variant":"melee","rewarded":false,
		"path":[],"path_timer":0.0,"attacks":0,"target_id":"player","reward_gold":rng.randi_range(7,12) + (25 if kind == "boss" else 0),
		"reward_xp":45 if kind == "boss" else (18 if kind == "elite" else 10),"drop_roll":rng.randf()}
	enemy.art.data = enemy
	enemy.art.position = stage.project(p)
	stage.sorting.add_child(enemy.art)
	enemies.append(enemy)
	return enemy

func clear() -> void:
	_clear_enemies()
	wave = 0
	cleared = false
	queue_redraw()

func _clear_enemies() -> void:
	for enemy: Dictionary in enemies:
		if is_instance_valid(enemy.art):
			enemy.art.queue_free()
	enemies.clear()
	hostile_projectiles.clear()
	companion_projectiles.clear()
	companion_effects.clear()
	floating_numbers.clear()
	active = false
	_serial = 0

func set_companion(mode: String) -> void:
	if mode not in ["follow","guard","passive"]:
		return
	companion_mode = mode
	companion_target_id = ""
	companion_cast = ""
	_change_companion_action("dead" if companion_dead else "stand")
	companion_guard = companion_foot
	companion_path.clear()
	companion_cooldown = maxf(companion_cooldown,0.25)
	companion_label.text = "瑟琳 · 战牧 / " + {"follow":"跟随","guard":"守卫","passive":"被动"}[mode]
	notice.emit({"follow":"队友：跟随并协助攻击。","guard":"队友：守卫当前位置。","passive":"队友：跟随，不主动攻击。"}[mode])

func step(delta: float) -> void:
	if stage == null or delta <= 0.0:
		return
	# A bounded accumulator prevents tunnelling during a slow frame and remains deterministic.
	var remaining := minf(delta,1.0)
	while remaining > 0.000001:
		var dt := minf(remaining,1.0/60.0)
		remaining -= dt
		_step_fixed(dt)
	for enemy: Dictionary in enemies:
		if is_instance_valid(enemy.art):
			enemy.art.position = stage.project(enemy.foot)
			enemy.art.queue_redraw()
	_update_companion_view()
	queue_redraw()

func _step_fixed(dt: float) -> void:
	_clock += dt
	for effect: Dictionary in companion_effects.duplicate():
		effect.life -= dt
		if effect.life <= 0.0:
			companion_effects.erase(effect)
	for number: Dictionary in floating_numbers.duplicate():
		number.life -= dt
		if number.life <= 0.0:
			floating_numbers.erase(number)
	if stage.knight.defeated:
		hostile_projectiles.clear()
		return
	for enemy: Dictionary in enemies:
		if enemy.state == "dead":
			enemy.death_elapsed += dt
			continue
		enemy.clock += dt
		enemy.hurt_elapsed += dt
		enemy.hurt_left = maxf(0.0,enemy.hurt_left-dt)
		if enemy.attack_active:
			enemy.attack_elapsed += dt
		enemy.flash = maxf(0,enemy.flash-dt)
		enemy.cooldown = maxf(0,enemy.cooldown-dt)
		enemy.path_timer = maxf(0,enemy.path_timer-dt)
		var dot: float = enemy.reaction.step(dt)
		if dot > 0.0:
			_damage(enemy,dot,"shock",false)
		if enemy.state == "dead":
			continue
		if enemy.reaction.stun_left > 0.0 or enemy.reaction.airborne():
			continue
		_step_enemy(enemy,dt)
	_step_projectiles(dt)
	_step_companion(dt)
	_step_companion_projectiles(dt)
	_check_cleared()

func _combat_bounds() -> Rect2:
	# Dedicated dungeon maps use their own playable area. The old courtyard
	# arena remains only for the legacy mixed town/combat prototype.
	if "contract" in stage and stage.contract.get("zone_id", "town") in ["ruins", "forest"]:
		return stage.bounds
	return ARENA.grow(1.2)

func _step_enemy(enemy: Dictionary, dt: float) -> void:
	var stats: Dictionary = DEFINITIONS[enemy.kind]
	var target_id := _choose_enemy_target(enemy)
	enemy.target_id = target_id
	var target: Vector2 = companion_foot if target_id == "serin" else stage.foot
	var target_height: float = 0.0 if target_id == "serin" else stage.height_z
	var offset: Vector2 = target - enemy.foot
	var distance := offset.length()
	var dedicated_dungeon: bool = "contract" in stage and stage.contract.get("zone_id", "town") in ["ruins", "forest"]
	if not _combat_bounds().has_point(target) or (not dedicated_dungeon and enemy.foot.distance_to(enemy.home) > 7.5):
		if enemy.state != "return":
			enemy.state = "return"
			enemy.attack_active = false
			enemy.path.clear()
	if enemy.state == "return":
		_move_enemy(enemy,enemy.home,dt,float(stats.speed)*1.3)
		if enemy.foot.distance_to(enemy.home) < 0.15:
			enemy.state = "idle"
			enemy.timer = 0.5
		return
	if enemy.state == "idle":
		enemy.timer -= dt
		if (dedicated_dungeon or distance < 6.4) and enemy.timer <= 0.0 and _combat_bounds().has_point(target):
			enemy.state = "chase"
		return
	if enemy.state == "recover":
		enemy.timer -= dt
		if enemy.timer <= 0.0:
			enemy.state = "chase"
			enemy.attack_active = false
		return
	if enemy.state == "telegraph":
		enemy.timer -= dt
		if enemy.timer <= 0.0:
			enemy.state = "attack"
			enemy.timer = 0.16
			enemy.attack_elapsed = float(stats.windup)
			_resolve_attack(enemy)
		return
	if enemy.state == "attack":
		enemy.timer -= dt
		if enemy.timer <= 0.0:
			enemy.state = "recover"
			enemy.timer = 0.38 if enemy.kind != "boss" else 0.7
		return
	if absf(offset.x) > 0.12:
		enemy.facing = signf(offset.x)
	var can_attack := distance < float(stats.range) + 0.35 and absf(offset.y) < 2.0
	if enemy.kind != "ranged":
		# Reuse the actual strike/target geometry. A larger centre-distance
		# threshold can make AI stop outside reach and swing forever at a
		# stationary party member instead of taking the last step forward.
		var target_half := Vector2(0.2,0.2) if target_id == "serin" else Vector2(0.18,0.18)
		var strike := {"facing":enemy.facing,"range":float(stats.range)*120.0,"depth_radius":0.57}
		can_attack = absf(offset.y) < 0.65 and Query.overlaps(enemy.foot,0.0,Rect2(target-target_half,target_half*2),target_height,1.7,strike)
	can_attack = can_attack and target_height < 1.55 and _line_clear(enemy.foot,target,0.4)
	if can_attack and enemy.cooldown <= 0.0:
		enemy.state = "telegraph"
		enemy.attack_active = true
		enemy.attack_elapsed = 0.0
		enemy.timer = stats.windup
		enemy.aim = target
		enemy.target_id = target_id
		enemy.attack_origin = enemy.foot
		enemy.attack_facing = enemy.facing
		enemy.attack_variant = "ranged" if enemy.kind == "ranged" else ("slam" if enemy.kind == "boss" and int(enemy.attacks)%2 == 0 else "melee")
		enemy.attacks += 1
	elif not can_attack:
		var stand_off := 3.0 if enemy.kind == "ranged" else 0.8
		# When the player crosses our X axis, align depth first instead of
		# chasing alternating left/right offsets through the player.
		var desired := Vector2(enemy.foot.x,target.y) if absf(offset.x) <= stand_off else target - Vector2(enemy.facing * stand_off,0)
		_move_enemy(enemy,desired,dt,float(stats.speed))

func _resolve_attack(enemy: Dictionary) -> void:
	var stats: Dictionary = DEFINITIONS[enemy.kind]
	enemy.cooldown = stats.cooldown
	if enemy.attack_variant == "ranged":
		var socket := _projectile_socket("caster",enemy.foot,enemy.attack_facing,0.72)
		var direction: Vector2 = _projectile_direction(enemy.foot,socket.foot,enemy.aim)
		hostile_projectiles.append({"foot":socket.foot,"launch_from":enemy.foot,"velocity":direction*4.1,"z":socket.z,"damage":stats.damage,"life":2.2,"owner":enemy.id})
		return
	var event := {"facing":enemy.attack_facing,"range":float(stats.range)*120.0,"depth_radius":0.57}
	var origin: Vector2 = enemy.attack_origin
	if enemy.attack_variant == "slam":
		origin = enemy.aim
		event = {"shape":"radial","range":1.4*120.0,"depth_radius":0.9}
	var rect := Rect2(stage.foot-Vector2(0.18,0.18),Vector2(0.36,0.36))
	# All enemy melee swings stay below a jumping character's feet above 0.9 m.
	if stage.height_z <= 0.9 and Query.overlaps(origin,0.0,rect,stage.height_z,1.7,event) and _line_clear(enemy.foot,stage.foot,0.35):
		stage.knight.apply_damage(float(stats.damage),stage.project(enemy.foot))
	# A telegraph is a real area attack. Both party members can be hit; its
	# locked aim never teleports to a new target when either one moves away.
	if companion_enabled and not companion_dead:
		var ally_rect := Rect2(companion_foot-Vector2(0.2,0.2),Vector2(0.4,0.4))
		if Query.overlaps(origin,0.0,ally_rect,0.0,1.7,event) and _line_clear(enemy.foot,companion_foot,0.35):
			damage_companion(float(stats.damage),enemy.foot)

func _choose_enemy_target(enemy: Dictionary) -> String:
	if not companion_enabled or companion_dead or not _combat_bounds().has_point(companion_foot):
		return "player"
	if not _combat_bounds().has_point(stage.foot):
		return "serin"
	var hero_distance: float = enemy.foot.distance_to(stage.foot)
	var ally_distance: float = enemy.foot.distance_to(companion_foot)
	# Small hysteresis keeps a pursuer from oscillating between equal targets.
	if str(enemy.get("target_id","player")) == "serin" and ally_distance <= hero_distance+0.65:
		return "serin"
	return "serin" if ally_distance+0.35 < hero_distance else "player"

func _projectile_socket(id: String, foot: Vector2, facing: float, default_height: float) -> Dictionary:
	# Emitters are authored on the untrimmed frame at event_ms. Texture storage
	# crops cannot change this geometry, and the view never triggers damage.
	if not _spell_clips.has(id):
		_spell_clips[id] = {}
		var path := "res://assets/roster/"+id+"/animation.json"
		if id in ["caster","serin"] and FileAccess.file_exists(path):
			var decoded = JSON.parse_string(FileAccess.get_file_as_string(path))
			if decoded is Dictionary and decoded.get("actions") is Dictionary:
				_spell_clips[id] = decoded.actions.get("attack",{})
	var clip: Dictionary = _spell_clips[id]
	if not _valid_point(clip.get("emitter")) or not _valid_point(clip.get("pivot")) or not _valid_number(clip.get("scale")):
		return {"foot":foot,"z":default_height}
	var scale_factor := float(clip.scale)
	if scale_factor <= 0.0 or scale_factor > 4.0:
		return {"foot":foot,"z":default_height}
	var offset := (Vector2(clip.emitter[0],clip.emitter[1])-Vector2(clip.pivot[0],clip.pivot[1]))*scale_factor
	var unit_x: float = stage.project(Vector2(1,0)).x-stage.project(Vector2.ZERO).x
	var unit_z: float = stage.project(Vector2.ZERO).y-stage.project(Vector2.ZERO,1.0).y
	if unit_x <= 0.0 or unit_z <= 0.0:
		return {"foot":foot,"z":default_height}
	return {"foot":foot+Vector2(offset.x*signf(facing)/unit_x,0),"z":clampf(-offset.y/unit_z,0.05,3.0)}

func _projectile_direction(origin: Vector2, muzzle: Vector2, target: Vector2) -> Vector2:
	var direction := origin.direction_to(target)
	# A target already inside the hand/staff reach is hit by the launch sweep;
	# do not turn a point-blank bolt backwards merely because the tip passed it.
	if (target-muzzle).dot(direction) > 0.0:
		return muzzle.direction_to(target)
	return direction if not direction.is_zero_approx() else Vector2.RIGHT

func _step_projectiles(dt: float) -> void:
	for projectile: Dictionary in hostile_projectiles.duplicate():
		var before: Vector2 = projectile.get("launch_from",projectile.foot)
		var after: Vector2 = projectile.foot + projectile.velocity * dt
		projectile.erase("launch_from")
		projectile.life -= dt
		if projectile.life <= 0.0 or not stage.bounds.has_point(after) or not _line_clear(before,after,float(projectile.z)):
			hostile_projectiles.erase(projectile)
			continue
		projectile.foot = after
		var victim := ""
		var nearest := INF
		for target_id in ["player","serin"]:
			if target_id == "serin" and (not companion_enabled or companion_dead):
				continue
			var target: Vector2 = stage.foot if target_id == "player" else companion_foot
			var height: float = stage.height_z if target_id == "player" else 0.0
			var closest := Geometry2D.get_closest_point_to_segment(target,before,after)
			if absf(closest.x-target.x) <= 0.27 and absf(closest.y-target.y) <= 0.33 and float(projectile.z) >= height and float(projectile.z) <= height+1.7:
				var distance := before.distance_squared_to(closest)
				if distance < nearest:
					nearest = distance
					victim = target_id
		if not victim.is_empty():
			if victim == "player":
				stage.knight.apply_damage(float(projectile.damage),stage.project(before))
			else:
				damage_companion(float(projectile.damage),before)
			hostile_projectiles.erase(projectile)

func hit(source: Vector2, z: float, event: Dictionary) -> int:
	var count := 0
	if float(event.get("damage",0.0)) <= 0.0:
		return 0
	for enemy: Dictionary in enemies:
		if enemy.state == "dead":
			continue
		var half := Vector2(0.30,0.25) if enemy.kind == "boss" else Vector2(0.23,0.22)
		if Query.overlaps(source,z,Rect2(enemy.foot-half,half*2),enemy.reaction.height/120.0,1.5,event) and _line_clear(source,enemy.foot,maxf(z,0.45)):
			_apply_hit(enemy,event)
			count += 1
	_check_cleared()
	return count

func hit_projectile(from_x: float, to_x: float, depth: float, z: float, damage: float) -> bool:
	if damage <= 0.0:
		return false
	var nearest: Dictionary = {}
	var best := INF
	for enemy: Dictionary in enemies:
		if enemy.state == "dead" or absf(depth-enemy.foot.y) > 0.55:
			continue
		var bottom: float = enemy.reaction.height/120.0
		# The authored knight's hand releases its bolt at 1.666 m. Include the
		# same forgiving upper margin as practice targets, so grounded enemies
		# can be hit by the real cast animation as well as low test projectiles.
		if z < bottom-0.15 or z > bottom+1.9:
			continue
		if maxf(from_x,to_x) < enemy.foot.x-0.28 or minf(from_x,to_x) > enemy.foot.x+0.28:
			continue
		var distance := absf(float(enemy.foot.x)-from_x)
		if distance < best and _line_clear(Vector2(from_x,depth),enemy.foot,z):
			best = distance
			nearest = enemy
	if nearest.is_empty():
		# True means the projectile was consumed, including a wall impact.
		# Merely rejecting damage for this segment would let the next frame
		# start beyond the wall and hit an enemy from the other side.
		return not _line_clear(Vector2(from_x,depth),Vector2(to_x,depth),z)
	_apply_hit(nearest,{"action":"magic","damage":damage})
	_check_cleared()
	return true

func _apply_hit(enemy: Dictionary, event: Dictionary) -> void:
	var action := str(event.get("action","attack1"))
	if event.get("launch",false):
		action = "attack3"
	var reaction: Dictionary = enemy.reaction.hit(action)
	# Taking a hit cancels the currently telegraphed strike, including its stored target.
	enemy.state = "recover"
	enemy.timer = 0.32
	enemy.attack_active = false
	enemy.hurt_left = 0.4
	enemy.hurt_elapsed = 0.0
	_damage(enemy,float(event.get("damage",0.0))+float(reaction.bonus),"air" if reaction.air_hit else "hit",true)

func _damage(enemy: Dictionary, amount: float, source: String, show_number: bool) -> void:
	if enemy.state == "dead" or enemy.hp <= 0.0:
		return
	enemy.hp = maxf(0.0,enemy.hp-amount)
	enemy.flash = 0.13
	if show_number or source == "shock":
		floating_numbers.append({"foot":enemy.foot,"height":enemy.reaction.height,"amount":int(ceil(amount)),"life":0.7,"source":source})
	if enemy.hp <= 0.0:
		enemy.state = "dead"
		enemy.attack_active = false
		enemy.death_elapsed = 0.0
		enemy.art.show()
		if not enemy.rewarded:
			enemy.rewarded = true
			var drops: Array = []
			if enemy.kind == "boss":
				drops.append({"id":"arcane_sword","count":1})
			enemy_defeated.emit({"id":enemy.id,"kind":enemy.kind,"wave":wave,"foot":[enemy.foot.x,enemy.foot.y],"gold":enemy.reward_gold,"xp":enemy.reward_xp,"drops":drops})

func _check_cleared() -> void:
	if not active or cleared or enemies.is_empty():
		return
	for enemy: Dictionary in enemies:
		if enemy.state != "dead":
			return
	active = false
	cleared = true
	hostile_projectiles.clear()
	wave_cleared.emit(wave)

func _step_companion(dt: float) -> void:
	if not companion_enabled:
		return
	if companion_dead:
		_change_companion_action("dead")
		return
	companion_cooldown = maxf(0.0,companion_cooldown-dt)
	companion_heal_cooldown = maxf(0.0,companion_heal_cooldown-dt)
	companion_ward_cooldown = maxf(0.0,companion_ward_cooldown-dt)
	companion_hurt_left = maxf(0.0,companion_hurt_left-dt)
	companion_invuln_left = maxf(0.0,companion_invuln_left-dt)
	companion_shield_left = maxf(0.0,companion_shield_left-dt)
	if companion_shield_left <= 0.0:
		companion_shield = 0.0
	companion_mp = minf(COMPANION_MAX_MP,companion_mp+dt*(1.4 if active else 4.0))
	companion_elapsed += dt
	companion_path_timer = maxf(0.0,companion_path_timer-dt)
	if companion_hurt_left > 0.0:
		_change_companion_action("hit")
		return
	if companion_action in ["attack1","magic"] and companion_elapsed < 0.6:
		if companion_elapsed >= 0.24 and not companion_hit_fired:
			companion_hit_fired = true
			_resolve_companion_cast()
		return
	# Passive means follow without autonomous damage or support spells. It
	# remains vulnerable and never grants invulnerability by switching modes.
	if companion_mode != "passive":
		var heal_target := _companion_heal_candidate()
		if not heal_target.is_empty() and companion_mp >= 18.0 and companion_heal_cooldown <= 0.0:
			companion_mp -= 18.0
			companion_heal_cooldown = 8.0
			companion_heal_target = heal_target
			_start_companion_cast("heal","magic")
			return
		if active and companion_hp/COMPANION_MAX_HP < 0.72 and companion_mp >= 24.0 and companion_ward_cooldown <= 0.0 and companion_shield <= 0.0:
			companion_mp -= 24.0
			companion_ward_cooldown = 12.0
			_start_companion_cast("ward","magic")
			return
	var target: Dictionary = {}
	var nearest := 5.0
	if companion_mode != "passive" and active:
		for enemy: Dictionary in enemies:
			if enemy.state == "dead":
				continue
			if enemy.foot.distance_to(companion_guard if companion_mode == "guard" else stage.foot) > (3.2 if companion_mode == "guard" else 5.0):
				continue
			var distance: float = companion_foot.distance_to(enemy.foot)
			if distance < nearest:
				nearest = distance
				target = enemy
	var destination: Vector2 = companion_guard if companion_mode == "guard" else stage.foot+Vector2(-0.8*stage.knight.facing,0.55)
	if not target.is_empty():
		companion_facing = 1 if target.foot.x >= companion_foot.x else -1
		var in_range: bool = companion_foot.distance_to(target.foot) < 4.5 and absf(target.foot.y-companion_foot.y) < 1.5 and target.reaction.height < 160 and _line_clear(companion_foot,target.foot,0.8)
		if companion_mode != "guard" and not in_range:
			destination = target.foot - Vector2(companion_facing*2.8,0)
		elif in_range:
			destination = companion_foot
		if in_range and companion_cooldown <= 0.0:
			companion_cooldown = 1.6
			companion_target_id = target.id
			_start_companion_cast("bolt","attack1")
			return
	if companion_foot.distance_to(destination) > 0.28:
		var direction := _steering(companion_foot,destination,companion_path,companion_path_timer <= 0.0)
		if companion_path_timer <= 0.0:
			companion_path_timer = 0.65
		var before := companion_foot
		companion_foot = Physics.step_position(stage.volumes,stage.bounds,companion_foot,direction*2.45*dt,0.0,true)
		if absf(companion_foot.x-before.x) > 0.0001:
			companion_facing = 1 if companion_foot.x > before.x else -1
		_change_companion_action("walk" if before.distance_to(companion_foot)>0.001 else "stand")
	else:
		_change_companion_action("stand")

func _start_companion_cast(kind: String, action: String) -> void:
	companion_cast = kind
	companion_action = action
	companion_elapsed = 0.0
	companion_hit_fired = false

func _companion_heal_candidate() -> String:
	var self_ratio := companion_hp/COMPANION_MAX_HP
	var hero_ratio: float = stage.knight.health/maxf(1.0,stage.knight.max_health)
	var hero_in_range: bool = not stage.knight.defeated and companion_foot.distance_to(stage.foot) <= 4.8 and _line_clear(companion_foot,stage.foot,0.8)
	if hero_ratio < 0.55 and hero_in_range and hero_ratio <= self_ratio:
		return "player"
	return "serin" if self_ratio < 0.55 else ""

func _resolve_companion_cast() -> void:
	if companion_dead or companion_mode == "passive":
		return
	if companion_cast == "heal":
		if companion_heal_target == "player":
			if stage.knight.defeated or companion_foot.distance_to(stage.foot) > 4.8 or not _line_clear(companion_foot,stage.foot,0.8):
				return
			stage.knight.health = minf(stage.knight.max_health,stage.knight.health+40.0)
			stage.knight.stats_changed.emit(stage.knight.health,stage.knight.mana)
			companion_effects.append({"foot":stage.foot,"kind":"heal","life":0.75})
		else:
			companion_hp = minf(COMPANION_MAX_HP,companion_hp+40.0)
			companion_effects.append({"foot":companion_foot,"kind":"heal","life":0.75})
		companion_changed.emit(companion_status())
	elif companion_cast == "ward":
		companion_shield = 38.0
		companion_shield_left = 6.0
		companion_effects.append({"foot":companion_foot,"kind":"ward","life":0.75})
		companion_changed.emit(companion_status())
	elif companion_cast == "bolt":
		for enemy: Dictionary in enemies:
			if enemy.id == companion_target_id and enemy.state != "dead" and companion_foot.distance_to(enemy.foot) <= 4.8 and enemy.reaction.height < 190 and _line_clear(companion_foot,enemy.foot,0.8):
				var socket := _projectile_socket("serin",companion_foot,companion_facing,0.8)
				var direction: Vector2 = _projectile_direction(companion_foot,socket.foot,enemy.foot)
				companion_projectiles.append({"foot":socket.foot,"launch_from":companion_foot,"velocity":direction*7.0,"z":socket.z,"damage":18.0,"life":0.85})
				break

func _step_companion_projectiles(dt: float) -> void:
	for shot: Dictionary in companion_projectiles.duplicate():
		var before: Vector2 = shot.get("launch_from",shot.foot)
		var after: Vector2 = shot.foot + shot.velocity*dt
		shot.erase("launch_from")
		shot.life -= dt
		if shot.life <= 0.0 or not stage.bounds.has_point(after) or not _line_clear(before,after,shot.z):
			companion_projectiles.erase(shot)
			continue
		shot.foot = after
		var nearest: Dictionary = {}
		var distance := INF
		for enemy: Dictionary in enemies:
			if enemy.state == "dead" or enemy.reaction.height > 130:
				continue
			var closest := Geometry2D.get_closest_point_to_segment(enemy.foot,before,after)
			if absf(closest.x-enemy.foot.x) < 0.3 and absf(closest.y-enemy.foot.y) < 0.32:
				var along := before.distance_squared_to(closest)
				if along < distance:
					distance = along
					nearest = enemy
		if not nearest.is_empty():
			companion_hits += 1
			_apply_hit(nearest,{"damage":shot.damage,"action":"support_bolt"})
			companion_projectiles.erase(shot)

func damage_companion(amount: float, from: Vector2 = Vector2.ZERO) -> float:
	if not companion_enabled or companion_dead or companion_invuln_left > 0.0 or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var absorption := minf(companion_shield,amount)
	companion_shield -= absorption
	var taken := minf(companion_hp,maxf(0.0,amount-absorption))
	companion_hp -= taken
	companion_invuln_left = 0.22
	companion_hurt_left = 0.32
	companion_cast = ""
	companion_target_id = ""
	companion_hit_fired = true
	companion_facing = 1 if from.x >= companion_foot.x else -1
	_change_companion_action("hit")
	floating_numbers.append({"foot":companion_foot,"height":0.0,"amount":int(ceil(taken)),"life":0.7,"source":"ally_hurt"})
	if companion_hp <= 0.0:
		companion_dead = true
		companion_shield = 0.0
		companion_shield_left = 0.0
		companion_projectiles.clear()
		_change_companion_action("dead")
		notice.emit("瑟琳已倒下，回城休整可以复苏。")
	companion_changed.emit(companion_status())
	return taken

func _change_companion_action(action: String) -> void:
	if companion_action != action:
		companion_action = action
		companion_elapsed = 0.0

func _update_companion_view() -> void:
	if stage == null:
		return
	companion_root.position = stage.project(companion_foot)
	companion_root.visible = companion_enabled
	if is_instance_valid(companion_view):
		companion_view.call("set_combat_view",companion_status().merged({"elapsed":companion_elapsed,"facing":companion_facing,"hurt_left":companion_hurt_left}))

func replace_companion_view(view: Node2D) -> void:
	if not is_instance_valid(view) or not view.has_method("set_combat_view"):
		return
	if is_instance_valid(companion_view):
		companion_view.queue_free()
	companion_view = view
	companion_root.add_child(view)
	companion_sprite.hide()
	companion_label.hide()
	_update_companion_view()

func companion_status() -> Dictionary:
	return {"id":"serin","name":"瑟琳","class_name":"战牧","enabled":companion_enabled,"mode":companion_mode,
		"hp":companion_hp,"max_hp":COMPANION_MAX_HP,"mp":companion_mp,"max_mp":COMPANION_MAX_MP,
		"dead":companion_dead,"shield":companion_shield,"shield_left":companion_shield_left,"action":companion_action,
		"cooldowns":{"bolt":companion_cooldown,"heal":companion_heal_cooldown,"ward":companion_ward_cooldown},
		"skills":[{"id":"bolt","name":"圣光弹","cost":0,"cooldown":1.6,"remaining":companion_cooldown,"description":"18 点伤害，弹道可被障碍阻挡。"},
		{"id":"heal","name":"愈合术","cost":18,"cooldown":8.0,"remaining":companion_heal_cooldown,"description":"治疗范围内低于 55% 血量的队员，恢复 40 生命。"},
		{"id":"ward","name":"圣域盾","cost":24,"cooldown":12.0,"remaining":companion_ward_cooldown,"description":"战斗中自身低于 72% 血量时施放，吸收 38 伤害，持续 6 秒。"}]}

func companion_snapshot() -> Dictionary:
	return {"version":1,"enabled":companion_enabled,"mode":companion_mode,"hp":companion_hp,"mp":companion_mp,
		"dead":companion_dead,"shield":companion_shield,"shield_left":companion_shield_left,"cooldown":companion_cooldown,
		"heal_cooldown":companion_heal_cooldown,"ward_cooldown":companion_ward_cooldown,"hurt_left":companion_hurt_left,
		"invuln_left":companion_invuln_left,"action":companion_action,"elapsed":companion_elapsed,"cast":companion_cast,
		"heal_target":companion_heal_target,"hit_fired":companion_hit_fired,"target_id":companion_target_id,"facing":companion_facing}

func validate_companion(data: Dictionary) -> bool:
	if data.is_empty():
		return true # Legacy player saves did not contain an independent party body.
	if data.get("version",0) != 1 or not data.get("enabled") is bool or not data.get("dead") is bool:
		return false
	if data.get("mode","") not in ["follow","guard","passive"]:
		return false
	var limits := {"hp":COMPANION_MAX_HP,"mp":COMPANION_MAX_MP,"shield":38.0,"shield_left":6.0,"cooldown":1.6,
		"heal_cooldown":8.0,"ward_cooldown":12.0,"hurt_left":0.32,"invuln_left":0.22}
	for key in limits:
		if not _valid_number(data.get(key)) or float(data[key]) < 0.0 or float(data[key]) > float(limits[key])+0.00001:
			return false
	if bool(data.dead) != (float(data.hp) <= 0.0):
		return false
	if float(data.shield) > 0.0 and (float(data.shield_left) <= 0.0 or bool(data.dead)):
		return false
	if data.get("action","stand") not in ["stand","walk","attack1","magic","hit","dead"] or data.get("cast","") not in ["","bolt","heal","ward"]:
		return false
	if data.get("action","stand") == "dead" and not bool(data.dead):
		return false
	if data.get("action","stand") in ["attack1","magic"] and data.get("cast","").is_empty():
		return false
	if not _valid_number(data.get("elapsed",0.0)) or float(data.get("elapsed",0.0)) < 0.0:
		return false
	if data.get("heal_target","") not in ["","serin","player"] or not data.get("target_id","") is String or not data.get("hit_fired",false) is bool:
		return false
	if not _valid_number(data.get("facing",1)) or absf(float(data.get("facing",1))) != 1.0:
		return false
	return true

func restore_companion(data: Dictionary) -> bool:
	if not validate_companion(data):
		return false
	if data.is_empty():
		rest_companion()
		return true
	companion_enabled = data.enabled
	companion_mode = data.mode
	companion_hp = float(data.hp)
	companion_mp = float(data.mp)
	companion_dead = data.dead
	companion_shield = float(data.shield)
	companion_shield_left = float(data.shield_left)
	companion_cooldown = float(data.cooldown)
	companion_heal_cooldown = float(data.heal_cooldown)
	companion_ward_cooldown = float(data.ward_cooldown)
	companion_hurt_left = float(data.hurt_left)
	companion_invuln_left = float(data.invuln_left)
	companion_action = "dead" if companion_dead else str(data.get("action","stand"))
	companion_elapsed = float(data.get("elapsed",0.0))
	companion_cast = str(data.get("cast",""))
	companion_heal_target = str(data.get("heal_target",""))
	companion_hit_fired = bool(data.get("hit_fired",false))
	companion_target_id = str(data.get("target_id",""))
	companion_facing = int(data.get("facing",1))
	companion_path.clear()
	companion_projectiles.clear()
	_update_companion_view()
	companion_changed.emit(companion_status())
	return true

func rest_companion() -> bool:
	var changed := companion_hp < COMPANION_MAX_HP or companion_mp < COMPANION_MAX_MP or companion_dead or companion_cooldown > 0.0 or companion_heal_cooldown > 0.0 or companion_ward_cooldown > 0.0 or companion_hurt_left > 0.0 or companion_invuln_left > 0.0 or companion_shield > 0.0
	companion_hp = COMPANION_MAX_HP
	companion_mp = COMPANION_MAX_MP
	companion_dead = false
	companion_shield = 0.0
	companion_shield_left = 0.0
	companion_cooldown = 0.0
	companion_heal_cooldown = 0.0
	companion_ward_cooldown = 0.0
	companion_hurt_left = 0.0
	companion_invuln_left = 0.0
	companion_cast = ""
	companion_target_id = ""
	companion_hit_fired = false
	companion_projectiles.clear()
	_change_companion_action("stand")
	_update_companion_view()
	companion_changed.emit(companion_status())
	return changed

func _move_enemy(enemy: Dictionary, destination: Vector2, dt: float, speed: float) -> void:
	var direction := _steering(enemy.foot,destination,enemy.path,enemy.path_timer <= 0.0)
	if enemy.path_timer <= 0.0:
		enemy.path_timer = 0.7
	var separation := Vector2.ZERO
	for other: Dictionary in enemies:
		if enemy.state == "return" or other.id == enemy.id or other.state == "dead":
			continue
		var away: Vector2 = enemy.foot-other.foot
		if away.length() < 0.55 and away.length() > 0.01:
			separation += away.normalized() * 0.5
	direction = (direction+separation).limit_length(1.0)
	enemy.foot = Physics.step_position(stage.volumes,stage.bounds,enemy.foot,direction*minf(speed*dt,enemy.foot.distance_to(destination)),0.0,true)
	if enemy.state == "return" and absf(direction.x) > 0.12:
		enemy.facing = signf(direction.x)

func _steering(from: Vector2, destination: Vector2, path: Array, rebuild: bool) -> Vector2:
	if _line_clear(from,destination,0.0):
		path.clear()
		return from.direction_to(destination)
	if rebuild or path.is_empty():
		path.clear()
		path.append_array(_find_path(from,destination))
	while not path.is_empty() and from.distance_to(path[0]) < 0.25:
		path.pop_front()
	if not path.is_empty():
		return from.direction_to(path[0])
	return Vector2.ZERO

func _find_path(from: Vector2, destination: Vector2) -> Array[Vector2]:
	# Small deterministic 0.5 m grid: fewer than 1,000 cells for this courtyard.
	var origin: Vector2 = stage.bounds.position
	var start := Vector2i(roundi((from.x-origin.x)/0.5),roundi((from.y-origin.y)/0.5))
	var goal := Vector2i(roundi((destination.x-origin.x)/0.5),roundi((destination.y-origin.y)/0.5))
	var open: Array[Vector2i] = [start]
	var previous := {start:start}
	var scores := {start:0.0}
	var best := start
	var visited := 0
	while not open.is_empty() and visited < 1100:
		var index := 0
		var lowest := INF
		for i in open.size():
			var score: float = scores[open[i]] + Vector2(open[i]-goal).length()
			if score < lowest:
				index = i
				lowest = score
		var current: Vector2i = open.pop_at(index)
		visited += 1
		if Vector2(current-goal).length_squared() < Vector2(best-goal).length_squared():
			best = current
		if current == goal:
			best = current
			break
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = current+offset
			var point := origin+Vector2(next)*0.5
			if previous.has(next) or not stage.bounds.grow(-0.25).has_point(point) or not _walkable(point):
				continue
			if not _line_clear(origin+Vector2(current)*0.5,point,0.0):
				continue
			previous[next] = current
			scores[next] = float(scores[current])+1.0
			open.append(next)
	var result: Array[Vector2] = []
	while best != start:
		result.push_front(origin+Vector2(best)*0.5)
		best = previous[best]
	return result

func _walkable(point: Vector2) -> bool:
	return not Physics.blocked(stage.volumes,point,0.0) and bool(Physics.support(stage.volumes,point,0.15).valid)

func _line_clear(from: Vector2, to: Vector2, z: float) -> bool:
	var count := maxi(1,int(ceil(from.distance_to(to)/0.12)))
	for i in range(1,count+1):
		var point := from.lerp(to,float(i)/float(count))
		if Physics.blocked(stage.volumes,point,z):
			return false
		if z <= 0.01 and not Physics.support(stage.volumes,point,0.15).valid:
			return false
	return true

func _free_point(point: Vector2) -> Vector2:
	var safe := Vector2(clampf(point.x,stage.bounds.position.x+0.25,stage.bounds.end.x-0.25),clampf(point.y,stage.bounds.position.y+0.25,stage.bounds.end.y-0.25))
	if _walkable(safe):
		return safe
	for ring in range(1,15):
		for side in 12:
			var candidate := safe+Vector2.from_angle(float(side)*TAU/12.0)*ring*0.25
			if stage.bounds.grow(-0.25).has_point(candidate) and _walkable(candidate):
				return candidate
	return stage.foot

func snapshot() -> Dictionary:
	var saved: Array = []
	for enemy: Dictionary in enemies:
		var entry := {}
		for key in ["id","kind","hp","max_hp","state","timer","cooldown","facing","clock","flash","attack_facing","attack_variant","rewarded","attacks","target_id","reward_gold","reward_xp","drop_roll","hurt_left","hurt_elapsed","death_elapsed","attack_active","attack_elapsed","attack_windup","attack_recovery"]:
			entry[key] = enemy[key]
		for key in ["foot","home","aim","attack_origin"]:
			entry[key] = [enemy[key].x,enemy[key].y]
		entry["reaction"] = {}
		for key in ["height","rise_speed","shock_left","shock_tick","combo","combo_left","air_hits","air_hold","stun_left"]:
			entry.reaction[key] = enemy.reaction.get(key)
		saved.append(entry)
	var shots: Array = []
	for shot: Dictionary in hostile_projectiles:
		var record := {"foot":[shot.foot.x,shot.foot.y],"velocity":[shot.velocity.x,shot.velocity.y],"z":shot.z,"damage":shot.damage,"life":shot.life,"owner":shot.owner}
		if shot.has("launch_from"): record.launch_from = [shot.launch_from.x,shot.launch_from.y]
		shots.append(record)
	var ally := companion_snapshot()
	ally["foot"] = [companion_foot.x,companion_foot.y]
	ally["guard"] = [companion_guard.x,companion_guard.y]
	var bolts: Array = []
	for bolt in companion_projectiles:
		var record := {"foot":[bolt.foot.x,bolt.foot.y],"velocity":[bolt.velocity.x,bolt.velocity.y],"z":bolt.z,"damage":bolt.damage,"life":bolt.life}
		if bolt.has("launch_from"): record.launch_from = [bolt.launch_from.x,bolt.launch_from.y]
		bolts.append(record)
	return {"version":1,"wave":wave,"active":active,"cleared":cleared,"seed":run_seed,"rng_state":str(rng.state),"serial":_serial,"enemies":saved,"projectiles":shots,"companion":ally,"companion_projectiles":bolts}

func restore(data: Dictionary) -> bool:
	if data.get("version",0) != 1 or not data.get("enemies") is Array or not data.get("companion",{}) is Dictionary or not data.get("projectiles",[]) is Array:
		return false
	if int(data.get("wave",0)) < 0 or int(data.get("wave",0)) > 3 or data.enemies.size() > 12:
		return false
	if data.get("projectiles",[]).size() > 40:
		return false
	var ids := {}
	for entry in data.enemies:
		if not entry is Dictionary or not DEFINITIONS.has(str(entry.get("kind",""))) or not _valid_point(entry.get("foot",null)):
			return false
		if not entry.get("id",null) is String or entry.id.is_empty() or ids.has(entry.id):
			return false
		ids[entry.id] = true
		for key in ["hp","timer","cooldown","facing","clock","flash","attack_facing","attacks","reward_gold","reward_xp","drop_roll","hurt_left","hurt_elapsed","death_elapsed","attack_elapsed","attack_windup","attack_recovery"]:
			if entry.has(key) and not _valid_number(entry[key]):
				return false
		for key in ["home","aim","attack_origin"]:
			if entry.has(key) and not _valid_point(entry[key]):
				return false
		if entry.has("reaction"):
			if not entry.reaction is Dictionary:
				return false
			for value in entry.reaction.values():
				if not _valid_number(value):
					return false
	var ally_data: Dictionary = data.get("companion",{})
	if ally_data.has("version") and not validate_companion(ally_data):
		return false
	if ally_data.has("cooldown") and not _valid_number(ally_data.cooldown):
		return false
	for key in ["foot","guard"]:
		if ally_data.has(key) and not _valid_point(ally_data[key]):
			return false
	if not data.get("companion_projectiles",[]) is Array or data.get("companion_projectiles",[]).size() > 12:
		return false
	for entry in data.get("companion_projectiles",[]):
		if not entry is Dictionary or not _valid_point(entry.get("foot")) or not _valid_point(entry.get("velocity")):
			return false
		if entry.has("launch_from") and not _valid_point(entry.launch_from): return false
		for key in ["z","damage","life"]:
			if not _valid_number(entry.get(key)) or float(entry[key]) < 0.0:
				return false
	for entry in data.get("projectiles",[]):
		if not entry is Dictionary or not _valid_point(entry.get("foot")) or not _valid_point(entry.get("velocity")):
			return false
		if entry.has("launch_from") and not _valid_point(entry.launch_from): return false
		for key in ["z","damage","life"]:
			if entry.has(key) and not _valid_number(entry[key]):
				return false
	_clear_enemies()
	wave = int(data.get("wave",0))
	run_seed = int(data.get("seed",1))
	rng.seed = run_seed
	for entry: Dictionary in data.enemies:
		var enemy := _spawn(str(entry.kind),_free_point(Vector2(entry.foot[0],entry.foot[1])),str(entry.get("id","")))
		for key in ["timer","cooldown","facing","clock","flash","attack_facing","attacks","reward_gold","reward_xp","drop_roll","hurt_left","hurt_elapsed","death_elapsed","attack_elapsed","attack_windup","attack_recovery"]:
			if entry.get(key) is float or entry.get(key) is int:
				enemy[key] = entry[key]
		enemy.hp = clampf(float(entry.get("hp",enemy.max_hp)),0.0,enemy.max_hp)
		enemy.state = str(entry.get("state","idle"))
		if enemy.state not in ["idle","chase","telegraph","attack","recover","return","dead"]:
			enemy.state = "idle"
		enemy.rewarded = bool(entry.get("rewarded",false))
		enemy.attack_active = bool(entry.get("attack_active",false))
		if enemy.hp <= 0.0 or enemy.state == "dead":
			enemy.hp = 0.0
			enemy.state = "dead"
			enemy.rewarded = true
			enemy.attack_active = false
		enemy.attack_variant = str(entry.get("attack_variant","melee"))
		enemy.target_id = "serin" if entry.get("target_id","") == "serin" else "player"
		for key in ["home","aim","attack_origin"]:
			if _valid_point(entry.get(key,null)):
				enemy[key] = Vector2(entry[key][0],entry[key][1])
		var reaction: Dictionary = entry.get("reaction",{}) if entry.get("reaction",{}) is Dictionary else {}
		for key in ["height","rise_speed","shock_left","shock_tick","combo","combo_left","air_hits","air_hold","stun_left"]:
			if reaction.get(key) is int or reaction.get(key) is float:
				enemy.reaction.set(key,reaction[key])
	active = bool(data.get("active",false))
	cleared = bool(data.get("cleared",false))
	_serial = maxi(_serial,int(data.get("serial",_serial)))
	rng.state = int(str(data.get("rng_state",str(rng.state))))
	var ally: Dictionary = data.get("companion",{})
	companion_enabled = bool(ally.get("enabled",false))
	companion_root.visible = companion_enabled
	companion_mode = str(ally.get("mode","follow"))
	if companion_mode not in ["follow","guard","passive"]:
		companion_mode = "follow"
	if _valid_point(ally.get("foot",null)):
		companion_foot = _free_point(Vector2(ally.foot[0],ally.foot[1]))
	companion_guard = Vector2(ally.guard[0],ally.guard[1]) if _valid_point(ally.get("guard",null)) else companion_foot
	if ally.has("version"):
		restore_companion(ally)
	else:
		rest_companion()
		companion_cooldown = clampf(float(ally.get("cooldown",0.0)),0.0,1.6)
	companion_label.text = "瑟琳 · 战牧 / "+companion_mode
	for entry in data.get("companion_projectiles",[]):
		var shot := {"foot":Vector2(entry.foot[0],entry.foot[1]),"velocity":Vector2(entry.velocity[0],entry.velocity[1]).limit_length(7.0),"z":clampf(float(entry.z),0.0,3.0),"damage":clampf(float(entry.damage),0.0,18.0),"life":clampf(float(entry.life),0.0,0.85)}
		if entry.has("launch_from"): shot.launch_from = Vector2(entry.launch_from[0],entry.launch_from[1])
		companion_projectiles.append(shot)
	for entry in data.get("projectiles",[]):
		if entry is Dictionary and _valid_point(entry.get("foot",null)) and _valid_point(entry.get("velocity",null)):
			var shot := {"foot":Vector2(entry.foot[0],entry.foot[1]),"velocity":Vector2(entry.velocity[0],entry.velocity[1]).limit_length(8.0),"z":clampf(float(entry.get("z",0.72)),0.0,3.0),"damage":clampf(float(entry.get("damage",8)),0,100),"life":clampf(float(entry.get("life",1)),0,3),"owner":str(entry.get("owner",""))}
			if entry.has("launch_from"): shot.launch_from = Vector2(entry.launch_from[0],entry.launch_from[1])
			hostile_projectiles.append(shot)
	_update_companion_view()
	queue_redraw()
	return true

func _valid_point(value) -> bool:
	return value is Array and value.size() == 2 and _valid_number(value[0]) and _valid_number(value[1])

func _valid_number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and absf(float(value)) < 100000000.0

func _draw() -> void:
	if stage == null:
		return
	for enemy: Dictionary in enemies:
		if enemy.state not in ["telegraph","attack"]:
			continue
		var alpha := 0.25 if enemy.state == "telegraph" else 0.6
		var color := Color(1.0,0.32,0.24,alpha)
		var origin: Vector2 = enemy.attack_origin
		if enemy.attack_variant == "slam":
			var points := PackedVector2Array()
			for i in 40:
				var angle := float(i)*TAU/40.0
				points.append(stage.project(enemy.aim+Vector2(cos(angle)*1.4,sin(angle)*0.9)))
			draw_colored_polygon(points,color)
			points.append(points[0])
			draw_polyline(points,Color(1.0,0.5,0.3,0.85),2.0)
		elif enemy.attack_variant == "ranged":
			draw_line(stage.project(origin,0.72),stage.project(enemy.aim,0.72),Color(1,0.5,0.4,0.65),2.0)
			draw_arc(stage.project(enemy.aim),18,0,TAU,24,color.lightened(0.3),2)
		else:
			var reach: float = DEFINITIONS[enemy.kind].range
			var end := origin+Vector2(reach*enemy.attack_facing,0)
			draw_colored_polygon(PackedVector2Array([stage.project(origin+Vector2(0,-0.57)),stage.project(end+Vector2(0,-0.57)),stage.project(end+Vector2(0,0.57)),stage.project(origin+Vector2(0,0.57))]),color)
	for shot: Dictionary in hostile_projectiles:
		var point: Vector2 = stage.project(shot.foot,shot.z)
		var direction: Vector2 = (stage.project(shot.foot+shot.velocity,shot.z)-point).normalized()
		draw_line(point-direction*18.0,point,Color(0.76,0.38,1.0,0.65),4.0)
		draw_circle(point,10,Color(0.72,0.3,1.0,0.25))
		draw_circle(point,5,Color("f7d9ff"))
	for shot: Dictionary in companion_projectiles:
		var point: Vector2 = stage.project(shot.foot,shot.z)
		var direction: Vector2 = (stage.project(shot.foot+shot.velocity,shot.z)-point).normalized()
		draw_line(point-direction*21.0,point,Color(1.0,0.83,0.37,0.65),5.0)
		draw_circle(point,8,Color(1.0,0.86,0.43,0.25))
		draw_circle(point,4,Color("fff9cf"))
	for effect in companion_effects:
		var at: Vector2 = stage.project(effect.foot,0.65)
		var strength := clampf(float(effect.life)/0.75,0.0,1.0)
		var tint := Color(0.62,1.0,0.72,strength) if effect.kind == "heal" else Color(1.0,0.87,0.45,strength)
		draw_arc(at,20+(1-strength)*20,0,TAU,32,tint,3.0)
		if effect.kind == "heal":
			draw_line(at+Vector2(-8,0),at+Vector2(8,0),tint,4)
			draw_line(at+Vector2(0,-8),at+Vector2(0,8),tint,4)
	if companion_enabled and not companion_dead and companion_shield > 0.0:
		draw_arc(stage.project(companion_foot,0.7),47,PI*0.15,PI*1.85,32,Color(1.0,0.89,0.5,0.65),2.5)
	for number: Dictionary in floating_numbers:
		var position_on_screen: Vector2 = stage.project(number.foot)-Vector2(10,145+number.height+(0.7-number.life)*50)
		draw_string(ThemeDB.fallback_font,position_on_screen,str(number.amount)+( " AIR" if number.source == "air" else ""),HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color(1,0.9,0.6,clampf(number.life/0.25,0,1)))

func _exit_tree() -> void:
	for enemy: Dictionary in enemies:
		if is_instance_valid(enemy.art):
			enemy.art.queue_free()
	if is_instance_valid(companion_root):
		companion_root.queue_free()
