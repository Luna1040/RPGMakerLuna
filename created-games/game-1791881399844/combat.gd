extends RefCounted
# Combat simulation owns projectiles and rewards; generated art never decides hits.
var game
var enemies: Array[Dictionary]=[]
var bullets: Array[Dictionary]=[]
var shots: Array[Dictionary]=[]
var effects: Array[Dictionary]=[]
var elapsed:=0.0
var spawn_cd:=1.0
var fire_cd:=0.0
var kills:=0
var weapon:=0
var rank:=1
var pulses:=3
var pulse_cd:=0.0
var choice:=false
var choices_taken:=0
var boss_spawned:=false
var won:=false
var return_left:=5.0
var next_id:=0
var entry_edges: Array=[]
var textures: Dictionary={}
var sounds: Dictionary={}
var muted:=false
var xp:=0
var xp_goal:=6
var run_level:=1
var passive_choice:=false
var offers: Array=[]
var perks: Dictionary={}
var max_hull:=3
const PERKS:=[
	{"id":"rapid","name":"过载扳机","desc":"射速 +15% · 可叠 3 层"},
	{"id":"power","name":"高能弹芯","desc":"所有武器伤害 +20%"},
	{"id":"critical","name":"精准棱镜","desc":"暴击率 +15% · 暴击双倍"},
	{"id":"magnet","name":"引力井","desc":"采集半径 +22 · 自动牵引"},
	{"id":"armor","name":"复合装甲","desc":"船体上限 +1 · 修复 1 点"},
	{"id":"pulse","name":"脉冲电容","desc":"补满清弹 · 脉冲伤害 +40%"},
	{"id":"salvage","name":"星砂回收器","desc":"敌机星砂掉落 +2"},
	{"id":"dash","name":"相位引擎","desc":"冲刺冷却缩短 15%"},
	{"id":"multishot","name":"分裂弹仓","desc":"每轮额外 +2 发子弹"},
	{"id":"colossal","name":"巨型弹头","desc":"弹体宽度 +35% · 伤害 +10%"},
	{"id":"frost","name":"极寒弹芯","desc":"命中减速 · 冰蓝弹体"},
	{"id":"chain","name":"连锁电弧","desc":"命中向附近敌人传导电击"}
]
func stacks(id: String) -> int: return int(perks.get(id,0))
func roll_perks() -> void:
	offers.clear()
	var pool: Array=[]
	for entry in PERKS:
		if stacks(entry.id)<3: pool.append(entry)
	while offers.size()<3 and not pool.is_empty():
		var index: int=game.rng.randi_range(0,pool.size()-1)
		offers.append(pool.pop_at(index))
	for reward in [{"id":"supply_repair","name":"维修无人机","desc":"修复 1 点船体"},{"id":"supply_energy","name":"能源补给","desc":"恢复 30 能源 · 补充清弹"},{"id":"supply_core","name":"星核储备","desc":"立即获得 2 枚星核"}]:
		if offers.size()<3: offers.append(reward)
	passive_choice=true; choice=true; bullets.clear()
	game.message="升级！选择随机舰装，叠加构筑本航次打法。"
func choose_perk(index: int) -> void:
	if index<0 or index>=offers.size(): return
	var entry: Dictionary=offers[index]
	if not str(entry.id).begins_with("supply_"): perks[entry.id]=stacks(entry.id)+1
	if entry.id=="supply_repair": game.hull=mini(max_hull,game.hull+1)
	if entry.id=="supply_energy": game.energy=minf(game.max_energy(),game.energy+30); pulses=mini(3,pulses+1)
	if entry.id=="supply_core": game.cargo_cores+=2
	if entry.id=="armor": max_hull+=1; game.hull=mini(max_hull,game.hull+1)
	if entry.id=="pulse": pulses=3
	passive_choice=false; choice=false; run_level+=1; sound("upgrade")
	game.message="获得 %s ×%d · 本航次 Lv.%d" % [entry.name,stacks(entry.id),run_level]

const NAMES:=["星芒散射","贯穿光矛","追踪僚机"]
const COLORS:=[Color("72f9ed"),Color("ffe3a1"),Color("cbabff")]
func _init(owner) -> void:
	game=owner
	for name in ["scout","gunship","spinner","boss"]:
		var path: String="res://assets/shooter-v1/"+name+".png"
		if ResourceLoader.exists(path): textures[name]=load(path)
