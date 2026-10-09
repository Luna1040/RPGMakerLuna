extends Node2D
## World-space, unlit vector effects. Each effect expires without child nodes.
const MAX_EFFECTS := 32
var effects: Array[Dictionary] = []

func play(kind: String, screen_position: Vector2, facing: int = 1, effect_scale: float = 1.0) -> void:
	if effects.size() >= MAX_EFFECTS:
		effects.pop_front()
	var duration := 0.32
	match kind:
		"rising": duration = 0.48
		"trinity": duration = 0.29
		"land", "air_slash", "plunge", "air_attack": duration = 0.38
		"dash", "dash_attack": duration = 0.23
	effects.append({"kind":kind,"position":screen_position,"facing":facing,"scale":effect_scale,"age":0.0,"duration":duration})
	queue_redraw()

func _process(delta: float) -> void:
	for index in range(effects.size() - 1, -1, -1):
		effects[index].age += delta
		if effects[index].age >= effects[index].duration:
			effects.remove_at(index)
	if not effects.is_empty():
		queue_redraw()
	else:
		queue_redraw()

func _draw() -> void:
	for effect in effects:
		var phase: float = effect.age / effect.duration
		var alpha := pow(1.0 - phase, 1.3)
		var origin: Vector2 = effect.position
		var size_scale: float = effect.scale
		var facing: float = effect.facing
		draw_set_transform(origin, 0.0, Vector2(facing, 1) * size_scale)
		# The 264 px knight grips the sword roughly 130 px above her feet.
		# Widen sword trails to the combat reach without making them taller.
		if effect.kind in ["crescent", "rising", "trinity", "dash_attack"]:
			draw_set_transform(origin + Vector2(0, -105 * size_scale), 0.0, Vector2(facing * 1.6, 1) * size_scale)
		elif effect.kind == "dash":
			draw_set_transform(origin + Vector2(0, -85 * size_scale), 0.0, Vector2(facing, 1) * size_scale)
		match effect.kind:
			"crescent":
				arc_ribbon(Vector2(22,-52), 108 + phase*23, -1.2+phase*0.2, 1.15+phase*0.2, 18*(1-phase), Color(0.48,0.81,1.0,alpha))
				arc_ribbon(Vector2(22,-52), 120+phase*26, -0.9, 0.95, 4, Color(0.91,0.98,1.0,alpha))
				for j in range(6):
					var p := Vector2(28,-52)+Vector2.from_angle(-1.1+j*0.4)*(125+phase*50)
					draw_line(p-Vector2(12,0),p,Color(0.62,0.88,1.0,alpha*0.75),2,true)
			"rising":
				arc_ribbon(Vector2(45,-31), 88+phase*35, -1.85, 0.8-phase*1.2, 20*(1-phase), Color(1,0.75,0.27,alpha))
				arc_ribbon(Vector2(45,-31), 98+phase*38, -1.7, 0.6-phase, 4, Color(1,0.98,0.77,alpha))
				for j in range(7):
					var p := Vector2(25+j*11, -25-phase*(145+j*9))
					draw_line(p+Vector2(-6,18),p,Color(1,0.82,0.4,alpha*0.8),2,true)
			"trinity":
				for j in range(3):
					var offset := Vector2(j*16,-j*9)
					arc_ribbon(Vector2(30,-42)+offset, 81+phase*26, -0.9-j*0.25, 0.95-j*0.25, (9-j*2)*(1-phase), Color(0.63+j*0.1,0.51+j*0.14,1,alpha*(0.9-j*0.2)))
				streak(Vector2(25,-72),Vector2(165+phase*30,-35),Color(0.91,0.83,1.0,alpha),5*(1-phase))
			"dash", "dash_attack":
				for j in range(7):
					var p := Vector2(-45-j*9-phase*45,-18-j*12)
					streak(p-Vector2(45+j*4,0),p,Color(0.67,0.85,1,alpha*(0.5+j*0.06)),1+j%2)
				if effect.kind == "dash_attack":
					streak(Vector2(20,-60),Vector2(168+phase*30,-57),Color(0.9,0.98,1.0,alpha),9*(1-phase))
					streak(Vector2(10,-64),Vector2(170+phase*30,-57),Color(0.48,0.76,1.0,alpha*0.7),17*(1-phase))
			"land", "air_slash", "plunge", "air_attack":
				var is_impact: bool = effect.kind != "land"
				# The descending strike reaches ~214 px: show that footprint
				# promptly, rather than a tiny ring whose growth happens too late.
				var radius := 100 + sqrt(phase) * 110 if is_impact else 22 + phase * 80
				var depth := 0.22 if is_impact else 0.3
				var ring := PackedVector2Array()
				for j in range(41):
					var angle := TAU*j/40.0
					ring.append(Vector2(cos(angle)*radius,sin(angle)*radius*depth))
				draw_polyline(ring,Color(0.76,0.84,0.95,alpha),2*(1-phase)+0.5,true)
				for j in range(9):
					var angle := TAU*j/9.0
					var direction := Vector2(cos(angle),sin(angle)*depth)
					var p := direction*(radius * 0.87)
					draw_circle(p+Vector2(0,-phase*14),5*(1-phase),Color(0.72,0.69,0.62,alpha*0.46))
					if is_impact:
						draw_polyline(PackedVector2Array([direction*25,direction*88+Vector2(8,-6),direction*150]),Color(0.74,0.88,1,alpha*0.8),1.5,true)
				if is_impact:
					streak(Vector2(10,-230+phase*30),Vector2(20,0),Color(0.87,0.95,1,alpha),11*(1-phase))
		draw_set_transform(Vector2.ZERO)

func arc_ribbon(center: Vector2, radius: float, start: float, end: float, width: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(25):
		var t := index / 24.0
		points.append(center + Vector2.from_angle(lerpf(start,end,t)) * radius)
	for index in range(24,-1,-1):
		var t := index / 24.0
		var thickness := width*sin(PI*t)
		points.append(center + Vector2.from_angle(lerpf(start,end,t)) * (radius-thickness))
	draw_colored_polygon(points,color)

func streak(start: Vector2, end: Vector2, color: Color, width: float) -> void:
	var normal := (end-start).normalized().orthogonal()*width*0.5
	draw_colored_polygon(PackedVector2Array([start,end+normal,end-normal]),color)
