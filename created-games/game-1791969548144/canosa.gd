extends Node2D

const WALL_X := 2800.0
const GATE_Y := 1800.0
const WORLD := Vector2(6400,3600)
const SPAWN := Vector2(620,1800)
var hero := SPAWN
var pet := SPAWN + Vector2(-40,25)
var hp := 180.0
var level := 1
var quest := 0
var kills := 0
var potions := 5
var attack_cd := 0.0
var skill_cd := 0.0
var pet_cd := 0.0
var flash := 0.0
var flash_radius := 115.0
var state := "title"
var hint := "欢迎来到卡诺萨城，先拜访引导员艾琳"
var enemies: Array[Dictionary] = []
var floats: Array[Dictionary] = []
var defeated := [0,0,0]
var font: Font = preload("res://font.ttf")
var stone: Texture2D
var grass: Texture2D
var knight: Texture2D
var portrait: Texture2D
var route: Array[Vector2] = []
var mouse_npc := -1
var mouse_enemy := -1
var walk_frames: Array[Texture2D] = []
var walk_clock := 0.0
var walking := false
var facing_left := false
var character_name := "冒险者"
var profession := "战士"
var active_slot := -1
var save_store = preload("res://character_saves.gd").new()
var character_menu: CanvasLayer
var autosave_clock := 0.0
var player_ui: CanvasLayer
var gold := 0
var master_volume := 100.0
var show_nameplates := true
var client_map: RefCounted
var native_actors: Dictionary={}
var enemy_actors: Array[Node]=[]
var monster_definitions: Array=[]
var current_region:=1000
var world_travel: CanvasLayer
var pet_actors: Array[Node]=[]

func quest_npcs() -> Array:
 return world_travel.main_npcs if current_region==2000 and world_travel!=null else npcs

func load_client_roles() -> void:
 for id in ["warrior","mage","738","701","728","603","721","704","719"]:
  var actor=load("res://native_client_actor.gd").new()
  add_child(actor)
  actor.setup(id)
  native_actors[id]=actor
 var records=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client_roles/npcs.json"))
 for record in records:
  var pos:=Vector2(record.pos[0],record.pos[1])
  # Preserve exact source tile coordinates separately. Runtime origin is a
  # provisional map alignment, with small nearest-walkable corrections.
  if client_map!=null and (not client_map.land(pos) or client_map.route(client_map.SPAWN,pos,10).is_empty()):
   var found:=false
   for radius in range(1,9):
    for step in range(16):
     var candidate:=pos+Vector2.from_angle(TAU*step/16)*radius*48
     if client_map.safe(candidate) and client_map.land(candidate) and not client_map.route(client_map.SPAWN,candidate,10).is_empty():
      pos=candidate
      found=true
      break
    if found: break
  npcs.append({"name":record.name,"pos":pos,"reward":0,"message":"我是"+record.name+"，"+record.note+"。你可以向我了解本职事务，或继续城内的新手指引。","client_id":record.id,"client_grid":record.client_grid,"client_model":record.client_model,"note":record.note})

func map_size() -> Vector2:
 return client_map.SIZE if client_map!=null else WORLD

func map_spawn() -> Vector2:
 return client_map.SPAWN if client_map!=null else SPAWN

func map_gate() -> Vector2:
 return client_map.GATE if client_map!=null else Vector2(WALL_X,GATE_Y)
var pets: Array[Dictionary] = []
var pet_images: Array[Texture2D] = []
var pet_faces: Array[Texture2D] = []

var pet_collection=preload("res://pet_collection.gd").new()
var equipment=preload("res://equipment_system.gd").new()
var item_drops: Array[Dictionary]=[]
const PHANTOM_DROP_CHANCE:=0.3
const SOUL_DROP_CHANCE:=0.1
var combat_xp:=0
var loot_visuals=preload("res://loot_visuals.gd").new()
const EGG_DROP_CHANCE:=0.5
var egg_drops: Array[Dictionary]=[]
var hunt_complete:=false

func refresh_pet_actors() -> void:
 for actor in pet_actors:
  if actor!=null:
   remove_child(actor)
   actor.queue_free()
 pet_actors.clear()
 for companion in pets:
  var actor: Node=null
  if companion.deployed and not native_actors.is_empty():
   actor=load("res://native_client_actor.gd").new()
   add_child(actor)
   actor.setup("petwarrior" if companion.type_id==1071020 else "petmage")
  pet_actors.append(actor)

func init_pets() -> void:
 pet_collection.reset()
 egg_drops.clear()
 hunt_complete=false
 pets.clear()
 for i in range(2):
  var companion: Dictionary=pet_collection.make_pet(1071020 if profession=="战士" else 1071220,true,"attack" if i==0 else "defense")
  companion.pos=hero+Vector2(-50 if i==0 else 50,30)
  pets.append(companion)
 refresh_pet_actors()

func deployed_pet(role: String) -> int:
 for i in range(pets.size()):
  if pets[i].deployed and pets[i].role==role and pets[i].hp>0: return i
 return -1

func toggle_pet(index: int) -> void:
 if index<0 or index>=pets.size(): return
 if not pets[index].deployed:
  var occupied: Array=[]
  for companion in pets:
   if companion.deployed: occupied.append(companion.role)
  if occupied.size()>=2:
   hint="最多同时出征两只幻兽，请先收回一只。"
   return
  pets[index].role="attack" if not "attack" in occupied else "defense"
 pets[index].deployed=not pets[index].deployed
 pets[index].pos=hero+Vector2(-55 if pets[index].role=="attack" else 55,30)
 hint=pets[index].name+("已出征" if pets[index].deployed else "已收回休息")
 refresh_pet_actors()
 save_progress()
 queue_redraw()

func add_item_drop(id: int, pos: Vector2) -> void:
 item_drops.append({"id":id,"pos":pos,"region_id":current_region})

func pickup_item(index: int) -> bool:
 if index<0 or index>=item_drops.size(): return false
 if not equipment.add_item(int(item_drops[index].id)):
  hint=equipment.message
  return false
 hint="拾取："+equipment.definitions[int(item_drops[index].id)].name
 item_drops.remove_at(index)
 save_progress()
 return true

func merchant_index() -> int:
 if current_region!=1000: return -1
 for i in range(npcs.size()):
  if int(npcs[i].get("client_id",0))==1055: return i
 return -1

func locate_merchant() -> void:
 var index:=merchant_index()
 if index<0: return
 mouse_enemy=-1
 mouse_npc=index
 navigate(npcs[index].pos)
 hint="前往杂货商克莱德：到达后可购买或出售物品。"

func npc_display_name(npc: Dictionary) -> String:
 return "杂货商 · "+str(npc.name) if int(npc.get("client_id",0))==1055 else str(npc.name)

func can_trade_at(index: int) -> bool:
 if current_region!=1000 or index<0 or index>=npcs.size(): return false
 return index==6 or "杂货" in str(npcs[index].get("note","")) or "商人" in str(npcs[index].get("note",""))