func sound(name: String) -> void:
	if muted: return
	if not sounds.has(name):
		var path:="res://assets/shooter-v1/audio/"+name+".wav"
		if not ResourceLoader.exists(path): return
		var player:=AudioStreamPlayer.new()
		player.stream=load(path); player.volume_db=-12 if name=="shot" else -5
		game.add_child(player); sounds[name]=player
	sounds[name].play()
func reset() -> void:
	enemies.clear(); bullets.clear(); shots.clear(); effects.clear()
	entry_edges.clear()
	xp=0; xp_goal=6; run_level=1; passive_choice=false; offers.clear(); perks.clear(); max_hull=3
	elapsed=0; spawn_cd=1; fire_cd=0; kills=0; weapon=0; rank=1; pulses=3; pulse_cd=0
	choice=false; choices_taken=0; boss_spawned=false; won=false; return_left=5
func choose(index: int) -> void:
	if not choice or index<0 or index>2: return
	if passive_choice:
		choose_perk(index)
		return
	weapon=index; rank=mini(4,rank+1); choice=false; choices_taken+=1
	sound("upgrade")
	game.message="装备 %s Lv.%d · 自动射击，Q 清除弹幕" % [NAMES[weapon],rank]
func entry_position() -> Vector2:
	if entry_edges.is_empty():
		entry_edges=[0,1,2,3]
		for i in range(3,0,-1):
			var j: int=game.rng.randi_range(0,i)
			var value=entry_edges[i]; entry_edges[i]=entry_edges[j]; entry_edges[j]=value
	var edge: int=entry_edges.pop_back()
	var bounds: Rect2=game.FIELD.grow(-40)
	var best:=bounds.position
	var best_distance:=-1.0
	for attempt in 24:
		var pos:=Vector2(game.rng.randf_range(bounds.position.x,bounds.end.x),game.rng.randf_range(bounds.position.y,bounds.end.y))
		match edge:
			0: pos.x=bounds.position.x
			1: pos.x=bounds.end.x
			2: pos.y=bounds.position.y
			3: pos.y=bounds.end.y
		var distance: float=pos.distance_to(game.player)
		if distance>best_distance: best_distance=distance; best=pos
		if distance>=220 and not enemies.any(func(e):return Vector2(e.p).distance_to(pos)<75): return pos
	# Corners guarantee a safe option even if the player hugs the chosen edge.
	var corners: Array=[bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]
	for pos in corners:
		var on_edge: bool=(pos.x==bounds.position.x if edge==0 else pos.x==bounds.end.x if edge==1 else pos.y==bounds.position.y if edge==2 else pos.y==bounds.end.y)
		if on_edge and pos.distance_to(game.player)>best_distance: best=pos; best_distance=pos.distance_to(game.player)
	return best
func spawn(kind: int, pos: Vector2) -> Dictionary:
	next_id+=1
	var hp: float=[18.0,58.0,44.0,5500.0][kind]*(1+game.sector*.2)
	var enemy: Dictionary={"id":next_id,"kind":kind,"p":pos,"hp":hp,"max":hp,"age":0.0,"fire":1.6,"flash":0.0,"slow":0.0,"radius":[22.0,32.0,28.0,75.0][kind],"origin":pos.y,"angle":(game.player-pos).angle()+PI,"anchor":game.FIELD.get_center()+(pos-game.FIELD.get_center()).normalized()*160}
	enemies.append(enemy)
	return enemy
func damage_player() -> void:
	if game.hit_cd>0 or game.dash_left>0 or won: return
	game.hull-=1; game.hit_cd=1.6
	sound("hit")
	game.burst(game.player,Color("ff748c"))
func pulse() -> void:
	if game.mode!="flight" or choice or won or pulses<=0 or pulse_cd>0: return
	pulses-=1; pulse_cd=.7
	sound("pulse")
	game.hit_cd=maxf(game.hit_cd,.8)
	bullets.clear()
	effects.append({"p":game.player,"age":0.0,"radius":320.0,"pulse":true})
	for e in enemies:
		if game.player.distance_to(e.p)<320: e.hp-=85*(1+stacks("pulse")*.4)
	game.message="脉冲爆发：弹幕已清除 · 剩余 %d 次" % pulses
