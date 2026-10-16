from pathlib import Path
p=Path('dungeon_world.gd');s=p.read_text(encoding='utf-8-sig')
s=s.replace('\t\t\tvar before: Dictionary=game.character.duplicate(true)\n\t\t\tif not D.next_floor','\t\t\tvar before: Dictionary=game.character.duplicate(true)\n\t\t\tvar old_position: Vector2=game.player_pos\n\t\t\tif not D.next_floor',1).replace('if not game.persist(): game.character=before; return','if not game.persist(): game.character=before; game.player_pos=old_position; return',1)
s=s.replace('''		"exit":
			if bool(game.character.dungeon.run.get("completed",false)): game.character.dungeon.run.active=false
			game.character.zone="wilds"; game.player_pos=Vector2(950,500); game.persist(); game.show_world()''','''		"exit":
			var before: Dictionary=game.character.duplicate(true)
			var old_position: Vector2=game.player_pos
			if bool(game.character.dungeon.run.get("completed",false)): game.character.dungeon.run.active=false
			game.character.zone="wilds"; game.player_pos=Vector2(950,500)
			if not game.persist(): game.character=before; game.player_pos=old_position; return
			game.show_world()''')
s=s.replace('''	var before: Dictionary=game.character.duplicate(true)
	if not D.enter''','''	var before: Dictionary=game.character.duplicate(true)
	var old_position: Vector2=game.player_pos
	if not D.enter''',1).replace('if not game.persist(): game.character=before; game.dialog("存档失败"','if not game.persist(): game.character=before; game.player_pos=old_position; game.dialog("存档失败"',1)
s=s.replace('''	var c: Dictionary=game.character
	var spec: Dictionary=game.battle_spec''','''	var c: Dictionary=game.character
	var previous: Dictionary=c.duplicate(true)
	var spec: Dictionary=game.battle_spec''',1)
s=s.replace('''	game.persist()
	var names: PackedStringArray=[]''','''	if not game.persist():
		game.character=previous
		game.dialog("结算保存失败",game.store.last_error+"；本次奖励未入账，请重试保存。","重试结算",retry_settlement)
		game.modal.get_child(0).get_child(3).queue_free()
		return
	var names: PackedStringArray=[]''',1)
s+='''
func retry_settlement() -> void:
	game.close_dialog()
	game.settled=false
	game.settle_battle()
'''
p.write_text(s,encoding='utf-8')
p=Path('main.gd');s=p.read_text(encoding='utf-8').replace('"positions":[Vector2(290,400)]','"positions":[Vector2(320,480)]');p.write_text(s,encoding='utf-8')
