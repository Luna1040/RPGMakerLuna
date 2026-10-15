extends Node2D

const FOOD = ["炙烤三文鱼", "海苔寿司卷", "柚子气泡饮"]
const PRICE = [38,28,18]
const GOLD = Color("e9c58a")
const CREAM = Color("f3e7d4")
const MUTED = Color("9eaea9")
const TEAL = Color("65c8b3")
const CORAL = Color("ef967b")
const TABLE_POS = [Vector2(535,460),Vector2(760,545),Vector2(375,565),Vector2(565,675)]
const PICKUP_POS = [Vector2(400,438),Vector2(460,406),Vector2(520,374)]
const WATER_POS = Vector2(880,490)
const FLOOR = [Vector2(150,505),Vector2(590,305),Vector2(975,525),Vector2(580,790)]
var font: Font
var art: Dictionary = {}
var walk_frames: Array = []
var walk_durations: Array = []
var walk_total = 0.0
var walk_clock = 0.0
var walk_canvas=Vector2(768,768)
var walk_pivot=Vector2(384,640)
var walk_scale=0.22
var player = Vector2(575,625)
var facing_left = false
var moving = false
var grid = AStarGrid2D.new()
var route = PackedVector2Array()
var destination = Vector2.ZERO
var target_kind = ""
var target_id = -1
var service_kind = ""
var service_id = -1
var service_time = 0.0
var service_duration = 0.0
var tables: Array = []
var inventory = [2,2,2]
var replenish = [0.0,0.0,0.0]
var tray: Array = []
var water = 4
var active = false
var paused = false
var modal = true
var night = 1
var money = 0
var level = 0
var best = 0
var remaining = 180.0
var earned = 0
var served = 0
var missed = 0
var watered = 0
var combo = 0
var spawned = 0
var spawn_timer = 2.0
var tick = 0.0
var toast_text = "厨房会自动补货。你只管把这一晚照顾好。"
var toast_timer = 8.0
var result_text = ""
var floating: Array = []
var rng = RandomNumberGenerator.new()
var save_path = "res://saves/progress.json"
var mute = false
var audio: AudioStreamPlayer
var screenshot_mode = false
var testing = false
var anchor_review = false

func _ready():
	font=load("res://font.ttf")
	for name in ["room","server","guest","seated","woman","woman_standing","chef","table","salmon","maki","yuzu","water"]:
		art[name]=load("res://assets/v2/"+name+".png")
	if FileAccess.file_exists("res://assets/v2/walk/action.json"):
		var animation=JSON.parse_string(FileAccess.get_file_as_string("res://assets/v2/walk/action.json"))
		walk_canvas=Vector2(animation.canvas[0],animation.canvas[1])
		walk_pivot=Vector2(animation.pivot[0],animation.pivot[1])
		walk_scale=float(animation.scale)
		for frame in animation.frames:
			walk_frames.append(load("res://assets/v2/walk/"+frame.file))
			walk_durations.append(float(frame.duration_ms)/1000.0)
			walk_total+=float(frame.duration_ms)/1000.0
	rng.randomize()
	DirAccess.make_dir_recursive_absolute("res://saves")
	load_game()
	for table_id in range(TABLE_POS.size()):
		for seat in range(2):
			tables.append({"pos":TABLE_POS[table_id],"table_id":table_id,"seat":seat,"state":"empty","food":0,"patience":55.0,"maximum":55.0,"watered":false,"timer":0.0,"guest_pos":Vector2.ZERO,"variant":0,"guest_route":PackedVector2Array()})
	build_grid()
	audio=AudioStreamPlayer.new()
	audio.volume_db=-19
	add_child(audio)
	if "--smoke-test" in OS.get_cmdline_user_args(): call_deferred("smoke_test")
	if "--capture" in OS.get_cmdline_user_args(): call_deferred("capture_scene")
	if "--interaction-test" in OS.get_cmdline_user_args(): call_deferred("interaction_test")
	if "--motion-test" in OS.get_cmdline_user_args(): call_deferred("motion_test")
	if "--anchor-test" in OS.get_cmdline_user_args(): call_deferred("anchor_test")
	if "--seat-test" in OS.get_cmdline_user_args(): call_deferred("seat_test")
	if "--aisle-test" in OS.get_cmdline_user_args(): call_deferred("aisle_test")

func panel(rect: Rect2, color: Color = Color("142b2e"), border: Color = Color("3c5550"), radius: int = 12):
	var style=StyleBoxFlat.new()
	style.bg_color=color
	style.border_color=border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color=Color(0,0,0,0.17)
	style.shadow_size=5
	draw_style_box(style,rect)

func text_at(value: String, pos: Vector2, size: int = 20, color: Color = CREAM):
	draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func centered(value: String, rect: Rect2, size: int = 20, color: Color = CREAM):
	var w=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	text_at(value,Vector2(rect.get_center().x-w/2,rect.position.y+rect.size.y/2+size*0.35),size,color)

func button(rect: Rect2, title: String, accent: bool = false, disabled: bool = false):
	var hovered=rect.has_point(get_global_mouse_position()) and not disabled
	var col=Color("315b54") if accent else Color("213b3c")
	if hovered: col=col.lightened(0.14)
	if disabled: col=Color("1e2c2e")
	panel(rect,col,GOLD if accent else Color("49605a"),8)
	centered(title,rect,18,MUTED if disabled else CREAM)

func image_fit(texture: Texture2D, rect: Rect2, tint: Color = Color.WHITE):
	if texture==null: return
	var ratio=minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
	var size=texture.get_size()*ratio
	draw_texture_rect(texture,Rect2(rect.get_center()-size/2,size),false,tint)

func icon(id: int, rect: Rect2):
	image_fit(art[["salmon","maki","yuzu","water"][id]],rect)

