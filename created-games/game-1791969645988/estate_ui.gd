extends RefCounted
const S=preload("res://spell_system.gd")
var manual_texture: Texture2D
const SlotIcon=preload("res://slot_icon.gd")
const B=preload("res://breakthrough_system.gd")
const E=preload("res://estate_system.gd")
const G=preload("res://equipment_system.gd")
var game
var section:=""
var selected_seed:="qing"
var bag_page:=0
var storage_page:=0
var quality:=0
var slot:=0
var notice:=""
var meditating:=false
var clock:=0.0
var rest_clock:=0.0
var plots: Array=[]
var plot_textures: Array=[]
var foundation_texture: Texture2D
var resource_texture: Texture2D
var gear_textures: Dictionary={}
var status: Label
func build(owner_game, content: VBoxContainer) -> void:
	game=owner_game
	game.menu_layer.size=Vector2(1280,800)
	var backdrop:=TextureRect.new()
	backdrop.name="EstateBackdrop"
	var rooms: Dictionary={"药园":"garden","洞府":"cave","仓库":"warehouse","炼丹炉":"alchemy","炼器室":"forge"}
	var scene_path: String="res://assets/estate-%s.png" % rooms[section] if rooms.has(section) else "res://assets/estate-map.png"
	backdrop.texture=game.texture_file(scene_path if FileAccess.file_exists(scene_path) else "res://assets/estate-map.png")
	backdrop.size=Vector2(1280,800)
	backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	game.menu_layer.add_child(backdrop)
	game.menu_layer.move_child(backdrop,1)
	if section=="":
		game.menu_window.hide()
		map_hub()
		return
	game.menu_window.position=Vector2(90,110)
	game.menu_window.custom_minimum_size=Vector2(1100,580)
	game.menu_window.size=Vector2(1100,580)
	var room_style: StyleBoxFlat=game.menu_window.get_theme_stylebox("panel").duplicate()
	room_style.bg_color=Color(0.025,0.07,0.09,0.82)
	room_style.set_border_width_all(2)
	game.menu_window.add_theme_stylebox_override("panel",room_style)
	content.add_theme_constant_override("separation",8)
	var nav:=HBoxContainer.new()
	content.add_child(nav)
	game.button(nav,"仙园总览",navigate.bind(""))
	for title in ["药园","洞府","仓库","炼丹炉","炼器室"]:
		var tab: Button=game.button(nav,title,navigate.bind(title))
		if FileAccess.file_exists("res://assets/estate-icons.png"):
			var icon:=AtlasTexture.new(); icon.atlas=game.texture_file("res://assets/estate-icons.png")
			icon.region=Rect2(["药园","洞府","仓库","炼丹炉","炼器室"].find(title)*256,0,256,256)
			tab.icon=icon; tab.expand_icon=true; tab.add_theme_constant_override("icon_max_width",26)
		if title==section: tab.add_theme_color_override("font_color",Color("ffe3a0"))
	game.label_text(content,notice if not notice.is_empty() else "仙园 · 种药炼丹，静修养气",16)
	match section:
		"药园":
			game.menu_window.position=Vector2(90,60)
			game.menu_window.custom_minimum_size=Vector2(1100,680)
			game.menu_window.size=Vector2(1100,680)
			garden(content)
		"洞府": cave(content)
		"仓库": warehouse(content)
		"炼丹炉": furnace(content)
		"炼器室": forge(content)
		_: hub(content)
func refresh() -> void: game.refresh_gear_panel(3)
func navigate(title: String) -> void:
	section=title; meditating=false; rest_clock=0; notice=""; refresh()
func transaction(operation: Callable, success: String) -> bool:
	var before: Dictionary=game.character.duplicate(true)
	if not operation.call():
		game.character=before; notice="操作未完成：请检查材料、灵石、成熟时间或目标空间"; refresh(); return false
	if not game.persist():
		game.character=before; notice=game.store.last_error; refresh(); return false
	notice=success; refresh(); return true
func hub(content: VBoxContainer) -> void:
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",12); content.add_child(row)
	var atlas_image:=Image.load_from_file("res://assets/estate-icons.png")
	var texture:=ImageTexture.create_from_image(atlas_image)
	var titles:=["药园","洞府","仓库","炼丹炉","炼器室"]
	var hints:=["20块药田 · 10秒成熟","打坐恢复气血与经验","1000格 · 双向转存","药材炼丹 · 丹药疗伤","分解碎片 · 消耗灵石制造"]
	for i in range(5):
		var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(196,230); row.add_child(column)
		var b:=Button.new(); b.custom_minimum_size=Vector2(196,180)
		var icon:=AtlasTexture.new(); icon.atlas=texture; icon.region=Rect2(i*256,0,256,256)
		b.icon=icon; b.expand_icon=true; b.pressed.connect(navigate.bind(titles[i])); column.add_child(b)
		game.button(column,titles[i],navigate.bind(titles[i])); game.label_text(column,hints[i],14)
