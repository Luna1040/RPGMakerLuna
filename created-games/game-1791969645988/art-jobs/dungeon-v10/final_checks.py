from pathlib import Path
p=Path('dungeon_world.gd');s=p.read_text(encoding='utf-8').replace('Vector2(1030,350)','Vector2(1030,270)').replace('Vector2(460+i*340,540)','[Vector2(700,360),Vector2(870,535)][i]');p.write_text(s,encoding='utf-8')
p=Path('tests/dungeon_v10.gd');s=p.read_text(encoding='utf-8-sig').replace('var failures:=0','class FailingStore:\n\textends "res://save_store.gd"\n\tfunc save_slot(_slot: int, _data: Dictionary) -> bool:\n\t\tlast_error="test write failure"\n\t\treturn false\nvar failures:=0',1)
s=s.replace('\tgame.close_dialog(); game.dungeon_world.handle("enter"); game.dungeon_world.enter()','''	game.close_dialog()
	var original_store=game.store
	var original_character: Dictionary=game.character.duplicate(true)
	game.store=FailingStore.new(); game.dungeon_world.enter()
	check(game.character==original_character,"failed save refunds entry and restores map")
	game.store=original_store; game.close_dialog()
	game.dungeon_world.handle("enter"); game.dungeon_world.enter()''')
s=s.replace('\tgame.persist(); var saved=game.character.dungeon.duplicate(true); game.logout(); game.enter_character(0)','''	game.character.inventory[0]=G.make_item(1,3,10,"xiaoyao")
	var current_level:=int(game.character.level)
	game.character.level=9
	check(not game.equip_from_bag(0),"level nine cannot equip Xiaoyao")
	game.character.level=current_level
	check(game.equip_from_bag(0),"level ten plus can equip Xiaoyao")
	game.close_menu()
	game.persist(); var saved=game.character.dungeon.duplicate(true); game.logout(); game.enter_character(0)''')
p.write_text(s,encoding='utf-8')
