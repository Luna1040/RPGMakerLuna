extends SceneTree
const R=preload("res://retainer_system.gd")
class FailingStore:
	extends "res://save_store.gd"
	func save_slot(_slot: int, _data: Dictionary) -> bool:
		last_error="test write failure"
		return false
var failures:=0
func check(ok: bool, title: String) -> void:
	if not ok: failures+=1; push_error(title)
func blank() -> Dictionary:
	var c: Dictionary={"level":10,"realm":"练气期"}
	R.normalize(c); return c
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var c:=blank()
	check(c.retainers.offers.size()==12,"twelve initial offers")
	for level in [10,20,30,40,70]:
		c.level=level; check(R.reserve_limit(c)==mini(8,level/10*2),"reserve level caps")
	for realm in ["练气期","筑基期","金丹期","元婴期","化神期"]:
		c.realm=realm; check(R.follow_limit(c)==mini(4,["练气期","筑基期","金丹期","元婴期","化神期"].find(realm)+1),"realm caps")
	c=blank(); c.level=9
	check(not R.recruit(c,0),"level nine cannot recruit")
	c.level=10
	check(R.recruit(c,0) and c.retainers.reserve[0].level==1 and c.retainers.offers[0].is_empty(),"recruit level one into reserve leaves empty")
	check(R.recruit(c,1) and not R.recruit(c,2),"full reserve blocks recruitment")
	check(R.deploy(c,0) and not R.deploy(c,0),"one following at qi realm")
	check(R.recruit(c,2) and not R.withdraw(c,0),"full reserve blocks withdrawal")
	var before:=c.duplicate(true)
	check(not R.refresh(c,int(c.retainers.refresh_at)-1) and c==before,"cooldown rejects without mutation")
	check(R.refresh(c,int(c.retainers.refresh_at)) and not c.retainers.offers[0].is_empty(),"exact minute refresh replaces whole field")
	var reserve_xp:=int(c.retainers.reserve[0].xp)
	R.award_battle(c,84)
	check(c.retainers.following[0].level==2 and c.retainers.following[0].xp==68,"double battle xp and level up")
	check(c.retainers.reserve[0].xp==reserve_xp,"reserve gets no battle xp")
	check(R.pick_root(0)==0 and R.pick_root(49.999)==0 and R.pick_root(50)==1 and R.pick_root(99.49)==4 and R.pick_root(99.5)==5,"rarity probability boundaries")
	for q in range(1,6):
		check(R.WEIGHTS[q]<R.WEIGHTS[q-1],"rarer roots lower probability")
		var low={"root":q-1,"level":2}; var high={"root":q,"level":2}
		check(R.stats(high).attack>R.stats(low).attack and R.stats(high).hp>R.stats(low).hp,"higher root grows more")
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/retainer-v8-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="散修测试"; game.finish_creation()
	game.character.level=10; game.character.realm="练气期"; game.character.zone="sect"; game.character.quest=5; game.character.field_quest=2; game.character.progression_version=2; game.show_world()
	game.player_pos=game.SECT_POS[2]+game.NPC_APPROACH; game.talk(2)
	check(is_instance_valid(game.modal),"new steward dialogue after approach")
	game.open_retainer_guide(); check(game.active_menu==1 and game.character.retainers.introduced,"guide opens retainer menu")
	var original_store=game.store
	var original_state: Dictionary=game.character.retainers.duplicate(true)
	game.store=FailingStore.new()
	game.retainer_ui.manage(2,0)
	check(game.character.retainers==original_state,"failed save rolls recruitment back")
	game.store=original_store
	game.retainer_ui.manage(2,0); game.retainer_ui.manage(1,0)
	for i in range(5): await process_frame
	var rect: Rect2=game.menu_window.get_global_rect()
	check(rect.end.x<=1280 and rect.end.y<=712,"retainer window fits viewport")
	var grids:=[]
	for child in game.menu_window.get_node("Content").get_children():
		if child is GridContainer: grids.append(child)
		if child is Control: check(child.get_global_rect().end.y<=rect.end.y+1,"menu content fits")
	check(grids.size()==3 and grids[0].get_child_count()==4 and grids[1].get_child_count()==8 and grids[2].get_child_count()==12,"4/8/12 slots in four columns")
	var saved: Dictionary=game.character.duplicate(true)
	game.close_menu(); game.character.zone="field"; game.character.cleared=[]; game.character.hp=game.max_hp(); game.show_world(); var fixture: Dictionary=game.character.duplicate(true)
	game.start_battle(0); game.quick_battle(); var quick: Dictionary=game.character.duplicate(true)
	var level:=int(game.character.retainers.following[0].level); var xp:=int(game.character.retainers.following[0].xp)
	game.settle_battle(); check(game.character.retainers.following[0].level==level and game.character.retainers.following[0].xp==xp,"settlement xp awarded once")
	game.return_from_battle(); game.character=fixture.duplicate(true); game.show_world(); game.start_battle(0)
	check(game.battle_retainer_nodes.size()==1,"following companion in battle")
	for i in range(1500):
		if game.mode!="battle": break
		game.advance_battle(0.1)
	check(game.character.retainers.following==quick.retainers.following and game.character.xp==quick.xp and game.character.hp==quick.hp,"normal and quick same combat result and companion xp")
	game.return_from_battle(); game.persist(); var state=game.character.retainers.duplicate(true); game.logout(); game.enter_character(0)
	check(game.character.retainers==state,"retainers cooldown offers ranks xp save roundtrip")
	game.character.retainers.reserve.append(game.character.retainers.following.pop_back())
	var uid=game.character.retainers.reserve[0].uid
	check(R.dismiss(game.character,0) and game.character.retainers.reserve.is_empty(),"dismiss permanently removes reserve")
	game.store.delete_slot(0); game.character={}
	print("RETAINER TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)

