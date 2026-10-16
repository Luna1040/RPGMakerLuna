extends RefCounted
const ROOT_NAMES=["下品灵根","中品灵根","上品灵根","极品灵根","天灵根","道品灵根"]
const COLORS=["eeeeee","67ce72","57a8ff","ba7bff","ff9f40","c39a39"]
const WEIGHTS=[50.0,27.0,14.0,6.0,2.5,0.5]
const NAMES=["沈清尘","顾长风","苏晚晴","陆云舟","林照月","叶听雨","温玄","楚星河","白若兰","宁无涯","秦疏影","柳灵溪"]
static func normalize(c: Dictionary) -> void:
	if not c.has("retainers"): c.retainers={"following":[],"reserve":[],"offers":[],"refresh_at":0,"serial":0,"introduced":false}
	var state: Dictionary=c.retainers
	for key in ["following","reserve","offers"]:
		if not state.has(key): state[key]=[]
	for key in ["refresh_at","serial"]: state[key]=int(state.get(key,0))
	if not state.has("introduced"): state.introduced=false
	for group in [state.following,state.reserve,state.offers]:
		for unit in group:
			if unit.is_empty(): continue
			for key in ["level","xp","root","portrait"]: unit[key]=int(unit.get(key,0))
	if state.offers.is_empty():
		for i in range(12): state.offers.append({})
	if not state.get("initialized",false) and int(c.get("level",1))>=10:
		refresh(c,int(Time.get_unix_time_from_system()),true)
		state.initialized=true
static func follow_limit(c: Dictionary) -> int:
	var realm:=str(c.get("realm","凡人"))
	if "元婴" in realm or "化神" in realm or "合体" in realm or "大乘" in realm or "渡劫" in realm or "炼虚" in realm or "出窍" in realm or "分神" in realm or "洞虚" in realm or "仙人" in realm or "真仙" in realm or "金仙" in realm: return 4
	if "金丹" in realm: return 3
	if "筑基" in realm: return 2
	return 1 if "练气" in realm or "炼气" in realm else 0
static func reserve_limit(c: Dictionary) -> int: return mini(8,int(c.get("level",1))/10*2)
static func pick_root(roll: float) -> int:
	var sum:=0.0
	for i in range(6):
		sum+=WEIGHTS[i]
		if roll<sum: return i
	return 5
static func refresh(c: Dictionary, now: int, initial: bool=false) -> bool:
	if int(c.level)<10 or (not initial and now<int(c.retainers.refresh_at)): return false
	var rng:=RandomNumberGenerator.new()
	if c.retainers.has("rng_state"): rng.state=int(str(c.retainers.rng_state))
	else: rng.randomize()
	c.retainers.offers=[]
	var names: Array=NAMES.duplicate()
	for i in range(12):
		c.retainers.serial+=1
		c.retainers.offers.append({"uid":"retainer_%d" % c.retainers.serial,"name":names.pop_at(rng.randi_range(0,names.size()-1)),"root":pick_root(rng.randf()*100.0),"level":1,"xp":0,"portrait":[0,2,4,5,6][rng.randi_range(0,4)]})
	c.retainers.rng_state=str(rng.state)
	c.retainers.refresh_at=now+60
	return true
static func recruit(c: Dictionary, index: int) -> bool:
	if int(c.level)<10 or index<0 or index>=12 or c.retainers.offers[index].is_empty() or c.retainers.reserve.size()>=reserve_limit(c): return false
	c.retainers.reserve.append(c.retainers.offers[index]); c.retainers.offers[index]={}; return true
static func deploy(c: Dictionary, index: int) -> bool:
	if index<0 or index>=c.retainers.reserve.size() or c.retainers.following.size()>=follow_limit(c): return false
	c.retainers.following.append(c.retainers.reserve.pop_at(index)); return true
static func withdraw(c: Dictionary, index: int) -> bool:
	if index<0 or index>=c.retainers.following.size() or c.retainers.reserve.size()>=reserve_limit(c): return false
	c.retainers.reserve.append(c.retainers.following.pop_at(index)); return true
static func dismiss(c: Dictionary, index: int) -> bool:
	if index<0 or index>=c.retainers.reserve.size(): return false
	c.retainers.reserve.remove_at(index); return true
static func stats(unit: Dictionary) -> Dictionary:
	var growth:=int(unit.root)+1
	return {"attack":8+int(unit.level)*growth*2,"defense":2+int(unit.level)*growth,"hp":50+int(unit.level)*growth*12}
static func award_battle(c: Dictionary, protagonist_xp: int) -> void:
	for unit in c.retainers.following:
		unit.xp=int(unit.xp)+maxi(0,protagonist_xp)*2
		while int(unit.xp)>=100: unit.xp-=100; unit.level+=1
static func describe(unit: Dictionary) -> String:
	var attributes:=stats(unit)
	return "%s · %s\n等级%d · 经验%d/100\n气血%d 攻击%d 防御%d\n每级成长：气血+%d 攻击+%d 防御+%d" % [unit.name,ROOT_NAMES[int(unit.root)],unit.level,unit.xp,attributes.hp,attributes.attack,attributes.defense,(int(unit.root)+1)*12,(int(unit.root)+1)*2,int(unit.root)+1]

static func refresh_paid(c: Dictionary, now: int) -> bool:
	if int(c.level)<10 or int(c.get("stones",0))<12: return false
	var deadline:=int(c.retainers.refresh_at)
	if not refresh(c,now,true): return false
	c.retainers.refresh_at=deadline
	c.stones=int(c.stones)-12
	return true
