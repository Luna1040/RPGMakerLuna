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
 ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(host)
 ui.toggle(1)
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==15:
  root.get_texture().get_image().save_png("res://art-jobs/client-pets-20261015/panel-review.png")
  host.free()
  print("PASS: pet UI fixture rendered; game scene not started")
  quit()
 return false
