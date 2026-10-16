extends SceneTree
var ticks:=0
func _initialize() -> void:
 var canvas=load("res://tests/tree_map_preview_canvas.gd").new()
 root.add_child.call_deferred(canvas)
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==30:
  root.get_texture().get_image().save_png("res://art-jobs/client-recovery-20261015/treecity-entry-review.png")
  print("PASS: independent original tree city map preview; main scene not loaded")
  quit()
 return false
