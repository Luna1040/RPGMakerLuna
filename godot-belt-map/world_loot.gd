extends Node2D
const HitQuery = preload("combat_query.gd")
## All collision tests use world meters and ground depth, never projected screen distance.
signal notice(text: String)
signal crate_destroyed(id: String)
var crates: Dictionary = {}
var chests: Array = []
var drops: Array = []
var materials := {"木料":0, "碎布":0, "旧铜币":0, "秘银碎屑":0}
var latest_equipment := ""
var pending_equipment: Array[String] = []
var equipment: RefCounted
var volumes: Array
var sorting: Node2D
var projection: Callable
var time := 0.0
var chest_skins: Dictionary = {}

class LootArt extends Node2D:
	var kind := "chest"
	var opened := false
	var tint := Color("d9bb68")
	var bounce := 0.0
	var skins: Dictionary = {}
	var slot := "weapon"
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO,0,Vector2(1,0.24))
		draw_circle(Vector2.ZERO,34 if kind=="chest" else 15,Color(0.02,0.03,0.04,0.35))
		draw_set_transform(Vector2(0,-bounce))
		if kind=="chest":
			if not skins.is_empty():
				var skin: Dictionary=skins["chest-open" if opened else "chest-closed"]
				var texture: Texture2D=skin.texture
				var scale_factor: float=skin.recommendedScale
				var pivot := Vector2(skin.pivot[0],skin.pivot[1])
				draw_texture_rect(texture,Rect2(-pivot*scale_factor,texture.get_size()*scale_factor),false)
				return
			draw_rect(Rect2(-37,-43,74,40),Color("30221e"))
			draw_rect(Rect2(-33,-39,66,33),Color("704329"))
			for i in 4:
				draw_line(Vector2(-31,-35+i*9),Vector2(30,-35+i*9),Color("372b25"),2)
			var lid_y := -66.0 if opened else -57.0
			draw_colored_polygon(PackedVector2Array([Vector2(-36,-43),Vector2(-29,lid_y),Vector2(29,lid_y),Vector2(36,-43)]),Color("976638"))
			if opened:
				draw_rect(Rect2(-30,-48,60,8),Color("211c21"))
				draw_line(Vector2(-25,-44),Vector2(24,-44),Color("e5be59"),2)
			for x in [-25,20]:
				draw_rect(Rect2(x,-43,5,37),Color("b7a268"))
				draw_line(Vector2(x,lid_y+2),Vector2(x,-43),Color("d7bd78"),4)
			for x in [-22,23]:
				for y in [-34,-12]:
					draw_circle(Vector2(x,y),1.4,Color("f3df9d"))
			draw_rect(Rect2(-6,-41,12,14),Color("e2bf69"))
			draw_circle(Vector2(0,-34),2,Color("413524"))
			draw_line(Vector2(-34,-5),Vector2(34,-5),Color("c3a064"),3)
		else:
			if kind=="equipment":
				draw_line(Vector2(0,-8),Vector2(0,-62),Color(tint,0.23),8)
				draw_line(Vector2(0,-8),Vector2(0,-58),Color(tint,0.75),2)
				match slot:
					"armor":
						draw_colored_polygon(PackedVector2Array([Vector2(-7,-38),Vector2(-17,-32),Vector2(-12,-23),Vector2(-8,-27),Vector2(-10,-12),Vector2(10,-12),Vector2(8,-27),Vector2(12,-23),Vector2(17,-32),Vector2(7,-38),Vector2(4,-32),Vector2(-4,-32)]),Color("b7d2e3"))
						draw_line(Vector2(0,-31),Vector2(0,-14),Color("e9bc62"),3)
					"charm":
						draw_arc(Vector2(0,-31),12,0,TAU,24,Color("e9bc62"),3)
						draw_colored_polygon(PackedVector2Array([Vector2(0,-24),Vector2(7,-17),Vector2(0,-8),Vector2(-7,-17)]),Color("7de9f1"))
					_:
						draw_line(Vector2(-8,-14),Vector2(10,-38),Color("29394a"),8)
						draw_line(Vector2(-8,-14),Vector2(10,-38),Color("d7edf1"),4)
						draw_line(Vector2(-12,-24),Vector2(0,-16),Color("e9bc62"),4)
			else:
				draw_rect(Rect2(-11,-19,22,13),Color("45332a"))
				draw_line(Vector2(-8,-17),Vector2(9,-11),tint,7)
				draw_line(Vector2(-7,-12),Vector2(7,-19),Color("e1c99a"),3)

