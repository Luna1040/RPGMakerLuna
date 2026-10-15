extends "res://street_3d.gd"
const Creatures = preload("res://creatures_3d.gd")
const AREAS = [Rect2(-15,-12,30,24),Rect2(-40,-10,25,26),Rect2(15,-12,25,24),Rect2(-14,12,28,26)]
const SPAWNS = [["野猫",3,Vector3(-22,0,3),false],["蛤蟆",5,Vector3(-29,0,8),false],["狐狸",7,Vector3(-35,0,1),false],["野猪",11,Vector3(32,0,-4),false],["狂牛",10,Vector3(24,0,5),false],["灰狼",12,Vector3(-3,0,25),true]]
var monsters: Array[Dictionary] = []
var selected_monster := -1
var glide_remaining := 0.0
var glide_direction := Vector3.FORWARD
var meditating := false
var healing_fraction := 0.0
var lightness := false
var lightness_remaining := 0.0
var active_lightness := "lightness"
var learned_skills: Array[String]=["attack","potion"]
var skill_slots: Array[String]=["attack","","","","","","","",""]
var kungfu_fx: Node3D
var hunt_kills := 0
var region := "泫渤派城"

func build_world() -> void:
	build_town_core()
	monsters.clear()
	# Replace the sealed perimeter with three physically open gateways.
	for child in world.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			var size: Vector3 = child.mesh.size
			if size==Vector3(30,1.6,0.3) or size==Vector3(0.3,1.6,24): child.free()
	wall(Vector3(0,0.8,-11.8),Vector3(30,1.6,0.3))
	for x in [-14.8,14.8]:
		var gate_z := 3.0 if x<0 else 0.0
		var lo := gate_z-2.4
		var hi := gate_z+2.4
		wall(Vector3(x,0.8,(-12+lo)/2),Vector3(0.3,1.6,lo+12))
		wall(Vector3(x,0.8,(12+hi)/2),Vector3(0.3,1.6,12-hi))
		gate(Vector3(x,0,gate_z),"西门 · 野猫 / 蛤蟆 / 狐狸" if x<0 else "东门 · 狂牛 / 野猪",true)
	for x in [-8.75,8.75]: wall(Vector3(x,0.8,11.8),Vector3(12.5,1.6,0.3))
	gate(Vector3(0,0,11.8),"南门 · 灰狼主动攻击",false)
	var grass := load_grass()
	for i in range(1,4):
		var area: Rect2 = AREAS[i]
		var center := area.get_center()
		Models.box(world,Vector3(center.x,-0.20,center.y),Vector3(area.size.x,0.4,area.size.y),Color("8daa79"),1)
		if grass!=null:
			var plane := PlaneMesh.new()
			plane.size=area.size
			var surface := Models.mesh_node(world,plane,Vector3(center.x,0.025,center.y),Color.WHITE)
			surface.name="GeneratedWildGrass%d" % i
			surface.material_override=grass
		# Readable winding dirt paths; these remain modeled geometry.
		var horizontal := i<3
		Models.box(world,Vector3(center.x,0.035,3 if i==1 else 0 if i==2 else center.y),Vector3(area.size.x,0.03,2.8) if horizontal else Vector3(3,0.03,area.size.y),Color("756d52"))
	for at in [Vector3(-20,0,-6),Vector3(-31,0,-5),Vector3(-37,0,12),Vector3(-24,0,12),Vector3(20,0,-8),Vector3(36,0,8),Vector3(30,0,9),Vector3(-10,0,19),Vector3(9,0,23),Vector3(8,0,33),Vector3(-10,0,34)]:
		Models.tree(world,at)
		obstacles.append(Rect2(at.x-0.65,at.z-0.65,1.3,1.3))
	for at in [Vector3(-27,0,1),Vector3(27,0,-5),Vector3(4,0,28)]:
		Models.box(world,at+Vector3(0,0.45,0),Vector3(1.8,0.9,1.5),Color("80938d"),2)
		obstacles.append(Rect2(at.x-0.9,at.z-0.75,1.8,1.5))
	# Outer boundary collision; the remaining cross-shaped edges are also blocked in navigation.
	for x in [-40.1,40.1]: wall(Vector3(x,0.6,2),Vector3(0.25,1.2,30))
	wall(Vector3(0,0.6,38.1),Vector3(28,1.2,0.25))
	for spec in SPAWNS: spawn_monster(spec)
	Textures.apply_building(world)

