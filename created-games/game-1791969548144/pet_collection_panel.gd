extends HBoxContainer
var game: Node
var owner_ui: Node
var page:=0
var selected_egg:=-1
var selected_main:=-1
var secondary_ids: Array=[]
var countdowns: Array=[]
var status: Label
var confirm: ConfirmationDialog
var pending_main:=-1
var pending_secondary:=-1
var clock:=0.0
var showcase: Control
var fusion_busy:=false
var fusion_done:=false
var candidate_list: VBoxContainer
var star_warning: ConfirmationDialog
var warning_candidate:=-1
var warned_secondary:=-1
var discard_popup: ConfirmationDialog
var discard_id:=-1

func setup(host: Node, ui: Node) -> void:
 game=host
 owner_ui=ui
 add_theme_constant_override("separation",18)
 custom_minimum_size=Vector2(1060,440)
 confirm=ConfirmationDialog.new()
 confirm.title="确认幻化"
 confirm.ok_button_text="消耗副幻兽并幻化"
 confirm.cancel_button_text="取消"
 confirm.dialog_hide_on_ok=false
 confirm.confirmed.connect(confirm_fusion)
 add_child(confirm)
 var body=HBoxContainer.new()
 body.add_theme_constant_override("separation",12)
 confirm.add_child(body)
 showcase=load("res://fusion_showcase.gd").new()
 body.add_child(showcase)
 var choices=VBoxContainer.new()
 choices.custom_minimum_size=Vector2(250,390)
 body.add_child(choices)
 text(choices,"选择副幻兽",20)
 text(choices,"休息中幻兽 · 支持跨类型幻化",12)
 var scroll=ScrollContainer.new()
 scroll.custom_minimum_size=Vector2(250,350)
 scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
 choices.add_child(scroll)
 candidate_list=VBoxContainer.new()
 candidate_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 scroll.add_child(candidate_list)
 star_warning=ConfirmationDialog.new()
 star_warning.title="星级幻兽消耗提醒"
 star_warning.ok_button_text="我已了解，选择这只副幻兽"
 star_warning.cancel_button_text="保留这只幻兽"
 confirm.add_child(star_warning)
 star_warning.confirmed.connect(func():
  warned_secondary=warning_candidate
  apply_secondary(warning_candidate)
 )
 showcase.finished.connect(func():
  fusion_busy=false
  fusion_done=true
  confirm.get_ok_button().disabled=false
  confirm.ok_button_text="完成"
  confirm.get_cancel_button().hide()
 )
 discard_popup=ConfirmationDialog.new()
 discard_popup.title="确认丢弃幻兽"
 discard_popup.ok_button_text="丢弃幻兽"
 discard_popup.cancel_button_text="保留"
 discard_popup.confirmed.connect(func():
  if discard_id>=0 and game.pet_collection.discard(game.pets,discard_id):
   game.refresh_pet_actors()
   game.save_progress()
  discard_id=-1
  rebuild()
 )
 add_child(discard_popup)
 rebuild()

func confirm_fusion() -> void:
 if fusion_done:
  confirm.hide()
  return
 if fusion_busy: return
 var candidate:=find_pet(pending_secondary)
 if not candidate.is_empty() and int(candidate.star)>=1 and warned_secondary!=pending_secondary:
  warn_about_secondary(pending_secondary)
  return
 if game.pet_collection.fuse(game.pets,pending_main,pending_secondary):
  game.refresh_pet_actors()
  game.hint="幻化成功，主幻兽获得星级经验。"
  var saved: bool=game.save_progress()
  for pet in game.pets:
   if int(pet.id)==pending_main:
    showcase.begin_result(pet)
    showcase.set_meta("saved",saved)
  fusion_busy=true
  for card in candidate_list.get_children():
   if card is Button: card.disabled=true
  confirm.get_ok_button().disabled=true
  confirm.get_cancel_button().disabled=true
 else:
  game.hint="幻化失败，请选择休息中的副幻兽。"
  confirm.hide()
 rebuild()

func text(parent: Node, value: String, font_size: int=14) -> Label:
 var label=Label.new()
 label.text=value
 label.add_theme_font_size_override("font_size",font_size)
 parent.add_child(label)
 return label

func button(parent: Node, value: String, callback: Callable) -> Button:
 var item=Button.new()
 item.text=value
 item.add_theme_font_size_override("font_size",13)
 item.pressed.connect(callback)
 parent.add_child(item)
 return item

