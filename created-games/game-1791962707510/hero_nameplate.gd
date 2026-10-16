extends Control
var game: Node
func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 z_index=5
func _process(_dt: float) -> void:
 visible=game.active_slot>0 and not game.menu.visible and game.get_node("GameMenus").current<0 and not game.camera.is_position_behind(game.hero.position)
 if visible:
  position=game.camera.unproject_position(game.hero_model.root.global_position+Vector3(0,1.6,0))-Vector2(80,29)
  queue_redraw()
func _draw() -> void:
 var font: Font=game.FONT
 var title := "%s · Lv.%d" % [game.character.get("name","侠客"),game.level]
 var width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
 draw_style_box(game.make_style(Color(0.04,0.08,0.1,0.8)),Rect2(80-width/2-5,0,width+10,22))
 draw_string(font,Vector2(80-width/2,16),title,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("fff1cd"))
 draw_rect(Rect2(36,25,88,6),Color("14292b"))
 draw_rect(Rect2(37,26,86*clampf(game.hp/game.max_hp(),0,1),4),Color("6fce86"))
 draw_rect(Rect2(36,33,88,5),Color("14292b"))
 draw_rect(Rect2(37,34,86*clampf(game.qi/game.max_qi(),0,1),3),Color("65b5ec"))
