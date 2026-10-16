extends RefCounted
const E=preload("res://estate_system.gd")
const P=preload("res://progression_system.gd")
const R=preload("res://retainer_system.gd")
const G=preload("res://equipment_system.gd")
static func day(now: int) -> String: return Time.get_datetime_string_from_unix_time(now+8*3600).left(10)
static func normalize(c: Dictionary, now: int) -> void:
	if not c.has("dungeon"): c.dungeon={"day":day(now),"used":0,"run":{},"wins":0}
	var d: Dictionary=c.dungeon
	if str(d.day)!=day(now): d.day=day(now); d.used=0; d.bought=0
	d.bought=int(d.get("bought",0))
	d.used=int(d.used); d.wins=int(d.get("wins",0))
	if not d.run.is_empty():
		d.run.floor=int(d.run.floor)
		for i in range(d.run.cleared.size()): d.run.cleared[i]=int(d.run.cleared[i])
static func enter(c: Dictionary, now: int) -> bool:
	normalize(c,now)
	if int(c.level)<10: return false
	if not c.dungeon.run.is_empty() and bool(c.dungeon.run.get("active",false)): return true
	if remaining(c)<=0: return false
	c.dungeon.used+=1
	c.dungeon.run={"active":true,"floor":1,"cleared":[],"completed":false}
	return true
static func ready(c: Dictionary, index: int) -> bool:
	var run: Dictionary=c.dungeon.run
	return not run.is_empty() and bool(run.active) and index>=0 and index<5 and not index in run.cleared and (index<4 or run.cleared.size()>=4)
static func win(c: Dictionary, index: int) -> bool:
	if not ready(c,index): return false
	c.dungeon.run.cleared.append(index)
	if int(c.dungeon.run.floor)==3 and c.dungeon.run.cleared.size()==5:
		c.dungeon.run.completed=true; c.dungeon.wins+=1
	return true
static func next_floor(c: Dictionary) -> bool:
	if c.dungeon.run.is_empty() or c.dungeon.run.cleared.size()!=5 or int(c.dungeon.run.floor)>=3: return false
	c.dungeon.run.floor+=1; c.dungeon.run.cleared=[]; return true
static func drop_category(boss: bool, roll: float) -> String:
	if roll<(0.2 if boss else 0.1): return "scatter"
	if boss or roll<0.3: return "xiaoyao"
	return "none"
static func loot(c: Dictionary, boss: bool, count: int, level: int) -> Array:
	var rng:=RandomNumberGenerator.new(); rng.seed=int(c.loot_seed)
	if c.has("loot_rng_state"): rng.state=int(str(c.loot_rng_state))
	var result: Array=[]
	for i in range(count):
		var category:=drop_category(boss,rng.randf())
		if category=="none": continue
		c.gear_serial=int(c.gear_serial)+1
		var slots: Array=[1,3,4,5]
		var item:=G.make_item(slots[rng.randi_range(0,3)] if category=="xiaoyao" else rng.randi_range(0,7),3 if category=="xiaoyao" else rng.randi_range(2,3),10 if category=="xiaoyao" else level,"xiaoyao" if category=="xiaoyao" else "","cave_%d_%d" % [int(c.loot_seed),int(c.gear_serial)])
		G.receive(c,item); result.append(item)
	c.loot_rng_state=str(rng.state)
	return result

static func remaining(c: Dictionary) -> int: return maxi(0,5+int(c.dungeon.get("bought",0))-int(c.dungeon.used))
static func purchase(c: Dictionary, now: int) -> bool:
	normalize(c,now)
	if int(c.get("level",1))<10 or int(c.get("stones",0))<3000: return false
	c.stones=int(c.stones)-3000
	c.dungeon.bought+=1
	return true
static func sweep(c: Dictionary, now: int) -> Dictionary:
	normalize(c,now)
	if int(c.get("level",1))<10 or int(c.dungeon.wins)<1: return {"error":"需先亲自完整通关万妖窟"}
	if not c.dungeon.run.is_empty() and bool(c.dungeon.run.get("active",false)) and not bool(c.dungeon.run.get("completed",false)): return {"error":"请先完成当前未结束的挑战"}
	if remaining(c)<=0: return {"error":"今日挑战次数不足，可购买额外次数"}
	if int(c.get("stones",0))<1000: return {"error":"灵石不足1000"}
	c.stones=int(c.stones)-1000
	c.dungeon.used+=1
	var result: Dictionary={"xp":0,"stones":0,"loot":[],"fee":1000}
	for floor in range(1,4):
		for index in range(5):
			var boss:=index==4
			var level: int=12+floor*2 if boss else 9+floor*2
			var count:=1 if boss else 3
			var experience:=P.dungeon_xp(floor,boss)
			P.add(c,experience); R.award_battle(c,experience)
			result.xp+=experience
			result.stones+=level*2*count*5
			result.loot.append_array(loot(c,boss,count,level))
			if boss:
				var seed:=E.seed_item(["jade","violet","sun"][floor-1],1)
				if not E.put(c.inventory,seed): c.pending_loot.append(seed)
				result.loot.append(seed)
	c.stones=int(c.stones)+int(result.stones)
	c.victories=int(c.get("victories",0))+15
	c.dungeon.wins+=1
	c.dungeon.run={"active":false,"floor":3,"cleared":[0,1,2,3,4],"completed":true}
	return result
