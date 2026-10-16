from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8')
s=s.replace('const TOWN_POS := [Vector2(270,330),Vector2(560,310),Vector2(860,350),Vector2(400,540),Vector2(830,565)]','const TOWN_POS := [Vector2(315,415),Vector2(520,350),Vector2(995,485),Vector2(400,580),Vector2(705,315)]')
s=s.replace('const FIELD_POS := [Vector2(250,340),Vector2(900,320)]','const FIELD_POS := [Vector2(280,360),Vector2(1005,345)]\nconst NPC_APPROACH := Vector2(0,38)\nconst NPC_DIALOG_RADIUS := 48.0\nconst MAP_ACTOR_SIZE := Vector2(48,72)')
a=s.index('\t\tvar portrait:=TextureRect.new()');b=s.index('\tvar nameplate:=Label.new()',a)
s=s[:a]+'''\t\t# Sprite2D has no texture-driven minimum size: atlas pixels cannot
\t\t# force the 320x400 source cell back onto the map.
\t\tvar portrait:=Sprite2D.new()
\t\tportrait.name="Portrait"
\t\tportrait.texture=atlas
\t\tportrait.scale=MAP_ACTOR_SIZE*scale_value/atlas.get_size()
\t\tportrait.position=Vector2(0,-MAP_ACTOR_SIZE.y*scale_value/2.0)
\t\tholder.add_child(portrait)
'''+s[b:]
s=s.replace('nameplate.position=Vector2(-70,0)','nameplate.position=Vector2(-70,3)\n\tnameplate.mouse_filter=Control.MOUSE_FILTER_IGNORE\n\tnameplate.add_theme_font_size_override("font_size",14)')
s=s.replace('hit.position=locations[i]+Vector2(-40,30)','hit.position=locations[i]+Vector2(-32,24)\n\t\thit.add_theme_font_size_override("font_size",13)')
s=s.replace('hit.size=Vector2(80,30)','hit.size=Vector2(64,25)')
s=s.replace('locations[i]+Vector2(0,85)','locations[i]+NPC_APPROACH')
s=s.replace('func talk(index: int) -> void:\n','''func talk(index: int) -> void:
\tvar locations: Array=TOWN_POS if character.zone=="town" else FIELD_POS
\tif index<0 or index>=locations.size(): return
\tif player_pos.distance_to(locations[index])>NPC_DIALOG_RADIUS:
\t\ttravel(locations[index]+NPC_APPROACH,"npc:"+str(index))
\t\treturn
''')
p.write_text(s,encoding='utf-8')
p=Path('tests/smoke.gd');s=p.read_text(encoding='utf-8-sig')
s=s.replace('game.TOWN_POS[0]+Vector2(0,85)','game.TOWN_POS[0]+game.NPC_APPROACH').replace('game.TOWN_POS[i]+Vector2(0,85)','game.TOWN_POS[i]+game.NPC_APPROACH')
s=s.replace('game.talk(0)\n\tgame.advance_field(1)','game.player_pos=game.FIELD_POS[0]+game.NPC_APPROACH\n\tgame.talk(0)\n\tgame.advance_field(1)')
s=s.replace('game.talk(1)\n\tgame.advance_field(2)','game.player_pos=game.FIELD_POS[1]+game.NPC_APPROACH\n\tgame.talk(1)\n\tgame.advance_field(2)')
s=s.replace('check(game.character.quest==0,"new quest starts at zero")','''check(game.character.quest==0,"new quest starts at zero")
\tfor node in game.map_layer.get_children():
\t\tvar portrait=node.get_node_or_null("Portrait")
\t\tif portrait is Sprite2D:
\t\t\tvar drawn_size=portrait.texture.get_size()*portrait.scale
\t\t\tcheck(drawn_size.is_equal_approx(game.MAP_ACTOR_SIZE),"map portrait fixed at 48x72 pixels")
\tgame.talk(0)
\tcheck(not is_instance_valid(game.modal),"direct distant dialogue redirects to approach")''')
p.write_text(s,encoding='utf-8')
