extends SceneTree
const G=preload("res://equipment_system.gd")
class FailingStore:
	extends "res://save_store.gd"
	func save_slot(_slot: int, _data: Dictionary) -> bool:
		last_error="测试写入失败"
		return false
var failures:=0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures+=1
		push_error(label)
func blank() -> Dictionary:
	var c: Dictionary={"quest":0,"field_quest":0,"loot_seed":123456,"name":"装备测试","profession":"剑仙","level":10,"xp":0,"hp":200,"stones":0,"victories":0,"created_at":"test","logged_out_at":"","zone":"town","position":[620,610],"progression_version":2,"estate":{"starter":true}}
	G.normalize(c)
	return c
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for slot in range(8):
		var previous: Dictionary={"attack":0,"defense":0,"hp":0}
		for quality in range(7):
			var item=G.make_item(slot,quality,10)
			for stat in ["attack","defense","hp"]:check(item.stats[stat]>previous[stat],"higher quality improves all attributes")
			previous=item.stats
	check(G.drop_category("wild",0.299)=="scatter" and G.drop_category("wild",0.30)=="none","wild 30 percent boundary")
	check(G.drop_category("dungeon",0.299)=="scatter" and G.drop_category("dungeon",0.30)=="set","dungeon 30/70 boundary")
	var sample=blank()
	var drops=G.roll_wild(sample,7,10000)
	check(drops.size()>2800 and drops.size()<3200,"sampled wild drop probability close to 30 percent")
	var qualities: Dictionary={}
	for item in drops:
		check(int(item.quality) in [0,1] and item.set_id=="","wild only gray/white scatter")
		qualities[item.quality]=true
	check(qualities.size()==2,"both wild qualities can drop")
	var same_a=blank()
	var same_b=blank()
	check(G.roll_wild(same_a,9,20)==G.roll_wild(same_b,9,20),"same saved RNG gives same normal/quick loot")
	var rng_saved=same_a.duplicate(true)
	check(G.roll_wild(same_a,9,20)==G.roll_wild(rng_saved,9,20),"RNG resumes exactly after save roundtrip")
	var defs: Dictionary={"test":{"name":"测试套装","bonuses":{2:{"attack":2,"defense":2,"hp":2},4:{"attack":4,"defense":4,"hp":4},6:{"attack":6,"defense":6,"hp":6},8:{"attack":8,"defense":8,"hp":8}}}}
	var gear: Array=[]
	var base_attack:=0
	for i in range(8):
		var item=G.make_item(i,3,10,"test")
		base_attack+=int(item.stats.attack)
		gear.append(item)
		var total=G.totals(gear,defs)
		var expected:=0
		for n in [2,4,6,8]:
			if i+1>=n:expected+=n
		check(total.attack==base_attack+expected,"2/4/6/8 bonuses accumulate at exact thresholds")
	var game=load("res://main.tscn").instantiate()
	game.store.directory="res://tests/equipment-v6-saves"
	root.add_child(game)
	await process_frame
	game.character=blank()
	game.slot=0
	game.show_world()
	game.character.quest=5
	game.migrate()
	check(game.character.inventory[0].uid=="xianyuan_5" and game.character.inventory[0].quality==3,"level-five blue set gift")
	game.character.field_quest=4
	game.migrate()
	check(game.character.inventory[1].uid=="xianyuan_10" and game.character.inventory[1].slot==2,"level-ten blue set gift")
	game.migrate()
	var count:=0
	for item in game.character.inventory:
		if G.valid(item):count+=1
	check(count==2,"migration and repeated quest calls never duplicate gifts")
	game.toggle_menu(2)
	var grid=game.menu_window.get_node("Content/InventorySlots")
	grid.get_child(0).pressed.emit()
	check(game.character.equipment[0].uid=="xianyuan_5","bag click equips item")
	var one=game.gear_stats()
	game.equip_from_bag(1)
	var two=game.gear_stats()
	check(two.active_bonuses.size()==1 and two.sets.xianyuan==2,"two-piece Xianyuan active")
	var sword=game.character.equipment[0]
	var robe=game.character.equipment[2]
	check(two.attack==sword.stats.attack+robe.stats.attack+8 and two.defense==sword.stats.defense+robe.stats.defense+4,"set bonuses included in derived attributes")
	check(game.max_hp()==200+sword.stats.hp+robe.stats.hp+40,"equipment and set HP contributes to max HP")
	game.character.inventory[0]=G.make_item(0,0,5,"","replacement")
	check(game.equip_from_bag(0),"same-slot replacement succeeds")
	check(game.character.inventory[0].uid=="xianyuan_5" and game.character.equipment[0].uid=="replacement","replaced gear returns to clicked bag slot")
	check(game.gear_stats().active_bonuses.is_empty(),"set bonus removed immediately on replacement")
	game.character.hp=game.max_hp()
	game.close_menu()
	game.toggle_menu(0)
	var slots=null
	for child in game.menu_window.get_node("Content").get_children():
		if child is HBoxContainer and child.has_node("EquipmentSlots"):slots=child.get_node("EquipmentSlots")
	slots.get_child(0).pressed.emit()
	check(game.character.equipment[0].is_empty(),"character slot click unequips")
	check(game.character.hp<=game.max_hp(),"unequip clamps HP without healing exploit")
	for i in range(500):game.character.inventory[i]=G.make_item(i%8,0,1,"","full_%d" % i)
	var robe_uid=game.character.equipment[2].uid
	check(not game.unequip_slot(2) and game.character.equipment[2].uid==robe_uid,"full bag prevents unequip without item loss")
	var pending_before=game.character.pending_loot.size()
	G.receive(game.character,G.make_item(7,1,5,"","queued"))
	check(game.character.pending_loot.size()==pending_before+1,"full bag drop queued safely")
	game.character.inventory[4]={}
	game.claim_pending_equipment()
	check(game.character.inventory[4].uid=="queued","pending item claimed into free slot")
	var real_store=game.store
	var before_failure=game.character.duplicate(true)
	game.store=FailingStore.new()
	check(not game.equip_from_bag(4),"failed save rejects equip")
	check(game.character.inventory==before_failure.inventory and game.character.equipment==before_failure.equipment,"failed equip rolls back without losing items")
	game.store=real_store
	game.close_menu()
	game.character.zone="field"
	game.character.field_quest=2
	game.character.cleared=[]
	game.character.level=7
	game.character.hp=game.max_hp()
	game.show_world()
	game.start_battle(2)
	game.begin_round()
	var expected_attack=32+7*3+int(game.gear_stats().attack)
	game.resolve_player_hit(false)
	check(game.enemy_hp==game.max_enemy_hp-expected_attack,"gear attack affects actual battle")
	var hp_before=game.combat_hp
	var expected_damage=maxi(1,26-int(game.gear_stats().defense))
	game.resolve_enemy_hit(false)
	check(game.combat_hp==hp_before-expected_damage,"gear defense reduces actual enemy damage")
	game.quick_battle()
	var before_serial=game.character.gear_serial
	game.settle_battle()
	check(game.character.gear_serial==before_serial,"settlement cannot repeat item rolls")
	game.return_from_battle()
	game.persist()
	var saved=game.character.duplicate(true)
	game.logout()
	game.enter_character(0)
	check(game.character.equipment==saved.equipment and game.character.inventory==saved.inventory and game.character.pending_loot==saved.pending_loot,"gear, bag and pending loot roundtrip")
	check(game.character.reward_claims==saved.reward_claims,"quest gift claims persisted")
	game.store.delete_slot(0)
	game.character={}
	print("EQUIPMENT TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
