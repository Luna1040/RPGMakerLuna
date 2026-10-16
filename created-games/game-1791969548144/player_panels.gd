extends CanvasLayer

const TITLES := ["人物","幻兽","背包","任务","技能","系统"]
const KEYS := [KEY_C,KEY_H,KEY_TAB,KEY_Q,KEY_K,KEY_ESCAPE]
const KEY_NAMES := ["C","H","Tab","Q","K","Esc"]
const ICONS := ["character","pet","bag","quest","skill","system"]
const EQUIPMENT := ["武器","头盔","护甲","项链","手镯","腰带","戒指","靴子"]
var game: Node
var opened := -1
var panel: PanelContainer
var shade: ColorRect
var content: VBoxContainer
var equipment_grid: GridContainer
var bag_grid: GridContainer
var task_tabs: TabContainer
var exit_confirm: ConfirmationDialog
var discard_confirm: ConfirmationDialog
var discard_uid:=-1
var menu_buttons: Array[Button] = []

func setup(host: Node) -> void:
 game=host
 layer=80
 for i in range(6):
  var index: int=i
  var button=Button.new()
  button.position=Vector2(392+i*145,723)
  button.size=Vector2(140,50)
  button.text=TITLES[i]+" "+KEY_NAMES[i]
  button.icon=load("res://assets/ui/"+ICONS[i]+".svg")
  button.expand_icon=true
  button.add_theme_constant_override("icon_max_width",30)
  button.add_theme_font_size_override("font_size",17)
  button.pressed.connect(func(): toggle(index))
  add_child(button)
  menu_buttons.append(button)
 shade=ColorRect.new()
 shade.position=Vector2(0,150)
 shade.size=Vector2(1280,568)
 shade.color=Color(0.02,0.04,0.07,0.65)
 add_child(shade)
 panel=PanelContainer.new()
 panel.position=Vector2(215,165)
 panel.size=Vector2(850,535)
 var style=StyleBoxFlat.new()
 style.bg_color=Color("152532")
 style.border_color=Color("bda16b")
 style.set_border_width_all(2)
 style.content_margin_left=20
 style.content_margin_right=20
 style.content_margin_top=14
 style.content_margin_bottom=14
 panel.add_theme_stylebox_override("panel",style)
 add_child(panel)
 content=VBoxContainer.new()
 content.add_theme_constant_override("separation",10)
 panel.add_child(content)
 exit_confirm=ConfirmationDialog.new()
 exit_confirm.title="退出游戏"
 exit_confirm.dialog_text="保存角色进度并退出游戏？"
 exit_confirm.ok_button_text="保存并退出"
 exit_confirm.cancel_button_text="取消"
 exit_confirm.confirmed.connect(func():
  if game.active_slot<0 or game.save_progress(true): get_tree().quit()
 )
 add_child(exit_confirm)
 discard_confirm=ConfirmationDialog.new()
 discard_confirm.title="确认丢弃"
 discard_confirm.ok_button_text="丢弃"
 discard_confirm.cancel_button_text="保留"
 discard_confirm.confirmed.connect(func():
  if discard_uid<0: return
  for i in range(game.equipment.bag.size()):
   var item=game.equipment.bag[i]
   if item!=null and int(item.uid)==discard_uid:
    game.equipment.bag[i]=null
    game.equipment.message="已丢弃物品，背包空位已腾出。"
    game.save_progress()
    break
  discard_uid=-1
  refresh()
 )
 discard_confirm.canceled.connect(func(): discard_uid=-1)
 add_child(discard_confirm)
 close()

func close() -> void:
 opened=-1
 panel.hide()
 shade.hide()
 if exit_confirm!=null: exit_confirm.hide()
 if discard_confirm!=null: discard_confirm.hide()
 for button in menu_buttons: button.release_focus()

func toggle(index: int) -> void:
 if game.state in ["characters","dead","travel"] or game.dialog_npc>=0: return
 if opened==index:
  close()
  return
 game.route.clear()
 game.walking=false
 opened=index
 refresh()
 panel.show()
 shade.show()

