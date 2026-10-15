extends "res://wilderness_3d.gd"
const ClientTownArt = preload("res://client_town_layout.gd")
const CITY_SCALE := 2.4
const CITY_AREAS := [Rect2(-36,-28.8,72,57.6),Rect2(-116,-28.8,80,100),Rect2(36,-28.8,80,100),Rect2(-36,28.8,72,80)]
const CITY_SPAWNS := [["野猫",3,Vector3(-52,0,3),false],["蛤蟆",5,Vector3(-76,0,14),false],["狐狸",7,Vector3(-100,0,36),false],["野猪",11,Vector3(93,0,-5),false],["狂牛",10,Vector3(59,0,28),false],["灰狼",12,Vector3(-12,0,60),true]]
const NPC_NAMES := ["泫渤派门主","金香玉","韦大宝","平十指","刀剑笑","银娇龙"]
var city_ready := false
var client_ground: Dictionary={}
var gate_regions: Array[Rect2]=[]

func movement_speed() -> float:
	return 14.4 if lightness and lightness_remaining>0 else 7.2

func load_grass() -> ShaderMaterial:
	return preload("res://client_field_art.gd").ground()

func simplify_route() -> void:
	if route.size()<3: return
	var compact := PackedVector2Array([route[0]])
	for i in range(1,route.size()-1):
		var before := (route[i]-route[i-1]).normalized()
		var after := (route[i+1]-route[i]).normalized()
		if before.dot(after)<0.999: compact.append(route[i])
	compact.append(route[route.size()-1])
	route=compact

func navigate_to(at: Vector3, target: String="") -> void:
	super.navigate_to(at,target)
	simplify_route()

func navigate_to_actor(actor: Node3D, kind: String) -> void:
	super.navigate_to_actor(actor,kind)
	simplify_route()