func use_scroll(index: int) -> bool:
 if index<0 or index>=40 or equipment.bag[index]==null or state!="play": return false
 var id:=int(equipment.bag[index].id)
 if id not in [1020010,1020020]: return false
 var destination:=map_spawn()
 if id==1020020:
  var found:=false
  for attempt in range(500):
   var candidate:=Vector2(randf_range(80,map_size().x-80),randf_range(80,map_size().y-80))
   if (client_map==null or client_map.clearance(candidate)) and candidate.distance_to(hero)>200:
    destination=candidate
    found=true
    break
  if not found:
   hint="未找到可安全落脚的位置，未消耗随机符。"
   return false
 if client_map!=null and not client_map.clearance(destination):
  hint="城区落点不可用，未消耗符。"
  return false
 if not equipment.consume(id): return false
 hero=destination
 route.clear()
 mouse_npc=-1
 mouse_enemy=-1
 walking=false
 for enemy in enemies: enemy.aggro=false
 for companion in pets: companion.pos=hero+Vector2(-55 if companion.role=="attack" else 55,30)
 save_progress()
 hint="已回到当前地图城区。" if id==1020010 else "已随机传送至当前地图可行走位置。"
 queue_redraw()
 return true

func can_forge_at(index: int) -> bool:
 if current_region!=1000 or index<0 or index>=npcs.size(): return false
 return index==2 or "锻造" in str(npcs[index].get("note",""))

func pet_overhead_text(companion: Dictionary) -> String:
 return "Lv.%d · %d星" % [companion.level,companion.star]

func pickup_egg(index: int) -> bool:
 if index<0 or index>=egg_drops.size(): return false
 if not pet_collection.add_egg(egg_drops[index].type_id):
  hint="幻兽蛋区域已满（50/50），无法拾取。"
  return false
 egg_drops.remove_at(index)
 hint="拾取幻兽蛋：已放入幻兽栏，按 H 孵化。"
 save_progress()
 return true

func snapshot() -> Dictionary:
 var companions: Array=[]
 for companion in pets:
  companions.append({"name":companion.name,"type_id":companion.type_id,"role":companion.role,"hp":companion.hp,"max":companion.max,"profession":companion.profession,"deployed":companion.deployed,"level":companion.level,"exp":companion.exp,"id":companion.id,"star":companion.star,"star_xp":companion.star_xp,"base_max":companion.base_max})
 return {"level":level,"combat_xp":combat_xp,"hp":hp,"quest":quest,"kills":kills,"potions":potions,"defeated":defeated.duplicate(),"position":[hero.x,hero.y],"pets":companions,"pet_collection":pet_collection.snapshot(),"equipment":equipment.snapshot(),"gold":gold,"master_volume":master_volume,"show_nameplates":show_nameplates,"region_id":current_region,"map_id":("client_treecity" if current_region==2000 else "client_chamgw26") if client_map!=null else "prototype"}

func save_progress(offline: bool = false) -> bool:
 if active_slot<0: return false
 var ok: bool=save_store.save_character(active_slot,snapshot(),offline,int(Time.get_unix_time_from_system()))
 hint="存档已保存（UTC+8）" if ok else "保存失败："+save_store.error
 return ok

func create_character(slot: int, name: String, job: String) -> bool:
 if not save_store.create(slot,name,job,int(Time.get_unix_time_from_system())): return false
 active_slot=slot
 character_name=name.strip_edges()
 profession=job
 new_run()
 init_pets()
 if not save_progress(): return false
 if character_menu!=null: character_menu.hide()
 return true

func load_character(slot: int) -> bool:
 if slot<0 or slot>=6 or save_store.slots[slot]==null: return false
 var record: Dictionary=save_store.slots[slot]
 active_slot=slot
 character_name=record.name
 profession=record["class"]
 new_run()
 var data: Dictionary=record.get("snapshot",{})
 if int(data.get("region_id",1000))==2000 and world_travel!=null: world_travel.switch_region(2000)
 level=clampi(int(data.get("level",record.level)),1,999)
 quest=clampi(int(data.get("quest",0)),0,5)
 hp=clampf(float(data.get("hp",180)),0,180)
 kills=maxi(0,int(data.get("kills",0)))
 combat_xp=clampi(int(data.get("combat_xp",(kills%5)*20)),0,99)
 potions=clampi(int(data.get("potions",5)),0,99)
 gold=maxi(0,int(data.get("gold",0)))
 equipment.restore(data.get("equipment",{}))
 master_volume=clampf(float(data.get("master_volume",100)),0,100)
 show_nameplates=bool(data.get("show_nameplates",true))
 AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.0001,master_volume/100)))
 var counts=data.get("defeated",[0,0,0])
 if counts is Array and counts.size()==3: defeated=[maxi(0,int(counts[0])),maxi(0,int(counts[1])),maxi(0,int(counts[2]))]
 var position_data=data.get("position",[SPAWN.x,SPAWN.y])
 if position_data is Array and position_data.size()==2:
   hero=Vector2(float(position_data[0]),float(position_data[1])).clamp(Vector2(60,60),map_size()-Vector2(60,60))
 var expected_map:="client_treecity" if current_region==2000 else "client_chamgw26"
 if client_map!=null and (data.get("map_id","")!=expected_map or not client_map.clearance(hero)): hero=map_spawn()
 init_pets()
 var companions=data.get("pets",[])
 if companions is Array and data.has("pets"):
  pets.clear()
  var deployed_count:=0
  for i in range(mini(50,companions.size())):
   var saved: Dictionary=companions[i]
   var type_id:=int(saved.get("type_id",1071020 if profession=="战士" else 1071220))
   if not type_id in [1071020,1071220]: type_id=1071020 if profession=="战士" else 1071220
   var companion: Dictionary=pet_collection.make_pet(type_id)
   for key in ["level","exp","star","star_xp"]: companion[key]=maxi(0,int(saved.get(key,companion[key])))
   companion.level=maxi(1,companion.level)
   companion.id=maxi(1,int(saved.get("id",i+1)))
   companion.role=str(saved.get("role","attack" if i==0 else "defense"))
   companion.deployed=bool(saved.get("deployed",true)) and deployed_count<2
   if companion.deployed: deployed_count+=1
   companion.base_max=float(saved.get("base_max",saved.get("max",80.0 if i==0 else 120.0)))
   companion.max=companion.base_max*pet_collection.growth(companion)
   companion.hp=clampf(float(saved.get("hp",companion.max)),0,companion.max)
   companion.pos=hero
   pets.append(companion)
 pet_collection.restore(data.get("pet_collection",{}),pets)
 refresh_pet_actors()
 pet=hero+Vector2(-40,25)
 hint="欢迎回来，"+character_name+"。Tab 背包，Q 任务，Esc 系统，F5 保存。"
 if player_ui!=null: player_ui.show()
 if character_menu!=null: character_menu.hide()
 if hp<=0:
  if world_travel!=null: world_travel.show_death()
  else: state="dead"
 return true

func open_character_menu() -> void:
 if active_slot>=0 and not save_progress(true): return
 close_dialog()
 state="characters"
 if player_ui!=null:
  player_ui.close()
  player_ui.hide()
 if character_menu!=null:
  character_menu.refresh()
  character_menu.show()
 queue_redraw()

