extends Control
var stage
var compact := false
var world_view := false
var world: Dictionary = {}
var terrain: Texture2D
var area := Rect2()
const BIOMES := {"ocean":"285978","coast":"c6bd89","desert":"cba264","grassland":"8aaf64","savanna":"b4ad61","forest":"53866a","rainforest":"316f55","wetland":"688b83","mountain":"928e7e","alpine":"a7ab90","snow":"dce5e3","tundra":"999b86","taiga":"62817a","volcanic":"776763"}

func setup(map_stage, small: bool = false) -> void:
	stage = map_stage
	compact = small
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not compact:
		world = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world-atlas.json").trim_prefix("\ufeff"))
		var w := int(world.width)
		var h := int(world.height)
		var img := Image.create(w,h,false,Image.FORMAT_RGB8)
		for y in h:
			for x in w:
				var idx := y*w+x
				var c := Color(BIOMES.get(str(world.biomes[idx]),"8aaf64"))
				var height_delta: float = float(world.heights[idx])-float(world.heights[maxi(0,idx-w-1)])
				var noise := fposmod(sin(x*127.1+y*311.7)*43758.5453,1.0)-.5
				var shade := clampf(height_delta*1.7+noise*.06,-.16,.16)
				img.set_pixel(x,y,c.lightened(shade) if shade>0 else c.darkened(-shade))
		terrain = ImageTexture.create_from_image(img)
	queue_redraw()

func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()

