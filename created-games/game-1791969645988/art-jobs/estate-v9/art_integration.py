from pathlib import Path
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8-sig').replace('art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED','art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED');s=s.replace('atlas.region=Rect2(stage*512,0,512,512)','atlas.region=[Rect2(0,0,484,512),Rect2(499,0,500,512),Rect2(1014,0,522,512)][stage]');p.write_text(s,encoding='utf-8')
p=Path('tests/estate_layout_v7.gd');s=p.read_text(encoding='utf-8-sig').replace('rect.end.y>712','rect.end.y>800');p.write_text(s,encoding='utf-8')
