from pathlib import Path
p=Path('dungeon_world.gd');s=p.read_text(encoding='utf-8').replace('\treturn "万妖窟 · 第%d/3层', '\tif bool(c.dungeon.run.get("completed",false)): return "万妖窟 · 三层已通关！点击东南漩涡返回镇妖谷"\n\tif c.dungeon.run.cleared.size()==5: return "万妖窟 · 本层已平定，点击东南漩涡前往下一层"\n\treturn "万妖窟 · 第%d/3层',1);p.write_text(s,encoding='utf-8')
