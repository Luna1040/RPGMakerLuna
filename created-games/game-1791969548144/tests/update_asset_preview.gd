extends SceneTree
var actors: Array=[]
var ticks:=0
func _initialize() -> void: call_deferred("setup")
func setup() -> void:
 var row=HBoxContainer.new()
 root.add_child(row)
 for id in ["603","721","704","719"]:
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
  for i in range(actors.size()): actors[i].texture().get_image().save_png("res://art-jobs/client-npcs-extended-20261015/preview-%d.png" % i)
  for id in [1071020,1071220]:
   var tex: Texture2D=load("res://assets/client_pets/%d.dds" % id)
   tex.get_image().save_png("res://art-jobs/client-pets-20261015/preview-%d.png" % id)
  print("PASS: independent original NPC/pet asset previews; main game not loaded")
  quit()
 return false
