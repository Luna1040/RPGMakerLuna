from pathlib import Path
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('\tgame=owner_game','''	game=owner_game
	game.menu_layer.size=Vector2(1280,800)
	var backdrop:=TextureRect.new()
	backdrop.name="EstateBackdrop"
	backdrop.texture=game.texture_file("res://assets/estate-map.png") if FileAccess.file_exists("res://assets/estate-map.png") else game.texture_file("res://assets/sect.png")
	backdrop.size=Vector2(1280,800)
	backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	game.menu_layer.add_child(backdrop)
	game.menu_layer.move_child(backdrop,1)
	if section=="":
		game.menu_window.hide()
		map_hub()
		return''',1)
s=s.replace('\t\t"药园": garden(content)','\t\t"药园":\n\t\t\tgame.menu_window.position=Vector2(90,60)\n\t\t\tgame.menu_window.custom_minimum_size=Vector2(1100,680)\n\t\t\tgame.menu_window.size=Vector2(1100,680)\n\t\t\tgarden(content)',1)
s=s.replace('Vector2(132,70)','Vector2(132,108)')
s=s.replace('\t\tgrid.add_child', '\t\tgrid.add_child')
s=s.replace('\t\tb.pressed.connect(click_plot.bind(i)); grid.add_child(b); plots.append(b)','''		b.pressed.connect(click_plot.bind(i)); grid.add_child(b); plots.append(b)
		var art:=TextureRect.new()
		art.name="PlotArt"
		art.position=Vector2(3,3)
		art.size=Vector2(126,74)
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
		b.alignment=HORIZONTAL_ALIGNMENT_CENTER
		var label:=Label.new()
		label.name="PlotCaption"
		label.position=Vector2(2,78)
		label.size=Vector2(128,28)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",12)
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		b.add_child(label)''',1)
a=s.index('\t\tplots[i].text=');b=s.index('func cave(',a)
s=s[:a]+'''		plots[i].text=""
		plots[i].get_node("PlotCaption").text="空地 · 可播种" if plot.is_empty() else (("青灵草" if plot.id=="qing" else "凝露花")+(" · 可收割" if left==0 else " · %d秒" % left))
		plots[i].tooltip_text="药田%02d · " % (i+1)+plots[i].get_node("PlotCaption").text
		var stage:=0 if plot.is_empty() else (2 if left==0 else 1)
		if FileAccess.file_exists("res://assets/estate-plots.png"):
			var atlas:=AtlasTexture.new()
			atlas.atlas=game.texture_file("res://assets/estate-plots.png")
			atlas.region=Rect2(stage*512,0,512,512)
			plots[i].get_node("PlotArt").texture=atlas
		plots[i].modulate=Color(1,0.94,0.72) if stage==2 else Color.WHITE
'''+s[b:]
s+='''
func map_hub() -> void:
	var header:=game.panel_at(game.menu_layer,Vector2(20,20),Vector2(1240,80))
	var row:=HBoxContainer.new()
	header.add_child(row)
	game.label_text(row,"仙园 · 点击建筑进入功能室",27)
	game.button(row,"离开仙园 [Esc]",game.close_menu)
	var names:=["药园","洞府","仓库","炼丹炉","炼器室"]
	var areas:=[Rect2(70,440,360,240),Rect2(65,160,300,230),Rect2(465,150,310,240),Rect2(875,150,330,240),Rect2(850,440,360,230)]
	for i in range(5):
		var hit: Button=game.click_area(game.menu_layer,areas[i],navigate.bind(names[i]),names[i])
		hit.tooltip_text="进入"+names[i]
		var label:=Button.new()
		label.text=names[i]+" · 点击进入"
		label.position=Vector2(areas[i].get_center().x-100,areas[i].end.y-15)
		label.size=Vector2(200,42)
		label.pressed.connect(navigate.bind(names[i]))
		game.menu_layer.add_child(label)
'''
p.write_text(s,encoding='utf-8')