func build_town_core() -> void:
	super.build_world()

func wall(at: Vector3, size: Vector3) -> void:
	Models.box(world,at,size,Color("b7aa8b"),2).set_meta("material_kind","wall")
	obstacles.append(Rect2(at.x-size.x/2,at.z-size.z/2,size.x,size.z))

func gate(at: Vector3, title: String, sideways: bool) -> void:
	var holder := Node3D.new()
	holder.position=at
	holder.rotation.y=PI/2 if sideways else 0
	world.add_child(holder)
	for x in [-2.55,2.55]:
		Models.box(holder,Vector3(x,1.4,0),Vector3(0.42,2.8,0.6),Color("977651"),2).set_meta("material_kind","wood")
	Models.roof(holder,Vector3(0,2.8,0),6.5,1.7,0.9,Color("63898b"))
	Models.caption(holder,title,Vector3(0,3.65,0),FONT,28)

func load_grass() -> Material:
	return Textures.surface("wild-grass")

func spawn_monster(spec: Array) -> void:
	var body := CharacterBody3D.new()
	body.name="WildMonster%d" % monsters.size()
	body.position=spec[2]+Vector3(0,0.05,0)
	body.collision_layer=4
	body.collision_mask=11
	body.floor_snap_length=0.5
	body.set_meta("kind","monster:%d" % monsters.size())
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=0.36
	capsule.height=1.25
	shape.shape=capsule
	shape.position.y=0.625
	body.add_child(shape)
	world.add_child(body)
	var model_id := ["野猫","蛤蟆","狐狸","野猪","狂牛","灰狼"].find(spec[0])
	var file := "res://assets/3d/monster_%d.tscn" % model_id
	var visual: Node3D
	if FileAccess.file_exists("res://assets/client-wild/MOB10001.glb"):
		visual=preload("res://client_creature_rig.gd").make(body,spec[0])
	elif FileAccess.file_exists(file):
		visual=(load(file) as PackedScene).instantiate()
		body.add_child(visual)
	else: visual=Creatures.make(body,spec[0])
	var title := Models.caption(body,"%s Lv.%d · %s" % [spec[0],spec[1],"主动" if spec[3] else "被动"],Vector3(0,1.65,0),FONT,20)
	title.pixel_size=0.0045
	title.outline_size=2
	if visual.has_meta("height"): title.position.y=float(visual.get_meta("height"))+0.2
	var health: float = 35.0+spec[1]*12
	monsters.append({"body":body,"visual":visual,"species":spec[0],"level":spec[1],"aggressive":spec[3],"hp":health,"max_hp":health,"home":body.position,"aggro":false,"dead":false,"respawn":0.0,"cool":0.0,"wind":0.0,"aim":Vector3.ZERO,"path":PackedVector2Array(),"path_index":0,"repath":0.0})
	monsters.back().merge({"wander_target":body.position,"wander_wait":randf_range(0.5,3.5),"wander_radius":3.5,"wander_speed":randf_range(0.65,1.05)})

func build_navigation() -> void:
	grid.region=Rect2i(-79,-23,159,99)
	grid.cell_size=Vector2(CELL,CELL)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for x in range(-79,80):
		for z in range(-23,76):
			var point := Vector2(x,z)*CELL
			var solid := not walkable(point)
			for obstacle in obstacles:
				if obstacle.grow(0.42).has_point(point): solid=true
			for actor in town_actors.values()+[practice]:
				if point.distance_to(Vector2(actor.position.x,actor.position.z))<0.8: solid=true
			grid.set_point_solid(Vector2i(x,z),solid)

func walkable(point: Vector2) -> bool:
	for area in AREAS:
		if area.has_point(point): return true
	return false

func free_cell(at: Vector3) -> Vector2i:
	var desired := cell_for(at)
	desired.x=clampi(desired.x,-79,79)
	desired.y=clampi(desired.y,-23,75)
	if not grid.is_point_solid(desired): return desired
	for radius in range(1,12):
		var best := desired
		var distance := INF
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				var id := desired+Vector2i(x,z)
				if grid.is_in_boundsv(id) and not grid.is_point_solid(id):
					var d := Vector2(id-desired).length()
					if d<distance: distance=d; best=id
		if distance<INF: return best
	return Vector2i(0,7)

