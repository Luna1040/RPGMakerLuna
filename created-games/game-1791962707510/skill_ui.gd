extends CanvasLayer
const Definitions=preload("res://kungfu_data.gd")
var game: Node
var slots: Array[Button]=[]
var column: VBoxContainer
var buff: VBoxContainer
var buff_icon: TextureRect
var countdown: Label

class SkillButton extends Button:
 var game: Node
 var skill_id := ""
 var slot_index := -1
 func _get_drag_data(_position: Vector2) -> Variant:
  var id: String=game.skill_slots[slot_index] if slot_index>=0 else skill_id
  if id.is_empty() or not id in game.learned_skills:return null
  var preview:=TextureRect.new()
  preview.texture=preload("res://kungfu_data.gd").icon(id)
  preview.custom_minimum_size=Vector2(48,48)
  preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
  if get_viewport().gui_is_dragging():set_drag_preview(preview)
  else:preview.free()
  return {"kind":"jianghu_skill","id":id}
 func _can_drop_data(_position: Vector2, data: Variant) -> bool:
  return slot_index>=0 and data is Dictionary and data.get("kind")=="jianghu_skill" and data.get("id") in game.learned_skills
 func _drop_data(position: Vector2, data: Variant) -> void:
  if _can_drop_data(position,data):game.assign_skill(slot_index,data.id)
 func _gui_input(event: InputEvent) -> void:
  if slot_index>=0 and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
   game.assign_skill(slot_index,"")
   accept_event()

func _ready() -> void:
 layer=29
 column=VBoxContainer.new()
 column.position=Vector2(25,215)
 column.add_theme_constant_override("separation",3)
 add_child(column)
 for i in range(9):
  var button:=SkillButton.new()
  button.game=game
  button.slot_index=i
  button.custom_minimum_size=Vector2(50,48)
  button.focus_mode=Control.FOCUS_NONE
  button.expand_icon=true
  button.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
  button.add_theme_constant_override("icon_max_width",36)
  button.pressed.connect(activate_slot.bind(i))
  column.add_child(button)
  var number:=Label.new()
  number.text=str(i+1)
  number.position=Vector2(3,0)
  number.add_theme_font_size_override("font_size",13)
  number.add_theme_color_override("font_outline_color",Color.BLACK)
  number.add_theme_constant_override("outline_size",4)
  number.mouse_filter=Control.MOUSE_FILTER_IGNORE
  button.add_child(number)
  slots.append(button)
  var stack:=stack_label()
  button.add_child(stack)
 buff=VBoxContainer.new()
 buff.position=Vector2(1190,265)
 buff.custom_minimum_size=Vector2(60,78)
 add_child(buff)
 buff_icon=TextureRect.new()
 buff_icon.custom_minimum_size=Vector2(48,48)
 buff_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 buff_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 buff.add_child(buff_icon)
 countdown=Label.new()
 countdown.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 countdown.add_theme_font_size_override("font_size",18)
 buff.add_child(countdown)

func create_source(id: String) -> Button:
 var button:=SkillButton.new()
 button.game=game
 button.skill_id=id
 button.custom_minimum_size=Vector2(64,64)
 button.icon=Definitions.icon(id)
 button.expand_icon=true
 button.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
 button.add_theme_constant_override("icon_max_width",54)
 button.focus_mode=Control.FOCUS_NONE
 button.tooltip_text=Definitions.DATA[id].name+" · 拖到左侧技能格"
 button.modulate=Color.WHITE if id in game.learned_skills else Color(0.4,0.4,0.4,1)
 if id=="potion" or (game.has_method("item_count") and game.Items.DATA.has(id)):
  var stack:=stack_label()
  stack.position=Vector2(46,23)
  stack.text=str(game.item_count(id)) if game.has_method("item_count") else str(game.potions)
  button.add_child(stack)
 return button

func stack_label() -> Label:
 var label:=Label.new()
 label.name="StackCount"
 label.position=Vector2(30,29)
 label.add_theme_font_size_override("font_size",14)
 label.add_theme_color_override("font_outline_color",Color.BLACK)
 label.add_theme_constant_override("outline_size",4)
 label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 return label

func _process(_dt: float) -> void:
 column.visible=game.active_slot>0 and not game.menu.visible
 buff.visible=column.visible and game.lightness and game.lightness_remaining>0
 if buff.visible:
  buff_icon.texture=Definitions.icon(game.active_lightness)
  buff_icon.tooltip_text=Definitions.DATA[game.active_lightness].name+" · 双倍移速"
  countdown.text="%ds" % ceili(game.lightness_remaining)
 for i in range(9):
  var id: String=game.skill_slots[i]
  slots[i].icon=Definitions.icon(id)
  slots[i].get_node("StackCount").text=str(game.item_count(id)) if game.has_method("item_count") and game.Items.DATA.has(id) else (str(game.potions) if id=="potion" else "")
  slots[i].tooltip_text=(Definitions.DATA[id].name if Definitions.DATA.has(id) else "空技能格")+" · 按 %d / 右键清空" % (i+1)

func activate_slot(index: int) -> bool:
 if game.paused or game.menu.visible or game.dialogue.visible:return false
 return game.use_skill(game.skill_slots[index])

func _input(event: InputEvent) -> void:
 if game.active_slot==0 or game.menu.visible or game.paused or game.dialogue.visible:return
 if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed:
  var index: int=int(event.keycode)-KEY_1
  if event.keycode>=KEY_KP_1 and event.keycode<=KEY_KP_9:index=int(event.keycode)-KEY_KP_1
  if index>=0 and index<9:
   activate_slot(index)
   get_viewport().set_input_as_handled()
