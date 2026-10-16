extends "res://city_3d.gd"
const Advanced=preload("res://kungfu_data.gd")
var promotion_stage := 0
var promotion_boar := 0
var promotion_bones := 0
var progression_ui: CanvasLayer
var native_attack_remaining := 0.0
var native_attack_duration := 0.55
var native_attack_skill := false
var martial_cd := 0.0
var strike_timer := 0.0
var strike_target := -1
var strike_skill := ""
var skill_damage_bonus := 0
var queued_skill := ""
var queued_target := -1
var skill_repath := 0.0

func _ready() -> void:
 super._ready()
 progression_ui=preload("res://progression_ui.gd").new()
 progression_ui.game=self
 progression_ui.name="ProgressionUI"
 add_child(progression_ui)

func reset_game() -> void:
 promotion_stage=0
 promotion_boar=0
 promotion_bones=0
 queued_skill=""
 strike_skill=""
 native_attack_remaining=0
 super.reset_game()

func snapshot() -> Dictionary:
 var data:=super.snapshot()
 data["advancement"]={"stage":promotion_stage,"boar":promotion_boar,"bones":promotion_bones}
 return data

func restore(data: Dictionary) -> void:
 var saved: Dictionary=data.get("advancement",{})
 promotion_stage=int(saved.get("stage",0))
 promotion_boar=int(saved.get("boar",0))
 promotion_bones=int(saved.get("bones",0))
 queued_skill=""
 strike_skill=""
 strike_timer=0
 martial_cd=0
 native_attack_remaining=0
 if is_instance_valid(progression_ui):progression_ui.reset_windows()
 super.restore(data)
 # The base restore resets per-character gameplay before applying its save fields.
 promotion_stage=int(saved.get("stage",0))
 promotion_boar=int(saved.get("boar",0))
 promotion_bones=int(saved.get("bones",0))
 legacy_archive.erase("advancement")
 hp=clampf(float(data.get("hp",hp)),0,max_hp())
 qi=clampf(float(data.get("qi",100)),0,max_qi())

func max_hp() -> float:
 return super.max_hp()+(50 if promotion_stage==14 else 0)
func max_qi() -> float:
 return 150.0 if promotion_stage==14 else 100.0
func attack_power() -> int:
 return super.attack_power()+skill_damage_bonus+(2 if promotion_stage==14 else 0)
func defense_power() -> int:
 return super.defense_power()+(2 if promotion_stage==14 else 0)
func role_code() -> String:
 return {"刀客":"blade","剑客":"sword","枪客":"spear"}.get(Saves.display_profession(character.get("profession","刀客")),"blade")
func rank_title() -> String:
 return {"blade":"刀杰","sword":"剑侠","spear":"枪豪"}[role_code()] if promotion_stage==14 else "未升职"
func available_skills() -> Array:
 return ["attack",role_code()+"_10","lightness","cloud_step"]
func learn_skill(id: String) -> bool:
 var info: Dictionary=Advanced.DATA.get(id,{})
 if info.has("role"):
  if info.role!=role_code() or promotion_stage!=14:
   message="完成第一次升职后，方可修习本职业十级武功。"
   return false
 return super.learn_skill(id)

func start_native_attack(special: bool=false) -> void:
 native_attack_duration=0.68 if special else 0.55
 native_attack_remaining=native_attack_duration
 native_attack_skill=special

func attack_monster(id: int) -> void:
 if id<0 or id>=monsters.size():return
 var old_hp: float=monsters[id].hp
 super.attack_monster(id)
 if monsters[id].hp<old_hp:
  start_native_attack()
  if monsters[id].dead:promotion_kill(monsters[id].species)

func attack_practice() -> void:
 var old_hp:=enemy_health
 super.attack_practice()
 if enemy_health<old_hp:start_native_attack()

func navigate_to(at: Vector3, target: String="") -> void:
 queued_skill=""
 super.navigate_to(at,target)
func navigate_to_actor(actor: Node3D, kind: String) -> void:
 queued_skill=""
 super.navigate_to_actor(actor,kind)
func select_monster(id: int) -> void:
 queued_skill=""
 super.select_monster(id)

