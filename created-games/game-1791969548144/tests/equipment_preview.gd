extends SceneTree
var host: Node
var ui: CanvasLayer
var ticks:=0
func _initialize() -> void: call_deferred("setup")
func setup() -> void:
 root.gui_embed_subwindows=true
 host=load("res://canosa.gd").new()
 host.new_run()
 host.character_name="卡诺萨冒险者"
 host.level=30
 host.equipment.add_item(410050)
 host.equipment.equip(0,"战士",30)
 host.equipment.add_item(111000)
 host.equipment.equip(0,"战士",30)
 for id in [131010,121000,141000,161000,440000,135000,115000,410010,420000,410007]:host.equipment.add_item(id)
 for i in range(4):
  host.equipment.add_item(1037170)
  host.equipment.add_item(1037160)
 ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(host)
 ui.toggle(2)
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==15: capture("bag")
 if ticks==20: ui.toggle(0)
 if ticks==35: capture("character")
 if ticks==40: ui.toggle(6)
 if ticks==55: capture("forge")
 if ticks==60:
  var forge=ui.content.get_child(1)
  forge.request_forge("quality")
 if ticks==75: capture("forge-confirm")
 if ticks==80:
  ui.free()
  host.free()
  print("PASS: independent equipment bag, equipped slots, crystal forge and confirmation previews; player game not launched")
  quit()
 return false
func capture(name: String) -> void:
 assert(ui.panel.position.x+ui.panel.size.x<=1280 and ui.panel.position.y+ui.panel.size.y<=718,"Panel must fit viewport")
 root.get_texture().get_image().save_png("res://art-jobs/client-equipment-20261015/"+name+"-review.png")
