from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8')
s=s.replace('\tcharacter = {"name": name_value', '\tplayer_pos=Vector2(620,610)\n\tcharacter = {"name": name_value')
# Clear pending movement and mode when going back to character selection.
s=s.replace('func show_slots() -> void:\n', 'func show_slots() -> void:\n\tmode="slots"\n')
p.write_text(s,encoding='utf-8')
p=Path('tests/smoke.gd');s=p.read_text(encoding='utf-8-sig')
s=s.replace('game.interact("exit")\n\tcheck(game.character.zone=="town"', 'game.travel(game.TOWN_POS[0]+Vector2(0,85),"npc:0")\n\tcheck(not is_instance_valid(game.modal),"dialogue does not open at a distance")\n\tgame._process(5.0)\n\tcheck(is_instance_valid(game.modal),"arrival opens dialogue")\n\tgame.close_dialog()\n\tgame.interact("exit")\n\tcheck(game.character.zone=="town"',1)
p.write_text(s,encoding='utf-8')
