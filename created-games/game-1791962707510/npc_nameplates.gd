extends Control
var game: Node
func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(_dt: float) -> void:
 visible=game.active_slot>0 and not game.menu.visible and game.get_node("GameMenus").current<0
 if game.has_node("TownServices") and game.services_ui.window.visible:visible=false
 queue_redraw()
func _draw() -> void:
 for title in game.town_actors:
  var actor: Node3D=game.town_actors[title]
  if actor.position.distance_to(game.hero.position)>38:continue
  var at:=actor.global_position+Vector3(0,2.0,0)
  if game.camera.is_position_behind(at):continue
  var point: Vector2=game.camera.unproject_position(at)
  if point.x<100 or point.x>1170 or point.y<220 or point.y>650:continue
  var width: float=game.FONT.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,21).x
  var baseline:=point-Vector2(width/2,0)
  draw_string_outline(game.FONT,baseline,title,HORIZONTAL_ALIGNMENT_LEFT,-1,21,5,Color("102227"))
  draw_string(game.FONT,baseline,title,HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("ffedb6"))