func reset_game() -> void:
	super.reset_game()
	meditating=false
	lightness=false
	lightness_remaining=0.0
	active_lightness="lightness"
	learned_skills.assign(["attack","potion"])
	selected_monster=-1
	glide_remaining=0.0
	skill_slots.assign(["attack","","","","","","","",""])
	healing_fraction=0
	hunt_kills=0
	region="泫渤派城"
	runtime.zone=region+" · 3D"
	for mob in monsters: reset_monster(mob)

func reset_monster(mob: Dictionary) -> void:
	mob.hp=mob.max_hp
	mob.dead=false
	mob.aggro=false
	mob.respawn=0.0
	mob.cool=0.0
	mob.wind=0.0
	mob.path=PackedVector2Array()
	mob.body.position=mob.home
	mob.body.velocity=Vector3.ZERO
	mob.wander_target=mob.home
	mob.wander_wait=randf_range(0.5,3.5)
	mob.body.visible=true
	mob.body.collision_layer=4
	mob.body.get_child(0).disabled=false

func snapshot() -> Dictionary:
	var data := super.snapshot()
	var records: Array = []
	for mob in monsters: records.append({"hp":mob.hp,"dead":mob.dead,"respawn":mob.respawn})
	data["wilderness"]={"version":1,"lightness":lightness,"kills":hunt_kills,"monsters":records}
	data["kungfu"]={"learned":learned_skills.duplicate(),"slots":skill_slots.duplicate(),"remaining":lightness_remaining if lightness else 0.0,"active":active_lightness}
	return data

func restore(data: Dictionary) -> void:
	selected_monster=-1
	glide_remaining=0.0
	meditating=false
	learned_skills.assign(["attack","potion"])
	skill_slots.assign(["attack","","","","","","","",""])
	super.restore(data)
	legacy_archive.erase("wilderness")
	var saved: Dictionary=data.get("wilderness",{})
	lightness=bool(saved.get("lightness",false)) and level>=5
	var kungfu: Dictionary=data.get("kungfu",{})
	for id in kungfu.get("learned",[]):
		if preload("res://kungfu_data.gd").DATA.has(id) and not id in learned_skills: learned_skills.append(id)
	if lightness and not "lightness" in learned_skills: learned_skills.append("lightness")
	var slots: Array=kungfu.get("slots",[])
	if slots.size()==9:
		for i in range(9): skill_slots[i]=slots[i] if slots[i] in learned_skills else ""
	active_lightness=str(kungfu.get("active","lightness"))
	if active_lightness=="cloud_step": kungfu=kungfu.duplicate(); kungfu.remaining=0; active_lightness="lightness"
	if not active_lightness in ["lightness","cloud_step"]: active_lightness="lightness"
	lightness_remaining=clampf(float(kungfu.get("remaining",60.0 if lightness else 0.0)),0,60)
	lightness=lightness_remaining>0 and active_lightness in learned_skills and level>=preload("res://kungfu_data.gd").DATA[active_lightness].level
	hunt_kills=int(saved.get("kills",0))
	var records: Array=saved.get("monsters",[])
	for i in range(mini(records.size(),monsters.size())):
		var mob := monsters[i]
		var record: Dictionary=records[i]
		mob.hp=clampf(float(record.get("hp",mob.max_hp)),0,mob.max_hp)
		mob.dead=bool(record.get("dead",false)) or mob.hp<=0
		mob.respawn=clampf(float(record.get("respawn",12)),0.1,12) if mob.dead else 0.0
		mob.body.visible=not mob.dead
		mob.body.collision_layer=0 if mob.dead else 4
		mob.body.get_child(0).disabled=mob.dead
	hp=clampf(hp,0,max_hp())
	update_region()
	update_camera(1,true)

func max_hp() -> float:
	return 120+(level-1)*25

func attack_power() -> int:
	return 24+(level-1)*5

func defense_power() -> int:
	return 2+(level-1)*2

func xp_needed() -> int:
	return 80+(level-1)*30

