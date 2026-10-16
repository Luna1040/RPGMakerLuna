extends Node2D
# All gameplay positions use a fixed logical canvas; no enlarged bitmap sprites.
const FIELD := Rect2(30, 150, 940, 580)
const HOME := Vector2(140, 440)
const GOLD := Color("ffcf7a")
const CYAN := Color("6aefd7")
const WHITE := Color("e7f1ff")
const MUTED := Color("93a9c9")
const SECTORS := ["静谧星湾", "紫晶风暴", "日冕遗迹"]
const UPGRADES := ["星砂精炼", "能源电池", "引力采集", "脉冲引擎"]
const COSTS := [22, 26, 20, 24]
const SAVE := "user://starlight_progress_v2.json"
var ui_font: Font = preload("res://font.ttf")
var player := HOME
var heading := Vector2.RIGHT
var sector := 0
var selected_sector := 0
var mode := "dock"
var bank := 0
var cores := 0
var gates := 0
var flights := 0
var total_banked := 0
var levels: Array = [0,0,0,0]
var cargo := 0
var cargo_cores := 0
var energy := 100.0
var hull := 3
var clock := 0.0
var flight_time := 0.0
var hit_cd := 0.0
var dash_left := 0.0
var dash_direction:=Vector2.RIGHT
var dash_cd := 0.0
var scan_left := 0.0
var scan_cd := 0.0
var combo := 0
var combo_left := 0.0
var combo_best := 0
var stars: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var background: Array[Dictionary] = []
var message := "欢迎归航。击破敌机、升级武器，挑战星蚀方舟。"
var result := "第一座星门：需要 36 星砂 + 1 星核"
var save_enabled := true
var save_path := SAVE
var rng := RandomNumberGenerator.new()
var art: Dictionary={}
var animation_art: Dictionary={}
var trail: Array[Dictionary]=[]
var gate_open_left:=0.0
var gate_open_index:=-1
var combat
var combat_enabled:=true

func _ready() -> void:
	rng.seed=72491
	for i in 110:
		background.append({"p":Vector2(rng.randf_range(32,967),rng.randf_range(152,728)),"size":rng.randf_range(.6,1.8),"phase":rng.randf()*TAU})
	load_art()
	combat=preload("res://combat.gd").new(self)
	var vfx=preload("res://combat_vfx.gd").new()
	vfx.combat=combat; vfx.name="Effects"
	var effects_clip:=Control.new()
	effects_clip.name="CombatVFX"; effects_clip.position=FIELD.position; effects_clip.size=FIELD.size
	effects_clip.clip_contents=true; effects_clip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	vfx.position=-FIELD.position; effects_clip.add_child(vfx)
	var projectile_layer=preload("res://projectiles.gd").new()
	projectile_layer.combat=combat; projectile_layer.position=-FIELD.position
	effects_clip.add_child(projectile_layer)
	add_child(effects_clip)
	load_progress()
	queue_redraw()

func capacity() -> int: return 18+int(levels[0])*8
func max_energy() -> float: return 100.0+float(levels[1])*25.0
func collect_radius() -> float: return 23.0+float(levels[2])*13.0+(combat.stacks("magnet")*22 if combat!=null else 0)
func speed() -> float: return 195.0+float(levels[3])*18.0
func upgrade_cost(index: int) -> int: return int(COSTS[index])*(int(levels[index])+1)
func gate_cost() -> int: return 36+gates*28
func unlocked() -> int: return mini(gates,2)

func launch() -> void:
	if mode!="dock": return
	sector=mini(selected_sector,unlocked())
	mode="flight"
	combat.reset()
	player=HOME
	cargo=0
	cargo_cores=0
	energy=max_energy()
	hull=3
	flight_time=0
	dash_cd=0
	scan_cd=0
	dash_left=0
	hit_cd=0
	combo=0
	combo_left=0
	stars.clear()
	hazards.clear()
	rng.randomize()
	for i in 35:
		var pos:=Vector2(rng.randf_range(295,920),rng.randf_range(195,685))
		stars.append({"p":pos,"core":false,"value":1+sector,"phase":rng.randf()*TAU})
	for i in 2+sector:
		stars.append({"p":Vector2(610+i*80,240+(i%2)*350),"core":true,"value":0,"phase":float(i)})
	for i in 4+sector*3:
		hazards.append({"center":Vector2(375+i%4*160,285+i/4*145),"p":Vector2.ZERO,"radius":26.0+sector*3,"phase":rng.randf()*TAU,"orbit":40.0+rng.randf()*30})
	message="自动射击已启动 · 空格闪避 / Q 清弹 · 坚持 150 秒迎战 Boss。"