func _notification(what: int) -> void:
 if what==NOTIFICATION_WM_CLOSE_REQUEST:
  if active_slot>=0 and not save_progress(true):
   open_character_menu()
   return
  get_tree().quit()

func take_hit(amount: float) -> void:
 if safe(hero): return
 amount=maxf(1,amount-equipment.stats().defense*0.1)
 var absorbed := 0.0
 var guard:=deployed_pet("defense")
 if guard>=0:
  absorbed=minf(amount*0.5,pets[guard].hp)
  pets[guard].hp-=absorbed
 hp-=amount-absorbed
var dialog_npc := -1
var dialog_text := ""
var dialog_focus := 0

func dialog_button_rect(index: int) -> Rect2:
 return Rect2(425,442+index*42,430,34)

func load_walk() -> void:
 walk_frames.clear()
 var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/walk/action.json")) if FileAccess.file_exists("res://assets/walk/action.json") else null
 if manifest is Dictionary:
  for frame in manifest.frames:
   walk_frames.append(load("res://assets/walk/"+frame.file))

func close_dialog() -> void:
 dialog_npc=-1
 route.clear()
 mouse_npc=-1
 walking=false
 queue_redraw()

func dialog_options() -> Array[String]:
 if dialog_npc==merchant_index() and dialog_npc>=0:
  return ["购买 / 出售（杂货商店）","了解杂货商","没什么事"]
 var primary := "询问这里的情况"
 if current_region==1000 and dialog_npc==quest and quest<5: primary="完成新手任务（等级 +%d）" % npcs[dialog_npc].reward
 if current_region==1000 and dialog_npc==4 and quest==4: primary="完成幻兽契约（新手结业）"
 elif dialog_npc==6: primary="休整：补满生命和药水"
 return [primary,"杂货交易（购买 / 出售）" if can_trade_at(dialog_npc) else ("装备锻造（幻魔 / 灵魂）" if can_forge_at(dialog_npc) else ("了解本职事务" if npcs[dialog_npc].has("client_id") else "了解城门与野怪")),"没什么事"]

func choose_dialog(index: int) -> void:
 if dialog_npc<0: return
 if dialog_npc==merchant_index() and index==0 and player_ui!=null:
  close_dialog()
  player_ui.toggle(7)
  return
 if index==2:
  close_dialog()
 elif index==1:
  if can_trade_at(dialog_npc) and dialog_npc!=merchant_index() and player_ui!=null:
   close_dialog()
   player_ui.toggle(7)
   return
  if can_forge_at(dialog_npc) and player_ui!=null:
   close_dialog()
   player_ui.toggle(6)
   return
  if npcs[dialog_npc].has("client_id"):
   dialog_text=npcs[dialog_npc].name+" · "+npcs[dialog_npc].note+"\n城内的引导员可指引你的新手旅程。"
  else: dialog_text="城内是安全区，一级即可从城门出城。新手任务升至五级。鹿角兽被动反击；巨杰士与猎杀兽主动追击。"
 else:
  resolve_talk()
  dialog_text=hint
 queue_redraw()
const ISO_X := Vector2(0.8,0.4)
const ISO_Y := Vector2(-0.8,0.4)

func project_pos(pos: Vector2) -> Vector2:
 if client_map!=null: return pos*client_map.SCALE
 return ISO_X*pos.x+ISO_Y*pos.y

func screen_pos(pos: Vector2) -> Vector2:
 return project_pos(pos-hero)+Vector2(640,430)

func world_pos(pos: Vector2) -> Vector2:
 var p := pos-Vector2(640,430)
 if client_map!=null: return hero+p/client_map.SCALE
 return hero+Vector2(p.x/1.6+p.y/0.8,-p.x/1.6+p.y/0.8)

func navigate(pos: Vector2) -> void:
 route.clear()
 if client_map!=null:
  route=client_map.route(hero,pos,level)
  if route.is_empty(): hint="目的地不可通行，或有障碍物；请点击道路或台阶。"
  return
 var target := pos.clamp(Vector2(60,60),WORLD-Vector2(60,60))
 if safe(hero)!=safe(target):
  route.append(Vector2(WALL_X-120 if safe(hero) else WALL_X+120,GATE_Y))
  route.append(Vector2(WALL_X+120 if safe(hero) else WALL_X-120,GATE_Y))
 route.append(target)

func mouse_click(pos: Vector2) -> void:
 mouse_npc = -1
 mouse_enemy = -1
 if pos.y<150:
  if Rect2(700,80,130,35).has_point(pos): save_progress()
  elif Rect2(850,80,130,35).has_point(pos) and player_ui!=null: player_ui.toggle(5)
  if Rect2(700,119,280,27).has_point(pos): locate_merchant()
  if Rect2(1010,15,240,130).has_point(pos):
   navigate((pos-Vector2(1010,15))/Vector2(240,130)*map_size())
  return
 if pos.y>=718:
  if pos.x<140: strike(true)
  elif pos.x<280:
   if potions>0 and hp<180:
    potions-=1
    hp=minf(180,hp+85)
  elif pos.x<392: state="pause"
  return
 for i in range(item_drops.size()):
  if int(item_drops[i].region_id)!=current_region: continue
  if pos.distance_to(screen_pos(item_drops[i].pos)+Vector2(0,-12))<35:
   if hero.distance_to(item_drops[i].pos)<=120: pickup_item(i)
   else:
    navigate(item_drops[i].pos)
    hint="靠近掉落物后再次点击拾取。"
   return
 for i in range(egg_drops.size()):
  if int(egg_drops[i].get("region_id",1000))!=current_region: continue
  if pos.distance_to(screen_pos(egg_drops[i].pos)+Vector2(0,-12))<30:
   if hero.distance_to(egg_drops[i].pos)<=120: pickup_egg(i)
   else:
    navigate(egg_drops[i].pos)
    hint="前往幻兽蛋，靠近后再次点击拾取。"
   return
 var closest := 65.0
 for i in range(npcs.size()):
  var distance: float = pos.distance_to(screen_pos(npcs[i].pos)+Vector2(0,-35))
  if distance<closest:
   closest=distance
   mouse_npc=i
 if mouse_npc>=0:
  navigate(npcs[mouse_npc].pos)
  return
 for i in range(enemies.size()):
  if enemies[i].hp>0 and pos.distance_to(screen_pos(enemies[i].pos))<35:
   mouse_enemy=i
   navigate(enemies[i].pos)
   return
 navigate(world_pos(pos))
