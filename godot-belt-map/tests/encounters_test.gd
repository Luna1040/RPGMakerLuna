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
	service.rest_companion()
	# Isolate legacy skills; area spell is tested separately below.
	service.companion_smite_cooldown=8.0
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
	fresh()
	var chain_a: Dictionary = one("melee",Vector2(21.5,4))
	var chain_b: Dictionary = one("melee",Vector2(22.5,4.2))
	var chain_c: Dictionary = one("melee",Vector2(23.5,4))
	var chain_d: Dictionary = one("melee",Vector2(24.5,4.1))
	var chain: Dictionary = service.hit_skill_projectile(20,22,4,0.7,11,0.65,3,1.2)
	check(chain.consumed and chain.hit_ids.size() == 3 and chain.segments.size() == 2,"lightning chain must stop at the configured target count")
	check(chain_a.hp < chain_a.max_hp and chain_b.hp < chain_b.max_hp and chain_c.hp < chain_c.max_hp and chain_d.hp == chain_d.max_hp,"lightning chain selected the wrong targets")
	fresh()
	far = one("melee",Vector2(23,4))
	near = one("melee",Vector2(21.5,4))
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
	for tick in 60:
		advance(1.0/60.0)
		if arena.knight.health < 100:
			break
	check(arena.knight.health < 100,"enemy must damage actual knight actor")
	check(enemy.state == "attack" and enemy.attack_active and is_equal_approx(enemy.attack_elapsed,enemy.attack_windup),"actual damage release must set the visual timeline exactly at the authored impact mapping")
	var after_attack: float = arena.knight.health
	advance(0.8)
	check(arena.knight.health == after_attack,"attack cooldown must prevent repeated frame damage")
	for facing in [1,-1]:
		fresh()
		enemy = one("melee",Vector2(22,4))
		enemy.state = "chase"
		# Target near the authored steel tip, including its body half-width.
		# The former 1.1 m placeholder attack missed this visible sword contact.
		arena.foot = enemy.foot+Vector2(facing*1.85,0)
		advance(1.0/60.0)
		check(enemy.state == "telegraph","authored scout tip reach must begin a real strike in either facing")
		advance(0.7)
		check(arena.knight.health < 100,"authored scout sword contact must damage a stationary target in either facing")
		fresh()
		enemy = one("melee",Vector2(22,4))
		enemy.state = "chase"
		arena.foot = enemy.foot+Vector2(facing*(float(Encounters.DEFINITIONS.melee.range)+0.27),0)
		var before_step: Vector2 = enemy.foot
		advance(1.0/60.0)
		check(enemy.state == "chase" and enemy.foot.distance_to(before_step)>0.001,"outside the real hurt rectangle AI must advance, not repeatedly telegraph an unreachable strike")
		advance(1.2)
		check(arena.knight.health < 100,"AI must close the former empty-swing gap and hit a stationary target")
		fresh()
		enemy = one("melee",Vector2(22,4))
		enemy.state = "chase"
		arena.foot = Vector2(2,2)
		service.companion_foot = enemy.foot+Vector2(facing*1.9,0)
		service._step_enemy(enemy,1.0/60.0)
		check(enemy.target_id == "serin" and enemy.state == "telegraph","melee acquisition must use the companion's actual body rectangle")
		service._resolve_attack(enemy)
		check(service.companion_hp < Encounters.COMPANION_MAX_HP,"the companion must be hittable at the same visible sword tip")
		fresh()
		enemy = one("melee",Vector2(22,4))
		enemy.state = "chase"
		arena.foot = Vector2(2,2)
		service.companion_foot = enemy.foot+Vector2(facing*(float(Encounters.DEFINITIONS.melee.range)+0.27),0)
		service._step_enemy(enemy,1.0/60.0)
		check(enemy.state == "chase","an out-of-range companion must not trap AI in empty swings")
	# Authored axe/greatsword tip reach replaces the old placeholder ranges.
	for kind in ["elite","boss"]:
		for facing in [1,-1]:
			fresh()
			service.companion_enabled = false
			enemy = one(kind,Vector2(22,4))
			enemy.state = "chase"
			var visible_reach: float = 2.30 if kind == "elite" else 2.09
			arena.foot = enemy.foot+Vector2(facing*(visible_reach+0.15),0)
			advance(1.0/60.0)
			check(enemy.state == "telegraph",kind+" must acquire a target at the authored weapon tip")
			advance(float(Encounters.DEFINITIONS[kind].windup)+0.01)
			check(arena.knight.health < 100,kind+" visible weapon contact must damage in both facings")
			fresh()
			service.companion_enabled = false
			enemy = one(kind,Vector2(22,4))
			enemy.state = "chase"
			arena.foot = enemy.foot+Vector2(facing*(float(Encounters.DEFINITIONS[kind].range)+0.3),0)
			advance(1.0/60.0)
			check(enemy.state == "chase",kind+" must approach targets beyond the hit rectangle")
	service.companion_enabled = true
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
	check(service.companion_sprite.texture != null or is_instance_valid(service.companion_view),"companion must have a visible authored view")
	fresh()
	enemy = one()
	enemy.state = "chase"
	arena.foot = Vector2(5,4)
	advance(0.1)
	check(enemy.state in ["return","idle"],"enemy must return rather than invade town")
	# Serin has her own combat body and resources; modes never grant immunity.
	fresh()
	service.companion_foot = Vector2(22,4)
	enemy = one("melee",Vector2(23,4))
	enemy.state = "chase"
	arena.foot = Vector2(19,4)
	service.set_companion("guard")
	service.companion_cooldown = 1.6
	advance(0.1)
	check(enemy.target_id == "serin" and enemy.state == "telegraph","nearby living companion must be a real enemy target")
	advance(0.7)
	check(service.companion_hp < service.COMPANION_MAX_HP and arena.knight.health == 100,"enemy melee must damage Serin independently from hero")
	check(service.companion_action == "hit" or service.companion_hurt_left > 0,"companion must react to damage")
	fresh()
	service.companion_foot = Vector2(22,4)
	arena.foot = Vector2(21,4)
	service.hostile_projectiles.append({"foot":Vector2(24,4),"velocity":Vector2(-4,0),"z":0.7,"damage":20,"life":3,"owner":"projectile-test"})
	service.set_companion("guard")
	advance(0.55)
	check(service.companion_hp == 120 and arena.knight.health == 100 and service.hostile_projectiles.is_empty(),"nearest party body must intercept a hostile projectile exactly once")
	fresh()
	service.companion_foot = Vector2(20,4)
	service.companion_hp = 80
	service.set_companion("follow")
	arena.knight.health = 35
	advance(0.15)
	check(arena.knight.health == 35 and service.companion_mp < 63,"healing must spend MP before an interruptible cast, not instantly restore HP")
	advance(0.2)
	check(arena.knight.health == 75 and service.companion_hp == 80,"healer must heal the lower-ratio nearby party member by 40 HP")
	var healing_cd: float = service.companion_heal_cooldown
	arena.knight.health = 20
	advance(0.7)
	check(arena.knight.health == 20 and service.companion_heal_cooldown > 6 and service.companion_heal_cooldown < healing_cd,"healing cooldown must prevent free repeated casts")
	fresh()
	service.companion_foot = Vector2(20,4)
	service.companion_mp = 0
	service.companion_hp = 30
	service.set_companion("follow")
	advance(0.8)
	check(service.companion_hp == 30 and service.companion_heal_cooldown == 0,"not enough MP must block healing")
	fresh()
	service.companion_foot = Vector2(20,4)
	service.companion_hp = 90
	service.set_companion("follow")
	enemy = one("melee",Vector2(23,4))
	enemy.state = "recover"
	enemy.timer = 99
	advance(0.3)
	check(service.companion_shield == 38 and service.companion_mp < 57 and service.companion_ward_cooldown > 11,"ward must spend MP and grant a timed, finite shield")
	check(service.damage_companion(20,Vector2(23,4)) == 0 and service.companion_shield == 18 and service.companion_hp == 90,"shield must absorb only its remaining capacity")
	service.companion_invuln_left = 0
	check(service.damage_companion(30,Vector2(23,4)) == 12 and service.companion_shield == 0 and service.companion_hp == 78,"damage exceeding shield must reach independent HP")
	fresh()
	service.companion_foot = Vector2(21,4)
	service.set_companion("follow")
	enemy = one("melee",Vector2(22,4))
	enemy.state = "recover"
	enemy.timer = 99
	advance(0.28)
	check(service.companion_action == "attack1","support bolt must have a visible attack windup")
	service.damage_companion(10,Vector2(22,4))
	advance(0.35)
	check(enemy.hp == enemy.max_hp and service.companion_projectiles.is_empty(),"taking damage must interrupt an unreleased companion cast")
	service.companion_invuln_left = 0
	service.damage_companion(999,Vector2(22,4))
	check(service.companion_dead and service.companion_hp == 0 and service.companion_action == "dead","lethal damage must down Serin")
	service.set_companion("guard")
	service.set_companion_enabled(false)
	service.set_companion_enabled(true)
	check(service.companion_dead and service.companion_hp == 0,"mode, dismissal, and recruitment toggles must not revive a fallen companion")
	advance(3)
	check(enemy.hp == enemy.max_hp and service.companion_action == "dead","fallen companion must stop all autonomous attacks and spells")
	var fallen: Dictionary = service.companion_snapshot()
	check(service.restore_companion(JSON.parse_string(JSON.stringify(fallen))) and service.companion_dead,"JSON save must preserve defeat and never refill companion HP")
	var invalid_ally: Dictionary = fallen.duplicate(true)
	invalid_ally.hp = service.COMPANION_MAX_HP+1
	check(not service.restore_companion(invalid_ally) and service.companion_hp == 0,"invalid resource values must reject atomically")
	invalid_ally = fallen.duplicate(true)
	invalid_ally.dead = false
	check(not service.restore_companion(invalid_ally) and service.companion_dead,"contradictory dead/HP state must reject")
	check(service.rest_companion() and not service.companion_dead and service.companion_hp == service.COMPANION_MAX_HP and service.companion_mp == service.COMPANION_MAX_MP,"explicit town rest must revive and restore both resources")
	check(not service.rest_companion(),"resting a completely refreshed companion must not report a healing need")
	service.companion_hp = 77
	service.companion_mp = 31
	service.companion_heal_cooldown = 4.2
	service.companion_ward_cooldown = 8.3
	var wounded: Dictionary = service.companion_snapshot()
	check(service.restore_companion(JSON.parse_string(JSON.stringify(wounded))) and service.companion_hp == 77 and service.companion_mp == 31 and is_equal_approx(service.companion_heal_cooldown,4.2),"HP/MP and class cooldowns must roundtrip without resetting")
	var paused: Dictionary = service.companion_snapshot()
	service.step(0.0)
	check(service.companion_snapshot() == paused,"zero simulation time must not regenerate resources or advance cooldowns")
	# A spell is born at its authored hand/staff tip, in the same coordinates
	# before and after lossless texture cropping. Its initial sweep still covers
	# nearby targets and obstacles between the caster body and the muzzle.
	fresh()
	service._spell_clips = {"serin":{"pivot":[300,600],"emitter":[540,360],"scale":0.5,"storage_crop":[100,100,600,650]},"caster":{"pivot":[300,600],"emitter":[540,360],"scale":0.5}}
	var socket: Dictionary = service._projectile_socket("serin",Vector2(21,4),1,0.8)
	check(socket.foot.is_equal_approx(Vector2(22,4)) and is_equal_approx(socket.z,1.0),"authored emitter must map from original image pixels to world units")
	var reflected: Dictionary = service._projectile_socket("serin",Vector2(21,4),-1,0.8)
	check(reflected.foot.is_equal_approx(Vector2(20,4)) and is_equal_approx(reflected.z,1.0),"facing mirrors emitter x around the fixed foot, never its height")
	check(service._projectile_direction(Vector2(21,4),Vector2(22,4),Vector2(21.5,4)).x > 0,"point-blank targets must not reverse a bolt behind its muzzle")
	service.companion_foot = Vector2(21,4)
	service.companion_facing = 1
	service.set_companion("guard")
	enemy = one("melee",Vector2(21.5,4))
	enemy.state = "recover"
	enemy.timer = 99
	service.companion_cast = "bolt"
	service.companion_target_id = enemy.id
	service._resolve_companion_cast()
	check(service.companion_projectiles.size() == 1 and service.companion_projectiles[0].foot == Vector2(22,4),"holy bolt must start at the authored staff tip")
	var launched: Dictionary = service.snapshot()
	check(service.restore(JSON.parse_string(JSON.stringify(launched))) and service.companion_projectiles[0].get("launch_from") == Vector2(21,4),"save roundtrip preserves a pending initial projectile sweep")
	var invalid_launch: Dictionary = launched.duplicate(true)
	invalid_launch.companion_projectiles[0].launch_from = ["bad",4]
	check(not service.restore(invalid_launch),"invalid pending launch origin rejects before changing combat")
	service._step_companion_projectiles(1.0/60)
	check(service.enemies[0].hp < service.enemies[0].max_hp and service.companion_projectiles.is_empty(),"launch sweep must hit a close enemy that is already behind the staff tip")
	fresh()
	enemy = one("melee",Vector2(23,4))
	arena.volumes.append({"id":"muzzle-wall","kind":"wall","x":21.4,"depth":3,"width":0.2,"depth_size":2,"base_z":0,"height":3,"solid":true,"standable":false})
	service.companion_projectiles.append({"foot":Vector2(22,4),"launch_from":Vector2(21,4),"velocity":Vector2(7,0),"z":1.0,"damage":18,"life":0.85})
	service._step_companion_projectiles(0.2)
	check(enemy.hp == enemy.max_hp and service.companion_projectiles.is_empty(),"staff tip beyond a wall must not bypass launch collision")
	fresh()
	arena.foot = Vector2(23.5,4)
	enemy = one("ranged",Vector2(24,4))
	enemy.aim = arena.foot
	enemy.attack_facing = -1
	enemy.attack_variant = "ranged"
	service._resolve_attack(enemy)
	check(service.hostile_projectiles[0].foot == Vector2(23,4) and is_equal_approx(service.hostile_projectiles[0].z,1.0),"hostile caster uses its own mirrored spell socket")
	service._step_projectiles(1.0/60)
	check(arena.knight.health == 92 and service.hostile_projectiles.is_empty(),"hostile launch sweep must hit a close party member exactly once")
	fresh()
	service.companion_smite_cooldown=0
	service.companion_foot=Vector2(20,4)
	service.set_companion("follow")
	var cluster: Array=[]
	for point in [Vector2(22,4),Vector2(22.5,4.3),Vector2(24,7)]:
		var member: Dictionary=one("elite",point)
		member.state="recover"
		member.timer=99
		cluster.append(member)
	service._step_companion(.01)
	check(service.companion_cast=="smite" and service.companion_mp<59,"AI selects area spell and pays MP")
	check(cluster[0].hp==cluster[0].max_hp,"Area spell has windup")
	service._step_companion(.25)
	check(cluster[0].hp<cluster[0].max_hp and cluster[1].hp<cluster[1].max_hp and cluster[2].hp==cluster[2].max_hp,"Area spell hits cluster but not distant enemy")
	var hp_after: float=cluster[0].hp
	service._step_companion(.1)
	check(cluster[0].hp==hp_after,"Area damage resolves once")
	service._step_companion(.4)
	check(service.companion_cast=="bolt" and service.companion_smite_cooldown>7,"Bolt fills area cooldown")
	var saved: Dictionary=service.companion_snapshot()
	check(service.restore_companion(saved) and service.companion_smite_cooldown>7,"Area cooldown persists")
	saved.erase("smite_cooldown")
	check(service.restore_companion(saved) and service.companion_smite_cooldown==0,"Old saves migrate")
	service.companion_action="stand"
	service.companion_mp=0
	service.companion_cooldown=0
	service._step_companion(.01)
	check(service.companion_cast=="bolt","Low MP falls back to bolt")
	service.companion_action="stand"
	service.companion_mp=80
	service.set_companion("passive")
	service._step_companion(.3)
	check(service.companion_smite_cooldown==0,"Passive mode blocks area spell")
	for error in failures:
		push_error(error)
	print("ENCOUNTERS_TEST ","PASS" if failures.is_empty() else "FAIL", " · waves/save/rewards, collision, Serin HP/MP/targeting/heal/ward/interrupt/death/revive/persistence")
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
