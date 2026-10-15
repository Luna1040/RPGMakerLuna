extends RefCounted
## Local client map 101 static scenery, converted from documented vertex/UV data.
## Existing gameplay collisions and navigation remain authoritative.
const FOLDER := "res://assets/client-xuanbo/"
static var manifest: Dictionary = {}
static var pavement: StandardMaterial3D
static var masonry: ShaderMaterial
static var roof_tiles: ShaderMaterial

static func hide_geometry(node: Node) -> void:
 if node is MeshInstance3D: node.visible=false
 for child in node.get_children(): hide_geometry(child)

static func model(parent: Node3D, id: int, footprint: Vector2, title: String="") -> MeshInstance3D:
 if manifest.is_empty(): manifest=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"source-manifest.json"))
 var entry: Dictionary={}
 for candidate in manifest.models:
  if int(candidate.archetype)==id: entry=candidate; break
 assert(not entry.is_empty(),"Missing client archetype")
 var result:=MeshInstance3D.new()
 result.name="ClientMap101_%03d" % id
 result.mesh=load(FOLDER+entry.asset) as Mesh
 assert(result.mesh!=null)
 var size: Array=entry.dimensions_m
 var factor:=minf(footprint.x/maxf(float(size[0]),0.001),footprint.y/maxf(float(size[2]),0.001))
 result.scale=Vector3.ONE*factor
 result.set_meta("client_archetype",id)
 result.set_meta("source_map","NCSData/101/101.txt")
 result.set_meta("role",title)
 # Preserve source atlas UVs; alpha cutout handles fences, leaves and cloth holes.
 for surface in range(result.mesh.get_surface_count()):
  var original=result.mesh.surface_get_material(surface)
  if original is StandardMaterial3D:
   var material: StandardMaterial3D=original.duplicate()
   material.roughness=0.95
   material.cull_mode=BaseMaterial3D.CULL_DISABLED
   material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
   material.alpha_scissor_threshold=0.35
   material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
   result.set_surface_override_material(surface,material)
 parent.add_child(result)
 return result

static func replace_building(holder: Node3D, id: int, footprint: Vector2, title: String) -> void:
 hide_geometry(holder)
 # Parent may already be scaled by map enlargement. Fit using world dimensions.
 var replacement:=model(holder,id,footprint/Vector2(holder.scale.x,holder.scale.z),title)
 replacement.scale.y/=holder.scale.y/maxf(holder.scale.x,0.001)
 holder.set_meta("client_building",true)

static func apply(game: Node) -> void:
 var world: Node3D=game.world
 var count:=0
 for child in world.get_children():
  if not child is Node3D: continue
  var path: String=child.scene_file_path
  if path.ends_with("hall.tscn"):
   replace_building(child,52,Vector2(10,7.5),"泫渤大殿")
   count+=1
  elif path.ends_with("inn.tscn"):
   var clinic: bool=child.position.x>15 and child.position.z<0 and child.position.z>-18
   replace_building(child,50 if clinic else 49,Vector2(7.2,6.1) if absf(child.position.x)<23 and child.position.z<0 else Vector2(5.6,5.2),"十指医馆" if clinic else "客栈与民居")
   count+=1
  elif child.get_child_count()>0 and child.get_child(0) is MeshInstance3D and child.get_child(0).mesh is CylinderMesh and is_equal_approx(child.get_child(0).mesh.height,2.8):
   hide_geometry(child)
   model(child,1,Vector2(4.3,4.3),"泫渤派树木")
   count+=1
  else:
   for label in child.get_children():
    if label is Label3D:
     var title: String=label.text
     if title in ["刀剑铁坊","大宝杂货","银龙绸庄"]:
      replace_building(child,48 if title=="刀剑铁坊" else (69 if title=="大宝杂货" else 70),Vector2(5.8,3.7),title)
      count+=1
     elif title.contains("东门") or title.contains("西门") or title.contains("南门"):
      hide_geometry(child)
      model(child,35,Vector2(10.5,3.0),title)
      count+=1
 # The original client stone texture replaces the generated pavement only.
 if pavement==null:
  pavement=StandardMaterial3D.new()
  pavement.albedo_texture=load(FOLDER+"tex_028.png")
  pavement.uv1_scale=Vector3(20,16,1)
  pavement.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
  pavement.roughness=0.95
 for child in world.get_children():
  if child is MeshInstance3D and child.name=="GeneratedStonePavement":
   child.material_override=pavement
 # World-space maps make platform/stair blocks match the recovered pavement.
 masonry=surface("tex_028.png",0.45)
 roof_tiles=surface("tex_051.png",0.8)
 apply_masonry(world)
 game.set_meta("client_scenery_count",count)

static func surface(texture: String, tiling: float) -> ShaderMaterial:
 var shader:=Shader.new()
 shader.code="""shader_type spatial;
 uniform sampler2D atlas: source_color,filter_linear_mipmap_anisotropic,repeat_enable;
 uniform float scale=0.5;
 varying vec3 p;
 varying vec3 n;
 void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;n=normalize(mat3(MODEL_MATRIX)*NORMAL);}
 void fragment(){vec3 w=pow(abs(normalize(n)),vec3(8.0));w/=max(dot(w,vec3(1.0)),0.001);ALBEDO=texture(atlas,p.zy*scale).rgb*w.x+texture(atlas,p.xz*scale).rgb*w.y+texture(atlas,p.xy*scale).rgb*w.z;ROUGHNESS=0.95;}
 """
 var material:=ShaderMaterial.new()
 material.shader=shader
 material.set_shader_parameter("atlas",load(FOLDER+texture))
 material.set_shader_parameter("scale",tiling)
 return material

static func apply_masonry(node: Node) -> void:
 # Imported client mesh UVs are authoritative and must never be overwritten.
 if node is MeshInstance3D and not node.has_meta("client_archetype"):
  var kind: String=str(node.get_meta("material_kind",""))
  if kind in ["wall","stone"] or node.mesh is PrismMesh or (node.mesh is BoxMesh and node.mesh.size.x>=1.5 and node.mesh.size.y<=0.9): node.material_override=masonry
  elif kind=="roof": node.material_override=roof_tiles
 for child in node.get_children():
  if not child.has_meta("client_archetype"): apply_masonry(child)
