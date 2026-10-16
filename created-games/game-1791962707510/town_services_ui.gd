extends CanvasLayer
var game: Node
var window: PanelContainer
var content: VBoxContainer
var title := ""
var shared := false
var page := 0
var prior_pause := false
var notice: Label

func _ready() -> void:
 layer=42
 window=PanelContainer.new()
 window.position=Vector2(105,105)
 window.custom_minimum_size=Vector2(1070,550)
 var style: StyleBoxFlat=game.make_style(Color("132930"))
 style.set_content_margin_all(18)
 window.add_theme_stylebox_override("panel",style)
 add_child(window)
 content=VBoxContainer.new()
 content.add_theme_constant_override("separation",10)
 window.add_child(content)
 window.hide()

func _input(event: InputEvent) -> void:
 if not window.visible:return
 if event is InputEventKey and event.pressed:
  if event.keycode==KEY_ESCAPE:close()
  get_viewport().set_input_as_handled()
 if event is InputEventMouseButton:game.dragging=false

func _process(_dt: float) -> void:
 if window.visible and (game.menu.visible or game.hp<=0):close()

func open(npc: String) -> void:
 var menus: Node=game.get_node("GameMenus")
 if menus.current>=0:menus.close()
 if not window.visible:prior_pause=game.paused
 game.load_shared()
 title=npc
 page=0
 shared=false
 game.paused=true
 game.dragging=false
 game.hero.velocity=Vector3.ZERO
 rebuild()
 window.show()

func close() -> void:
 if not is_instance_valid(window) or not window.visible:return
 window.hide()
 game.paused=prior_pause or game.menu.visible

func label(parent: Node, text: String, size: int=20) -> Label:
 var node:=Label.new()
 node.text=text
 node.add_theme_font_size_override("font_size",size)
 parent.add_child(node)
 return node

func button(parent: Node, text: String, callback: Callable) -> Button:
 var node:=Button.new()
 node.text=text
 node.custom_minimum_size=Vector2(150,36)
 node.pressed.connect(callback)
 parent.add_child(node)
 return node

func rebuild() -> void:
 for child in content.get_children():content.remove_child(child);child.queue_free()
 label(content,title+" · "+("仓库" if title=="韦大宝" else "商店"),27)
 if title=="韦大宝":build_warehouse()
 else:build_shop()
 notice=label(content,game.message,18)
 notice.custom_minimum_size.x=1000
 notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 button(content,"关闭 · Esc",close)

func slot(parent: Node, entry: Dictionary, callback: Callable) -> Button:
 var node:=Button.new()
 node.custom_minimum_size=Vector2(50,48)
 node.expand_icon=true
 node.add_theme_constant_override("icon_max_width",36)
 node.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
 node.focus_mode=Control.FOCUS_NONE
 if not entry.is_empty():
  node.icon=game.Items.icon(entry.id)
  node.tooltip_text=game.Items.DATA[entry.id].name+" ×"+str(entry.count)+" · 点击整组存取"
  var count:=Label.new()
  count.text=str(entry.count)
  count.position=Vector2(30,29)
  count.add_theme_font_size_override("font_size",13)
  count.add_theme_constant_override("outline_size",4)
  count.add_theme_color_override("font_outline_color",Color.BLACK)
  count.mouse_filter=Control.MOUSE_FILTER_IGNORE
  node.add_child(count)
 else:node.tooltip_text="空格"
 node.disabled=entry.is_empty() or (shared and game.level<10) or game.storage_fault
 node.pressed.connect(callback)
 parent.add_child(node)
 return node

func transfer(deposit: bool, index: int) -> void:
 game.transfer_item(shared,deposit,index)
 rebuild()

func build_warehouse() -> void:
 var tabs:=HBoxContainer.new()
 content.add_child(tabs)
 for i in range(2):
  var node:=button(tabs,["个人仓库 · 当前角色","综合仓库 · 全角色共享（10级）"][i],func():shared=i==1;page=0;rebuild())
  node.toggle_mode=true
  node.button_pressed=shared==(i==1)
 label(content,"每种仓库 5 页，每页 40 格；点击物品整组存取。个人仓库随角色删除，综合仓库保留。",17)
 if shared and game.level<10:label(content,"尚未达到十级：综合仓库已锁定，无法存入或取出。",20)
 game.sync_potions()
 var row:=HBoxContainer.new()
 row.add_theme_constant_override("separation",65)
 content.add_child(row)
 var left:=VBoxContainer.new()
 row.add_child(left)
 label(left,"背包 · 点击存入")
 var bag:=GridContainer.new()
 bag.columns=8
 left.add_child(bag)
 for i in range(40):slot(bag,game.inventory[i],transfer.bind(true,i))
 var right:=VBoxContainer.new()
 row.add_child(right)
 label(right,("综合" if shared else "个人")+"仓库 · 第 %d / 5 页 · 点击取出" % (page+1))
 var grid:=GridContainer.new()
 grid.columns=8
 right.add_child(grid)
 var slots: Array=game.shared_storage if shared else game.personal_storage
 for i in range(page*40,page*40+40):slot(grid,slots[i],transfer.bind(false,i))
 var pages:=HBoxContainer.new()
 content.add_child(pages)
 for i in range(5):
  var node:=button(pages,"第 %d 页" % (i+1),func():page=i;rebuild())
  node.toggle_mode=true
  node.button_pressed=page==i

func build_shop() -> void:
 label(content,"银两 %d 两 · 点击购买，物品进入背包。药品与回城符可拖入技能栏。" % game.coins,19)
 var catalog: Array={"平十指":["potion","hp_medium","mp_small","mp_medium","return_scroll"],"刀剑笑":["blade_weapon","sword_weapon","spear_weapon"],"银娇龙":["armor"]}.get(title,[])
 for id in catalog:
  var info: Dictionary=game.Items.DATA[id]
  var text: String=info.name+" · %d 两" % info.price
  if info.has("hp"):text+=" · 恢复 %d 生命" % info.hp
  if info.has("mp"):text+=" · 恢复 %d 内力" % info.mp
  if info.has("attack"):text+=" · 攻击 +%d" % info.attack
  if info.has("defense"):text+=" · 防御 +%d" % info.defense
  var node:=button(content,text,func():game.buy_item(id);rebuild())
  node.icon=game.Items.icon(id)
  node.expand_icon=true
  node.add_theme_constant_override("icon_max_width",32)