func shot(pos: Vector2, velocity: Vector2, kind: int) -> void:
	if shots.size()>=200: return
	var multiplier:=1+stacks("power")*.2+stacks("colossal")*.1
	if game.rng.randf()<stacks("critical")*.15: multiplier*=2
	shots.append({"p":pos,"v":velocity,"life":2.2,"kind":kind,"size":minf(3.2,1+(run_level-1)*.07+(rank-1)*.12+stacks("colossal")*.35),"hit":[],"damage":((12.0+rank*4) if kind!=1 else (18.0+rank*5))*multiplier})
func fire() -> void:
	sound("shot")
	var aim:=Vector2.RIGHT
	var nearest:=INF
	for e in enemies:
		var distance: float=game.player.distance_squared_to(e.p)
		if distance<nearest:
			nearest=distance; aim=(e.p-game.player).normalized()
	game.heading=aim
	var muzzle: Vector2=game.player+aim*25
	match weapon:
		0:
			for i in range(-rank,rank+1): shot(muzzle,aim.rotated(i*.11)*650,0)
		1: shot(muzzle,aim*900,1)
		2:
			shot(muzzle,aim*600,0)
			for side in [-1,1]: shot(game.player+Vector2(-15,side*30),aim.rotated(side*.2)*420,2)
	for i in stacks("multishot"):
		for side in [-1,1]: shot(muzzle,aim.rotated(side*(.22+i*.12))*650,weapon)
func enemy_fire(e: Dictionary) -> void:
	var aim: Vector2=(game.player-e.p).normalized()
	var kind: int=e.kind
	var speed: float=125.0+game.sector*12+minf(40,elapsed*.18)
	if kind==0:
		add_bullet(e.p,aim*speed,0)
	elif kind==1:
		for i in range(-2,3): add_bullet(e.p,aim.rotated(i*.20)*speed,1)
	else:
		var count:=10 if kind==2 else 16
		var rotation: float=e.age*.65
		for i in count:
			add_bullet(e.p,Vector2.from_angle(rotation+i*TAU/count)*speed,2)
		if kind==3 and e.hp<e.max*.5:
			for i in range(-2,3): add_bullet(e.p,aim.rotated(i*.12)*(speed+35),1)
func add_bullet(pos: Vector2, velocity: Vector2, kind: int) -> void:
	if bullets.size()<160: bullets.append({"p":pos,"v":velocity,"kind":kind,"life":9.0})
func defeat(e: Dictionary) -> void:
	kills+=1
	xp+=[1,3,5,15][e.kind]
	sound("explode")
	effects.append({"p":e.p,"age":0.0,"radius":100.0 if e.kind==3 else 40.0,"pulse":false})
	game.burst(e.p,Color("ffb87a"))
	game.stars.append({"p":e.p,"core":e.kind>=2,"value":3+game.sector+stacks("salvage")*2,"phase":0.0})
	game.energy=minf(game.max_energy(),game.energy+2)
	if e.kind==2:
		game.hull=mini(max_hull,game.hull+1)
		pulses=mini(3,pulses+1)
	if e.kind==3:
		won=true; bullets.clear(); shots.clear()
		sound("victory")
		# Victory recovers all rewards, ignoring cargo capacity; settlement remains once-only.
		for drop in game.stars:
			if drop.core: game.cargo_cores+=1
			else: game.cargo+=int(drop.value)
		game.stars.clear(); game.cargo+=40; game.cargo_cores+=3
		game.message="星湾守卫已击破！回收全部战利品，5 秒后自动返航。"