func rebuild() -> void:
 for child in get_children():
  if child!=confirm and child!=discard_popup:
   remove_child(child)
   child.queue_free()
 countdowns.clear()
 var left=VBoxContainer.new()
 left.custom_minimum_size.x=470
 add_child(left)
 text(left,"幻兽蛋 %d / 50 · 双击蛋自动孵化 / 单击选蛋" % (50-game.pet_collection.eggs.count(null)),17)
 var egg_grid=GridContainer.new()
 egg_grid.columns=10
 left.add_child(egg_grid)
 for i in range(50):
  var slot: int=i
  var egg=game.pet_collection.eggs[i]
  var item=button(egg_grid,("战蛋" if egg.type_id==1071020 else "法蛋") if egg!=null else "·",func():
   selected_egg=slot if game.pet_collection.eggs[slot]!=null else -1
   rebuild()
  )
  item.custom_minimum_size=Vector2(43,31)
  item.tooltip_text="幻兽蛋栏位 %d · 双击自动放入首个空孵化格" % (i+1)
  item.gui_input.connect(func(event):
   if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
    auto_incubate(slot)
  )
  if selected_egg==i: item.modulate=Color("ffe19b")
 text(left,"孵化 %d / 50 · 就绪后点击提取" % (50-game.pet_collection.incubators.count(null)),17)
 var grid=GridContainer.new()
 grid.columns=10
 left.add_child(grid)
 for i in range(50):
  var slot: int=i
  var job=game.pet_collection.incubators[i]
  var item=button(grid,"",func(): incubator_clicked(slot))
  item.custom_minimum_size=Vector2(43,31)
  item.tooltip_text="第%d格 · 孵化耗时%d秒" % [i+1,game.pet_collection.duration(i)]
  countdowns.append({"button":item,"slot":i})
 text(left,"1–10格：1秒    11–20格：1分钟\n21–30格：1小时    31–50格：12小时",13)

 status=text(left,"离线继续孵化；提取前请保留幻兽空位。",13)
 status.custom_minimum_size=Vector2(460,38)
 status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 var right=VBoxContainer.new()
 right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 add_child(right)
 var deployed:=0
 for pet in game.pets:
  if pet.deployed: deployed+=1
 text(right,"幻兽 %d / 50 · 出征 %d / 2 · 出征优先" % [game.pets.size(),deployed],17)
 var indices: Array=game.pet_collection.sorted_indices(game.pets)
 for row_index in range(5):
  var row=HBoxContainer.new()
  row.custom_minimum_size.y=62
  right.add_child(row)
  var offset:=page*5+row_index
  if offset>=indices.size():
   text(row,"空位 %d" % (offset+1),14)
   continue
  var index: int=indices[offset]
  var pet: Dictionary=game.pets[index]
  if game.pet_faces.size()==2:
   var icon=TextureRect.new()
   icon.texture=game.pet_faces[0 if pet.type_id==1071020 else 1]
   icon.custom_minimum_size=Vector2(54,54)
   icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
   icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
   row.add_child(icon)
  var info=text(row,"%s #%d  Lv.%d  %d星%s\n生命%d/%d · 星经验%d/%d · 成长+%d%%" % [pet.name,pet.id,pet.level,pet.star," · 出征" if pet.deployed else "",pet.hp,pet.max,pet.star_xp,game.pet_collection.threshold(pet),pet.star*8],13)

  info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  button(row,"收回" if pet.deployed else "出征",func(): game.toggle_pet(index); rebuild())
  button(row,"幻化",func(): open_fusion(int(game.pets[index].id)))
  var uid: int=pet.id
  button(row,"丢弃",func():
   discard_id=uid
   discard_popup.dialog_text="丢弃 %s #%d（%d星）？幻兽将永久消失，出征中的幻兽会同时收回。" % [pet.name,uid,pet.star]
   discard_popup.popup_centered(Vector2i(500,190))
  )
 var pages=HBoxContainer.new()
 right.add_child(pages)
 button(pages,"上一页",func(): page=maxi(0,page-1); rebuild())
 text(pages,"第 %d / 10 页" % (page+1),14)
 button(pages,"下一页",func(): page=mini(9,page+1); rebuild())
 text(right,"点击幻化直接选择主兽；在弹窗右侧选择副幻兽。",13)
 text(right,"副兽须未出征，可跨类型；1星及以上会额外提醒。",13)
 secondary_ids=eligible_secondaries(selected_main)
 text(right,"每次+40星经验，副兽每星额外+20；升星提升8%成长。",12)
 update_countdowns()

func incubator_clicked(slot: int) -> void:
 var job=game.pet_collection.incubators[slot]
 var now:=int(Time.get_unix_time_from_system())
 if job==null:
  if not game.pet_collection.incubate(selected_egg,slot,now):
   status.text="请先点击上方的一枚幻兽蛋。"
   return
  selected_egg=-1
 elif now<int(job.ready_at):
  status.text="还在孵化，请等待倒计时结束。"
  return
 elif not game.pet_collection.extract_pet(slot,now,game.pets):
  status.text="幻兽区域已满（50/50），无法提取；蛋会保留。"
  return
 else:
  game.refresh_pet_actors()
  game.hint="提取成功，幻兽已进入右侧幻兽区域。"
 game.save_progress()
 rebuild()

