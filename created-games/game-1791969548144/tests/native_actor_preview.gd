extends SceneTree

var actors: Array=[]
var ticks := 0

func _initialize() -> void:
 call_deferred("setup")

func setup() -> void:
 var row=HBoxContainer.new()
 root.add_child(row)
 for id in ["warrior","mage","738","701","728"]:
  var actor=load("res://native_client_actor.gd").new()
  root.add_child(actor)
  actor.setup(id)
  actors.append(actor)
  var icon=TextureRect.new()
  icon.texture=actor.texture()
  icon.custom_minimum_size=Vector2(256,256)
  row.add_child(icon)

func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==30:
  for i in range(actors.size()):
   var image: Image=actors[i].texture().get_image()
   image.save_png("res://art-jobs/client-roles-20261015/preview-%d.png" % i)
  print("PASS: standalone asset previews rendered; main game scene not loaded")
  actors[0].set_movement(Vector2(1,0))
  actors[1].set_movement(Vector2(-1,0))
 if ticks==42:
  for i in range(2):
   actors[i].texture().get_image().save_png("res://art-jobs/client-roles-20261015/walk-preview-%d.png" % i)
  quit()
 return false