func step(dt: float) -> void:
	if choice or game.mode!="flight": return
	for i in range(effects.size()-1,-1,-1):
		effects[i].age+=dt
		if effects[i].age>(.65 if effects[i].pulse else 2.0): effects.remove_at(i)
	if won:
		return_left-=dt
		if return_left<=0:
			game.bank_cargo(); game.result="星湾战役胜利 · 全部战利品已入库"
		return
	if not boss_spawned and elapsed>1 and enemies.is_empty(): spawn_cd=minf(spawn_cd,.6)
	elapsed+=dt; pulse_cd=maxf(0,pulse_cd-dt); fire_cd-=dt; spawn_cd-=dt
	if not boss_spawned and elapsed>=150:
		boss_spawned=true; enemies.clear(); bullets.clear()
		spawn(3,entry_position()); game.message="警报：星蚀方舟接近！Q 脉冲清弹，空格穿越火网。"
	if spawn_cd<=0 and not boss_spawned and enemies.size()<28:
		spawn_cd=maxf(1.1,2.2-elapsed*.01)
		var kind:=mini(2,int(elapsed/18)%3)
		for i in mini(28-enemies.size(),mini(10,6+int(elapsed/30))): spawn(kind,entry_position())
	if fire_cd<=0:
		fire_cd=(.26 if weapon!=1 else .38)/(1+stacks("rapid")*.15)
		fire()
	for e in enemies:
		e.age+=dt; e.flash=maxf(0,e.flash-dt); e.slow=maxf(0,e.slow-dt)
		var towards: Vector2=game.player-e.p
		e.angle=lerp_angle(e.angle,towards.angle()+PI,minf(1,dt*4))
		if e.kind==3:
			var target: Vector2=e.anchor+Vector2(sin(e.age*.5)*28,sin(e.age*.7)*75)
			e.p=Vector2(e.p).move_toward(target,dt*85)
		else:
			var direction:=towards.normalized()
			var spacing: float=(95.0 if e.kind==0 else 220.0)+int(e.id)%4*18
			var radial:=clampf((towards.length()-spacing)/100.0,-.65,1.0)
			var orbit:=direction.orthogonal()*(.4 if int(e.id)%2==0 else -.4)
			var velocity: Vector2=(direction*radial+orbit)*(85 if e.kind==0 else 60)*(.5 if e.slow>0 else 1.0)
			e.p=(Vector2(e.p)+velocity*dt).clamp(game.FIELD.position+Vector2(35,35),game.FIELD.end-Vector2(35,35))
		e.fire-=dt
		if e.fire<=0:
			enemy_fire(e); e.fire=2.1 if e.kind!=3 else (1.1 if e.hp<e.max*.5 else 1.6)
		if game.player.distance_to(e.p)<e.radius+5: damage_player()
	for i in range(shots.size()-1,-1,-1):
		var s: Dictionary=shots[i]
		if s.kind==2 and not enemies.is_empty():
			var target: Vector2=enemies[0].p
			var best:=INF
			for e in enemies:
				var distance: float=s.p.distance_squared_to(e.p)
				if distance<best: best=distance; target=e.p
			s.v=Vector2(s.v).lerp((target-s.p).normalized()*480,minf(1,dt*5))
		var old: Vector2=s.p
		s.p+=s.v*dt; s.life-=dt
		for e in enemies:
			if e.id in s.hit: continue
			var closest:=Geometry2D.get_closest_point_to_segment(e.p,old,s.p)
			if closest.distance_to(e.p)<e.radius+4*float(s.get("size",1)):
				e.hp-=s.damage; e.flash=.09; s.hit.append(e.id)
				if stacks("frost")>0: e.slow=1.0+stacks("frost")*.5
				if stacks("chain")>0:
					for other in enemies:
						if other.id!=e.id and other.p.distance_squared_to(e.p)<32400:
							other.hp-=s.damage*.3*stacks("chain"); other.flash=.12
							effects.append({"p":e.p,"to":other.p,"age":0.0,"radius":0.0,"pulse":true})
							break
				if s.kind!=1: s.life=0; break
		if s.life<=0 or not game.FIELD.grow(40).has_point(s.p): shots.remove_at(i)
	for i in range(bullets.size()-1,-1,-1):
		var b: Dictionary=bullets[i]
		var old: Vector2=b.p
		b.p+=b.v*dt; b.life-=dt
		if Geometry2D.get_closest_point_to_segment(game.player,old,b.p).distance_to(game.player)<10:
			damage_player(); b.life=0
		if b.life<=0 or not game.FIELD.grow(10).has_point(b.p): bullets.remove_at(i)
	for i in range(enemies.size()-1,-1,-1):
		if enemies[i].hp<=0:
			defeat(enemies[i]); enemies.remove_at(i)
	if won: enemies.clear()
	elif xp>=xp_goal:
		xp-=xp_goal; xp_goal+=4; roll_perks()
	elif choices_taken<3 and elapsed>=30+choices_taken*45:
		choice=true; bullets.clear(); game.message="获得武器补给：按 1 / 2 / 3 选择，战斗暂停。"
