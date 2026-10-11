extends SceneTree
const Encounters = preload("res://systems/encounters/encounters.gd")
const KnightScene = preload("res://characters/first_knight/knight.tscn")
var failures: Array[String] = []
var rewards: Array = []
var clears: Array = []
var arena
var service

class TestStage extends Node2D:
	var foot := Vector2(21,4)
	var height_z := 0.0
	var bounds := Rect2(0.7,0.5,24.2,8.7)
	var volumes: Array = []
	var sorting := Node2D.new()
	var knight
	func project(point: Vector2, z: float = 0) -> Vector2:
		return Vector2(point.x*120,410+point.y*45-z*120)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func advance(seconds: float) -> void:
	for i in int(ceil(seconds*60)):
		arena.knight._physics_process(1.0/60)
		service.step(1.0/60)

func fresh() -> void:
	service.clear()
	arena.volumes.clear()
	arena.foot = Vector2(21,4)
	arena.height_z = 0
	arena.knight.reset_character()
	service.set_companion("passive")
	service.companion_foot = Vector2(2,2)
	rewards.clear()
	clears.clear()

func one(kind: String = "melee", point: Vector2 = Vector2(22,4)) -> Dictionary:
	service.wave = 1
	service.active = true
	return service._spawn(kind,point)

func run() -> void:
	arena = TestStage.new()
	root.add_child(arena)
	arena.add_child(arena.sorting)
	arena.knight = KnightScene.instantiate()
	arena.knight.use_local_input = false
	arena.knight.equipment.persistence_enabled = false
	arena.add_child(arena.knight)
	arena.knight.set_physics_process(false)
	service = Encounters.new()
	arena.add_child(service)
	service.setup(arena)
	check(not service.companion_enabled and not service.companion_root.visible,"unrecruited companion must stay hidden")
	service.set_companion_enabled(true)
	service.enemy_defeated.connect(func(data: Dictionary): rewards.append(data))
	service.wave_cleared.connect(func(number: int): clears.append(number))
	fresh()
	check(service.begin_wave(1,91),"first wave should begin")
	check(service.enemies.size() == 3,"wave one must have three enemies")
	check(not service.begin_wave(2,91),"active encounter must not be overwritten")
	var snapshot: Dictionary = service.snapshot()
	var expected: Array = snapshot.enemies.duplicate(true)
	check(service.restore(JSON.parse_string(JSON.stringify(snapshot))),"snapshot must survive JSON roundtrip")
	var restored: Array = service.snapshot().enemies
	for i in expected.size():
		for key in expected[i]:
			if typeof(expected[i][key]) == TYPE_FLOAT:
				check(is_equal_approx(float(expected[i][key]),float(restored[i][key])),"snapshot float field: "+key)
			elif expected[i][key] != restored[i][key]:
				check(false,"snapshot field "+key+": "+str(expected[i][key])+" != "+str(restored[i][key]))
	check(not service.restore({"version":1,"wave":1,"enemies":[{"kind":"bogus","foot":[1,2]}]}),"invalid save must be rejected")
	check(not service.restore({"version":1}),"missing mandatory fields must reject without changing world")
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.enemies[0]["hp"] = "invalid"
	check(not service.restore(malformed),"invalid enemy numeric fields must reject before mutation")
	fresh()
	var enemy: Dictionary = one()
	var swing := {"damage":10,"facing":1,"range":240,"action":"attack1","depth_radius":0.6}
	check(service.hit(Vector2(21,7),0,swing) == 0,"depth mismatch must miss")
	check(service.hit(Vector2(21,4),3.5,swing) == 0,"height mismatch must miss")
	check(service.hit(Vector2(23,4),0,swing) == 0,"enemy behind facing must miss")
	check(service.hit(Vector2(21,4),0,swing) == 1,"in-reach sword should hit")
	check(enemy.state == "recover","hit must interrupt AI")
	service.hit(Vector2(21,4),0,{"damage":1,"facing":1,"range":240,"launch":true})
	check(enemy.reaction.airborne(),"launch must create elevation")
	advance(0.25)
	var air_height: float = enemy.reaction.height
	service.hit(Vector2(21,4),0,swing)
	check(enemy.reaction.air_hits > 0 and air_height > 1,"air combo must preserve float reaction")
	advance(2.5)
	check(not enemy.reaction.airborne(),"gravity must land enemy")
	fresh()
	enemy = one()
	check(service.hit_projectile(20,23,4,0.7,10),"projectile should hit")
	check(enemy.reaction.shock_left > 0,"spell must apply shock")
	var hp: float = enemy.hp
	advance(0.6)
	check(enemy.hp < hp,"shock must deal damage over time")
	fresh()
	enemy = one()
	enemy.hp = 1
	service.hit(Vector2(21,4),0,swing)
	service.hit(Vector2(21,4),0,swing)
	advance(1)
	check(rewards.size() == 1,"enemy death reward must emit exactly once")
	check(clears == [1],"wave completion must emit exactly once")
	check(not service.active and service.cleared,"cleared encounter must end")
	fresh()
	one("melee",Vector2(22,4))
	one("melee",Vector2(22.2,4.2))
	check(service.hit(Vector2(21,4),0,{"damage":999,"facing":1,"range":300,"action":"attack1"}) == 2,"cleaving sword must hit multiple targets")
	check(rewards.size() == 2 and clears.size() == 1,"multi-target death must clear once")
	fresh()
	var far: Dictionary = one("melee",Vector2(23,4))
	var near: Dictionary = one("melee",Vector2(21.5,4))
	service.hit_projectile(20,24,4,0.7,11)
	check(near.hp < near.max_hp and far.hp == far.max_hp,"projectile must hit nearest target in travel direction")
	arena.volumes.append({"id":"wall","kind":"wall","x":20.7,"depth":3,"width":0.4,"depth_size":2,"base_z":0,"height":3,"solid":true,"standable":false})
	var near_hp: float = near.hp
	check(service.hit_projectile(20,24,4,0.7,11) and near.hp == near_hp,"wall must absorb player projectile without damaging enemy behind it")
	check(service.hit(Vector2(20,4),0,{"damage":11,"facing":1,"range":400}) == 0,"wall must block melee")
	fresh()
	enemy = one("melee",Vector2(22,4))
	enemy.state = "chase"
	advance(0.1)
	check(enemy.state == "telegraph","melee must warn before hitting")
	check(arena.knight.health == 100,"telegraph must not damage")
	arena.foot.y = 5.5
	advance(0.65)
	check(arena.knight.health == 100,"stepping out of locked telegraph must avoid attack")
	fresh()
	enemy = one("melee",Vector2(22,4))
	enemy.state = "chase"
	advance(0.1)
	arena.height_z = 1.1
	advance(0.7)
	check(arena.knight.health == 100,"jump must avoid low melee swing")
	fresh()
	enemy = one("melee",Vector2(22,4))
	enemy.state = "chase"
	advance(0.75)
	check(arena.knight.health < 100,"enemy must damage actual knight actor")
	var after_attack: float = arena.knight.health
	advance(0.8)
	check(arena.knight.health == after_attack,"attack cooldown must prevent repeated frame damage")
	fresh()
	enemy = one("ranged",Vector2(24,4))
	enemy.state = "chase"
	advance(1.0)
	check(not service.hostile_projectiles.is_empty(),"caster must create a visible projectile after windup")
	advance(0.8)
	check(arena.knight.health < 100,"hostile projectile must damage hero")
	fresh()
	enemy = one("ranged",Vector2(24,4))
	service.hostile_projectiles.append({"foot":Vector2(24,4),"velocity":Vector2(-4,0),"z":0.7,"damage":20,"life":3,"owner":enemy.id})
	arena.volumes.append({"id":"wall","kind":"wall","x":22.4,"depth":3,"width":0.4,"depth_size":2,"base_z":0,"height":3,"solid":true,"standable":false})
	advance(1.0)
	check(arena.knight.health == 100 and service.hostile_projectiles.is_empty(),"wall must absorb hostile projectile")
	fresh()
	enemy = one("boss",Vector2(22,4))
	enemy.state = "chase"
	arena.knight.health = 1
	advance(1.5)
	check(arena.knight.defeated,"boss must cause real character death")
	var before_death: Vector2 = enemy.foot
	advance(1)
	check(enemy.foot == before_death,"AI must stop after hero death")
	fresh()
	enemy = one("melee",Vector2(22,4))
	enemy.state = "recover"
	enemy.timer = 99
	service.companion_foot = Vector2(21,4)
	service.set_companion("follow")
	advance(0.3)
	check(enemy.hp == enemy.max_hp,"companion must wind up before dealing damage")
	advance(0.3)
	check(enemy.hp < enemy.max_hp and service.companion_hits > 0,"companion must assist with real damage")
	service.set_companion("passive")
	hp = enemy.hp
	advance(2.0)
	check(enemy.hp == hp,"passive companion must not attack")
	service.set_companion("guard")
	var guard: Vector2 = service.companion_guard
	arena.foot = Vector2(5,4)
	enemy.state = "dead"
	advance(1.0)
	check(service.companion_foot.distance_to(guard) < 0.35,"guard companion must hold location")
	fresh()
	arena.volumes.append({"id":"wall","kind":"wall","x":10,"depth":3,"width":0.6,"depth_size":2,"base_z":0,"height":3,"solid":true,"standable":false})
	arena.foot = Vector2(12,4)
	service.companion_foot = Vector2(9,4)
	service.set_companion("passive")
	advance(6.0)
	check(service.companion_foot.x > 10.8,"companion pathfinding must go around blocking wall")
	check(not service.Physics.blocked(arena.volumes,service.companion_foot,0),"companion must never finish inside collision")
	check(service.companion_sprite.texture != null,"companion should reuse actor textures")
	fresh()
	enemy = one()
	enemy.state = "chase"
	arena.foot = Vector2(5,4)
	advance(0.1)
	check(enemy.state in ["return","idle"],"enemy must return rather than invade town")
	for error in failures:
		push_error(error)
	print("ENCOUNTERS_TEST ","PASS" if failures.is_empty() else "FAIL", " · waves, save, seeded drops, depth/height/facing, launch/air combos/shock, damage/death, telegraphs/cooldowns, projectiles/walls, companion modes/pathfinding")
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
