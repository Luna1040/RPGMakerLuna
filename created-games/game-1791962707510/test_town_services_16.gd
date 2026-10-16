extends SceneTree
var game: Node
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, detail: String) -> void:
 if not ok:failed=true;push_error("FAIL "+detail)
func frames(n: int) -> void:
 for i in range(n):await physics_frame;await process_frame
func find_item(slots: Array,id: String) -> int:
 for i in range(slots.size()):
  if slots[i].get("id")==id:return i
 return -1
func run() -> void:
 game=load("res://main.tscn").instantiate()
 game.saves.directory="res://art-jobs/town-services-16/test-saves-%d" % Time.get_ticks_usec()
 root.add_child(game)
 await frames(5)
 game.name_input.text="Service16"
 game.select_slot(1)
 await frames(5)
 game.set_process(false)
 game.set_physics_process(false)
 check(game.inventory.size()==40 and game.item_count("return_scroll")==10,"New role gets ten scrolls and forty bag slots")
 check(game.personal_storage.size()==200 and game.shared_storage.size()==200,"Both warehouses have two hundred slots")
 check(game.practice.position.distance_to(game.master.position)<5,"Practice blade stands beside master")
 game.talk_town_npc("韦大宝")
 check(game.services_ui.window.visible and game.paused,"Warehouse opens from NPC dialogue")
 var scroll:=find_item(game.inventory,"return_scroll")
 check(not game.transfer_item(true,true,scroll),"Shared deposit blocked below ten")
 check(game.transfer_item(false,true,scroll),"Personal deposit")
 check(game.item_count("return_scroll")==0 and game.personal_storage[0].count==10,"Personal transfer has no duplication")
 game.services_ui.page=4
 game.services_ui.rebuild()
 check(game.services_ui.page==4,"Fifth page renders")
 check(game.transfer_item(false,false,0),"Personal withdrawal")
 game.level=10
 check(game.transfer_item(true,true,find_item(game.inventory,"return_scroll")),"Shared deposit at ten")
 check(game.transfer_item(false,true,find_item(game.inventory,"potion")),"Personal items exist before character deletion")
 game.services_ui.close()
 check(not game.paused,"Warehouse close unpauses")
 game.save_character()
 var slot1: Dictionary=game.saves.read_slot(1)
 check(not slot1.is_empty(),"Service save accepted")
 game.open_menu()
 game.name_input.text="Other16"
 game.select_slot(2)
 await frames(4)
 game.set_process(false)
 game.set_physics_process(false)
 check(game.item_count("return_scroll")==10 and game.personal_storage[0].is_empty(),"New role has independent bag and personal warehouse")
 check(game.shared_storage[0].count==10,"Other role sees shared warehouse")
 check(not game.transfer_item(true,false,0),"Shared withdrawal blocked below ten")
 game.level=10
 check(game.transfer_item(true,false,0) and game.item_count("return_scroll")==20,"Shared withdrawal merges stack")
 check(game.transfer_item(true,true,find_item(game.inventory,"return_scroll")),"Leave shared items before character deletion")
 check(game.saves.delete_slot(1),"Delete first isolated test role")
 game.open_menu()
 game.name_input.text="Replacement16"
 game.select_slot(1)
 await frames(4)
 game.set_process(false)
 game.set_physics_process(false)
 check(game.personal_storage[0].is_empty() and game.item_count("return_scroll")==10,"Replacement role does not inherit deleted personal warehouse")
 check(game.shared_storage[0].count==20,"Shared items survive deletion and role switch")
 game.hero.position=Vector3(15,0,50)
 check(game.use_item("return_scroll"),"Return scroll usable")
 check(game.item_count("return_scroll")==9 and game.hero.position.distance_to(game.master.position)<6,"Scroll consumed and returns near master")
 game.coins=1000
 for npc in ["平十指","刀剑笑","银娇龙"]:
  game.talk_town_npc(npc)
  check(game.services_ui.title==npc and game.services_ui.window.visible,"Native NPC opens shop "+npc)
  game.services_ui.close()
 for id in ["mp_small","hp_medium","mp_medium","blade_weapon","armor"]:check(game.buy_item(id),"Purchase "+id)
 game.hp=1
 game.qi=0
 check(game.use_item("hp_medium") and game.hp==minf(game.max_hp(),181),"Health medicine works")
 check(game.use_item("mp_small") and game.qi==30,"Inner power medicine works")
 var attack: int=game.attack_power()
 var defense: int=game.defense_power()
 check(game.use_item("blade_weapon") and game.attack_power()==attack+5,"Purchased weapon equips")
 check(game.use_item("armor") and game.defense_power()==defense+3,"Purchased armor equips")
 game.level=10
 game.learn_skill("lightness")
 game.learn_skill("cloud_step")
 game.qi=100
 check(game.use_skill("lightness") and game.qi==90,"Lightness costs ten inner power")
 check(game.use_skill("cloud_step") and game.qi==75,"Cloud step costs fifteen inner power")
 game.qi=0
 check(not game.use_skill("cloud_step") and game.qi==0,"Insufficient inner power blocks auxiliary skill")
 var menus: Node=game.get_node("GameMenus")
 menus.toggle(1)
 check(menus.bag_slots.size()==40,"Generalized bag has forty slots")
 menus.close()
 check(game.save_character(),"Save generalized items and equipment")
 var data: Dictionary=game.saves.read_slot(1)
 var expected: int=game.item_count("return_scroll")
 game.restore(data.progress)
 await frames(4)
 check(game.item_count("return_scroll")==expected and game.equipped.get("armor")=="armor","Inventory and gear round trip")
 check(game.saves.valid_progress(game.snapshot()),"Extended save schema validates")
 var bad: Dictionary=game.snapshot().duplicate(true)
 bad.town_services.personal[199]={"id":"potion","count":-1}
 check(not game.saves.valid_progress(bad),"Invalid warehouse entry rejected")
 # A recorded interrupted transaction rolls forward exactly once on next access.
 var saved_count: int=game.item_count("return_scroll")
 var transaction: Dictionary={"character":game.character.duplicate(true),"shared":game.shared_storage.duplicate(true)}
 check(game.atomic_json(game.saves.directory.path_join("warehouse_transaction.json"),transaction),"Create isolated interrupted transaction")
 check(game.recover_transaction() and game.recover_transaction(),"Transaction recovery is idempotent")
 var recovered: Array=game.saves.read_slot(1).progress.town_services.bag
 for i in range(40):
  var before: Dictionary=game.character.progress.town_services.bag[i]
  check(recovered[i].get("id","")==before.get("id","") and int(recovered[i].get("count",0))==int(before.get("count",0)),"Recovery preserves inventory slot "+str(i))
 var source=menus.skill_ui.create_source("mp_medium")
 root.add_child(source)
 var drag: Variant=source._get_drag_data(Vector2.ZERO)
 check(drag is Dictionary and drag.id=="mp_medium","Medicine creates hotbar drag payload")
 menus.skill_ui.slots[8]._drop_data(Vector2.ZERO,drag)
 game.qi=0
 check(menus.skill_ui.activate_slot(8) and game.qi==80,"Dragged medicine used through hotbar")
 source.free()
 var private_before: Array=game.personal_storage.duplicate(true)
 for i in range(200):game.personal_storage[i]={"id":"armor","count":1}
 var bag_before: int=game.item_count("return_scroll")
 check(not game.transfer_item(false,true,find_item(game.inventory,"return_scroll")) and game.item_count("return_scroll")==bag_before,"Full warehouse refuses deposit without losing items")
 game.personal_storage=private_before
 # Real navigation and capsule physics, multiple lanes through the widened south arch.
 game.paused=false
 game.glide_remaining=0
 game.lightness=false
 game.set_process(true)
 game.set_physics_process(true)
 Engine.time_scale=4
 for npc in ["韦大宝","平十指","刀剑笑","银娇龙"]:
  game.services_ui.close()
  game.dialogue.hide()
  game.paused=false
  var actor: Node3D=game.town_actors[npc]
  var start: Vector2=Vector2(game.free_cell(actor.position+Vector3(3,0,3)))*game.CELL
  game.hero.position=Vector3(start.x,game.surface_height(start)+0.05,start.y)
  game.navigate_to_actor(actor,"npc:"+npc)
  for i in range(160):
   await frames(1)
   if game.services_ui.window.visible:break
  check(game.services_ui.window.visible and game.services_ui.title==npc,"Walk up to NPC opens service "+npc)
 game.services_ui.close()
 game.paused=false
 for x in [-0.6,0.75,2.0]:
  game.hero.position=Vector3(x,game.surface_height(Vector2(x,17))+0.05,17)
  game.navigate_to(Vector3(x,0,32))
  for i in range(260):
   await frames(1)
   if game.hero.position.z>30:break
  check(game.hero.position.z>30,"South exit lane "+str(x)+" actual "+str(game.hero.position))
 Engine.time_scale=1
 var path: String=game.shared_path()
 var intact: String=FileAccess.get_file_as_string(path)
 var corrupt:=FileAccess.open(path,FileAccess.WRITE)
 corrupt.store_string("broken")
 corrupt.close()
 check(not game.load_shared() and game.storage_fault,"Corrupt shared ledger stops access instead of replaying an old backup")
 var repair:=FileAccess.open(path,FileAccess.WRITE)
 repair.store_string(intact)
 repair.close()
 check(game.load_shared() and game.shared_storage[0].count==20,"Isolated shared ledger restored without losing cross-role items")
 print("TOWN_SERVICES_16_PASS" if not failed else "TOWN_SERVICES_16_FAILED")
 game.queue_free()
 await frames(2)
 quit(1 if failed else 0)
