from pathlib import Path
p=Path('created-games/velvet-mahogany/multiplayer.gd')
s=p.read_text(encoding='utf-8-sig')
s=s.replace('var last_actor: int=-1','var last_actor: int=-1\nvar npc_delay:=0.8')
s=s.replace('create_timer(0.8)','create_timer(npc_delay)')
s=s.replace('label("●" if turn else "◉",pos+Vector2(12,13),Vector2(32,30),26,Color("dfb971") if index==1 else Color("76b4b1"))','''var portrait:=TextureRect.new()
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	var atlas:=AtlasTexture.new()
	atlas.atlas=preload("res://assets/npc-portraits.png")
	var half: float=atlas.atlas.get_width()/2.0
	atlas.region=Rect2((index-1)*half,0,half,atlas.atlas.get_height())
	portrait.texture=atlas
	portrait.position=pos+Vector2(8,10); portrait.size=Vector2(56,56)
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(portrait)''')
s=s.replace('Vector2(50,10),Vector2(170,25)','Vector2(74,10),Vector2(146,25)')
s=s.replace('Vector2(50,37),Vector2(170,23)','Vector2(74,37),Vector2(146,23)')
p.write_text(s,encoding='utf-8')
