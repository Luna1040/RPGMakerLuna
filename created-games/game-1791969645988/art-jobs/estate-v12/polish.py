from pathlib import Path
p=Path('dungeon_world.gd');s=p.read_text(encoding='utf-8');s=s.replace('sweep_button.disabled=int(game.character.dungeon.wins)<1','sweep_button.disabled=int(game.character.dungeon.wins)<1\n\t\t\tsweep_button.tooltip_text="需先完整通关一次；花1000灵石并消耗1次今日挑战"');s=s.replace('每天可挑战五次，进入新挑战消耗一次；','每天基础五次，可额外购买；进入新挑战消耗一次；');p.write_text(s,encoding='utf-8')