func buy(index: int) -> bool:
	if mode!="dock" or index<0 or index>3 or int(levels[index])>=4: return false
	var cost:=upgrade_cost(index)
	if bank<cost:
		message="星砂不足：升级需要 %d，当前 %d。" % [cost,bank]
		return false
	bank-=cost
	levels[index]=int(levels[index])+1
	message=UPGRADES[index]+" 已升级至 Lv.%d" % levels[index]
	save_progress()
	return true

func repair_gate() -> bool:
	if mode!="dock" or gates>=3: return false
	if bank<gate_cost() or cores<gates+1:
		message="修复需要 %d 星砂 + %d 星核，先返航储存资源。" % [gate_cost(),gates+1]
		return false
	bank-=gate_cost()
	cores-=gates+1
	gates+=1
	gate_open_index=gates-1
	gate_open_left=5.0
	selected_sector=unlocked()
	result="星门 %d / 3 已点亮 · %s" % [gates,"新的星域已开放" if gates<3 else "星路重连！继续探索，完成全套升级。"]
	message=result
	save_progress()
	return true

func bank_cargo(emergency: bool = false) -> void:
	if mode!="flight": return
	var kept:=int(floor(cargo*.5)) if emergency else cargo
	bank+=kept
	total_banked+=kept
	if not emergency: cores+=cargo_cores
	flights+=1
	result=("紧急救援 · 保留一半星砂，星核遗失" if emergency else "安全返航 · 所有资源已存入仓库")
	message="本航次 +%d 星砂 / +%d 星核 · 连采纪录 %d" % [kept,0 if emergency else cargo_cores,combo_best]
	cargo=0
	cargo_cores=0
	mode="dock"
	player=HOME
	particles.clear()
	save_progress()

func trigger_dash() -> void:
	if mode=="flight" and dash_cd<=0 and energy>8:
		energy-=8
		dash_left=.22
		var movement:=Input.get_vector("ui_left","ui_right","ui_up","ui_down")
		dash_direction=movement.normalized() if movement.length()>0 else heading
		dash_cd=maxf(.7,3.0-float(levels[3])*.35)/(1+combat.stacks("dash")*.15)

func trigger_scan() -> void:
	if mode=="flight" and scan_cd<=0:
		scan_left=3.0
		scan_cd=12.0
		message="扫描：青色指示线指向星核；青色圆环内自动采集。"

func interact() -> void:
	if mode=="dock": launch()
	elif player.distance_to(HOME)<72: bank_cargo()
	else: message="返回左侧空间站光环，按 E 卸货。"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton: _unhandled_key_input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if combat_enabled and mode=="flight" and combat.choice:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_1,KEY_2,KEY_3]: combat.choose(event.keycode-KEY_1)
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			for i in 3:
				if Rect2(110+i*278,390,260,145).has_point(get_global_mouse_position()): combat.choose(i)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E,KEY_ENTER: interact()
			KEY_SPACE: trigger_dash()
			KEY_Q:
				if combat_enabled: combat.pulse()
				else: trigger_scan()
			KEY_1: buy(0)
			KEY_2: buy(1)
			KEY_3: buy(2)
			KEY_4: buy(3)
			KEY_G: repair_gate()
			KEY_TAB:
				if mode=="dock": selected_sector=(selected_sector+1)%(unlocked()+1)
			KEY_R:
				if mode=="flight": message="本版不会一键清空进度。返回空间站按 E，失败也保留仓库。"
		queue_redraw()
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var mouse:=get_global_mouse_position()
		if mode=="dock":
			for i in 4:
				if Rect2(1000,320+i*66,250,55).has_point(mouse): buy(i)
			if Rect2(1000,611,250,44).has_point(mouse): repair_gate()
			if Rect2(1000,669,250,46).has_point(mouse): launch()
			if Rect2(1000,180,250,105).has_point(mouse): selected_sector=(selected_sector+1)%(unlocked()+1)
		elif Rect2(1000,669,250,46).has_point(mouse): interact()