var npcs := [
 {"name":"引导员艾琳","pos":Vector2(620,1550),"reward":1,"message":"欢迎来到卡诺萨！请去西北训练场拜访教官。"},
 {"name":"教官罗兰","pos":Vector2(700,700),"reward":1,"message":"基础训练完成。前往东北工坊领取武器。"},
 {"name":"铁匠布鲁克","pos":Vector2(1900,650),"reward":1,"message":"武器已强化。去中央药剂师处领取补给。"},
 {"name":"药剂师米娅","pos":Vector2(1400,1750),"reward":1,"message":"补给准备好了。前往南侧幻兽师学习协战。"},
 {"name":"幻兽师露娜","pos":Vector2(850,2800),"reward":0,"message":"幻兽契约完成！新手指导已结束，祝你狩猎顺利。"},
 {"name":"城门守卫凯恩","pos":Vector2(2550,1800),"reward":0,"message":"城门不限等级。城外有1级鹿角兽、5级巨杰士和7级猎杀兽，留意主动类型。"},
 {"name":"军需官诺亚","pos":Vector2(1900,2750),"reward":0,"message":"安全区可休整。每次交谈恢复生命与五瓶药水。"}
]

func _ready() -> void:
 get_tree().auto_accept_quit=false
 client_map=load("res://client_canosa_map.gd").new()
 client_map.setup()
 for i in range(npcs.size()): npcs[i].pos=client_map.NPC_POS[i]
 if ResourceLoader.exists("res://assets/canosa_stone.png"): stone = load("res://assets/canosa_stone.png")
 if ResourceLoader.exists("res://assets/canosa_grass.png"): grass = load("res://assets/canosa_grass.png")
 if ResourceLoader.exists("res://assets/knight_reused.png"): knight = load("res://assets/knight_reused.png")
 if ResourceLoader.exists("res://assets/hero_portrait.png"): portrait = load("res://assets/hero_portrait.png")
 load_walk()
 load_client_roles()
 new_run()
 for asset in ["res://assets/pet_cub.png","res://assets/pet_spirit.png"]:
  if ResourceLoader.exists(asset): pet_images.append(load(asset))
 for type_id in [1071020,1071220]: pet_faces.append(load("res://assets/client_pets/%d.dds" % type_id))
 save_store.read_slots()
 character_menu=load("res://character_menu.gd").new()
 add_child(character_menu)
 character_menu.setup(self)
 player_ui=load("res://player_panels.gd").new()
 add_child(player_ui)
 player_ui.setup(self)
 player_ui.hide()
 world_travel=load("res://world_travel.gd").new()
 add_child(world_travel)
 world_travel.setup(self)
 state = "characters"

func safe(pos: Vector2) -> bool:
 if client_map!=null: return client_map.safe(pos)
 return pos.x < WALL_X

func new_run() -> void:
 if current_region!=1000 and world_travel!=null: world_travel.switch_region(1000)
 monster_definitions=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client_roles/field-monsters.json"))
 for actor in enemy_actors:
  remove_child(actor)
  actor.queue_free()
 enemy_actors.clear()
 hero = map_spawn()
 pet = hero + Vector2(-40,25)
 hp = 180
 level = 1
 quest = 0
 kills = 0
 combat_xp=0
 potions = 5
 gold=0
 equipment.reset()
 item_drops.clear()
 master_volume=100
 show_nameplates=true
 AudioServer.set_bus_volume_db(0,0)
 if player_ui!=null:
  player_ui.close()
  player_ui.show()
 defeated = [0,0,0]
 attack_cd = 0
 skill_cd = 0
 pet_cd = 0
 flash = 0
 route.clear()
 mouse_npc = -1
 mouse_enemy = -1
 dialog_npc = -1
 walking = false
 walk_clock = 0
 facing_left = false
 for actor in native_actors.values():
  actor.direction=actor.base_direction
  actor.set_movement(Vector2.ZERO)
 floats.clear()
 enemies.clear()
 for kind in range(3):
  for i in range(12):
   var origin := Vector2(3450+kind*1000,450+(i/4)*1000)
   var pos := origin+Vector2((i%4)*175,0)
   if client_map!=null:
    pos=Vector2(4900+kind*1000+(i%4)*180,2200+(i/4)*300)
   var definition: Dictionary=monster_definitions[kind]
   enemies.append({"kind":kind,"name":definition.name,"type_id":definition.type_id,"model":definition.model,"pos":pos,"previous_pos":pos,"spawn":pos,"hp":float(definition.max_hp),"max":float(definition.max_hp),"level":int(definition.level),"active":definition.active,"aggro":false,"cd":0.0,"respawn":0.0,"wander_target":pos,"wander_wait":randf_range(0.2,3.0),"activity_radius":280.0})
   if not native_actors.is_empty():
    var actor=load("res://native_client_actor.gd").new()
    add_child(actor)
    actor.setup(definition.model)
    actor.set_active(false)
    enemy_actors.append(actor)
 state = "play"
 autosave_clock=0
 init_pets()
 hint = "新手任务：靠近引导员艾琳，按 F 交谈"

func move_allowed(from: Vector2, target: Vector2) -> Vector2:
 if client_map!=null: return client_map.move_allowed(from,target,level)
 var result := target.clamp(Vector2(60,60),WORLD-Vector2(60,60))
 if (from.x < WALL_X and result.x >= WALL_X) or (from.x > WALL_X and result.x <= WALL_X):
  if absf(result.y-GATE_Y)>155:
   result.x = WALL_X-45 if from.x<WALL_X else WALL_X+45
   hint = "请从中央城门通行（不限等级）"
 return result

func talk() -> void:
 var candidates: Array[int]=[]
 for index in range(npcs.size()): candidates.append(index)
 candidates.sort_custom(func(a,b): return hero.distance_to(npcs[a].pos)<hero.distance_to(npcs[b].pos))
 if mouse_npc>=0 and mouse_npc<npcs.size() and hero.distance_to(npcs[mouse_npc].pos)<=110:
  candidates.erase(mouse_npc)
  candidates.push_front(mouse_npc)
 for i in candidates:
  if hero.distance_to(npcs[i].pos)<=110:
   dialog_npc=i
   dialog_focus=0
   dialog_text="你好，冒险者。"+npcs[i].message
   if npcs[i].has("client_id"):
    dialog_text=npcs[i].message
   if i<5 and i>quest: dialog_text="请先拜访 "+npcs[quest].name+"，完成前置任务。"
   elif i<quest: dialog_text="你已完成这里的新手任务。还有什么需要帮助的吗？"
   route.clear()
   walking=false
   queue_redraw()
   return
 hint="靠近NPC后交谈"

func resolve_talk() -> void:
 var candidates: Array[int]=[]
 if dialog_npc>=0: candidates.append(dialog_npc)
 else:
  for index in range(npcs.size()): candidates.append(index)
 for i in candidates:
  if hero.distance_to(npcs[i].pos)>110: continue
  if i == quest and quest < 5:
   level += npcs[i].reward
   quest += 1
   hp = 180
   hint = npcs[i].name+"："+npcs[i].message+"  等级 +"+str(npcs[i].reward)
  elif i == 6:
   hp = 180
   potions = 5
   hint = "军需官：生命与药水已补满"
  elif i < 5 and i > quest:
   hint = "请先拜访 "+npcs[quest].name
  elif i < 5:
   hint = "任务已完成，奖励不能重复领取"
  else: hint = npcs[i].message
  return
 hint = "靠近 NPC 后按 F；当前目标已标在小地图"