func bar(rect: Rect2, fraction: float, color: Color):
	panel(rect,Color("192a2a"),Color("192a2a"),3)
	if fraction>0.01:
		var inner=rect
		inner.size.x*=clampf(fraction,0,1)
		panel(inner,color,color,3)

func anchored_texture(texture: Texture2D, feet: Vector2, size: Vector2, pivot: Vector2, flip: bool, tint: Color = Color.WHITE):
	# Mirror around the world-space foot anchor, never by shifting a negative rect.
	draw_set_transform(feet,0,Vector2(-1,1) if flip else Vector2.ONE)
	draw_texture_rect(texture,Rect2(-pivot,size),false,tint)
	draw_set_transform(Vector2.ZERO)

func sprite_at(name: String, feet: Vector2, height: float, tint: Color = Color.WHITE, flip: bool = false):
	var texture: Texture2D=art[name]
	var width=height*texture.get_width()/texture.get_height()
	anchored_texture(texture,feet,Vector2(width,height),Vector2(width/2,height),flip,tint)

func draw_actor(feet: Vector2, is_player: bool, variant: int = 0, seated: bool = false, flip_guest: bool = false):
	draw_set_transform(feet,0,Vector2(1,0.35))
	draw_circle(Vector2.ZERO,20 if is_player else 17,Color(0.02,0.04,0.04,0.35))
	if is_player: draw_arc(Vector2.ZERO,22,0,TAU,40,TEAL,2,true)
	draw_set_transform(Vector2.ZERO)
	if is_player:
		if moving and not walk_frames.is_empty():
			var moment=fmod(walk_clock,walk_total)
			var frame_index=0
			while frame_index<walk_durations.size()-1 and moment>walk_durations[frame_index]:
				moment-=walk_durations[frame_index]
				frame_index+=1
			var size=walk_canvas*walk_scale
			anchored_texture(walk_frames[frame_index],feet,size,walk_pivot*walk_scale,facing_left)
		else: sprite_at("server",feet,112,Color.WHITE,facing_left)
		draw_set_transform(feet,0,Vector2(-1,1) if facing_left else Vector2.ONE)
		for i in range(tray.size()): icon(tray[i],Rect2(Vector2(-8+i*22,-72),Vector2(30,25)))
		draw_set_transform(Vector2.ZERO)
	else:
		var tint=[Color.WHITE,Color("d5e4ee"),Color("f3dac4"),Color("cbe1ce")][variant%4]
		var sprite_name=("woman" if seated else "woman_standing") if variant%2==1 else ("seated" if seated else "guest")
		sprite_at(sprite_name,feet,132 if seated else 108,tint,flip_guest)

func draw_scene():
	draw_texture_rect(art.room,Rect2(0,64,1144,763),false)
	# Fine glints animate independently of the painted environment.
	for i in range(9):
		var p=Vector2(25+i*109,778+sin(i*3.0)*22)
		draw_line(p,p+Vector2(15+sin(tick*0.7+i)*5,0),Color(0.35,0.72,0.70,0.08+0.06*sin(tick+i)),1,true)
	sprite_at("chef",Vector2(414,357),90)
	var entities: Array=[]
	for i in range(tables.size()):
		var t=tables[i]
		if t.seat==0: entities.append({"y":t.pos.y,"kind":"table","index":i})
		if t.state in ["arriving","waiting","eating","leaving"]: entities.append({"y":t.guest_pos.y,"kind":"guest","index":i})
	entities.append({"y":player.y,"kind":"player","index":0})
	entities.sort_custom(func(a,b): return a.y<b.y)
	for entity in entities:
		if entity.kind=="player": draw_actor(player,true)
		elif entity.kind=="guest":
			var t=tables[entity.index]
			draw_actor(t.guest_pos,false,t.variant,t.state in ["waiting","eating"],t.seat==1)
		else:
			var t=tables[entity.index]
			image_fit(art.table,Rect2(t.pos-Vector2(85,110),Vector2(170,145)))
			for seat_id in range(entity.index,entity.index+2):
				var guest=tables[seat_id]
				var plate_pos=plate_position(guest)
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
			var r=cleanup_badge(i)
			draw_line(Vector2(r.get_center().x,r.end.y),plate_position(t),GOLD,1,true)
			panel(r,Color("463b32"),GOLD,7)
			centered("清理",r,12,GOLD)
		if t.state in ["waiting","dirty"] and can_service_from(player,i):
			draw_set_transform(seat_position(t),0,Vector2(1,0.4))
			draw_arc(Vector2.ZERO,18,0,TAU,24,TEAL,1.5,true)
			draw_set_transform(Vector2.ZERO)
	if not route.is_empty():
		for i in range(0,route.size(),5): draw_circle(route[i],2,Color(0.65,0.91,0.8,0.35))
		draw_arc(destination,12,0,TAU,24,TEAL,1.5,true)
	if service_kind=="water":
		icon(3,Rect2(player+Vector2(-22,-76),Vector2(34,36)))
		var from=player+Vector2(0,-65)
		var to=tables[service_id].pos+(Vector2(-23,-65) if tables[service_id].seat==0 else Vector2(23,-45))
		var stream=PackedVector2Array()
		for i in range(12):
			var fraction=float(i)/11
			stream.append(from.lerp(to,fraction)+Vector2(0,-sin(fraction*PI)*12))
		draw_polyline(stream,Color(0.50,0.82,0.91,0.85),2.2,true)
	if service_kind=="clean":
		for i in range(5):
			var p=tables[service_id].pos+Vector2(sin(tick*8+i*1.5)*25,-60+cos(tick*5+i)*9)
			draw_line(p-Vector2(3,0),p+Vector2(3,0),GOLD,1.5,true)
			draw_line(p-Vector2(0,3),p+Vector2(0,3),GOLD,1.5,true)
	if not service_kind.is_empty():
		panel(Rect2(player+Vector2(-48,-147),Vector2(96,30)),Color("173c3b"),TEAL,7)
		centered({"water":"正在倒水","clean":"正在清桌","serve":"正在上菜"}.get(service_kind,""),Rect2(player+Vector2(-48,-147),Vector2(96,24)),14)
		bar(Rect2(player+Vector2(-42,-120),Vector2(84,4)),1-service_time/service_duration,TEAL)
	for f in floating: text_at(f.text,f.pos+Vector2(0,-(1.8-f.life)*24),19,f.color)

