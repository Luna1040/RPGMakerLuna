extends Node2D
## Explicitly stepped combat service. Logical feet/depth/z stay independent of artwork.
## No gameplay timer or tween runs while the map is paused by an inventory/modal.
signal enemy_defeated(data: Dictionary)
signal wave_cleared(wave: int)
signal notice(text: String)

const Physics = preload("res://belt_physics.gd")
const Query = preload("res://combat_query.gd")
const Reactions = preload("res://dummy_reactions.gd")
const EnemyArt = preload("enemy_art.gd")
const ARENA := Rect2(18.65,2.5,5.65,6.2)
const DEFINITIONS := {
	"melee":{"hp":74.0,"speed":1.3,"damage":9.0,"range":1.1,"windup":0.6,"cooldown":1.35,"label":"Scout / prototype"},
	"ranged":{"hp":58.0,"speed":0.95,"damage":8.0,"range":5.2,"windup":0.9,"cooldown":2.1,"label":"Caster / prototype"},
	"elite":{"hp":145.0,"speed":1.1,"damage":13.0,"range":1.35,"windup":0.8,"cooldown":1.65,"label":"Guard / prototype"},
	"boss":{"hp":360.0,"speed":0.9,"damage":18.0,"range":1.8,"windup":1.1,"cooldown":2.0,"label":"Warden / prototype"}
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
var companion_root := Node2D.new()
var companion_sprite := Sprite2D.new()
var companion_label := Label.new()
var companion_path: Array[Vector2] = []
var companion_path_timer := 0.0
var _serial := 0
var _clock := 0.0

func setup(map_stage) -> void:
	stage = map_stage
	z_index = 1
	companion_foot = _free_point(stage.foot + Vector2(-0.8,0.5))
	companion_guard = companion_foot
	stage.sorting.add_child(companion_root)
	companion_root.name = "CompanionEcho"
	companion_root.add_child(companion_sprite)
	companion_root.add_child(companion_label)
	companion_label.text = "ALLY / follow"
	companion_label.position = Vector2(-60,-260)
	companion_label.add_theme_font_size_override("font_size",15)
	companion_label.add_theme_color_override("font_color",Color("8ce8eb"))
	companion_label.add_theme_color_override("font_shadow_color",Color("12242e"))
	companion_label.add_theme_constant_override("shadow_offset_x",2)
	companion_label.add_theme_constant_override("shadow_offset_y",2)
	companion_sprite.modulate = Color(0.7,0.92,1.0,0.85)
	_update_companion_view()
	companion_root.visible = companion_enabled

func set_companion_enabled(enabled: bool) -> void:
	companion_enabled = enabled
	companion_root.visible = enabled
	companion_target_id = ""
	_change_companion_action("stand")
	if enabled and stage != null:
		companion_foot = _free_point(stage.foot + Vector2(-0.8,0.55))
		companion_guard = companion_foot
		companion_path.clear()
		companion_cooldown = 0.25
		_update_companion_view()

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
		"aim":p,"attack_origin":p,"attack_facing":-1.0,"attack_variant":"melee","rewarded":false,
		"path":[],"path_timer":0.0,"attacks":0,"reward_gold":rng.randi_range(7,12) + (25 if kind == "boss" else 0),
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
	floating_numbers.clear()
	active = false
	_serial = 0

func set_companion(mode: String) -> void:
	if mode not in ["follow","guard","passive"]:
		return
	companion_mode = mode
	companion_target_id = ""
	_change_companion_action("stand")
	companion_guard = companion_foot
	companion_path.clear()
	companion_cooldown = maxf(companion_cooldown,0.25)
	companion_label.text = "ALLY / " + mode
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
	for number: Dictionary in floating_numbers.duplicate():
		number.life -= dt
		if number.life <= 0.0:
			floating_numbers.erase(number)
	if stage.knight.defeated:
		hostile_projectiles.clear()
		return
	for enemy: Dictionary in enemies:
		if enemy.state == "dead":
			continue
		enemy.clock += dt
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
	_check_cleared()

func _step_enemy(enemy: Dictionary, dt: float) -> void:
	var stats: Dictionary = DEFINITIONS[enemy.kind]
	var target: Vector2 = stage.foot
	var offset: Vector2 = target - enemy.foot
	var distance := offset.length()
	if not ARENA.grow(1.2).has_point(target) or enemy.foot.distance_to(enemy.home) > 7.5:
		if enemy.state != "return":
			enemy.state = "return"
			enemy.path.clear()
	if enemy.state == "return":
		_move_enemy(enemy,enemy.home,dt,float(stats.speed)*1.3)
		if enemy.foot.distance_to(enemy.home) < 0.15:
			enemy.state = "idle"
			enemy.timer = 0.5
		return
	if enemy.state == "idle":
		enemy.timer -= dt
		if distance < 6.4 and enemy.timer <= 0.0 and ARENA.grow(1.2).has_point(target):
			enemy.state = "chase"
		return
	if enemy.state == "recover":
		enemy.timer -= dt
		if enemy.timer <= 0.0:
			enemy.state = "chase"
		return
	if enemy.state == "telegraph":
		enemy.timer -= dt
		if enemy.timer <= 0.0:
			enemy.state = "attack"
			enemy.timer = 0.16
			_resolve_attack(enemy)
		return
	if enemy.state == "attack":
		enemy.timer -= dt
		if enemy.timer <= 0.0:
			enemy.state = "recover"
			enemy.timer = 0.38 if enemy.kind != "boss" else 0.7
		return
	enemy.facing = 1.0 if offset.x >= 0.0 else -1.0
	var can_attack := distance < float(stats.range) + 0.35 and absf(offset.y) < (2.0 if enemy.kind == "ranged" else 0.65)
	can_attack = can_attack and stage.height_z < 1.55 and _line_clear(enemy.foot,target,0.4)
	if can_attack and enemy.cooldown <= 0.0:
		enemy.state = "telegraph"
		enemy.timer = stats.windup
		enemy.aim = target
		enemy.attack_origin = enemy.foot
		enemy.attack_facing = enemy.facing
		enemy.attack_variant = "ranged" if enemy.kind == "ranged" else ("slam" if enemy.kind == "boss" and int(enemy.attacks)%2 == 0 else "melee")
		enemy.attacks += 1
	elif not can_attack:
		var desired := target - Vector2(enemy.facing * (3.0 if enemy.kind == "ranged" else 0.8),0)
		_move_enemy(enemy,desired,dt,float(stats.speed))

func _resolve_attack(enemy: Dictionary) -> void:
	var stats: Dictionary = DEFINITIONS[enemy.kind]
	enemy.cooldown = stats.cooldown
	if enemy.attack_variant == "ranged":
		var direction: Vector2 = (enemy.aim-enemy.foot).normalized()
		hostile_projectiles.append({"foot":enemy.foot,"velocity":direction*4.1,"z":0.72,"damage":stats.damage,"life":2.2,"owner":enemy.id})
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

func _step_projectiles(dt: float) -> void:
	for projectile: Dictionary in hostile_projectiles.duplicate():
		var before: Vector2 = projectile.foot
		var after: Vector2 = before + projectile.velocity * dt
		projectile.life -= dt
		if projectile.life <= 0.0 or not stage.bounds.has_point(after) or not _line_clear(before,after,float(projectile.z)):
			hostile_projectiles.erase(projectile)
			continue
		projectile.foot = after
		var closest := Geometry2D.get_closest_point_to_segment(stage.foot,before,after)
		if absf(closest.x-stage.foot.x) <= 0.27 and absf(closest.y-stage.foot.y) <= 0.33 and float(projectile.z) >= stage.height_z and float(projectile.z) <= stage.height_z+1.7:
			stage.knight.apply_damage(float(projectile.damage),stage.project(before))
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
		enemy.art.hide()
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
	companion_cooldown = maxf(0.0,companion_cooldown-dt)
	companion_elapsed += dt
	companion_path_timer = maxf(0.0,companion_path_timer-dt)
	if companion_action == "attack1" and companion_elapsed < 0.45:
		if companion_elapsed >= 0.18 and not companion_hit_fired:
			companion_hit_fired = true
			for enemy: Dictionary in enemies:
				if enemy.id == companion_target_id and enemy.state != "dead" and absf(enemy.foot.x-companion_foot.x) < 1.8 and absf(enemy.foot.y-companion_foot.y) < 0.6 and enemy.reaction.height < 170 and _line_clear(companion_foot,enemy.foot,0.5):
					companion_hits += 1
					_apply_hit(enemy,{"damage":12.0,"action":"attack1"})
					break
		return
	var target: Dictionary = {}
	var nearest := 5.0 if companion_mode == "follow" else 3.2
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
		destination = target.foot - Vector2(companion_facing*1.0,0)
		if absf(target.foot.x-companion_foot.x) < 1.65 and absf(target.foot.y-companion_foot.y) < 0.5 and target.reaction.height < 160 and _line_clear(companion_foot,target.foot,0.5) and companion_cooldown <= 0.0:
			companion_action = "attack1"
			companion_elapsed = 0.0
			companion_cooldown = 1.6
			companion_target_id = target.id
			companion_hit_fired = false
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

func _change_companion_action(action: String) -> void:
	if companion_action != action:
		companion_action = action
		companion_elapsed = 0.0

func _update_companion_view() -> void:
	if stage == null:
		return
	companion_root.position = stage.project(companion_foot)
	companion_sprite.visible = not stage.knight.defeated
	if not stage.knight.clips.has(companion_action):
		return
	var clip: Dictionary = stage.knight.clips[companion_action]
	var frames: Array = clip.get("frames",[])
	var cached: Array = stage.knight.textures.get(companion_action,[])
	if frames.is_empty() or cached.is_empty():
		return
	var time := fmod(companion_elapsed*1000.0,maxf(1.0,float(clip.duration_ms)))
	var frame_index := 0
	for i in frames.size():
		frame_index = i
		time -= float(frames[i].get("duration_ms",100.0))
		if time < 0.0:
			break
	frame_index = mini(frame_index,cached.size()-1)
	companion_sprite.texture = cached[frame_index][0]
	var pivot: Array = frames[frame_index].get("pivot",clip.get("pivot",[384,700]))
	var scale_factor: float = float(clip.get("scale",1.0))*stage.knight.visual_scale*0.9
	companion_sprite.scale = Vector2(companion_facing*scale_factor,scale_factor)
	companion_sprite.position = (Vector2(384,384)-Vector2(float(pivot[0]),float(pivot[1])))*Vector2(companion_facing*scale_factor,scale_factor)

func _move_enemy(enemy: Dictionary, destination: Vector2, dt: float, speed: float) -> void:
	var direction := _steering(enemy.foot,destination,enemy.path,enemy.path_timer <= 0.0)
	if enemy.path_timer <= 0.0:
		enemy.path_timer = 0.7
	var separation := Vector2.ZERO
	for other: Dictionary in enemies:
		if other.id == enemy.id or other.state == "dead":
			continue
		var away: Vector2 = enemy.foot-other.foot
		if away.length() < 0.55 and away.length() > 0.01:
			separation += away.normalized() * 0.5
	direction = (direction+separation).limit_length(1.0)
	enemy.foot = Physics.step_position(stage.volumes,stage.bounds,enemy.foot,direction*speed*dt,0.0,true)
	if absf(direction.x) > 0.02:
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
		for key in ["id","kind","hp","max_hp","state","timer","cooldown","facing","clock","flash","attack_facing","attack_variant","rewarded","attacks","reward_gold","reward_xp","drop_roll"]:
			entry[key] = enemy[key]
		for key in ["foot","home","aim","attack_origin"]:
			entry[key] = [enemy[key].x,enemy[key].y]
		entry["reaction"] = {}
		for key in ["height","rise_speed","shock_left","shock_tick","combo","combo_left","air_hits","air_hold","stun_left"]:
			entry.reaction[key] = enemy.reaction.get(key)
		saved.append(entry)
	var shots: Array = []
	for shot: Dictionary in hostile_projectiles:
		shots.append({"foot":[shot.foot.x,shot.foot.y],"velocity":[shot.velocity.x,shot.velocity.y],"z":shot.z,"damage":shot.damage,"life":shot.life,"owner":shot.owner})
	return {"version":1,"wave":wave,"active":active,"cleared":cleared,"seed":run_seed,"rng_state":str(rng.state),"serial":_serial,"enemies":saved,"projectiles":shots,"companion":{"enabled":companion_enabled,"mode":companion_mode,"foot":[companion_foot.x,companion_foot.y],"guard":[companion_guard.x,companion_guard.y],"cooldown":companion_cooldown}}

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
		for key in ["hp","timer","cooldown","facing","clock","flash","attack_facing","attacks","reward_gold","reward_xp","drop_roll"]:
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
	if ally_data.has("cooldown") and not _valid_number(ally_data.cooldown):
		return false
	for entry in data.get("projectiles",[]):
		if not entry is Dictionary or not _valid_point(entry.get("foot")) or not _valid_point(entry.get("velocity")):
			return false
		for key in ["z","damage","life"]:
			if entry.has(key) and not _valid_number(entry[key]):
				return false
	_clear_enemies()
	wave = int(data.get("wave",0))
	run_seed = int(data.get("seed",1))
	rng.seed = run_seed
	for entry: Dictionary in data.enemies:
		var enemy := _spawn(str(entry.kind),_free_point(Vector2(entry.foot[0],entry.foot[1])),str(entry.get("id","")))
		for key in ["timer","cooldown","facing","clock","flash","attack_facing","attacks","reward_gold","reward_xp","drop_roll"]:
			if entry.get(key) is float or entry.get(key) is int:
				enemy[key] = entry[key]
		enemy.hp = clampf(float(entry.get("hp",enemy.max_hp)),0.0,enemy.max_hp)
		enemy.state = str(entry.get("state","idle"))
		if enemy.state not in ["idle","chase","telegraph","attack","recover","return","dead"]:
			enemy.state = "idle"
		enemy.rewarded = bool(entry.get("rewarded",false))
		if enemy.hp <= 0.0 or enemy.state == "dead":
			enemy.hp = 0.0
			enemy.state = "dead"
			enemy.rewarded = true
			enemy.art.hide()
		enemy.attack_variant = str(entry.get("attack_variant","melee"))
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
	companion_cooldown = clampf(float(ally.get("cooldown",0.0)),0.0,3.0)
	companion_action = "stand"
	companion_target_id = ""
	companion_path.clear()
	companion_label.text = "ALLY / "+companion_mode
	for entry in data.get("projectiles",[]):
		if entry is Dictionary and _valid_point(entry.get("foot",null)) and _valid_point(entry.get("velocity",null)):
			hostile_projectiles.append({"foot":Vector2(entry.foot[0],entry.foot[1]),"velocity":Vector2(entry.velocity[0],entry.velocity[1]).limit_length(8.0),"z":clampf(float(entry.get("z",0.72)),0.0,3.0),"damage":clampf(float(entry.get("damage",8)),0,100),"life":clampf(float(entry.get("life",1)),0,3),"owner":str(entry.get("owner",""))})
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
		draw_circle(point,10,Color(1.0,0.3,0.3,0.25))
		draw_circle(point,5,Color("ffd28c"))
	for number: Dictionary in floating_numbers:
		var position_on_screen: Vector2 = stage.project(number.foot)-Vector2(10,145+number.height+(0.7-number.life)*50)
		draw_string(ThemeDB.fallback_font,position_on_screen,str(number.amount)+( " AIR" if number.source == "air" else ""),HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color(1,0.9,0.6,clampf(number.life/0.25,0,1)))

func _exit_tree() -> void:
	for enemy: Dictionary in enemies:
		if is_instance_valid(enemy.art):
			enemy.art.queue_free()
	if is_instance_valid(companion_root):
		companion_root.queue_free()
