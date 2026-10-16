extends RefCounted
static func normalize(c: Dictionary, now: int) -> void:
	if not c.has("monster_respawns"):
		c.monster_respawns={}
		for group in c.get("cleared",[]): c.monster_respawns[str(int(group))]=now+30
	for key in c.monster_respawns: c.monster_respawns[key]=int(c.monster_respawns[key])
static func dead(c: Dictionary, group: int, now: int) -> bool:
	return now<int(c.get("monster_respawns",{}).get(str(group),0))
static func killed(c: Dictionary, group: int, now: int) -> void:
	c.monster_respawns[str(group)]=now+30
static func expire(c: Dictionary, now: int) -> bool:
	var changed:=false
	for key in c.monster_respawns.keys():
		if now>=int(c.monster_respawns[key]): c.monster_respawns.erase(key); changed=true
	return changed
