extends "res://progression_3d.gd"
const Items=preload("res://town_items.gd")
var inventory: Array=[]
var personal_storage: Array=[]
var shared_storage: Array=[]
var equipped: Dictionary={}
var services_ui: CanvasLayer
var storage_fault := false
var transaction_before: Dictionary={}

func _ready() -> void:
 storage_fault=not recover_transaction()
 super._ready()
 services_ui=preload("res://town_services_ui.gd").new()
 services_ui.game=self
 services_ui.name="TownServices"
 add_child(services_ui)
 var plates:=preload("res://npc_nameplates.gd").new()
 plates.game=self
 get_node("GameMenus").add_child(plates)

func build_world() -> void:
 super.build_world()
 for actor in town_actors.values():
  for child in actor.get_children():
   if child is Label3D:child.hide()
 for child in practice.get_children():
  if child is Label3D:child.text="练习刀客 Lv.1";child.font_size=32;child.pixel_size=0.009

func empty_slots(count: int) -> Array:
 var result: Array=[]
 for i in range(count):result.append({})
 return result

func reset_game() -> void:
 super.reset_game()
 inventory=empty_slots(40)
 inventory[0]={"id":"potion","count":potions}
 inventory[1]={"id":"return_scroll","count":10}
 personal_storage=empty_slots(200)
 equipped={}
 register_items()

func save_character(logout: bool=false) -> bool:
 if storage_fault:return false
 return super.save_character(logout)

func register_items() -> void:
 for id in Items.DATA:
  if Advanced.DATA.has(id) and not id in learned_skills:learned_skills.append(id)

func sync_potions() -> void:
 var index: int=-1
 for i in range(inventory.size()):
  if inventory[i].get("id")=="potion":
   if index<0:index=i
   else:inventory[i]={}
 if index>=0:inventory[index]={"id":"potion","count":potions} if potions>0 else {}
 elif potions>0:
  for i in range(inventory.size()):
   if inventory[i].is_empty():inventory[i]={"id":"potion","count":potions};break

func snapshot() -> Dictionary:
 sync_potions()
 var data:=super.snapshot()
 data["town_services"]={"version":1,"bag":inventory.duplicate(true),"personal":personal_storage.duplicate(true),"equipped":equipped.duplicate(true)}
 return data

func restore(data: Dictionary) -> void:
 var pending: Variant=saves.parse_file(saves.directory.path_join("warehouse_transaction.json")) if FileAccess.file_exists(saves.directory.path_join("warehouse_transaction.json")) else null
 if pending is Dictionary:
  if not recover_transaction():storage_fault=true;return
  if int(pending.character.slot)==active_slot:data=pending.character.progress;character=pending.character
 super.restore(data)
 var saved: Dictionary=data.get("town_services",{})
 inventory=saved.get("bag",empty_slots(40)).duplicate(true)
 personal_storage=saved.get("personal",empty_slots(200)).duplicate(true)
 equipped=saved.get("equipped",{}).duplicate(true)
 sync_potions()
 register_items()
 legacy_archive.erase("town_services")
 if is_instance_valid(services_ui):services_ui.close()
 load_shared()

func shared_path() -> String:
 return saves.directory.path_join("shared_warehouse.json")

func atomic_json(path: String, data: Variant) -> bool:
 if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK:return false
 var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
 if file==null:return false
 file.store_string(JSON.stringify(data))
 file.flush()
 var ok:=file.get_error()==OK
 file.close()
 if not ok:return false
 if FileAccess.file_exists(path):
  if DirAccess.copy_absolute(path,path+".bak")!=OK:return false
 return DirAccess.rename_absolute(path+".tmp",path)==OK

func recover_transaction() -> bool:
 var path:=saves.directory.path_join("warehouse_transaction.json")
 if not FileAccess.file_exists(path):return true
 var record: Variant=saves.parse_file(path)
 if not record is Dictionary or not record.get("character") is Dictionary:return false
 var role: Dictionary=record.character
 if not saves.valid(role,int(role.get("slot",0))) or not Items.valid_slots(record.get("shared"),200):return false
 if not atomic_json(shared_path(),{"version":1,"slots":record.shared}):return false
 if not saves.write_slot(int(role.slot),role):return false
 return DirAccess.remove_absolute(path)==OK

func load_shared() -> bool:
 storage_fault=not recover_transaction()
 if storage_fault:message="仓库事务尚未完成，请检查存档目录权限。";return false
 var path:=shared_path()
 shared_storage=empty_slots(200)
 if not FileAccess.file_exists(path):return true
 var saved: Variant=saves.parse_file(path)
 # An older shared backup cannot be replayed alone: a completed withdrawal may
 # already exist in a character save. Preserve both files and stop instead.
 if not saved is Dictionary or saved.get("version")!=1 or not Items.valid_slots(saved.get("slots"),200):
  storage_fault=true
  message="综合仓库存档损坏，已停止存取并保留原文件。"
  return false
 shared_storage=saved.slots.duplicate(true)
 return true

func commit_services() -> bool:
 sync_potions()
 character.level=level
 character.progress=snapshot()
 character.saved_at=Saves.utc_plus_8(int(Time.get_unix_time_from_system()))
 var transaction: Dictionary={"character":character.duplicate(true),"shared":shared_storage.duplicate(true)}
 if not saves.valid(character,active_slot) or not atomic_json(saves.directory.path_join("warehouse_transaction.json"),transaction):
  if not transaction_before.is_empty():
   inventory=transaction_before.bag
   personal_storage=transaction_before.personal
   shared_storage=transaction_before.shared
   equipped=transaction_before.equipped
   coins=transaction_before.coins
   hp=transaction_before.hp
   qi=transaction_before.qi
   hero.position=transaction_before.position
   recount_potions()
  storage_fault=true
  message="无法保存物品事务，已停止存取。"
  return false
 storage_fault=not recover_transaction()
 if storage_fault:message="物品事务待恢复，暂时无法继续存取。"
 return not storage_fault

