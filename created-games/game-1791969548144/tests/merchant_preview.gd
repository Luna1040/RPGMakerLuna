extends SceneTree
var host: Node
var ui: CanvasLayer
var ticks:=0
func _initialize() -> void: call_deferred("setup")
func find_button(node: Node, value: String) -> Button:
 if node is Button and node.text==value: return node
 for child in node.get_children():
  var result:=find_button(child,value)
  if result!=null: return result
 return null
func setup() -> void:
 root.gui_embed_subwindows=true
 host=load("res://canosa.gd").new()
 host.new_run()
 host.gold=1200
 for id in [410000,410001,410002,410003,410007,1037170,1037160,1020010,1020020]: host.equipment.add_item(id)
 host.pets.append(host.pet_collection.make_pet(1071220))
 host.pets.append(host.pet_collection.make_pet(1071020))
 host.pet_collection.add_egg(1071020)
 ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(host)
 ui.toggle(7)
func capture(name: String) -> void:
 assert(ui.panel.get_global_rect().end.x<=1280 and ui.panel.get_global_rect().end.y<=718)
 root.get_texture().get_image().save_png("res://art-jobs/merchant-pets-20261015/"+name+".png")
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==15: capture("merchant-buy")
 if ticks==20: ui.content.get_child(1).tabs.current_tab=1
 if ticks==35: capture("merchant-sell")
 if ticks==40: ui.toggle(2)
 if ticks==55: capture("quality-bag")
 if ticks==60: ui.toggle(1)
 if ticks==75: capture("pet-management")
 if ticks==80: ui.content.get_child(1).open_fusion(host.pets[0].id)
 if ticks==95: capture("cross-type-fusion")
 if ticks==100:
  ui.content.get_child(1).confirm.hide()
  find_button(ui.content.get_child(1),"丢弃").pressed.emit()
 if ticks==110: capture("pet-discard-confirm")
 if ticks==115:
  ui.free()
  host.free()
  print("PASS: merchant buy/sell, five color equipment, pet management/discard and cross-type fusion previews fit viewport")
  quit()
 return false
