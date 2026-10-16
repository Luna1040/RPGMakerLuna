from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8');s=s.replace('万妖窟每日可开启五次新挑战，UTC+8零点重置。','万妖窟每日基础五次挑战，UTC+8零点重置。可花3000灵石增加一次当日挑战；完整通关后可花1000灵石速刷，仍消耗一次挑战。',1);p.write_text(s,encoding='utf-8')