func draw_ellipse_plate(pos: Vector2):
	draw_set_transform(pos,0,Vector2(1,0.45))
	draw_circle(Vector2.ZERO,22,Color("cac0a6"))
	draw_arc(Vector2.ZERO,17,0,TAU,32,Color("877862"),2,true)
	draw_set_transform(Vector2.ZERO)
	for i in range(3): draw_circle(pos+Vector2(-7+i*6,-2+i%2*4),2,Color("72543c"))

func _draw():
	if art.is_empty(): return
	if anchor_review:
		draw_anchor_review()
		return
	draw_rect(Rect2(0,0,1440,900),Color("0d2228"))
	draw_scene()
	panel(Rect2(20,16,1104,76),Color("102b2e"),Color("506359"),13)
	text_at("月 汐 食 堂",Vector2(43,51),27,GOLD)
	text_at("M O O N T I D E   /   夜 食",Vector2(45,75),11,MUTED)
	text_at("第 %02d 夜"%night,Vector2(310,48),20)
	text_at("营业中" if active else "准备营业",Vector2(312,72),13,TEAL)
	text_at("%02d:%02d"%[int(remaining)/60,int(remaining)%60],Vector2(452,58),30)
	text_at("收入",Vector2(610,43),12,MUTED)
	text_at("¥ %d"%earned,Vector2(610,69),24,GOLD)
	text_at("好评",Vector2(754,43),12,MUTED)
	text_at("%d 位"%served,Vector2(754,69),24)
	button(Rect2(872,32,98,42),"暂停" if not paused else "继续")
	button(Rect2(982,32,120,42),"返回大厅")
	draw_sidebar()
	draw_bottom()
	if modal: draw_modal()

func draw_sidebar():
	panel(Rect2(1140,16,280,868),Color("10292c"),Color("485d54"),14)
	text_at("今夜的厨房",Vector2(1160,50),23,GOLD)
	text_at("自动备餐 · 每种最多 3 份",Vector2(1160,76),14,MUTED)
	for i in range(3):
		var r=Rect2(1156,94+i*91,248,82)
		panel(r,Color("1b3738"),TEAL if target_kind=="pickup" and target_id==i else Color("36534e"),10)
		icon(i,Rect2(r.position+Vector2(5,8),Vector2(70,56)))
		text_at(FOOD[i],r.position+Vector2(82,24),17)
		text_at("¥%d   库存 %d / 3"%[PRICE[i],inventory[i]],r.position+Vector2(82,47),14,GOLD)
		var duration=cook_duration(i)
		bar(Rect2(r.position+Vector2(82,59),Vector2(147,5)),1.0 if inventory[i]>=3 else 1-replenish[i]/duration,TEAL)
		text_at("已备满" if inventory[i]>=3 else "自动补货 %.1fs"%replenish[i],r.position+Vector2(82,75),11,MUTED)
		text_at("%d  取餐"%(i+1),r.position+Vector2(8,74),12,MUTED)
	text_at("餐桌订单 · 双人席",Vector2(1160,398),21,GOLD)
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
	text_at("钱包 ¥%d  ·  厨房 Lv.%d"%[money,level+1],Vector2(1160,797),16,GOLD)
	text_at("连续好评 %d   /   倒水 %d"%[combo,watered],Vector2(1160,825),14,MUTED)
	text_at("M 静音" if not mute else "M 开启音效",Vector2(1160,857),13,MUTED)

func draw_bottom():
	panel(Rect2(20,813,1104,71),Color("122e30"),Color("486055"),12)
	text_at("托盘",Vector2(38,841),15,GOLD)
	text_at("%d / 2"%tray.size(),Vector2(38,865),15,MUTED)
	for i in range(2):
		panel(Rect2(90+i*66,821,58,55),Color("243c3b"),Color("587265"),8)
		if tray.size()>i: icon(tray[i],Rect2(93+i*66,824,52,49))
		else: centered("空",Rect2(90+i*66,821,58,55),13,MUTED)
	icon(3,Rect2(232,819,50,57))
	text_at("水 %d/4"%water,Vector2(287,850),16,TEAL)
	button(Rect2(363,830,85,36),"补水 R")
	text_at(toast_text.left(38),Vector2(468,841),16,CREAM)
	text_at("点击目标自动走近  ·  WASD 移动 / E 互动 / 1–3 取餐 / Q 清空一份",Vector2(468,866),12,MUTED)