func _process(delta: float) -> void:
	clock+=delta
	gate_open_left=maxf(0,gate_open_left-delta)
	for i in range(trail.size()-1,-1,-1):
		trail[i].life-=delta
		if trail[i].life<=0: trail.remove_at(i)
	if mode=="flight": trail.append({"p":player,"life":.3})
	for i in range(particles.size()-1,-1,-1):
		particles[i].life-=delta
		particles[i].p+=particles[i].v*delta
		if particles[i].life<=0: particles.remove_at(i)
	if mode=="flight":
		var remaining:=minf(delta,.2)
		var movement:=Input.get_vector("ui_left","ui_right","ui_up","ui_down")
		while remaining>0.00001 and mode=="flight":
			var step:=minf(remaining,1.0/60.0)
			step_flight(step,movement)
			remaining-=step
	queue_redraw()

func step_flight(dt: float, direction: Vector2) -> void:
	if mode!="flight": return
	if combat_enabled and combat.choice: return
	if combat_enabled and combat.won:
		combat.step(dt)
		return
	flight_time+=dt
	energy=maxf(0,energy-dt*((.12+sector*.04) if combat_enabled else (1.0+sector*.22)))
	hit_cd=maxf(0,hit_cd-dt)
	dash_cd=maxf(0,dash_cd-dt)
	scan_cd=maxf(0,scan_cd-dt)
	scan_left=maxf(0,scan_left-dt)
	combo_left=maxf(0,combo_left-dt)
	if combo_left==0: combo=0
	if direction.length()>0: heading=direction.normalized()
	player+=(dash_direction*speed()*3.4 if dash_left>0 else direction*speed())*dt
	dash_left=maxf(0,dash_left-dt)
	player=player.clamp(FIELD.position+Vector2(20,20),FIELD.end-Vector2(20,20))
	# Advanced sectors change routing rather than only increasing object counts.
	if sector==1 and player.distance_to(Vector2(650,440))<125:
		energy=maxf(0,energy-dt*2.0)
	if sector==2 and fmod(flight_time,10.0)>=7.0 and player.x>530 and player.x<710 and hit_cd==0 and dash_left==0:
		hull-=1
		hit_cd=1.6
		burst(player,Color("ff748c"))
		message="日冕喷发！避开竖向红区，或冲刺穿越。"
	for hazard in hazards:
		var angle: float=flight_time*(.45+sector*.2)+float(hazard.phase)
		hazard.p=hazard.center+Vector2(cos(angle)*hazard.orbit,sin(angle)*hazard.orbit*.65)
		if player.distance_to(hazard.p)<float(hazard.radius)+12 and hit_cd==0 and dash_left==0:
			hull-=1
			hit_cd=1.6
			combo=0
			burst(player,Color("ff748c"))
			message="船体受损！冲刺期间可穿过危险，尽快返航。"
	for i in range(stars.size()-1,-1,-1):
		var star: Dictionary=stars[i]
		if combat_enabled and combat.stacks("magnet")>0 and player.distance_to(star.p)<collect_radius()*2:
			star.p=Vector2(star.p).move_toward(player,dt*180)
		if player.distance_to(star.p)<=collect_radius():
			if not combat_enabled and not star.core and cargo>=capacity(): continue
			if star.core: cargo_cores+=1
			else:
				combo+=1
				combo_left=4.5
				combo_best=maxi(combo_best,combo)
				var gain:=int(star.value)+(1 if combo%5==0 else 0)
				cargo=cargo+gain+int(levels[0]) if combat_enabled else mini(capacity(),cargo+gain)
			burst(star.p,CYAN if star.core else GOLD)
			stars.remove_at(i)
	if combat_enabled:
		combat.step(dt)
		scan_left=1.0
	if hull<=0 or energy<=0: bank_cargo(true)
	elif not combat_enabled and stars.is_empty(): message="星域已清空。返回左侧空间站，按 E 安全返航。"
	elif not combat_enabled and cargo>=capacity(): message="货舱已满！还可寻找星核，或立即返回空间站卸货。"

func burst(at: Vector2, tint: Color) -> void:
	for i in 9:
		var angle:=rng.randf()*TAU
		particles.append({"p":at,"v":Vector2(cos(angle),sin(angle))*rng.randf_range(30,100),"life":.6,"tint":tint})

func save_progress() -> bool:
	if not save_enabled: return true
	var data: Dictionary={"version":2,"bank":bank,"cores":cores,"gates":gates,"flights":flights,"levels":levels,"total":total_banked,"combo":combo_best}
	var file:=FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if file==null:
		message="保存失败，请保持游戏打开。"
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	var error:=DirAccess.rename_absolute(save_path+".tmp",save_path)
	if error!=OK: message="保存失败，请检查存档目录。"
	return error==OK

