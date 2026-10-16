extends RefCounted
static func foundation(c: Dictionary) -> bool:
	return str(c.get("realm",""))=="筑基期" or bool(c.get("foundation_established",false))
static func normalize(c: Dictionary) -> bool:
	if int(c.get("balance_version",0))>=11: return false
	if int(c.get("level",1))>10 and not foundation(c):
		c.pre_v11_progress={"level":int(c.level),"xp":int(c.get("xp",0))}
		var earned:=int(c.get("dungeon",{}).get("wins",0))*200
		var run: Dictionary=c.get("dungeon",{}).get("run",{})
		if not run.is_empty() and not bool(run.get("completed",false)):
			for floor in range(1,int(run.floor)): earned+=40+boss_xp(floor)
			for pack in run.cleared: earned+=boss_xp(int(run.floor)) if int(pack)==4 else 10
		c.level=mini(20,10+earned/100)
		c.xp=earned%100 if int(c.level)<20 else 0
	c.balance_version=11
	return true
static func boss_xp(floor: int) -> int: return [20,25,35][clampi(floor-1,0,2)]
static func dungeon_xp(floor: int, boss: bool) -> int: return boss_xp(floor) if boss else 10
static func add(c: Dictionary, amount: int) -> bool:
	var old_level:=int(c.level)
	if not foundation(c) and old_level>=20: c.xp=0; return false
	c.xp=int(c.get("xp",0))+maxi(0,amount)
	while int(c.xp)>=100:
		c.xp-=100; c.level=int(c.level)+1
		if not foundation(c) and int(c.level)>=20: c.level=20; c.xp=0; break
	return int(c.level)>old_level
static func realm_stats(c: Dictionary) -> Dictionary:
	return {"attack":25,"defense":15,"hp":150} if foundation(c) else {"attack":0,"defense":0,"hp":0}