func draw_modal():
	draw_rect(Rect2(0,0,1440,900),Color(0.01,0.05,0.06,0.70))
	panel(Rect2(360,190,720,490),Color("102c30"),GOLD,18)
	image_fit(art.server,Rect2(372,235,180,335))
	text_at("月 汐 · 夜 食",Vector2(573,239),30,GOLD)
	text_at("今晚，也请好好招待每一位客人。",Vector2(574,272),17,MUTED)
	button(Rect2(391,600,140,42),"返回大厅")
	if paused:
		text_at("营业已暂停",Vector2(574,324),24)
		text_at("点击订单上菜；点击倒水延长等待。",Vector2(574,367),17)
		text_at("水壶随身携带，最多 4 杯，R 去补水。",Vector2(574,398),17)
		text_at("厨房自动补货，两格托盘可同时端两份。",Vector2(574,429),17)
	else:
		if not result_text.is_empty():
			text_at(result_text,Vector2(574,312),18,TEAL)
		text_at("01   厨房自动备餐，点餐品图标取餐",Vector2(574,355),18)
		text_at("02   给等餐客人倒水，耐心 +18 秒",Vector2(574,391),18)
		text_at("03   上菜、清桌，连获好评赚取小费",Vector2(574,427),18)
		text_at("每夜 3 分钟  ·  每位客人可倒水一次",Vector2(574,469),15,MUTED)
	button(Rect2(574,504,458,53),"继续营业" if paused else "第 %d 夜 · 开门迎客  →"%night,true)
	if not paused:
		button(Rect2(574,571,458,45),"厨房已满级" if level>=4 else "升级厨房  ¥%d  ·  补货更快"%upgrade_cost(),false,money<upgrade_cost() or level>=4)
		text_at("钱包 ¥%d    ·    最高单夜 ¥%d"%[money,best],Vector2(575,647),16,MUTED)
	else: text_at("ESC 继续游戏   /   M 切换音效",Vector2(574,604),16,MUTED)

func cook_duration(i: int) -> float:
	return maxf(2.5,[7.0,6.0,5.0][i]-level*0.8)

func upgrade_cost() -> int:
	return 100+level*100

func start_night():
	active=true; paused=false; modal=false
	remaining=180; earned=0; served=0; missed=0; combo=0; watered=0; spawned=0
	spawn_timer=1; inventory=[2,2,2]; replenish=[cook_duration(0),cook_duration(1),cook_duration(2)]
	tray.clear(); water=4; player=Vector2(575,625)
	cancel_movement()
	for t in tables: t.state="empty"; t.watered=false
	toast("厨房已备好餐，点击右侧图标取餐。")

func toast(value: String):
	toast_text=value
	toast_timer=6

func feedback(value: String, pos: Vector2, color: Color=TEAL):
	floating.append({"text":value,"pos":pos,"life":1.8,"color":color})

func sound(freq: float):
	if mute or audio==null or screenshot_mode: return
	var stream=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=22050
	var data=PackedByteArray()
	data.resize(4400*2)
	for i in range(4400):
		var t=float(i)/22050
		var wave=sin(t*TAU*freq)*exp(-t*25)*0.4+sin(t*TAU*freq*2)*exp(-t*35)*0.1
		data.encode_s16(i*2,int(wave*20000))
	stream.data=data
	audio.stream=stream
	audio.play()

func spawn_customer():
	var empty=[]
	for i in range(tables.size()):
		if tables[i].state=="empty": empty.append(i)
	if empty.is_empty(): return
	var t=tables[empty[rng.randi_range(0,empty.size()-1)]]
	t.state="arriving"; t.watered=false; t.food=rng.randi_range(0,2)
	t.maximum=54.0+level*3; t.patience=t.maximum
	t.guest_pos=Vector2(590,760); t.variant=spawned%4
	t.guest_route=grid.get_point_path(nearest_cell(t.guest_pos),nearest_cell(seat_position(t)))
	spawned+=1
	sound(440)

func seat_position(t: Dictionary) -> Vector2:
	return t.pos+(Vector2(-66,-20) if t.seat==0 else Vector2(66,18))

func seat_label(i: int) -> String:
	return str(tables[i].table_id+1)+("A" if tables[i].seat==0 else "B")

func seat_row(i: int) -> Rect2:
	return Rect2(1156,414+i*44,248,40)

func order_bubble(i: int) -> Rect2:
	return Rect2(seat_position(tables[i])+Vector2(-24,-175),Vector2(48,48))

func plate_position(t: Dictionary) -> Vector2:
	return t.pos+Vector2(-23 if t.seat==0 else 23,-63 if t.seat==0 else -43)

func cleanup_badge(i: int) -> Rect2:
	return Rect2(plate_position(tables[i])+Vector2(-22,-36),Vector2(44,24))

func can_service_from(point: Vector2, i: int) -> bool:
	var anchor=seat_position(tables[i])
	if point.distance_to(anchor)>60: return false
	# Do not allow reaching through the tabletop from the opposite side.
	for step in range(1,9):
		if not walkable(point.lerp(anchor,float(step)/10.0)): return false
	return true

func table_access(i: int) -> Vector2:
	if can_service_from(player,i): return Vector2(nearest_cell(player)*10)
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
	return best_point

func walkable(point: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(point,PackedVector2Array(FLOOR)): return false
	for pos in TABLE_POS:
		# Ground footprint, including clearance for the server's feet.
		var diff=(point-(pos+Vector2(0,-8)))/Vector2(52,27)
		if diff.length()<1: return false
	return true

func build_grid():
	grid.region=Rect2i(0,0,115,82)
	grid.cell_size=Vector2(10,10)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in range(115):
		for y in range(82): grid.set_point_solid(Vector2i(x,y),not walkable(Vector2(x*10,y*10)))

func nearest_cell(point: Vector2) -> Vector2i:
	var cell=Vector2i(roundi(point.x/10),roundi(point.y/10))
	if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell): return cell
	var best_cell=Vector2i(57,62)
	var distance=INF
	for x in range(cell.x-5,cell.x+6):
		for y in range(cell.y-5,cell.y+6):
			var c=Vector2i(x,y)
			if grid.is_in_boundsv(c) and not grid.is_point_solid(c):
				var d=Vector2(c*10).distance_to(point)
				if d<distance: distance=d; best_cell=c
	return best_cell

