from pathlib import Path
p=Path('tests/retainer_v8.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('var failures:=0','class FailingStore:\n\textends "res://save_store.gd"\n\tfunc save_slot(_slot: int, _data: Dictionary) -> bool:\n\t\tlast_error="test write failure"\n\t\treturn false\nvar failures:=0',1)
s=s.replace('\tgame.retainer_ui.manage(2,0); game.retainer_ui.manage(1,0)','\tvar original_store=game.store\n\tvar original_state: Dictionary=game.character.retainers.duplicate(true)\n\tgame.store=FailingStore.new()\n\tgame.retainer_ui.manage(2,0)\n\tcheck(game.character.retainers==original_state,"failed save rolls recruitment back")\n\tgame.store=original_store\n\tgame.retainer_ui.manage(2,0); game.retainer_ui.manage(1,0)')
s=s.replace('\tvar uid=game.character.retainers.reserve[0].uid','\tvar uid=game.character.retainers.reserve[0].uid')
p.write_text(s,encoding='utf-8')