func garden(content: VBoxContainer) -> void:
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",24); content.add_child(row)
	var grid:=GridContainer.new(); grid.columns=5; row.add_child(grid); plots=[]
	for i in range(20):
		var b=preload("res://garden_plot.gd").new(); b.custom_minimum_size=Vector2(132,108)
		b.receiver=plant.bind(i); b.allowed=func(): return game.character.estate.plots[i].is_empty()
		b.pressed.connect(click_plot.bind(i)); grid.add_child(b); plots.append(b)
		var art:=TextureRect.new()
		art.name="PlotArt"
		art.position=Vector2(3,3)
		art.size=Vector2(126,74)
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
		b.add_child(label)
	var seeds:=VBoxContainer.new(); seeds.custom_minimum_size=Vector2(310,280); row.add_child(seeds)
	game.label_text(seeds,"背包里的种子",21)
	game.label_text(seeds,"拖动种子到空地；也可先选种子再点击土地。成熟后点击采摘。",16)
	for id in E.HERBS.keys():
		var amount:=E.count(game.character.inventory,"seed",id)
		if amount<=0: continue
		var b=preload("res://seed_drag.gd").new(); b.seed_id=id; b.text=E.seed_item(id,amount).name+" ×"+str(amount)
		b.pressed.connect(select_seed.bind(id)); seeds.add_child(b)
		b.icon=item_icon({"id":id}); b.expand_icon=true; b.add_theme_constant_override("icon_max_width",24)
	game.label_text(seeds,"当前选择："+E.seed_item(selected_seed,1).name,16)
	game.button(seeds,"购买青灵草种 ×1 · 2灵石",buy_seed.bind("qing"))
	game.button(seeds,"购买凝露花种 ×1 · 2灵石",buy_seed.bind("ning"))
	update_plots()
func select_seed(id: String) -> void: selected_seed=id; refresh()
func buy_seed(id: String) -> void:
	transaction(func():
		if int(game.character.stones)<2: return false
		if not E.put(game.character.inventory,E.seed_item(id,1)): return false
		game.character.stones-=2; return true,"已购买种子")
func plant(id: String, index: int) -> void:
	transaction(func(): return E.plant(game.character,index,id,int(Time.get_unix_time_from_system())),"已种下，10秒后成熟")
func click_plot(index: int) -> void:
	if game.character.estate.plots[index].is_empty(): plant(selected_seed,index)
	else: transaction(func(): return E.harvest(game.character,index,int(Time.get_unix_time_from_system())),"已采摘，药材进入背包")
func update_plots() -> void:
	for i in range(plots.size()):
		if not is_instance_valid(plots[i]): continue
		var plot: Dictionary=game.character.estate.plots[i]
		var left:=0 if plot.is_empty() else maxi(0,int(plot.ready_at)-int(Time.get_unix_time_from_system()))
		plots[i].text=""
		plots[i].get_node("PlotCaption").text="空地 · 可播种" if plot.is_empty() else (str(E.HERBS.get(plot.id,"灵草"))+(" · 可收割" if left==0 else " · %d秒" % left))
		plots[i].tooltip_text="药田%02d · " % (i+1)+plots[i].get_node("PlotCaption").text
		var stage:=0 if plot.is_empty() else (2 if left==0 else 1)
		if FileAccess.file_exists("res://assets/estate-plots.png"):
			if plot_textures.is_empty():
				var source: Texture2D=game.texture_file("res://assets/estate-plots.png")
				for region in [Rect2(0,0,484,512),Rect2(499,0,500,512),Rect2(1014,0,522,512)]:
					var atlas:=AtlasTexture.new()
					atlas.atlas=source
					atlas.region=region
					plot_textures.append(atlas)
			plots[i].get_node("PlotArt").texture=plot_textures[stage]
		plots[i].modulate=Color(1,0.94,0.72) if stage==2 else Color.WHITE
