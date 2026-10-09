extends Node2D
## Coordinates are in the original fountain painting, cropped by alphaBBox.
var elapsed := 0.0
var water_material: ShaderMaterial
const FALLS := [Vector2(463,350), Vector2(565,355), Vector2(920,355), Vector2(1014,350)]
const LANDINGS := [Vector2(408,623), Vector2(521,668), Vector2(952,670), Vector2(1060,625)]
func setup(sprite: Sprite2D, bounds: Array) -> void:
	water_material = ShaderMaterial.new()
	water_material.shader = preload("fountain_water.gdshader")
	water_material.set_shader_parameter("water_time", 0.0)
	sprite.material = water_material
	position = sprite.position - sprite.texture.get_size()*sprite.scale/2.0 - Vector2(bounds[0],bounds[1])*sprite.scale
	scale = sprite.scale

func _process(delta: float) -> void:
	elapsed += delta
	water_material.set_shader_parameter("water_time", elapsed)
	queue_redraw()

func ellipse(center: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in 49:
		var a := TAU*i/48.0
		points.append(center+Vector2(cos(a),sin(a))*radius)
	draw_polyline(points,color,width,true)

func _draw() -> void:
	for i in 4:
		var start: Vector2 = FALLS[i]
		var end: Vector2 = LANDINGS[i]
		# Bright streaks travel down the four existing cascades.
		for j in 7:
			var t := fposmod(elapsed*0.78+j/7.0+i*0.13,1.0)
			var t2 := minf(t+0.045,1.0)
			var p := start.lerp(end,t)
			var p2 := start.lerp(end,t2)
			p.x += sin(t*PI)*(-14.0 if i<2 else 14.0)
			p2.x += sin(t2*PI)*(-14.0 if i<2 else 14.0)
			draw_line(p,p2,Color(0.78,0.96,1,0.65*sin(t*PI)),4.5,true)
		for j in 3:
			var t := fposmod(elapsed*0.7+j/3.0+i*.17,1.0)
			ellipse(end,Vector2(14+58*t,4+13*t),Color(.75,.95,1,(1-t)*.5),2.8)
		for j in 9:
			var t := fposmod(elapsed*1.2+j/9.0+i*.12,1.0)
			var spread := sin(j*12.34+i)*43
			var p := end+Vector2(spread*t,-sin(t*PI)*(14+float(j%3)*7))
			draw_circle(p,2.2,Color(.83,.97,1,(1-t)*.8))
	# Fountain crown: a rising jet and falling droplets above the upper basin.
	for j in 16:
		var t := fposmod(elapsed*.65+j/16.0,1.0)
		var side := -1.0 if j%2==0 else 1.0
		var p := Vector2(741+side*(18+float(j%5)*10)*t,312-205*sin(t*PI))
		draw_circle(p,2.5+float(j%3),Color(.8,.97,1,sin(t*PI)*.8))
	for j in 4:
		var t := fposmod(elapsed*.5+j/4.0,1.0)
		ellipse(Vector2(745,323),Vector2(30+140*t,4+14*t),Color(.8,.96,1,(1-t)*.45),2.4)