func build_world() -> void:
	gate_regions.clear()
	build_town_core()
	monsters.clear()
	var old_obstacles := obstacles.duplicate()
	obstacles.clear()
	for child in world.get_children():
		if child is Node3D and child.get_child_count()>0 and child.get_child(0) is MeshInstance3D and child.get_child(0).mesh is BoxMesh and child.get_child(0).mesh.size==Vector3(0.4,2.4,0.4):
			child.free()
			continue
		if child is MeshInstance3D and child.mesh is BoxMesh:
			var size: Vector3=child.mesh.size
			if size==Vector3(30,1.6,0.3) or size==Vector3(0.3,1.6,24) or size==Vector3(0.94,0.03,0.94):
				child.free()
				continue
		if child is Camera3D or child is WorldEnvironment or child is DirectionalLight3D: continue
		if child==hero or child==marker or child==shadow or child==warning_ring: continue
		if child is Node3D:
			child.position.x*=CITY_SCALE
			child.position.z*=CITY_SCALE
			if not child is CollisionObject3D:
				var factor := 1.25 if child.name in ["hall","inn"] or child.get_node_or_null("@Label3D@1")!=null else CITY_SCALE
				# Scene-backed halls and inns stay human-sized; streets gain breathing room.
				if child.scene_file_path.ends_with("hall.tscn") or child.scene_file_path.ends_with("inn.tscn"): factor=1.25
				child.scale.x*=factor
				child.scale.z*=factor
				if child.scene_file_path.ends_with("hall.tscn"): child.position.y=0.9
	for old in old_obstacles:
		if old.size==Vector2(1.2,1.2): continue
		var center: Vector2=old.get_center()*CITY_SCALE
		var size: Vector2=old.size*(1.25 if old.size.x>=5 else CITY_SCALE)
		obstacles.append(Rect2(center-size/2,size))
	master.position=Vector3(0,0.9,-11.1)
	# Six physically traversable 15 cm steps and a raised civic plaza.
	for i in range(6):
		var height := (i+1)*0.15
		Models.box(world,Vector3(0,height/2,-4.8-i*0.9),Vector3(6,height,0.9),Color("aaa18c"),1).set_meta("material_kind","stone")
		Models.box(world,Vector3(0,height+0.008,-4.8-i*0.9+0.42),Vector3(6,0.018,0.05),Color("657d81"))
	Models.box(world,Vector3(0,0.45,-15.0),Vector3(15,0.9,10.5),Color("a6a695"),1).set_meta("material_kind","stone")
	for x in [-7.7,7.7]:
		wall(Vector3(x,0.95,-15),Vector3(0.3,1.9,10.5))
	wall(Vector3(0,1.4,-28.6),Vector3(72,2.8,0.35))
	for x in [-35.8,35.8]:
		var middle := 7.2 if x<0 else 0.0
		var lo := middle-4
		var hi := middle+4
		wall(Vector3(x,1.4,(-28.8+lo)/2),Vector3(0.35,2.8,lo+28.8))
		wall(Vector3(x,1.4,(28.8+hi)/2),Vector3(0.35,2.8,28.8-hi))
		gate(Vector3(x,0,middle),"西门 · 青草坡" if x<0 else "东门 · 野牛林",true)
	for x in [-20,20]: wall(Vector3(x,1.4,28.6),Vector3(32,2.8,0.35))
	gate(Vector3(0,0,28.6),"南门 · 灰狼谷",false)
	# Residential lanes and shops surround a wide central square.
	for at in [Vector3(-27,0,-21),Vector3(-13,0,-23),Vector3(13,0,-23),Vector3(27,0,-21),Vector3(-27,0,20),Vector3(-15,0,22),Vector3(15,0,22),Vector3(27,0,10)]:
		var house: Node3D=(load("res://assets/3d/inn.tscn") as PackedScene).instantiate()
		house.position=at
		world.add_child(house)
		obstacles.append(Rect2(at.x-3,at.z-2.8,6,5.6))
	for at in [Vector3(-20,0,2),Vector3(22,0,8),Vector3(-5,0,18),Vector3(7,0,18)]:
		Models.box(world,at+Vector3(0,0.23,0),Vector3(2.1,0.46,0.7),Color("8e7760"),2)
		obstacles.append(Rect2(at.x-1.05,at.z-0.35,2.1,0.7))
	for at in [Vector3(-27,0,12),Vector3(-22,0,6),Vector3(9,0,21),Vector3(28,0,-5)]:
		garden_tree(at)
		obstacles.append(Rect2(at.x-0.7,at.z-0.7,1.4,1.4))
	var grass := load_grass()
	for index in range(1,4):
		var area: Rect2=CITY_AREAS[index]
		var center := area.get_center()
		Models.box(world,Vector3(center.x,-0.2,center.y),Vector3(area.size.x,0.4,area.size.y),Color("819b71"),1)
		var plane := PlaneMesh.new()
		plane.size=area.size
		var surface := Models.mesh_node(world,plane,Vector3(center.x,0.027,center.y),Color.WHITE)
		surface.name="GeneratedWildGrass%d" % index
		surface.material_override=grass
		country_road(area,index)
	for index in range(3):
		var area: Rect2=CITY_AREAS[index+1]
		for i in range(14):
			var at := Vector3(area.position.x+7+posmod(i*17, int(area.size.x-14)),0,area.position.y+8+posmod(i*23,int(area.size.y-16)))
			if absf(at.x)<4 or (index<2 and absf(at.z-(7.2 if index==0 else 0.0))<5): continue
			var overlaps := false
			for spec in CITY_SPAWNS:
				for row in range(4):
					for col in range(3):
						if at.distance_to(spec[2]+Vector3((col-1)*5,0,row*5))<3: overlaps=true
			if not overlaps:
				garden_tree(at)
				obstacles.append(Rect2(at.x-0.7,at.z-0.7,1.4,1.4))
	for x in [-116,116]: wall(Vector3(x,0.8,21),Vector3(0.4,1.6,100))
	wall(Vector3(0,0.8,108.7),Vector3(72,1.6,0.4))
	for spec in CITY_SPAWNS: spawn_monster(spec)
	for type in range(6):
		for i in range(9):
			var spec: Array=CITY_SPAWNS[type].duplicate()
			spec[2]+=Vector3((i%3-1)*5,0,(i/3+1)*5)
			spawn_monster(spec)
	Textures.apply_building(world)
	ClientTownArt.apply(self)
	populate_client_outskirts()
	shadow.hide()
	kungfu_fx=preload("res://kungfu_fx.gd").new()
	kungfu_fx.game=self
	world.add_child(kungfu_fx)
	for actor in town_actors.values():
		for caption in actor.get_children():
			if caption is Label3D:
				caption.font_size=20
				caption.pixel_size=0.0045
				caption.text=caption.text.split(" · ")[0]
	camera.far=220
	city_ready=true

func country_road(area: Rect2, index: int) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := area.size.x if index<3 else area.size.y
	var segments := int(length/2)
	for i in range(segments):
		for corner in [[0,-1],[1,-1],[1,1],[0,-1],[1,1],[0,1]]:
			var t: float=float(i+corner[0])/segments
			var bend := sin(t*TAU)*1.3*sin(t*PI)
			var width := 2.5+0.3*sin(t*23)
			var point := Vector3(area.position.x+t*length,0.055,(7.2 if index==1 else 0.0)+bend+corner[1]*width) if index<3 else Vector3(bend+corner[1]*width,0.055,area.position.y+t*length)
			tool.set_normal(Vector3.UP)
			tool.set_uv(Vector2(t,float(corner[1]+1)/2))
			tool.add_vertex(point)
	var road := Models.mesh_node(world,tool.commit(),Vector3.ZERO,Color.WHITE)
	road.name="EarthRoad%d" % index
	road.material_override=preload("res://client_field_art.gd").ground(true)

