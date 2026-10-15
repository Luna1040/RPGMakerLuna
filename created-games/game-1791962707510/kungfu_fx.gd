extends Node3D
var game: Node
var puffs: Array[Dictionary]=[]
var emit_clock:=0.0
var dust_count:=0
var meditation_ring: MeshInstance3D
var meditation_clock:=0.0
func material(texture: String, additive: bool) -> StandardMaterial3D:
 var mat:=StandardMaterial3D.new()
 mat.albedo_texture=load("res://assets/client-skills/"+texture)
 mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
 mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
 mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 mat.no_depth_test=false
 return mat
func emit(texture: String, at: Vector3, duration: float, size: float, additive: bool, follow: bool=false) -> void:
 if puffs.size()>96:return
 var mesh:=MeshInstance3D.new()
 var quad:=QuadMesh.new()
 quad.size=Vector2(size,size)
 mesh.mesh=quad
 mesh.material_override=material(texture,additive)
 mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 mesh.position=at
 add_child(mesh)
 puffs.append({"mesh":mesh,"life":duration,"max":duration,"base_size":size,"follow":follow,"offset":at-game.hero.position,"additive":additive})
func cast(id: String) -> void:
 for i in range(puffs.size()-1,-1,-1):
  if puffs[i].follow:
   puffs[i].mesh.queue_free()
   puffs.remove_at(i)
 var layers:=6 if id=="cloud_step" else 3
 for i in range(layers):
  emit("cloud_wind.png" if id=="cloud_step" else "wind.png",game.hero.position+Vector3(0,0.3+i*0.22,0),3.2,0.7+i*0.16,true,true)
func _process(dt: float) -> void:
 if game.hero==null or game.paused or game.menu.visible or game.dialogue.visible:return
 if game.meditating and game.hp>0:
  if not is_instance_valid(meditation_ring):
   meditation_ring=MeshInstance3D.new()
   var plane:=PlaneMesh.new()
   plane.size=Vector2(2.1,2.1)
   meditation_ring.mesh=plane
   var mat:=material("wungi.png",true)
   mat.billboard_mode=BaseMaterial3D.BILLBOARD_DISABLED
   mat.albedo_color=Color(0.25,0.6,0.3,0.35)
   meditation_ring.material_override=mat
   meditation_ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   add_child(meditation_ring)
  meditation_ring.position=game.hero.position+Vector3(0,0.06,0)
  meditation_ring.rotation.y+=dt*0.3
  meditation_clock-=dt
  if meditation_clock<=0:
   meditation_clock=0.14
   emit("particle.png",game.hero.position+Vector3(randf_range(-0.55,0.55),0.3,randf_range(-0.55,0.55)),1.6,0.13,true)
 elif is_instance_valid(meditation_ring):
  meditation_ring.queue_free()
  meditation_ring=null
 var moving:=Vector2(game.hero.velocity.x,game.hero.velocity.z).length()>0.1
 if game.lightness and moving and game.hp>0:
  emit_clock-=dt
  if emit_clock<=0:
   emit_clock=0.09
   var behind: Vector3=-game.hero.velocity.normalized()*0.45
   emit("dust_gray.png",game.hero.position+behind+Vector3(randf_range(-0.12,0.12),0.2,randf_range(-0.12,0.12)),0.8,0.4,false)
   dust_count+=1
 else:emit_clock=0.0
 for i in range(puffs.size()-1,-1,-1):
  var puff: Dictionary=puffs[i]
  puff.life-=dt
  if puff.life<=0:
   puff.mesh.queue_free()
   puffs.remove_at(i)
   continue
  var t: float=1.0-puff.life/puff.max
  var mesh: MeshInstance3D=puff.mesh
  if puff.follow:mesh.position=game.hero.position+puff.offset
  else:mesh.position.y+=dt*0.2
  mesh.scale=Vector3.ONE*(1+t*1.6)
  var mat: StandardMaterial3D=mesh.material_override
  var alpha:=sin(PI*t)*(0.16 if puff.additive else 0.65)
  mat.albedo_color=Color(0.65,0.8,0.85,alpha) if puff.additive else Color(0.62,0.6,0.56,alpha)