func cave(content: VBoxContainer) -> void:
	game.label_text(content,"洞府 · 静坐调息",26)
	status=game.label_text(content,"",21); update_status()
	game.label_text(content,"每打坐5秒：恢复最大气血的10%，获得1点经验。离开洞府即停止，不结算离线打坐。",18)
	game.button(content,"停止打坐" if meditating else "开始打坐",toggle_rest)
	game.label_text(content,"筑基突破：20级练气期可尝试；失败降至19级，需重新升满20级。",17)
	game.label_text(content,"筑基丹 %d枚 · 不用丹30%%，使用1枚80%%；每次最多1枚。成功后气血+150、攻击+25、防御+15。" % E.count(game.character.inventory,"breakthrough_pill","foundation"),16)
	var options:=HBoxContainer.new(); content.add_child(options)
	var plain: Button=game.button(options,"直接突破 · 30%",breakthrough.bind(false))
	plain.disabled=not B.can_attempt(game.character)
	var aided: Button=game.button(options,"使用1枚筑基丹突破 · 80%",breakthrough.bind(true))
	aided.disabled=not B.can_attempt(game.character) or E.count(game.character.inventory,"breakthrough_pill","foundation")==0
func toggle_rest() -> void: meditating=not meditating; rest_clock=0; refresh()
func update_status() -> void:
	if is_instance_valid(status): status.text="气血 %d/%d · 等级%d · 经验%d/100 · %s" % [game.character.hp,game.max_hp(),game.character.level,game.character.xp,"打坐中" if meditating else "休息中"]
func tick(delta: float) -> void:
	if game==null or not is_instance_valid(game) or game.active_menu!=3 or not is_instance_valid(game.menu_layer): meditating=false; return
	clock+=delta
	if clock>=0.25:
		clock=0
		if section=="药园": update_plots()
	if section!="洞府" or not meditating: return
	rest_clock+=delta
	if rest_clock>=5:
		rest_clock-=5
		var before: Dictionary=game.character.duplicate(true)
		game.character.hp=mini(game.max_hp(),int(game.character.hp)+maxi(1,int(game.max_hp()*0.1)))
		game.add_experience(1)
		if not game.persist(): game.character=before; meditating=false
		game.refresh_map(); update_status()
func warehouse(content: VBoxContainer) -> void:
	game.label_text(content,"点击物品整叠转存；装备逐件转存。背包500格 / 仓库1000格",17)
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",30); content.add_child(row)
	storage_side(row,false); storage_side(row,true)
func storage_side(row: Node, stored: bool) -> void:
	var col:=VBoxContainer.new(); col.custom_minimum_size=Vector2(500,330); row.add_child(col)
	var page: int=storage_page if stored else bag_page
	var bag: Array=game.character.estate.storage if stored else game.character.inventory
	game.label_text(col,("仓库 → 背包" if stored else "背包 → 仓库")+" · 第%d/%d页" % [page+1,20 if stored else 10],19)
	var grid:=GridContainer.new(); grid.columns=10; col.add_child(grid)
	for i in range(page*50,page*50+50):
		var b:=Button.new(); b.clip_contents=true; b.custom_minimum_size=Vector2(46,42); b.add_theme_font_size_override("font_size",10)
		b.text="·" if bag[i].is_empty() else str(bag[i].get("name","物品")).left(3)+"\n"+str(bag[i].get("qty",1))
		b.tooltip_text=E.describe(bag[i]); b.pressed.connect(move_item.bind(stored,i)); grid.add_child(b)
		var icon: Texture2D=item_icon(bag[i])
		if icon!=null:
			b.text=""
			SlotIcon.add_to(b,icon,Rect2(10,2,27,27))
			var quantity:=Label.new(); quantity.text="×"+str(bag[i].get("qty",1)); quantity.position=Vector2(3,26)
			quantity.add_theme_font_size_override("font_size",10); quantity.mouse_filter=Control.MOUSE_FILTER_IGNORE; b.add_child(quantity)
	var nav:=HBoxContainer.new(); col.add_child(nav)
	game.button(nav,"上一页",storage_turn.bind(stored,-1)); game.button(nav,"下一页",storage_turn.bind(stored,1))
func storage_turn(stored: bool, step: int) -> void:
	if stored: storage_page=clampi(storage_page+step,0,19)
	else: bag_page=clampi(bag_page+step,0,9)
	refresh()
func move_item(stored: bool, index: int) -> void:
	transaction(func(): return E.transfer(game.character,stored,index),"已完成转存")
func furnace(content: VBoxContainer) -> void:
	game.label_text(content,"炼丹炉 · 背包药材自动识别",25)
	game.label_text(content,"青灵草 %d · 凝露花 %d" % [E.count(game.character.inventory,"herb","qing"),E.count(game.character.inventory,"herb","ning")],20)
	recipe_button(content,"青灵丹：青灵草×2 → 丹药×1（恢复50气血）","weak",brew.bind(false))
	recipe_button(content,"凝露丹：青灵草×1、凝露花×2 → 丹药×1（恢复100气血）","strong",brew.bind(true))
	game.label_text(content,"丹药进入背包，点击服用。材料不足或背包满时不扣除材料。",17)
	game.label_text(content,"筑基丹材料：青髓芝 %d/3 · 紫灵花 %d/3 · 玄阳参 %d/3\n三种种子分别由万妖窟第一、二、三层BOSS掉落；种下采收后可炼丹。" % [E.count(game.character.inventory,"herb","jade"),E.count(game.character.inventory,"herb","violet"),E.count(game.character.inventory,"herb","sun")],17)
	var foundation: Button=game.button(content,"炼制筑基丹 · 三种药材各3份 → 1枚",brew_foundation)
	foundation.icon=item_icon({"id":"foundation"}); foundation.expand_icon=true; foundation.add_theme_constant_override("icon_max_width",30)
	game.label_text(content,"筑基丹在洞府突破时使用，不能作为普通回血药服用。",16)
