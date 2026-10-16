extends CanvasLayer

var game: Node
var box: VBoxContainer
var name_input: LineEdit
var class_input: OptionButton
var notice: Label
var confirm: ConfirmationDialog
var pending_delete := -1

func setup(host: Node) -> void:
 game=host
 layer=90
 var shade=ColorRect.new()
 shade.color=Color(0.02,0.04,0.07,0.98)
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(shade)
 var panel=PanelContainer.new()
 panel.position=Vector2(65,95)
 panel.size=Vector2(1150,680)
 add_child(panel)
 box=VBoxContainer.new()
 box.add_theme_constant_override("separation",8)
 panel.add_child(box)
 confirm=ConfirmationDialog.new()
 confirm.title="删除角色存档"
 confirm.ok_button_text="确认删除"
 confirm.cancel_button_text="取消"
 confirm.confirmed.connect(func():
  if game.save_store.delete_character(pending_delete,true):
   if game.active_slot==pending_delete: game.active_slot=-1
   pending_delete=-1
   refresh()
  else: notice.text="删除失败："+game.save_store.error
 )
 confirm.canceled.connect(func(): pending_delete=-1)
 add_child(confirm)
 refresh()

func refresh() -> void:
 for child in box.get_children():
  box.remove_child(child)
  child.queue_free()
 var heading=Label.new()
 heading.text="卡诺萨城 · 角色存档（最多六个）"
 heading.add_theme_font_size_override("font_size",28)
 box.add_child(heading)
 var form=HBoxContainer.new()
 box.add_child(form)
 name_input=LineEdit.new()
 name_input.placeholder_text="角色名（1—12字，支持中文）"
 name_input.max_length=12
 name_input.custom_minimum_size=Vector2(440,38)
 form.add_child(name_input)
 class_input=OptionButton.new()
 class_input.add_item("战士 · 刀剑 / 物理")
 class_input.add_item("法师 · 法杖 / 法术")
 form.add_child(class_input)
 notice=Label.new()
 notice.text="时间均为 UTC+8。填写名字和职业，再点击空槽“新建”。返回选角或退出时记录下线时间。"
 notice.add_theme_font_size_override("font_size",16)
 box.add_child(notice)
 for i in range(6):
  var slot: int=i
  var row=HBoxContainer.new()
  row.custom_minimum_size=Vector2(1120,75)
  box.add_child(row)
  var label=Label.new()
  label.custom_minimum_size=Vector2(885,65)
  label.add_theme_font_size_override("font_size",16)
  var data=game.save_store.slots[i]
  label.text="%d · 空存档位" % (i+1) if data==null else "%d · %s  |  %s  |  Lv.%d\n创建：%s    下线：%s%s" % [i+1,data.name,data["class"],data.level,data.created_at,data.offline_at if not data.offline_at.is_empty() else "尚未下线","（估算）" if data.get("offline_estimated",false) else ""]
  row.add_child(label)
  var enter=Button.new()
  enter.text="新建" if data==null else "进入"
  enter.custom_minimum_size=Vector2(95,44)
  enter.disabled=not game.save_store.error.is_empty()
  enter.pressed.connect(func():
   if game.save_store.slots[slot]==null:
    if not game.create_character(slot,name_input.text,"战士" if class_input.selected==0 else "法师"):
     notice.text="新建失败：检查角色名、存档位或写入权限。"+game.save_store.error
   else: game.load_character(slot)
  )
  row.add_child(enter)
  var remove=Button.new()
  remove.text="删除"
  remove.disabled=data==null or not game.save_store.error.is_empty()
  remove.custom_minimum_size=Vector2(95,44)
  remove.pressed.connect(func():
   pending_delete=slot
   confirm.dialog_text="确定永久删除“%s”的角色存档吗？\n角色、等级及任务进度将一并删除。" % game.save_store.slots[slot].name
   confirm.popup_centered(Vector2i(520,190))
  )
  row.add_child(remove)
 if not game.save_store.error.is_empty(): notice.text=game.save_store.error
