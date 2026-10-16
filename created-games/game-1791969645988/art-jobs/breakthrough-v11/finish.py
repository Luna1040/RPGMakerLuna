from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('暂离可继续原进度，不再扣次。','暂离可继续原进度，不再扣次。完整通关得200经验，十级起五次升到二十级。三层BOSS各掉一种筑基药种，种植炼丹后，到仙园洞府突破筑基。',1);p.write_text(s,encoding='utf-8')
p=Path('tests/breakthrough_v11.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('const G=','const R=preload("res://retainer_system.gd")\nconst G=',1).replace('check(P.realm_stats(c).hp==150','check(R.follow_limit(c)==2,"foundation allows two followers")\n\tcheck(P.realm_stats(c).hp==150',1)
s=s.replace('\tgame.store=original_store\n\tgame.estate_ui.perform_breakthrough(true)','''	game.store=original_store
	for room in ["药园","炼丹炉","洞府"]:
		game.estate_ui.navigate(room)
		for tick in range(4): await process_frame
		var rect: Rect2=game.menu_window.get_global_rect()
		check(rect.end.y<=800,"new facility window fits")
		for child in game.menu_window.get_node("Content").get_children():
			if child is Control: check(child.get_global_rect().end.y<=rect.end.y+1,"new recipe and breakthrough controls fit")
	game.estate_ui.perform_breakthrough(true)''',1)
p.write_text(s,encoding='utf-8')
