extends "res://town_game.gd"

const Models = preload("res://models_3d.gd")
const Textures = preload("res://texture_materials.gd")
const CELL := 0.5
var world: Node3D
var hero: CharacterBody3D
var hero_model: Dictionary = {}
var master: StaticBody3D
var practice: StaticBody3D
var practice_model: Dictionary = {}
var camera: Camera3D
var marker: MeshInstance3D
var shadow: MeshInstance3D
var warning_ring: MeshInstance3D
var grid := AStarGrid2D.new()
var obstacles: Array[Rect2] = []
var route := PackedVector2Array()
var route_index := 0
var click_target := ""
var yaw := 0.0
var pitch := deg_to_rad(48.0)
var zoom := 13.0
var actual_zoom := 13.0
var camera_anchor := Vector3(0,1.3,3.5)
var dragging := false
var leap_remaining := 0.0
var leap_cd := 0.0
var slash_remaining := 0.0
var enemy_health := 100.0
var enemy_cooldown := 0.0
var enemy_windup := 0.0
var enemy_aim := Vector3.ZERO
var training_state := 0
var training_rewarded := false
var practice_hits := 0
var legacy_archive: Dictionary = {}
var runtime := {"zone":"泫渤派街区 · 3D"}
var map_generation := 0
var town_actors: Dictionary = {}
var dialogue: PanelContainer
var dialogue_portrait: TextureRect
var dialogue_text: Label

func _ready() -> void:
	build_world()
	build_navigation()
	super._ready()
	reset_game()
	paused = true
	build_dialogue()
	update_camera(1.0,true)

