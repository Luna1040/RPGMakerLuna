extends Node2D

var FONT := FontFile.new()
const FIELD = Rect2(55, 220, 1170, 445)
var player := Vector2(260, 470)
var facing := Vector2.RIGHT
var hp := 120.0
var qi := 100.0
var level := 1
var exp_points := 0
var coins := 0
var potions := 3
var stage := 0
var state := "title"
var enemies: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var texts: Array[Dictionary] = []
var attack_cd := 0.0
var skill_cd := 0.0
var dash_cd := 0.0
var invincible := 0.0
var swing := 0.0
var burst := 0.0
var elapsed := 0.0
var kills := 0
var message := "与韦大宝交谈，踏上你的江湖第一战。"
var paused := false

func _init() -> void:
	FONT.data = FileAccess.get_file_as_bytes("res://font.ttf")

func _ready() -> void:
	ThemeDB.fallback_font = FONT
	queue_redraw()

func reset_game() -> void:
	player = Vector2(260,470)
	facing = Vector2.RIGHT
	hp = 120
	qi = 100
	level = 1
	exp_points = 0
	coins = 0
	potions = 3
	stage = 0
	kills = 0
	elapsed = 0
	attack_cd = 0
	skill_cd = 0
	dash_cd = 0
	invincible = 0
	swing = 0
	burst = 0
	paused = false
	enemies.clear()
	drops.clear()
	texts.clear()
	state = "play"
	message = "靠近韦大宝按 E 接取委托 · 药品有限，注意闪避。"
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := get_global_mouse_position()
		if state != "play" and Rect2(490,548,300,58).has_point(p): reset_game()
		elif state == "play" and Rect2(1080,25,155,42).has_point(p): paused = not paused
	if not event is InputEventKey or not event.pressed or event.echo: return
	if state != "play":
		if event.keycode in [KEY_ENTER, KEY_R, KEY_SPACE]: reset_game()
		return
	if event.keycode == KEY_ESCAPE: paused = not paused
	if paused: return
	match event.keycode:
		KEY_J, KEY_SPACE: strike(false)
		KEY_Q: strike(true)
		KEY_SHIFT: dash()
		KEY_H: heal()
		KEY_E: interact()

func interact() -> void:
	if stage == 0 and player.distance_to(Vector2(410,400)) < 110:
		stage = 1
		spawn_wave()
	elif stage > 0 and enemies.is_empty() and player.x > 1080:
		if stage == 3:
			coins += 200
			state = "win"
		else:
			stage += 1
			player = Vector2(160,470)
			hp = minf(max_hp(), hp + 25)
			qi = minf(100, qi + 35)
			spawn_wave()
	else:
		message = "靠近韦大宝接委托。" if stage == 0 else ("清场后到右侧出口按 E 前进。" if enemies.is_empty() else "先击败本区域所有敌人！")

func max_hp() -> float:
	return 120.0 + (level - 1) * 25.0

func spawn_wave() -> void:
	drops.clear()
	var count := 4 if stage == 1 else (5 if stage == 2 else 3)
	for i in range(count):
		var boss := stage == 3 and i == count - 1
		var health := 340.0 if boss else (62.0 + stage * 10)
		enemies.append({"pos": Vector2(720+i*95, 300+(i%3)*130), "hp":health, "max":health, "boss":boss, "cool":1.0+i*0.2, "wind":0.0, "target":Vector2.ZERO, "flash":0.0})
	message = ["", "委托一：清理山道的四名刀客", "委托二：突破竹林伏击", "最终战：击败赤风寨主，夺回镖银"][stage]

func strike(skill: bool) -> void:
	if skill:
		if skill_cd > 0 or qi < 30:
			message = "气功需 30 真气，冷却 4 秒。"
			return
		skill_cd = 4
		qi -= 30
		burst = 0.35
	else:
		if attack_cd > 0: return
		attack_cd = 0.38
		swing = 0.2
	var hit := false
	for e in enemies:
		var offset: Vector2 = e.pos - player
		if offset.length() < (205 if skill else 108) and (skill or offset.normalized().dot(facing) > -0.1):
			var damage := (45 if skill else 23) + (level - 1)*7
			e.hp -= damage
			e.flash = 0.18
			e.pos += offset.normalized() * (22 if e.boss else 40)
			floating(e.pos, str(damage), Color("ffdb83"))
			hit = true
	if hit: message = "烈焰气功！" if skill else "刀锋命中 · 连击追敌"
	remove_dead()

