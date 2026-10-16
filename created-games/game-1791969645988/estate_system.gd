extends RefCounted
const Gear=preload("res://equipment_system.gd")
const HERBS={"qing":"青灵草","ning":"凝露花","jade":"青髓芝","violet":"紫灵花","sun":"玄阳参"}
const YIELDS=[2,4,7,11,16,23,32]
static func stack(kind: String, id: String, title: String, qty: int, quality: int=0) -> Dictionary:
	return {"kind":kind,"id":id,"name":title,"qty":qty,"quality":quality}
static func normalize(c: Dictionary) -> void:
	if not c.has("estate"): c.estate={}
	if not c.estate.has("plots"): c.estate.plots=[]
	while c.estate.plots.size()<20: c.estate.plots.append({})
	if not c.estate.has("storage"): c.estate.storage=[]
	while c.estate.storage.size()<1000: c.estate.storage.append({})
	for bag in [c.inventory,c.pending_loot,c.estate.storage]:
		for item in bag:
			if item.has("qty"): item.qty=int(item.qty)
			if item.has("quality"): item.quality=int(item.quality)
			if item.has("heal"): item.heal=int(item.heal)
			Gear.normalize_item(item)
	for plot in c.estate.plots:
		if plot.has("ready_at"): plot.ready_at=int(plot.ready_at)
	if not c.estate.get("starter",false):
		for id in ["qing","ning"]:
			var item:=seed_item(id,10)
			if not put(c.inventory,item): c.pending_loot.append(item)
		c.estate.starter=true
static func seed_item(id: String, qty: int) -> Dictionary:
	return stack("seed",id,str(HERBS.get(id,"未知药材"))+"种",qty)
static func put(bag: Array, item: Dictionary) -> bool:
	if not Gear.valid(item):
		for other in bag:
			if not other.is_empty() and other.get("kind","")==item.get("kind","-") and other.get("id","")==item.get("id","!"):
				other.qty=int(other.qty)+int(item.get("qty",1)); return true
	for i in range(bag.size()):
		if bag[i].is_empty(): bag[i]=item.duplicate(true); return true
	return false
static func take_slot(bag: Array, index: int, qty: int) -> void:
	if int(bag[index].get("qty",1))<=qty: bag[index]={}
	else: bag[index].qty=int(bag[index].qty)-qty
static func count(bag: Array, kind: String, id: String) -> int:
	var total:=0
	for item in bag:
		if item.get("kind","")==kind and item.get("id","")==id: total+=int(item.get("qty",1))
	return total
static func consume(bag: Array, kind: String, id: String, qty: int) -> bool:
	if count(bag,kind,id)<qty: return false
	for i in range(bag.size()):
		if bag[i].get("kind","")!=kind or bag[i].get("id","")!=id: continue
		var used:=mini(qty,int(bag[i].get("qty",1)))
		take_slot(bag,i,used); qty-=used
		if qty==0: break
	return true
static func plant(c: Dictionary, index: int, id: String, now: int) -> bool:
	if index<0 or index>=20 or not c.estate.plots[index].is_empty() or not HERBS.has(id): return false
	if not consume(c.inventory,"seed",id,1): return false
	c.estate.plots[index]={"id":id,"ready_at":now+10}; return true
static func harvest(c: Dictionary, index: int, now: int) -> bool:
	var plot: Dictionary=c.estate.plots[index]
	if plot.is_empty() or now<int(plot.ready_at): return false
	if not put(c.inventory,stack("herb",plot.id,str(HERBS.get(plot.id,"灵草")),3)): return false
	c.estate.plots[index]={}; return true
static func transfer(c: Dictionary, from_storage: bool, index: int) -> bool:
	var source: Array=c.estate.storage if from_storage else c.inventory
	var target: Array=c.inventory if from_storage else c.estate.storage
	if index<0 or index>=source.size() or source[index].is_empty(): return false
	if not put(target,source[index]): return false
	source[index]={}; return true
static func alchemy(c: Dictionary, strong: bool) -> bool:
	var before:=c.duplicate(true)
	if not consume(c.inventory,"herb","qing",1 if strong else 2): return false
	if strong and not consume(c.inventory,"herb","ning",2): c.merge(before,true); return false
	var potion:=stack("potion","strong" if strong else "weak","凝露丹" if strong else "青灵丹",1)
	potion.heal=100 if strong else 50
	if not put(c.inventory,potion): c.merge(before,true); return false
	return true
static func dismantle(c: Dictionary, index: int) -> bool:
	if index<0 or index>=c.inventory.size() or not Gear.valid(c.inventory[index]): return false
	var quality:=int(c.inventory[index].quality)
	c.inventory[index]={}
	return put(c.inventory,stack("fragment",str(quality),Gear.QUALITY_NAMES[quality]+"装备碎片",YIELDS[quality],quality))
static func craft_cost(q: int) -> int: return (q+1)*(q+1)*10
static func craft_need(q: int) -> int: return YIELDS[q]+maxi(2,int(ceil(YIELDS[q]*0.5)))
static func craft(c: Dictionary, quality: int, slot: int) -> bool:
	if quality<0 or quality>6 or slot<0 or slot>7: return false
	if int(c.stones)<craft_cost(quality) or count(c.inventory,"fragment",str(quality))<craft_need(quality): return false
	var before:=c.duplicate(true)
	consume(c.inventory,"fragment",str(quality),craft_need(quality))
	if not put(c.inventory,Gear.make_item(slot,quality,int(c.level))): c.merge(before,true); return false
	c.stones=int(c.stones)-craft_cost(quality); return true
static func describe(item: Dictionary) -> String:
	if Gear.valid(item): return Gear.describe(item)
	if item.is_empty(): return "空格"
	return "%s ×%d" % [str(item.get("name","物品")),int(item.get("qty",1))]

static func foundation_pill(c: Dictionary) -> bool:
	for id in ["jade","violet","sun"]:
		if count(c.inventory,"herb",id)<3: return false
	var before:=c.duplicate(true)
	for id in ["jade","violet","sun"]: consume(c.inventory,"herb",id,3)
	if not put(c.inventory,stack("breakthrough_pill","foundation","筑基丹",1,3)):
		c.merge(before,true); return false
	return true
