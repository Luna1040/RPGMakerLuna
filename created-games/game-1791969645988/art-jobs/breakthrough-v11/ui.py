from pathlib import Path
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8');s=s.replace('const E=','const B=preload("res://breakthrough_system.gd")\nconst E=',1).replace('var plot_textures: Array=[]','var plot_textures: Array=[]\nvar foundation_texture: Texture2D',1)
s=s.replace('for id in ["qing","ning"]:', 'for id in E.HERBS.keys():',1)
s=s.replace('(("青灵草" if plot.id=="qing" else "凝露花")+','(str(E.HERBS.get(plot.id,"灵草"))+',1)
s=s.replace('\tgame.button(content,"停止打坐" if meditating else "开始打坐",toggle_rest)','''	game.button(content,"停止打坐" if meditating else "开始打坐",toggle_rest)
	game.label_text(content,"筑基突破：20级练气期可尝试；失败降至19级，需重新升满20级。",17)
	game.label_text(content,"筑基丹 %d枚 · 不用丹30%%，使用1枚80%%；每次最多1枚。成功后气血+150、攻击+25、防御+15。" % E.count(game.character.inventory,"breakthrough_pill","foundation"),16)
	var options:=HBoxContainer.new(); content.add_child(options)
	var plain: Button=game.button(options,"直接突破 · 30%",breakthrough.bind(false))
	plain.disabled=not B.can_attempt(game.character)
	var aided: Button=game.button(options,"使用1枚筑基丹突破 · 80%",breakthrough.bind(true))
	aided.disabled=not B.can_attempt(game.character) or E.count(game.character.inventory,"breakthrough_pill","foundation")==0''',1)
s=s.replace('\tgame.label_text(content,"丹药进入背包，点击服用。材料不足或背包满时不扣除材料。",17)','''	game.label_text(content,"丹药进入背包，点击服用。材料不足或背包满时不扣除材料。",17)
	game.label_text(content,"筑基丹材料：青髓芝 %d/3 · 紫灵花 %d/3 · 玄阳参 %d/3\\n三种种子分别由万妖窟第一、二、三层BOSS掉落；种下采收后可炼丹。" % [E.count(game.character.inventory,"herb","jade"),E.count(game.character.inventory,"herb","violet"),E.count(game.character.inventory,"herb","sun")],17)
	var foundation: Button=game.button(content,"炼制筑基丹 · 三种药材各3份 → 1枚",brew_foundation)
	foundation.icon=item_icon({"id":"foundation"}); foundation.expand_icon=true; foundation.add_theme_constant_override("icon_max_width",30)
	game.label_text(content,"筑基丹在洞府突破时使用，不能作为普通回血药服用。",16)''',1)
s+='''
func breakthrough(use_pill: bool) -> void:
	if not B.can_attempt(game.character): return
	var dialog:=ConfirmationDialog.new()
	dialog.title="确认筑基突破"
	dialog.dialog_text="本次成功率%s；失败降至19级、经验归零。%s" % ["80%" if use_pill else "30%","会消耗一枚筑基丹，无论成败。" if use_pill else "不消耗筑基丹。"]
	game.menu_layer.add_child(dialog)
	dialog.confirmed.connect(perform_breakthrough.bind(use_pill))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(500,190))
func perform_breakthrough(use_pill: bool) -> void:
	var before: Dictionary=game.character.duplicate(true)
	var result:=B.attempt(game.character,use_pill)
	if not result in ["success","failure"]: notice="尚未满足突破条件或没有筑基丹"; refresh(); return
	game.character.hp=game.max_hp() if result=="success" else mini(int(game.character.hp),game.max_hp())
	if not game.persist():
		game.character=before; notice=game.store.last_error+"；突破与丹药消耗已回滚"
	else: notice="突破成功！已进入筑基期，随行上限提升至2位，气血+150、攻击+25、防御+15。" if result=="success" else "突破失败，降至19级。再次升到20级后可重试。"
	meditating=false; refresh()
func brew_foundation() -> void:
	transaction(func(): return E.foundation_pill(game.character),"筑基丹炼制成功！可到洞府选择使用1枚进行突破。")
func item_icon(item: Dictionary) -> Texture2D:
	var ids: Array=["jade","violet","sun","foundation"]
	var index:=ids.find(str(item.get("id","")))
	if index<0 or not FileAccess.file_exists("res://assets/foundation-items.png"): return null
	if foundation_texture==null: foundation_texture=game.texture_file("res://assets/foundation-items.png")
	var atlas:=AtlasTexture.new(); atlas.atlas=foundation_texture; atlas.region=Rect2(index*256,0,256,256)
	return atlas
'''
p.write_text(s,encoding='utf-8')
p=Path('main.gd');s=p.read_text(encoding='utf-8');s=s.replace('var new_balance_state:=Progress.normalize(character)','var new_balance_state:=Progress.normalize(character)\n\tif new_balance_state: character.hp=mini(int(character.hp),max_hp())',1)
s=s.replace('\tcharacter.realm="练气期"','\tif not Progress.foundation(character): character.realm="练气期"',1)
s=s.replace('''			cell.text=str(item.get("name","物品"))+"\\n×"+str(item.get("qty",1))
			cell.add_theme_font_size_override("font_size",11)''','''			var material_icon: Texture2D=estate_ui.item_icon(item)
			if material_icon!=null:
				var picture:=TextureRect.new(); picture.texture=material_icon
				picture.position=Vector2(3,10); picture.size=Vector2(24,24)
				picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
				cell.add_child(picture)
				var caption:=Label.new(); caption.text=str(item.get("name","物品"))+"\\n×"+str(item.get("qty",1))
				caption.position=Vector2(28,3); caption.size=Vector2(39,44); caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				caption.add_theme_font_size_override("font_size",10); caption.mouse_filter=Control.MOUSE_FILTER_IGNORE; cell.add_child(caption)
			else: cell.text=str(item.get("name","物品"))+"\\n×"+str(item.get("qty",1))
			cell.add_theme_font_size_override("font_size",11)''',1)
s=s.replace('elif character.inventory[index].get("kind","")=="potion":','elif character.inventory[index].get("kind","")=="breakthrough_pill":\n\t\tgear_notice="筑基丹请到仙园洞府突破时使用，每次最多一枚"\n\t\trefresh_gear_panel(2)\n\telif character.inventory[index].get("kind","")=="potion":',1)
p.write_text(s,encoding='utf-8')