func remove_dead() -> void:
	for i in range(enemies.size()-1,-1,-1):
		if enemies[i].hp > 0: continue
		var e := enemies[i]
		kills += 1
		exp_points += 75 if e.boss else 25
		drops.append({"pos":e.pos, "value":80 if e.boss else 15})
		enemies.remove_at(i)
		if exp_points >= 75 and level < 4:
			exp_points -= 75
			level += 1
			hp = max_hp()
			qi = 100
			floating(player, "升级！生命与真气恢复", Color("aef7c5"))
	if enemies.is_empty() and stage > 0:
		message = "区域已清！拾取镖银，前往右侧金色出口按 E。"

func dash() -> void:
	if dash_cd > 0: return
	dash_cd = 1.8
	invincible = 0.45
	player = clamp_position(player + facing * 140)
	floating(player, "轻功", Color("94e4ec"))

func heal() -> void:
	if potions <= 0:
		message = "金创药已用尽！升级或通关区域可恢复生命。"
		return
	if hp >= max_hp():
		message = "生命已满，无需用药。"
		return
	potions -= 1
	hp = minf(max_hp(), hp + 65)
	floating(player, "+65 生命", Color("aef7c5"))

func floating(at: Vector2, label: String, color: Color) -> void:
	texts.append({"pos":at-Vector2(0,65), "text":label, "color":color, "life":1.2})

func clamp_position(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x,80,1200),clampf(p.y,255,630))

func _process(dt: float) -> void:
	if state != "play" or paused:
		queue_redraw()
		return
	elapsed += dt
	attack_cd = maxf(0, attack_cd-dt)
	skill_cd = maxf(0, skill_cd-dt)
	dash_cd = maxf(0, dash_cd-dt)
	invincible = maxf(0, invincible-dt)
	swing = maxf(0, swing-dt)
	burst = maxf(0, burst-dt)
	qi = minf(100, qi+dt*7)
	var movement := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if movement.length() > 0:
		facing = movement.normalized()
		player = clamp_position(player + facing*230*dt)
	for e in enemies:
		e.flash = maxf(0,e.flash-dt)
		e.cool -= dt
		if e.wind > 0:
			e.wind -= dt
			if e.wind <= 0:
				var radius := 115.0 if e.boss else 65.0
				if player.distance_to(e.target) < radius and invincible <= 0:
					hp -= 26 if e.boss else 12
					invincible = 0.55
					floating(player, "-26" if e.boss else "-12", Color("ff8275"))
					e.cool = 1.4 if e.boss else 1.1
		else:
			var distance: float = e.pos.distance_to(player)
			if distance > (95 if e.boss else 50):
				e.pos = clamp_position(e.pos + e.pos.direction_to(player)*(72 if e.boss else 100)*dt)
			elif e.cool <= 0:
				e.wind = 0.85 if e.boss else 0.5
				e.target = player
	for i in range(drops.size()-1,-1,-1):
		if player.distance_to(drops[i].pos) < 38:
			coins += drops[i].value
			floating(player,"+%d 镖银" % drops[i].value,Color("f8d078"))
			drops.remove_at(i)
	for i in range(texts.size()-1,-1,-1):
		texts[i].life -= dt
		texts[i].pos.y -= dt*30
		if texts[i].life <= 0: texts.remove_at(i)
	if hp <= 0:
		hp = 0
		state = "lose"
	queue_redraw()

