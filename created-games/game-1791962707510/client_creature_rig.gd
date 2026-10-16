extends Node3D
const IDS := {"野猫":10001,"蛤蟆":10007,"狐狸":10015,"野猪":10013,"狂牛":10002,"灰狼":10009}
var skeleton: Skeleton3D
var bases: Array[Basis]=[]
var phase := 0.0
var species := ""
var model: Node3D
var base_y := 0.0
var animation_state := "idle"

static func make(parent: Node3D, title: String) -> Node3D:
 var rig=load("res://client_creature_rig.gd").new()
 rig.name="ClientCreature"
 rig.species=title
 parent.add_child(rig)
 rig.model=(load("res://assets/client-wild/MOB%05d.glb" % IDS[title]) as PackedScene).instantiate()
 rig.add_child(rig.model)
 rig.skeleton=rig.model.find_children("*","Skeleton3D",true,false)[0]
 for i in range(rig.skeleton.get_bone_count()): rig.bases.append(rig.global_rest(i).basis)
 var mesh: MeshInstance3D=rig.model.find_children("*","MeshInstance3D",true,false)[0]
 var bounds:=mesh.get_aabb()
 var target: float={"野猫":0.62,"蛤蟆":0.58,"狐狸":0.76,"野猪":1.0,"狂牛":1.28,"灰狼":0.92}[title]
 var factor:=target/maxf(0.01,bounds.size.y)
 rig.model.scale=Vector3.ONE*factor
 rig.base_y=-bounds.position.y*factor
 rig.model.position.y=rig.base_y
 rig.set_meta("client_monster",IDS[title])
 rig.set_meta("height",target)
 return rig

func global_rest(index: int) -> Transform3D:
 var local:=skeleton.get_bone_rest(index)
 var parent:=skeleton.get_bone_parent(index)
 return global_rest(parent)*local if parent>=0 else local

func pose(title: String, angles: Vector3) -> void:
 var index:=skeleton.find_bone(title)
 if index<0: return
 var basis: Basis=bases[index]
 var rotation:=basis.inverse()*Basis.from_euler(angles)*basis
 skeleton.set_bone_pose_rotation(index,(skeleton.get_bone_rest(index).basis*rotation).get_rotation_quaternion())

func animate(speed: float, attack_progress: float, dt: float) -> void:
 var walking:=speed>0.08 and attack_progress<0
 animation_state="attack" if attack_progress>=0 else "walk" if walking else "idle"
 phase=phase+dt*(6.5 if speed<1.5 else 10) if walking else 0.0
 var stride:=sin(phase)*0.38 if walking else 0.0
 var strike:=sin(clampf(attack_progress,0,1)*PI) if attack_progress>=0 else 0.0
 for side in ["L","R"]:
  var sign_value:=1.0 if side=="L" else -1.0
  pose("Bip01_"+side+"_Thigh",Vector3(stride*sign_value,0,0))
  pose("Bip01_"+side+"_Calf",Vector3(maxf(0,-stride*sign_value)*0.9,0,0))
  pose("Bip01_"+side+"_UpperArm",Vector3(-stride*sign_value-strike*0.45,0,0))
  pose("Bip01_"+side+"_Forearm",Vector3(maxf(0,stride*sign_value)*0.7,0,0))
 pose("Bip01_Spine1",Vector3(-strike*0.22,0,stride*0.08))
 pose("Bip01_Head",Vector3(strike*0.4,0,0))
 pose("Bip01_Tail",Vector3(0,stride*0.2,0))
 model.position.y=base_y+(absf(sin(phase))*0.10 if walking and species=="蛤蟆" else 0.0)
 model.position.z=strike*0.22