func build_world() -> void:
	map_generation += 1
	world = Node3D.new()
	world.name = "WuxiaStreet3D"
	add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("a6c9cc")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d9e8ef")
	settings.ambient_light_energy = 0.25
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-35,0)
	sun.light_color = Color("fff9f2")
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	world.add_child(sun)
	Models.box(world,Vector3(0,-0.2,0),Vector3(30,0.4,24),Color("7e9580"),1)
	# Instanced stone slabs have real thickness and do not participate in navigation collision.
	for x in range(-14,15):
		for z in range(-11,12):
			if abs(x) < 7 or abs(z) < 3:
				Models.box(world,Vector3(x+0.22*(posmod(z,2)),0.015,z),Vector3(0.94,0.03,0.94),Color("a6a895").darkened(posmod(x+z,4)*0.025))
	var stone_material := Textures.surface("stone")
	if stone_material != null:
		var pavement := PlaneMesh.new()
		pavement.size = Vector2(30,24)
		var textured_ground := Models.mesh_node(world,pavement,Vector3(0,0.041,0),Color.WHITE)
		textured_ground.name = "GeneratedStonePavement"
		textured_ground.material_override = stone_material
	var hall: Node3D = (load("res://assets/3d/hall.tscn") as PackedScene).instantiate()
	hall.position = Vector3(0,0,-6.6)
	world.add_child(hall)
	Textures.apply_building(hall)
	Models.caption(hall,"泫渤大殿",Vector3(0,3.25,2.65),FONT,29)
	var inn: Node3D = (load("res://assets/3d/inn.tscn") as PackedScene).instantiate()
	inn.position = Vector3(-8,0,-5)
	world.add_child(inn)
	Textures.apply_building(inn)
	Models.caption(inn,"香玉客栈",Vector3(0,3.25,2.4),FONT,29)
	obstacles.append(Rect2(-4,-9.6,8,6))
	obstacles.append(Rect2(-11,-7.6,6,5.2))
	# A courtyard wall is intentionally placed across a direct click route.
	Models.box(world,Vector3(-5,0.8,3),Vector3(0.5,1.6,5),Color("bdac8c"),2).set_meta("material_kind","wall")
	Models.box(world,Vector3(-5,1.65,3),Vector3(0.85,0.16,5.2),Color("506966"),2).set_meta("material_kind","roof")
	obstacles.append(Rect2(-5.45,0.4,0.9,5.2))
	for at in [Vector3(-12,0,6),Vector3(5,0,-7),Vector3(12,0,-6),Vector3(7,0,8)]:
		Models.tree(world,at)
		obstacles.append(Rect2(at.x-0.6,at.z-0.6,1.2,1.2))
	for z in [-11.8,11.8]: Models.box(world,Vector3(0,0.8,z),Vector3(30,1.6,0.3),Color("b7aa8b"),2).set_meta("material_kind","wall")
	for x in [-14.8,14.8]: Models.box(world,Vector3(x,0.8,0),Vector3(0.3,1.6,24),Color("b7aa8b"),2).set_meta("material_kind","wall")
	Models.ramp(world)
	# Three traversable 15 cm steps leading to a small garden landing.
	for i in range(3):
		var height := (i+1)*0.15
		Models.box(world,Vector3(-9,height/2,8.5-i*0.5),Vector3(2,height,0.5),Color("b8b09a"),1)
	Models.box(world,Vector3(-9,0.225,6.75),Vector3(2,0.45,1.5),Color("b8b09a"),1)
	obstacles.append(Rect2(-10.4,5.7,0.4,2.7))
	obstacles.append(Rect2(-8,5.7,0.4,2.7))
	obstacles.append(Rect2(-10,5.7,2,0.3))
	# Side/back ledges are blocked so the raised terrace is approached via its ramp.
	obstacles.append(Rect2(7.6,1.7,0.4,5.1))
	obstacles.append(Rect2(11,1.7,0.4,5.1))
	obstacles.append(Rect2(8,1.7,3,0.4))
	master = make_target(Vector3(0,0,-2.4),"master",Color("bca16b"),true)
	Models.caption(master,"泫渤派门主 · 点击拜见",Vector3(0,1.9,0),FONT,30)
	town_actors.clear()
	town_actors["泫渤派门主"]=master
	var clinic: Node3D = (load("res://assets/3d/inn.tscn") as PackedScene).instantiate()
	clinic.position=Vector3(9,0,-5)
	world.add_child(clinic)
	Models.caption(clinic,"十指医馆",Vector3(0,3.25,2.4),FONT,29)
	obstacles.append(Rect2(6,-7.6,6,5.2))
	make_stall(Vector3(-12.6,0,-0.4),"刀剑铁坊")
	make_stall(Vector3(2,0,6.8),"大宝杂货")
	make_stall(Vector3(12.3,0,6.8),"银龙绸庄")
	for data in [
		["金香玉",Vector3(-8,0,-1.1),Color("d5a078")],
		["韦大宝",Vector3(2,0,8.4),Color("b86b43")],
		["平十指",Vector3(9,0,-1.1),Color("8e897c")],
		["刀剑笑",Vector3(-12.2,0,1.5),Color("946d50")],
		["银娇龙",Vector3(12.3,0,8.4),Color("489787")]]:
		var body := make_town_actor(data[1],data[0],data[2])
		town_actors[data[0]]=body
	practice = make_target(Vector3(6,0,1),"enemy",Color("ae6654"),false)
	practice_model = practice.get_meta("model")
	Models.caption(practice,"练习刀客 · 点击切磋",Vector3(0,1.9,0),FONT,30)
	hero = CharacterBody3D.new()
	hero.name = "Hero"
	hero.collision_layer = 8
	hero.collision_mask = 7
	hero.floor_snap_length = 0.5
	hero.floor_max_angle = deg_to_rad(38)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.65
	collider.shape = capsule
	collider.position.y = 0.825
	hero.add_child(collider)
	world.add_child(hero)
	hero_model = Models.actor_from_scene(hero,"res://assets/3d/hero.tscn")
	var ring := CylinderMesh.new()
	ring.height = 0.018
	ring.top_radius = 0.4
	ring.bottom_radius = 0.4
	ring.radial_segments = 24
	shadow = Models.mesh_node(world,ring,Vector3.ZERO,Color("4c685b"))
	var marker_mesh := TorusMesh.new()
	marker_mesh.inner_radius = 0.26
	marker_mesh.outer_radius = 0.39
	marker_mesh.rings = 20
	marker_mesh.ring_segments = 8
	marker = Models.mesh_node(world,marker_mesh,Vector3.ZERO,Color("f9d67a"))
	marker.visible = false
	var warning_mesh := TorusMesh.new()
	warning_mesh.inner_radius = 1.15
	warning_mesh.outer_radius = 1.25
	warning_mesh.rings = 32
	warning_mesh.ring_segments = 6
	warning_ring = Models.mesh_node(world,warning_mesh,Vector3.ZERO,Color("e97961"))
	warning_ring.visible = false
	camera = Camera3D.new()
	camera.fov = 52
	camera.near = 0.12
	camera.far = 150
	world.add_child(camera)
	camera.current = true
	Textures.apply_building(world)

