from pathlib import Path
p=Path('created-games/moontide-bistro/main.gd');s=p.read_text(encoding='utf-8')
s=s.replace('for pos in TABLE_POS:\n\t\ttables.append({"pos":pos,"state":"empty","food":0,"patience":55.0,"maximum":55.0,"watered":false,"timer":0.0,"guest_pos":pos+Vector2(-45,-20),"variant":0,"guest_route":PackedVector2Array()})','for table_id in range(TABLE_POS.size()):\n\t\tfor seat in range(2):\n\t\t\ttables.append({"pos":TABLE_POS[table_id],"table_id":table_id,"seat":seat,"state":"empty","food":0,"patience":55.0,"maximum":55.0,"watered":false,"timer":0.0,"guest_pos":Vector2.ZERO,"variant":0,"guest_route":PackedVector2Array()})')
# All gameplay loops operate on eight independently occupied seats. The anchor render review remains four panels.
s=s.replace('range(4)','range(tables.size())')
s=s.replace('func draw_anchor_review():\n\tdraw_rect(Rect2(0,0,1440,900),Color("10282b"))\n\tfor i in range(tables.size()):','func draw_anchor_review():\n\tdraw_rect(Rect2(0,0,1440,900),Color("10282b"))\n\tfor i in range(4):')
s=s.replace('t.pos+Vector2(-40,-18)','seat_position(t)').replace('t.pos+Vector2(-65,-20)','seat_position(t)')
s=s.replace('entities.append({"y":t.pos.y,"kind":"table","index":i})','if t.seat==0: entities.append({"y":t.pos.y,"kind":"table","index":i})')
s=s.replace('func draw_actor(feet: Vector2, is_player: bool, variant: int = 0, seated: bool = false):','func draw_actor(feet: Vector2, is_player: bool, variant: int = 0, seated: bool = false, flip_guest: bool = false):')
s=s.replace('sprite_at(sprite_name,feet,132 if seated else 108,tint,false)','sprite_at(sprite_name,feet,132 if seated else 108,tint,flip_guest)')
s=s.replace('draw_actor(t.guest_pos,false,t.variant,t.state in ["waiting","eating"])','draw_actor(t.guest_pos,false,t.variant,t.state in ["waiting","eating"],t.seat==1)')
a=s.index('\t\t\tif t.state=="eating": icon(');b=s.index('\tif not route.is_empty():',a)
s=s[:a]+'''			for seat_id in range(entity.index,entity.index+2):
				var guest=tables[seat_id]
				var plate_pos=t.pos+Vector2(-23 if guest.seat==0 else 23,-63 if guest.seat==0 else -43)
				if guest.state=="eating": icon(guest.food,Rect2(plate_pos-Vector2(22,15),Vector2(44,30)))
				if guest.state=="dirty": draw_ellipse_plate(plate_pos)
				if guest.watered and guest.state in ["waiting","eating"]: icon(3,Rect2(plate_pos+Vector2(-10,-28),Vector2(22,24)))
	for i in range(tables.size()):
		var t=tables[i]
		if t.seat==0:
			var badge=Rect2(t.pos+Vector2(-15,26),Vector2(30,25))
			panel(badge,Color("193332"),GOLD,8)
			centered(str(t.table_id+1),badge,16,GOLD)
		if t.state=="waiting":
			var r=order_bubble(i)
			panel(r,Color("f5ead4"),GOLD,9)
			icon(t.food,Rect2(r.position+Vector2(4,2),Vector2(40,32)))
			bar(Rect2(r.position+Vector2(5,39),Vector2(38,4)),float(t.patience)/float(t.maximum),CORAL if t.patience<18 else Color("4f9c81"))
		elif t.state=="dirty":
			var r=order_bubble(i)
			r.size=Vector2(48,24)
			panel(r,Color("463b32"),GOLD,7)
			centered("清理",r,12,GOLD)
		if t.state in ["waiting","dirty"] and can_service_from(player,i):
			draw_set_transform(seat_position(t),0,Vector2(1,0.4))
			draw_arc(Vector2.ZERO,18,0,TAU,24,TEAL,1.5,true)
			draw_set_transform(Vector2.ZERO)
''' +s[b:]
a=s.index('\ttext_at("餐桌订单"');b=s.index('\ttext_at("钱包',a)
s=s[:a]+'''	text_at("餐桌订单 · 双人席",Vector2(1160,398),21,GOLD)
	for i in range(tables.size()):
		var t=tables[i]
		var r=seat_row(i)
		panel(r,Color("193234"),TEAL if target_id==i and target_kind in ["table","water"] else Color("35504b"),7)
		text_at(seat_label(i),r.position+Vector2(8,24),14,GOLD)
		if t.state in ["waiting","arriving"]:
			icon(t.food,Rect2(r.position+Vector2(37,2),Vector2(38,32)))
			text_at("入座" if t.state=="arriving" else "%ds"%int(t.patience),r.position+Vector2(80,20),13,CORAL if t.patience<18 else MUTED)
			bar(Rect2(r.position+Vector2(80,28),Vector2(57,4)),float(t.patience)/float(t.maximum),TEAL if t.patience>18 else CORAL)
			button(Rect2(r.position+Vector2(150,7),Vector2(90,27)),"已倒水" if t.watered else "倒水 +18",false,t.watered or t.state=="arriving")
		else:
			var msg={"empty":"空位 · 可入座","eating":"享用中","dirty":"清理这个座位","leaving":"离店中"}.get(t.state,"")
			text_at(msg,r.position+Vector2(48,25),14,GOLD if t.state=="dirty" else MUTED)
''' +s[b:]
s=s.replace('func table_access(i: int) -> Vector2:\n\treturn tables[i].pos+Vector2(15,50)', '''func seat_position(t: Dictionary) -> Vector2:
	return t.pos+(Vector2(-66,-20) if t.seat==0 else Vector2(66,18))

func seat_label(i: int) -> String:
	return str(tables[i].table_id+1)+("A" if tables[i].seat==0 else "B")

func seat_row(i: int) -> Rect2:
	return Rect2(1156,414+i*44,248,40)

func order_bubble(i: int) -> Rect2:
	return Rect2(seat_position(tables[i])+Vector2(-24,-175),Vector2(48,48))

func can_service_from(point: Vector2, i: int) -> bool:
	var anchor=seat_position(tables[i])
	if point.distance_to(anchor)>60: return false
	# Do not allow reaching through the tabletop from the opposite side.
	for step in range(1,9):
		if not walkable(point.lerp(anchor,float(step)/10.0)): return false
	return true

func table_access(i: int) -> Vector2:
	if can_service_from(player,i): return player
	var anchor=seat_position(tables[i])
	var best_point=Vector2(nearest_cell(anchor)*10)
	var best_cost=INF
	var start=nearest_cell(player)
	for x in range(roundi(anchor.x/10)-6,roundi(anchor.x/10)+7):
		for y in range(roundi(anchor.y/10)-6,roundi(anchor.y/10)+7):
			var cell=Vector2i(x,y)
			var point=Vector2(cell*10)
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell) or not can_service_from(point,i): continue
			var path=grid.get_point_path(start,cell)
			if path.is_empty(): continue
			var cost=0.0
			for j in range(1,path.size()): cost+=path[j-1].distance_to(path[j])
			if cost<best_cost: best_cost=cost;best_point=point
	return best_point''')
