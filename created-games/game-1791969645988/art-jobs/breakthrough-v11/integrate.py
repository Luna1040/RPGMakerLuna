from pathlib import Path
p=Path('estate_system.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('const YIELDS=', 'const HERBS={"qing":"青灵草","ning":"凝露花","jade":"青髓芝","violet":"紫灵花","sun":"玄阳参"}\nconst YIELDS=',1)
s=s.replace('return stack("seed",id,"青灵草种" if id=="qing" else "凝露花种",qty)','return stack("seed",id,str(HERBS.get(id,"未知药材"))+"种",qty)')
s=s.replace('not id in ["qing","ning"]','not HERBS.has(id)').replace('"青灵草" if plot.id=="qing" else "凝露花"','str(HERBS.get(plot.id,"灵草"))')
s+='''
static func foundation_pill(c: Dictionary) -> bool:
	for id in ["jade","violet","sun"]:
		if count(c.inventory,"herb",id)<3: return false
	var before:=c.duplicate(true)
	for id in ["jade","violet","sun"]: consume(c.inventory,"herb",id,3)
	if not put(c.inventory,stack("breakthrough_pill","foundation","筑基丹",1,3)):
		c.merge(before,true); return false
	return true
'''
p.write_text(s,encoding='utf-8')
p=Path('main.gd');s=p.read_text(encoding='utf-8');s=s.replace('const Dungeon=','const Progress=preload("res://progression_system.gd")\nconst Dungeon=',1)
s=s.replace('\tDungeon.normalize(character,int(Time.get_unix_time_from_system()))','\tDungeon.normalize(character,int(Time.get_unix_time_from_system()))\n\tvar new_balance_state:=Progress.normalize(character)',1)
s=s.replace('(gifted or new_retainer_offers or new_respawn_state)','(gifted or new_retainer_offers or new_respawn_state or new_balance_state)')
a=s.index('func add_experience(');b=s.index('func npc_has_task(',a)
s=s[:a]+'''func add_experience(amount: int) -> void:
	if Progress.add(character,amount): character.hp=max_hp()

'''+s[b:]
s=s.replace('return Gear.totals(character.get("equipment",[]))','var result:=Gear.totals(character.get("equipment",[]))\n\tvar realm_stats:=Progress.realm_stats(character)\n\tfor key in ["attack","defense","hp"]: result[key]+=int(realm_stats[key])\n\treturn result',1)
s=s.replace('var multiplier:=DUNGEON_REWARD_MULTIPLIER if kind=="dungeon" else 1\n\treturn {"xp":maxi(1,level)*4*maxi(0,count)*multiplier,"stones":','var multiplier:=DUNGEON_REWARD_MULTIPLIER if kind=="dungeon" else 1\n\tvar experience:=maxi(1,level)*4*maxi(0,count)*multiplier\n\tif kind=="wild" and int(character.get("level",1))>=10: experience=mini(6,maxi(0,count)*2)\n\treturn {"xp":experience,"stones":',1)
s=s.replace('\tif character.zone=="town":\n\t\tquest_label.text=', '\tif int(character.level)==20 and not Progress.foundation(character): status_label.text+=" · 瓶颈：请到洞府突破"\n\tif character.zone=="town":\n\t\tquest_label.text=',1)
p.write_text(s,encoding='utf-8')
p=Path('dungeon_world.gd');s=p.read_text(encoding='utf-8');s=s.replace('const D=','const E=preload("res://estate_system.gd")\nconst P=preload("res://progression_system.gd")\nconst D=',1)
s=s.replace('\tvar credited:=false','\tif spec.zone=="cavern": reward.xp=P.dungeon_xp(int(c.dungeon.run.floor),bool(spec.get("boss",false)))\n\tvar credited:=false',1)
s=s.replace('\telse: c.hp=game.max_hp()','''			if spec.zone=="cavern" and bool(spec.get("boss",false)):
				var seed_id: String=["jade","violet","sun"][int(c.dungeon.run.floor)-1]
				var seed:=E.seed_item(seed_id,1)
				if not E.put(c.inventory,seed): c.pending_loot.append(seed)
				loot.append(seed)
	else: c.hp=game.max_hp()''',1)
p.write_text(s,encoding='utf-8')