func text_at(value: String, p: Vector2, color := Color("eadbb6"), font_size: int = 15) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font,p,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color("182c2a"))
	draw_string(font,p,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func map_point(p: Vector2) -> Vector2:
	return area.position + (p-stage.bounds.position)/stage.bounds.size*area.size

func world_point(p: Vector2) -> Vector2:
	return area.position + p/Vector2(world.width,world.height)*area.size

func oval(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 40:
		var a := TAU*i/40.0
		points.append(center+Vector2(cos(a),sin(a))*radius)
	draw_colored_polygon(points,color)

func _draw() -> void:
	if stage == null: return
	var style := StyleBoxFlat.new()
	style.bg_color=Color("152d30")
	style.border_color=Color("a3956a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	draw_style_box(style,Rect2(Vector2.ZERO,size))
	if compact:
		text_at(stage.runtime.Registry.title(stage.runtime.zone) if stage.runtime!=null else "苍石庭院",Vector2(12,22),Color("e9d79f"),16)
		text_at("M · 地图",Vector2(size.x-80,22),Color("a9c4b7"),13)
		area=Rect2(12,32,size.x-24,size.y-47)
	else:
		area=Rect2(22,22,size.x-44,size.y-44)
		var aspect: float = (float(world.width)/float(world.height)) if world_view else (stage.bounds.size.x/stage.bounds.size.y)
		var fit := Vector2(area.size.x,area.size.x/aspect)
		if fit.y>area.size.y: fit=Vector2(area.size.y*aspect,area.size.y)
		area=Rect2((size-fit)/2,fit)

	if world_view:
		draw_world()
	else:
		draw_local()
	if not world_view and stage.runtime!=null and stage.runtime.portals!=null:
		for link in stage.runtime.portals.links:
			var at:=map_point(Vector2(link.x,link.depth))
			draw_circle(at,4 if compact else 7,Color("dfa55d") if stage.runtime.portals.locked(link) else Color("68e5ff"))
			if not compact: text_at(str(link.label),at+Vector2(-70,-12),Color("b6efff"),15)

	# Inset neatline and north pointer.
	draw_rect(area,Color("899c86"),false,1)
	text_at("N ↑",Vector2(size.x-53,size.y-5),Color("a7baab"),11 if compact else 14)

func local_branch_roads() -> Array:
	# These approaches belong to the courtyard buildings, not every map.
	return [4.0,20.8] if stage.contract.get("zone_id", "town") == "town" else []

func draw_local() -> void:
	draw_rect(area,Color("667a5c"))
	# Fine muted terrain blocks, all keyed to the same courtyard ground coordinates.
	for y in 18:
		for x in 48:
			var c := Color("657c60").lightened((sin(x*19.0+y*13.0)+1)*.035)
			draw_rect(Rect2(area.position+Vector2(x/48.0,y/18.0)*area.size,area.size/Vector2(48,18)+Vector2.ONE),c)
	var road_y := map_point(Vector2(0,5.4)).y
	draw_line(Vector2(area.position.x,road_y),Vector2(area.end.x,road_y),Color("a6a282"),area.size.y*.27)
	draw_line(Vector2(area.position.x,road_y),Vector2(area.end.x,road_y),Color("bbb28c"),area.size.y*.19)
	if not compact:
		for i in 54:
			var x := area.position.x+i*area.size.x/54
			draw_line(Vector2(x,road_y-area.size.y*.08),Vector2(x,road_y+area.size.y*.08),Color(0.3,0.3,0.23,.12),1)
	for x in local_branch_roads():
		draw_line(map_point(Vector2(x,1.2)),map_point(Vector2(x,5.4)),Color("aaa583"),area.size.x*.033)
	for v: Dictionary in stage.volumes:
		var origin := map_point(Vector2(v.x,v.depth))
		var extent: Vector2 = Vector2(v.width,v.depth_size)/stage.bounds.size*area.size
		var center := origin+extent/2
		if v.kind=="building":
			var rect := Rect2(origin,extent)
			draw_rect(rect.grow(2),Color("374f43"))
			draw_rect(rect,Color("b48b60"))
			draw_colored_polygon(PackedVector2Array([rect.position,Vector2(rect.get_center().x,rect.position.y-extent.y*.35),Vector2(rect.end.x,rect.position.y)]),Color("c5a879"))
			draw_line(Vector2(rect.position.x,rect.get_center().y),Vector2(rect.end.x,rect.get_center().y),Color("e0c494"),2)
			if not compact: text_at("旅店" if v.id=="inn" else "东侧工坊",origin+Vector2(0,-8))
		elif v.kind=="tree":
			oval(center+Vector2(2,2),Vector2.ONE*(6 if compact else 19),Color("405b45"))
			oval(center,Vector2.ONE*(5 if compact else 16),Color("739466"))
			oval(center-Vector2(2,2),Vector2.ONE*(3 if compact else 10),Color("87a473"))
		elif v.kind=="water":
			oval(center,extent/2+Vector2.ONE*2,Color("d5cba1"))
			oval(center,extent/2,Color("4d9ca3"))
			oval(center,extent/2*.67,Color("68b6ba"))
			draw_circle(center,2 if compact else 5,Color("e5e2c4"))
			if not compact: text_at("庭院喷泉",center+Vector2(-32,-extent.y/2-12))
		elif v.kind=="crate":
			draw_rect(Rect2(origin,extent),Color("8d7552"))
			draw_rect(Rect2(origin,extent),Color("ddbe84"),false,1)
	for npc: Dictionary in stage.townsfolk.residents:
		var p := map_point(npc.position)
		draw_circle(p,5 if compact else 8,Color("173b38"))
		draw_circle(p,3 if compact else 5,Color("9ef4d0"))
		if not compact: text_at(npc.name,p+Vector2(12,5),Color("c6f1d7"))
	for chest: Dictionary in stage.loot.chests:
		var p := map_point(chest.foot)
		var r := 3.0 if compact else 6.0
		var c := Color("938a76") if chest.opened else Color("efc96f")
		draw_rect(Rect2(p-Vector2(r,r*.7),Vector2(r*2,r*1.4)),c)
		draw_line(p-Vector2(r,0),p+Vector2(r,0),Color("544a36"),1)
		if not compact: text_at("已开启" if chest.opened else "宝箱",p+Vector2(10,5),c)
	var player := map_point(stage.foot)
	var radius := 4.0 if compact else 7.0
	draw_circle(player,radius+3,Color("28372a"))
	draw_circle(player,radius,Color("fff1af"))
	var direction := Vector2(float(stage.knight.facing),0)
	draw_colored_polygon(PackedVector2Array([player+direction*(radius+9),player+direction*(radius+2)+Vector2(0,-4),player+direction*(radius+2)+Vector2(0,4)]),Color("fff1af"))
	if not compact: text_at("你的位置",player+Vector2(-24,25),Color("fff1af"))

func draw_world() -> void:
	draw_texture_rect(terrain,area,false)
	for y in range(2,int(world.height)-2,4):
		for x in range(2,int(world.width)-2,4):
			var biome: String = world.biomes[y*int(world.width)+x]
			var p := world_point(Vector2(x+.5,y+.5))
			if biome in ["forest","rainforest","taiga"]:
				draw_colored_polygon(PackedVector2Array([p+Vector2(0,-3),p+Vector2(-2,2),p+Vector2(2,2)]),Color(.1,.26,.2,.42))
			elif biome in ["mountain","alpine"]:
				draw_polyline(PackedVector2Array([p+Vector2(-3,2),p+Vector2(0,-2),p+Vector2(3,2)]),Color(.25,.27,.22,.24),1,true)
	for road in world.get("roads",[]):
		for i in range(1,road.size(),2):
			draw_line(world_point(Vector2(road[i-1].x,road[i-1].y)),world_point(Vector2(road[i].x,road[i].y)),Color("dbc996"),1.5,true)
	var labels: Array[Rect2] = []
	for place: Dictionary in world.places:
		var p := world_point(Vector2(place.x,place.y))
		var current: bool = place.id==stage.contract.get("worldLocationId","")
		if current: draw_arc(p,10,0,TAU,32,Color("ffdb8b"),2,true)
		draw_circle(p,4,Color("f4e6b9"))
		var caption := str(place.name)+( " · 当前区域" if current else "")
		var width := get_theme_default_font().get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		var position := p+Vector2(8,-8)
		position.x=clampf(position.x,area.position.x+4,area.end.x-width-4)
		for attempt in 8:
			var overlaps := false
			for previous in labels:
				if previous.intersects(Rect2(position-Vector2(0,14),Vector2(width,19))): overlaps=true
			if not overlaps: break
			position.y+=20
		labels.append(Rect2(position-Vector2(0,14),Vector2(width,19)))
		if position.distance_to(p)>25: draw_line(p,position+Vector2(0,-5),Color("c7c29b"),1,true)
		text_at(caption,position,Color("ffe1a0") if current else Color("eee3c5"),14)
