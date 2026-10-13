extends Control
var runtime
const ROOMS=preload("dungeon_rooms.gd")
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	position=Vector2(1080,38)
func _process(_delta:float) -> void:
	visible=runtime.Registry.is_dungeon(runtime.zone) and runtime.run_state.get("rooms",false) and not runtime.stage.interface.is_modal()
	if visible: queue_redraw()
func _draw() -> void:
	if not visible: return
	draw_rect(Rect2(-24,-18,170,154),Color("152d30"))
	draw_rect(Rect2(-24,-18,170,154),Color("bda575"),false,2)
	var current:=int(runtime.run_state.get("room",0))
	for i in range(2):
		draw_line(Vector2(ROOMS.CELLS[i])*48+Vector2(18,18),Vector2(ROOMS.CELLS[i+1])*48+Vector2(18,18),Color("a7bec5"),5)
	for i in 3:
		var rect:=Rect2(Vector2(ROOMS.CELLS[i])*48,Vector2(36,36))
		draw_rect(rect,Color("bc9545") if i==current else Color("385953") if i<current else Color("243345"))
		draw_rect(rect,Color("ffe3a2") if i==current else Color("8294a4"),false,2)
		draw_string(get_theme_default_font(),rect.position+Vector2(8,25),"B" if i==2 else str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	draw_string(get_theme_default_font(),Vector2(-25,114),runtime.Registry.title(runtime.zone)+" · 房间地图",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e7d9b8"))
