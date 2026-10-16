extends RefCounted
## Map 101 object matrices and recovered terrain heights; preserve original scenery UVs.
const DIR := "res://assets/client-xuanbo/"
const Art = preload("res://client_town_art.gd")
static func apply(game: Node) -> void:
 var keep: Array=[game.hero,game.master,game.practice,game.camera,game.marker,game.shadow,game.warning_ring]
 keep.append_array(game.town_actors.values())
 for mob in game.monsters: keep.append(mob.body)
 for child in game.world.get_children():
  if child in keep or child is WorldEnvironment or child is Light3D: continue
  if str(child.name).begins_with("EarthRoad"): continue
  if not child is Node3D: continue
  if child is MeshInstance3D:
   if child.mesh is PlaneMesh: continue
   if child.mesh is BoxMesh and child.mesh.size.y<=0.5 and child.mesh.size.x>=25: continue
  if absf(child.position.x)>36 or child.position.z>29 or child.position.z < -29: continue
  child.free()
 var outside: Array[Rect2]=[]
 for rect in game.obstacles:
  var center: Vector2=rect.get_center()
  if absf(center.x)>36 or center.y>29 or center.y < -29: outside.append(rect)
 game.obstacles=outside
 var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DIR+"source-manifest.json"))
 var holder:=Node3D.new()
 holder.name="OriginalXuanboLayout"
 game.world.add_child(holder)
 game.client_ground=JSON.parse_string(FileAccess.get_file_as_string(DIR+"terrain-heights.json"))
 var terrain:=MeshInstance3D.new()
 terrain.name="OriginalTownTerrain"
 terrain.mesh=load(DIR+"town_terrain.obj")
 terrain.material_override=preload("res://texture_materials.gd").surface("stone")
 terrain.set_meta("stone_fallback",true)
 holder.add_child(terrain)
 terrain.create_trimesh_collision()
 var count:=0
 for entry in manifest.models:
  var id:=int(entry.archetype)
  var center:=Vector3(entry.source_center[0],entry.source_center[1],entry.source_center[2])
  for matrix in entry.source_instances:
   var t: Array=matrix[3]
   if float(t[0]) < -100 or float(t[0])>1300 or float(t[2])<1290 or float(t[2])>2380: continue
   var source_basis:=Basis(Vector3(matrix[0][0],matrix[0][1],matrix[0][2]),Vector3(matrix[1][0],matrix[1][1],matrix[1][2]),Vector3(matrix[2][0],matrix[2][1],matrix[2][2]))
   var source_pos: Vector3=source_basis*center+Vector3(t[0],t[1],t[2])
   var mesh: MeshInstance3D=Art.model(holder,id,Vector2(float(entry.dimensions_m[0]),float(entry.dimensions_m[2])),"客户端原坐标")
   var flip:=Basis.from_scale(Vector3(1,1,-1))
   mesh.basis=flip*source_basis*flip
   mesh.position=Vector3((source_pos.x-600)*0.05,(source_pos.y+364)*0.05,-(source_pos.z-1850)*0.05)
   if id in [35,36]:
    mesh.scale.x*=1.65
    mesh.scale.y*=1.6
    var gate_bounds: AABB=mesh.transform*mesh.get_aabb()
    game.gate_regions.append(Rect2(gate_bounds.position.x,gate_bounds.position.z,gate_bounds.size.x,gate_bounds.size.z).grow(2.0))
    gate_collision(mesh)
    for body in mesh.get_children():
     if body is StaticBody3D: body.collision_layer=16
    game.hero.collision_mask|=16
   elif id in [13,47,54,55]: mesh.create_trimesh_collision()
   mesh.set_meta("source_translation",t)
   var bounds: AABB=mesh.transform*mesh.get_aabb()
   # South gate (archetype 73) was sealed by recovered wall-end/corner pieces.
   # Remove only the two overlapping pieces, retaining all surrounding walls.
   if id in [31,32,33,34] and bounds.position.z<24 and bounds.end.z>19 and bounds.position.x<4.0 and bounds.end.x> -2.5:
    mesh.queue_free()
    continue
   if id==73 and bounds.position.z>19 and bounds.position.z<23:
    game.gate_regions.append(Rect2(-2.5,18.0,6.5,9.0))
    # Keep the recovered willow, but clear its canopy away from the reopened exit.
    mesh.position.x+=4.0
   if id==54:
    game.obstacles.append(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).grow(0.1))
   if id in [31,32,33,34,46,48,49,50,51,52,63,64,65,69,70,71]:
    var rect:=Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)
    # Eaves extend beyond the solid walls; keep the walking perimeter accessible.
    if id in [46,48,49,50,52,63,64,65]: rect=rect.grow(-minf(0.65,minf(rect.size.x,rect.size.y)*0.12))
    if rect.size.x>0.1 and rect.size.y>0.1: game.obstacles.append(rect)
    var body:=StaticBody3D.new()
    body.collision_layer=2
    body.collision_mask=0
    var shape:=CollisionShape3D.new()
    var box:=BoxShape3D.new()
    box.size=Vector3(maxf(rect.size.x,0.1),maxf(bounds.size.y,0.5),maxf(rect.size.y,0.1))
    shape.shape=box
    body.position=Vector3(rect.get_center().x,bounds.position.y+bounds.size.y/2,rect.get_center().y)
    body.add_child(shape)
    holder.add_child(body)
   count+=1
 # Reuse the client's open gate model to make the south passage visually explicit.
 for template in holder.get_children():
  if template is MeshInstance3D and template.get_meta("client_archetype",-1)==35:
   var south_gate: MeshInstance3D=template.duplicate()
   south_gate.scale.x*=2.0
   south_gate.scale.y*=1.25
   var b: AABB=south_gate.transform*south_gate.get_aabb()
   south_gate.name="SouthGate"
   south_gate.position+=Vector3(0.75-b.get_center().x,-b.position.y,22.0-b.get_center().z)
   holder.add_child(south_gate)
   break
 var positions: Dictionary={"泫渤派门主":Vector3(-21.5,0,3.5),"金香玉":Vector3(-13,0,13),"韦大宝":Vector3(-5,0,7),"平十指":Vector3(6,0,-3),"刀剑笑":Vector3(23,0,-18),"银娇龙":Vector3(10,0,9)}
 for title in positions:
  var position: Vector3=positions[title]
  position.y=game.surface_height(Vector2(position.x,position.z))
  game.town_actors[title].position=position
 game.practice.position=Vector3(-18,game.surface_height(Vector2(-18,2.5)),2.5)
 # Client stone pavement stays in use, including its original repeating UV texture.
 for child in game.world.get_children():
  if child is MeshInstance3D and child.name=="GeneratedStonePavement":
   var material:=StandardMaterial3D.new()
   material.albedo_texture=load(DIR+"tex_028.png")
   material.uv1_scale=Vector3(20,16,1)
   material.roughness=0.95
   material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
   child.material_override=material
   child.material_override=preload("res://texture_materials.gd").surface("stone")
   child.show()
 game.set_meta("client_scenery_count",count)
 game.set_meta("original_layout",true)

static func gate_collision(mesh: MeshInstance3D) -> void:
 # Use jambs and the lintel; recovered decorative doorway triangles must not seal the passage.
 var bounds := mesh.get_aabb()
 var body := StaticBody3D.new()
 body.collision_layer=16
 body.collision_mask=0
 mesh.add_child(body)
 var thickness := bounds.size.x*0.12
 for side in [-1,1]:
  var collider := CollisionShape3D.new()
  var box := BoxShape3D.new()
  box.size=Vector3(thickness,bounds.size.y,bounds.size.z*0.55)
  collider.shape=box
  collider.position=bounds.get_center()+Vector3(side*(bounds.size.x-thickness)/2,0,0)
  body.add_child(collider)
 var top := CollisionShape3D.new()
 var beam := BoxShape3D.new()
 beam.size=Vector3(bounds.size.x,bounds.size.y*0.1,bounds.size.z*0.55)
 top.shape=beam
 top.position=bounds.get_center()+Vector3(0,bounds.size.y*0.45,0)
 body.add_child(top)