func _input(event: InputEvent) -> void:
 if player_ui==null or state in ["characters","dead","travel"] or dialog_npc>=0: return
 if player_ui.handle_key(event):
  get_viewport().set_input_as_handled()
  queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
 if state in ["characters","dead","travel"]: return
 if player_ui!=null and player_ui.opened>=0: return
 if dialog_npc>=0:
  if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
   for i in range(3):
     if dialog_button_rect(i).has_point(event.position): choose_dialog(i)
  elif event is InputEventKey and event.pressed and not event.echo:
   if event.keycode==KEY_ESCAPE: close_dialog()
   elif event.keycode==KEY_UP: dialog_focus=(dialog_focus+2)%3
   elif event.keycode==KEY_DOWN: dialog_focus=(dialog_focus+1)%3
   elif event.keycode in [KEY_ENTER,KEY_SPACE]: choose_dialog(dialog_focus)
  queue_redraw()
  return
 if event is InputEventMouseButton and event.pressed:
  if event.button_index == MOUSE_BUTTON_LEFT:
   if state == "title": state="play"
   elif state in ["win","lose"]: new_run()
   elif state == "pause": state="play"
   else: mouse_click(event.position)
  elif event.button_index == MOUSE_BUTTON_RIGHT and state == "play": strike(true)
  queue_redraw()
  return
 if not event is InputEventKey or not event.pressed or event.echo: return
 if event.keycode==KEY_F5:
  save_progress()
  return
 if event.keycode == KEY_ENTER and state == "title": state = "play"
 elif event.keycode == KEY_R and state in ["win","lose"]: new_run()
 elif event.keycode == KEY_ESCAPE and state in ["play","pause"]: state = "pause" if state == "play" else "play"
 elif state == "play":
  if event.keycode == KEY_F: talk()
  elif event.keycode == KEY_R: strike(true)
  elif event.keycode == KEY_E and potions>0 and hp<180:
   hp = minf(180,hp+85)
   potions -= 1
 queue_redraw()

func popup(pos: Vector2, value: String, color: Color) -> void:
 floats.append({"pos":pos,"text":value,"color":color,"life":0.8})

func strike(skill: bool) -> void:
 if safe(hero):
  hint = "城内是安全区，不能攻击"
  return
 if (skill and skill_cd>0) or (not skill and attack_cd>0): return
 if skill: skill_cd = 5
 else: attack_cd = 0.5
 var actor_id:="warrior" if profession=="战士" else "mage"
 if native_actors.has(actor_id):
  var facing:=project_pos(enemies[mouse_enemy].pos-hero) if mouse_enemy>=0 and mouse_enemy<enemies.size() else Vector2.ZERO
  native_actors[actor_id].play_attack(facing)
 flash = 0.2
 flash_radius = (280 if skill else 250) if profession=="法师" else (190 if skill else 115)
 for enemy in enemies:
  if enemy.hp>0 and hero.distance_to(enemy.pos)<flash_radius:
   # Distinct defenses make physical and magical attacks separate damage types.
   var raw: float=(70.0 if skill else 36.0)+float(equipment.stats().get("magic" if profession=="法师" else "physical_max",0))
   var defense: float = (4.0+enemy.kind*2) if profession=="法师" else (6.0+enemy.kind*3)
   enemy["last_damage_type"]="magic" if profession=="法师" else "physical"
   damage(enemy,maxf(1,raw-defense))

func damage(enemy: Dictionary, amount: float) -> void:
 if enemy.hp<=0: return
 enemy.aggro = true
 enemy.hp -= amount
 popup(enemy.pos,str(int(amount)),Color("ffe2a0"))
 if enemy.hp<=0:
  defeated[enemy.kind] += 1
  kills += 1
  gold+=10+enemy.kind*5
  var quality_roll:=randf()
  if quality_roll<0.3:
   var ordinary:=randf()<0.8
   var candidates: Array=[]
   for data in equipment.definitions.values():
    if data.has("slot") and int(data.quality) in [0,1,2,3,7] and (not ordinary or int(data.quality)==0): candidates.append(int(data.id))
   if not candidates.is_empty(): add_item_drop(candidates.pick_random(),enemy.pos+Vector2(-50,25))
  if randf()<PHANTOM_DROP_CHANCE: add_item_drop(1037170,enemy.pos+Vector2(50,25))
  if randf()<SOUL_DROP_CHANCE: add_item_drop(1037160,enemy.pos+Vector2(0,75))
  if randf()<EGG_DROP_CHANCE:
   egg_drops.append({"region_id":current_region,"type_id":1071020 if randf()<0.5 else 1071220,"pos":enemy.pos+Vector2(0,-25)})
   hint="怪物掉落幻兽蛋，靠近后点击拾取（H 打开幻兽栏）。"
  enemy.respawn = 18
  combat_xp+=40
  while combat_xp>=100:
   combat_xp-=100
   level += 1
   hp = minf(180,hp+30)
  for companion in pets:
   if companion.deployed and companion.hp>0:
    companion.exp+=40
    while companion.exp>=100:
     companion.exp-=100
     companion.level=mini(level,companion.level+1)

func move_enemy(enemy: Dictionary, target: Vector2, speed: float, dt: float) -> void:
 var candidate: Vector2=enemy.pos.move_toward(target,speed*dt)
 if candidate.distance_to(enemy.spawn)>enemy.activity_radius or safe(candidate): return
 if client_map!=null:
  if client_map.move_allowed(enemy.pos,candidate,10)!=candidate: return
 enemy.pos=candidate

func wander_enemy(enemy: Dictionary, dt: float) -> void:
 enemy.wander_wait-=dt
 if enemy.wander_wait<=0:
  enemy.wander_wait=randf_range(2.0,5.0)
  var target: Vector2=enemy.spawn+Vector2.from_angle(randf()*TAU)*randf_range(40,enemy.activity_radius-30)
  if not safe(target) and (client_map==null or client_map.clearance(target)):
   enemy.wander_target=target
 move_enemy(enemy,enemy.wander_target,randf_range(26,38),dt)

func update_enemy_visuals() -> void:
 if current_region!=1000: return
 for i in range(enemy_actors.size()):
  var enemy: Dictionary=enemies[i]
  var actor: Node=enemy_actors[i]
  actor.set_active(enemy.hp>0 and Rect2(-150,0,1580,900).has_point(screen_pos(enemy.pos)))
  actor.set_movement(project_pos(enemy.pos-enemy.previous_pos))
  enemy.previous_pos=enemy.pos

