from pathlib import Path
p=Path('retainer_system.gd');s=p.read_text(encoding='utf-8');s+='''
static func refresh_paid(c: Dictionary, now: int) -> bool:
	if int(c.level)<10 or int(c.get("stones",0))<12: return false
	var deadline:=int(c.retainers.refresh_at)
	if not refresh(c,now,true): return false
	c.retainers.refresh_at=deadline
	c.stones=int(c.stones)-12
	return true
''';p.write_text(s,encoding='utf-8')
p=Path('retainer_ui.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('\trefresh_button.custom_minimum_size.y=30','\trefresh_button.custom_minimum_size.y=30\n\tvar paid: Button=game.button(line,"快速刷新 · 12灵石",refresh_paid)\n\tpaid.custom_minimum_size.y=30\n\tpaid.disabled=int(game.character.stones)<12');s+='''
func refresh_paid() -> void:
	apply(func(): return R.refresh_paid(game.character,int(Time.get_unix_time_from_system())),"已花费12灵石刷新，免费刷新倒计时保持不变")
''';p.write_text(s,encoding='utf-8')
p=Path('main.gd');s=p.read_text(encoding='utf-8');s=s.replace('const Retainers=','const Wild=preload("res://wild_spawns.gd")\nvar respawn_clock:=0.0\nconst Retainers=',1)
s=s.replace('\tvar gifted:=Gear.grant_gifts(character)','\tWild.normalize(character,int(Time.get_unix_time_from_system()))\n\tvar gifted:=Gear.grant_gifts(character)',1)
s=s.replace('var cleared: bool=i in character.cleared','var cleared: bool=monster_dead(i)')
s=s.replace('if group in character.cleared:', 'if monster_dead(group):')
s=s.replace('if group in character.cleared or int(character.field_quest)==0','if monster_dead(group) or int(character.field_quest)==0')
s=s.replace('\t\tif not battle_group in character.cleared:\n\t\t\tcharacter.cleared.append(battle_group)','\t\tif not monster_dead(battle_group):\n\t\t\tWild.killed(character,battle_group,int(Time.get_unix_time_from_system()))\n\t\t\tif not battle_group in character.cleared: character.cleared.append(battle_group)')
s=s.replace('if character.cleared.size()==3: character.field_quest=3','if character.cleared.size()==3 and int(character.field_quest)<3: character.field_quest=3')
s=s.replace('\tretainer_ui.update_cooldown()','\tretainer_ui.update_cooldown()\n\trespawn_clock+=delta\n\tif respawn_clock>=1 and mode=="map" and not character.is_empty() and not is_instance_valid(menu_layer) and not is_instance_valid(modal):\n\t\trespawn_clock=0\n\t\tif Wild.expire(character,int(Time.get_unix_time_from_system())):\n\t\t\tpersist()\n\t\t\tshow_world()',1)
s=s.replace('Color("647781")','Color("9ab7c5")').replace('style.set_border_width_all(2 if exists else 1)','style.set_border_width_all(2)')
# material cells also receive strong grid borders
s=s.replace('\t\telif not item.is_empty():\n\t\t\tcell.text=', '\t\telse:\n\t\t\tdecorate_gear_cell(cell,{},0,false)\n\t\tif not Gear.valid(item) and not item.is_empty():\n\t\t\tcell.text=',1)
s+='''
func monster_dead(group: int) -> bool:
	return Wild.dead(character,group,int(Time.get_unix_time_from_system()))
''';p.write_text(s,encoding='utf-8')
