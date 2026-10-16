extends RefCounted

const SIZE := Vector2(8856,10240)
const SPAWN := Vector2(2700,1700)
const GATE := Vector2(4250,1700)
const SCALE := 0.8
const CELL := 48
const PORTAL := Vector2(8680,10060)
const BRIDGES := [[Vector2(6870,6125),Vector2(7425,6410)],[Vector2(5370,6740),Vector2(5780,6970)]]
# Footprints traced against tile1-review.png (1400 px preview of a 4096 tile).
# They describe ground contact, not the full height of a building sprite.
const FOOTPRINTS := [
 [Vector2(605,205),Vector2(676,165),Vector2(770,166),Vector2(828,220),Vector2(776,266),Vector2(666,265)],
 [Vector2(867,86),Vector2(965,46),Vector2(1042,132),Vector2(953,183),Vector2(858,140)],
 [Vector2(1256,217),Vector2(1340,178),Vector2(1398,215),Vector2(1398,296),Vector2(1339,325),Vector2(1254,276)],
 [Vector2(612,352),Vector2(676,330),Vector2(718,384),Vector2(692,451),Vector2(609,460),Vector2(553,418)],
 [Vector2(711,349),Vector2(773,322),Vector2(838,354),Vector2(820,398),Vector2(759,409)],
 [Vector2(823,369),Vector2(872,339),Vector2(946,391),Vector2(938,449),Vector2(866,472),Vector2(834,434)],
 [Vector2(1087,516),Vector2(1151,485),Vector2(1228,527),Vector2(1182,559)],
 [Vector2(493,800),Vector2(612,730),Vector2(686,766),Vector2(669,814),Vector2(570,854)],
 [Vector2(1011,296),Vector2(1071,263),Vector2(1143,310),Vector2(1080,341)],
 [Vector2(1132,379),Vector2(1180,354),Vector2(1233,384),Vector2(1180,411)]
]
const DECOR_FOOTPRINTS := [
 # center x/y and radii in the same source preview: flower beds, pedestals,
 # crates and planters. Stair approaches remain open.
 Vector4(775,645,39,20),Vector4(922,632,28,24),
 Vector4(627,672,17,12),Vector4(662,657,17,12),
 Vector4(405,691,26,20),Vector4(361,780,18,12),
 Vector4(618,931,20,13),Vector4(1298,418,14,12),
 Vector4(1194,446,13,12),Vector4(1302,315,13,12),
 Vector4(917,914,37,22)
]
const NPC_POS := [Vector2(2450,1800),Vector2(1550,2150),Vector2(3350,1900),Vector2(3350,1200),Vector2(1650,1350),Vector2(4100,1700),Vector2(2200,2400)]
const CITY := [Vector2(100,1960),Vector2(1220,1320),Vector2(1100,950),Vector2(1400,350),Vector2(2500,10),Vector2(4100,10),Vector2(4500,500),Vector2(4800,1100),Vector2(4400,1640),Vector2(4200,1850),Vector2(3750,2200),Vector2(3150,2550),Vector2(2200,3000),Vector2(200,2350)]
var tiles: Array[Texture2D]=[]
var overview: Texture2D
var terrain: Image
var grid: AStarGrid2D
var blocked_grid: AStarGrid2D
var footprints: Array[PackedVector2Array]=[]

func setup() -> void:
 for i in range(1,10): tiles.append(load("res://assets/client_canosa/10240-%d.dds" % i))
 overview=load("res://assets/client_canosa/4096.jpg")
 terrain=overview.get_image()
 for polygon in FOOTPRINTS:
  var points:=PackedVector2Array()
  for point in polygon: points.append(point*(4096.0/1400.0))
  footprints.append(points)
 grid=make_grid(false)
 blocked_grid=make_grid(true)

func safe(pos: Vector2) -> bool:
 return Geometry2D.is_point_in_polygon(pos,PackedVector2Array(CITY))