func begin_transaction() -> void:
 transaction_before={"bag":inventory.duplicate(true),"personal":personal_storage.duplicate(true),"shared":shared_storage.duplicate(true),"equipped":equipped.duplicate(true),"coins":coins,"hp":hp,"qi":qi,"position":hero.position}

func add_item(slots: Array, id: String, count: int=1) -> bool:
 var maximum: int=Items.DATA[id].get("stack",999)
 var capacity:=0
 for entry in slots:
  if entry.is_empty():capacity+=maximum
  elif entry.id==id:capacity+=maximum-int(entry.count)
 if capacity<count:return false
 for i in range(slots.size()):
  if not slots[i].is_empty() and slots[i].id==id:
   var amount:=mini(count,maximum-int(slots[i].count))
   slots[i].count+=amount
   count-=amount
 for i in range(slots.size()):
  if count<=0:break
  if slots[i].is_empty():
   var amount:=mini(count,maximum)
   slots[i]={"id":id,"count":amount}
   count-=amount
 return true

func item_count(id: String) -> int:
 if id=="potion":return potions
 var count:=0
 for entry in inventory:
  if entry.get("id")==id:count+=int(entry.count)
 return count

func recount_potions() -> void:
 potions=0
 for entry in inventory:
  if entry.get("id")=="potion":potions+=int(entry.count)

func transfer_item(shared: bool, deposit: bool, index: int) -> bool:
 if storage_fault or active_slot==0 or hp<=0:return false
 if shared and level<10:message="综合仓库需达到十级才可存取。";return false
 sync_potions()
 begin_transaction()
 var warehouse: Array=shared_storage if shared else personal_storage
 var source: Array=inventory if deposit else warehouse
 var target: Array=warehouse if deposit else inventory
 if index<0 or index>=source.size() or source[index].is_empty():return false
 var entry: Dictionary=source[index].duplicate()
 if not add_item(target,entry.id,int(entry.count)):message="目标空间不足。";return false
 source[index]={}
 recount_potions()
 if not commit_services():return false
 message=("存入" if deposit else "取出")+Items.DATA[entry.id].name+" ×"+str(entry.count)
 return true

func buy_item(id: String) -> bool:
 if not Items.DATA.has(id) or storage_fault or active_slot==0:return false
 var price: int=Items.DATA[id].price
 if coins<price:message="银两不足。";return false
 sync_potions()
 begin_transaction()
 if not add_item(inventory,id):message="背包已满。";return false
 coins-=price
 recount_potions()
 if not commit_services():return false
 message="购得 "+Items.DATA[id].name
 return true

func use_skill(id: String) -> bool:
 if Items.DATA.has(id):return use_item(id)
 if id in ["lightness","cloud_step"]:
  var cost: int=Advanced.DATA[id].cost
  if qi<cost:message="内力不足，可打坐或使用人参恢复。";return false
  var ok:=super.use_skill(id)
  if ok:qi-=cost
  return ok
 return super.use_skill(id)

func use_item(id: String) -> bool:
 if hp<=0 or active_slot==0 or storage_fault or item_count(id)<=0:return false
 var info: Dictionary=Items.DATA[id]
 if info.has("hp") and hp>=max_hp():return false
 if info.has("mp") and qi>=max_qi():return false
 if info.has("role") and info.role!=role_code():message="这是其它职业的装备。";return false
 sync_potions()
 begin_transaction()
 var index: int=-1
 for i in range(inventory.size()):
  if inventory[i].get("id")==id:index=i;break
 if index<0:return false
 if info.has("equip"):
  var old: String=equipped.get(info.equip,"")
  inventory[index].count-=1
  if inventory[index].count<=0:inventory[index]={}
  if not old.is_empty():add_item(inventory,old)
  equipped[info.equip]=id
 else:
  inventory[index].count-=1
  if inventory[index].count<=0:inventory[index]={}
 if info.has("hp"):hp=minf(max_hp(),hp+float(info.hp))
 if info.has("mp"):qi=minf(max_qi(),qi+float(info.mp))
 if id=="return_scroll":
  var cell:=free_cell(master.position+Vector3(2,0,-2))
  var at:=Vector2(cell)*CELL
  hero.position=Vector3(at.x,surface_height(at)+0.05,at.y)
  hero.velocity=Vector3.ZERO
  route.clear()
  click_target=""
  queued_skill=""
  strike_timer=0
  selected_monster=-1
  glide_remaining=0
  meditating=false
  for mob in monsters:mob.aggro=false;mob.wind=0
  update_region()
  update_camera(1,true)
 recount_potions()
 if not commit_services():return false
 message="使用 "+str(info.name)
 return true

func attack_power() -> int:
 var id: String=equipped.get("weapon","")
 return super.attack_power()+int(Items.DATA.get(id,{}).get("attack",0))
func defense_power() -> int:
 var id: String=equipped.get("armor","")
 return super.defense_power()+int(Items.DATA.get(id,{}).get("defense",0))

func talk_town_npc(title: String) -> void:
 var advances: bool=(promotion_stage in [3,7] and title=="银娇龙") or (promotion_stage in [8,12] and title=="刀剑笑") or (promotion_stage in [9,11] and title=="平十指")
 if advances or title not in ["韦大宝","平十指","刀剑笑","银娇龙"]:
  super.talk_town_npc(title)
  return
 var toward: Vector3=hero.position-town_actors[title].position
 town_actors[title].get_node("VisualBody").rotation.y=atan2(toward.x,toward.z)
 route.clear()
 click_target=""
 dialogue.hide()
 services_ui.open(title)
