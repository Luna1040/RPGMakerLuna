extends SceneTree
const D=preload("res://dungeon_system.gd")
const E=preload("res://estate_system.gd")
const P=preload("res://progression_system.gd")
const R=preload("res://retainer_system.gd")
const G=preload("res://equipment_system.gd")
class FailingStore:
	extends "res://save_store.gd"
	func save_slot(_slot: int, _c: Dictionary) -> bool: last_error="test failure"; return false
var failures:=0
func check(ok: bool, title: String) -> void:
	if not ok: failures+=1; push_error(title)
func fixture() -> Dictionary:
	var c: Dictionary={"level":10,"xp":0,"hp":200,"realm":"练气期","stones":10000,"victories":0,"loot_seed":12345,"balance_version":11}
	G.normalize(c); E.normalize(c); R.normalize(c); D.normalize(c,0)
	c.retainers.following.append(c.retainers.offers[0].duplicate(true))
	c.dungeon.wins=1
	return c
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var c:=fixture(); c.dungeon.wins=0
	var before:=c.duplicate(true)
	check(D.sweep(c,0).has("error") and c==before,"uncleared dungeon cannot sweep")
	c=fixture(); c.stones=999; before=c.duplicate(true)
	check(D.sweep(c,0).has("error") and c==before,"insufficient sweep balance unchanged")
	c=fixture(); c.dungeon.used=5
	check(D.sweep(c,0).has("error"),"sweep consumes challenge allowance")
	check(D.purchase(c,0) and c.stones==7000 and D.remaining(c)==1,"three thousand buys one extra")
	check(not D.sweep(c,0).has("error") and c.dungeon.used==6,"purchased attempt usable for sweep")
	D.normalize(c,57600); check(D.remaining(c)==5 and c.dungeon.bought==0,"UTC8 resets purchased daily allowance")
	var swept:=fixture(); var manual:=swept.duplicate(true)
	var result:=D.sweep(swept,0)
	check(not result.has("error") and result.xp==200 and result.stones==5160 and swept.level==12,"full sweep reward and progression")
	D.enter(manual,0)
	for floor in range(1,4):
		for pack in range(5):
			var boss:=pack==4; var level: int=12+floor*2 if boss else 9+floor*2
			var experience:=P.dungeon_xp(floor,boss)
			P.add(manual,experience); R.award_battle(manual,experience)
			D.loot(manual,boss,1 if boss else 3,level)
			manual.stones+=level*2*(1 if boss else 3)*5
			manual.victories+=1; D.win(manual,pack)
			if boss: E.put(manual.inventory,E.seed_item(["jade","violet","sun"][floor-1],1))
		if floor<3: D.next_floor(manual)
	check(swept.inventory==manual.inventory and swept.pending_loot==manual.pending_loot and swept.loot_rng_state==manual.loot_rng_state,"sweep rolls exact same complete-run loot and seeds")
	check(swept.retainers.following==manual.retainers.following and swept.stones==manual.stones-1000 and swept.xp==manual.xp,"same xp and companion xp with fee difference only")
	c=fixture(); D.enter(c,0); before=c.duplicate(true)
	check(D.sweep(c,0).has("error") and c==before,"sweep does not erase unfinished manual run")
	c=fixture()
	for i in range(500): c.inventory[i]=G.make_item(i%8,0,1)
	result=D.sweep(c,0)
	check(not result.has("error") and c.pending_loot.size()>=6,"full bag sweep queues equipment and three seeds")
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/sweep-v12-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="速刷测试"; game.finish_creation()
	game.character.level=10; game.character.realm="练气期"; game.character.zone="wilds"; game.character.stones=10000; game.character.dungeon.wins=1; game.show_world()
	game.dungeon_world.handle("enter")
	check(game.modal.get_child(0).get_child_count()>=6,"entrance includes sweep and buy controls")
	var store=game.store; before=game.character.duplicate(true); game.store=FailingStore.new()
	game.dungeon_world.sweep_once(); check(game.character==before,"failed sweep save refunds fee quota and loot")
	game.dungeon_world.purchase_once(); check(game.character==before,"failed purchase save refunds fee and quota")
	game.store=store; game.close_dialog(); game.dungeon_world.purchase_once(); game.close_dialog(); game.dungeon_world.sweep_once()
	check(game.character.dungeon.bought==1 and game.character.dungeon.used==1 and game.character.level==12,"UI purchase and sweep persist")
	game.close_dialog(); game.persist(); var saved=game.character.duplicate(true); game.logout(); game.enter_character(0)
	check(game.character.dungeon==saved.dungeon and game.character.inventory==saved.inventory and game.character.stones==saved.stones,"sweep rewards and purchased quota save roundtrip")
	game.store.delete_slot(0); game.character={}
	print("SWEEP TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
