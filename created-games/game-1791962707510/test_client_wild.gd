extends SceneTree
var game: Node
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
 if not ok: failures+=1; push_error(title)
func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
  await process_frame
func bone_state(rig: Node) -> Array:
 var states: Array=[]
 for sk in rig.skeletons:
  for i in range(sk.get_bone_count()):states.append(sk.get_bone_pose_rotation(i))
 return states
func run() -> void:
 game=load("res://main.tscn").instantiate()
 root.add_child(game)
 await frames(4)
 game.active_slot=1
 game.character={"name":"动作测试","profession":"刀客"}
 game.menu.hide()
 game.paused=false
 game.apply_profession_model()
 check(game.hero_model.root.get_child(0).scene_file_path.ends_with("CMK00010.glb"),"Blade K source")
 check(not game.shadow.visible,"No round player marker")
 var weapon: MeshInstance3D=game.hero_model.root.find_children("ClientWeapon","MeshInstance3D",true,false)[0]
 check(weapon.mesh.resource_path.ends_with("WCK001.obj"),"Blade K weapon source")
 var rig: Node=game.hero_model.root
 game.hero.velocity=Vector3.ZERO
 rig._process(0.1)
 var idle:=bone_state(rig)
 rig._process(0.7)
 check(idle==bone_state(rig),"Hero idle is motionless")
 game.hero.velocity=Vector3(1,0,0)
 rig._process(0.13)
 var walk:=bone_state(rig)
 rig._process(0.13)
 check(walk!=bone_state(rig),"Hero walk moves bones")
 game.hero.velocity=Vector3.ZERO
 game.slash_remaining=0.25
 rig.get_node("RightArm").rotation.x=-1.2
 rig._process(0.1)
 check(idle!=bone_state(rig),"Hero attack moves arm torso")
 game.slash_remaining=0
 for title in game.NPC_NAMES:
  var npc: Node=game.town_actors[title].get_node("VisualBody")
  var before:=bone_state(npc)
  npc._process(1)
  check(before==bone_state(npc) and not npc.is_processing(),"NPC fixed pose "+title)
 var species: Dictionary={}
 for mob in game.monsters:
  species[mob.species]=true
  check(mob.visual.get_meta("client_monster",0)>0,"Native monster")
  mob.visual.animate(1,-1,0.13)
  check(mob.visual.animation_state=="walk","Monster walk")
  mob.visual.animate(0,0.4,0.1)
  check(mob.visual.animation_state=="attack","Monster attack")
  mob.visual.animate(0,-1,0.1)
  check(mob.visual.animation_state=="idle","Monster idle")
 check(species.size()==6,"Six original species")
 var initial: Array=[]
 for mob in game.monsters:initial.append(mob.body.position)
 await frames(500)
 var moved:=0
 for i in range(game.monsters.size()):
  var mob: Dictionary=game.monsters[i]
  if mob.body.position.distance_to(initial[i])>0.2:moved+=1
  check(mob.body.position.distance_to(mob.home)<4.1,"Roam stays in home range")
  check(game.walkable(Vector2(mob.body.position.x,mob.body.position.z)),"Roam stays on map")
 check(moved>20,"Random slow movement visible")
 print("ROAM_MOVED=",moved)
 var target: Dictionary=game.monsters[0]
 game.hero.position=target.body.position+Vector3(0,0,1.0)
 game.hero.velocity=Vector3.ZERO
 game.attack_cd=0
 var enemy_before: float=target.hp
 game.attack_monster(0)
 check(target.hp<enemy_before and game.slash_remaining>0,"Hero attack damages monster and starts action")
 target.aggro=true
 target.cool=0
 target.wind=0
 game.update_monster(target,0.01)
 check(target.wind>0,"Monster starts telegraphed attack")
 var hero_before: float=game.hp
 game.update_monster(target,0.6)
 check(game.hp<hero_before,"Monster attack resolves damage")
 game.active_slot=0
 game.queue_free()
 await frames(2)
 print("CLIENT_WILD_PASS" if failures==0 else "CLIENT_WILD_FAIL")
 quit(1 if failures else 0)