func load_progress() -> bool:
	if not FileAccess.file_exists(save_path): return false
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(save_path))!=OK: return false
	var data=parser.data
	if not data is Dictionary or data.get("version")!=2: return false
	for key in ["bank","cores","gates","flights","total","combo"]:
		if not data.get(key) is float and not data.get(key) is int: return false
		if not is_finite(float(data[key])) or float(data[key])<0 or float(data[key])>10000000: return false
	if data.gates>3 or not data.get("levels") is Array or data.levels.size()!=4: return false
	for level in data.levels:
		if (not level is float and not level is int) or level<0 or level>4 or level!=floor(level): return false
	bank=int(data.bank); cores=int(data.cores); gates=int(data.gates); flights=int(data.flights)
	total_banked=int(data.total); combo_best=int(data.combo); levels=data.levels.duplicate()
	selected_sector=unlocked()
	message="欢迎回来。仓库、飞船升级与星门进度已恢复。"
	return true

func text_at(value: String, at: Vector2, size: int=18, tint: Color=WHITE) -> void:
	draw_string(ui_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,tint)

func panel(rect: Rect2, tint: Color=Color("101e35"), border: Color=Color("29445b")) -> void:
	var style:=StyleBoxFlat.new()
	style.bg_color=tint; style.border_color=border
	style.set_border_width_all(1); style.set_corner_radius_all(12)
	draw_style_box(style,rect)

func star_shape(at: Vector2, radius: float, tint: Color, rotation: float=0) -> void:
	var points:=PackedVector2Array()
	for i in 8:
		var angle: float=i*PI/4+rotation
		points.append(at+Vector2(cos(angle),sin(angle))*(radius if i%2==0 else radius*.28))
	draw_colored_polygon(points,tint)

func load_art() -> void:
	for name in ["starfield","violet","solar","ship","station","gate","stardust","core","meteor"]:
		var path: String="res://assets/gpt-v1/"+name+".png"
		if ResourceLoader.exists(path): art[name]=load(path)
	for name in ["ship","station","gate","gate-open","boss"]:
		var path: String="res://assets/h3-v1/"+name+"/"
		if FileAccess.file_exists(path+"manifest.json") and ResourceLoader.exists(path+"atlas.png"):
			var spec=JSON.parse_string(FileAccess.get_file_as_string(path+"manifest.json"))
			spec.texture=load(path+"atlas.png")
			animation_art[name]=spec

func art_sprite(name: String, at: Vector2, size: float, angle: float=0, tint: Color=Color.WHITE, animated: bool=true, frame_override: int=-1) -> void:
	if not art.has(name) and not animation_art.has(name): return
	draw_set_transform(at,angle)
	if animated and animation_art.has(name):
		var clip: Dictionary=animation_art[name]
		var index:=int(clock*float(clip.fps))%int(clip.frames)
		if name=="gate-open": index=clampi(int((5.0-gate_open_left)*float(clip.fps)),0,int(clip.frames)-1)
		if frame_override>=0: index=clampi(frame_override,0,int(clip.frames)-1)
		var tile:=float(clip.tile)
		var source:=Rect2((index%int(clip.columns))*tile,(index/int(clip.columns))*tile,tile,tile)
		# Video references occupy 570/768 of the canvas; compensate once for every frame.
		var frame_size:=size*768.0/570.0
		draw_texture_rect_region(clip.texture,Rect2(-frame_size/2,-frame_size/2,frame_size,frame_size),source,tint)
	else:
		draw_texture_rect(art[name],Rect2(-size/2,-size/2,size,size),false,tint)
	draw_set_transform(Vector2.ZERO)

func ship(at: Vector2, direction: Vector2, size: float=1.0) -> void:
	art_sprite("ship",at,86*size,direction.angle(),Color.WHITE if hit_cd==0 or sin(clock*28)>0 else Color("ff718c"))

