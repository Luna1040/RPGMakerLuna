from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('extends Node2D','extends Node2D\nconst SlotIcon=preload("res://slot_icon.gd")',1)
s=s.replace('''				var picture:=TextureRect.new(); picture.texture=material_icon
				picture.position=Vector2(3,10); picture.size=Vector2(24,24)''','''				var picture:=SlotIcon.add_to(cell,material_icon,Rect2(3,10,24,24))''',1)
s=s.replace('''				picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
				cell.add_child(picture)
''','',1)
s=s.replace('''		var crystal:=TextureRect.new(); crystal.texture=currency_icon; crystal.position=Vector2(340,0); crystal.size=Vector2(30,30)
		crystal.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; crystal.mouse_filter=Control.MOUSE_FILTER_IGNORE; assets.add_child(crystal)''','''		SlotIcon.add_to(assets,currency_icon,Rect2(340,0,24,24))''',1)
s=s.replace('func decorate_gear_cell(cell: Button, item: Dictionary, slot_id: int, equipped: bool) -> void:\n','func decorate_gear_cell(cell: Button, item: Dictionary, slot_id: int, equipped: bool) -> void:\n\tcell.clip_contents=true\n',1)
s=s.replace('''		var icon:=Sprite2D.new()
		icon.texture=atlas
		icon.scale=Vector2(30,30)/atlas.get_size()
		icon.position=Vector2(21,27)
		cell.add_child(icon)''','''		SlotIcon.add_to(cell,atlas,Rect2(6,12,30,30))''',1)
p.write_text(s,encoding='utf-8')
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('extends RefCounted','extends RefCounted\nconst SlotIcon=preload("res://slot_icon.gd")',1)
s=s.replace('var b:=Button.new(); b.custom_minimum_size=Vector2(46,42);','var b:=Button.new(); b.clip_contents=true; b.custom_minimum_size=Vector2(46,42);',1)
s=s.replace('''			var picture:=TextureRect.new(); picture.texture=icon; picture.position=Vector2(10,2); picture.size=Vector2(27,27)
			picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; picture.mouse_filter=Control.MOUSE_FILTER_IGNORE; b.add_child(picture)''','''			SlotIcon.add_to(b,icon,Rect2(10,2,27,27))''',1)
p.write_text(s,encoding='utf-8')
