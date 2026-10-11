extends Node2D
## Serin's own PNG actor. No borrowed knight frames or articulated cutouts.
const ClipPlayer = preload("roster_animation.gd")
const FONT = preload("res://assets/fonts/NotoSansSC-subset.ttf")
var animation := ClipPlayer.new()
var status: Dictionary = {}
var selected: Dictionary = {}

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animation.configure("serin")

func set_combat_view(data: Dictionary) -> void:
	status = data
	var action: String = {"attack1":"attack","magic":"cast","hit":"hurt","dead":"hurt"}.get(str(data.get("action","stand")),str(data.get("action","stand")))
	var elapsed := float(data.get("elapsed",0.0))
	var clip: Dictionary = animation.clip(action)
	var milliseconds := elapsed*1000.0
	if bool(data.get("dead",false)):
		milliseconds = ClipPlayer.duration_ms(clip)
	elif action in ["attack","cast"]:
		milliseconds = ClipPlayer.attack_time(clip,elapsed,0.24,0.36)
	elif action == "hurt":
		milliseconds = ClipPlayer.duration_ms(clip)*clampf(elapsed/0.32,0.0,1.0)
	selected = animation.sample(action,milliseconds,action in ["stand","walk"])
	queue_redraw()

func _draw() -> void:
	if status.is_empty():
		return
	var dead := bool(status.get("dead",false))
	draw_set_transform(Vector2.ZERO,0.0,Vector2(1.0,0.25))
	draw_circle(Vector2.ZERO,27,Color(0.02,0.04,0.06,0.32))
	draw_set_transform(Vector2.ZERO)
	if not selected.is_empty():
		var scale_factor := float(selected.scale)
		var facing := float(status.get("facing",1.0))
		var anchor: Vector2 = selected.pivot
		var tint := Color(0.58,0.62,0.69,0.7) if dead else Color.WHITE
		if float(status.get("hurt_left",0.0)) > 0.18:
			tint = Color(1.0,0.88,0.88,1.0)
		# This is an explicit hurt-endpoint fallback, not a death animation.
		var angle := -0.25*facing if dead else 0.0
		draw_set_transform(Vector2.ZERO,angle,Vector2(facing*scale_factor,scale_factor))
		draw_texture(selected.texture,-anchor,tint)
		draw_set_transform(Vector2.ZERO)
	var y := animation.standing_top()-12.0
	_draw_centered("瑟琳 · 战牧"+(" · 倒下" if dead else ""),Vector2(0,y-11),16,Color("e7e6ed"))
	if selected.is_empty():
		_draw_centered("素材加载中",Vector2(0,-100),14,Color("c6babc"))
	draw_rect(Rect2(-35,y,70,5),Color("17232d"))
	draw_rect(Rect2(-34,y+1,68*clampf(float(status.get("hp",0))/140.0,0,1),3),Color("86c89c"))
	draw_rect(Rect2(-35,y+7,70,4),Color("17232d"))
	draw_rect(Rect2(-34,y+8,68*clampf(float(status.get("mp",0))/80.0,0,1),2),Color("99bdf4"))

func _draw_centered(text: String, position_on_screen: Vector2, size: int, color: Color) -> void:
	var width := FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	draw_string(FONT,position_on_screen-Vector2(width*0.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