func setup(sort_root: Node2D, world_volumes: Array, project_fn: Callable, gear: RefCounted) -> void:
	sorting=sort_root
	volumes=world_volumes
	projection=project_fn
	equipment=gear
	chest_skins=JSON.parse_string(FileAccess.get_file_as_string("res://assets/loot/chest-meta.json")).assets
	for key in chest_skins:
		chest_skins[key].texture=load("res://assets/loot/"+key+".png")
	for v: Dictionary in volumes:
		if v.kind=="crate":
			crates[str(v.id)]={"volume":v,"hp":30.0,"node":sorting.get_node_or_null(NodePath(str(v.id)))}
	add_chest("courtyard-cache",Vector2(11.8,6.8),["courtyard_blade","courtyard_mail"])
	add_chest("east-cache",Vector2(22.2,4.8),["courtyard_charm"])

func add_chest(id: String, position_world: Vector2, contents: Array) -> void:
	var art := LootArt.new()
	art.name=id
	art.skins=chest_skins
	art.position=projection.call(position_world,0.0)
	sorting.add_child(art)
	chests.append({"id":id,"foot":position_world,"opened":false,"contents":contents,"node":art})

func _process(delta: float) -> void:
	time+=delta
	for drop: Dictionary in drops:
		drop.age+=delta
		var art: LootArt=drop.node
		art.bounce=3+sin(time*3+float(drop.serial))*2+maxf(0,1-float(drop.age)/0.6)*18
		art.queue_redraw()

func hit_melee(foot: Vector2, z: float, event: Dictionary) -> int:
	var hit := 0
	for id: String in crates.keys():
		var v: Dictionary=crates[id].volume
		var rect := Rect2(float(v.x),float(v.depth),float(v.width),float(v.depth_size))
		if HitQuery.overlaps(foot,z,rect,float(v.base_z),float(v.height),event):
			damage_crate(id,float(event.get("damage",22)))
			hit+=1
	return hit

func hit_projectile(from_x: float, to_x: float, depth: float, z: float, damage: float, radius_m: float = 0.9) -> bool:
	var first := ""
	var distance := INF
	for id: String in crates:
		var v: Dictionary=crates[id].volume
		# The bolt has a generous 0.9 m vertical radius; it still cannot strike across depth lanes.
		if depth<float(v.depth)-0.4 or depth>float(v.depth)+float(v.depth_size)+0.4 or z<float(v.base_z)-radius_m or z>float(v.height)+radius_m:
			continue
		if maxf(from_x,to_x)<float(v.x) or minf(from_x,to_x)>float(v.x)+float(v.width):
			continue
		var d := absf(clampf(from_x,float(v.x),float(v.x)+float(v.width))-from_x)
		if d<distance:
			distance=d
			first=id
	if first.is_empty():
		return false
	damage_crate(first,damage)
	return true

func damage_crate(id: String, damage: float) -> void:
	if not crates.has(id):
		return
	var crate: Dictionary=crates[id]
	crate.hp=maxf(0,float(crate.hp)-damage)
	if crate.hp>0:
		if is_instance_valid(crate.node):
			crate.node.modulate=Color(1.4,0.85,0.65)
			create_tween().tween_property(crate.node,"modulate",Color.WHITE,0.15)
		notice.emit("木箱受损 · 剩余 %d / 30" % int(crate.hp))
		return
	var v: Dictionary=crate.volume
	var foot := Vector2(float(v.x)+float(v.width)/2,float(v.depth)+float(v.depth_size)/2)
	if is_instance_valid(crate.node):
		crate.node.queue_free()
	volumes.erase(v)
	crates.erase(id)
	spawn_drop("木料",3,foot+Vector2(-0.22,0.15),false)
	spawn_drop("旧铜币",5,foot+Vector2(0.22,0.22),false)
	spawn_drop("碎布",1,foot+Vector2(0,0.4),false)
	crate_destroyed.emit(id)
	notice.emit("木箱已击碎！靠近杂物按 E 拾取")

func spawn_drop(id: String, amount: int, foot: Vector2, is_equipment: bool) -> void:
	var art := LootArt.new()
	art.kind="equipment" if is_equipment else "material"
	if is_equipment and equipment.CATALOG.has(id):
		art.slot=equipment.CATALOG[id].slot
	art.tint=Color("89cff6") if is_equipment else Color("c9a375")
	art.position=projection.call(foot,0.0)
	sorting.add_child(art)
	drops.append({"id":id,"amount":amount,"foot":foot,"equipment":is_equipment,"node":art,"age":0.0,"serial":drops.size()})

func nearby(foot: Vector2, target: Vector2, radius: float=0.85) -> bool:
	return absf(foot.y-target.y)<=0.65 and foot.distance_to(target)<=radius

