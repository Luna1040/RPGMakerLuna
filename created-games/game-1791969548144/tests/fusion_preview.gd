extends SceneTree
var host: Node
var ui: CanvasLayer
var collection: Control
var ticks:=0
var prefix:="fusion"
func _initialize() -> void: call_deferred("setup")
func setup() -> void:
 root.gui_embed_subwindows=true
 host=load("res://canosa.gd").new()
 if OS.get_cmdline_user_args().has("mage"):
  host.profession="法师"
  prefix="mage-fusion"
 host.new_run()
 host.pets[0].star_xp=80
 host.pets.append(host.pet_collection.make_pet(1071020 if host.profession=="战士" else 1071220))
 ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(host)
 ui.toggle(1)
 collection=ui.content.get_child(1)
 collection.pending_main=host.pets[0].id
 collection.pending_secondary=host.pets[2].id
 collection.showcase.prepare(host.pets[0],host.pets[2])
 collection.confirm.dialog_text=""
 collection.confirm.ok_button_text="开始幻化"
 collection.confirm.popup_centered(Vector2i(800,500))
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks in [15,21,40,100]:
  root.get_texture().get_image().save_png("res://art-jobs/pet-fusion-20261015/%s-%d.png" % [prefix,ticks])
 if ticks==20:
  collection.confirm.confirmed.emit()
  assert(host.pets.size()==2 and host.pets[0].star==1)
  collection.confirm.confirmed.emit()
  assert(host.pets.size()==2 and host.pets[0].star_xp==20)
 if ticks==105:
  assert(collection.fusion_done)
  collection.confirm.confirmed.emit()
  assert(not collection.confirm.visible)
  ui.free()
  host.free()
  print("PASS: original client fusion circle and two 3D models rendered; review/channel/result; repeated confirmation cannot consume twice")
  quit()
 return false
