extends SceneTree
const UI=preload("res://skill_ui.gd")
var game: Node
func _initialize() -> void:call_deferred("run")
func frames(n: int) -> void:
 for i in range(n):await process_frame
func mouse(at: Vector2, pressed: bool) -> void:
 var event:=InputEventMouseButton.new()
 event.button_index=MOUSE_BUTTON_LEFT
 event.pressed=pressed
 event.position=at
 event.global_position=at
 root.push_input(event,true)
func motion(at: Vector2, relative: Vector2) -> void:
 var event:=InputEventMouseMotion.new()
 event.position=at
 event.global_position=at
 event.relative=relative
 event.button_mask=MOUSE_BUTTON_MASK_LEFT
 root.push_input(event,true)
func run() -> void:
 root.size=Vector2i(1280,800)
 game=load("res://main.tscn").instantiate()
 root.add_child(game)
 await frames(3)
 game.active_slot=1
 game.character={"name":"拖放测试","profession":"刀客"}
 game.menu.hide()
 game.paused=false
 game.level=10
 game.learn_skill("lightness")
 var menus: Node=game.get_node("GameMenus")
 menus.skill_category=1
 menus.toggle(3)
 await frames(4)
 var source: Control
 for node in menus.content.find_children("*","Button",true,false):
  if node is UI.SkillButton and node.skill_id=="lightness":source=node
 assert(source!=null)
 var from: Vector2=source.get_global_rect().get_center()
 var to: Vector2=menus.skill_ui.slots[4].get_global_rect().get_center()
 mouse(from,true)
 await frames(1)
 motion(from+Vector2(30,0),Vector2(30,0))
 await frames(2)
 var dragging:=root.gui_is_dragging()
 motion(to,to-from)
 await frames(2)
 mouse(to,false)
 await frames(2)
 var ok: bool=dragging and game.skill_slots[4]=="lightness"
 print("GUI_DRAG_PASS" if ok else "GUI_DRAG_FAIL", " from=",from," to=",to," assigned=",game.skill_slots[4])
 game.active_slot=0
 game.queue_free()
 await frames(2)
 quit(0 if ok else 1)
