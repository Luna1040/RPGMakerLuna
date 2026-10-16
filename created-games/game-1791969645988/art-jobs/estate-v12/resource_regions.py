from pathlib import Path
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8');s=s.replace('resource.region=Rect2(resource_index*256,0,256,256)','resource.region=[Rect2(15,18,210,217),Rect2(230,18,210,217),Rect2(446,18,210,217),Rect2(662,18,210,217),Rect2(1091,18,210,217),Rect2(1306,18,210,217)][resource_index]');p.write_text(s,encoding='utf-8')