func gain_experience(amount: int) -> void:
	exp_points+=amount
	var upgraded := false
	while level<99 and exp_points>=xp_needed():
		exp_points-=xp_needed()
		level+=1
		hp=max_hp()
		upgraded=true
	if level==99: exp_points=mini(exp_points,xp_needed())
	if upgraded:
		message="升级至 %d！生命 +25 · 攻击 +5 · 防御 +2%s" % [level," · 可修习轻功提纵术，Shift 施展" if level>=5 else ""]

func movement_speed() -> float:
	return 7.2 if lightness and level>=5 else 3.6

func begin_leap() -> void:
	if lightness:
		lightness=false
		lightness_remaining=0.0
		message="轻功已关闭。"
		return
	if not "lightness" in learned_skills and not learn_skill("lightness"): return
	use_skill("lightness")

func learn_skill(id: String) -> bool:
	var data: Dictionary=preload("res://kungfu_data.gd").DATA
	if not data.has(id) or level<int(data[id].level):
		message="尚未达到修习等级。"
		return false
	if not id in learned_skills: learned_skills.append(id)
	return true

func assign_skill(index: int, id: String) -> bool:
	if index<0 or index>=9 or (not id.is_empty() and not id in learned_skills): return false
	skill_slots[index]=id
	return true

func use_skill(id: String) -> bool:
	if hp<=0 or active_slot==0 or not id in learned_skills: return false
	var data: Dictionary=preload("res://kungfu_data.gd").DATA
	if not data.has(id) or level<int(data[id].level): return false
	if id=="potion":
		if potions<=0 or hp>=max_hp(): return false
		potions-=1
		hp=minf(max_hp(),hp+60)
		message="使用小金创药 · 恢复 60 生命"
		return true
	if id=="cloud_step":
		meditating=false
		click_target=""
		glide_direction=Vector3(sin(hero_model.root.rotation.y),0,cos(hero_model.root.rotation.y))
		if route_index<route.size():
			var point: Vector2=route[route.size()-1]
			glide_direction=Vector3(point.x-hero.position.x,0,point.y-hero.position.z).normalized()
		route.clear()
		glide_remaining=0.9
		if is_instance_valid(kungfu_fx): kungfu_fx.cast(id)
		message="梯云纵 · 两段滑翔 · 可立即再次施展"
		return true
	if id=="attack":
		if selected_monster>=0 and selected_monster<monsters.size() and not monsters[selected_monster].dead:
			if attack_cd>0: return false
			navigate_to_actor(monsters[selected_monster].body,"monster:%d" % selected_monster)
			if hero.position.distance_to(monsters[selected_monster].body.position)<=1.8: attack_monster(selected_monster)
			return true
		if attack_cd>0: return false
		var nearest := -1
		var distance := 1.8
		for i in range(monsters.size()):
			var d: float=hero.position.distance_to(monsters[i].body.position)
			if not monsters[i].dead and d<distance: nearest=i; distance=d
		if nearest>=0: attack_monster(nearest)
		elif enemy_health>0 and hero.position.distance_to(practice.position)<1.8: attack_practice()
		else:
			attack_cd=0.55
			slash_remaining=0.38
			message="普通攻击 · 靠近或选中敌人可命中。"
		return true
	active_lightness=id
	lightness=true
	lightness_remaining=60.0
	meditating=false
	leap_remaining=0.8
	message="%s · 持续 60 秒 · 移动速度为基础的两倍" % data[id].name
	if is_instance_valid(kungfu_fx): kungfu_fx.cast(id)
	return true

func toggle_meditation() -> void:
	if hp<=0: return
	if meditating:
		meditating=false
		message="结束打坐。"
	else:
		meditating=true
		lightness=false
		lightness_remaining=0.0
		route.clear()
		click_target=""
		leap_remaining=0
		hero.velocity=Vector3.ZERO
		message="正在原地打坐 · 持续恢复生命；受击不中断，主动行动结束。"

func _unhandled_input(event: InputEvent) -> void:
	if not paused and not menu.visible and not dialogue.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_C and event.ctrl_pressed:
			toggle_meditation()
			get_viewport().set_input_as_handled()
			return
		if event.keycode==KEY_R and hp<=0:
			hp=max_hp()
			hero.position=Vector3(0,0.05,3.5)
			hero.velocity=Vector3.ZERO
			route.clear()
			click_target=""
			meditating=false
			update_region()
			for mob in monsters: mob.aggro=false; mob.wind=0.0
			message="已回城疗伤 · 等级、经验与任务保留。"
			return
	super._unhandled_input(event)

