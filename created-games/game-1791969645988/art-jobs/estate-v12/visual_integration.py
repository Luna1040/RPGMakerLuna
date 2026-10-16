from pathlib import Path
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8');s=s.replace('var foundation_texture: Texture2D','var foundation_texture: Texture2D\nvar resource_texture: Texture2D',1)
s=s.replace('backdrop.texture=game.texture_file("res://assets/estate-map.png") if FileAccess.file_exists("res://assets/estate-map.png") else game.texture_file("res://assets/sect.png")','''var rooms: Dictionary={"药园":"garden","洞府":"cave","仓库":"warehouse","炼丹炉":"alchemy","炼器室":"forge"}
	var scene_path: String="res://assets/estate-%s.png" % rooms[section] if rooms.has(section) else "res://assets/estate-map.png"
	backdrop.texture=game.texture_file(scene_path if FileAccess.file_exists(scene_path) else "res://assets/estate-map.png")''',1)
s=s.replace('content.add_theme_constant_override("separation",8)','''var room_style: StyleBoxFlat=game.menu_window.get_theme_stylebox("panel").duplicate()
	room_style.bg_color=Color(0.025,0.07,0.09,0.82)
	room_style.set_border_width_all(2)
	game.menu_window.add_theme_stylebox_override("panel",room_style)
	content.add_theme_constant_override("separation",8)''',1)
s=s.replace('for title in ["药园","洞府","仓库","炼丹炉","炼器室"]: game.button(nav,title,navigate.bind(title))','''for title in ["药园","洞府","仓库","炼丹炉","炼器室"]:
		var tab: Button=game.button(nav,title,navigate.bind(title))
		if FileAccess.file_exists("res://assets/estate-icons.png"):
			var icon:=AtlasTexture.new(); icon.atlas=game.texture_file("res://assets/estate-icons.png")
			icon.region=Rect2(["药园","洞府","仓库","炼丹炉","炼器室"].find(title)*256,0,256,256)
			tab.icon=icon; tab.expand_icon=true; tab.add_theme_constant_override("icon_max_width",26)
		if title==section: tab.add_theme_color_override("font_color",Color("ffe3a0"))''',1)
s=s.replace('if index<0 or not FileAccess.file_exists("res://assets/foundation-items.png"): return null','''if index<0:
		var resource_index:=4 if item.get("kind","")=="fragment" else ["qing","ning","weak","strong","_fragment","stones"].find(str(item.get("id","")))
		if resource_index<0 or not FileAccess.file_exists("res://assets/estate-resources.png"): return null
		if resource_texture==null: resource_texture=game.texture_file("res://assets/estate-resources.png")
		var resource:=AtlasTexture.new(); resource.atlas=resource_texture; resource.region=Rect2(resource_index*256,0,256,256)
		return resource
	if not FileAccess.file_exists("res://assets/foundation-items.png"): return null''',1)
p.write_text(s,encoding='utf-8')
p=Path('main.gd');s=p.read_text(encoding='utf-8');s=s.replace('picture.position=Vector2(3,10); picture.size=Vector2(24,24)','picture.position=Vector2(3,10); picture.size=Vector2(24,24)\n\t\t\t\tif item.get("kind","")=="fragment": picture.modulate=Color(Gear.QUALITY_COLORS[int(item.get("quality",0))])',1)
s=s.replace('assets.name="GoldBalance"','''assets.name="GoldBalance"
	var currency_icon: Texture2D=estate_ui.item_icon({"id":"stones"})
	if currency_icon!=null:
		var crystal:=TextureRect.new(); crystal.texture=currency_icon; crystal.position=Vector2(340,0); crystal.size=Vector2(30,30)
		crystal.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; crystal.mouse_filter=Control.MOUSE_FILTER_IGNORE; assets.add_child(crystal)''',1)
p.write_text(s,encoding='utf-8')
