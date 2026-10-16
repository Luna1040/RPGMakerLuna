from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8')
s=s.replace('"town_field","position":Vector2(1110,595)','"town_field","position":Vector2(95,535)').replace('"target":"town","spawn":Vector2(1050,595)','"target":"town","spawn":Vector2(155,555)')
s=s.replace('点击东侧云雾漩涡','点击左下桥头云雾漩涡')
s=s.replace('mark.text="?"\n\t\t\tmark.position=Vector2(-60,-3)','mark.text="?"\n\t\t\tmark.name="QuestMarker"\n\t\t\tmark.position=Vector2(-20,-110)\n\t\t\tmark.size=Vector2(40,32)\n\t\t\tmark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER')
a=s.index('\t\t\tactor(map_layer,7,GROUP_POS[i]');b=s.index('\tavatar=actor(',a)
s=s[:a]+'''\t\t\tvar monster:=actor(map_layer,7,GROUP_POS[i],MONSTERS[i]+(" · 已击杀" if cleared else " ×3"))
\t\t\tmonster.name="Monster%d" % i
\t\t\tif cleared:
\t\t\t\tvar shader:=Shader.new()
\t\t\t\tshader.code="shader_type canvas_item; void fragment(){ vec4 c = texture(TEXTURE, UV); float gray = dot(c.rgb, vec3(0.299,0.587,0.114)); COLOR = vec4(vec3(gray * 0.65), c.a); }"
\t\t\t\tvar material:=ShaderMaterial.new()
\t\t\t\tmaterial.shader=shader
\t\t\t\tmonster.get_node("Portrait").material=material
\t\t\tclick_area(monster,Rect2(-85,-54,170,84),travel.bind(GROUP_POS[i]+Vector2(-55,35),"monster:"+str(i)),MONSTERS[i])
'''+s[b:]
s=s.replace('\t\tvar group:=int(action.get_slice(":",1))\n\t\tif int(character.field_quest)', '\t\tvar group:=int(action.get_slice(":",1))\n\t\tif group<0 or group>=MONSTERS.size() or character.zone!="field": return\n\t\tif group in character.cleared:\n\t\t\tdialog("已经击杀",MONSTERS[group]+"已经击杀，无法再次战斗。","知道了",close_dialog)\n\t\t\treturn\n\t\tif int(character.field_quest)')
p.write_text(s,encoding='utf-8')
p=Path('tests/smoke.gd');s=p.read_text(encoding='utf-8-sig').replace('Vector2(1110,595)','Vector2(95,535)')
s=s.replace('check(game.character.zone=="field","portal arrives at field")','''check(game.character.zone=="field","portal arrives at field")
\tfor i in range(3):
\t\tvar monster=game.map_layer.get_node("Monster%d" % i)
\t\tvar hit=monster.get_node("ClickArea")
\t\tcheck(hit.text.is_empty() and not hit.disabled,"monster click area has no attack button")
\t\tcheck(Rect2(hit.position,hit.size).has_point(Vector2(0,-25)),"monster model clickable")
\t\tcheck(Rect2(hit.position,hit.size).has_point(Vector2(0,15)),"monster name clickable")''')
s=s.replace('check(game.player_pos==Vector2(330,555),"map return position")','''check(game.player_pos==Vector2(330,555),"map return position")
\tcheck(game.map_layer.get_node("Monster0/Portrait").material is ShaderMaterial,"cleared monster grayscale material")
\tvar before_gold=int(game.character.gold)
\tgame.map_layer.get_node("Monster0/ClickArea").pressed.emit()
\tfinish_walk(game)
\tcheck(game.mode=="map" and is_instance_valid(game.modal),"cleared monster click gives notice")
\tcheck(game.modal.get_child(0).get_child(0).text=="已经击杀","notice says already killed")
\tcheck(game.character.gold==before_gold,"cleared monster cannot repeat reward")
\tgame.close_dialog()''')
s=s.replace('check(game.character.level==1,"new character level one")','''check(game.character.level==1,"new character level one")
\tvar found_mark:=false
\tfor node in game.map_layer.get_children():
\t\tvar mark=node.get_node_or_null("QuestMarker")
\t\tif mark!=null:
\t\t\tfound_mark=true
\t\t\tcheck(mark.position.y+mark.size.y<=-game.MAP_ACTOR_SIZE.y,"quest marker above head")
\tcheck(found_mark,"current quest NPC has head marker")''')
p.write_text(s,encoding='utf-8')