func render() -> void:
	if game.mode!="flight": return
	for e in enemies:
		var name: String=["scout","gunship","spinner","boss"][e.kind]
		var size: float=[72,100,88,240][e.kind]
		if e.kind==3 and game.animation_art.has("boss"):
			game.art_sprite("boss",e.p,size,e.angle)
		elif textures.has(name):
			game.draw_set_transform(e.p,e.angle if e.kind!=2 else e.age*.3)
			game.draw_texture_rect(textures[name],Rect2(-Vector2.ONE*size/2,Vector2.ONE*size),false,Color(2,2,2) if e.flash>0 else (Color(.4,.85,1) if e.slow>0 else Color.WHITE))
			game.draw_set_transform(Vector2.ZERO)
		if e.fire<.35: game.draw_arc(e.p,e.radius+7,0,TAU,32,Color(1,.35,.35,.8),2,true)
		if e.kind==3:
			game.panel(Rect2(320,158,480,46),Color(.05,.02,.09,.85))
			game.text_at("星蚀方舟  /  "+("暴走阶段" if e.hp<e.max*.5 else "环状弹幕"),Vector2(335,179),16,Color("ffa5c9"))
			game.meter(Vector2(335,190),450,e.hp/e.max,Color("ef6fa2"))
		else: game.meter(e.p+Vector2(-24,-size*.4),48,e.hp/e.max,Color("ed879e"))
	for fx in effects:
		var ratio: float=fx.age/.65
		if ratio>=1: continue
		if fx.has("to"):
			game.draw_line(fx.p,fx.to,Color(.5,.8,1,1-ratio),3,true)
			continue
		game.draw_arc(fx.p,fx.radius*ratio,0,TAU,64,Color(.5,1,1,1-ratio) if fx.pulse else Color(1,.6,.25,1-ratio),4,true)
	game.draw_circle(game.player,5,Color(.02,.05,.1))
	game.draw_circle(game.player,3,Color.WHITE)
	if weapon==2:
		for side in [-1,1]: game.art_sprite("ship",game.player+Vector2(-20,side*32),30,game.heading.angle())
	game.text_at("%02d:%02d · 击破 %d · %s %d级 · 舰装 Lv.%d  XP %d/%d" % [int(elapsed)/60,int(elapsed)%60,kills,NAMES[weapon],rank,run_level,xp,xp_goal],Vector2(48,714),16,game.CYAN)
	if won: game.text_at("战役胜利 · %.0f 秒后返航" % ceil(return_left),Vector2(330,370),30,game.GOLD)
	if choice:
		game.draw_rect(game.FIELD,Color(.015,.025,.06,.9))
		game.text_at("随机舰装 / 组合本航次构筑" if passive_choice else "战地补给 / 选择本航次武器",Vector2(230,315),30,game.GOLD)
		game.text_at("舰装仅本航次生效 · 同类最多叠 3 层" if passive_choice else "时间暂停 · 切换武器保留等级 · 返航后重置",Vector2(230,352),17,game.MUTED)
		for i in (offers.size() if passive_choice else 3):
			var rect:=Rect2(110+i*278,390,260,145)
			game.panel(rect,Color("152b40"),COLORS[i])
			game.text_at("[%d] %s" % [i+1,offers[i].name if passive_choice else NAMES[i]],rect.position+Vector2(14,40),23,COLORS[i])
			game.text_at(offers[i].desc if passive_choice else ["扇形齐射 · 清理编队","穿透敌群 · 高额单发","双僚机 · 转向追踪"][i],rect.position+Vector2(14,82),17)
			game.text_at(("立即领取" if str(offers[i].id).begins_with("supply_") else "叠加至 %d 层" % (stacks(offers[i].id)+1)) if passive_choice else "升级至 Lv.%d" % mini(4,rank+1),rect.position+Vector2(14,116),16,game.GOLD)
