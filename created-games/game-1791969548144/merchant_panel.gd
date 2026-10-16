extends VBoxContainer
var game: Node
var shop=preload("res://merchant_system.gd").new()
var tabs: TabContainer
var info: Label
var confirmation: ConfirmationDialog
var pending_uid:=-1
var pending_kind:=""
func setup(host: Node) -> void:
 game=host
 info=Label.new()
 add_child(info)
 tabs=TabContainer.new()
 tabs.custom_minimum_size=Vector2(790,380)
 add_child(tabs)
 confirmation=ConfirmationDialog.new()
 confirmation.title="确认出售"
 confirmation.ok_button_text="确认出售"
 confirmation.cancel_button_text="保留"
 confirmation.confirmed.connect(func():
  if pending_uid<0: return
  if pending_kind=="pet": shop.sell_pet(game,pending_uid)
  else: shop.sell_item(game,pending_uid)
  pending_uid=-1
  refresh()
 )
 add_child(confirmation)
 refresh()
func list_tab(title: String) -> VBoxContainer:
 var scroll=ScrollContainer.new()
 scroll.name=title
 tabs.add_child(scroll)
 var list=VBoxContainer.new()
 list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 scroll.add_child(list)
 return list
func refresh() -> void:
 var tab:=maxi(0,tabs.current_tab)
 for child in tabs.get_children():
  tabs.remove_child(child)
  child.queue_free()
 info.text="杂货商 · 金币 %d  |  %s" % [game.gold,shop.message]
 var buy=list_tab("购买")
 for id in [1071020,1071220,1020020,1020010]:
  var key: int=id
  var button=Button.new()
  button.text=("战士攻防型蛋" if id==1071020 else ("法师攻防型蛋" if id==1071220 else game.equipment.definitions[id].name))+" · %d金币 · 购买1个" % shop.PRICES[id]
  button.icon=load("res://assets/client_loot/egg1.dds" if id==1071020 else ("res://assets/client_loot/egg2.dds" if id==1071220 else game.equipment.definitions[id].icon))
  button.expand_icon=true
  button.add_theme_constant_override("icon_max_width",36)
  button.custom_minimum_size.y=65
  button.pressed.connect(func(): shop.buy(game,key); refresh())
  buy.add_child(button)
 var items=list_tab("出售物品")
 for item in game.equipment.bag:
  if item==null: continue
  var uid: int=item.uid
  var data: Dictionary=game.equipment.definition(item)
  var button=Button.new()
  var value: int=shop.item_price(game,item)*int(item.count)
  button.text="%s ×%d · 售价%d金币" % [data.name,item.count,value]
  button.icon=load(data.icon)
  button.expand_icon=true
  button.add_theme_constant_override("icon_max_width",32)
  button.custom_minimum_size.y=45
  if data.has("slot"): button.modulate=game.equipment.quality_color(data)
  button.pressed.connect(func():
   pending_uid=uid
   pending_kind="item"
   confirmation.dialog_text="出售 %s ×%d，获得%d金币？出售后物品不会保留。" % [data.name,item.count,value]
   confirmation.popup_centered(Vector2i(500,190))
  )
  items.add_child(button)
 var pets=list_tab("出售幻兽")
 for pet in game.pets:
  var uid: int=pet.id
  var value: int=shop.pet_price(pet)
  var button=Button.new()
  button.text="%s #%d · Lv.%d · %d星 · %d金币%s" % [pet.name,uid,pet.level,pet.star,value,"（需先收回）" if pet.deployed else ""]
  button.icon=load("res://assets/client_pets/%d.dds" % pet.type_id)
  button.expand_icon=true
  button.add_theme_constant_override("icon_max_width",42)
  button.custom_minimum_size.y=55
  button.disabled=pet.deployed
  button.pressed.connect(func():
   pending_uid=uid
   pending_kind="pet"
   confirmation.dialog_text="出售 %s #%d（%d星），获得%d金币？幻兽将永久离开。" % [pet.name,uid,pet.star,value]
   confirmation.popup_centered(Vector2i(500,190))
  )
  pets.add_child(button)
 tabs.current_tab=mini(tab,2)
