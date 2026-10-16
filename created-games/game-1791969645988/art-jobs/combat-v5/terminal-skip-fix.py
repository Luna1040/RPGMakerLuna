from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8').replace('if player_hit_done or enemy_hp<=0: return','if player_hit_done or enemy_hp<=0 or combat_hp<=0: return')
s=s.replace('func battle_turn() -> void:\n\tif mode!="battle": return\n\tbegin_round()','func battle_turn() -> void:\n\tif mode!="battle": return\n\tif enemy_hp<=0 or combat_hp<=0:\n\t\tsettle_battle()\n\t\treturn\n\tbegin_round()')
p.write_text(s,encoding='utf-8')
p=Path('tests/battle_v5.gd');s=p.read_text(encoding='utf-8-sig').replace('\tgame.store.delete_slot(0)','''\tfixture(game)
\tgame.character.hp=1
\tgame.start_battle(2)
\tgame.advance_battle(2.3)
\tcheck(game.phase==6 and game.combat_hp==0,"defeat awaits final damage fade")
\tvar final_enemy_hp=game.enemy_hp
\tvar final_round=game.round_number
\tgame.quick_battle()
\tcheck(game.enemy_hp==final_enemy_hp and game.round_number==final_round,"skip after defeat cannot grant dead player another attack")
\tgame.store.delete_slot(0)''')
p.write_text(s,encoding='utf-8')