func navigate_to(at: Vector3, target: String="") -> void:
	meditating=false
	for mob in monsters:
		if not mob.dead and Vector2(at.x,at.z).distance_to(Vector2(mob.body.position.x,mob.body.position.z))<0.9:
			var away: Vector3 = hero.position-mob.body.position
			away.y=0
			if away.length()<0.1: away=Vector3.RIGHT
			at=mob.body.position+away.normalized()*1.35
	var blocked := block_creatures()
	super.navigate_to(at,target)
	for id in blocked: grid.set_point_solid(id,false)

func navigate_to_actor(actor: Node3D, kind: String) -> void:
	meditating=false
	var blocked := block_creatures()
	super.navigate_to_actor(actor,kind)
	for id in blocked: grid.set_point_solid(id,false)

func block_creatures() -> Array[Vector2i]:
	var changed: Array[Vector2i]=[]
	var start := cell_for(hero.position)
	for mob in monsters:
		if mob.dead: continue
		var center := cell_for(mob.body.position)
		for x in range(-2,3):
			for z in range(-2,3):
				var id := center+Vector2i(x,z)
				if id==start or not grid.is_in_boundsv(id) or grid.is_point_solid(id): continue
				if (Vector2(id)*CELL).distance_to(Vector2(mob.body.position.x,mob.body.position.z))<0.8:
					grid.set_point_solid(id,true)
					changed.append(id)
	return changed

func click_world(point: Vector2) -> void:
	if paused or ui_at(point): return
	var hit := pick_at(point)
	if not hit.is_empty():
		var kind: String=hit.collider.get_meta("kind","")
		if kind.begins_with("monster:"):
			var id := int(kind.substr(8))
			select_monster(id)
			return
	selected_monster=-1
	super.click_world(point)

func select_monster(id: int) -> void:
	if id<0 or id>=monsters.size() or monsters[id].dead: return
	if selected_monster==id:
		navigate_to_actor(monsters[id].body,"monster:%d" % id)
	else:
		selected_monster=id
		click_target=""
		route.clear()
		hero.velocity=Vector3.ZERO
		message="选中 %s · 再次点击或使用普通攻击发起攻击" % monsters[id].species
	queue_redraw()

func ui_at(point: Vector2) -> bool:
	return Rect2(25,168,780,38).has_point(point) or super.ui_at(point)

func attack_monster(id: int) -> void:
	if id<0 or id>=monsters.size() or attack_cd>0 or hp<=0: return
	var mob := monsters[id]
	if mob.dead or hero.position.distance_to(mob.body.position)>1.8: return
	meditating=false
	attack_cd=0.55
	slash_remaining=0.38
	var delta: Vector3=mob.body.position-hero.position
	hero_model.root.rotation.y=atan2(delta.x,delta.z)
	mob.aggro=true
	mob.hp=maxf(0,mob.hp-attack_power())
	message="攻击 %s · 伤害 %d · 剩余生命 %d" % [mob.species,attack_power(),mob.hp]
	if mob.hp<=0:
		mob.dead=true
		if selected_monster==id: selected_monster=-1
		mob.aggro=false
		mob.wind=0.0
		mob.respawn=12.0
		mob.body.hide()
		mob.body.collision_layer=0
		mob.body.get_child(0).set_deferred("disabled",true)
		hunt_kills+=1
		coins+=mob.level*2
		click_target=""
		var reward: int=mob.level*22
		message="击败 %s · 经验 +%d · 镰银 +%d · 12 秒后刷新" % [mob.species,reward,mob.level*2]
		gain_experience(reward)

func update_region() -> void:
	region="西郊 · 青草坡" if hero.position.x < -15 else "东郊 · 野牛林" if hero.position.x>15 else "南郊 · 灰狼谷" if hero.position.z>12 else "泫渤派城"
	runtime.zone=region+" · 3D"