s=s.replace('"table","water": destination=table_access(id)','"table","water":\n\t\t\tif can_service_from(player,id):\n\t\t\t\troute.clear(); arrive(); return\n\t\t\tdestination=table_access(id)')
s=s.replace('moving=false\n\tvar direction=Vector2.ZERO','moving=false\n\tif target_kind in ["table","water"] and can_service_from(player,target_id):\n\t\troute.clear();arrive();return\n\tvar direction=Vector2.ZERO')
s=s.replace('var closest=-1; var distance=80.0','var closest=-1; var distance=INF')
s=s.replace('var d=player.distance_to(table_access(i))\n\t\t\t\tif d<distance: distance=d; closest=i','if tables[i].state not in ["waiting","dirty"] or not can_service_from(player,i): continue\n\t\t\t\tvar d=player.distance_to(seat_position(tables[i]))\n\t\t\t\tif d<distance: distance=d; closest=i')
s=s.replace('player.distance_to(tables[i].pos)','player.distance_to(seat_position(tables[i]))')
s=s.replace('var r=Rect2(1156,414+i*88,248,80)','var r=seat_row(i)').replace('Rect2(r.position+Vector2(135,49),Vector2(100,23))','Rect2(r.position+Vector2(150,7),Vector2(90,27))')
a=s.index('\tfor i in range(tables.size()):\n\t\tif Rect2(tables[i].pos',s.index('func handle_click'));b=s.index('\tif p.distance_to(WATER_POS',a)
s=s[:a]+'''	# Match clicks to the actual guest, not to the whole table rectangle.
	var picked=-1
	var best_distance=INF
	for i in range(tables.size()):
		var t=tables[i]
		if t.state not in ["waiting","dirty","eating"]: continue
		if order_bubble(i).has_point(p): go("table",i); return
		var anchor=seat_position(t)
		if Rect2(anchor-Vector2(31,130),Vector2(62,146)).has_point(p):
			var d=p.distance_to(anchor-Vector2(0,70))
			if d<best_distance: best_distance=d;picked=i
	if picked>=0: go("table",picked); return
''' +s[b:]
# Updated input regression coordinates: first seat row is now compact.
s=s.replace('Vector2(1330,475)','Vector2(1330,434)').replace('Vector2(1240,445)','Vector2(1240,434)')
s=s.replace('if can_service_from(player,i): return player','if can_service_from(player,i): return Vector2(nearest_cell(player)*10)')
p.write_text(s,encoding='utf-8')