func update_countdowns() -> void:
 var now:=int(Time.get_unix_time_from_system())
 for entry in countdowns:
  var job=game.pet_collection.incubators[entry.slot]
  var value: String
  if job==null:
   value="1秒" if entry.slot<10 else ("1分" if entry.slot<20 else ("1时" if entry.slot<30 else "12时"))
  else:
   var seconds:=maxi(0,int(job.ready_at)-now)
   value="提取" if seconds==0 else ("%ds" % seconds if seconds<60 else ("%dm" % int(ceil(seconds/60.0)) if seconds<3600 else "%dh" % int(ceil(seconds/3600.0))))
  entry.button.text=value
  entry.button.modulate=Color("9fe3b7") if job!=null and int(job.ready_at)<=now else Color.WHITE

func _process(dt: float) -> void:
 clock+=dt
 if clock>=0.25:
  clock=0
  update_countdowns()

func find_pet(uid: int) -> Dictionary:
 for pet in game.pets:
  if int(pet.id)==uid: return pet
 return {}

func eligible_secondaries(main_id: int) -> Array:
 var result: Array=[]
 var main:=find_pet(main_id)
 if main.is_empty(): return result
 for pet in game.pets:
  if int(pet.id)!=main_id and not pet.deployed: result.append(int(pet.id))
 return result

func open_fusion(uid: int) -> void:
 var main:=find_pet(uid)
 if main.is_empty(): return
 selected_main=uid
 pending_main=uid
 pending_secondary=-1
 star_warning.hide()
 warned_secondary=-1
 fusion_busy=false
 fusion_done=false
 showcase.prepare(main)
 confirm.dialog_text=""
 confirm.ok_button_text="开始幻化"
 confirm.get_ok_button().disabled=true
 confirm.get_cancel_button().disabled=false
 confirm.get_cancel_button().show()
 refresh_candidates()
 confirm.popup_centered(Vector2i(1080,520))

func refresh_candidates() -> void:
 for child in candidate_list.get_children():
  candidate_list.remove_child(child)
  child.queue_free()
 secondary_ids=eligible_secondaries(pending_main)
 if secondary_ids.is_empty():
  text(candidate_list,"暂无可用副幻兽。\n请孵化更多幻兽，\n或先收回出征幻兽。",14)
 for uid in secondary_ids:
  var pet:=find_pet(uid)
  var id: int=uid
  var card=Button.new()
  card.custom_minimum_size=Vector2(240,76)
  card.text="%s #%d\nLv.%d · %d星 · 星经验%d\n%s" % [pet.name,pet.id,pet.level,pet.star,pet.star_xp,"已选择" if uid==pending_secondary else "点击选择副幻兽"]
  card.add_theme_font_size_override("font_size",12)
  card.icon=load("res://assets/client_pets/%d.dds" % pet.type_id)
  card.expand_icon=true
  card.add_theme_constant_override("icon_max_width",46)
  if uid==pending_secondary: card.modulate=Color("ffe2a2")
  card.pressed.connect(func(): select_secondary(id))
  candidate_list.add_child(card)

func warn_about_secondary(uid: int) -> void:
 var pet:=find_pet(uid)
 if pet.is_empty(): return
 warning_candidate=uid
 star_warning.dialog_text="这只副幻兽已达到 %d星！\n%s #%d 将在幻化后永久消失。\n主幻兽获得星经验，副幻兽不会保留。是否仍要选择？" % [pet.star,pet.name,pet.id]
 star_warning.popup_centered(Vector2i(540,220))

func select_secondary(uid: int) -> void:
 if fusion_busy or fusion_done or not uid in eligible_secondaries(pending_main): return
 var pet:=find_pet(uid)
 if int(pet.star)>=1 and warned_secondary!=uid:
  warn_about_secondary(uid)
  return
 apply_secondary(uid)

func apply_secondary(uid: int) -> void:
 if fusion_busy or fusion_done or not uid in eligible_secondaries(pending_main): return
 pending_secondary=uid
 showcase.prepare(find_pet(pending_main),find_pet(uid))
 confirm.get_ok_button().disabled=false
 refresh_candidates()

func auto_incubate(slot: int) -> void:
 if game.pet_collection.auto_incubate(slot,int(Time.get_unix_time_from_system())):
  selected_egg=-1
  game.save_progress()
  rebuild()
 else:
  status.text="孵化栏已满，或该蛋已移入孵化栏；蛋不会丢失。"
