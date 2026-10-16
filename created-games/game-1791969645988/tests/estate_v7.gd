extends SceneTree
const E=preload("res://estate_system.gd")
const G=preload("res://equipment_system.gd")
class FailingStore:
	extends "res://save_store.gd"
	func save_slot(_slot: int, _data: Dictionary) -> bool:
		last_error="test write failure"
		return false
var failures:=0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	game.store.directory="res://tests/estate-v7-saves"
	root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="仙园测试"; game.finish_creation()
	check(game.character.inventory.size()==500,"500 slots")
	check(game.character.estate.storage.size()==1000 and game.character.estate.plots.size()==20,"estate capacities")
	check(game.store.timestamp(0)=="1970-01-01T08:00:00+08:00","UTC+8 epoch")
	var dates={"created_at":"1969-12-31T16:00:00-08:00","logged_out_at":""}
	game.store.normalize_dates(dates)
	check(dates.created_at==game.store.timestamp(0),"legacy timestamp preserves instant")
	game.character.erase("stones"); game.character.gold=123
	game.migrate(); game.migrate()
	check(game.character.stones==123 and not game.character.has("gold"),"currency migration idempotent")
	game.toggle_menu(2); game.change_bag_page(9)
	check(game.bag_page==9 and game.menu_window.get_node("Content/InventorySlots").get_child_count()==50,"last bag page visible")
	game.close_menu(); game.toggle_menu(2); check(game.bag_page==0,"fresh open resets page")
	game.close_menu(); game.toggle_menu(3)
	for title in ["药园","洞府","仓库","炼丹炉","炼器室",""]:
		game.estate_ui.navigate(title); await process_frame
		check(game.active_menu==3,"all facility views open")
	game.estate_ui.navigate("药园")
	var drag=preload("res://seed_drag.gd").new(); drag.seed_id="qing"; drag.text="种子"
	check(game.estate_ui.plots[0]._can_drop_data(Vector2.ZERO,{"seed_id":"qing"}),"plot accepts seed drag")
	drag.free()
	game.estate_ui.plots[1]._drop_data(Vector2.ZERO,{"seed_id":"ning"})
	check(not game.character.estate.plots[1].is_empty(),"drag drop reaches planting transaction")
	var real_store=game.store
	var rollback=game.character.duplicate(true)
	game.store=FailingStore.new()
	game.estate_ui.plant("qing",2)
	check(game.character==rollback,"failed save rolls back estate transaction")
	game.store=real_store
	var c: Dictionary=game.character
	var start:=E.count(c.inventory,"seed","qing")
	check(E.plant(c,0,"qing",100),"seed plants")
	check(E.count(c.inventory,"seed","qing")==start-1,"one seed consumed")
	check(not E.plant(c,0,"qing",100),"occupied plot rejects second seed")
	check(not E.harvest(c,0,109) and E.harvest(c,0,110),"exact ten-second harvest")
	check(E.count(c.inventory,"herb","qing")==3,"harvest yields herbs")
	check(E.alchemy(c,false) and E.count(c.inventory,"herb","qing")==1,"alchemy consumes ingredients")
	var before:=c.duplicate(true)
	check(not E.alchemy(c,true) and c==before,"insufficient recipe rolls back all inputs")
	var index:=G.empty_bag_slot(c)
	c.inventory[index]=G.make_item(0,3,5,"","forge-test")
	check(E.dismantle(c,index),"dismantles equipment")
	check(E.count(c.inventory,"fragment","3")==E.YIELDS[3],"same quality fragments")
	E.put(c.inventory,E.stack("fragment","3","蓝色装备碎片",30,3))
	c.stones=10000
	var old_stones:=int(c.stones); var fragments:=E.count(c.inventory,"fragment","3")
	check(E.craft(c,3,2),"craft succeeds")
	check(c.stones==old_stones-E.craft_cost(3) and E.count(c.inventory,"fragment","3")==fragments-E.craft_need(3),"craft costs and fragment loss")
	for q in range(1,7):check(E.YIELDS[q]>E.YIELDS[q-1] and E.craft_need(q)>E.YIELDS[q],"higher quality yield and loss")
	var moved: Dictionary=c.inventory[0].duplicate(true)
	check(E.transfer(c,false,0) and c.inventory[0].is_empty(),"deposit stack")
	check(E.transfer(c,true,0) and E.count(c.inventory,moved.kind,moved.id)==int(moved.qty),"withdraw stack")
	game.estate_ui.navigate("洞府"); game.estate_ui.toggle_rest()
	c.hp=1; var xp:=int(c.xp); game._process(5.0)
	check(c.hp>1 and c.xp==xp+1,"meditation restores health and grants slow xp")
	game.close_menu(); game._process(10.0)
	check(c.xp==xp+1,"meditation stops outside cave")
	game.persist(); var saved:=c.duplicate(true)
	game.logout(); game.enter_character(0)
	check(game.character.inventory==saved.inventory and game.character.estate==saved.estate,"estate and inventory persist")
	var full: Dictionary=game.character.duplicate(true)
	for i in range(500): full.inventory[i]=G.make_item(i%8,0,1)
	full.estate.plots[0]={"id":"ning","ready_at":0}
	check(not E.harvest(full,0,100) and not full.estate.plots[0].is_empty(),"full bag preserves mature crop")
	for i in range(1000): full.estate.storage[i]=G.make_item(i%8,0,1)
	var before_full=full.duplicate(true)
	check(not E.transfer(full,false,0) and full==before_full,"full storage rejects deposit without loss")
	full.inventory[1]=E.stack("fragment","0","gray fragments",100)
	full.stones=1000
	before_full=full.duplicate(true)
	check(not E.craft(full,0,0) and full==before_full,"full bag craft refunds materials and stones")
	game.store.delete_slot(0); game.character={}
	print("ESTATE TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
