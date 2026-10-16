extends SceneTree
var host: Node
var travel: CanvasLayer
var ticks:=0
func _initialize() -> void: call_deferred("setup")
func setup() -> void:
 # Popup-only fixture. The game node is not added and _ready is not executed.
 host=load("res://canosa.gd").new()
 host.new_run()
 host.hp=0
 travel=load("res://world_travel.gd").new()
 root.add_child(travel)
 travel.setup(host)
 travel.show_death()
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==20:
  root.get_texture().get_image().save_png("res://art-jobs/client-recovery-20261015/death-dialog-review.png")
  host.free()
  print("PASS: standalone death confirmation popup preview")
  quit()
 return false