func brew(strong: bool) -> void: transaction(func(): return E.alchemy(game.character,strong),"炼丹成功，丹药已放入背包")
func forge(content: VBoxContainer) -> void:
	var row:=HBoxContainer.new(); content.add_child(row)
	var qualities:=OptionButton.new()
	for title in G.QUALITY_NAMES: qualities.add_item(title)
	qualities.selected=quality; qualities.item_selected.connect(select_quality); row.add_child(qualities)
	var slots:=OptionButton.new()
	for title in G.SLOT_NAMES: slots.add_item(title)
	slots.selected=slot; slots.item_selected.connect(select_slot); row.add_child(slots)
	game.label_text(content,"%s碎片 %d · 制造消耗%d片、%d灵石\n同品质装备分解得%d片；制造含碎片损耗，仅制造散装。" % [G.QUALITY_NAMES[quality],E.count(game.character.inventory,"fragment",str(quality)),E.craft_need(quality),E.craft_cost(quality),E.YIELDS[quality]],17)
	game.button(content,"制造所选装备",make_equipment)
	game.label_text(content,"分解背包装备（身上装备请先卸下）：",18)
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(1000,210); content.add_child(scroll)
	var list:=VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	for i in range(game.character.inventory.size()):
		var item: Dictionary=game.character.inventory[i]
		if not G.valid(item): continue
		var b=game.button(list,"分解 "+str(item.name)+" → %d片%s碎片" % [E.YIELDS[int(item.quality)],G.QUALITY_NAMES[int(item.quality)]],break_equipment.bind(i))
		b.tooltip_text=G.describe(item)
func select_quality(index: int) -> void: quality=index; refresh()
func select_slot(index: int) -> void: slot=index; refresh()
func break_equipment(index: int) -> void: transaction(func(): return E.dismantle(game.character,index),"装备已分解，碎片进入背包")
func make_equipment() -> void: transaction(func(): return E.craft(game.character,quality,slot),"制造成功，散装已放入背包")

func map_hub() -> void:
	var header=game.panel_at(game.menu_layer,Vector2(20,20),Vector2(1240,80))
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
	if item.get("kind","")=="spell_manual" and S.DATA.has(str(item.get("id",""))) and FileAccess.file_exists("res://assets/spell-manuals.png"):
		if manual_texture==null: manual_texture=game.texture_file("res://assets/spell-manuals.png")
		var atlas:=AtlasTexture.new(); atlas.atlas=manual_texture
		atlas.region=Rect2(S.CLASSES.find(S.DATA[item.id]["class"])*256,0,256,256)
		return atlas
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
	var ids: Array=["jade","violet","sun","foundation"]
	var index:=ids.find(str(item.get("id","")))
	if index<0:
		var resource_index:=4 if item.get("kind","")=="fragment" else ["qing","ning","weak","strong","_fragment","stones"].find(str(item.get("id","")))
		if resource_index<0 or not FileAccess.file_exists("res://assets/estate-resources.png"): return null
		if resource_texture==null: resource_texture=game.texture_file("res://assets/estate-resources.png")
		var resource:=AtlasTexture.new(); resource.atlas=resource_texture; resource.region=[Rect2(15,18,210,217),Rect2(230,18,210,217),Rect2(446,18,210,217),Rect2(662,18,210,217),Rect2(1091,18,210,217),Rect2(1306,18,210,217)][resource_index]
		return resource
	if not FileAccess.file_exists("res://assets/foundation-items.png"): return null
	if foundation_texture==null: foundation_texture=game.texture_file("res://assets/foundation-items.png")
	var atlas:=AtlasTexture.new(); atlas.atlas=foundation_texture; atlas.region=Rect2(index*256,0,256,256)
	return atlas

func recipe_button(content: Node, title: String, id: String, callback: Callable) -> void:
	var control: Button=game.button(content,title,callback)
	control.icon=item_icon({"id":id}); control.expand_icon=true; control.add_theme_constant_override("icon_max_width",30)