func garden_tree(at: Vector3) -> void:
	var holder := Node3D.new()
	holder.position=at
	world.add_child(holder)
	preload("res://client_town_art.gd").model(holder,0 if posmod(int(at.x),3)==0 else 1,Vector2(4.2,4.2),"客户端郊外树木")
	var body := StaticBody3D.new()
	body.collision_layer=2
	body.collision_mask=0
	var shape := CollisionShape3D.new()
	var volume := CylinderShape3D.new()
	volume.height=2.8
	volume.radius=0.3
	shape.shape=volume
	shape.position.y=1.4
	body.add_child(shape)
	holder.add_child(body)

func gate(at: Vector3, title: String, sideways: bool) -> void:
	var holder := Node3D.new()
	holder.position=at
	holder.rotation.y=PI/2 if sideways else 0
	world.add_child(holder)
	for x in [-4.35,4.35]:
		Models.box(holder,Vector3(x,2.1,0),Vector3(0.7,4.2,1.2),Color("998262"),2).set_meta("material_kind","wall")
		Models.box(holder,Vector3(x,0.2,0),Vector3(1.1,0.4,1.5),Color("a8a58c"),2)
	Models.roof(holder,Vector3(0,4.2,0),10.5,3,1.4,Color("5e8582"))
	Models.caption(holder,title,Vector3(0,3.55,0.7),FONT,24).pixel_size=0.008

func make_town_actor(at: Vector3, title: String, color: Color) -> StaticBody3D:
	var body := super.make_town_actor(at,title,color)
	for child in body.get_children():
		if child is Label3D: child.pixel_size=0.006
	return body

func populate_client_outskirts() -> void:
	for at in [Vector3(-43,0,-15),Vector3(-48,0,22),Vector3(-63,0,17),Vector3(-64,0,-11),Vector3(-82,0,33),Vector3(-92,0,20),Vector3(-106,0,56),Vector3(46,0,14),Vector3(68,0,-12),Vector3(80,0,24),Vector3(104,0,12),Vector3(61,0,45),Vector3(-24,0,45),Vector3(18,0,58),Vector3(-17,0,83),Vector3(23,0,97)]:
		var near_spawn := false
		for mob in monsters:
			if at.distance_to(mob.home)<3.0: near_spawn=true
		if near_spawn: continue
		garden_tree(at)
		obstacles.append(Rect2(at.x-0.7,at.z-0.7,1.4,1.4))

func make_target(at: Vector3, kind: String, color: Color, elder: bool) -> StaticBody3D:
	var body := super.make_target(at,kind,color,elder)
	var shape: CollisionShape3D=body.get_child(0)
	shape.shape.radius=0.5
	shape.shape.height=2.3
	shape.position.y=1.15
	return body

func build_navigation() -> void:
	grid.region=Rect2i(-231,-57,463,274)
	grid.cell_size=Vector2(CELL,CELL)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for x in range(-231,232):
		for z in range(-57,217):
			var point := Vector2(x,z)*CELL
			var solid := not walkable(point)
			for obstacle in obstacles:
				if obstacle.grow(0.42).has_point(point): solid=true; break
			for actor in town_actors.values()+[practice]:
				if point.distance_to(Vector2(actor.position.x,actor.position.z))<0.8: solid=true
			grid.set_point_solid(Vector2i(x,z),solid)
	var client_cells: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client-xuanbo/client-blocked-cells.json"))
	for point in client_cells:
		var id:=Vector2i(point[0],point[1])
		var gate_area := false
		for rect in gate_regions:
			if rect.has_point(Vector2(id)*CELL): gate_area=true
		if grid.is_in_boundsv(id) and not gate_area: grid.set_point_solid(id,true)
	call_deferred("refresh_gate_navigation_after_frame")

func refresh_gate_navigation_after_frame() -> void:
	await get_tree().physics_frame
	if is_instance_valid(world): refresh_gate_navigation()

func walkable(point: Vector2) -> bool:
	for area in CITY_AREAS:
		if area.has_point(point): return true
	return false

func free_cell(at: Vector3) -> Vector2i:
	var desired := cell_for(at)
	desired.x=clampi(desired.x,-231,231)
	desired.y=clampi(desired.y,-57,216)
	if not grid.is_point_solid(desired): return desired
	for radius in range(1,32):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				var id := desired+Vector2i(x,z)
				if grid.is_in_boundsv(id) and not grid.is_point_solid(id): return id
	return Vector2i(0,7)

