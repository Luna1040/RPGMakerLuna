extends Node2D
var combat
var clip: Dictionary={}
func _ready() -> void:
	var additive:=CanvasItemMaterial.new()
	additive.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	material=additive
	var folder:="res://assets/h3-v1/explosion/"
	if FileAccess.file_exists(folder+"manifest.json") and ResourceLoader.exists(folder+"atlas.png"):
		clip=JSON.parse_string(FileAccess.get_file_as_string(folder+"manifest.json"))
		clip.texture=load(folder+"atlas.png")
func _process(_delta: float) -> void: queue_redraw()
func _draw() -> void:
	if combat==null or clip.is_empty() or combat.choice or combat.game.mode!="flight": return
	for fx in combat.effects:
		if fx.pulse: continue
		var index:=clampi(int(fx.age/2.0*clip.frames),0,int(clip.frames)-1)
		var tile:=float(clip.tile)
		var source:=Rect2(index%int(clip.columns)*tile,index/int(clip.columns)*tile,tile,tile)
		var size: float=fx.radius*3.4
		draw_texture_rect_region(clip.texture,Rect2(fx.p-Vector2.ONE*size/2,Vector2.ONE*size),source,Color(1,1,1,clampf((2-fx.age)*3,0,1)))
