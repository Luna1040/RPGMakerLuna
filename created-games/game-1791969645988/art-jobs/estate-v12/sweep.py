from pathlib import Path
p=Path('dungeon_system.gd');s=p.read_text(encoding='utf-8-sig').replace('const G=','const E=preload("res://estate_system.gd")\nconst P=preload("res://progression_system.gd")\nconst R=preload("res://retainer_system.gd")\nconst G=',1)
s=s.replace('if str(d.day)!=day(now): d.day=day(now); d.used=0','if str(d.day)!=day(now): d.day=day(now); d.used=0; d.bought=0\n\td.bought=int(d.get("bought",0))')
s=s.replace('if int(c.dungeon.used)>=5:','if remaining(c)<=0:')
s+='''
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
''';p.write_text(s,encoding='utf-8')
p=Path('dungeon_world.gd');s=p.read_text(encoding='utf-8');s=s.replace('今日已挑战%d/5次（UTC+8）" % c.dungeon.used','今日剩余%d次（基础5次+已购%d次，UTC+8）" % [D.remaining(c),int(c.dungeon.bought)]')
s=s.replace('"\\n今日已用%d/5次（UTC+8零点刷新）。" % game.character.dungeon.used','"\\n今日剩余%d次（基础5次+已购%d次，UTC+8零点刷新）。" % [D.remaining(game.character),int(game.character.dungeon.bought)]')
s=s.replace('\t\t"next":','''			var options: VBoxContainer=game.modal.get_child(0)
			var sweep_button: Button=game.button(options,"速刷一次 · 1000灵石（消耗1次挑战）",confirm_sweep)
			sweep_button.disabled=int(game.character.dungeon.wins)<1
			game.button(options,"购买额外挑战 · 3000灵石/次",confirm_purchase)
		"next":''',1)
s+='''
func confirm_sweep() -> void:
	game.dialog("确认速刷万妖窟","消耗1000灵石和1次今日挑战，结算完整三层奖励：200经验、5160灵石、三种种子各1份及按原概率掷出的装备。", "确认速刷",sweep_once)
func confirm_purchase() -> void:
	game.dialog("购买额外挑战","花费3000灵石，增加1次今日挑战次数。额外次数当日有效，UTC+8零点重置。","确认购买",purchase_once)
func purchase_once() -> void:
	var before: Dictionary=game.character.duplicate(true)
	if not D.purchase(game.character,int(Time.get_unix_time_from_system())):
		game.dialog("购买失败","需达到10级并持有3000灵石。","返回",game.close_dialog); return
	if not game.persist(): game.character=before; game.dialog("保存失败",game.store.last_error,"返回",game.close_dialog); return
	game.dialog("购买成功","已增加1次挑战，今日剩余%d次。" % D.remaining(game.character),"返回副本入口",handle.bind("enter"))
	game.refresh_map()
func sweep_once() -> void:
	var before: Dictionary=game.character.duplicate(true)
	var reward:=D.sweep(game.character,int(Time.get_unix_time_from_system()))
	if reward.has("error"): game.character=before; game.dialog("无法速刷",reward.error,"返回",game.close_dialog); return
	game.character.hp=game.max_hp()
	if not game.persist(): game.character=before; game.dialog("保存失败",game.store.last_error+"；扣费、次数和奖励已回滚。","返回",game.close_dialog); return
	var names: PackedStringArray=[]
	for item in reward.loot: names.append(item.name)
	game.dialog("万妖窟速刷完成","花费1000灵石，消耗1次挑战。获得200经验、5160灵石、三种种子和%d件装备。\\n随行散修各获400经验。满包物品在背包待领取。今日剩余%d次。" % [reward.loot.size()-3,D.remaining(game.character)],"确定",game.close_dialog)
	game.refresh_map()
''';p.write_text(s,encoding='utf-8')
