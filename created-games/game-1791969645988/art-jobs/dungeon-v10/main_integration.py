from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8');s=s.replace('const Wild=','const Dungeon=preload("res://dungeon_system.gd")\nvar dungeon_world=preload("res://dungeon_world.gd").new()\nvar next_encounter: Dictionary={}\nvar battle_spec: Dictionary={}\nconst Wild=',1)
s=s.replace('\tvar gifted:=Gear.grant_gifts(character)','\tDungeon.normalize(character,int(Time.get_unix_time_from_system()))\n\tif character.get("zone","")=="cavern" and character.dungeon.run.is_empty(): character.zone="wilds"\n\tvar gifted:=Gear.grant_gifts(character)',1)
s=s.replace('"portraits":[5,2,6]}','"portraits":[5,2,6]},\n\t"wilds":{"title":"镇妖谷 · 万妖窟外","background":"res://assets/demon-valley.png","names":["镇妖使"],"positions":[Vector2(290,400)],"portraits":[6]},\n\t"cavern":{"title":"万妖窟 · 三层试炼","background":"res://assets/demon-cavern.png","names":[],"positions":[],"portraits":[]}',1)
s=s.replace('"label":"云雾山","level":1}]\n}', '"label":"云雾山","level":1},{"id":"sect_wilds","position":Vector2(1125,555),"target":"wilds","spawn":Vector2(180,560),"label":"镇妖谷 · 10级","level":10}],\n\t"wilds":[{"id":"wilds_sect","position":Vector2(125,560),"target":"sect","spawn":Vector2(1020,550),"label":"青云宗","level":10}]\n}',1)
s=s.replace('func npc_has_task(index: int) -> bool:\n','func npc_has_task(index: int) -> bool:\n\tif character.zone in ["wilds","cavern"]: return false\n',1)
s=s.replace('func use_portal(id: String) -> void:\n','func use_portal(id: String) -> void:\n\tif id.begins_with("extra_"):\n\t\tdungeon_world.handle(id.trim_prefix("extra_")); return\n',1)
s=s.replace('\tavatar=actor(map_layer,0,player_pos,character.name)','\tdungeon_world.draw(self)\n\tavatar=actor(map_layer,0,player_pos,character.name)',1)
s=s.replace('\telse:\n\t\tquest_label.text=["仙途','\telif character.zone in ["wilds","cavern"]:\n\t\tquest_label.text=dungeon_world.status()\n\telse:\n\t\tquest_label.text=["仙途',1)
s=s.replace('func interact(action: String) -> void:\n','func interact(action: String) -> void:\n\tif action.begins_with("extra:"):\n\t\tdungeon_world.handle(action.trim_prefix("extra:")); return\n',1)
s=s.replace('\tif character.zone=="sect":\n\t\tif index==2:', '\tif character.zone=="wilds":\n\t\tdialog("镇妖使","万妖窟每日可开启五次新挑战，UTC+8零点重置。三层均需击败四堆小怪，再击败妖王。逍遥套装含头冠、护腕、腰带、鞋履；均为蓝色、10级可装备。暂离可继续原进度，不再扣次。","明白了",close_dialog)\n\t\treturn\n\tif character.zone=="sect":\n\t\tif index==2:',1)
s=s.replace('''	if character.zone!="field" or group<0 or group>=3: return
	if monster_dead(group) or int(character.field_quest)==0 or (group>0 and int(character.field_quest)<2): return
	return_pos=player_pos''','''	if next_encounter.is_empty():
		if character.zone!="field" or group<0 or group>=3: return
		if monster_dead(group) or int(character.field_quest)==0 or (group>0 and int(character.field_quest)<2): return
		battle_spec={"zone":"field","level":MONSTER_LEVELS[group],"count":3,"name":MONSTERS[group],"hp":160+group*70,"damage":12+group*7,"background":"res://assets/battle.png"}
	else:
		battle_spec=next_encounter; next_encounter={}
	return_pos=player_pos''',1)
s=s.replace('max_enemy_hp=160+group*70','max_enemy_hp=int(battle_spec.hp)',1).replace('background("res://assets/battle.png")','background(str(battle_spec.background))',1)
s=s.replace('for i in range(3): battle_enemies.append(actor(screen,7,Vector2(850+i*100,500+i*50),"妖狼 Lv.%d" % MONSTER_LEVELS[group],1.6))','for i in range(int(battle_spec.count)): battle_enemies.append(actor(screen,7,Vector2(850+i*100,500+i*50),str(battle_spec.name)+" Lv.%d" % int(battle_spec.level),2.5 if battle_spec.get("boss",false) else 1.6))',1)
s=s.replace('"云雾山 · "+MONSTERS[group]+" / 自动回合战斗"','str(battle_spec.name)+" / 自动回合战斗"',1)
s=s.replace('12+battle_group*7-int(', 'int(battle_spec.get("damage",12+battle_group*7))-int(')
s=s.replace('(maxi(round_number,1)-1)%3','(maxi(round_number,1)-1)%maxi(1,battle_enemies.size())',1)
s=s.replace('\treset_battle_poses()\n\tvar rewards:=','\treset_battle_poses()\n\tif battle_spec.get("zone","field")!="field":\n\t\tdungeon_world.settle(); return\n\tvar rewards:=',1)
s=s.replace('\tvar previous:=character.duplicate(true)\n\tvar item: Dictionary=character.inventory[index]','\tif int(character.level)<int(character.inventory[index].level):\n\t\tgear_notice="等级不足，需要%d级" % int(character.inventory[index].level)\n\t\trefresh_gear_panel(2)\n\t\treturn false\n\tvar previous:=character.duplicate(true)\n\tvar item: Dictionary=character.inventory[index]',1)
s=s.replace('\tlabel_text(content,set_text,17)','\tif int(stats.sets.get("xiaoyao",0))>0: set_text+="\\n逍遥 %d/4 · 2件攻击+12防御+8气血+60；4件额外攻击+25防御+15气血+120" % int(stats.sets.xiaoyao)\n\tlabel_text(content,set_text,17)',1)
p.write_text(s,encoding='utf-8')
