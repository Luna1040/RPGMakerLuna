extends SceneTree
var host: Node
var ui: CanvasLayer
var collection: Control
var ticks:=0
func _initialize() -> void: call_deferred("setup")
func setup() -> void:
 root.gui_embed_subwindows=true
 host=load("res://canosa.gd").new()
 host.new_run()
 for i in range(5): host.pets.append(host.pet_collection.make_pet(1071020))
 host.pets[3].star=1
 host.pets[3].level=12
 for pet in host.pets: pet.star_xp=20
 ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(host)
 ui.toggle(1)
 collection=ui.content.get_child(1)
 collection.open_fusion(host.pets[0].id)
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==15: capture("fusion-picker")
 if ticks==20: collection.select_secondary(host.pets[3].id)
 if ticks==30: capture("star-warning")
 if ticks==35: collection.star_warning.get_ok_button().pressed.emit()
 if ticks==45: capture("fusion-selected")
 if ticks==50: collection.confirm_fusion()
 if ticks==51: capture("fusion-channel")
 if ticks==90:
  capture("fusion-result")
  assert(collection.fusion_done)
  ui.free()
  host.free()
  print("PASS: direct fusion picker, native main model, visual secondary cards, 1-star warning, channel and result preview")
  quit()
 return false
func capture(name: String) -> void:
 root.get_texture().get_image().save_png("res://art-jobs/loot-fusion-20261015/"+name+".png")
