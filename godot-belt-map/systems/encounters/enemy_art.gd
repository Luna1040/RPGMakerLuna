extends Node2D
## Readable code-drawn encounter placeholders; replace this view without changing AI.
var data: Dictionary = {}

func _draw() -> void:
	if data.is_empty() or data.get("state", "dead") == "dead":
		return
	var boss: bool = data.kind == "boss"
	var scale_factor := 1.45 if boss else 1.0
	var facing: float = data.facing
	var lift: float = data.reaction.height
	var bob := sin(float(data.clock) * 8.0) * (3.0 if data.state == "chase" else 0.7)
	var tint: Color = {"melee":Color("87ae73"), "ranged":Color("9f84c4"), "elite":Color("cb9b69"), "boss":Color("cf7372")}.get(data.kind,Color.WHITE)
	if data.flash > 0.0:
		tint = Color("fff1c8")
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1,0.26))
	draw_circle(Vector2.ZERO, 26 * scale_factor, Color(0.03,0.06,0.07,0.45))
	draw_set_transform(Vector2(0,-lift),0.0,Vector2(scale_factor * facing,scale_factor))
	var swing := 18.0 if data.state == "attack" else (8.0 if data.state == "telegraph" else 0.0)
	var stride := sin(float(data.clock)*10.0)*9.0 if data.state == "chase" else 2.0
	for side in [-1.0,1.0]:
		draw_line(Vector2(side*10,-42+bob),Vector2(side*12+stride*side,-5),Color("182832"),15)
		draw_line(Vector2(side*10,-42+bob),Vector2(side*12+stride*side,-5),tint.darkened(0.35),9)
		draw_line(Vector2(side*12+stride*side-5,-3),Vector2(side*12+stride*side+10,-3),Color("182832"),7)
	draw_colored_polygon(PackedVector2Array([Vector2(-21,-79+bob),Vector2(19,-80+bob),Vector2(26,-39+bob),Vector2(-23,-39+bob)]),Color("182832"))
	draw_colored_polygon(PackedVector2Array([Vector2(-16,-76+bob),Vector2(15,-76+bob),Vector2(20,-43+bob),Vector2(-17,-43+bob)]),tint)
	draw_line(Vector2(-18,-50+bob),Vector2(20,-50+bob),Color("453a36"),6)
	draw_circle(Vector2(0,-99+bob),23,Color("182832"))
	draw_circle(Vector2(0,-99+bob),18,tint)
	draw_colored_polygon(PackedVector2Array([Vector2(-14,-103+bob),Vector2(-32,-119+bob),Vector2(-19,-91+bob)]),tint)
	draw_colored_polygon(PackedVector2Array([Vector2(14,-103+bob),Vector2(30,-119+bob),Vector2(19,-91+bob)]),tint)
	draw_line(Vector2(2,-101+bob),Vector2(13,-101+bob),Color("fff0b0"),4)
	draw_rect(Rect2(9,-103+bob,3,6),Color("19242e"))
	draw_line(Vector2(-17,-73+bob),Vector2(-25,-44+bob),Color("182832"),11)
	draw_line(Vector2(15,-74+bob),Vector2(28+swing,-53-swing+bob),Color("182832"),12)
	draw_line(Vector2(15,-74+bob),Vector2(28+swing,-53-swing+bob),tint,7)
	if data.kind == "ranged":
		draw_line(Vector2(32,-26+bob),Vector2(35,-98+bob),Color("dcc689"),5)
		draw_circle(Vector2(35,-104+bob),10,Color("86d7f7"))
	else:
		draw_line(Vector2(30+swing,-42-swing+bob),Vector2(44+swing,-106-swing+bob),Color("192735"),11)
		draw_line(Vector2(30+swing,-42-swing+bob),Vector2(44+swing,-106-swing+bob),Color("d2e1dc"),6)
		draw_line(Vector2(22+swing,-55-swing+bob),Vector2(44+swing,-49-swing+bob),Color("ddb563"),5)
	if boss or data.kind == "elite":
		draw_colored_polygon(PackedVector2Array([Vector2(-20,-113+bob),Vector2(-25,-139+bob),Vector2(-7,-119+bob),Vector2(8,-139+bob),Vector2(13,-115+bob)]),Color("edd18a"))
	draw_set_transform(Vector2(0,-lift))
	if data.reaction.shock_left > 0.0:
		draw_polyline(PackedVector2Array([Vector2(-32,-124),Vector2(-40,-97),Vector2(-25,-100),Vector2(-36,-73)]),Color("9de8ff"),3)
	var bar_y := -155.0 * scale_factor
	draw_rect(Rect2(-39,bar_y,78,7),Color("192735"))
	draw_rect(Rect2(-38,bar_y+1,76*clampf(float(data.hp)/float(data.max_hp),0,1),5),Color("e8907d"))
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(-55,bar_y-10),str(data.label),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff0c8"))
	var status: String = {"telegraph":"!", "return":"RETURN", "recover":"..."}.get(data.state,"")
	if data.reaction.airborne():
		status = "AIR x" + str(data.reaction.combo)
	if not status.is_empty():
		draw_string(font,Vector2(-24,-58),status,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff0aa"))
