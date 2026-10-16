from pathlib import Path
p=Path('equipment_system.gd');s=p.read_text(encoding='utf-8').replace('item.has_all(["uid","slot","quality","stats"])','item.has_all(["uid","name","level","slot","quality","stats"]) and item.stats is Dictionary');p.write_text(s,encoding='utf-8')
p=Path('tests/equipment_v6.gd');s=p.read_text(encoding='utf-8-sig').replace('var failures:=0','''class FailingStore:
\textends "res://save_store.gd"
\tfunc save_slot(_slot: int, _data: Dictionary) -> bool:
\t\tlast_error="测试写入失败"
\t\treturn false
var failures:=0''')
s=s.replace('\tgame.close_menu()\n\tgame.character.zone="field"','''\tvar real_store=game.store
\tvar before_failure=game.character.duplicate(true)
\tgame.store=FailingStore.new()
\tcheck(not game.equip_from_bag(4),"failed save rejects equip")
\tcheck(game.character.inventory==before_failure.inventory and game.character.equipment==before_failure.equipment,"failed equip rolls back without losing items")
\tgame.store=real_store
\tgame.close_menu()
\tgame.character.zone="field"''')
p.write_text(s,encoding='utf-8')
