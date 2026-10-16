from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8').replace('quick_button.text="快速战斗"','quick_button.text="快速战斗"\n\tquick_button.tooltip_text="按相同规则立即结算剩余回合，奖励不变"');p.write_text(s,encoding='utf-8')