func _process(dt: float) -> void:
	super._process(dt)
	if hero==null or paused or menu.visible or active_slot==0 or dialogue.visible: return
	if glide_remaining>0:
		var glide_phase: float=0.9-glide_remaining
		hero_model.root.position.y=0.55*sin(PI*fmod(glide_phase,0.45)/0.45)
	update_region()
	if lightness:
		lightness_remaining=maxf(0.0,lightness_remaining-dt)
		if lightness_remaining<=0:
			lightness=false
			message="轻功效果结束 · 已恢复基础移动速度。"
	if hp<=0:
		lightness=false
		lightness_remaining=0.0
		message="你已倒下 · 按 R 回城疗伤，等级与任务保留。"
		return
	if meditating:
		healing_fraction+=max_hp()*0.06*dt
		if healing_fraction>=1:
			var restored := floorf(healing_fraction)
			hp=minf(max_hp(),hp+restored)
			healing_fraction-=restored
	if click_target.begins_with("monster:"):
		var id := int(click_target.substr(8))
		var mob := monsters[id]
		if mob.dead: click_target=""
		elif hero.position.distance_to(mob.body.position)<=1.8:
			route.clear()
			attack_monster(id)
		elif route_index>=route.size(): navigate_to_actor(mob.body,click_target)
	for mob in monsters:
		update_monster(mob,dt)
		if not mob.dead and mob.visual.has_method("animate"):
			var speed := Vector2(mob.body.velocity.x,mob.body.velocity.z).length()
			mob.visual.animate(speed,1.0-mob.wind/0.55 if mob.wind>0 else -1.0,dt)
	if meditating:
		hero_model.root.position.y=-0.55
		hero_model.robe.scale.y=0.62
		hero_model.left_leg.position=Vector3(-0.13,0.64,0.35)
		hero_model.right_leg.position=Vector3(0.13,0.64,0.35)
		hero_model.left_leg.rotation=Vector3(0,0,-PI/2)
		hero_model.right_leg.rotation=Vector3(0,0,PI/2)
		hero_model.right_arm.position.y=1.2
		hero_model.left_arm.rotation.z=0.6
		hero_model.right_arm.rotation=Vector3(-0.35,0,-0.6)
	else:
		hero_model.robe.scale.y=1
		hero_model.right_arm.position.y=1.35
		hero_model.left_leg.position=Vector3(-0.15,0.26,0)
		hero_model.right_leg.position=Vector3(0.15,0.26,0)
		hero_model.left_leg.rotation.z=0
		hero_model.right_leg.rotation.z=0
		hero_model.left_arm.rotation.z=0
		hero_model.right_arm.rotation.z=0
	for title in ["BootLeft","BootRight"]:
		var boot: Node3D=hero_model.root.get_node_or_null(title)
		if boot!=null:
			boot.position.y=0.64 if meditating else 0.09
			boot.position.z=0.4 if meditating else 0.07

func attack_practice() -> void:
	meditating=false
	super.attack_practice()

func update_monster(mob: Dictionary, dt: float) -> void:
	if mob.dead:
		mob.respawn-=dt
		if mob.respawn<=0: reset_monster(mob)
		return
	mob.cool=maxf(0,mob.cool-dt)
	var distance: float=hero.position.distance_to(mob.body.position)
	if mob.aggressive and distance<7 and hero.position.z>12: mob.aggro=true
	if mob.aggro and mob.body.position.distance_to(mob.home)>11:
		mob.aggro=false
		mob.hp=mob.max_hp
	if mob.wind>0:
		mob.body.velocity=Vector3.ZERO
		mob.wind-=dt
		if mob.wind<=0:
			if hero.position.distance_to(mob.aim)<1.8:
				hp=maxf(0,hp-maxi(1,mob.level*2+5-defense_power()))
			mob.cool=1.4
		return
	mob.visual.rotation.x=0
	if mob.aggro and distance<1.6 and mob.cool<=0:
		mob.wind=0.55
		mob.aim=hero.position
		mob.path=PackedVector2Array()
		return
	var destination: Vector3=hero.position if mob.aggro else mob.home
	if not mob.aggro and mob.body.position.distance_to(mob.home)<4.5:
		mob.wander_wait-=dt
		if mob.wander_wait>0:
			mob.body.velocity=Vector3.ZERO
			mob.path=PackedVector2Array()
			return
		if mob.body.position.distance_to(mob.wander_target)<0.3 and not mob.path.is_empty():
			mob.wander_wait=randf_range(1.5,4.0)
			mob.body.velocity=Vector3.ZERO
			mob.path=PackedVector2Array()
			return
		if mob.body.position.distance_to(mob.wander_target)<0.3:
			for attempt in range(12):
				var angle := randf()*TAU
				var offset := Vector3(sin(angle),0,cos(angle))*randf_range(1.0,mob.wander_radius)
				var candidate: Vector3=mob.home+offset
				var cell := cell_for(candidate)
				if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
					mob.wander_target=Vector3(cell.x*CELL,mob.home.y,cell.y*CELL)
					mob.repath=0.0
					break
		destination=mob.wander_target
	if mob.body.position.distance_to(destination)<(1.35 if mob.aggro else 0.15):
		if not mob.aggro: mob.wander_wait=randf_range(1.5,4.0)
		mob.body.velocity=Vector3.ZERO
		mob.path=PackedVector2Array()
		return
	mob.repath-=dt
	if mob.repath<=0:
		mob.repath=0.6
		mob.path=grid.get_point_path(free_cell(mob.body.position),free_cell(destination))
		mob.path_index=0

