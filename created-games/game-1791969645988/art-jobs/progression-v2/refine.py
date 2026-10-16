from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8')
s=s.replace('const SECT_POS := [Vector2(680,380),Vector2(930,465)]','const SECT_POS := [Vector2(570,535),Vector2(780,590)]')
s=s.replace('"field_sect","position":Vector2(1100,350)','"field_sect","position":Vector2(1130,595)').replace('"spawn":Vector2(1040,350)','"spawn":Vector2(1070,595)')
s=s.replace('portrait.scale=MAP_ACTOR_SIZE*scale_value/source.get_size()\n\t\tportrait.position=Vector2(0,-MAP_ACTOR_SIZE.y*scale_value/2.0)','var display_size:=Vector2(76,50) if index==7 else MAP_ACTOR_SIZE\n\t\tportrait.scale=display_size*scale_value/source.get_size()\n\t\tportrait.position=Vector2(0,-display_size.y*scale_value/2.0)')
p.write_text(s,encoding='utf-8')
p=Path('tests/smoke.gd');s=p.read_text(encoding='utf-8-sig').replace('Vector2(1100,350)','Vector2(1130,595)')
s=s.replace('check(count==6,"five NPC models plus player")','''check(count==6,"five NPC models plus player")
\tvar clickable_npcs:=0
\tfor node in game.map_layer.get_children():
\t\tvar hit=node.get_node_or_null("ClickArea")
\t\tif hit is Button and node.get_node_or_null("Portrait")!=null:
\t\t\tclickable_npcs+=1
\t\t\tcheck(hit.text.is_empty(),"no visible dialogue button text")
\t\t\tcheck(Rect2(hit.position,hit.size).has_point(Vector2(0,-35)),"model clickable")
\t\t\tcheck(Rect2(hit.position,hit.size).has_point(Vector2(0,14)),"name clickable")
\tcheck(clickable_npcs==5,"all five NPCs clickable")''')
p.write_text(s,encoding='utf-8')
