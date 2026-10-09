extends Node2D
var tools
func loop(points: PackedVector2Array, color: Color, width: float=1.5) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed,color,width,true)
func shape_points(v: Dictionary, height: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var stage=tools.stage
	if v.get("shape","")=="ellipse":
		for i in 40:
			var angle := TAU*i/40.0
			result.append(stage.project(Vector2(v.x+v.width*.5+cos(angle)*v.width*.5,v.depth+v.depth_size*.5+sin(angle)*v.depth_size*.5),height))
	else:
		for uv in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
			result.append(stage.project(Vector2(v.x+uv.x*v.width,v.depth+uv.y*v.depth_size),height))
	return result
func volume(v: Dictionary, color: Color, label: String="") -> void:
	var bottom := shape_points(v,float(v.base_z))
	var top := shape_points(v,float(v.base_z)+float(v.height))
	draw_colored_polygon(bottom,Color(color,.08))
	loop(bottom,color,2)
	loop(top,Color(color,.65))
	var stride := 10 if bottom.size()==40 else 1
	for i in range(0,bottom.size(),stride): draw_line(bottom[i],top[i],Color(color,.4),1,true)
	if label!="":
		var font := ThemeDB.fallback_font
		draw_string_outline(font,top[0]+Vector2(0,-4),label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color.BLACK)
		draw_string(font,top[0]+Vector2(0,-4),label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
func _draw() -> void:
	if tools==null: return
	var stage=tools.stage
	if stage.debug_collision:
		for v in stage.volumes:
			var color := Color("59bfff") if v.kind=="water" else Color("f5cb67") if v.standable else Color("ff7777")
			volume(v,color,str(v.id)+"  h=%.2f" % float(v.height))
		volume({"x":stage.foot.x-stage.Physics.RADIUS,"depth":stage.foot.y-stage.Physics.RADIUS,"width":stage.Physics.RADIUS*2,"depth_size":stage.Physics.RADIUS*2,"shape":"ellipse","base_z":stage.height_z,"height":stage.Physics.BODY_HEIGHT},Color("75f6ed"),"player")
		for npc in stage.townsfolk.residents:
			loop(shape_points({"x":npc.position.x-1.4,"depth":npc.position.y-1.4,"width":2.8,"depth_size":2.8,"shape":"ellipse"},0),Color("bda3ed"),1)
		for prop in stage.sorting.get_children():
			if not prop is Node2D: continue
			var p: Vector2=prop.position
			draw_line(p-Vector2(5,0),p+Vector2(5,0),Color.WHITE,2)
			draw_line(p-Vector2(0,5),p+Vector2(0,5),Color.WHITE,2)
	if tools.hit_toggle.button_pressed:
		for target in stage.practice.targets:
			volume({"x":target.foot.x-.23,"depth":target.foot.y-.22,"width":.46,"depth_size":.44,"base_z":target.reaction.height/120.0,"height":1.35},Color("f2a3df"),"木桩受击体")
		if not tools.hit_event.is_empty():
			var e: Dictionary=tools.hit_event
			var reach := float(e.get("range",240))/120.0
			var depth := float(e.get("depth_radius",.6))
			var radial: bool=e.get("shape","fan")=="radial"
			var face := float(e.get("facing",1))
			var x: float=tools.hit_foot.x-reach if radial else tools.hit_foot.x-.18 if face>0 else tools.hit_foot.x-reach
			volume({"x":x,"depth":tools.hit_foot.y-depth,"width":reach*2 if radial else reach+.18,"depth_size":depth*2,"shape":"ellipse" if radial else "rectangle","base_z":maxf(0,tools.hit_height-.15),"height":tools.hit_height+1.8-maxf(0,tools.hit_height-.15)},Color("ffad54"),"最近攻击 · 保留显示")