func _physics_process(dt: float) -> void:
	if menu!=null and menu.visible: return
	if glide_remaining>0 and not paused and not menu.visible and not dialogue.visible and hp>0:
		glide_remaining=maxf(0,glide_remaining-dt)
		var phase: float=0.9-glide_remaining
		var speed: float=34.0 if phase<0.38 or phase>0.5 else 8.0
		var motion: Vector3=glide_direction*speed*dt
		var next: Vector3=hero.position+motion
		if not walkable(Vector2(next.x,next.z)) or grid.is_point_solid(cell_for(next)):
			glide_remaining=0
			hero.velocity=Vector3.ZERO
		else:
			hero.velocity=glide_direction*speed
			hero.velocity.y=-0.2
			step_up(motion)
			hero.move_and_slide()
			hero_model.root.position.y=0.55*sin(PI*fmod(phase,0.45)/0.45)
	elif not meditating: super._physics_process(dt)
	if hero==null or paused or menu.visible or dialogue.visible or hp<=0 or active_slot==0: return
	# Hard ground bounds cover the cross-shaped world even when pushed by a creature.
	if not walkable(Vector2(hero.position.x,hero.position.z)):
		var safe := Vector2(free_cell(hero.position))*CELL
		hero.position=Vector3(safe.x,0.05,safe.y)
		hero.velocity=Vector3.ZERO
	for mob in monsters:
		if mob.dead or mob.wind>0: continue
		var body: CharacterBody3D=mob.body
		var direction := Vector3.ZERO
		if mob.path_index<mob.path.size():
			var point: Vector2=mob.path[mob.path_index]
			var delta := Vector3(point.x-body.position.x,0,point.y-body.position.z)
			if delta.length()<0.15: mob.path_index+=1
			else: direction=delta.normalized()*minf(2.4 if mob.aggro else mob.wander_speed,delta.length()/dt)
		if not mob.aggro and body.position.distance_to(mob.home)>mob.wander_radius+0.5 and direction.dot(mob.home-body.position)<0:
			direction=Vector3.ZERO
			mob.wander_target=mob.home
			mob.repath=0.0
		body.velocity=Vector3(direction.x,-0.2 if body.is_on_floor() else body.velocity.y-18*dt,direction.z)
		body.move_and_slide()
		if direction.length()>0.1:
			mob.visual.rotation.y=lerp_angle(mob.visual.rotation.y,atan2(direction.x,direction.z),dt*9)
			if not mob.visual.has_method("animate"):
				for i in range(4): mob.visual.get_node("Leg%d" % i).rotation.x=sin(elapsed*12+i*PI)*0.3

func map_position(at: Vector3) -> Vector2:
	return Vector2(1053,54)+Vector2((at.x+40)/80,(at.z+12)/50)*Vector2(180,130)

func map_areas() -> Array:
	return AREAS

func map_extent() -> Vector2:
	return Vector2(80,50)

func map_gates() -> Array:
	return [["西",Vector3(-14.8,0,3)],["东",Vector3(14.8,0,0)],["南",Vector3(0,0,11.8)]]

