extends VBoxContainer
var game: Node
var selector: OptionButton
var detail: RichTextLabel
var status: Label
var confirmation: ConfirmationDialog
var uids: Array=[]
var pending_uid:=-1
var pending_mode:=""
var stone_counts: Dictionary={}
func setup(host: Node) -> void:
 game=host
 var heading=Label.new()
 heading.text="锻造工会 · 装备锻造"
 heading.add_theme_font_size_override("font_size",25)
 add_child(heading)
 var instructions=Label.new()
 instructions.text="幻魔晶石提升至同系列下一等级；灵魂晶石提升一档品质。\n本作每次消耗1枚，100%成功；保留装备品质或等级，不损毁装备。"
 add_child(instructions)
 var stones=HBoxContainer.new()
 add_child(stones)
 for id in [1037170,1037160]:
  var icon=TextureRect.new()
  icon.texture=load(game.equipment.definitions[id].icon)
  icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
  icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
  icon.custom_minimum_size=Vector2(36,36)
  stones.add_child(icon)
  var amount=Label.new()
  amount.custom_minimum_size.x=290
  stones.add_child(amount)
  stone_counts[id]=amount
 selector=OptionButton.new()
 add_child(selector)
 detail=RichTextLabel.new()
 detail.custom_minimum_size=Vector2(770,165)
 detail.bbcode_enabled=false
 add_child(detail)
 var row=HBoxContainer.new()
 add_child(row)
 for mode in ["level","quality"]:
  var action: String=mode
  var button=Button.new()
  button.text="幻魔 · 提升等级" if mode=="level" else "灵魂 · 提升品质"
  button.custom_minimum_size=Vector2(270,45)
  row.add_child(button)
  button.pressed.connect(func(): request_forge(action))
 status=Label.new()
 status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 status.custom_minimum_size=Vector2(770,42)
 add_child(status)
 confirmation=ConfirmationDialog.new()
 confirmation.title="确认锻造"
 confirmation.ok_button_text="消耗晶石并锻造"
 confirmation.cancel_button_text="取消"
 add_child(confirmation)
 confirmation.canceled.connect(func(): pending_uid=-1)
 confirmation.confirmed.connect(func():
  if pending_uid<0: return
  var chosen_uid:=pending_uid
  pending_uid=-1
  game.equipment.forge(chosen_uid,pending_mode,game.level)
  status.text=game.equipment.message
  game.save_progress()
  rebuild()
 )
 selector.item_selected.connect(func(_index): update_detail())
 rebuild()
func rebuild() -> void:
 var chosen:=pending_uid
 for id in stone_counts: stone_counts[id].text=game.equipment.definitions[id].name+" ×"+str(game.equipment.count_material(id))
 selector.clear()
 uids.clear()
 for slot in game.equipment.SLOTS:
  if game.equipment.equipped.has(slot): add_choice(game.equipment.equipped[slot],"已穿戴 · ")
 for item in game.equipment.bag:
  if item!=null and game.equipment.definition(item).has("slot"): add_choice(item,"背包 · ")
 if uids.is_empty(): selector.add_item("没有可锻造的装备，请先去野外收集。")
 elif chosen in uids: selector.select(uids.find(chosen))
 update_detail()
func add_choice(item: Dictionary, prefix: String) -> void:
 var data: Dictionary=game.equipment.definition(item)
 selector.add_icon_item(load(data.icon),prefix+"%s Lv.%d %s" % [data.name,data.level,game.equipment.quality_name(data)])
 selector.add_theme_constant_override("icon_max_width",32)
 uids.append(int(item.uid))
func update_detail() -> void:
 if uids.is_empty():
  detail.text="战士和法师35级以下装备可由野怪掉落。"
  return
 var item: Dictionary=game.equipment.find_instance(uids[selector.selected])
 selector.add_theme_color_override("font_color",game.equipment.quality_color(game.equipment.definition(item)))
 detail.text=game.equipment.tooltip(item)+"\n\n持有幻魔 %d枚 · 灵魂 %d枚\n品质越高，装备的基础属性越强。" % [game.equipment.count_material(1037170),game.equipment.count_material(1037160)]
func request_forge(mode: String) -> void:
 if uids.is_empty(): return
 pending_uid=uids[selector.selected]
 pending_mode=mode
 var item: Dictionary=game.equipment.find_instance(pending_uid)
 var target: Dictionary=game.equipment.target(item,mode)
 if target.is_empty():
  status.text="已达当前装备库上限，没有35级以下的后续装备。"
  return
 confirmation.dialog_text="消耗1枚%s（本作100%%成功）\n升级为：%s · Lv.%d · %s\n仅改变%s，保留其他锻造方向。" % ["幻魔晶石" if mode=="level" else "灵魂晶石",target.name,target.level,game.equipment.quality_name(target),"装备等级" if mode=="level" else "装备品质"]
 confirmation.popup_centered(Vector2i(500,220))
