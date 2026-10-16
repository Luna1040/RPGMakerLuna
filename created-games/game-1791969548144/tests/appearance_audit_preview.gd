extends SceneTree
var actors: Array=[]
var ids: Array=[]
var ticks:=0
func _initialize() -> void: call_deferred("setup")
func setup() -> void:
 ids=JSON.parse_string(FileAccess.get_file_as_string("res://art-jobs/client-recovery-20261015/candidate-ids.json"))
 var grid=GridContainer.new()
 grid.columns=5
 root.add_child(grid)
 for id in ids:
  var actor=load("res://native_client_actor.gd").new()
  root.add_child(actor)
  actor.setup(id,"res://art-jobs/client-recovery-20261015/candidates/")
  actors.append(actor)
  var box=VBoxContainer.new()
  grid.add_child(box)
  var label=Label.new()
  label.text=id
  box.add_child(label)
  var icon=TextureRect.new()
  icon.texture=actor.texture()
  icon.custom_minimum_size=Vector2(240,240)
  box.add_child(icon)
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==25:
  for i in range(actors.size()):actors[i].texture().get_image().save_png("res://art-jobs/client-recovery-20261015/"+ids[i]+".png")
  root.get_texture().get_image().save_png("res://art-jobs/client-recovery-20261015/contact-review.png")
  print("PASS: independent client appearance audit previews")
  quit()
 return false
