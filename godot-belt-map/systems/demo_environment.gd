extends Node2D
## Original generated backgrounds keep their aspect ratio; weather remains animated.
var environment_id := "frost"
var room_index := 0
var clock := 0.0
var background: Texture2D

func _ready() -> void:
	background = load("res://assets/knight-demo/"+environment_id+".png")

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	if background == null: return
	var frost := environment_id == "frost"
	var scale_factor := 3072.0 / float(background.get_width())
	var tint := Color.WHITE
	if room_index == 1: tint = Color(.9,.95,1) if frost else Color(1,.9,.85)
	if room_index == 2: tint = Color(.83,.9,1) if frost else Color(1,.83,.76)
	draw_texture_rect(background,Rect2(Vector2(0,-520),Vector2(background.get_size())*scale_factor),false,tint)
	if not frost:
		for x in [1140,1320,1520,1700,1840]:
			var pulse := .5+.5*sin(clock*5+float(x))
			draw_circle(Vector2(x,420),44+4*pulse,Color(1,.42,.09,.035+.02*pulse))
	for i in 90:
		var x := fposmod(float(i*137)+clock*(24 if frost else 9),3072)
		var y := fposmod(float(i*83)+clock*(42 if frost else -24),1000)-100
		draw_circle(Vector2(x,y),1.2+float(i%3)*.45,Color(.85,.95,1,.48) if frost else Color(1,.55,.2,.5))