func _process(dt: float) -> void:
 if world_travel!=null: world_travel.tick()
 if state != "play" or dialog_npc>=0 or (player_ui!=null and player_ui.opened>=0): return
 var previous_position := hero
 attack_cd = maxf(0,attack_cd-dt)
 skill_cd = maxf(0,skill_cd-dt)
 pet_cd = maxf(0,pet_cd-dt)
 flash = maxf(0,flash-dt)
 var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
 if direction!=Vector2.ZERO:
  route.clear()
  mouse_npc=-1
  mouse_enemy=-1
  # Keyboard directions remain aligned with the screen axes.
  var movement := direction.normalized() if client_map!=null else Vector2(direction.x+direction.y,-direction.x+direction.y).normalized()
  hero = move_allowed(hero,hero+movement*380*dt)
 elif not route.is_empty():
  if route.size()==1 and mouse_enemy>=0:
   if enemies[mouse_enemy].hp<=0:
    route.clear()
    mouse_enemy=-1
   elif client_map==null: route[0]=enemies[mouse_enemy].pos
   elif hero.distance_to(enemies[mouse_enemy].pos)>110: route=client_map.route(hero,enemies[mouse_enemy].pos,level)
  if not route.is_empty():
   var stop := 85.0 if mouse_npc>=0 and route.size()==1 else (90.0 if mouse_enemy>=0 and route.size()==1 else 8.0)
   if hero.distance_to(route[0])>stop:
    hero=move_allowed(hero,hero.move_toward(route[0],380*dt))
   elif route.size()>1: route.pop_front()
   elif mouse_npc>=0:
    talk()
    mouse_npc=-1
    route.clear()
   elif mouse_enemy>=0: strike(false)
   else: route.clear()
 pet = pet.move_toward(hero+Vector2(-40,25),450*dt)
 for i in range(pets.size()):
  var previous: Vector2=pets[i].pos
  pets[i].pos=pets[i].pos.move_toward(hero+Vector2(-55 if pets[i].role=="attack" else 55,30),450*dt)
  if i<pet_actors.size() and pet_actors[i]!=null:
   pet_actors[i].set_active(pets[i].deployed)
   pet_actors[i].set_movement(project_pos(pets[i].pos-previous))
  if safe(hero): pets[i].hp=minf(pets[i].max,pets[i].hp+dt*10)
 update_walk(previous_position,dt)
 if Input.is_physical_key_pressed(KEY_SPACE): strike(false)
 var target: Dictionary = {}
 var closest := 250.0
 for enemy in enemies:
  if enemy.hp<=0:
   enemy.respawn -= dt
   if enemy.respawn<=0:
    enemy.hp = enemy.max
    enemy.pos = enemy.spawn
    enemy.aggro = false
   continue
  enemy.cd = maxf(0,enemy.cd-dt)
  var d: float = hero.distance_to(enemy.pos)
  if safe(hero):
   enemy.aggro = false
  elif enemy.active and d<230: enemy.aggro = true
  if hero.distance_to(enemy.spawn)>enemy.activity_radius+40 or d>700: enemy.aggro = false
  if enemy.aggro:
   if d>42: move_enemy(enemy,hero,95+enemy.kind*12,dt)
   if d<55 and enemy.cd<=0:
    take_hit(10+enemy.kind*3)
    enemy.cd = 1.2
    var index:=enemies.find(enemy)
    if index<enemy_actors.size(): enemy_actors[index].play_attack(project_pos(hero-enemy.pos))
    popup(hero,"受击",Color("ff7a8c"))
   if d<closest:
    closest = d
    target = enemy
  else: wander_enemy(enemy,dt)
 update_enemy_visuals()
 if not target.is_empty() and pet_cd<=0:
  var assist:=deployed_pet("attack")
  if assist>=0:
   damage(target,(18 if pets[assist].profession=="战士" else 22)*pet_collection.growth(pets[assist]))
   if assist<pet_actors.size() and pet_actors[assist]!=null: pet_actors[assist].play_attack(project_pos(target.pos-pets[assist].pos))
   pets[assist].hp=maxf(0,pets[assist].hp-1)
  pet_cd = 0.9
 for i in range(floats.size()-1,-1,-1):
  floats[i].life -= dt
  floats[i].pos.y -= dt*35
  if floats[i].life<=0: floats.remove_at(i)
 if hp<=0:
  hp = 0
  if world_travel!=null: world_travel.show_death()
  else: state="dead"
 elif not hunt_complete and defeated[0]>=3 and defeated[1]>=3 and defeated[2]>=3:
  hunt_complete=true
  hint = "狩猎目标已完成！可继续探索、打怪收集幻兽蛋。"
 autosave_clock+=dt
 if autosave_clock>=15:
  autosave_clock=0
  if active_slot>=0: save_progress()
 queue_redraw()

func update_walk(previous_position: Vector2, dt: float) -> void:
 var displacement := project_pos(hero-previous_position)
 walking=displacement.length()>0.05
 if walking:
  walk_clock+=dt
  if absf(displacement.x)>0.1: facing_left=displacement.x<0
 else: walk_clock=0
 for id in ["warrior","mage"]:
  if native_actors.has(id): native_actors[id].set_movement(displacement if id==("warrior" if profession=="战士" else "mage") else Vector2.ZERO)

func caption(pos: Vector2, value: String, size: int = 20, color: Color = Color("ece7dc")) -> void:
 draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func draw_person(pos: Vector2, tint: Color = Color.WHITE, is_hero: bool = false, npc_model: String = "") -> void:
 var p := screen_pos(pos)
 draw_set_transform(p,0,Vector2(1,0.4))
 draw_circle(Vector2.ZERO,25,Color(0,0,0,0.35))
 draw_set_transform(Vector2.ZERO)
 var native_id: String=("warrior" if profession=="战士" else "mage") if is_hero else npc_model
 if native_actors.has(native_id):
  var extent:=192.0 if is_hero else 160.0
  draw_texture_rect(native_actors[native_id].texture(),Rect2(p-native_actors[native_id].foot_anchor*(extent/256),Vector2(extent,extent)),false)
  return
 if knight!=null:
  var texture := knight
  if is_hero and walking and not walk_frames.is_empty(): texture=walk_frames[int(walk_clock/0.08)%walk_frames.size()]
  # Preserve the full transparent source canvas and its fixed foot anchor.
  draw_set_transform(p,0,Vector2(-1 if is_hero and facing_left else 1,1))
  draw_texture_rect(texture,Rect2(Vector2(-88,-139),Vector2(176,176)),false,tint)
  draw_set_transform(Vector2.ZERO)
  if is_hero and profession=="法师":
   var staff_base := p+Vector2(25,0)
   draw_line(staff_base,staff_base+Vector2(0,-90),Color("9d78c5"),4)
   draw_circle(staff_base+Vector2(0,-95),8,Color("88dcff"))
 else: draw_circle(p,20,tint)

