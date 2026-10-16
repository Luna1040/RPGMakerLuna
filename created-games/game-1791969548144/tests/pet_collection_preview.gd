extends SceneTree
var host: Node
var ui: CanvasLayer
var ticks:=0
func _initialize() -> void: call_deferred("setup")
func setup() -> void:
 # UI-only fixture: do not add the game node, run _ready, or load main.tscn.
 host=load("res://canosa.gd").new()
 host.new_run()
 for id in [1071020,1071220]: host.pet_faces.append(load("res://assets/client_pets/%d.dds" % id))
 for i in range(12): host.pet_collection.add_egg(1071020 if i%2==0 else 1071220)
 for i in range(10):
  host.pets.append(host.pet_collection.make_pet(1071020 if i%2==0 else 1071220))
 for i in [0,10,20,30]: host.pet_collection.incubate(i%10,i,int(Time.get_unix_time_from_system())-2)
 ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(host)
 ui.toggle(1)
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==15:
  root.get_texture().get_image().save_png("res://art-jobs/pet-collection-20261015/panel-review.png")
  assert(ui.panel.get_global_rect().end.x<=1280 and ui.panel.get_global_rect().end.y<=718,"Panel must fit gameplay viewport")
  host.free()
  print("PASS: pet UI fixture rendered; game scene not started")
  quit()
 return false