func handle_key(event: InputEvent) -> bool:
 if not event is InputEventKey or not event.pressed or event.echo: return false
 if exit_confirm.visible or discard_confirm.visible: return false
 if opened in [6,7] and content.get_child_count()>1:
  if content.get_child(1).confirmation.visible: return false
 if opened==1 and content.get_child_count()>1:
  var collection_panel=content.get_child(1)
  if collection_panel.confirm.visible or collection_panel.discard_popup.visible: return false
 if event.keycode==KEY_F5:
  game.save_progress()
  return true
 var index=KEYS.find(event.keycode)
 if index>=0:
  if event.keycode==KEY_ESCAPE and opened>=0: close()
  else: toggle(index)
  return true
 return opened>=0

func label(value: String, size: int = 20) -> Label:
 var item=Label.new()
 item.text=value
 item.add_theme_font_size_override("font_size",size)
 content.add_child(item)
 return item

func action(value: String, callback: Callable) -> Button:
 var button=Button.new()
 button.text=value
 button.custom_minimum_size=Vector2(0,42)
 button.pressed.connect(callback)
 content.add_child(button)
 return button

func refresh() -> void:
 for child in content.get_children():
  content.remove_child(child)
  child.queue_free()
 equipment_grid=null
 bag_grid=null
 task_tabs=null
 panel.position=Vector2(90,155) if opened==1 else Vector2(215,165)
 panel.size=Vector2(1100,550) if opened==1 else Vector2(850,535)
 var header=HBoxContainer.new()
 content.add_child(header)
 var title=Label.new()
 title.text=TITLES[opened]+" · "+KEY_NAMES[opened] if opened<6 else ("装备锻造" if opened==6 else "杂货商")
 title.add_theme_font_size_override("font_size",25)
 title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 header.add_child(title)
 var dismiss=Button.new()
 dismiss.text="关闭 ×"
 dismiss.pressed.connect(close)
 header.add_child(dismiss)
 match opened:
  0:
   label("%s · %s · Lv.%d" % [game.character_name,game.profession,game.level],24)
   label("生命 %d / 180  |  击杀 %d  |  金币 %d" % [int(game.hp),game.kills,game.gold])
   label("攻击类型："+("物理 · 刀剑" if game.profession=="战士" else "法术 · 法杖"))
   equipment_grid=GridContainer.new()
   equipment_grid.columns=4
   content.add_child(equipment_grid)
   for slot in EQUIPMENT:
    var tile=Button.new()
    var equip_slot: String=slot
    var item=game.equipment.equipped.get(slot,null)
    tile.text=slot+"\n未装备"
    if item!=null:
     var data: Dictionary=game.equipment.definition(item)
     tile.text=slot+"\n%s Lv.%d %s" % [data.name,data.level,game.equipment.quality_name(data)]
     tile.icon=load(data.icon)
     tile.expand_icon=true
     tile.add_theme_constant_override("icon_max_width",35)
     tile.modulate=game.equipment.quality_color(data)
     tile.tooltip_text=game.equipment.tooltip(item)+"\n点击卸下"
    tile.add_theme_font_size_override("font_size",13)
    tile.clip_text=true
    tile.pressed.connect(func():
     game.equipment.unequip(equip_slot)
     game.save_progress()
     refresh()
    )
    tile.custom_minimum_size=Vector2(195,105)
    equipment_grid.add_child(tile)
   label("装备属性即时生效；外观使用当前职业造型。",14)
   var stats: Dictionary=game.equipment.stats()
   label("装备加成 · 物攻 %d–%d  魔攻 %d  物防 %d  魔防 %d" % [stats.physical_min,stats.physical_max,stats.magic,stats.defense,stats.magic_defense],16)
  1:
   var collection_panel=load("res://pet_collection_panel.gd").new()
   content.add_child(collection_panel)
   collection_panel.setup(game,self)
  2:
   label("背包 · 40格 · 左键穿戴 / 右键丢弃 / 悬停属性；E药袋",18)
   bag_grid=GridContainer.new()
   bag_grid.columns=8
   content.add_child(bag_grid)
   for i in range(40):
    var tile=Button.new()
    tile.custom_minimum_size=Vector2(95,58)
    var index: int=i
    var item=game.equipment.bag[i]
    tile.text=""
    tile.tooltip_text="空格 %d" % (i+1)
    tile.add_theme_font_size_override("font_size",12)
    tile.clip_text=true
    if item!=null:
     var data: Dictionary=game.equipment.definition(item)
     tile.text=data.name+("\n×%d" % item.count if data.get("kind","") in ["material","scroll"] else "\nLv.%d %s" % [data.level,game.equipment.quality_name(data)])
     tile.icon=load(data.icon)
     tile.expand_icon=true
     tile.add_theme_constant_override("icon_max_width",24)
     if data.has("slot"): tile.modulate=game.equipment.quality_color(data)
     tile.tooltip_text=game.equipment.tooltip(item)
    tile.pressed.connect(func():
     if game.equipment.bag[index]!=null and game.equipment.definition(game.equipment.bag[index]).get("kind","")=="scroll":
      if game.use_scroll(index): close()
      else: game.equipment.message=game.hint; refresh()
      return
     game.equipment.equip(index,game.profession,game.level)
     game.save_progress()
     refresh()
    )
    tile.gui_input.connect(func(event):
     if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
      request_discard(index)
    )
    bag_grid.add_child(tile)
   label("资产：金币 %d · 药水 %d" % [game.gold,game.potions],20)
   label(game.equipment.message,14)
   label("品质：灰色下品 · 绿色中品 · 蓝色上品 · 红色精品 · 紫色极品",14)
  3:
   task_tabs=TabContainer.new()
   task_tabs.custom_minimum_size=Vector2(790,380)
   content.add_child(task_tabs)
   for category in ["可接任务","已接任务","已完成任务"]:
    var list=VBoxContainer.new()
    list.name=category
    task_tabs.add_child(list)
    var text=Label.new()
    text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    text.custom_minimum_size=Vector2(760,320)
    text.text=task_text(category)
    list.add_child(text)
  4: label("暂无可学习的技能。",22)
  5:
   label("设置",22)
   var volume=HSlider.new()
   volume.min_value=0
   volume.max_value=100
   volume.value=game.master_volume
   volume.custom_minimum_size=Vector2(0,30)
   label("主音量",18)
   content.add_child(volume)
   volume.value_changed.connect(func(value):
    game.master_volume=value
    AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.0001,value/100)))
   )
   var names=CheckButton.new()
   names.text="显示角色头顶信息"
   names.button_pressed=game.show_nameplates
   names.toggled.connect(func(value): game.show_nameplates=value; game.queue_redraw())
   content.add_child(names)
   action("保存角色（F5）",func(): game.save_progress())
   action("选择其它角色",func(): game.open_character_menu(); close())
   action("退出游戏",func(): exit_confirm.popup_centered(Vector2i(460,180)))

  6:
   var forge=load("res://forge_panel.gd").new()
   content.add_child(forge)
   forge.setup(game)

  7:
   var merchant=load("res://merchant_panel.gd").new()
   content.add_child(merchant)
   merchant.setup(game)

 panel.set_deferred("size",Vector2(1100,550) if opened==1 else Vector2(850,535))

