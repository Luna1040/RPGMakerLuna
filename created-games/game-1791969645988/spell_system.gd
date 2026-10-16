extends RefCounted
const E=preload("res://estate_system.gd")
const P=preload("res://progression_system.gd")
const CLASSES=["剑仙","阴阳","魅影","天师"]
const ROLES=["sword","yinyang","shadow","celestial"]
const DATA={
"sword_q1":{"name":"青莲剑诀","class":"剑仙","realm":0,"damage":[12,4],"heal":[0,0],"guard":[0,0]},
"sword_q2":{"name":"御剑护体","class":"剑仙","realm":0,"damage":[4,2],"heal":[0,0],"guard":[7,2]},
"sword_f1":{"name":"天罡剑阵","class":"剑仙","realm":1,"damage":[28,7],"heal":[0,0],"guard":[3,1]},
"sword_f2":{"name":"万剑归宗","class":"剑仙","realm":1,"damage":[42,9],"heal":[0,0],"guard":[0,0]},
"yinyang_q1":{"name":"阴阳灵咒","class":"阴阳","realm":0,"damage":[10,4],"heal":[4,2],"guard":[0,0]},
"yinyang_q2":{"name":"两仪灵盾","class":"阴阳","realm":0,"damage":[3,1],"heal":[0,0],"guard":[9,3]},
"yinyang_f1":{"name":"阴阳逆转","class":"阴阳","realm":1,"damage":[24,6],"heal":[12,3],"guard":[0,0]},
"yinyang_f2":{"name":"太极归元","class":"阴阳","realm":1,"damage":[10,3],"heal":[14,3],"guard":[12,4]},
"shadow_q1":{"name":"影袭","class":"魅影","realm":0,"damage":[16,5],"heal":[0,0],"guard":[0,0]},
"shadow_q2":{"name":"隐遁","class":"魅影","realm":0,"damage":[5,2],"heal":[0,0],"guard":[8,3]},
"shadow_f1":{"name":"幽冥连刃","class":"魅影","realm":1,"damage":[34,8],"heal":[0,0],"guard":[0,0]},
"shadow_f2":{"name":"鬼影夺魂","class":"魅影","realm":1,"damage":[26,6],"heal":[10,3],"guard":[0,0]},
"celestial_q1":{"name":"雷符","class":"天师","realm":0,"damage":[14,4],"heal":[0,0],"guard":[0,0]},
"celestial_q2":{"name":"甘霖咒","class":"天师","realm":0,"damage":[2,1],"heal":[14,4],"guard":[2,1]},
"celestial_f1":{"name":"九霄雷法","class":"天师","realm":1,"damage":[38,9],"heal":[0,0],"guard":[0,0]},
"celestial_f2":{"name":"金光护身","class":"天师","realm":1,"damage":[8,3],"heal":[10,2],"guard":[16,5]}}
static func normalize(c: Dictionary) -> void:
	if not c.get("spells") is Dictionary: c.spells={}
	for id in c.spells.keys():
		if not DATA.has(id): c.spells.erase(id)
		else: c.spells[id]=clampi(int(c.spells[id]),0,10)
	if not c.has("foundation_quest"): c.foundation_quest=0
	c.foundation_quest=int(c.foundation_quest)
static func ids(c: Dictionary) -> Array:
	var result: Array=[]
	for id in DATA:
		if DATA[id]["class"]==c.profession: result.append(id)
	return result
static func permitted(c: Dictionary, id: String) -> bool:
	return DATA.has(id) and DATA[id]["class"]==c.profession and ((int(DATA[id].realm)==0 and (str(c.get("realm",""))=="练气期" or P.foundation(c))) or (int(DATA[id].realm)==1 and P.foundation(c)))
static func cost(c: Dictionary, id: String) -> int: return int(c.spells.get(id,0))+1
static func learn(c: Dictionary, id: String) -> bool:
	if not permitted(c,id) or int(c.spells.get(id,0))>=10: return false
	if not E.consume(c.inventory,"spell_manual",id,cost(c,id)): return false
	c.spells[id]=int(c.spells.get(id,0))+1
	return true
static func manual(id: String, count: int=1) -> Dictionary:
	return E.stack("spell_manual",id,str(DATA[id].name)+"玉简",count,3 if int(DATA[id].realm)==1 else 2)
static func drop_wild(c: Dictionary, count: int) -> Array:
	var rng:=RandomNumberGenerator.new(); rng.seed=int(c.loot_seed)^140014
	if c.has("spell_rng_state"): rng.state=int(str(c.spell_rng_state))
	var pool: Array=[]
	for id in ids(c):
		if int(DATA[id].realm)==0 or P.foundation(c) or int(c.level)>=20: pool.append(id)
	var drops: Array=[]
	for i in range(count):
		if rng.randf()>=0.15 or pool.is_empty(): continue
		var item:=manual(pool[rng.randi_range(0,pool.size()-1)])
		if not E.put(c.inventory,item): c.pending_loot.append(item)
		drops.append(item)
	c.spell_rng_state=str(rng.state)
	return drops
static func action(c: Dictionary, round_number: int) -> Dictionary:
	var known: Array=[]
	for realm in [1,0]:
		for id in ids(c):
			if int(DATA[id].realm)==realm and permitted(c,id) and int(c.spells.get(id,0))>0: known.append(id)
	if known.is_empty(): return {"name":"普通攻击","damage":0,"heal":0,"guard":0,"level":0}
	var id: String=known[(maxi(1,round_number)-1)%known.size()]
	var level:=int(c.spells[id])
	var result: Dictionary={"id":id,"name":DATA[id].name,"level":level}
	for key in ["damage","heal","guard"]: result[key]=int(DATA[id][key][0])+int(DATA[id][key][1])*(level-1)
	return result
static func describe(id: String, level: int) -> String:
	var values: Array=[]
	for key in ["damage","heal","guard"]: values.append(int(DATA[id][key][0])+int(DATA[id][key][1])*(maxi(1,level)-1))
	return "附加伤害%d · 恢复气血%d · 本回合减伤%d" % values