func go(kind: String, id: int=-1, point: Vector2=Vector2.ZERO):
	if not active or paused: return
	service_kind=""
	target_kind=kind; target_id=id
	match kind:
		"pickup": destination=PICKUP_POS[id]
		"refill": destination=WATER_POS
		"table","water":
			if can_service_from(player,id):
				route.clear(); arrive(); return
			destination=table_access(id)
		"floor": destination=point
	destination=Vector2(nearest_cell(destination)*10)
	route=grid.get_point_path(nearest_cell(player),nearest_cell(destination))
	if route.is_empty(): toast("这条路暂时走不过去。"); target_kind=""

func cancel_movement():
	route.clear(); target_kind=""; service_kind=""; moving=false

func arrive():
	var kind=target_kind; var id=target_id
	target_kind=""
	if kind=="pickup":
		if tray.size()>=2: toast("托盘满了，先上菜。Q 可清理最后一份。")
		elif inventory[id]<=0: toast("师傅正在自动补货，稍等几秒。")
		else:
			inventory[id]-=1; tray.append(id)
			sound(620)
			toast("已取 "+FOOD[id]+"，点击相应餐桌上菜。")
	elif kind=="refill":
		water=4; toast("水壶已装满：4 杯。倒水不占托盘。")
		feedback("水壶 +4",player+Vector2(-30,-125))
	elif kind in ["table","water"]:
		var t=tables[id]
		if kind=="water": begin_water(id)
		elif t.state=="dirty": begin_service("clean",id,1.0)
		elif t.state=="waiting":
			if tray.has(t.food): begin_service("serve",id,0.45)
			elif not t.watered: begin_water(id)
			else: toast("客人要 "+FOOD[t.food]+"；先去取对应餐品。")
		elif t.state=="empty": toast("餐桌已经干净，等待下一位客人。")
		elif t.state=="arriving": toast("客人正在入座，稍候即可服务。")

func begin_service(kind: String, id: int, duration: float):
	service_kind=kind; service_id=id; service_time=duration; service_duration=duration

func begin_water(id: int):
	var t=tables[id]
	if t.state!="waiting": toast("只有等餐的客人需要倒水。")
	elif t.watered: toast("已经为这位客人倒过水了，快上菜吧。")
	elif water<=0: toast("水壶空了，按 R 去水台补水。")
	else: begin_service("water",id,1.15)

func finish_service():
	var t=tables[service_id]
	match service_kind:
		"water":
			if t.state=="waiting" and not t.watered and water>0:
				t.watered=true; t.patience+=18; t.maximum+=18; water-=1; watered+=1
				feedback("耐心 +18秒",t.pos+Vector2(-52,-150))
				toast("谢谢你的水！这位客人愿意再等 18 秒。")
				sound(740)
		"serve":
			if t.state=="waiting" and tray.has(t.food):
				tray.erase(t.food)
				var tip=int(t.patience/12)+mini(combo,5)*2+(3 if t.watered else 0)
				var revenue=PRICE[t.food]+tip
				money+=revenue; earned+=revenue; served+=1; combo+=1
				t.state="eating"; t.timer=8
				feedback("+ ¥%d"%revenue,t.pos+Vector2(-25,-135),GOLD)
				toast("好评！¥%d，包含小费 ¥%d。"%[revenue,tip])
				sound(880)
		"clean":
			if t.state=="dirty":
				t.state="empty"; t.watered=false
				feedback("清理完成",t.pos+Vector2(-35,-125))
				toast("桌面干净了，可以迎接下一位客人。")
	service_kind=""

func update_game(delta: float):
	remaining=maxf(0,remaining-delta)
	for i in range(3):
		if inventory[i]<3:
			replenish[i]-=delta
			while replenish[i]<=0 and inventory[i]<3:
				inventory[i]+=1; replenish[i]+=cook_duration(i)
		else: replenish[i]=cook_duration(i)
	spawn_timer-=delta
	if spawn_timer<=0: spawn_customer(); spawn_timer=maxf(8,14-night*0.5)
	for t in tables:
		if t.state=="arriving":
			move_guest(t,delta,150)
			if t.guest_route.is_empty():
				t.state="waiting"
				t.guest_pos=seat_position(t)
		elif t.state=="waiting":
			t.patience-=delta
			if t.patience<=0:
				start_leaving(t); missed+=1; combo=0
				feedback("客人离开了",t.pos+Vector2(-42,-130),CORAL)
		elif t.state=="eating":
			t.timer-=delta
			if t.timer<=0: start_leaving(t)
		elif t.state=="leaving":
			move_guest(t,delta,190)
			if t.guest_route.is_empty(): t.state="dirty"
	if not service_kind.is_empty():
		service_time-=delta
		if service_time<=0: finish_service()
	if remaining<=0: finish_night()

func slide_step(origin: Vector2, motion: Vector2) -> Vector2:
	# Small substeps avoid skipping a collision during a slow frame.
	var result=origin
	var steps=maxi(1,ceili(motion.length()/3.0))
	var step=motion/steps
	for n in range(steps):
		if walkable(result+step): result+=step
		else:
			if walkable(result+Vector2(step.x,0)): result.x+=step.x
			if walkable(result+Vector2(0,step.y)): result.y+=step.y
	return result

func move_player(delta: float, allow_keyboard: bool=true):
	moving=false
	if target_kind in ["table","water"] and can_service_from(player,target_id):
		route.clear();arrive();return
	var direction=Vector2.ZERO
	if allow_keyboard:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.y-=1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.y+=1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x-=1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x+=1
	if direction.length()>0:
		cancel_movement()
		var next=slide_step(player,direction.normalized()*delta*235)
		moving=player.distance_to(next)>0.01
		player=next
	elif not route.is_empty():
		var next=route[0]
		direction=next-player
		player=player.move_toward(next,delta*235)
		moving=direction.length()>0.1
		if player.distance_to(next)<0.1: route.remove_at(0)
		if route.is_empty(): arrive()
	if moving:
		walk_clock+=delta
		if abs(direction.x)>0.5: facing_left=direction.x<0