func make_stall(at: Vector3, title: String) -> void:
	var stall := Node3D.new()
	stall.position=at
	world.add_child(stall)
	Models.box(stall,Vector3(0,0.55,0),Vector3(2,1.1,1),Color("956c4b"),2).set_meta("material_kind","wood")
	for x in [-0.95,0.95]: Models.cylinder(stall,Vector3(x,1.3,0),2.6,0.07,Color("b7996c")).set_meta("material_kind","wood")
	Models.roof(stall,Vector3(0,2.4,0),2.7,1.8,0.5,Color("63898b"))
	Models.caption(stall,title,Vector3(0,2.2,0.6),FONT,23)
	obstacles.append(Rect2(at.x-1.35,at.z-0.9,2.7,1.8))

func make_town_actor(at: Vector3, title: String, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position=at
	body.collision_layer=4
	body.collision_mask=0
	body.set_meta("kind","npc:"+title)
	world.add_child(body)
	var capsule := CapsuleShape3D.new()
	capsule.height=2
	capsule.radius=0.4
	var shape := CollisionShape3D.new()
	shape.shape=capsule
	shape.position.y=1
	body.add_child(shape)
	var npc_index: int=["泫渤派门主","金香玉","韦大宝","平十指","刀剑笑","银娇龙"].find(title)
	var model := Models.actor_from_scene(body,"res://assets/3d/npc_%d.tscn" % npc_index)
	body.set_meta("model",model)
	model.sword.visible=false
	if title=="韦大宝": model.robe.scale=Vector3(1.3,1,1.2)

	Models.caption(body,title+" · 点击对话",Vector3(0,1.9,0),FONT,26)
	return body

func build_dialogue() -> void:
	var layer := CanvasLayer.new()
	layer.layer=25
	add_child(layer)
	dialogue=PanelContainer.new()
	dialogue.position=Vector2(245,462)
	dialogue.size=Vector2(790,212)
	dialogue.add_theme_stylebox_override("panel",make_style(Color("173239")))
	layer.add_child(dialogue)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	dialogue.add_child(row)
	dialogue_portrait=TextureRect.new()
	dialogue_portrait.custom_minimum_size=Vector2(195,195)
	dialogue_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	dialogue_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(dialogue_portrait)
	var box := VBoxContainer.new()
	box.custom_minimum_size=Vector2(555,190)
	row.add_child(box)
	dialogue_text=Label.new()
	dialogue_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.custom_minimum_size=Vector2(555,150)
	dialogue_text.add_theme_font_size_override("font_size",22)
	box.add_child(dialogue_text)
	var close := Button.new()
	close.text="继续游历 · E / Esc"
	close.pressed.connect(func(): dialogue.hide())
	box.add_child(close)
	dialogue.hide()

func show_dialogue(title: String) -> void:
	if dialogue==null: return
	dialogue_portrait.texture=Portraits.npc(title)
	dialogue_text.text=title+"\n"+message
	dialogue.show()
	dragging=false

func make_target(at: Vector3, kind: String, color: Color, elder: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("kind",kind)
	world.add_child(body)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2
	shape.shape = capsule
	shape.position.y = 1
	body.add_child(shape)
	body.set_meta("model",Models.actor_from_scene(body,"res://assets/3d/master.tscn" if elder else "res://assets/3d/practice.tscn"))
	return body

func build_navigation() -> void:
	grid.region = Rect2i(-28,-22,57,45)
	grid.cell_size = Vector2(CELL,CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for x in range(-28,29):
		for z in range(-22,23):
			var point := Vector2(x,z)*CELL
			var solid := false
			for obstacle in obstacles:
				if obstacle.grow(0.42).has_point(point): solid = true
			var actors: Array = town_actors.values()
			actors.append(practice)
			for actor in actors:
				if point.distance_to(Vector2(actor.position.x,actor.position.z)) < 0.8: solid = true
			grid.set_point_solid(Vector2i(x,z),solid)

func cell_for(at: Vector3) -> Vector2i:
	return Vector2i(roundi(at.x/CELL),roundi(at.z/CELL))

func free_cell(at: Vector3) -> Vector2i:
	var desired := cell_for(at)
	desired.x = clampi(desired.x,-28,28)
	desired.y = clampi(desired.y,-22,22)
	if not grid.is_point_solid(desired): return desired
	for radius in range(1,9):
		var best := desired
		var distance := INF
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				var id := desired+Vector2i(x,z)
				if grid.is_in_boundsv(id) and not grid.is_point_solid(id):
					var d := Vector2(id).distance_to(Vector2(desired))
					if d < distance: best = id; distance = d
		if distance < INF: return best
	return Vector2i(0,7)

func navigate_to(at: Vector3, target: String = "") -> void:
	var start := free_cell(hero.position)
	var goal := free_cell(at)
	route = grid.get_point_path(start,goal)
	route_index = 0
	click_target = target
	if route.is_empty():
		message = "此处无法到达，请点击街道。"
		click_target = ""
		marker.hide()
		return
	var end := route[route.size()-1]
	marker.position = Vector3(end.x,surface_height(end)+0.05,end.y)
	marker.show()

func navigate_to_actor(actor: Node3D, kind: String) -> void:
	var start := free_cell(hero.position)
	var best := PackedVector2Array()
	var cost := INF
	var relative := hero.position-actor.position
	var angle := atan2(relative.x,relative.z)
	for i in range(24):
		var theta := angle+TAU*i/24.0
		var at := actor.position+Vector3(sin(theta),0,cos(theta))*1.35
		var goal := cell_for(at)
		if not grid.is_in_boundsv(goal) or grid.is_point_solid(goal): continue
		var endpoint := Vector2(goal)*CELL
		if endpoint.distance_to(Vector2(actor.position.x,actor.position.z))>1.65: continue
		var candidate := grid.get_point_path(start,goal)
		if candidate.is_empty(): continue
		var length := 0.0
		for step in range(1,candidate.size()): length+=candidate[step-1].distance_to(candidate[step])
		if length<cost: best=candidate; cost=length
	if best.is_empty():
		message="无法接近这位人物，请移动到街道另一侧。"
		return
	route=best
	route_index=0
	click_target=kind
	var point := best[best.size()-1]
	marker.position=Vector3(point.x,surface_height(point)+0.05,point.y)
	marker.show()

func surface_height(at: Vector2) -> float:
	if at.x>=-10 and at.x<=-8:
		if at.y>=6 and at.y<7.25: return 0.45
		if at.y>=7.25 and at.y<7.75: return 0.45
		if at.y>=7.75 and at.y<8.25: return 0.3
		if at.y>=8.25 and at.y<=8.75: return 0.15
	if at.x >= 8 and at.x <= 11:
		if at.y >= 2 and at.y <= 4: return 0.6
		if at.y > 4 and at.y <= 7: return (7-at.y)*0.2
	return 0

func ui_at(point: Vector2) -> bool:
	return Rect2(25,15,1000,155).has_point(point) or Rect2(1035,15,220,200).has_point(point) or Rect2(25,685,1230,100).has_point(point) or (menu != null and menu.visible)

func pick_at(point: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(point)
	var end := origin+camera.project_ray_normal(point)*150
	var query := PhysicsRayQueryParameters3D.create(origin,end,7)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func click_world(point: Vector2) -> void:
	if paused or ui_at(point): return
	var hit := pick_at(point)
	if hit.is_empty(): return
	var body: Object = hit.collider
	var kind: String = body.get_meta("kind","")
	if kind in ["master","enemy"] or kind.begins_with("npc:"):
		if kind == "enemy" and enemy_health <= 0:
			message = "练习刀客已经认输，回门主处交差。"
			return
		var target_body: Node3D = body
		navigate_to_actor(target_body,kind)
	elif (body as CollisionObject3D).collision_layer & 1:
		navigate_to(hit.position)
	else: message = "建筑和树木不可行走，请点击石板街道。"

func _input(event: InputEvent) -> void:
	if dialogue!=null and dialogue.visible: dragging=false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		dragging = false
	if dragging and event is InputEventMouseMotion:
		rotate_camera(event.relative)
		get_viewport().set_input_as_handled()

func rotate_camera(relative: Vector2) -> void:
	yaw = wrapf(yaw-relative.x*0.006,-PI,PI)
	pitch = clampf(pitch+relative.y*0.004,deg_to_rad(28),deg_to_rad(68))

func zoom_camera(amount: float) -> void:
	zoom = clampf(zoom+amount,6,20)

func _unhandled_input(event: InputEvent) -> void:
	if dialogue!=null and dialogue.visible:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_E,KEY_ESCAPE]: dialogue.hide()
		return
	if menu != null and menu.visible:
		super._unhandled_input(event)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			dragging = not paused and not ui_at(event.position)
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if not paused and not ui_at(event.position): zoom_camera(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if Rect2(825,25,185,38).has_point(event.position): open_menu()
			elif Rect2(825,70,185,38).has_point(event.position): save_character()
			elif Rect2(825,115,185,38).has_point(event.position): paused = not paused
			elif not dragging: click_world(event.position)
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5: save_character()
			KEY_F6: open_menu()
			KEY_ESCAPE: paused = not paused
			KEY_SHIFT:
				if not paused: begin_leap()
			KEY_E:
				if not paused and hero.position.distance_to(master.position)<2: talk_master()
			KEY_J,KEY_SPACE:
				if not paused and enemy_health>0 and hero.position.distance_to(practice.position)<1.8: attack_practice()
			KEY_R:
				if hp<=0 or enemy_health<=0:
					hp=max_hp()
					hero.position=Vector3(0,0.05,3.5)
					hero.velocity=Vector3.ZERO
					enemy_health=100
					practice.visible=true
					training_state=1
					click_target=""
					route.clear()
					message="已重新开始切磋，原任务记录保留；交差奖励仅领取一次。"

func reset_game() -> void:
	super.reset_game()
	legacy_archive = {}
	training_state = 0
	training_rewarded = false
	enemy_health = 100
	practice_hits = 0
	click_target = ""
	route.clear()
	leap_remaining = 0
	slash_remaining = 0
	enemy_windup = 0
	leap_cd = 0
	enemy_cooldown = 0
	enemy_aim = Vector3.ZERO
	route_index = 0
	dragging = false
	yaw = 0
	pitch = deg_to_rad(48)
	zoom = 13
	actual_zoom = zoom
	if hero != null:
		hero.position = Vector3(0,0.05,3.5)
		hero.velocity = Vector3.ZERO
		hero_model.root.position.y = 0
		hero_model.root.rotation = Vector3(0,PI,0)
		camera_anchor = hero.position+Vector3(0,1.3,0)
		marker.hide()
		warning_ring.hide()
		practice.visible = true
	if dialogue!=null: dialogue.hide()
	message = "左键点击门主拜见，再点击练习刀客切磋，最后返回交差。"

func select_slot(slot: int) -> void:
	var is_new := saves.read_slot(slot).is_empty()
	super.select_slot(slot)
	if is_new and active_slot==slot and not menu.visible:
		message="初入江湖 · 新地图已载入，请点击门主拜见。"

func snapshot() -> Dictionary:
	var data := super.snapshot()
	if hero != null:
		data["world3d"] = {"version":1,"position":[hero.position.x,hero.position.y,hero.position.z],"yaw":yaw,"pitch":pitch,"zoom":zoom,"enemy_hp":enemy_health,"training":training_state,"rewarded":training_rewarded,"hits":practice_hits}
	if not legacy_archive.is_empty(): data["legacy2d"] = legacy_archive.duplicate(true)
	return data

func restore(data: Dictionary) -> void:
	if world!=null:
		world.get_parent().remove_child(world)
		world.queue_free()
		world=null
		hero=null
		hero_model={}
		obstacles.clear()
		build_world()
		build_navigation()
	super.restore(data)
	legacy_archive = data.get("legacy2d",data).duplicate(true)
	legacy_archive.erase("world3d")
	legacy_archive.erase("legacy2d")
	if hero == null: return
	var saved: Dictionary = data.get("world3d",{})
	if not saved.is_empty():
		var pos: Array = saved.position
		var safe := free_cell(Vector3(pos[0],0,pos[2]))
		var ground := Vector2(safe)*CELL
		var exact := Vector2(float(pos[0]),float(pos[2]))
		var safe_exact := exact.x>=-14 and exact.x<=14 and exact.y>=-11 and exact.y<=11
		for obstacle in obstacles:
			if obstacle.grow(0.32).has_point(exact): safe_exact=false
		var actors: Array = town_actors.values()
		actors.append(practice)
		for body in actors:
			if exact.distance_to(Vector2(body.position.x,body.position.z))<0.75: safe_exact=false
		if safe_exact: ground=exact
		hero.position = Vector3(ground.x,surface_height(ground)+0.05,ground.y)
		yaw = wrapf(float(saved.get("yaw",0)),-PI,PI)
		pitch = clampf(float(saved.get("pitch",0.84)),deg_to_rad(28),deg_to_rad(68))
		zoom = clampf(float(saved.get("zoom",13)),6,20)
		enemy_health = clampf(float(saved.get("enemy_hp",100)),0,100)
		training_state = clampi(int(saved.get("training",0)),0,3)
		training_rewarded = bool(saved.get("rewarded",false))
		practice_hits = int(saved.get("hits",0))
	practice.visible = enemy_health>0
	apply_profession_model()
	actual_zoom = zoom
	camera_anchor = hero.position+Vector3(0,1.3,0)
	message = "原角色与任务已保留 · 点击门主开始街区切磋。" if saved.is_empty() else "三维街区进度已恢复。"
	update_camera(1,true)

func apply_profession_model() -> void:
	var profession := Saves.display_profession(str(character.get("profession","刀客")))
	var file: String = {"刀客":"class_blade","剑客":"class_sword","枪客":"class_spear"}.get(profession,"class_blade")
	var path := "res://assets/3d/%s.tscn" % file
	if not FileAccess.file_exists(path): return
	hero_model.root.free()
	hero_model=Models.actor_from_scene(hero,path)
	hero_model.root.rotation.y=PI

func talk_master() -> void:
	click_target = ""
	route.clear()
	if training_state == 0:
		training_state = 1
		message = "门主：欢迎来到泫渤派！与练习刀客切磋，再回来找我。"
	elif enemy_health<=0 and not training_rewarded:
		training_state = 3
		training_rewarded = true
		coins += 50
		message = "试炼完成！门主赠你 50 镖银。F5 保存，R 可重练。"
	elif training_rewarded: message = "门主：江湖路远，勤练武艺。奖励已领取，原任务记录未清空。"
	else: message = "门主：点击练习刀客自动接近与挥刀；红圈出现时移动躲避。"

	show_dialogue("泫渤派门主")

func talk_town_npc(title: String) -> void:
	click_target=""
	route.clear()
	match title:
		"金香玉": hp=max_hp(); qi=100; message="客栈已经备好热茶，歇息后生命与真气恢复。"
		"韦大宝":
			if coins>=15: coins-=15; potions+=1; message="十五镖银，金创药收好了！"
			else: message="金创药每瓶十五镖银，切磋交差后再来逛逛。"
		"平十指": hp=max_hp(); message="初入江湖不必客气，伤势已为你治好。"
		"刀剑笑": message="刀、剑、枪、医，各有所长。本版先练普通出招与轻功。"
		"银娇龙": message="名册中可以创建四职业、切换角色或确认删档。F5 保存，F6 返回名册。"
	show_dialogue(title)

func attack_practice() -> void:
	if attack_cd>0 or enemy_health<=0: return
	if training_state==0:
		message = "先拜见门主，获得切磋许可。"
		click_target = ""
		return
	attack_cd = 0.55
	slash_remaining = 0.38
	var delta := practice.position-hero.position
	hero_model.root.rotation.y = atan2(delta.x,delta.z)
	enemy_health = maxf(0,enemy_health-(18+(level-1)*3))
	practice_hits += 1
	message = "命中练习刀客 · 剩余生命 %d" % enemy_health
	if enemy_health<=0:
		training_state = 2
		click_target = ""
		practice.visible = false
		enemy_windup = 0
		message = "练习刀客认输！返回门主交差。"

func begin_leap() -> void:
	if leap_cd>0 or leap_remaining>0 or hp<=0: return
	leap_remaining = 0.8
	leap_cd = 2.5
	message = "轻功起跃 · 地面路径与碰撞继续约束行动。"

func camera_direction() -> Vector3:
	return Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))

func update_camera(dt: float, snap: bool = false) -> void:
	if camera == null: return
	var target := hero.position+Vector3(0,1.3,0)
	camera_anchor = target if snap else camera_anchor.lerp(target,1-exp(-dt*9))
	var direction := camera_direction()
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,camera_anchor)
	query.collision_mask = 3
	var space := world.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():
		camera_anchor = target
		query.transform = Transform3D(Basis.IDENTITY,camera_anchor)
	query.motion = direction*zoom
	var fractions := space.cast_motion(query)
	var safe_zoom := maxf(0.35,zoom*fractions[0]-0.2)
	actual_zoom = safe_zoom if safe_zoom<actual_zoom or snap else lerpf(actual_zoom,safe_zoom,1-exp(-dt*7))
	var at := camera_anchor+direction*actual_zoom
	at.y = maxf(at.y,surface_height(Vector2(at.x,at.z))+0.4)
	camera.position = at
	camera.look_at(camera_anchor,Vector3.UP)

func _process(dt: float) -> void:
	if world==null: return
	update_camera(dt)
	queue_redraw()
	if paused or (menu != null and menu.visible) or active_slot==0: return
	if dialogue!=null and dialogue.visible: return
	elapsed += dt
	attack_cd = maxf(0,attack_cd-dt)
	leap_cd = maxf(0,leap_cd-dt)
	slash_remaining = maxf(0,slash_remaining-dt)
	leap_remaining = maxf(0,leap_remaining-dt)
	hero_model.root.position.y = sin(PI*(1-leap_remaining/0.8))*0.95 if leap_remaining>0 else 0
	hero_model.ribbon.rotation.x = -0.35-sin(elapsed*12)*0.15 if leap_remaining>0 else -0.1
	hero_model.right_arm.rotation.x = -sin((1-slash_remaining/0.38)*PI)*1.7 if slash_remaining>0 else 0
	hero_model.root.rotation.z = sin((1-slash_remaining/0.38)*PI)*0.15 if slash_remaining>0 else 0
	shadow.position = hero.position+Vector3(0,0.065,0)
	marker.rotation.y += dt
	if hp<=0:
		message = "切磋落败 · 按 R 回到街区重新练习，角色与原任务保留。"
		return
	if click_target == "master" and hero.position.distance_to(master.position)<1.8: talk_master()
	if click_target.begins_with("npc:"):
		var title := click_target.substr(4)
		if town_actors.has(title) and hero.position.distance_to(town_actors[title].position)<1.8: talk_town_npc(title)
	if click_target == "enemy" and hero.position.distance_to(practice.position)<1.7:
		route.clear()
		attack_practice()
	enemy_cooldown = maxf(0,enemy_cooldown-dt)
	if training_state==1 and enemy_health>0:
		if enemy_windup>0:
			enemy_windup -= dt
			if enemy_windup<=0:
				if hero.position.distance_to(enemy_aim)<1.25 and leap_remaining<=0: hp = maxf(0,hp-9)
				enemy_cooldown = 1.8
		elif hero.position.distance_to(practice.position)<2 and enemy_cooldown<=0:
			enemy_windup = 0.7
			enemy_aim = hero.position
			message = "刀客即将出手！点击地面移开或按 Shift 轻功。"
	practice_model.right_arm.rotation.x = -0.8 if enemy_windup>0 else 0
	warning_ring.visible = enemy_windup>0
	warning_ring.position = Vector3(enemy_aim.x,surface_height(Vector2(enemy_aim.x,enemy_aim.z))+0.08,enemy_aim.z)
	save_timer += dt
	if save_timer>=30:
		save_timer = 0
		save_character()

func _physics_process(dt: float) -> void:
	if hero==null or active_slot==0 or paused or hp<=0:
		return
	if dialogue!=null and dialogue.visible:
		hero.velocity=Vector3.ZERO
		return
	var move := Vector3.ZERO
	if route_index < route.size():
		var point := route[route_index]
		var delta := Vector3(point.x-hero.position.x,0,point.y-hero.position.z)
		if delta.length()<0.13:
			route_index += 1
		else:
			move = delta.normalized()*minf(movement_speed(),delta.length()/dt)
			hero_model.root.rotation.y = lerp_angle(hero_model.root.rotation.y,atan2(move.x,move.z),minf(1,dt*14))
	else:
		marker.hide()
	hero.velocity.x = move.x
	hero.velocity.z = move.z
	hero.velocity.y -= 18*dt
	if hero.is_on_floor(): hero.velocity.y = -0.2
	step_up(move*dt)
	hero.move_and_slide()
	if hero.position.y < -1:
		hero.position = Vector3(0,0.05,3.5)
		hero.velocity = Vector3.ZERO
		route.clear()
	var walk := sin(elapsed*13)*0.4 if move.length()>0.1 else 0.0
	hero_model.left_leg.rotation.x = walk
	hero_model.right_leg.rotation.x = -walk
	hero_model.left_arm.rotation.x = -walk*0.6

func movement_speed() -> float:
	return 3.6

func step_up(horizontal_motion: Vector3) -> void:
	if horizontal_motion.length()<0.001 or not hero.is_on_floor(): return
	if not hero.test_move(hero.global_transform,horizontal_motion): return
	var raised := hero.global_transform
	raised.origin.y += 0.46
	if hero.test_move(raised,horizontal_motion): return
	var next := hero.position+horizontal_motion.normalized()*0.35
	var query := PhysicsRayQueryParameters3D.create(next+Vector3(0,0.47,0),next-Vector3(0,0.1,0),1)
	var floor_hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if floor_hit.is_empty(): return
	var difference: float = floor_hit.position.y-hero.position.y
	if difference>0.03 and difference<=0.45:
		hero.position.y += difference+0.005

func map_position(at: Vector3) -> Vector2:
	return Vector2(1053,54)+Vector2((at.x+15)/30,(at.z+12)/24)*Vector2(180,130)

func _draw() -> void:
	if hero==null: return
	panel(Rect2(25,15,780,85))
	label_at(Vector2(45,48),"热血江湖 · 泫渤派街区 / 3D",26,Color("f3cf88"))
	label_at(Vector2(45,81),"%s · %s · Lv.%d  镖银 %d  生命 %d" % [character.get("name","侠客"),Saves.display_profession(character.get("profession","刀客")),level,coins,hp],19)
	panel(Rect2(25,112,780,53))
	label_at(Vector2(43,144),message,17)
	for i in range(3): panel(Rect2(825,25+i*45,185,38))
	label_at(Vector2(838,50),"F6 · 名册 / 下线",18)
	label_at(Vector2(838,95),"F5 · 保存角色",18)
	label_at(Vector2(838,140),"Esc · 继续" if paused else "Esc · 暂停",18)
	panel(Rect2(1035,15,220,200))
	label_at(Vector2(1053,43),"实时地图 · 相机朝向",17,Color("f3cf88"))
	draw_rect(Rect2(1053,54,180,130),Color("718777"))
	for obstacle in obstacles:
		var a := map_position(Vector3(obstacle.position.x,0,obstacle.position.y))
		draw_rect(Rect2(a,obstacle.size/Vector2(30,24)*Vector2(180,130)),Color("b6ad90"))
	for title in town_actors:
		var point := map_position(town_actors[title].position)
		draw_circle(point,3,Color("f6d27c"))
		label_at(point+Vector2(4,-3),"门" if title=="泫渤派门主" else title.left(1),11)
	if enemy_health>0: draw_circle(map_position(practice.position),4,Color("f3846d"))
	var p := map_position(hero.position)
	draw_circle(p,4,Color("88f1f7"))
	var forward := Vector2(-sin(yaw),-cos(yaw))
	draw_line(p,p+forward*15,Color("fff7c6"),2)
	draw_line(p+forward*15,p+forward.rotated(0.45)*9,Color("fff7c6"),2)
	draw_line(p+forward*15,p+forward.rotated(-0.45)*9,Color("fff7c6"),2)
	label_at(Vector2(1053,203),"蓝:自己 金:NPC 红:刀客",13)
	panel(Rect2(25,690,1230,90))
	label_at(Vector2(45,721),"左键 地面寻路 / NPC 对话 / 敌人攻击    右键拖动 360° 视角    滚轮 缩放    Shift 轻功",20)
	label_at(Vector2(45,754),"目标：拜见门主 → 切磋刀客 → 返回交差   · 模型为简化三维占位，有真实侧面与背面",18,Color("a6c4bf"))
	if enemy_health>0:
		var screen := camera.unproject_position(practice.position+Vector3(0,2.1,0))
		if not camera.is_position_behind(practice.position): bar(screen-Vector2(35,0),Vector2(70,6),enemy_health/100,Color("d77360"))
	if paused and (menu==null or not menu.visible):
		panel(Rect2(425,315,430,90))
		label_at(Vector2(470,370),"已暂停 · Esc 继续",28)
