from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('const SlotIcon=','const Spells=preload("res://spell_system.gd")\nvar spell_ui=preload("res://spell_ui.gd").new()\nconst SlotIcon=',1)
s=s.replace('\tEstate.normalize(character)','\tEstate.normalize(character)\n\tSpells.normalize(character)',1)
s=s.replace('"任务","技能","系统"','"任务","仙法","系统"').replace('技能 K','仙法 K')
s=s.replace('\t\t4: build_task_menu(content)','\t\t4: build_task_menu(content)\n\t\t5: spell_ui.build(self,content)',1)
s=s.replace('elif character.inventory[index].get("kind","")=="breakthrough_pill":','elif character.inventory[index].get("kind","")=="spell_manual":\n\t\tspell_ui.game=self\n\t\tspell_ui.learn(str(character.inventory[index].id),2)\n\telif character.inventory[index].get("kind","")=="breakthrough_pill":',1)
s=s.replace('+(18 if round_number%3==0 else 0))','+(18 if round_number%3==0 else 0)+int(Spells.action(character,round_number).damage))',1)
s=s.replace('\tenemy_hp-=damage\n\tfor i in range(battle_retainer_units.size()):','\tenemy_hp-=damage\n\tvar spell:=Spells.action(character,round_number)\n\tcombat_hp=mini(max_hp(),combat_hp+int(spell.heal))\n\tif not quick_mode and int(spell.level)>0: battle_log.append_text("施展%s Lv.%d：恢复%d气血，本回合减伤%d。\\n" % [spell.name,spell.level,spell.heal,spell.guard])\n\tfor i in range(battle_retainer_units.size()):',1)
s=s.replace('var damage:=mini(combat_hp,maxi(1,int(battle_spec.get("damage",12+battle_group*7))-int(gear_stats().defense)))','var damage:=mini(combat_hp,maxi(1,int(battle_spec.get("damage",12+battle_group*7))-int(gear_stats().defense)-int(Spells.action(character,round_number).guard)))',1)
s=s.replace('\t\t\tloot=Gear.roll_wild(character,MONSTER_LEVELS[battle_group],3)','\t\t\tloot=Gear.roll_wild(character,MONSTER_LEVELS[battle_group],3)\n\t\t\tloot.append_array(Spells.drop_wild(character,3))',1)
s=s.replace('elif index==1 and int(character.sect_quest)==1:', 'elif index==0 and int(character.sect_quest)>=2:\n\t\t\tfoundation_dialog()\n\t\telif index==1 and int(character.sect_quest)==1:',1)
s=s.replace('return int(character.level)>=10 and ((index==2','return int(character.level)>=10 and ((index==0 and int(character.sect_quest)>=2 and foundation_task_ready()) or (index==2',1)
s=s.replace('\treturn result\n\nfunc build_task_menu','''	if int(character.sect_quest)>=2:
		var step:=int(character.foundation_quest)
		var titles: Array=["筑基之约 · 达到20级拜访接引长老","三灵归元 · 集齐药种并炼制筑基丹","洞府筑基 · 突破筑基后向长老复命"]
		for i in range(3):
			if i>0 and step<i+1: continue
			var status: String="已完成任务" if step>=i+2 else ("已接任务" if step==i+1 else "可接任务")
			result[status].append({"title":titles[i],"npc":"接引长老","zone":"sect","index":0})
	return result

func build_task_menu''',1)
s+='''
func foundation_task_ready() -> bool:
	match int(character.foundation_quest):
		0: return true
		1: return int(character.level)>=20 or Progress.foundation(character)
		2: return Estate.count(character.inventory,"breakthrough_pill","foundation")>0 or Progress.foundation(character)
		3: return Progress.foundation(character)
	return false
func foundation_dialog() -> void:
	var step:=int(character.foundation_quest)
	var lines: Array=["练气之上，便是筑基。先将修为修炼至二十级，再来寻我。十级起完整通关五次万妖窟恰可达到二十级。","二十级是练气瓶颈。万妖窟三层BOSS分别出产青髓芝、紫灵花、玄阳参种子；去仙园药园种植，每种药材三份，可在炼丹炉炼成筑基丹。","带上筑基丹，前往仙园洞府突破。不用丹成功率30%，使用一枚为80%。失败退回十九级，须重新升满二十级再试；成功后向我复命。","你已踏入筑基，仙途更进一步。这二百灵石助你继续修行。"]
	if step>=4: dialog("接引长老","筑基之路已成，继续研习本职业筑基仙法。","继续修行",close_dialog); return
	var action: String="接取 · 筑基之约" if step==0 else ("领取 · 筑基奖励" if step==3 else "完成阶段 · 继续指引")
	if not foundation_task_ready():
		dialog("接引长老",lines[maxi(0,step-1)],"继续准备",close_dialog); return
	dialog("接引长老",lines[step],action,advance_foundation.bind(step+1))
func advance_foundation(next_step: int) -> void:
	if int(character.sect_quest)<2 or next_step!=int(character.foundation_quest)+1 or not foundation_task_ready(): return
	var before:=character.duplicate(true)
	character.foundation_quest=next_step
	if next_step==4: character.stones=int(character.stones)+200
	if not persist(): character=before; return
	close_dialog(); show_world()
'''
p.write_text(s,encoding='utf-8')
p=Path('dungeon_world.gd');s=p.read_text(encoding='utf-8');s=s.replace('const E=','const S=preload("res://spell_system.gd")\nconst E=',1)
s=s.replace('\t\t\tif spec.zone=="cavern" and bool(spec.get("boss",false)):','\t\t\tif spec.zone=="wilds": loot.append_array(S.drop_wild(c,int(spec.count)))\n\t\t\tif spec.zone=="cavern" and bool(spec.get("boss",false)):',1);p.write_text(s,encoding='utf-8')
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8');s=s.replace('const SlotIcon=','const S=preload("res://spell_system.gd")\nvar manual_texture: Texture2D\nconst SlotIcon=',1)
s=s.replace('func item_icon(item: Dictionary) -> Texture2D:\n','''func item_icon(item: Dictionary) -> Texture2D:
	if item.get("kind","")=="spell_manual" and S.DATA.has(str(item.get("id",""))) and FileAccess.file_exists("res://assets/spell-manuals.png"):
		if manual_texture==null: manual_texture=game.texture_file("res://assets/spell-manuals.png")
		var atlas:=AtlasTexture.new(); atlas.atlas=manual_texture
		atlas.region=Rect2(S.CLASSES.find(S.DATA[item.id]["class"])*256,0,256,256)
		return atlas
''',1);p.write_text(s,encoding='utf-8')