func meter(at: Vector2, width: float, ratio: float, tint: Color) -> void:
	draw_rect(Rect2(at,Vector2(width,5)),Color("273b53"))
	draw_rect(Rect2(at,Vector2(width*clampf(ratio,0,1),5)),tint)

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,800),Color("080f20"))
	if art.has("starfield"):
		var region:=selected_sector if mode=="dock" else sector
		var texture: Texture2D=art[["starfield","violet","solar"][region]]
		var factor:=maxf(1280.0/texture.get_width(),800.0/texture.get_height())
		var extent:=texture.get_size()*factor
		draw_texture_rect(texture,Rect2((Vector2(1280,800)-extent)*.5,extent),false)
	draw_rect(Rect2(0,0,1280,145),Color(.015,.035,.065,.87))
	draw_rect(Rect2(0,735,1280,65),Color(.015,.035,.065,.88))
	text_at("S T A R F A L L   /   星光采集",Vector2(32,51),26)
	text_at("弹幕远征 · 战地进化 · 满载归航",Vector2(34,81),16,MUTED)
	text_at("星门  %d / 3" % gates,Vector2(1030,49),24,GOLD)
	text_at("仓库  %d 星砂   %d 星核" % [bank,cores],Vector2(1000,83),16,CYAN)
	panel(Rect2(30,104,940,34),Color("12263b"))
	text_at(message,Vector2(44,127),16,WHITE)
	panel(FIELD,Color(.02,.05,.09,.18),Color(.5,.68,.72,.3))
	# Background remains full resolution; foreground objects are independent generated assets.
	if mode=="dock":
		for i in 3:
			var at:=Vector2(440+i*174,435)
			if i>=gates and animation_art.has("gate-open"):
				art_sprite("gate-open",at,142,0,Color(.65,.7,.8,1),true,0)
			else:
				art_sprite("gate-open" if gate_open_left>0 and i==gate_open_index and animation_art.has("gate-open") else "gate",at,142,0,Color.WHITE if i<gates else Color(.4,.47,.57,.8),i<gates)
			text_at("0%d  %s" % [i+1,"已点亮" if i<gates else "待修复"],at+Vector2(-48,104),16,CYAN if i<gates else MUTED)
			text_at(SECTORS[i],at+Vector2(-40,128),15,MUTED)
	art_sprite("station",HOME,160)
	draw_arc(HOME,80,0,TAU,80,Color(.3,.95,.8,.2),1,true)
	text_at("归航空间站",HOME+Vector2(-40,108),16,CYAN)
	if mode=="dock":
		text_at("重连失落的星路",Vector2(330,230),36,WHITE)
		text_at("击破编队 → 三次武器进化 → 星蚀方舟 Boss",Vector2(330,270),18,MUTED)
		text_at(result,Vector2(330,594),18,GOLD)
		text_at("自动射击 / 方向键闪避 / 空格冲刺 / Q 清弹",Vector2(330,635),17,MUTED)
		text_at("E 出航或卸货  /  1–4 升级  /  G 修复星门",Vector2(330,666),17,MUTED)
		ship(HOME+Vector2(8,180),Vector2.RIGHT,1.35)
	else:
		if sector==1:
			draw_circle(Vector2(650,440),125,Color(.65,.3,1,.1))
			draw_arc(Vector2(650,440),125,0,TAU,80,Color("a78ae1"),2,true)
			text_at("离子云：能源消耗 ×3",Vector2(540,190),16,Color("cab4f4"))
		if sector==2:
			var phase:=fmod(flight_time,10.0)
			if phase>=4.0:
				draw_rect(Rect2(530,151,180,578),Color(1,.3,.2,.18 if phase>=7 else .05))
				draw_line(Vector2(530,152),Vector2(530,728),Color("ff897a"),2)
				draw_line(Vector2(710,152),Vector2(710,728),Color("ff897a"),2)
			text_at("日冕喷发！避开红区" if phase>=7 else "日冕预警：%.0f 秒后喷发" % (7-phase),Vector2(520,190),16,Color("ffb29f"))
		for hazard in hazards:
			var at: Vector2=hazard.p
			var radius: float=hazard.radius
			draw_circle(at,radius+5,Color(1,.3,.46,.045))
			art_sprite("meteor",at,radius*2.6,clock*.07+float(hazard.phase))
		for star in stars:
			var tint:=CYAN if star.core else GOLD
			var radius:=19.0 if star.core else 11.0
			draw_circle(star.p,radius+8,Color(tint,.06))
			art_sprite("core" if star.core else "stardust",star.p,(48.0 if star.core else 27.0)*(1+sin(clock*2+star.phase)*.045))
			if star.core and scan_left>0: draw_dashed_line(player,star.p,Color(CYAN,.4),1,8)
		for point in trail:
			draw_circle(point.p,2 if dash_left==0 else 4,Color(.25,.9,1,float(point.life)*.4))
		if scan_left>0: draw_arc(player,collect_radius(),0,TAU,40,CYAN,1,true)
		if cargo>0: draw_dashed_line(player,HOME,Color(.4,.9,.8,.12),1,12)
		ship(player,heading)
		for part in particles: draw_circle(part.p,2,Color(part.tint,float(part.life)/.6))
		if player.distance_to(HOME)<72: text_at("E  安全卸货",HOME+Vector2(-42,-84),18,CYAN)
	if combat_enabled: combat.render()
	# Right command deck.
	panel(Rect2(990,104,270,626),Color(.025,.06,.1,.94),Color("596b6b"))
	text_at("航 行 控 制",Vector2(1007,137),18,CYAN)
	panel(Rect2(1000,163,250,122),Color("17273d"))
	text_at(SECTORS[selected_sector if mode=="dock" else sector],Vector2(1014,193),24)
	text_at("星砂价值 ×%d / 风险 %d" % [(selected_sector if mode=="dock" else sector)+1,(selected_sector if mode=="dock" else sector)+1],Vector2(1014,225),16,GOLD)
	text_at("TAB / 点击切换已开放星域" if mode=="dock" else ("Boss 接近：%d 秒" % maxi(0,ceili(150-combat.elapsed)) if not combat.boss_spawned else "击破 Boss：自动回收返航"),Vector2(1014,257),15,MUTED)
	if mode=="dock":
		text_at("飞船工坊  /  永久升级",Vector2(1007,309),17,MUTED)
		for i in 4:
			var y:=320+i*66
			var available: bool=bank>=upgrade_cost(i) and int(levels[i])<4
			panel(Rect2(1000,y,250,55),Color("182d3b") if available else Color("142136"),CYAN if available else Color("29445b"))
			text_at("[%d] %s  %d/4" % [i+1,UPGRADES[i],levels[i]],Vector2(1012,y+23),17)
			var details: Array=["每次采集价值 +1","能源 +25","范围 +13","速度 / 冲刺冷却"]
			text_at("%s · %s" % [details[i],"已满级" if levels[i]>=4 else "%d 星砂" % upgrade_cost(i)],Vector2(1012,y+45),14,GOLD)
		text_at("星门需求 %d 星砂 / %d 星核" % [gate_cost(),gates+1] if gates<3 else "全部星门已点亮",Vector2(1008,601),16,GOLD)
		button(Rect2(1000,611,250,44),"G  修复星门" if gates<3 else "星路重连 · 已完成",false)
		button(Rect2(1000,669,250,46),"E  开始远航",true)
	else:
		text_at("能源  %d / %d" % [ceili(energy),int(max_energy())],Vector2(1008,326),19)
		meter(Vector2(1008,340),232,energy/max_energy(),CYAN if energy>25 else Color("ff748c"))
		text_at("船体  %s" % "◆ ".repeat(maxi(0,hull)),Vector2(1008,382),19,Color("ff9fac"))
		text_at("星砂  %d · 无上限" % cargo,Vector2(1008,430),19,GOLD)
		meter(Vector2(1008,444),232,float(combat.xp)/combat.xp_goal,CYAN)
		text_at("星核  %d · 无上限" % cargo_cores,Vector2(1008,482),19,CYAN)
		text_at("伤害 ×%.1f  射速 ×%.1f" % [1+combat.stacks("power")*.2,1+combat.stacks("rapid")*.15],Vector2(1008,509),15,MUTED)
		text_at("空格 冲刺  %s" % ("就绪" if dash_cd<=0 else "%.1fs" % dash_cd),Vector2(1008,556),18)
		text_at("Q 清弹     %s" % ("%d 次" % combat.pulses if combat_enabled else "扫描"),Vector2(1008,589),18)
		text_at("失事：星核丢失，星砂保留一半",Vector2(1008,635),14,Color("ff9fac"))
		button(Rect2(1000,669,250,46),"E  返回空间站卸货",player.distance_to(HOME)<72)
	text_at("方向键 移动   自动射击   空格 冲刺   Q 清弹   1–3 选择武器   ESC 菜单",Vector2(32,768),17,MUTED)
	text_at("%d FPS · 弹幕 %d" % [Engine.get_frames_per_second(),combat.bullets.size()],Vector2(1000,768),15,CYAN)

func button(rect: Rect2, label: String, active: bool) -> void:
	panel(rect,Color("1b4a50") if active else Color("192a3e"),CYAN if active else Color("37516b"))
	text_at(label,rect.position+Vector2(13,29),18,CYAN if active else WHITE)
