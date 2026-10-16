extends CanvasLayer
var game: Node
var shade: ColorRect
var death: PanelContainer
var death_confirm: Button
var letter: PanelContainer
var letter_body: VBoxContainer
var mail: Button
var prior_pause:=false
func _ready() -> void:
 layer=45
 shade=ColorRect.new()
 shade.size=Vector2(1280,800)
 shade.color=Color(0,0,0,0.5)
 shade.mouse_filter=Control.MOUSE_FILTER_STOP
 add_child(shade)
 shade.hide()
 death=panel(Vector2(410,285),Vector2(460,210))
 var box:=VBoxContainer.new()
 box.add_theme_constant_override("separation",18)
 death.add_child(box)
 label(box,"侠客重伤 · 回城疗伤",26)
 label(box,"确认后返回泫渤派。\n角色等级、银两、背包与任务进度保留。",20)
 death_confirm=button(box,"确认回城",game.confirm_return_to_town)
 letter=panel(Vector2(300,170),Vector2(680,420))
 letter_body=VBoxContainer.new()
 letter_body.add_theme_constant_override("separation",18)
 letter.add_child(letter_body)
 mail=Button.new()
 mail.position=Vector2(1038,237)
 mail.custom_minimum_size=Vector2(142,46)
 mail.icon=load("res://assets/client-progress/main_btn_mail.png")
 mail.expand_icon=true
 mail.add_theme_constant_override("icon_max_width",30)
 mail.pressed.connect(open_letter.bind(false))
 mail.focus_mode=Control.FOCUS_NONE
 add_child(mail)
func panel(at: Vector2, extent: Vector2) -> PanelContainer:
 var value:=PanelContainer.new()
 value.position=at
 value.custom_minimum_size=extent
 var style: StyleBoxFlat=game.make_style(Color("142e35"))
 style.content_margin_left=22
 style.content_margin_right=22
 style.content_margin_top=18
 style.content_margin_bottom=18
 value.add_theme_stylebox_override("panel",style)
 add_child(value)
 value.hide()
 return value
func label(parent: Node, text: String, font_size: int) -> void:
 var value:=Label.new()
 value.text=text
 value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 value.add_theme_font_size_override("font_size",font_size)
 parent.add_child(value)
func button(parent: Node, text: String, callback: Callable) -> Button:
 var value:=Button.new()
 value.text=text
 value.custom_minimum_size.y=38
 value.pressed.connect(callback)
 parent.add_child(value)
 return value
func _process(_dt: float) -> void:
 mail.visible=game.active_slot>0 and not game.menu.visible and game.promotion_stage>0 and not death.visible and not letter.visible
 mail.text="飞鸽 · 未读" if game.promotion_stage==1 else "门主传书"
 if game.menu.visible:reset_windows()
func reset_windows() -> void:
 if death==null:return
 death.hide()
 letter.hide()
 shade.hide()
func show_death() -> void:
 if death.visible:return
 var menus: Node=game.get_node("GameMenus")
 if menus.current>=0:menus.close()
 game.dialogue.hide()
 letter.hide()
 game.paused=true
 game.dragging=false
 game.hero.velocity=Vector3.ZERO
 shade.show()
 death.show()
 death_confirm.grab_focus()
func open_letter(offer: bool=false) -> void:
 if game.hp<=0 or game.menu.visible or letter.visible:return
 if game.promotion_stage==1:game.promotion_stage=2
 var menus: Node=game.get_node("GameMenus")
 if menus.current>=0:menus.close()
 prior_pause=game.paused
 game.paused=true
 game.dragging=false
 for child in letter_body.get_children():
  letter_body.remove_child(child)
  child.queue_free()
 label(letter_body,"飞鸽传书 · 泫渤派门主",27)
 label(letter_body,"侠客，你已满十级，可申请第一次升职。\n请备齐警备团甲衣与兵器，接受江湖历练。",22)
 label(letter_body,game.promotion_description(),21)
 if offer and game.promotion_stage in [1,2]:button(letter_body,"接受第一次升职任务",game.accept_promotion)
 elif game.promotion_stage<14:button(letter_body,"自动寻路 · "+game.promotion_target(),func():close_letter();game.guide_promotion())
 button(letter_body,"收起传书 · Esc",close_letter)
 shade.show()
 letter.show()
func close_letter() -> void:
 letter.hide()
 shade.hide()
 game.paused=prior_pause
func _input(event: InputEvent) -> void:
 if death!=null and death.visible:
  if event is InputEventKey:
   if event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER]:game.confirm_return_to_town()
   get_viewport().set_input_as_handled()
 elif letter!=null and letter.visible and event is InputEventKey:
  if event.pressed and event.keycode==KEY_ESCAPE:close_letter()
  get_viewport().set_input_as_handled()