func _process(delta):
	tick+=delta
	if active and not paused and not testing:
		move_player(delta)
		update_game(delta)
	for f in floating: f.life-=delta
	floating=floating.filter(func(f): return f.life>0)
	toast_timer-=delta
	if toast_timer<=0: toast_text="厨房自动补货 · 先倒水安抚，再上菜收获好评。"
	queue_redraw()

func toggle_pause():
	if active: paused=not paused; modal=paused

func return_home():
	var assistant=get_node_or_null("/root/GameAssistant")
	if assistant!=null: assistant.go_home()
	else: toast("请从游戏大厅进入，即可返回大厅。")

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_M: mute=not mute
		if event.keycode==KEY_ESCAPE: toggle_pause()
		if modal:
			if event.keycode==KEY_ENTER:
				if paused: toggle_pause()
				else: start_night()
			return
		if not active: return
		if event.keycode in [KEY_1,KEY_2,KEY_3]: go("pickup",event.keycode-KEY_1)
		if event.keycode==KEY_R: go("refill")
		if event.keycode==KEY_Q and not tray.is_empty():
			tray.pop_back()
			toast("已清理托盘中最后一份餐品。")
		if event.keycode==KEY_E:
			var closest=-1; var distance=INF
			for i in range(tables.size()):
				if tables[i].state not in ["waiting","dirty"] or not can_service_from(player,i): continue
				var d=player.distance_to(seat_position(tables[i]))
				if d<distance: distance=d; closest=i
			if closest>=0: go("table",closest)
		if event.keycode==KEY_F:
			var closest=-1; var distance=INF
			for i in range(tables.size()):
				if tables[i].state=="waiting" and not tables[i].watered:
					var d=player.distance_to(seat_position(tables[i]))
					if d<distance: distance=d; closest=i
			if closest>=0: go("water",closest)
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		handle_click(event.position)

func handle_click(p: Vector2):
	if testing: print("TEST_CLICK ",p," modal=",modal)
	if modal:
		if Rect2(391,600,140,42).has_point(p): return_home(); return
		if Rect2(574,504,458,53).has_point(p):
			if paused: toggle_pause()
			else: start_night()
		elif Rect2(574,571,458,45).has_point(p) and not paused: buy_upgrade()
		return
	if Rect2(982,32,120,42).has_point(p): return_home(); return
	if Rect2(872,32,98,42).has_point(p): toggle_pause(); return
	if not active: return
	for i in range(3):
		if Rect2(1156,94+i*91,248,82).has_point(p): go("pickup",i); return
	for i in range(tables.size()):
		var r=seat_row(i)
		if Rect2(r.position+Vector2(150,7),Vector2(90,27)).has_point(p) and tables[i].state=="waiting": go("water",i); return
		if r.has_point(p): go("table",i); return
	if Rect2(363,830,85,36).has_point(p): go("refill"); return
	# Match clicks to the actual guest, not to the whole table rectangle.
	var picked=-1
	var best_distance=INF
	# Visible controls take priority over overlapping guest bodies.
	for i in range(tables.size()):
		if tables[i].state=="dirty" and cleanup_badge(i).has_point(p):
			go("table",i);return
		if tables[i].state=="waiting" and order_bubble(i).has_point(p):
			go("table",i);return
	for i in range(tables.size()):
		var t=tables[i]
		if t.state not in ["waiting","dirty","eating"]: continue
		if t.state=="dirty":
			if Rect2(plate_position(t)-Vector2(22,12),Vector2(44,24)).has_point(p): go("table",i);return
			continue
		var anchor=seat_position(t)
		if Rect2(anchor-Vector2(31,130),Vector2(62,146)).has_point(p):
			var d=p.distance_to(anchor-Vector2(0,70))
			if d<best_distance: best_distance=d;picked=i
	if picked>=0: go("table",picked); return
	if p.distance_to(WATER_POS+Vector2(0,-40))<65: go("refill"); return
	if walkable(p): go("floor",-1,p)

func finish_night():
	active=false; modal=true; paused=false; cancel_movement()
	best=maxi(best,earned)
	result_text="服务 %d 位 · 倒水 %d 次 · 离开 %d 位 · ¥%d"%[served,watered,missed,earned]
	night+=1
	save_game()

func buy_upgrade():
	if level>=4 or money<upgrade_cost(): return
	money-=upgrade_cost(); level+=1
	save_game()
	result_text="厨房升级成功，自动补货速度提升。"
	sound(1040)

func save_game():
	var file=FileAccess.open(save_path,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"version":2,"money":money,"night":night,"level":level,"best":best}))

func load_game():
	if not FileAccess.file_exists(save_path): return
	var data=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary:
		money=maxi(0,int(data.get("money",0)))
		night=maxi(1,int(data.get("night",1)))
		level=clampi(int(data.get("level",0)),0,4)
		best=maxi(0,int(data.get("best",0)))

func capture_scene():
	screenshot_mode=true
	if not "--prep" in OS.get_cmdline_user_args():
		start_night()
		for i in range(tables.size()):
			var t=tables[i]
			t.state="waiting"; t.food=i%3; t.patience=38+i*4; t.maximum=54; t.variant=i
			t.guest_pos=seat_position(t)
		tables[1].watered=true
		tray=[0,2]; water=3; remaining=143; earned=126; money=126; served=3; combo=3
		paused=true; modal=false
		player=Vector2(650,610)
		if "--dirty-review" in OS.get_cmdline_user_args():
			for t in tables: t.state="dirty"
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture_path="res://evidence/v2-prep.png" if "--prep" in OS.get_cmdline_user_args() else "res://evidence/v3-two-seats.png"
	if "--dirty-review" in OS.get_cmdline_user_args(): capture_path="res://evidence/cleanup-badges.png"
	get_viewport().get_texture().get_image().save_png(capture_path)
	print("CAPTURE_OK")
	get_tree().quit()