func surface_height(at: Vector2) -> float:
	if client_ground.is_empty(): return 0.0
	var gx: float=(at.x*20+600)/40
	var gz: float=(1850-at.y*20)/40
	var x:=floori(gx)
	var z:=floori(gz)
	var a: float=client_ground.get("%d,%d" % [x,z],0.0)
	var b: float=client_ground.get("%d,%d" % [x+1,z],a)
	var c: float=client_ground.get("%d,%d" % [x,z+1],a)
	var d: float=client_ground.get("%d,%d" % [x+1,z+1],a)
	return maxf(0.0,lerpf(lerpf(a,b,gx-x),lerpf(c,d,gx-x),gz-z))

func snapshot() -> Dictionary:
	var data := super.snapshot()
	data.wilderness.version=2
	data["city"]={"version":1,"scale":CITY_SCALE}
	return data

func restore(data: Dictionary) -> void:
	var migrated := data.duplicate(true)
	if not data.has("city") and migrated.has("world3d"):
		migrated.world3d.position[0]*=CITY_SCALE
		migrated.world3d.position[2]*=CITY_SCALE
	super.restore(migrated)
	legacy_archive.erase("city")
	var position_data: Array=migrated.get("world3d",{}).get("position",[0,0,3.5])
	var cell := free_cell(Vector3(position_data[0],0,position_data[2]))
	var at := Vector2(cell)*CELL
	hero.position=Vector3(at.x,surface_height(at)+0.05,at.y)
	hero.velocity=Vector3.ZERO
	update_region()
	zoom=clampf(float(migrated.get("world3d",{}).get("zoom",13)),6,48)
	update_camera(1,true)

func update_region() -> void:
	if hero==null: return
	region="西郊 · 青草坡" if hero.position.x < -36 else "东郊 · 野牛林" if hero.position.x>36 else "南郊 · 灰狼谷" if hero.position.z>28.8 else "泫渤派城"
	runtime.zone=region+" · 3D"

func map_areas() -> Array:
	return CITY_AREAS

func map_extent() -> Vector2:
	return Vector2(232,137.6)

func map_gates() -> Array:
	return [["西",Vector3(-35.8,0,7.2)],["东",Vector3(35.8,0,0)],["南",Vector3(0,0,28.6)]]

func zoom_camera(amount: float) -> void:
	zoom=clampf(zoom+amount,6,48)

func map_position(at: Vector3) -> Vector2:
	return Vector2(1053,54)+Vector2((at.x+116)/232,(at.z+28.8)/137.6)*Vector2(180,130)

func _process(dt: float) -> void:
	super._process(dt)
	if hero==null: return
	hero_model.robe.position.y=0.85
	for mob in monsters:
		var nearby: bool=mob.body.position.distance_to(hero.position)<maxf(38,zoom*2)
		mob.visual.visible=nearby
		var caption: Label3D=mob.body.get_child(2)
		caption.visible=nearby

func talk_master() -> void:
	var toward := hero.position-master.position
	master.get_node("VisualBody").rotation.y=atan2(toward.x,toward.z)
	super.talk_master()

func talk_town_npc(title: String) -> void:
	if town_actors.has(title):
		var toward: Vector3=hero.position-town_actors[title].position
		town_actors[title].get_node("VisualBody").rotation.y=atan2(toward.x,toward.z)
	super.talk_town_npc(title)

func _draw() -> void:
	super._draw()
	if hero==null: return
	panel(Rect2(25,15,780,45))
	label_at(Vector2(45,48),"热血江湖 · 泫渤大城 / 3D",26,Color("f3cf88"))

func _ready() -> void:
	super._ready()
	var menus := preload("res://game_menus.gd").new()
	menus.name="GameMenus"
	add_child(menus)
	var plate := preload("res://hero_nameplate.gd").new()
	plate.name="HeroNameplate"
	plate.game=self
	menus.add_child(plate)

func refresh_gate_navigation() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius=0.36
	capsule.height=1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.collision_mask=18
	for rect in gate_regions:
		for x in range(floori(rect.position.x/CELL),ceili(rect.end.x/CELL)+1):
			for z in range(floori(rect.position.y/CELL),ceili(rect.end.y/CELL)+1):
				var id := Vector2i(x,z)
				if not grid.is_in_boundsv(id): continue
				if rect.position.y>18: grid.set_point_solid(id,false)
				var at := Vector2(id)*CELL
				query.transform=Transform3D(Basis.IDENTITY,Vector3(at.x,surface_height(at)+0.9,at.y))
				if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): grid.set_point_solid(id,true)
