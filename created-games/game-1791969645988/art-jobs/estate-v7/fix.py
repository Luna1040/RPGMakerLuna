from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8').replace('金币','灵石');s=s.replace('label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART','label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n\tlabel.size_flags_horizontal=Control.SIZE_EXPAND_FILL',1)
s=s.replace('"??"','"物品"').replace('"\\n?"','"\\n×"')
s=s.replace('button(pages,"???",change_bag_page.bind(-1))','button(pages,"上一页",change_bag_page.bind(-1))').replace('button(pages,"???",change_bag_page.bind(1))','button(pages,"下一页",change_bag_page.bind(1))')
s=s.replace('"? %d / 10 ?"','"第 %d / 10 页"').replace('"?? %d/500 ? ??50? ? ??? %d"','"容量 %d/500 · 每页50格 · 待领取 %d"').replace('"??????"','"领取待领物品"').replace('"???? ? ?? %d"','"人物资产 · 灵石 %d"').replace('"???????????????????"','"点击装备穿戴、丹药服用；材料在仙园使用"')
p.write_text(s,encoding='utf-8')
p=Path('tests/menu_ui.gd');s=p.read_text(encoding='utf-8').replace('金币','灵石').replace('game.character.stones=321','game.character.gold=321',1).replace('not game.character.has("stones")','not game.character.has("gold")');p.write_text(s,encoding='utf-8')
