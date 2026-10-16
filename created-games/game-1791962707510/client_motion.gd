extends RefCounted
## Native ANI local keyframes, reflected from client left-handed coordinates.
static var cache: Dictionary={}
static func clip(stem: String) -> Dictionary:
 if not cache.has(stem):
  var path: String="res://assets/client-actions/"+stem+".json"
  cache[stem]=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
  if not cache[stem].is_empty():
   for track in cache[stem].tracks:
    var orientation:=Quaternion.IDENTITY
    var absolute: Array=[]
    for key in track.rotation:
     # Source row-vector increments act on the left after conversion to Godot columns.
     orientation=(rotation_key(key)*orientation).normalized()
     absolute.append([key[0],orientation.x,orientation.y,orientation.z,orientation.w])
    track.rotation=absolute
 return cache[stem]
static func vector(values: Array, offset: int=0) -> Vector3:
 return Vector3(values[offset],values[offset+1],values[offset+2])
static func rotation_key(key: Array) -> Quaternion:
 var axis:=vector(key,1)
 return Quaternion(axis.normalized(),float(key[4])) if axis.length_squared()>0.000001 else Quaternion.IDENTITY
static func sample(keys: Array, tick: float, rotation: bool) -> Variant:
 var a: Array=keys[0]
 var b: Array=a
 for key in keys:
  if float(key[0])<=tick:a=key
  if float(key[0])>=tick:b=key;break
  b=key
 var weight: float=clampf((tick-float(a[0]))/maxf(1,float(b[0])-float(a[0])),0,1)
 if rotation:return Quaternion(a[1],a[2],a[3],a[4]).slerp(Quaternion(b[1],b[2],b[3],b[4]),weight)
 return vector(a,1).lerp(vector(b,1),weight)
static func apply(rig: Node3D, stem: String, fraction: float, blend: float=1.0) -> void:
 var data: Dictionary=clip(stem)
 if data.is_empty():return
 var tick: float=clampf(fraction,0,1)*float(data.ticks)
 for skeleton in rig.skeletons:
  for track in data.tracks:
   var index: int=skeleton.find_bone(track.name)
   if index<0 or track.name=="Bip01_Footsteps":continue
   var m: Array=track.matrix
   var basis:=Basis(vector(m,0),vector(m,4),vector(m,8)).orthonormalized()
   var rotation: Quaternion=sample(track.rotation,tick,true) if not track.rotation.is_empty() else basis.get_rotation_quaternion()
   var at: Vector3=sample(track.position,tick,false) if not track.position.is_empty() else vector(m,12)
   if track.name=="Bip01":
    var start: Vector3=vector(track.position[0],1) if not track.position.is_empty() else vector(m,12)
    at=skeleton.get_bone_rest(index).origin+Vector3(0,clampf(at.y-start.y,-0.3,1.5),0)
   skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index).slerp(rotation,blend))
   skeleton.set_bone_pose_position(index,skeleton.get_bone_pose_position(index).lerp(at,blend))
