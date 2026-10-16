from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8')
s=s.replace('const PROFESSIONS := ["剑修", "法修", "体修"]','const PROFESSIONS := ["剑仙", "阴阳", "魅影", "天师"]')
s=s.replace('character.stones','character.gold').replace('"stones": 0','"gold": 0').replace('灵石','金币')
# Preserve old balances before missing fields are filled in enter_character.
s=s.replace('\tfor key in {"xp": 0, "gold": 0, "hp": 100, "victories": 0}:','\tif not character.has("gold"): character.gold=int(character.get("stones",0))\n\tfor key in {"xp": 0, "gold": 0, "hp": 100, "victories": 0}:')
s=s.replace('func migrate() -> void:\n','''func migrate() -> void:
\tif character.has("profession"): character.profession=profession_name(str(character.profession))
\tif not character.has("gold"): character.gold=int(character.get("stones",0))
\tcharacter.erase("stones")
\tif not character.has("equipment"): character.equipment=["","","","","","","",""]
\tif not character.has("inventory"):
\t\tcharacter.inventory=[]
\t\tfor i in range(40): character.inventory.append({})
\tif not character.has("accepted_tasks"): character.accepted_tasks=[]
\tif not character.has("settings"): character.settings={"volume":0.8,"mute":false,"fullscreen":false}
''')
s=s.replace('data.name, data.profession, data.level','data.name, profession_name(str(data.profession)), data.level')
a=s.index('\tvar taskpanel:=panel_at(screen,Vector2(20,665)');b=s.index('\trefresh_map()',a)
s=s[:a]+'''\tvar taskpanel:=panel_at(screen,Vector2(20,650),Vector2(1240,60))
\tvar taskbox:=VBoxContainer.new()
\ttaskpanel.add_child(taskbox)
\tquest_label=label_text(taskbox,"",18)
\tlabel_text(taskbox,"点击NPC或名字靠近对话 · 点击地图漩涡传送 · 菜单快捷键见下方",14)
\tadd_menu_bar()
'''+s[b:]
s=s.replace('func background(path: String) -> void:\n','func background(path: String) -> void:\n\tclose_menu()\n')
s=s.replace('if mode!="map" or is_instance_valid(modal): return','if mode!="map" or is_instance_valid(modal) or is_instance_valid(menu_layer): return')
s=s.replace('if mode=="map" and is_instance_valid(avatar) and not is_instance_valid(modal):','if mode=="map" and is_instance_valid(avatar) and not is_instance_valid(modal) and not is_instance_valid(menu_layer):')
s=s.replace('func show_slots() -> void:\n','func show_slots() -> void:\n\tclose_menu()\n')
s=s.replace('func enter_character(index: int) -> void:\n','func enter_character(index: int) -> void:\n')
s=s.replace('\tplayer_pos=Vector2(character.position[0],character.position[1])','\tapply_settings()\n\tplayer_pos=Vector2(character.position[0],character.position[1])')
s=s.replace('\t\t\tdialog(TOWN_NAMES[index],lines[index]','\t\t\taccept_task("town_%d" % index)\n\t\t\tdialog(TOWN_NAMES[index],lines[index]')
s=s.replace('\t\t\tdialog("林守卫","三处妖患尽除！','\t\t\taccept_task("field_return")\n\t\t\tdialog("林守卫","三处妖患尽除！')
s=s.replace('\t\t\tdialog("传功师姐","气沉丹田','\t\t\taccept_task("sect_lesson")\n\t\t\tdialog("传功师姐","气沉丹田')
s+='''
const MENU_NAMES := ["人物","散修","背包","仙园","任务","技能","系统"]
const MENU_KEYS := [KEY_C,KEY_R,KEY_TAB,KEY_H,KEY_Q,KEY_K,KEY_ESCAPE]
const MENU_HINTS := ["C","R","Tab","H","Q","K","Esc"]
const EQUIPMENT_NAMES := ["武器","头冠","衣服","护腕","腰带","鞋履","戒指","护符"]
var menu_layer: Control
var menu_window: PanelContainer
var active_menu := -1
var task_list: VBoxContainer
var task_category := "可接任务"
var menu_error: Label

func profession_name(value: String) -> String:
\treturn {"剑修":"剑仙","法修":"阴阳","体修":"天师"}.get(value,value)

func add_menu_bar() -> void:
\tvar panel:=panel_at(screen,Vector2(20,720),Vector2(1240,70))
\tpanel.name="MenuBar"
\tvar row:=HBoxContainer.new()
\trow.add_theme_constant_override("separation",10)
\tpanel.add_child(row)
\tfor i in range(MENU_NAMES.size()):
\t\tvar item:=Button.new()
\t\titem.name="Menu%d" % i
\t\titem.custom_minimum_size=Vector2(163,48)
\t\titem.tooltip_text=MENU_NAMES[i]+" ["+MENU_HINTS[i]+"]"
\t\titem.focus_mode=Control.FOCUS_NONE
\t\titem.pressed.connect(toggle_menu.bind(i))
\t\trow.add_child(item)
\t\tif FileAccess.file_exists("res://assets/menu-icons.png"):
\t\t\tvar texture:=texture_file("res://assets/menu-icons.png")
\t\t\tvar atlas:=AtlasTexture.new()
\t\t\tatlas.atlas=texture
\t\t\tatlas.region=Rect2(Vector2(i*texture.get_width()/7.0,0),Vector2(texture.get_width()/7.0,texture.get_height()))
\t\t\tvar icon:=Sprite2D.new()
\t\t\ticon.texture=atlas
\t\t\ticon.position=Vector2(30,24)
\t\t\ticon.scale=Vector2(42,42)/atlas.get_size()
\t\t\titem.add_child(icon)
\t\tvar caption:=Label.new()
\t\tcaption.text=MENU_NAMES[i]+" ["+MENU_HINTS[i]+"]"
\t\tcaption.position=Vector2(58,12)
\t\tcaption.add_theme_font_size_override("font_size",17)
\t\tcaption.mouse_filter=Control.MOUSE_FILTER_IGNORE
\t\titem.add_child(caption)

func _input(event: InputEvent) -> void:
\tif character.is_empty() or mode!="map": return
\tif not event is InputEventKey or not event.pressed or event.echo: return
\tif event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
\tvar code: int=event.keycode if event.keycode!=0 else event.physical_keycode
\tif is_instance_valid(modal):
\t\tif code==KEY_ESCAPE:
\t\t\tclose_dialog()
\t\t\tget_viewport().set_input_as_handled()
\t\treturn
\tif code==KEY_ESCAPE and is_instance_valid(menu_layer):
\t\tclose_menu()
\t\tget_viewport().set_input_as_handled()
\t\treturn
\tvar index:=MENU_KEYS.find(code)
\tif index>=0:
\t\ttoggle_menu(index)
\t\tget_viewport().set_input_as_handled()

func close_menu() -> void:
\tif is_instance_valid(menu_layer):
\t\tmenu_layer.get_parent().remove_child(menu_layer)
\t\tmenu_layer.queue_free()
\tmenu_layer=null
\tmenu_window=null
\tactive_menu=-1

func toggle_menu(index: int) -> void:
\tif mode!="map" or is_instance_valid(modal) or index<0 or index>=MENU_NAMES.size(): return
\tif is_instance_valid(menu_layer) and active_menu==index:
\t\tclose_menu()
\t\treturn
\tclose_menu()
\tactive_menu=index
\tmenu_layer=Control.new()
\tmenu_layer.name="MenuOverlay"
\tmenu_layer.size=Vector2(1280,712)
\tmenu_layer.mouse_filter=Control.MOUSE_FILTER_STOP
\tscreen.add_child(menu_layer)
\tvar dim:=ColorRect.new()
\tdim.color=Color(0,0,0,0.42)
\tdim.size=menu_layer.size
\tmenu_layer.add_child(dim)
\tmenu_window=panel_at(menu_layer,Vector2(255,110),Vector2(770,525))
\tvar content:=VBoxContainer.new()
\tcontent.name="Content"
\tcontent.add_theme_constant_override("separation",14)
\tmenu_window.add_child(content)
\tvar heading:=HBoxContainer.new()
\tcontent.add_child(heading)
\tvar title:=label_text(heading,MENU_NAMES[index]+"  ["+MENU_HINTS[index]+"]",27)
\ttitle.size_flags_horizontal=Control.SIZE_EXPAND_FILL
\tbutton(heading,"关闭 [Esc]",close_menu)
\tmatch index:
\t\t0: build_character_menu(content)
\t\t2: build_inventory_menu(content)
\t\t4: build_task_menu(content)
\t\t6: build_system_menu(content)
\t\t_: label_text(content,"暂无内容",22)

func build_character_menu(content: VBoxContainer) -> void:
\tlabel_text(content,"%s · %s    %s / 等级%d" % [character.name,character.profession,character.realm,character.level],23)
\tlabel_text(content,"气血 %d/%d    经验 %d/100    战斗胜场 %d    金币 %d" % [character.hp,100+int(character.level)*10,character.xp,character.victories,character.gold],18)
\tvar row:=HBoxContainer.new()
\trow.add_theme_constant_override("separation",20)
\tcontent.add_child(row)
\tvar preview:=Control.new()
\tpreview.custom_minimum_size=Vector2(180,280)
\trow.add_child(preview)
\tactor(preview,0,Vector2(90,220),character.name,2.5)
\tvar grid:=GridContainer.new()
\tgrid.name="EquipmentSlots"
\tgrid.columns=4
\tgrid.add_theme_constant_override("h_separation",10)
\tgrid.add_theme_constant_override("v_separation",14)
\trow.add_child(grid)
\tfor i in range(8):
\t\tvar equipment:=Button.new()
\t\tequipment.custom_minimum_size=Vector2(117,90)
\t\tequipment.text=EQUIPMENT_NAMES[i]+"\\n"+("未装备" if str(character.equipment[i]).is_empty() else str(character.equipment[i]))
\t\tequipment.tooltip_text=EQUIPMENT_NAMES[i]+"装备栏"
\t\tgrid.add_child(equipment)

func build_inventory_menu(content: VBoxContainer) -> void:
\tvar grid:=GridContainer.new()
\tgrid.name="InventorySlots"
\tgrid.columns=8
\tgrid.add_theme_constant_override("h_separation",10)
\tgrid.add_theme_constant_override("v_separation",8)
\tcontent.add_child(grid)
\tvar occupied:=0
\tfor i in range(40):
\t\tvar cell:=Button.new()
\t\tcell.custom_minimum_size=Vector2(82,56)
\t\tvar item: Dictionary=character.inventory[i]
\t\tif not item.is_empty():
\t\t\toccupied+=1
\t\t\tcell.text=str(item.get("name","物品"))
\t\telse: cell.text=""
\t\tcell.tooltip_text="背包格 %d · " % (i+1)+("空" if item.is_empty() else str(item.get("name","物品")))
\t\tgrid.add_child(cell)
\tlabel_text(content,"容量 %d/40" % occupied,16)
\tvar assets:=label_text(content,"人物资产 · 金币 %d" % character.gold,22)
\tassets.name="GoldBalance"

func accept_task(id: String) -> void:
\tif not id in character.accepted_tasks:
\t\tcharacter.accepted_tasks.append(id)
\t\tpersist()

func get_task_groups() -> Dictionary:
\tvar result: Dictionary={"可接任务":[],"已接任务":[],"已完成任务":[]}
\tfor i in range(5):
\t\tvar status: String="已完成任务" if i<int(character.quest) else ("已接任务" if "town_%d" % i in character.accepted_tasks else "可接任务")
\t\tif i<=int(character.quest): result[status].append({"title":QUESTS[i],"npc":TOWN_NAMES[i],"zone":"town","index":i})
\tvar stage:=int(character.field_quest)
\tif int(character.quest)>=5:
\t\tresult["已完成任务" if 0 in character.cleared else ("已接任务" if stage>=1 else "可接任务")].append({"title":"山林除妖 · 击败第一堆灰狼","npc":"林守卫","zone":"field","index":0})
\tif 0 in character.cleared:
\t\tresult["已完成任务" if character.cleared.size()==3 else ("已接任务" if stage>=2 else "可接任务")].append({"title":"道长指引 · 平定其余两堆妖狼","npc":"云游道长","zone":"field","index":1})
\tif character.cleared.size()==3:
\t\tresult["已完成任务" if stage==4 else ("已接任务" if "field_return" in character.accepted_tasks else "可接任务")].append({"title":"守卫复命 · 领取历练奖励","npc":"林守卫","zone":"field","index":0})
\tif int(character.level)>=10:
\t\tresult["已完成任务" if int(character.sect_quest)>=1 else "可接任务"].append({"title":"修仙之路 · 拜入青云宗，进入练气期","npc":"接引长老","zone":"sect","index":0})
\tif int(character.sect_quest)>=1:
\t\tresult["已完成任务" if int(character.sect_quest)>=2 else ("已接任务" if "sect_lesson" in character.accepted_tasks else "可接任务")].append({"title":"周天功法 · 向传功师姐请教","npc":"传功师姐","zone":"sect","index":1})
\treturn result

func build_task_menu(content: VBoxContainer) -> void:
\tvar tabs:=HBoxContainer.new()
\ttabs.name="TaskTabs"
\tcontent.add_child(tabs)
\tvar groups:=get_task_groups()
\tfor category in ["可接任务","已接任务","已完成任务"]:
\t\tbutton(tabs,"%s (%d)" % [category,groups[category].size()],show_task_category.bind(category))
\tvar scroll:=ScrollContainer.new()
\tscroll.custom_minimum_size=Vector2(730,360)
\tscroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
\tcontent.add_child(scroll)
\ttask_list=VBoxContainer.new()
\ttask_list.name="TaskList"
\ttask_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
\ttask_list.add_theme_constant_override("separation",12)
\tscroll.add_child(task_list)
\tshow_task_category(task_category)

func show_task_category(category: String) -> void:
\ttask_category=category
\tfor child in task_list.get_children():
\t\ttask_list.remove_child(child)
\t\tchild.queue_free()
\tlabel_text(task_list,category,22)
\tvar entries: Array=get_task_groups()[category]
\tif entries.is_empty(): label_text(task_list,"暂无"+category,18)
\tfor entry in entries:
\t\tlabel_text(task_list,entry.title,19)
\t\tlabel_text(task_list,"%s · %s" % [ZONES[entry.zone].title,entry.npc],16)
\t\tif category!="已完成任务" and entry.zone==character.zone:
\t\t\tbutton(task_list,"寻访"+entry.npc,seek_task_npc.bind(entry))

func seek_task_npc(entry: Dictionary) -> void:
\tclose_menu()
\ttravel(ZONES[entry.zone].positions[entry.index]+NPC_APPROACH,"npc:"+str(entry.index))

func build_system_menu(content: VBoxContainer) -> void:
\tlabel_text(content,"游戏设置",22)
\tlabel_text(content,"主音量",18)
\tvar volume:=HSlider.new()
\tvolume.name="Volume"
\tvolume.min_value=0
\tvolume.max_value=100
\tvolume.value=float(character.settings.volume)*100
\tvolume.value_changed.connect(func(value):
\t\tcharacter.settings.volume=value/100.0
\t\tapply_settings()
\t\tpersist()
\t)
\tcontent.add_child(volume)
\tvar mute:=CheckBox.new()
\tmute.name="Mute"
\tmute.text="静音"
\tmute.button_pressed=bool(character.settings.mute)
\tmute.toggled.connect(func(value):
\t\tcharacter.settings.mute=value
\t\tapply_settings()
\t\tpersist()
\t)
\tcontent.add_child(mute)
\tvar fullscreen:=CheckBox.new()
\tfullscreen.name="Fullscreen"
\tfullscreen.text="全屏显示"
\tfullscreen.button_pressed=bool(character.settings.fullscreen)
\tfullscreen.toggled.connect(func(value):
\t\tcharacter.settings.fullscreen=value
\t\tapply_settings()
\t\tpersist()
\t)
\tcontent.add_child(fullscreen)
\tlabel_text(content,"人物 C · 散修 R · 背包 Tab · 仙园 H · 任务 Q · 技能 K · 系统 Esc",16)
\tvar commands:=HBoxContainer.new()
\tcontent.add_child(commands)
\tbutton(commands,"保存游戏",persist)
\tbutton(commands,"选择其它角色",logout)
\tbutton(commands,"退出游戏",save_and_exit)
\tmenu_error=label_text(content,"",16)

func apply_settings() -> void:
\tAudioServer.set_bus_volume_db(0,linear_to_db(maxf(float(character.settings.volume),0.001)))
\tAudioServer.set_bus_mute(0,bool(character.settings.mute) or float(character.settings.volume)==0)
\tif DisplayServer.get_name()!="headless":
\t\tDisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(character.settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)

func save_and_exit() -> void:
\tcharacter.logged_out_at=store.timestamp()
\tif persist(): get_tree().quit()
\telif is_instance_valid(menu_error): menu_error.text=store.last_error
'''
p.write_text(s,encoding='utf-8')
p=Path('tests/smoke.gd');s=p.read_text(encoding='utf-8-sig').replace('character.stones','character.gold');p.write_text(s,encoding='utf-8')
