extends SceneTree
const P=preload("res://progression_system.gd")
const B=preload("res://breakthrough_system.gd")
const E=preload("res://estate_system.gd")
const D=preload("res://dungeon_system.gd")
const R=preload("res://retainer_system.gd")
const G=preload("res://equipment_system.gd")
class FailingStore:
	extends "res://save_store.gd"
	func save_slot(_slot: int, _data: Dictionary) -> bool:
		last_error="test save failure"; return false
var failures:=0
func check(ok: bool, title: String) -> void:
	if not ok: failures+=1; push_error(title)
func fixture() -> Dictionary:
	var c: Dictionary={"level":20,"xp":0,"realm":"练气期","balance_version":11,"hp":300,"stones":0}
	G.normalize(c); E.normalize(c); return c
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var c:=fixture()
	check(B.resolve(c,false,0.29999)=="success" and c.realm=="筑基期","plain success below thirty percent")
	c=fixture(); check(B.resolve(c,false,0.3)=="failure" and c.level==19 and c.xp==0,"plain failure exact thirty boundary")
	check(B.resolve(c,false,0.0)=="blocked","must regain level twenty")
	P.add(c,100); check(c.level==20,"relevel to twenty")
	E.put(c.inventory,E.stack("breakthrough_pill","foundation","筑基丹",2,3))
	check(B.resolve(c,true,0.79999)=="success" and E.count(c.inventory,"breakthrough_pill","foundation")==1,"pill eighty percent consumes exactly one")
	check(R.follow_limit(c)==2,"foundation allows two followers")
	check(P.realm_stats(c).hp==150 and P.realm_stats(c).attack==25 and P.realm_stats(c).defense==15,"foundation stat bonus")
	P.add(c,100); check(c.level==21,"successful foundation lifts twenty cap")
	c=fixture(); E.put(c.inventory,E.stack("breakthrough_pill","foundation","筑基丹",1,3))
	check(B.resolve(c,true,0.8)=="failure" and E.count(c.inventory,"breakthrough_pill","foundation")==0,"pill failure at eighty consumes one")
	c=fixture(); var before:=c.duplicate(true)
	check(B.resolve(c,true,0)=="missing_pill" and c==before,"no free pill attempt")
	P.add(c,9999); check(c.level==20 and c.xp==0,"qi capped without banking excess xp")
	var migrated: Dictionary={"level":117,"xp":7,"realm":"练气期","dungeon":{"wins":5,"run":{}},"stones":5000}
	P.normalize(migrated); check(migrated.level==20 and migrated.xp==0 and migrated.stones==5000 and migrated.pre_v11_progress.level==117,"old inflated progression normalized with audit")
	P.normalize(migrated); check(migrated.level==20,"migration once only")
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/breakthrough-v11-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="筑基测试"; game.finish_creation()
	game.character.level=10; game.character.xp=0; game.character.realm="练气期"; game.character.quest=5; game.character.field_quest=4; game.character.zone="wilds"; game.show_world()
	for slot in range(8): game.character.equipment[slot]=G.make_item(slot,4,10)
	for run in range(5):
		game.dungeon_world.enter()
		for floor in range(1,4):
			for pack in range(5):
				game.character.hp=game.max_hp(); game.dungeon_world.attack(pack); game.quick_battle(); game.return_from_battle()
			if floor<3: game.dungeon_world.handle("next")
		check(game.character.level==12+run*2 and game.character.xp==0,"each full run grants exactly two levels")
		game.dungeon_world.handle("exit")
	check(game.character.level==20 and game.character.dungeon.wins==5,"five complete dungeons ten to twenty")
	for i in range(3):
		var id: String=["jade","violet","sun"][i]
		check(E.count(game.character.inventory,"seed",id)==5,"each full run collects all three seeds")
		check(E.plant(game.character,i,id,100) and E.harvest(game.character,i,110),"new seeds grow and harvest")
	check(E.foundation_pill(game.character) and E.count(game.character.inventory,"breakthrough_pill","foundation")==1,"three herbs brew foundation pill")
	var original_store=game.store; var before_save: Dictionary=game.character.duplicate(true)
	game.close_menu(); game.toggle_menu(3); game.estate_ui.navigate("洞府")
	game.store=FailingStore.new(); game.estate_ui.perform_breakthrough(true)
	check(game.character==before_save,"failed save rolls back attempt and pill")
	game.store=original_store
	for room in ["药园","炼丹炉","洞府"]:
		game.estate_ui.navigate(room)
		for tick in range(4): await process_frame
		var rect: Rect2=game.menu_window.get_global_rect()
		check(rect.end.y<=800,"new facility window fits")
		for child in game.menu_window.get_node("Content").get_children():
			if child is Control: check(child.get_global_rect().end.y<=rect.end.y+1,"new recipe and breakthrough controls fit")
	game.estate_ui.perform_breakthrough(true)
	check(E.count(game.character.inventory,"breakthrough_pill","foundation")==0 and int(game.character.breakthrough_attempts)==1,"real cave action persists one attempt and pill")
	check(game.character.realm=="筑基期" or game.character.level==19,"real breakthrough success or failure state")
	var saved: Dictionary=game.character.duplicate(true)
	game.close_menu(); game.logout(); game.enter_character(0)
	check(game.character.level==saved.level and game.character.realm==saved.realm and game.character.inventory==saved.inventory,"breakthrough inventory and realm survive reload")
	game.store.delete_slot(0); game.character={}
	print("BREAKTHROUGH TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