func use_skill(id: String) -> bool:
 var info: Dictionary=Advanced.DATA.get(id,{})
 if not info.has("role"):
  queued_skill=""
  if native_attack_remaining>0 and id=="attack":return false
  var ok:=super.use_skill(id)
  if ok and id=="attack" and slash_remaining>0:start_native_attack()
  return ok
 if hp<=0 or active_slot==0 or paused or not id in learned_skills or level<10 or promotion_stage!=14 or info.role!=role_code():return false
 if martial_cd>0 or strike_timer>0:
  message="武功尚在调息。"
  return false
 if qi<float(info.cost):message="内力不足，可打坐恢复内力。";return false
 if selected_monster<0 or selected_monster>=monsters.size() or monsters[selected_monster].dead:
  message="请先选中一只野怪，再施展攻击武功。"
  return false
 if hero.position.distance_to(monsters[selected_monster].body.position)>2.0:
  navigate_to_actor(monsters[selected_monster].body,"")
  queued_skill=id
  queued_target=selected_monster
  skill_repath=0.5
  message="正在接近目标，进入距离后施展 "+str(info.name)
  return true
 queued_skill=""
 route.clear()
 click_target=""
 meditating=false
 qi-=float(info.cost)
 martial_cd=2.0
 strike_timer=0.36
 strike_target=selected_monster
 strike_skill=id
 hero.velocity=Vector3.ZERO
 var direction: Vector3=monsters[strike_target].body.position-hero.position
 hero_model.root.rotation.y=atan2(direction.x,direction.z)
 start_native_attack(true)
 message="施展 "+str(info.name)
 return true

func resolve_martial_strike() -> void:
 if strike_target<0 or strike_target>=monsters.size() or monsters[strike_target].dead:return
 if hero.position.distance_to(monsters[strike_target].body.position)>2.5:
  message="目标已离开武功范围。"
  return
 skill_damage_bonus=int(Advanced.DATA[strike_skill].power)
 var old_hp: float=monsters[strike_target].hp
 attack_cd=0
 super.attack_monster(strike_target)
 skill_damage_bonus=0
 if monsters[strike_target].hp<old_hp:
  if is_instance_valid(kungfu_fx):kungfu_fx.martial_hit(monsters[strike_target].body.position,role_code())
  if monsters[strike_target].dead:promotion_kill(monsters[strike_target].species)

func _process(dt: float) -> void:
 super._process(dt)
 if hero==null or active_slot==0 or menu.visible:return
 if hp<=0:
  message="身受重伤 · 请在弹窗中确认回城疗伤。"
  if is_instance_valid(progression_ui):progression_ui.show_death()
  return
 if paused or dialogue.visible:return
 if promotion_stage==0 and level>=10:
  promotion_stage=1
  message="收到泫渤派门主的飞鸽传书 · 点击右侧飞鸽查看第一次升职任务。"
 native_attack_remaining=maxf(0,native_attack_remaining-dt)
 hero_model.root.rotation.z=0
 martial_cd=maxf(0,martial_cd-dt)
 if meditating:qi=minf(max_qi(),qi+dt*5)
 if strike_timer>0:
  strike_timer=maxf(0,strike_timer-dt)
  if strike_timer<=0:resolve_martial_strike()
 if not queued_skill.is_empty():
  if queued_target<0 or queued_target>=monsters.size() or monsters[queued_target].dead:
   queued_skill=""
  else:
   skill_repath-=dt
   if hero.position.distance_to(monsters[queued_target].body.position)<=2:
    selected_monster=queued_target
    var id:=queued_skill
    queued_skill=""
    use_skill(id)
   elif skill_repath<=0:
    var pending:=queued_skill
    navigate_to_actor(monsters[queued_target].body,"")
    queued_skill=pending
    skill_repath=0.5

func confirm_return_to_town() -> void:
 if hp>0:return
 hp=max_hp()
 qi=max_qi()
 meditating=false
 lightness=false
 lightness_remaining=0
 glide_remaining=0
 route.clear()
 click_target=""
 selected_monster=-1
 queued_skill=""
 strike_timer=0
 native_attack_remaining=0
 martial_cd=0
 attack_cd=0
 slash_remaining=0
 leap_remaining=0
 var cell:=free_cell(Vector3(0,0,3.5))
 var at:=Vector2(cell)*CELL
 hero.position=Vector3(at.x,surface_height(at)+0.05,at.y)
 hero.velocity=Vector3.ZERO
 for mob in monsters:
  mob.aggro=false
  mob.wind=0
  mob.path=PackedVector2Array()
 dialogue.hide()
 paused=false
 progression_ui.reset_windows()
 update_region()
 update_camera(1,true)
 message="已回到泫渤派疗伤 · 等级、物品和任务进度保留。"
 save_character()