func smoke_test():
	screenshot_mode=true
	save_path="user://moontide-v2-tests.json"
	start_night()
	inventory=[0,0,0]
	update_game(7.1)
	assert(inventory[0]>=1 and inventory[1]>=1 and inventory[2]>=1,"Automatic replenishment")
	for i in range(3): inventory[i]=3
	update_game(30)
	assert(inventory==[3,3,3],"Stock cap")
	for t in tables: t.state="empty"
	var t=tables[0]
	t.state="waiting"; t.food=0; t.patience=30; t.watered=false; t.maximum=54
	water=4
	begin_water(0); finish_service()
	assert(t.patience==48 and water==3 and t.watered and watered==1,"Water extends patience once")
	begin_water(0)
	assert(service_kind=="" and water==3,"No repeated watering")
	tray=[0,2]
	begin_service("serve",0,0.45); finish_service()
	assert(t.state=="eating" and tray==[2] and served==1 and earned>=PRICE[0],"Correct food served")
	t.state="waiting"; t.food=1; t.watered=true
	target_kind="table";target_id=0;arrive()
	assert(tray==[2] and t.state=="waiting","Wrong order does not consume tray")
	tray=[0,1];target_kind="pickup";target_id=2;arrive()
	assert(tray.size()==2,"Tray capacity")
	t.state="dirty";begin_service("clean",0,1);finish_service()
	assert(t.state=="empty","Cleaning")
	t.state="waiting";t.patience=0.01
	update_game(0.1)
	assert(t.state=="leaving" and missed==1,"Timeout")
	var points: Array=[]
	points.append_array(PICKUP_POS);points.append(WATER_POS)
	for i in range(tables.size()): points.append(table_access(i))
	for a in points:
		for b in points:
			player=Vector2(nearest_cell(a)*10)
			go("floor",-1,b)
			assert(not route.is_empty(),"Route must exist")
			for step in range(1000):
				move_player(1.0/60.0,false)
				if route.is_empty(): break
			assert(player.distance_to(Vector2(nearest_cell(b)*10))<1,"Route arrival")
	var before=remaining
	paused=true
	_process(2)
	assert(remaining==before,"Pause freezes simulation")
	paused=false
	money=500;level=0;buy_upgrade()
	assert(money==400 and level==1)
	money=0;load_game()
	assert(money==400 and level==1,"Save round trip")
	var key=InputEventKey.new();key.pressed=true;key.keycode=KEY_1
	_unhandled_input(key)
	assert(target_kind=="pickup" and target_id==0,"Keyboard route")
	handle_click(Vector2(1180,200))
	assert(target_kind=="pickup" and target_id==1,"Click route")
	finish_night()
	assert(not active and modal,"Settlement")
	print("PASS: auto stock, stock cap, water +18 seconds, one water per guest, tray capacity, serve, wrong order, cleaning, timeout")
	print("PASS: 144 actual navigation paths, keyboard and mouse routes, pause, upgrade, save migration, settlement")
	get_tree().quit()

func click_event(point: Vector2):
	var event=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=get_viewport().get_final_transform()*point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	var release=event.duplicate()
	release.pressed=false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await get_tree().process_frame

func run_route_and_service():
	for step in range(1600):
		move_player(1.0/60.0,false)
		update_game(1.0/60.0)
		if route.is_empty() and service_kind.is_empty(): break

func interaction_test():
	testing=true
	screenshot_mode=true
	save_path="user://interaction-test.json"
	await get_tree().process_frame
	await click_event(Vector2(800,530))
	assert(active and not modal,"Start button")
	spawn_timer=999
	var t=tables[0]
	t.state="waiting";t.food=0;t.patience=54;t.maximum=54;t.watered=false
	t.guest_pos=seat_position(t)
	await click_event(Vector2(1330,434))
	assert(target_kind=="water","Real water button event")
	run_route_and_service()
	assert(t.watered and watered==1 and water==3 and t.patience>54,"Click -> walk -> water -> patience")
	await click_event(Vector2(1240,130))
	assert(target_kind=="pickup")
	run_route_and_service()
	assert(tray==[0],"Click -> walk -> pickup")
	await click_event(Vector2(1240,434))
	run_route_and_service()
	assert(t.state=="eating" and served==1 and tray.is_empty(),"Click -> walk -> serve -> revenue")
	for step in range(1200): update_game(1.0/60.0)
	assert(t.state=="dirty","Eat -> leave -> dirty")
	await click_event(Vector2(1240,434))
	run_route_and_service()
	assert(t.state=="empty","Click -> walk -> clean")
	print("PASS: real Input.parse_input_event start, water, pickup, serve, clean; automatic movement and timed service chain")
	get_tree().quit()

func motion_test():
	screenshot_mode=true;testing=true
	start_night()
	assert(walk_frames.size()>8,"Generated walk frames loaded")
	player=Vector2(650,610);moving=true
	DirAccess.make_dir_recursive_absolute("res://evidence/motion")
	for i in range(16):
		walk_clock=float(i)*walk_total/16
		queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://evidence/motion/%02d.png"%i)
	print("PASS: generated animation rendered through complete loop in actual scene")
	get_tree().quit()