func _draw() -> void:
	if hero==null: return
	panel(Rect2(25,15,780,85))
	label_at(Vector2(45,48),"热血江湖 · 三门历练 / 3D",26,Color("f3cf88"))
	label_at(Vector2(45,81),"%s · %s · Lv.%d  镰银 %d  生命 %d" % [character.get("name","侠客"),Saves.display_profession(character.get("profession","刀客")),level,coins,hp],19)
	panel(Rect2(25,112,780,53))
	label_at(Vector2(43,144),message,17)
	for i in range(3): panel(Rect2(825,25+i*45,185,38))
	label_at(Vector2(838,50),"F6 · 名册 / 下线",18)
	label_at(Vector2(838,95),"F5 · 保存角色",18)
	label_at(Vector2(838,140),"Esc · 继续" if paused else "Esc · 暂停",18)
	panel(Rect2(1035,15,220,200))
	label_at(Vector2(1053,43),"实时地图 · 相机朝向",17,Color("f3cf88"))
	# Replace footer and map with the expanded world contract.
	panel(Rect2(25,690,1230,90))
	label_at(Vector2(45,718),"左键寻路 / 对话 / 攻击    右键旋转 · 滚轮缩放    Ctrl+C 打坐    Shift 轻功（5 级习得）",20)
	label_at(Vector2(45,750),"%s · 攻击 %d · 防御 %d · 轻功%s · 击杀 %d   5 级轻功提纵术 / 10 级梯云纵" % [region,attack_power(),defense_power(),"开启" if lightness else "关闭",hunt_kills],17,Color("a6c4bf"))
	panel(Rect2(25,168,780,38))
	bar(Vector2(42,181),Vector2(270,10),float(exp_points)/xp_needed(),Color("88bcb4"))
	label_at(Vector2(326,193),"经验 %d/%d  生命 %d/%d%s" % [exp_points,xp_needed(),hp,max_hp()," · 打坐中" if meditating else ""],17)
	draw_rect(Rect2(1053,54,180,130),Color("344d46"))
	for area in map_areas():
		var start := map_position(Vector3(area.position.x,0,area.position.y))
		draw_rect(Rect2(start,area.size/map_extent()*Vector2(180,130)),Color("789276"))
	for obstacle in obstacles:
		var a := map_position(Vector3(obstacle.position.x,0,obstacle.position.y))
		draw_rect(Rect2(a,obstacle.size/map_extent()*Vector2(180,130)),Color("b6ad90"))
	for title in town_actors:
		var npc_point := map_position(town_actors[title].position)
		draw_circle(npc_point,2,Color("f6d27c"))
		label_at(npc_point+Vector2(3,-3),"门" if title=="泫渤派门主" else title.left(1),9,Color("fff2cd"))
	for gate_data in map_gates():
		label_at(map_position(gate_data[1])+Vector2(-5,3),gate_data[0],11,Color.WHITE)
	for mob in monsters:
		if not mob.dead:
			draw_circle(map_position(mob.body.position),3,Color("f37469") if mob.aggressive or mob.aggro else Color("efbf74"))
			if monsters.find(mob)==selected_monster and not camera.is_position_behind(mob.body.position):
				var screen := camera.unproject_position(mob.body.position+Vector3(0,float(mob.visual.get_meta("height",1.0))+0.33,0))
				if Rect2(0,215,1280,470).has_point(screen): bar(screen-Vector2(25,0),Vector2(50,5),mob.hp/mob.max_hp,Color("dc9279"))
	var point := map_position(hero.position)
	draw_circle(point,3,Color("88f1f7"))
	var forward := Vector2(-sin(yaw),-cos(yaw))
	draw_line(point,point+forward*12,Color("fff7c6"),2)
	draw_line(point+forward*12,point+forward.rotated(0.5)*7,Color("fff7c6"),2)
	draw_line(point+forward*12,point+forward.rotated(-0.5)*7,Color("fff7c6"),2)
	label_at(Vector2(1053,203),"蓝 自己 · 金 NPC/被动 · 红 敌对",11)
	if enemy_health>0 and not camera.is_position_behind(practice.position):
		var screen := camera.unproject_position(practice.position+Vector3(0,2.3,0))
		if Rect2(0,215,1280,470).has_point(screen): bar(screen-Vector2(35,0),Vector2(70,6),enemy_health/100,Color("d77360"))
	if paused and not menu.visible:
		panel(Rect2(425,315,430,90))
		label_at(Vector2(470,370),"已暂停 · Esc 继续",28)