func _draw() -> void:
 draw_rect(Rect2(0,0,1280,800),Color("101722"))
 if client_map!=null:
  client_map.draw_ground(self,hero)
 else:
  draw_set_transform_matrix(Transform2D(ISO_X,ISO_Y,Vector2(640,430)-project_pos(hero)))
  draw_rect(Rect2(Vector2.ZERO,Vector2(WALL_X,3600)),Color("57646b"))
  draw_rect(Rect2(Vector2(WALL_X,0),Vector2(3600,3600)),Color("364e3a"))
  # Only visible tiles are drawn; world size does not multiply draw calls.
  for x in range(int((hero.x-1600)/512),int((hero.x+1600)/512)+1):
   for y in range(int((hero.y-1600)/512),int((hero.y+1600)/512)+1):
    var tex: Texture2D = stone if x*512<WALL_X else grass
    if tex != null: draw_texture_rect(tex,Rect2(x*512,y*512,512,512),false)
  draw_rect(Rect2(150,1660,2650,280),Color(0.45,0.4,0.28,0.65))
  draw_rect(Rect2(WALL_X,1660,3400,280),Color(0.43,0.37,0.24,0.65))
  for segment in [Rect2(2755,0,90,1645),Rect2(2755,1955,90,1645)]:
   draw_rect(segment,Color("899292"))
   draw_rect(segment,Color("b1bab5"),false,5)
  for y in range(40,3600,140):
   if absf(y-GATE_Y)>180: draw_rect(Rect2(2740,y,120,40),Color("5e6b70"))
  # Broad steps lead to the NPC plazas; decorative in this 2D prototype.
  for pos in [Vector2(500,520),Vector2(1700,460),Vector2(650,2580)]:
   for step in range(6):
    draw_rect(Rect2(pos+Vector2(0,step*18),Vector2(420,18)),Color(0.4+step*0.04,0.43+step*0.04,0.45+step*0.04))
  draw_set_transform(Vector2.ZERO)
  for span in [Vector2(0,1645),Vector2(1955,3600)]:
   var a := screen_pos(Vector2(2755,span.x))
   var b := screen_pos(Vector2(2755,span.y))
   var c := screen_pos(Vector2(2845,span.y))
   var d := screen_pos(Vector2(2845,span.x))
   var up := Vector2(0,-85)
   draw_colored_polygon(PackedVector2Array([a,b,b+up,a+up]),Color("53636e"))
   draw_colored_polygon(PackedVector2Array([b,c,c+up,b+up]),Color("3d4c5a"))
   draw_colored_polygon(PackedVector2Array([a+up,b+up,c+up,d+up]),Color("a9b6b8"))
  caption(screen_pos(Vector2(2500,1600)),"城门已开放",24)
 if not route.is_empty():
  draw_arc(screen_pos(route.back()),15,0,TAU,32,Color("ffe098"),2)
 # Sort all upright characters by projected foot depth for correct overlap.
 var people: Array[Dictionary] = [{"pos":hero,"npc":-1}]
 for i in range(npcs.size()): people.append({"pos":npcs[i].pos,"npc":i})
 for i in range(mini(enemy_actors.size(),enemies.size())):
  if enemies[i].hp>0: people.append({"pos":enemies[i].pos,"enemy":i})
 for i in range(pet_actors.size()):
  if pets[i].deployed and pet_actors[i]!=null: people.append({"pos":pets[i].pos,"companion":i})
 people.sort_custom(func(a,b): return project_pos(a.pos).y<project_pos(b.pos).y)
 for person in people:
  if person.has("companion"):
   var actor: Node=pet_actors[person.companion]
   var size:=Vector2(112,112)
   draw_texture_rect(actor.texture(),Rect2(screen_pos(person.pos)-actor.foot_anchor/256*size,size),false,Color(1,1,1,0.35 if pets[person.companion].hp<=0 else 1.0))
   continue
  if person.has("enemy"):
   var actor: Node=enemy_actors[person.enemy]
   var size:=Vector2(156,156)
   draw_texture_rect(actor.texture(),Rect2(screen_pos(person.pos)-actor.foot_anchor/256*size,size),false)
   continue
  draw_person(person.pos,Color.WHITE if person.npc<0 else Color.from_hsv(float(person.npc)/8.0,0.15,1),person.npc<0,"" if person.npc<0 else str(npcs[person.npc].get("client_model","")))
 if show_nameplates:
  var head := screen_pos(hero)+Vector2(0,-113)
  var title_text := character_name+" Lv."+str(level)
  var title_width := maxf(90,font.get_string_size(title_text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+12)
  draw_rect(Rect2(head+Vector2(-title_width/2,-20),Vector2(title_width,31)),Color(0.03,0.06,0.1,0.7))
  caption(head+Vector2(-title_width/2+6,-5),title_text,14,Color("ffe4a4"))
  draw_rect(Rect2(head+Vector2(-42,0),Vector2(84,5)),Color("482e3e"))
  draw_rect(Rect2(head+Vector2(-42,0),Vector2(84*clampf(hp/180,0,1),5)),Color("75ca96"))
 for i in range(npcs.size()):
  var npc: Dictionary = npcs[i]
  var p := screen_pos(npc.pos)
  var shop: bool=int(npc.get("client_id",0))==1055
  caption(p+Vector2(-90 if shop else -65,-115),npc_display_name(npc),20,Color("ffe098") if shop else Color.WHITE)
  if shop: draw_arc(p,25,0,TAU,32,Color("eac572"),2)
  if i == quest and quest<5: caption(p+Vector2(-8,-145),"!",36,Color("ffe098"))
  if hero.distance_to(npc.pos)<110: caption(p+Vector2(-55,30),"点击 / F 交谈",18,Color("ffe098"))
 var colors := [Color("c5b87c"),Color("be7585"),Color("a07acc")]
 for enemy in enemies:
  var p := screen_pos(enemy.pos)
  if enemy.hp<=0 or not Rect2(-100,-100,1480,1000).has_point(p): continue
  if enemy_actors.is_empty(): draw_circle(p,22,colors[enemy.kind])
  caption(p+Vector2(-65,-90),"%s · Lv%d %s" % [enemy.name,enemy.level,"主动" if enemy.active else "被动"],14)
  draw_rect(Rect2(p+Vector2(-25,-83),Vector2(50*enemy.hp/enemy.max,4)),Color("ed818f"))
 for i in range(pets.size()):
  if not pets[i].deployed: continue
  var p := screen_pos(pets[i].pos)
  var tint := Color.WHITE if i==0 else Color("bbdfef")
  if pets[i].hp<=0: tint.a=0.35
  if pet_actors.is_empty() and pet_images.size()==2:
   draw_texture_rect(pet_images[0 if profession=="战士" else 1],Rect2(p+Vector2(-25,-42),Vector2(50,50)),false,tint)
  elif pet_actors.is_empty(): draw_circle(p,12,Color("78e3f0"))
  draw_rect(Rect2(p+Vector2(-39,-79),Vector2(88,18)),Color(0.03,0.06,0.1,0.75))
  caption(p+Vector2(-34,-65),pet_overhead_text(pets[i]),12,Color("ffe6a3"))
  caption(p+Vector2(-32,24),"协战" if pets[i].role=="attack" else "守护",12)
  draw_rect(Rect2(p+Vector2(-22,11),Vector2(44*pets[i].hp/pets[i].max,3)),Color("75ca96"))
 if flash>0:
  draw_set_transform(screen_pos(hero),0,Vector2(1,0.5))
  draw_arc(Vector2.ZERO,flash_radius,0,TAU,64,Color("ffe2a0"),4)
  draw_set_transform(Vector2.ZERO)
 for drop in item_drops:
  if int(drop.region_id)!=current_region: continue
  var data: Dictionary=equipment.definitions[int(drop.id)]
  var point:=screen_pos(drop.pos)
  loot_visuals.draw_item(self,point,int(drop.id))
  caption(point+Vector2(-24,-51),data.name,12,Color("a5e9ed") if not data.has("slot") else equipment.quality_color(data))
 for drop in egg_drops:
  if int(drop.get("region_id",1000))!=current_region: continue
  var point:=screen_pos(drop.pos)
  loot_visuals.draw_egg(self,point,int(drop.type_id))
  caption(point+Vector2(-24,-40),"幻兽蛋",12,Color("ffe4a4"))
 for item in floats: caption(screen_pos(item.pos),item.text,18,item.color)
 draw_set_transform(Vector2.ZERO)
 draw_rect(Rect2(0,0,1280,150),Color(0.04,0.07,0.11,0.96))
 caption(Vector2(30,38),("树心城 · 城内安全区" if current_region==2000 else "卡诺萨城 · "+("城内安全区" if safe(hero) else "城外野怪区")),28,Color("efcd82"))
 caption(Vector2(30,75),"%s · %s  生命 %d/180  等级 %d  经验 %d/100  药水 %d" % [character_name,profession,int(hp),level,combat_xp,potions],18)
 draw_rect(Rect2(700,80,130,35),Color("294457"))
 caption(Vector2(711,104),"保存 F5",18)
 draw_rect(Rect2(850,80,130,35),Color("294457"))
 caption(Vector2(861,104),"系统 Esc",18)
 if merchant_index()>=0:
  draw_rect(Rect2(700,119,280,27),Color("51452c"))
  caption(Vector2(711,139),"杂货商 · 克莱德　点击寻路",16,Color("ffe098"))
 caption(Vector2(30,108),"新手 %d/5 · 狩猎 鹿角兽%d/3 巨杰士%d/3 猎杀兽%d/3" % [quest,defeated[0],defeated[1],defeated[2]],18)
 var goal: Vector2 = (client_map.PORTAL if current_region==2000 else (npcs[quest].pos if quest<5 else map_gate()))
 var next_label: String="返回卡诺萨城的传送阵" if current_region==2000 else (npcs[quest].name if quest<5 else "中央城门 / 城外狩猎")
 caption(Vector2(30,138),"下一站："+next_label+"  距离 %d米" % int(hero.distance_to(goal)/10),18)
 draw_rect(Rect2(0,718,1280,82),Color(0.04,0.07,0.11,0.96))
 caption(Vector2(15,747),"爆发 R       药水 E       暂停",18)
 caption(Vector2(25,780),hint,18,Color("efcd82"))
 var mini := Rect2(1010,15,240,130)
 if client_map!=null:
  draw_texture_rect(client_map.overview,mini,false)
 else:
  draw_rect(mini,Color("274035"))
  draw_rect(Rect2(mini.position,Vector2(240*WALL_X/WORLD.x,130)),Color("586571"))
  draw_line(mini.position+Vector2(240*WALL_X/WORLD.x,0),mini.position+Vector2(240*WALL_X/WORLD.x,130),Color.WHITE,2)
 for npc in npcs: draw_circle(mini.position+npc.pos/map_size()*mini.size,2,Color("70cddd"))
 if merchant_index()>=0:
  var shop_point: Vector2=mini.position+npcs[merchant_index()].pos/map_size()*mini.size
  draw_circle(shop_point,4,Color("ffe098"))
  caption(shop_point+Vector2(5,0),"商",12,Color("ffe098"))
 for enemy in enemies:
  if enemy.hp>0: draw_circle(mini.position+enemy.pos/map_size()*mini.size,1.5,Color("d27b80"))
 for companion in pets:
  if companion.deployed: draw_circle(mini.position+companion.pos/map_size()*mini.size,2,Color("87dfb6"))
 if client_map!=null:
  draw_circle(mini.position+client_map.PORTAL/map_size()*mini.size,4,Color("77efff"))
  var portal_screen:=screen_pos(client_map.PORTAL)
  if Rect2(-100,150,1480,568).has_point(portal_screen):
   draw_arc(portal_screen,28,0,TAU,32,Color("85f2ff"),2)
   caption(portal_screen+Vector2(-65,-40),"返回卡诺萨城" if current_region==2000 else "前往树心城",16,Color("85f2ff"))
 draw_circle(mini.position+goal/map_size()*mini.size,4,Color("ffe098"))
 draw_circle(mini.position+hero/map_size()*mini.size,4,Color.WHITE)
 if state != "play":
  draw_rect(Rect2(0,150,1280,568),Color(0.03,0.05,0.08,0.94))
  var title := "卡诺萨 · 新手冒险"
  var action := "点击开始 / Enter 开始"
  if state == "pause":
   title = "已暂停"
   action = "点击继续 / Esc 继续"
  elif state=="dead":
   title="角色倒下"
   action="请在弹窗确认回城复活，属性与进度保留"
  elif state=="travel":
   title="区域传送"
   action="请选择是否前往目标城市"
  elif state in ["win","lose"]:
   title = "狩猎完成！" if state == "win" else "冒险者倒下了"
   action = "点击 / R 重来：重置任务、等级、位置和怪物"
  caption(Vector2(280,310),title,36,Color("efcd82"))
  caption(Vector2(280,370),"城内拜访五位 NPC → 升至五级 → 出城狩猎",24)
  caption(Vector2(280,415),"每种12只：鹿角兽 Lv1、巨杰士 Lv5、猎杀兽 Lv7",22)
  caption(Vector2(280,485),action,26,Color("78e3f0"))
  caption(Vector2(280,540),"2.5D斜视 · 战士/法师使用本地客户端模型 · 单机新手主线",18)
  if not native_actors.is_empty():
   draw_texture_rect(native_actors["warrior" if profession=="战士" else "mage"].texture(),Rect2(50,270,195,195),false)
   caption(Vector2(60,490),profession+" · 职业模型",16)
  elif portrait!=null:
   draw_texture_rect(portrait,Rect2(50,270,195,195),false)
   caption(Vector2(45,490),"新人物母图预览",16)
 if dialog_npc>=0:
  draw_rect(Rect2(0,150,1280,568),Color(0.02,0.03,0.05,0.7))
  draw_rect(Rect2(400,282,480,314),Color("152533"))
  draw_rect(Rect2(400,282,480,314),Color("bc9d65"),false,2)
  caption(Vector2(425,318),npcs[dialog_npc].name,22,Color("ffe4a4"))
  var wrapped: Array[String]=[]
  var line:=""
  for character in dialog_text:
   if character=="\n" or font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x>430:
    wrapped.append(line)
    line="" if character=="\n" else character
   else: line+=character
  wrapped.append(line)
  draw_multiline_string(font,Vector2(425,350),"\n".join(wrapped),HORIZONTAL_ALIGNMENT_LEFT,430,17,4,Color("ece7dc"))
  var options := dialog_options()
  for i in range(3):
   var rect := dialog_button_rect(i)
   draw_rect(rect,Color("3c5668") if dialog_focus==i else Color("223a4d"))
   caption(rect.position+Vector2(12,23),options[i],17)
  caption(Vector2(425,579),"鼠标选择 · ↑↓切换 · Enter确认 · Esc关闭",13)