func interact(foot: Vector2, z: float) -> bool:
	if z>0.2:
		return false
	var picked: Array[String]=[]
	for drop: Dictionary in drops.duplicate():
		if not nearby(foot,drop.foot) or float(drop.age)<0.25:
			continue
		if drop.equipment:
			if equipment.grant(drop.id):
				queue_equipment(drop.id)
				picked.append(str(equipment.CATALOG[drop.id].name)+"（I 背包 / Q 装备）")
			elif not is_equipped(drop.id):
				queue_equipment(drop.id)
				picked.append(str(equipment.CATALOG[drop.id].name)+"（背包已有，Q 穿戴）")
			else:
				materials["秘银碎屑"]+=2
				picked.append("重复装备分解：秘银碎屑 ×2")
		else:
			materials[drop.id]=int(materials.get(drop.id,0))+int(drop.amount)
			picked.append("%s ×%d" % [drop.id,drop.amount])
		drop.node.queue_free()
		drops.erase(drop)
	if not picked.is_empty():
		notice.emit("获得："+"、".join(picked))
		return true
	for chest: Dictionary in chests:
		if not chest.opened and nearby(foot,chest.foot,1.0):
			chest.opened=true
			chest.node.opened=true
			chest.node.queue_redraw()
			for i in chest.contents.size():
				spawn_drop(chest.contents[i],1,chest.foot+Vector2((i-0.5)*0.44,0.45),true)
			notice.emit("宝箱已打开！靠近装备按 Q 直接穿戴，E 拾取附近物品")
			return true
	return false

func prompt(foot: Vector2, z: float) -> String:
	if z>0.2:
		return ""
	var closest := nearest_equipment(foot)
	if not closest.is_empty():
		return "Q 拾取并穿戴 %s · E 拾取附近物品" % equipment.CATALOG[closest.id].name
	for drop: Dictionary in drops:
		if nearby(foot,drop.foot):
			return "E 拾取附近物品"
	for chest: Dictionary in chests:
		if not chest.opened and nearby(foot,chest.foot,1.0):
			return "E 打开宝箱"
	return ""

func is_equipped(id: String) -> bool:
	return equipment.CATALOG.has(id) and equipment.equipped.get(equipment.CATALOG[id].slot, "")==id

func queue_equipment(id: String) -> void:
	latest_equipment=id
	pending_equipment.erase(id)
	pending_equipment.append(id)

func nearest_equipment(foot: Vector2) -> Dictionary:
	var closest: Dictionary={}
	var distance := INF
	for drop: Dictionary in drops:
		if not drop.equipment or float(drop.age)<0.25 or not nearby(foot,drop.foot):
			continue
		var candidate: float=foot.distance_squared_to(drop.foot)
		if candidate<distance:
			distance=candidate
			closest=drop
	return closest

func quick_equip(foot: Vector2, z: float) -> bool:
	# Ground interaction is unavailable during a jump, even with pending inventory.
	if z>0.2:
		return false
	var drop := nearest_equipment(foot)
	if drop.is_empty():
		return equip_latest()
	var id: String=drop.id
	if is_equipped(id):
		materials["秘银碎屑"]+=2
		notice.emit("已穿戴 %s，重复物分解：秘银碎屑 ×2" % equipment.CATALOG[id].name)
	else:
		if not equipment.owned.has(id):
			equipment.grant(id)
		if not equipment.equip(id):
			return false
		notice.emit("已拾取并装备："+str(equipment.CATALOG[id].name))
	latest_equipment=id
	pending_equipment.erase(id)
	drop.node.queue_free()
	drops.erase(drop)
	return true

func equip_latest() -> bool:
	while not pending_equipment.is_empty():
		var id: String=pending_equipment.pop_back()
		if is_equipped(id):
			continue
		if equipment.equip(id):
			latest_equipment=id
			notice.emit("已装备："+str(equipment.CATALOG[id].name))
			return true
	notice.emit("附近没有可穿戴的掉落，也没有待穿戴的新装备。I 打开背包。")
	return false

func inventory_text() -> String:
	var lines: Array[String]=["背包 · 杂物"]
	for id: String in materials:
		lines.append("%s ×%d" % [id,materials[id]])
	lines.append("\n庭院装备（Q 穿戴地上装备 / 依次穿戴待装备物）")
	for id in ["courtyard_blade","courtyard_mail","courtyard_charm"]:
		if equipment.owned.has(id):
			var item: Dictionary=equipment.CATALOG[id]
			lines.append(str(item.name)+("  [已装备]" if equipment.equipped[item.slot]==id else "  [背包中]"))
	return "\n".join(lines)
