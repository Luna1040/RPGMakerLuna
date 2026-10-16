from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8');s=s.replace('const Spells=','const ClassProfile=preload("res://class_profile.gd")\nconst Spells=',1)
s=s.replace('avatar=actor(map_layer,0,player_pos,character.name)','avatar=player_actor(map_layer,player_pos,character.name)',1).replace('battle_player=actor(screen,0,Vector2(320,570),character.name,2.4)','battle_player=player_actor(screen,Vector2(320,570),character.name,2.4)',1).replace('actor(preview,0,Vector2(90,160),character.name,2.0)','player_actor(preview,Vector2(90,160),character.name,2.0)',1)
s=s.replace('actions={"sword":load_battle_action("sword"),"bite":load_battle_action("bite")}','var class_action:=load_battle_action("classes/"+ClassProfile.role(character))\n\tactions={"sword":load_battle_action("sword") if class_action.is_empty() else class_action,"bite":load_battle_action("bite")}',1)
s=s.replace('\t\tquest_label.text=["仙途 · 达到10级，拜访接引长老","仙途 · 已入练气期，拜访传功师姐学习周天功法","仙途 · 入门功法已掌握，修仙之路正式开启"][mini(int(character.sect_quest),2)]','\t\tquest_label.text=["仙途 · 达到10级，拜访接引长老","仙途 · 已入练气期，拜访传功师姐学习周天功法","仙途 · 入门功法已掌握，修仙之路正式开启"][mini(int(character.sect_quest),2)]\n\t\tif int(character.sect_quest)>=2: quest_label.text=["筑基之约 · 拜访接引长老接取二十级筑基指引","筑基之约 · 将修为提升至20级后拜访接引长老","三灵归元 · 通关万妖窟收种，种药炼筑基丹，再找长老","洞府筑基 · 到仙园洞府突破，筑基成功后向长老复命","仙途 · 筑基任务完成，继续研习本职业筑基仙法"][clampi(int(character.foundation_quest),0,4)]',1)
s+='''
func player_actor(parent: Node, pos: Vector2, title: String, scale_value: float=1.0) -> Control:
	var holder:=actor(parent,0,pos,title,scale_value)
	ClassProfile.apply(holder,character,scale_value,texture_file)
	return holder
'''
p.write_text(s,encoding='utf-8')
