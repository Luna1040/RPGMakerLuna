from pathlib import Path
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8');s=s.replace('var resource_texture: Texture2D','var resource_texture: Texture2D\nvar gear_textures: Dictionary={}',1)
s=s.replace('game.button(content,"青灵丹：青灵草×2 → 丹药×1（恢复50气血）",brew.bind(false))','recipe_button(content,"青灵丹：青灵草×2 → 丹药×1（恢复50气血）","weak",brew.bind(false))',1).replace('game.button(content,"凝露丹：青灵草×1、凝露花×2 → 丹药×1（恢复100气血）",brew.bind(true))','recipe_button(content,"凝露丹：青灵草×1、凝露花×2 → 丹药×1（恢复100气血）","strong",brew.bind(true))',1)
s=s.replace('func item_icon(item: Dictionary) -> Texture2D:\n','''func item_icon(item: Dictionary) -> Texture2D:
	if G.valid(item):
		var set_piece: bool=item.get("set_id","")=="xiaoyao"
		var path: String="res://assets/xiaoyao-icons.png" if set_piece else "res://assets/equipment-icons.png"
		if not gear_textures.has(path): gear_textures[path]=game.texture_file(path)
		var source: Texture2D=gear_textures[path]
		var slot_id:=int(item.slot)
		var index: int=[1,3,4,5].find(slot_id) if set_piece else slot_id
		var atlas:=AtlasTexture.new(); atlas.atlas=source
		var size:=Vector2(source.get_width()/4.0,source.get_height()/(1.0 if set_piece else 2.0))
		atlas.region=Rect2(Vector2(index%4,index/4)*size,size)
		return atlas
''',1)
s+='''
func recipe_button(content: Node, title: String, id: String, callback: Callable) -> void:
	var control: Button=game.button(content,title,callback)
	control.icon=item_icon({"id":id}); control.expand_icon=true; control.add_theme_constant_override("icon_max_width",30)
'''
p.write_text(s,encoding='utf-8')
