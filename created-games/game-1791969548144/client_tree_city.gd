extends RefCounted
const SIZE:=Vector2(9216,5888)
const SCALE:=0.8
const CELL:=40
const SPAWN:=Vector2(2200,3460)
const GATE:=SPAWN
const PORTAL:=Vector2(2180,3420)
# Normalized surface footprints traced against the original assembled layout.
# Native DDS geometry remains unchanged; this graph follows leaf platforms,
# stairs and branches instead of allowing movement through the dark void.
const PLATFORMS:=[Vector4(.342,.593,.145,.125),Vector4(.235,.82,.083,.075),Vector4(.49,.72,.063,.055),Vector4(.47,.81,.055,.045),Vector4(.23,.45,.055,.045),Vector4(.34,.40,.067,.075),Vector4(.112,.43,.06,.06),Vector4(.193,.309,.048,.037),Vector4(.15,.13,.072,.065),Vector4(.61,.37,.075,.075),Vector4(.454,.225,.04,.035),Vector4(.76,.453,.04,.035),Vector4(.86,.371,.075,.07),Vector4(.622,.496,.06,.07),Vector4(.711,.65,.07,.055),Vector4(.87,.58,.068,.075),Vector4(.93,.65,.046,.04)]
const LINKS:=[
 [Vector2(.235,.59),Vector2(.23,.45)],[Vector2(.23,.45),Vector2(.34,.40)],
 [Vector2(.23,.45),Vector2(.112,.43)],[Vector2(.112,.43),Vector2(.193,.309)],
 [Vector2(.193,.309),Vector2(.15,.17)],[Vector2(.30,.69),Vector2(.235,.82)],
 [Vector2(.43,.69),Vector2(.49,.72)],[Vector2(.43,.69),Vector2(.47,.81)],
 [Vector2(.44,.49),Vector2(.61,.40)],[Vector2(.61,.40),Vector2(.454,.225)],
 [Vector2(.61,.40),Vector2(.76,.453)],[Vector2(.76,.453),Vector2(.86,.40)],
 [Vector2(.61,.40),Vector2(.622,.496)],[Vector2(.76,.453),Vector2(.711,.65)],
 [Vector2(.711,.65),Vector2(.622,.496)],[Vector2(.711,.65),Vector2(.87,.58)],
 [Vector2(.87,.58),Vector2(.93,.65)],[Vector2(.235,.82),Vector2(.30,.91)],
 [Vector2(.30,.91),Vector2(.80,.81)],[Vector2(.80,.81),Vector2(.93,.65)]
]
var grid: AStarGrid2D
var overview: Texture2D
var layout: Dictionary
var textures: Dictionary={}
func setup() -> void:
 layout=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client_treecity/layout.json"))
 overview=load("res://assets/client_treecity/overview.jpg")
 grid=AStarGrid2D.new()
 grid.region=Rect2i(0,0,ceili(SIZE.x/CELL),ceili(SIZE.y/CELL))
 grid.cell_size=Vector2(CELL,CELL)
 grid.offset=Vector2(CELL/2,CELL/2)
 grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
 grid.update()
 for y in range(grid.region.size.y):
  for x in range(grid.region.size.x): grid.set_point_solid(Vector2i(x,y),not clearance(Vector2(x*CELL+CELL/2,y*CELL+CELL/2),28))
func safe(_pos: Vector2) -> bool: return true
func land(pos: Vector2) -> bool:
 if pos.x<35 or pos.y<35 or pos.x>SIZE.x-35 or pos.y>SIZE.y-35: return false
 var uv:=pos/SIZE
 # The hollow inside the great central leaf is not a floor.
 if ((uv-Vector2(.35,.59))/Vector2(.06,.065)).length_squared()<1: return false
 for p in PLATFORMS:
  if ((uv-Vector2(p.x,p.y))/Vector2(p.z,p.w)).length_squared()<1: return true
 for link in LINKS:
  if Geometry2D.get_closest_point_to_segment(pos,link[0]*SIZE,link[1]*SIZE).distance_to(pos)<90: return true
 return false
func clearance(pos: Vector2, radius: float=14) -> bool:
 for delta in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
  if not land(pos+delta): return false
 return true
func move_allowed(from: Vector2, target: Vector2, _level: int) -> Vector2:
 var count:=maxi(1,ceili(from.distance_to(target)/10))
 for i in range(1,count+1):
  if not clearance(from.lerp(target,float(i)/count)): return from
 return target
func route(from: Vector2, target: Vector2, level: int) -> Array[Vector2]:
 var start:=Vector2i(from/float(CELL))
 var end:=Vector2i(target/float(CELL))
 if not grid.is_in_boundsv(start) or not grid.is_in_boundsv(end) or grid.is_point_solid(end): return []
 var solid:=grid.is_point_solid(start)
 grid.set_point_solid(start,false)
 var path:=grid.get_point_path(start,end)
 grid.set_point_solid(start,solid)
 var result: Array[Vector2]=[]
 var previous:=from
 for i in range(1,path.size()):
  if move_allowed(previous,path[i],level)!=path[i]: return []
  result.append(path[i])
  previous=path[i]
 if not result.is_empty() or start==end:
  if move_allowed(previous,target,level)==target: result.append(target)
 return result
func draw_ground(canvas: Node2D, hero: Vector2) -> void:
 var origin:=Vector2(640,430)-hero*SCALE
 canvas.draw_rect(Rect2(0,150,1280,568),Color("192c25"))
 var first: Vector2i=Vector2i((hero-Vector2(850,450))/128).max(Vector2i.ZERO)
 var last: Vector2i=Vector2i((hero+Vector2(850,450))/128).min(Vector2i(layout.columns-1,layout.rows-1))
 for y in range(first.y,last.y+1):
  for x in range(first.x,last.x+1):
   var id: int=layout.cells[y*int(layout.columns)+x]
   if id==65535: continue
   if not textures.has(id): textures[id]=load("res://assets/client_treecity/%d.dds" % id)
   canvas.draw_texture_rect(textures[id],Rect2(origin+Vector2(x*128,y*128)*SCALE,Vector2(128,128)*SCALE),false)