func label_at(p: Vector2, value: String, size: int = 20, color: Color = Color("e9dfc6")) -> void:
	draw_string(FONT,p,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func panel(rect: Rect2, color: Color = Color("152b31")) -> void:
	draw_style_box(make_style(color),rect)

func make_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("8c7955")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style

func bar(p: Vector2, size: Vector2, ratio: float, color: Color) -> void:
	draw_rect(Rect2(p,size),Color("0a171d"))
	draw_rect(Rect2(p,Vector2(size.x*clampf(ratio,0,1),size.y)),color)

func fighter(p: Vector2, color: Color, hero: bool, boss: bool = false, flash: bool = false) -> void:
	var scale_factor := 1.4 if boss else 1.0
	draw_set_transform(p,0,Vector2.ONE*scale_factor)
	draw_ellipse_shadow()
	var c := Color.WHITE if flash else color
	draw_line(Vector2(-8,-12),Vector2(-12,0),Color("1c2730"),9)
	draw_line(Vector2(8,-12),Vector2(12,0),Color("1c2730"),9)
	draw_colored_polygon(PackedVector2Array([Vector2(-15,-40),Vector2(14,-40),Vector2(22,-12),Vector2(-23,-12)]),c)
	draw_line(Vector2(-16,-17),Vector2(16,-17),Color("efd38c"),4)
	draw_circle(Vector2(0,-52),11,Color("ebbf98"))
	draw_arc(Vector2(0,-56),12,PI,TAU,12,Color("192331"),8)
	draw_line(Vector2(0,-61),Vector2(-15,-71),Color("d05742") if hero else Color("4a302d"),5)
	var sword_end := Vector2(44,-57) if hero else Vector2(-43,-39)
	draw_line(Vector2(12,-34),sword_end,Color("d5e9e1"),5)
	draw_line(Vector2(18,-35),Vector2(28,-27),Color("e5bb66"),4)
	draw_set_transform(Vector2.ZERO)

func draw_ellipse_shadow() -> void:
	draw_circle(Vector2(0,-2),17,Color(0,0,0,0.2))

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,800),Color("0c1b23"))
	# Temporary code-drawn arena. AI production is blocked; no generated assets claimed.
	draw_rect(FIELD,Color("304f48") if stage != 3 else Color("50413c"))
	for i in range(18):
		var x := 60+i*70
		draw_line(Vector2(x,225),Vector2(x+30,660),Color(0.7,0.7,0.5,0.06),1)
	draw_rect(Rect2(65,405,1150,110),Color(0.75,0.63,0.43,0.14))
	for i in range(16):
		var x := 75+i*76
		for y in [230,665]:
			draw_line(Vector2(x,y),Vector2(x-8,y-65),Color("648b64"),5)
			draw_line(Vector2(x-6,y-45),Vector2(x+16,y-65),Color("709568"),3)
	if stage == 0:
		fighter(Vector2(410,400),Color("b28c57"),false)
		label_at(Vector2(357,315),"韦大宝",22)
		label_at(Vector2(342,342),"E · 接取委托",18,Color("f4ce82"))
	if enemies.is_empty() and stage > 0:
		draw_rect(Rect2(1120,345,65,190),Color(0.95,0.75,0.3,0.22))
		label_at(Vector2(1080,322),"E · 交镖" if stage == 3 else "E · 下一关",20,Color("ffdc8f"))
	for e in enemies:
		if e.wind > 0:
			draw_circle(e.target,115 if e.boss else 65,Color(1,0.24,0.14,0.16))
			draw_arc(e.target,115 if e.boss else 65,0,TAU,48,Color("ff8975"),2)
		fighter(e.pos,Color("9f5144") if e.boss else Color("6e6c88"),false,e.boss,e.flash>0)
		bar(e.pos+Vector2(-30,-90 if e.boss else -80),Vector2(60,6),e.hp/e.max,Color("e58269"))
		label_at(e.pos+Vector2(-42,-102 if e.boss else -88),"赤风寨主" if e.boss else "山寨刀客",15)
	for d in drops:
		draw_circle(d.pos,9,Color("deb46c"))
		label_at(d.pos+Vector2(-14,-15),"银",16)
	if burst > 0:
		draw_circle(player,205*(1-burst/0.35),Color(0.95,0.68,0.22,burst))
	if swing > 0:
		var angle := facing.angle()
		draw_arc(player,100,angle-1.2,angle+1.2,24,Color("fff1ac"),7)
	fighter(player,Color("3c9baf"),true,false,invincible>0)
	for t in texts: label_at(t.pos,t.text,21,t.color)
	panel(Rect2(35,20,1010,78))
	label_at(Vector2(55,53),"热血江湖  /  单机试炼",27,Color("f3cf88"))
	label_at(Vector2(55,81),"刀客 · Lv.%d     镖银 %d     金创药 ×%d" % [level,coins,potions],18)
	bar(Vector2(460,40),Vector2(230,14),hp/max_hp(),Color("d66b62"))
	label_at(Vector2(705,53),"生命 %d/%d" % [hp,max_hp()],16)
	bar(Vector2(460,66),Vector2(230,10),qi/100,Color("58bdc6"))
	label_at(Vector2(705,80),"真气 %d    经验 %d/75" % [qi,exp_points],16)
	panel(Rect2(1080,25,155,42))
	label_at(Vector2(1093,53),"继续" if paused else "ESC · 暂停",20)
	panel(Rect2(35,115,1210,85))
	label_at(Vector2(55,148),["泫勃镇 · 镖行委托", "一 / 泫勃山道", "二 / 竹林险路", "三 / 赤风山寨"][stage],23,Color("f3cf88"))
	label_at(Vector2(55,180),message,20)
	label_at(Vector2(950,150),"击败 %d   剩余 %d" % [kills,enemies.size()],18)
	panel(Rect2(35,690,1210,90))
	label_at(Vector2(55,722),"WASD / 方向键 移动    J / 空格 挥刀    Q 气功    Shift 轻功    H 金创药    E 对话 / 出口",19)
	label_at(Vector2(55,754),"气功 %s   轻功 %s   · 红圈是敌人攻击预警，移开或轻功闪避 · 美术：临时绘制" % ["就绪" if skill_cd<=0 else "%.1fs" % skill_cd,"就绪" if dash_cd<=0 else "%.1fs" % dash_cd],18,Color("a6c4bf"))
	if state != "play" or paused:
		draw_rect(Rect2(0,0,1280,800),Color(0.02,0.06,0.09,0.86))
		panel(Rect2(270,165,740,475),Color("132930"))
		var title := "热血江湖 · 镖行风云"
		if state == "win": title = "镖银归来 · 名动泫勃"
		elif state == "lose": title = "胜败乃兵家常事"
		elif paused: title = "暂歇片刻"
		label_at(Vector2(345,247),title,38,Color("f4d08d"))
		if state == "title":
			label_at(Vector2(345,303),"一人，一柄刀，一段江湖路。",25)
			label_at(Vector2(345,353),"接受镖行委托，闯过山道与竹林，击败赤风寨主。",21)
			label_at(Vector2(345,398),"近身挥刀积累经验；气功破围；轻功避开红圈。",21)
			label_at(Vector2(345,443),"三瓶金创药随身携带，升级可恢复生命与真气。",21)
			label_at(Vector2(345,493),"原创简化单机原型 · 非官方网游复刻",18,Color("a6c4bf"))
		elif paused:
			label_at(Vector2(345,335),"ESC 或点击右上角继续。",24)
			label_at(Vector2(345,390),"目标：清场后到右侧金色出口按 E。",22)
		else:
			label_at(Vector2(345,328),"你守住了镖行的信誉！" if state == "win" else "红圈出手前使用轻功；靠近敌人挥刀。",23)
			label_at(Vector2(345,388),"等级 %d    击败 %d    镖银 %d    用时 %d 秒" % [level,kills,coins,elapsed],22)
			label_at(Vector2(345,446),"按 R / Enter 或点击下方，再闯一次江湖。",21)
		if not paused:
			panel(Rect2(490,548,300,58),Color("795d37"))
			label_at(Vector2(535,586),"踏入江湖 · Enter" if state == "title" else "重新出发 · R",24)
