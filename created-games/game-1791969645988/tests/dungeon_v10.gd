extends SceneTree
const D=preload("res://dungeon_system.gd")
const G=preload("res://equipment_system.gd")
class FailingStore:
	extends "res://save_store.gd"
	func save_slot(_slot: int, _data: Dictionary) -> bool:
		last_error="test write failure"
		return false
var failures:=0
func check(ok: bool, title: String) -> void:
	if not ok: failures+=1; push_error(title)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var c: Dictionary={"level":10,"loot_seed":12345}
	G.normalize(c); D.normalize(c,0)
	check(D.day(0)=="1970-01-01" and D.day(57599)=="1970-01-01" and D.day(57600)=="1970-01-02","UTC8 daily boundary")
	for i in range(5):
		check(D.enter(c,0),"five daily entries allowed")
		check(D.enter(c,0) and c.dungeon.used==i+1,"resume consumes no additional entry")
		c.dungeon.run.active=false
	check(not D.enter(c,0),"sixth entry denied")
	check(D.enter(c,57600) and c.dungeon.used==1,"new UTC8 day restores five")
	check(not D.ready(c,4),"boss locked behind four packs")
	for i in range(4):check(D.win(c,i),"four small packs")
	check(D.ready(c,4) and D.win(c,4) and not D.win(c,4),"boss clear idempotent")
	check(D.next_floor(c) and c.dungeon.run.floor==2 and c.dungeon.run.cleared.is_empty(),"floor gate requires clear")
	check(D.drop_category(false,0.0999)=="scatter" and D.drop_category(false,0.1)=="xiaoyao" and D.drop_category(false,0.2999)=="xiaoyao" and D.drop_category(false,0.3)=="none","small 10/20/70 percent boundary")
	check(D.drop_category(true,0.1999)=="scatter" and D.drop_category(true,0.2)=="xiaoyao" and D.drop_category(true,0.9999)=="xiaoyao","boss 20/80 percent boundary")
	var gear: Array=[]
	for slot in [1,3,4,5]:
		var item:=G.make_item(slot,3,10,"xiaoyao")
		check(item.quality==3 and item.level==10 and item.slot not in [0,2],"four blue set parts avoid Xianyuan")
		gear.append(item)
	var stats:=G.totals(gear)
	check(stats.sets.xiaoyao==4 and stats.active_bonuses.size()==2,"two and four piece bonuses active")
	var drops:=D.loot(c,true,100,14)
	check(drops.size()==100,"boss always one drop per kill")
	for item in drops:
		check(item.quality in [2,3],"only green or blue loot")
		if item.set_id=="xiaoyao":check(item.slot in [1,3,4,5] and item.level==10,"dungeon set contract")
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/dungeon-v10-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="万妖窟测试"; game.finish_creation()
	game.character.level=10; game.character.realm="练气期"; game.character.quest=5; game.character.field_quest=4; game.character.zone="sect"; game.show_world()
	game.player_pos=Vector2(1125,555); game.use_portal("sect_wilds")
	check(game.character.zone=="wilds" and game.ZONES.wilds.names.size()==1,"sect to new map with NPC")
	game.player_pos=game.ZONES.wilds.positions[0]+game.NPC_APPROACH; game.talk(0)
	check(is_instance_valid(game.modal),"new NPC dialogue")
	game.close_dialog()
	var original_store=game.store
	var original_character: Dictionary=game.character.duplicate(true)
	game.store=FailingStore.new(); game.dungeon_world.enter()
	check(game.character==original_character,"failed save refunds entry and restores map")
	game.store=original_store; game.close_dialog()
	game.dungeon_world.handle("enter"); game.dungeon_world.enter()
	check(game.character.zone=="cavern" and game.character.dungeon.used==1,"enter cave spends daily count")
	for slot in range(8): game.character.equipment[slot]=G.make_item(slot,4,10)
	game.character.hp=game.max_hp()
	game.dungeon_world.attack(4)
	check(game.mode=="map" and is_instance_valid(game.modal),"click boss before small packs blocked")
	game.close_dialog()
	for floor in range(1,4):
		for pack in range(5):
			game.character.hp=game.max_hp()
			game.dungeon_world.attack(pack)
			check(game.mode=="battle","each pack starts actual encounter")
			if floor==1 and pack in [0,4]:
				for tick in range(1200):
					if game.mode!="battle": break
					game.advance_battle(0.1)
			else: game.quick_battle()
			check(game.mode=="result" and pack in game.character.dungeon.run.cleared,"battle settlement clears pack")
			var after:=int(game.character.stones)
			game.settle_battle(); check(game.character.stones==after,"no repeat dungeon reward")
			game.return_from_battle()
		if floor<3:
			game.dungeon_world.handle("next")
			check(game.character.dungeon.run.floor==floor+1,"next layer gate")
	check(game.character.dungeon.run.completed and game.character.dungeon.wins==1,"all fifteen encounters finish dungeon")
	game.character.inventory[0]=G.make_item(1,3,10,"xiaoyao")
	var current_level:=int(game.character.level)
	game.character.level=9
	check(not game.equip_from_bag(0),"level nine cannot equip Xiaoyao")
	game.character.level=current_level
	check(game.equip_from_bag(0),"level ten plus can equip Xiaoyao")
	game.close_menu()
	game.persist(); var saved=game.character.dungeon.duplicate(true); game.logout(); game.enter_character(0)
	check(game.character.dungeon==saved,"dungeon progress and daily counts persist")
	game.dungeon_world.handle("exit"); check(game.character.zone=="wilds" and not game.character.dungeon.run.active,"completed run exit")
	game.store.delete_slot(0); game.character={}
	print("DUNGEON TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)

