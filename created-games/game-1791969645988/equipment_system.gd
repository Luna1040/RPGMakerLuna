extends RefCounted
const QUALITY_NAMES:=["灰色","白色","绿色","蓝色","紫色","橙色","暗金色"]
const QUALITY_COLORS:=["929292","eeeeee","67ce72","57a8ff","ba7bff","ff9f40","c39a39"]
const QUALITY_FACTORS:=[1,2,3,4,6,8,11]
const SLOT_NAMES:=["武器","头冠","衣服","护腕","腰带","鞋履","戒指","护符"]
const ITEM_NAMES:=["灵剑","道冠","道袍","护腕","腰带","布靴","灵戒","玉符"]
const SET_THRESHOLDS:=[2,4,6,8]
const SETS:={"xianyuan":{"name":"仙缘","pieces":2,"bonuses":{2:{"attack":8,"defense":4,"hp":40}}},"xiaoyao":{"name":"逍遥","pieces":4,"bonuses":{2:{"attack":12,"defense":8,"hp":60},4:{"attack":25,"defense":15,"hp":120}}}}

static func valid(item: Variant) -> bool:
	return item is Dictionary and item.has_all(["uid","name","level","slot","quality","stats"]) and item.stats is Dictionary and int(item.slot)>=0 and int(item.slot)<8 and int(item.quality)>=0 and int(item.quality)<7

static func normalize_item(item: Dictionary) -> void:
	if not valid(item): return
	for key in ["slot","quality","level"]: item[key]=int(item[key])
	for key in ["attack","defense","hp"]: item.stats[key]=int(item.stats.get(key,0))

static func normalize(c: Dictionary) -> void:
	if not c.get("equipment") is Array: c.equipment=[]
	while c.equipment.size()<8: c.equipment.append({})
	for i in range(8):
		if not valid(c.equipment[i]): c.equipment[i]={}
	if not c.get("inventory") is Array: c.inventory=[]
	while c.inventory.size()<500: c.inventory.append({})
	if not c.has("pending_loot"): c.pending_loot=[]
	if not c.has("reward_claims"): c.reward_claims={}
	if not c.has("gear_serial"): c.gear_serial=0
	if not c.has("loot_seed"): c.loot_seed=randi()
	for collection in [c.equipment,c.inventory,c.pending_loot]:
		for item in collection:
			if item is Dictionary: normalize_item(item)

static func make_item(slot: int, quality: int, level: int, set_id: String="", uid: String="") -> Dictionary:
	if slot<0 or slot>=8 or quality<0 or quality>=7: return {}
	if set_id=="xianyuan" and not slot in [0,2]: return {}
	if set_id=="xiaoyao":
		if not slot in [1,3,4,5]: return {}
		quality=3; level=10
	var factor: int=QUALITY_FACTORS[quality]
	var item_name: String=("仙缘" if set_id=="xianyuan" else ("逍遥" if set_id=="xiaoyao" else QUALITY_NAMES[quality]))+ITEM_NAMES[slot]
	return {"uid":uid if not uid.is_empty() else "%d-%d" % [Time.get_ticks_usec(),randi()],"name":item_name,"slot":slot,"quality":quality,"level":level,"set_id":set_id,"stats":{"attack":(1+int(ceil(level/3.0)))*factor*(2 if slot==0 else 1),"defense":(1+int(ceil(level/5.0)))*factor*(2 if slot==2 else 1),"hp":(5+level)*factor}}

static func empty_bag_slot(c: Dictionary) -> int:
	for i in range(500):
		if c.inventory[i] is Dictionary and c.inventory[i].is_empty(): return i
	return -1

static func receive(c: Dictionary, item: Dictionary) -> bool:
	var index:=empty_bag_slot(c)
	if index<0:
		c.pending_loot.append(item)
		return false
	c.inventory[index]=item
	return true

static func claim_pending(c: Dictionary) -> int:
	var count:=0
	while not c.pending_loot.is_empty() and empty_bag_slot(c)>=0:
		c.inventory[empty_bag_slot(c)]=c.pending_loot.pop_front()
		count+=1
	return count

static func grant_gifts(c: Dictionary) -> bool:
	var changed:=false
	for gift in [{"key":"xianyuan_5","eligible":int(c.get("quest",0))>=5,"slot":0,"level":5},{"key":"xianyuan_10","eligible":int(c.get("field_quest",0))==4,"slot":2,"level":10}]:
		if not gift.eligible or bool(c.reward_claims.get(gift.key,false)): continue
		receive(c,make_item(gift.slot,3,gift.level,"xianyuan",gift.key))
		c.reward_claims[gift.key]=true
		changed=true
	return changed

static func drop_category(kind: String, roll: float) -> String:
	if kind=="wild": return "scatter" if roll<0.30 else "none"
	if kind=="dungeon": return "scatter" if roll<0.30 else "set"
	return "none"

static func roll_wild(c: Dictionary, level: int, count: int) -> Array:
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(c.loot_seed)
	if c.has("loot_rng_state"): rng.state=int(str(c.loot_rng_state))
	var items: Array=[]
	for i in range(count):
		if drop_category("wild",rng.randf())!="scatter": continue
		c.gear_serial=int(c.gear_serial)+1
		var item:=make_item(rng.randi_range(0,7),rng.randi_range(0,1),level,"","drop_%d_%d" % [int(c.loot_seed),int(c.gear_serial)])
		receive(c,item)
		items.append(item)
	c.loot_rng_state=str(rng.state)
	return items

static func totals(equipment: Array, definitions: Dictionary=SETS) -> Dictionary:
	var result: Dictionary={"attack":0,"defense":0,"hp":0,"sets":{},"active_bonuses":[]}
	for item in equipment:
		if not valid(item): continue
		for stat in ["attack","defense","hp"]: result[stat]+=int(item.stats.get(stat,0))
		var set_id: String=str(item.get("set_id",""))
		if not set_id.is_empty(): result.sets[set_id]=int(result.sets.get(set_id,0))+1
	for set_id in result.sets:
		if not definitions.has(set_id): continue
		for threshold in SET_THRESHOLDS:
			if int(result.sets[set_id])<threshold: continue
			var bonus: Dictionary=definitions[set_id].bonuses.get(threshold,{})
			if bonus.is_empty(): continue
			for stat in ["attack","defense","hp"]: result[stat]+=int(bonus.get(stat,0))
			result.active_bonuses.append({"set_id":set_id,"name":definitions[set_id].name,"threshold":threshold,"stats":bonus})
	return result

static func describe(item: Dictionary) -> String:
	if not valid(item): return "未装备"
	var text: String="%s · %s · %d级\n%s\n攻击 +%d   防御 +%d   气血 +%d" % [item.name,QUALITY_NAMES[int(item.quality)],item.level,SLOT_NAMES[int(item.slot)],item.stats.attack,item.stats.defense,item.stats.hp]
	if item.get("set_id","")=="xianyuan":text+="\n仙缘套装（共2件）\n2件：攻击+8，防御+4，气血+40"
	elif item.get("set_id","")=="xiaoyao": text+="\n逍遥套装（共4件，10级可装备）\n2件：攻击+12 防御+8 气血+60\n4件额外：攻击+25 防御+15 气血+120"
	else: text+="\n散装备"
	return text