func promotion_target() -> String:
 match promotion_stage:
  3,7:return "银娇龙"
  4,6:return "金香玉"
  5:return "野猪"
  8,12:return "刀剑笑"
  9,11:return "平十指"
  10:return "灰狼"
 return "泫渤派门主"
func promotion_description() -> String:
 match promotion_stage:
  0:return "达到十级后，门主将以飞鸽传书召见。"
  1,2:return "阅读门主飞鸽，前往门主处申请第一次升职。"
  3:return "向银娇龙打听警备团甲衣的消息。"
  4:return "前往金香玉处，为银娇龙准备美食。"
  5:return "猎杀野猪，取得野猪后腿 1 个（%d/1）。" % promotion_boar
  6:return "将野猪后腿交给金香玉，制成野猪烧烤。"
  7:return "把野猪烧烤交给银娇龙，取得警备团甲衣。"
  8:return "前往刀剑笑处打听警备团兵器。"
  9:return "刀剑笑受伤了，向平十指求取伤药。"
  10:return "猎杀灰狼，取得灰狼之骨 3 个（%d/3）。" % promotion_bones
  11:return "将灰狼之骨交给平十指，取得刀剑笑的药。"
  12:return "把伤药交给刀剑笑，取得警备团兵器。"
  13:return "携甲衣与兵器回禀门主，完成第一次升职。"
 return "第一次升职已完成 · "+rank_title()
func guide_promotion() -> void:
 queued_skill=""
 dialogue.hide()
 var target:=promotion_target()
 if target in ["野猪","灰狼"]:
  for mob in monsters:
   if mob.species==target and not mob.dead:
    navigate_to(mob.home+Vector3(2,0,0))
    message="自动寻路前往 "+target+" 活动区；选中后进行战斗。"
    return
 elif town_actors.has(target):navigate_to_actor(town_actors[target],"master" if target=="泫渤派门主" else "npc:"+target)
func accept_promotion() -> void:
 if promotion_stage not in [1,2] or level<10:return
 promotion_stage=3
 message="已接受第一次升职任务 · "+promotion_description()
 progression_ui.close_letter()
 save_character()
func promotion_kill(species: String) -> void:
 if promotion_stage==5 and species=="野猪":
  promotion_boar=1
  promotion_stage=6
  message+=" · 获得任务物品：野猪后腿"
 elif promotion_stage==10 and species=="灰狼":
  promotion_bones=mini(3,promotion_bones+1)
  message+=" · 灰狼之骨 %d/3" % promotion_bones
  if promotion_bones==3:promotion_stage=11
func talk_master() -> void:
 var toward:=hero.position-master.position
 master.get_node("VisualBody").rotation.y=atan2(toward.x,toward.z)
 if promotion_stage in [1,2]:
  click_target=""
  route.clear()
  progression_ui.open_letter(true)
  return
 if promotion_stage==13:
  promotion_stage=14
  coins+=10000
  gain_experience(200)
  hp=max_hp()
  qi=max_qi()
  message="第一次升职完成！授予「%s」称号 · 银两 +10000 · 经验 +200 · 生命与内力上限 +50。" % rank_title()
  click_target=""
  route.clear()
  show_dialogue("泫渤派门主")
  save_character()
  return
 if promotion_stage>=3 and promotion_stage<14:
  message=promotion_description()
  click_target=""
  route.clear()
  show_dialogue("泫渤派门主")
  return
 super.talk_master()
func talk_town_npc(title: String) -> void:
 var advance:=false
 match promotion_stage:
  3:advance=title=="银娇龙"
  4,6:advance=title=="金香玉"
  7:advance=title=="银娇龙"
  8,12:advance=title=="刀剑笑"
  9,11:advance=title=="平十指"
 if advance:
  promotion_stage+=1
  var toward: Vector3=hero.position-town_actors[title].position
  town_actors[title].get_node("VisualBody").rotation.y=atan2(toward.x,toward.z)
  route.clear()
  click_target=""
  message=promotion_description()
  show_dialogue(title)
  save_character()
 else:super.talk_town_npc(title)