func land(pos: Vector2) -> bool:
 if pos.x<60 or pos.y<60 or pos.x>SIZE.x-60 or pos.y>SIZE.y-60: return false
 if on_bridge(pos): return true
 var p:=pos/SIZE*Vector2(terrain.get_size())
 var color:=terrain.get_pixel(clampi(int(p.x),0,terrain.get_width()-1),clampi(int(p.y),0,terrain.get_height()-1))
 # Conservative water mask; source pixels are never modified.
 if color.r<0.25 and color.b>color.g*1.2 and color.b>color.r*1.4 and color.b>0.22: return false
 # Large fountain/central monuments receive conservative footprint volumes.
 for obstacle in [Rect2(1840,1000,680,510),Rect2(1850,420,650,420),Rect2(2450,60,520,490),Rect2(3640,10,450,680)]:
  if obstacle.has_point(pos): return false
 for polygon in footprints:
  if Geometry2D.is_point_in_polygon(pos,polygon): return false
 var preview:=pos*(1400.0/4096.0)
 for decor in DECOR_FOOTPRINTS:
  var delta:=(preview-Vector2(decor.x,decor.y))/Vector2(decor.z,decor.w)
  if delta.length_squared()<1: return false
 return true

func on_bridge(pos: Vector2, radius: float=62.0) -> bool:
 for bridge in BRIDGES:
  if Geometry2D.get_closest_point_to_segment(pos,bridge[0],bridge[1]).distance_to(pos)<=radius: return true
 return false

func clearance(pos: Vector2, radius: float=14.0) -> bool:
 for delta in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
  if not land(pos+delta): return false
 return true

func make_grid(inside_only: bool) -> AStarGrid2D:
 var result:=AStarGrid2D.new()
 result.region=Rect2i(0,0,ceili(SIZE.x/CELL),ceili(SIZE.y/CELL))
 result.cell_size=Vector2(CELL,CELL)
 result.offset=Vector2(CELL/2,CELL/2)
 result.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
 result.update()
 for y in range(result.region.size.y):
  for x in range(result.region.size.x):
   var pos:=Vector2(x*CELL+CELL/2,y*CELL+CELL/2)
   var blocked:=not clearance(pos,35) or (inside_only and not safe(pos))
   if not inside_only and on_bridge(pos,35): blocked=false
   if pos.distance_to(GATE)>420:
    for delta in [Vector2(CELL,0),Vector2(-CELL,0),Vector2(0,CELL),Vector2(0,-CELL)]:
     if safe(pos)!=safe(pos+delta): blocked=true
   result.set_point_solid(Vector2i(x,y),blocked)
 return result

func move_allowed(from: Vector2, target: Vector2, level: int) -> Vector2:
 var count:=maxi(1,ceili(from.distance_to(target)/10))
 var previous:=from
 for i in range(1,count+1):
  var point:=from.lerp(target,float(i)/count)
  if not clearance(point): return from
  if safe(previous)!=safe(point):
   if point.distance_to(GATE)>420: return from
  previous=point
 return target

func route(from: Vector2, target: Vector2, level: int) -> Array[Vector2]:
 var nav:=grid
 var start:=Vector2i(from/float(CELL))
 var end:=Vector2i(target/float(CELL))
 if not nav.is_in_boundsv(start) or not nav.is_in_boundsv(end) or nav.is_point_solid(end): return []
 # Spawn/NPC standing points can lie just inside a coarse footprint edge.
 var start_blocked:=nav.is_point_solid(start)
 nav.set_point_solid(start,false)
 var points:=nav.get_point_path(start,end)
 nav.set_point_solid(start,start_blocked)
 var result: Array[Vector2]=[]
 var previous:=from
 for i in range(1,points.size()):
  if move_allowed(previous,points[i],level)!=points[i]: return []
  result.append(points[i])
  previous=points[i]
 if not result.is_empty() or start==end:
  if move_allowed(previous,target,level)!=target: return []
  result.append(target)
 return result

func draw_ground(canvas: Node2D, hero: Vector2) -> void:
 var origin:=Vector2(640,430)-hero*SCALE
 for i in range(tiles.size()):
  var pos:=Vector2((i%3)*4096,(i/3)*4096)
  var rect:=Rect2(origin+pos*SCALE,Vector2(tiles[i].get_size())*SCALE)
  if rect.intersects(Rect2(0,150,1280,568)): canvas.draw_texture_rect(tiles[i],rect,false)
