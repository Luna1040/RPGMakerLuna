from pathlib import Path
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8');s=s.replace('''		b.tooltip_text=E.describe(bag[i]); b.pressed.connect(move_item.bind(stored,i)); grid.add_child(b)''','''		b.tooltip_text=E.describe(bag[i]); b.pressed.connect(move_item.bind(stored,i)); grid.add_child(b)
		var icon: Texture2D=item_icon(bag[i])
		if icon!=null:
			b.text=""
			var picture:=TextureRect.new(); picture.texture=icon; picture.position=Vector2(10,2); picture.size=Vector2(27,27)
			picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; picture.mouse_filter=Control.MOUSE_FILTER_IGNORE; b.add_child(picture)
			var quantity:=Label.new(); quantity.text="×"+str(bag[i].get("qty",1)); quantity.position=Vector2(3,26)
			quantity.add_theme_font_size_override("font_size",10); quantity.mouse_filter=Control.MOUSE_FILTER_IGNORE; b.add_child(quantity)''',1)
s=s.replace('b.pressed.connect(select_seed.bind(id)); seeds.add_child(b)','b.pressed.connect(select_seed.bind(id)); seeds.add_child(b)\n\t\tb.icon=item_icon({"id":id}); b.expand_icon=true; b.add_theme_constant_override("icon_max_width",24)',1)
p.write_text(s,encoding='utf-8')
