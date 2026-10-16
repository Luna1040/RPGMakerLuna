extends RefCounted
var mapping: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client_loot/mapping.json"))
var cache: Dictionary={}
func texture(path: String) -> Texture2D:
 if not cache.has(path): cache[path]=load(path)
 return cache[path]
func ground_shadow(canvas: CanvasItem, point: Vector2, radius: float) -> void:
 canvas.draw_set_transform(point,0,Vector2(1,0.38))
 canvas.draw_circle(Vector2.ZERO,radius,Color(0.01,0.02,0.02,0.42))
 canvas.draw_set_transform(Vector2.ZERO)
func draw_item(canvas: CanvasItem, point: Vector2, id: int) -> void:
 var path: String=mapping.get(str(id),"")
 if path.is_empty(): return
 ground_shadow(canvas,point+Vector2(0,8),19)
 var icon:=texture(path)
 var extent:=icon.get_size()
 var scale:=minf(56.0/maxf(1,extent.x),56.0/maxf(1,extent.y))
 extent*=scale
 canvas.draw_texture_rect(icon,Rect2(point+Vector2(-extent.x/2,-extent.y+12),extent),false)
func draw_egg(canvas: CanvasItem, point: Vector2, type_id: int) -> void:
 ground_shadow(canvas,point+Vector2(0,8),16)
 var icon:=texture("res://assets/client_loot/egg1.dds" if type_id==1071020 else "res://assets/client_loot/egg2.dds")
 canvas.draw_texture_rect(icon,Rect2(point+Vector2(-16,-32),Vector2(32,42)),false)
