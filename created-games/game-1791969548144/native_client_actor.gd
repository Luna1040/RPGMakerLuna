extends Node

var viewport: SubViewport
var pivot: Node3D
var sources: Array[Dictionary]=[]
var scale_factor := 0.012
var moving := false
var phase := 0.0
var elapsed := 0.0
var direction := 0.0
var base_direction := 0.0
var foot_anchor := Vector2(128,208)
static var resource_cache: Dictionary={}
var clips: Dictionary={}
var animation_clock:=0.0
var attack_remaining:=0.0
var attack_serial:=0
var enabled:=true
var actor_id:=""
var asset_directory:="res://assets/client_roles/"

func transform_point(point: Array, matrix: Array) -> Vector3:
 var x: float=point[0]
 var y: float=point[1]
 var z: float=point[2]
 return Vector3(x*matrix[0]+y*matrix[4]+z*matrix[8]+matrix[12],x*matrix[1]+y*matrix[5]+z*matrix[9]+matrix[13],x*matrix[2]+y*matrix[6]+z*matrix[10]+matrix[14])

func setup(id: String, directory: String="res://assets/client_roles/") -> void:
 actor_id=id
 asset_directory=directory
 viewport=SubViewport.new()
 viewport.size=Vector2i(256,256)
 viewport.transparent_bg=true
 viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
 add_child(viewport)
 var world=Node3D.new()
 viewport.add_child(world)
 pivot=Node3D.new()
 base_direction=PI
 direction=base_direction
 pivot.rotation.y=base_direction
 world.add_child(pivot)
 var camera=Camera3D.new()
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=4.5 if id in ["warrior","mage"] or id.begins_with("mob") or id.begins_with("pet") else 3.3
 camera.position=Vector3(3,2.8,5)
 world.add_child(camera)
 camera.look_at(Vector3(0,1.05,0))
 camera.current=true
 foot_anchor=camera.unproject_position(Vector3.ZERO)
 var cache_key:=directory+id
 if not resource_cache.has(cache_key): resource_cache[cache_key]=JSON.parse_string(FileAccess.get_file_as_string(directory+id+".json"))
 var parts: Array=resource_cache[cache_key]
 if FileAccess.file_exists(directory+id+"-actions.json"):
  if not resource_cache.has(cache_key+"-actions"): resource_cache[cache_key+"-actions"]=JSON.parse_string(FileAccess.get_file_as_string(directory+id+"-actions.json"))
  clips=resource_cache[cache_key+"-actions"]
 var attachments: Dictionary=parts[0].attachments
 var min_z:=0.0
 for part in parts:
  for point in part.posed_vertices: min_z=minf(min_z,float(point[2]))
 scale_factor=2.15/maxf(1,absf(min_z))
 add_parts(parts,[])
 if id in ["warrior","mage"]:
  var heads: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client_roles/"+id+"_head.json"))
  add_parts(heads,attachments.get("v_head",[]))
  var hair: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client_roles/"+id+"_hair.json"))
  add_parts(hair,attachments.get("v_head",[]))
  var weapons: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client_roles/"+id+"_weapon.json"))
  add_parts(weapons,attachments.get("v_r_weapon",[]))

func add_parts(parts: Array, attachment: Array) -> void:
 for part in parts:
  var points:=PackedVector3Array()
  for raw in part.posed_vertices:
   var p: Vector3=transform_point(raw,attachment) if attachment.size()==16 else Vector3(raw[0],raw[1],raw[2])
   points.append(Vector3(p.x,-p.z,p.y)*scale_factor)
  var uv:=PackedVector2Array()
  for pair in part.uv: uv.append(Vector2(pair[0],pair[1]))
  var arrays: Array=[]
  arrays.resize(Mesh.ARRAY_MAX)
  arrays[Mesh.ARRAY_VERTEX]=points
  arrays[Mesh.ARRAY_TEX_UV]=uv
  arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(part.indices)
  var mesh=ArrayMesh.new()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  var instance=MeshInstance3D.new()
  instance.mesh=mesh
  var material=StandardMaterial3D.new()
  material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
  material.cull_mode=BaseMaterial3D.CULL_DISABLED
  material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
  material.alpha_scissor_threshold=0.2
  var texture_path: String=asset_directory+str(part.texture_file)
  material.albedo_texture=load(texture_path) if ResourceLoader.exists(texture_path) else ImageTexture.create_from_image(Image.load_from_file(texture_path))
  instance.material_override=material
  pivot.add_child(instance)
  sources.append({"instance":instance,"points":points,"arrays":arrays,"body":sources.is_empty()})

