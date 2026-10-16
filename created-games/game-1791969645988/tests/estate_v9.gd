extends SceneTree
const R=preload("res://retainer_system.gd")
const W=preload("res://wild_spawns.gd")
var failures:=0
func check(ok: bool, title: String) -> void:
	if not ok: failures+=1; push_error(title)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var c: Dictionary={"level":10,"realm":"练气期","stones":24,"cleared":[0]}
	R.normalize(c)
	c.retainers.refresh_at=500
	var offers: Array=c.retainers.offers.duplicate(true)
	check(R.refresh_paid(c,450) and c.stones==12 and c.retainers.refresh_at==500,"paid refresh costs twelve keeps active deadline")
	check(c.retainers.offers!=offers,"paid refresh replaces offers")
	check(R.refresh_paid(c,550) and c.stones==0 and c.retainers.refresh_at==500,"paid refresh after free ready keeps ready")
	check(R.refresh(c,550) and c.retainers.refresh_at==610 and c.stones==0,"free refresh coexists with paid")
	var before:=c.duplicate(true)
	check(not R.refresh_paid(c,560) and c==before,"insufficient currency no mutation")
	W.normalize(c,100)
	check(W.dead(c,0,129) and not W.dead(c,0,130),"legacy cleared respawns at thirty seconds")
	W.killed(c,1,100)
	check(not W.expire(c,129) and W.expire(c,130) and c.cleared==[0],"respawn does not erase quest history")
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/v9-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="刷新测试"; game.finish_creation()
	game.character.level=10; game.character.realm="练气期"; game.character.zone="field"; game.character.quest=5; game.character.field_quest=4; game.character.cleared=[0,1,2]; game.character.hp=game.max_hp(); game.show_world()
	game.character.monster_respawns={}
	game.start_battle(0); game.quick_battle()
	check(game.mode=="result" and game.monster_dead(0),"victory marks monster dead")
	check(game.character.field_quest==4,"repeat kill does not reset completed quest")
	var stones:=int(game.character.stones); var xp:=int(game.character.xp)
	game.return_from_battle(); game.start_battle(0)
	check(game.mode=="map","cannot fight during respawn cooldown")
	game.character.monster_respawns["0"]=int(Time.get_unix_time_from_system())-1
	game._process(1.0); check(not game.monster_dead(0),"runtime respawn tick revives monster")
	game.start_battle(0); game.quick_battle()
	check(game.character.stones>stones,"repeat victory awards currency again")
	game.return_from_battle(); game.toggle_menu(2)
	var cell=game.menu_window.get_node("Content/InventorySlots").get_child(49)
	check(cell.get_theme_stylebox("normal").border_width_left>=2,"empty inventory borders visible")
	game.close_menu(); game.estate_ui.section=""; game.toggle_menu(3)
	check(not game.menu_window.visible and game.menu_layer.get_node("EstateBackdrop").size==Vector2(1280,800),"full screen estate map")
	check(game.menu_layer.get_node("EstateBackdrop").texture!=null,"estate background integrated")
	game.estate_ui.navigate("药园"); await process_frame
	check(game.estate_ui.plots[0].get_node("PlotArt").texture is AtlasTexture,"empty plot image")
	game.estate_ui.plant("qing",0)
	check(game.estate_ui.plots[0].get_node("PlotArt").texture.region.position.x==499,"growing plot image")
	game.character.estate.plots[0].ready_at=0; game.estate_ui.update_plots()
	check(game.estate_ui.plots[0].get_node("PlotArt").texture.region.position.x==1014,"mature plot image with roots seeds")
	game.persist(); var state=game.character.monster_respawns.duplicate(true)
	game.logout(); game.enter_character(0)
	check(game.character.monster_respawns==state,"respawn timers persist")
	game.store.delete_slot(0); game.character={}
	print("V9 TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
