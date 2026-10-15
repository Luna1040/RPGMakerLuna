extends Node3D
## Real client skeletons and vertex weights; runtime poses are procedural, not original ANI clips.
const DIR := "res://assets/client-actors/"
var skeletons: Array[Skeleton3D]=[]
var rest_bases: Dictionary={}
var npc := false
var npc_id := -1
var phase := 0.0

static func make(parent: Node, path: String) -> Dictionary:
 var root=load("res://client_actor_rig.gd").new()
 root.name="VisualBody"
 parent.add_child(root)
 var basename:=path.get_file().get_basename()
 var index := -1
 if basename.begins_with("npc_"): index=int(basename.trim_prefix("npc_"))
 elif basename=="master": index=0
 root.npc=index>=0
 root.npc_id=index
 var stems: Array[String]=[]
 var weapon: String=""
 if root.npc:
  stems.append(["MOB00006","MOB00005","MOB00001","MOB00003","MOB00002","MOB00004"][index])
 else:
  var profession: String="剑客" if basename in ["class_sword","practice"] else ("枪客" if basename=="class_spear" else "刀客")
  stems.append({"刀客":"CMK00010","剑客":"CMS00010","枪客":"CMB00010"}[profession])
  for prefix in ["HM","FM","MM","LM"]: stems.append(prefix+{"刀客":"K","剑客":"S","枪客":"B"}[profession]+"00010")
  weapon={"刀客":"WCK001","剑客":"WCH001","枪客":"WCB001"}[profession]
 for stem in stems:
  var folder := "res://assets/client-wild/" if stem.ends_with("K00010") else DIR
  var model: Node3D=(load(folder+stem+".glb") as PackedScene).instantiate()
  root.add_child(model)
  root.prepare_materials(model)
  for skeleton in model.find_children("*","Skeleton3D",true,false):
   root.skeletons.append(skeleton)
   var globals: Array[Basis]=[]
   for i in range(skeleton.get_bone_count()): globals.append(root.global_rest(skeleton,i).basis)
   root.rest_bases[skeleton.get_instance_id()]=globals
 for title in ["LeftLeg","RightLeg","LeftArm","RightArm","Robe","Ribbon"]:
  var proxy:=Node3D.new()
  proxy.name=title
  root.add_child(proxy)
 var sword:=MeshInstance3D.new()
 sword.name="Sword"
 sword.visible=false
 root.get_node("RightArm").add_child(sword)
 if not weapon.is_empty():
  var skeleton: Skeleton3D=root.skeletons[0]
  var id:=skeleton.find_bone("Bip01_R_Hand")
  if id>=0:
   var attachment:=BoneAttachment3D.new()
   attachment.bone_name=skeleton.get_bone_name(id)
   skeleton.add_child(attachment)
   var mesh:=MeshInstance3D.new()
   mesh.name="ClientWeapon"
   mesh.mesh=load(DIR+weapon+".obj")
   var rest: Transform3D=root.global_rest(skeleton,id)
   mesh.basis=rest.basis.inverse()*Basis.from_euler(Vector3(0,0,-0.16))
   attachment.add_child(mesh)
   root.prepare_materials(mesh)
 root.scale=Vector3.ONE*0.7
 root.set_meta("client_skinned",true)
 if root.npc:
  if not root.npc_id in [0,1,5]:
   for skeleton in root.skeletons:
    root.pose(skeleton,"Bip01_L_UpperArm",Vector3(0,0,-0.65))
    root.pose(skeleton,"Bip01_R_UpperArm",Vector3(0,0,0.65))
  root.set_process(false)
 return {"root":root,"left_leg":root.get_node("LeftLeg"),"right_leg":root.get_node("RightLeg"),"left_arm":root.get_node("LeftArm"),"right_arm":root.get_node("RightArm"),"robe":root.get_node("Robe"),"ribbon":root.get_node("Ribbon"),"sword":sword}

func global_rest(skeleton: Skeleton3D, id: int) -> Transform3D:
 var local:=skeleton.get_bone_rest(id)
 var parent:=skeleton.get_bone_parent(id)
 return global_rest(skeleton,parent)*local if parent>=0 else local