func request_discard(index: int) -> void:
 if index<0 or index>=40 or game.equipment.bag[index]==null: return
 var item: Dictionary=game.equipment.bag[index]
 discard_uid=int(item.uid)
 discard_confirm.dialog_text="丢弃 %s ×%d？此操作不可恢复。" % [game.equipment.definition(item).name,item.count]
 discard_confirm.popup_centered(Vector2i(440,170))

func task_text(category: String) -> String:
 var lines: Array[String]=[]
 for i in range(5):
  if category=="已完成任务" and i<game.quest: lines.append("✓ "+game.quest_npcs()[i].name+"的新手指导（已完成）")
  elif category=="可接任务" and i==game.quest:
   lines.append(game.quest_npcs()[i].name+"的新手指导\n前往NPC交谈并选择完成。"+("奖励等级 +%d" % game.quest_npcs()[i].reward if game.quest_npcs()[i].reward>0 else "完成幻兽契约，新手结业。"))
 if category=="已接任务":
  if game.quest<5: lines.append("新手之路：拜访五位导师\n当前进度 %d/5，下一位：%s" % [game.quest,game.quest_npcs()[game.quest].name])
  elif game.defeated[0]<3 or game.defeated[1]<3 or game.defeated[2]<3: lines.append("城外狩猎：每种击败3只\n鹿角兽 %d/3 · 巨杰士 %d/3 · 猎杀兽 %d/3" % [game.defeated[0],game.defeated[1],game.defeated[2]])
 if category=="已完成任务" and game.quest==5:
  lines.append("✓ 新手之路（新手指导已结业）")
  if game.defeated[0]>=3 and game.defeated[1]>=3 and game.defeated[2]>=3: lines.append("✓ 城外狩猎")
 return "\n\n".join(lines) if not lines.is_empty() else "暂无"+category+"。"