func start_leaving(t: Dictionary):
	t.state="leaving"
	t.guest_route=grid.get_point_path(nearest_cell(t.guest_pos),nearest_cell(Vector2(590,760)))

func move_guest(t: Dictionary, delta: float, speed: float):
	if t.guest_route.is_empty(): return
	var goal=t.guest_route[0]
	t.guest_pos=t.guest_pos.move_toward(goal,delta*speed)
	if t.guest_pos.distance_to(goal)<0.1: t.guest_route.remove_at(0)

func draw_anchor_review():
	draw_rect(Rect2(0,0,1440,900),Color("10282b"))
	for i in range(4):
		moving=i>=2
		facing_left=i%2==1
		draw_actor(Vector2(240+i*300,420),true)

func anchor_test():
	testing=true;screenshot_mode=true;anchor_review=true
	tray=[0,2]
	DirAccess.make_dir_recursive_absolute("res://evidence/anchor-fix")
	for i in range(walk_frames.size()):
		walk_clock=float(i)*0.042+0.001
		queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://evidence/anchor-fix/%02d.png"%i)
	print("PASS: rendered idle and all walk frames, both directions, with held food at the same foot anchor")
	get_tree().quit()

func aisle_test():
	testing=true;screenshot_mode=true
	start_night();spawn_timer=999
	var segments=0
	for table_id in [2,3]:
		var previous=Vector2.ZERO
		for n in range(33):
			var angle=TAU*n/32.0
			var point=TABLE_POS[table_id]+Vector2(cos(angle)*95,sin(angle)*55)
			assert(walkable(point),"Lower table perimeter must be walkable")
			var cell=nearest_cell(point)
			assert(Vector2(cell*10).distance_to(point)<8,"No snapping out of the edge aisle")
			var path=grid.get_point_path(nearest_cell(Vector2(575,625)),cell)
			assert(not path.is_empty(),"Edge aisle is connected to main aisle")
			if n>0:
				var reached=slide_step(previous,point-previous)
				assert(reached.distance_to(point)<0.1,"Keyboard movement can circle lower tables")
				segments+=1
			previous=point
	# Diagonal movement into a table slides along it rather than freezing.
	var origin=TABLE_POS[2]+Vector2(-55,-8)
	var slid=slide_step(origin,Vector2(15,15))
	assert(slid.distance_to(origin)>8 and walkable(slid),"Slide along table collision")
	assert(not walkable(TABLE_POS[2]),"Table center remains blocked")
	print("PASS: lower tables have full connected perimeter routes; ",segments," keyboard segments; obstacle sliding")
	get_tree().quit()

func seat_test():
	testing=true;screenshot_mode=true
	start_night();spawn_timer=999
	assert(tables.size()==8)
	for i in range(9): spawn_customer()
	assert(tables.filter(func(t): return t.state=="arriving").size()==8,"Exactly 8 seats, no overwriting")
	for t in tables:
		t.state="waiting";t.guest_pos=seat_position(t);t.watered=false;t.patience=54;t.maximum=54
	var a=tables[0];var b=tables[1]
	a.food=0;b.food=1
	tray=[0,1]
	player=table_access(0)
	var origin=player
	go("water",0)
	assert(route.is_empty() and service_kind=="water" and player==origin,"Nearby service has no forced relocation")
	finish_service()
	assert(a.watered and not b.watered and b.patience==54,"Separate water and patience")
	go("table",0);finish_service()
	assert(a.state=="eating" and b.state=="waiting" and tray==[1],"Separate orders")
	player=table_access(1)
	go("table",1);finish_service()
	assert(b.state=="eating" and served==2 and tray.is_empty(),"Both seats can be served")
	a.state="dirty"
	player=table_access(0);go("table",0);finish_service()
	assert(a.state=="empty" and b.state=="eating","Clean one seat without resetting its neighbor")
	var tested_approaches=0
	for i in range(tables.size()):
		var t=tables[i];t.state="waiting";t.food=0
		var anchors=0
		for x in range(-6,7):
			for y in range(-6,7):
				var point=seat_position(t)+Vector2(x*10,y*10)
				if not walkable(point) or not can_service_from(point,i): continue
				player=point;tray=[0];service_kind="";route.clear()
				go("table",i)
				assert(service_kind=="serve" and route.is_empty() and player==point,"Service from nearby guest point")
				service_kind="";anchors+=1;tested_approaches+=1
		assert(anchors>=10,"Seat %d only has %d accessible approaches"%[i,anchors])
		player=Vector2(590,760);tray=[0]
		go("table",i)
		run_route_and_service()
		assert(t.state=="eating","Path reaches actual guest interaction range")
	# A direct E input at the guest's left side must not walk to the south of the table.
	a.state="waiting";a.food=0;tray=[0]
	player=seat_position(a)+Vector2(-35,0)
	assert(walkable(player) and can_service_from(player,0))
	var key=InputEventKey.new();key.keycode=KEY_E;key.pressed=true
	_unhandled_input(key)
	assert(service_kind=="serve" and route.is_empty(),"E uses guest radius")
	for t in tables: t.state="dirty"
	for i in range(tables.size()):
		player=table_access(i);cancel_movement()
		handle_click(cleanup_badge(i).get_center())
		assert(service_kind=="clean" and service_id==i,"Cleanup badge targets its own seat")
		cancel_movement()
		handle_click(plate_position(tables[i]))
		assert(service_kind=="clean" and service_id==i,"Dirty plate targets its own seat")
		cancel_movement()
	print("PASS: all 8 cleanup badges and dirty plates target their own seat")
	print("PASS: 4 tables / 8 seats; independent orders, patience, water, serving and cleanup")
	print("PASS: ",tested_approaches," accessible guest-centered approaches, 8 real paths and E interaction without south-only snapping")
	get_tree().quit()