func pose(skeleton: Skeleton3D, title: String, euler: Vector3) -> void:
 var index:=skeleton.find_bone(title)
 if index<0: return
 var global_basis: Basis=rest_bases[skeleton.get_instance_id()][index]
 var rotation: Basis=global_basis.inverse()*Basis.from_euler(euler)*global_basis
 skeleton.set_bone_pose_rotation(index,(skeleton.get_bone_rest(index).basis*rotation).get_rotation_quaternion())

func _process(dt: float) -> void:
 var moving := false
 var attacking := false
 var sitting := false
 var owner_game := get_tree().current_scene
 if not npc and get_parent() is CharacterBody3D:
  var body: CharacterBody3D=get_parent()
  moving=Vector2(body.velocity.x,body.velocity.z).length()>0.1
  owner_game=body.get_parent().get_parent()
  if owner_game.paused: return
  attacking=owner_game.slash_remaining>0
  sitting=owner_game.meditating
 if npc: return
 phase=phase+dt*1.4 if moving else 0.0
 for skeleton in skeletons:
  if sitting:
   pose(skeleton,"Bip01_L_Thigh",Vector3(-1.25,0,-0.65))
   pose(skeleton,"Bip01_R_Thigh",Vector3(-1.25,0,0.65))
   pose(skeleton,"Bip01_L_Calf",Vector3(1.8,0,0))
   pose(skeleton,"Bip01_R_Calf",Vector3(1.8,0,0))
   pose(skeleton,"Bip01_L_UpperArm",Vector3(-0.55,0,-1.1))
   pose(skeleton,"Bip01_R_UpperArm",Vector3(-0.55,0,1.1))
   pose(skeleton,"Bip01_L_Forearm",Vector3(-0.8,0,0))
   pose(skeleton,"Bip01_R_Forearm",Vector3(-0.8,0,0))
   pose(skeleton,"Bip01_Spine1",Vector3(0,0,0))
   continue
  if npc and npc_id in [0,1,5]:
   pose(skeleton,"Bip01_Spine1",Vector3(sin(phase*1.8)*0.008,0,0))
   continue
  var swing := sin(phase*9.0)*0.5 if moving else 0.0
  var attack: float= $RightArm.rotation.x if attacking else 0.0
  pose(skeleton,"Bip01_L_UpperArm",Vector3(-swing,0,-0.65+absf(attack)*0.15))
  pose(skeleton,"Bip01_R_UpperArm",Vector3(attack*0.65 if attacking else swing,0,0.65+attack*0.9))
  var stride := sin(phase*9.0)*0.48 if moving else 0.0
  pose(skeleton,"Bip01_L_Thigh",Vector3(stride,0,0))
  pose(skeleton,"Bip01_L_Calf",Vector3(maxf(0,-sin(phase*9.0))*0.65 if moving else 0,0,0))
  pose(skeleton,"Bip01_R_Calf",Vector3(maxf(0,sin(phase*9.0))*0.65 if moving else 0,0,0))
  pose(skeleton,"Bip01_L_Foot",Vector3(-stride*0.25,0,0))
  pose(skeleton,"Bip01_R_Foot",Vector3(stride*0.25,0,0))
  pose(skeleton,"Bip01_Pelvis",Vector3(0,sin(phase*9.0)*0.05 if moving else 0,0))
  pose(skeleton,"Bip01_R_Thigh",Vector3(-stride,0,0))
  var twist := sin(phase*9.0)*0.06 if moving else 0.0
  if attacking: twist=-$RightArm.rotation.x*0.2
  pose(skeleton,"Bip01_Spine1",Vector3(0.04 if moving else 0,twist,0))
  pose(skeleton,"Bip01_Head",Vector3(0,-twist*0.4,0))
  pose(skeleton,"Bip01_L_Forearm",Vector3(-0.15 if moving else 0,0,0))
  pose(skeleton,"Bip01_R_Forearm",Vector3(attack*0.25 if attacking else -0.2 if moving else 0,0,0))


func prepare_materials(node: Node) -> void:
 if node is MeshInstance3D and node.mesh!=null:
  for surface in range(node.mesh.get_surface_count()):
   var material: Material=node.get_active_material(surface)
   if material==null: material=StandardMaterial3D.new()
   node.set_surface_override_material(surface,material.duplicate())
 for child in node.get_children(): prepare_materials(child)