func set_movement(displacement: Vector2) -> void:
 moving=displacement.length()>0.05
 if moving: direction=atan2(displacement.x,displacement.y)+0.54+base_direction
 pivot.rotation.y=direction
 if enabled: viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func set_active(value: bool) -> void:
 enabled=value
 viewport.render_target_update_mode=SubViewport.UPDATE_ONCE if value else SubViewport.UPDATE_DISABLED

func play_attack(facing: Vector2=Vector2.ZERO) -> void:
 if facing.length()>0.05: direction=atan2(facing.x,facing.y)+0.54+base_direction
 attack_remaining=float(clips.attack.duration) if clips.has("attack") else 0.48
 attack_serial+=1
 animation_clock=0

func apply_original_frame(action: String) -> void:
 var clip: Dictionary=clips[action]
 var index:=mini(int(animation_clock/float(clip.duration)*clip.frames.size()),clip.frames.size()-1)
 var frame: Array=clip.frames[index]
 for part_index in range(sources.size()):
  var points:=PackedVector3Array()
  for raw in frame[part_index]: points.append(Vector3(raw[0],-raw[2],raw[1])*scale_factor)
  var source: Dictionary=sources[part_index]
  var arrays: Array=source.arrays.duplicate()
  arrays[Mesh.ARRAY_VERTEX]=points
  var mesh=ArrayMesh.new()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  source.instance.mesh=mesh

func _process(dt: float) -> void:
 if get_parent().has_method("update_walk"):
  var game=get_parent()
  if game.state!="play" or game.dialog_npc>=0 or (game.player_ui!=null and game.player_ui.opened>=0): return
 var was_attacking:=attack_remaining>0
 attack_remaining=maxf(0,attack_remaining-dt)
 animation_clock+=dt
 if not enabled: return
 if not clips.is_empty():
  var action:="attack" if attack_remaining>0 else ("walk" if moving else "idle")
  if animation_clock>=float(clips[action].duration): animation_clock=fmod(animation_clock,float(clips[action].duration))
  elapsed+=dt
  if elapsed>=0.08:
   elapsed=0
   pivot.rotation.y=direction
   apply_original_frame(action)
   viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
  return
 if moving and get_parent().has_method("update_walk") and not get_parent().walking: moving=false
 if not moving and phase==0 and not was_attacking: return
 elapsed+=dt
 if elapsed<0.08: return
 elapsed=0
 phase=phase+0.65 if moving else 0
 # Lightweight fallback gait on the original mesh. This is not an original
 # client walk animation: lower body strides, torso/cape follow the same beat.
 for source in sources:
  var points: PackedVector3Array=source.points.duplicate()
  if moving:
   for i in range(points.size()):
    var p:=points[i]
    if source.body and p.y<1.0:
     var side:=1.0 if p.x>0 else -1.0
     var stride:=sin(phase+side*PI/2)
     var weight:=clampf(1.0-p.y,0,1)
     p.z+=stride*0.16*weight
     p.y+=maxf(0,stride)*0.06*weight
    p.y+=absf(sin(phase))*0.025
    p.x+=sin(phase)*0.01*clampf(p.y,0,2)
    points[i]=p
  if attack_remaining>0:
   var t:=1.0-attack_remaining/0.48
   var swing:=sin(t*PI)
   for i in range(points.size()):
    var p:=points[i]
    var weight:=clampf((p.y-0.65)/0.9,0,1)
    var angle:=swing*0.65*weight
    var turned:=Vector2(p.x,p.z).rotated(angle)
    p.x=turned.x
    p.z=turned.y-swing*0.09
    p.y-=swing*0.06
    if source==sources.back():
     var wrist:=Vector3(0.35,1.15,0)
     p=wrist+(p-wrist).rotated(Vector3.FORWARD,(-0.75+t*1.7)*swing)
    points[i]=p
  var arrays: Array=source.arrays.duplicate()
  arrays[Mesh.ARRAY_VERTEX]=points
  var mesh=ArrayMesh.new()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  source.instance.mesh=mesh
 viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func texture() -> Texture2D:
 return viewport.get_texture()
