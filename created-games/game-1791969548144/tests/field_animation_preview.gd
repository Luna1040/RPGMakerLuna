extends SceneTree
var actors: Array=[]
var ticks:=0
var ids:=["warrior","mage","mob100","mob110","mob120"]
func _initialize() -> void: call_deferred("setup")
func setup() -> void:
 var row=HBoxContainer.new()
 root.add_child(row)
 for id in ids:
  var actor=load("res://native_client_actor.gd").new()
  root.add_child(actor)
  actor.setup(id)
  actors.append(actor)
  var image=TextureRect.new()
  image.texture=actor.texture()
  image.custom_minimum_size=Vector2(256,256)
  row.add_child(image)
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks in [15,25,35,45,55,65,75]:
  for i in range(actors.size()): actors[i].texture().get_image().save_png("res://art-jobs/client-field-monsters-20261015/%s-%d.png" % [ids[i],ticks])
 if ticks==15:
  for actor in actors: actor.set_movement(Vector2(1,0))
 if ticks==45:
  for actor in actors:
   actor.set_movement(Vector2.ZERO)
   actor.play_attack()
 if ticks==80:
  print("PASS: isolated warrior/mage/three-monster idle, move and attack previews; main scene not loaded")
  quit()
 return false
