extends SceneTree
var failures:=0
func check(ok: bool, description: String) -> void:
	if not ok:
		failures+=1
		push_error(description)
func key(game, code: int, echo: bool=false) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.pressed=true
	event.echo=echo
	game._input(event)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	game.store.directory="res://tests/menu-test-saves"
	root.add_child(game)
	await process_frame
	for i in range(4):
		game.create_character(i)
		check(game.profession_input.item_count==4,"four professions selectable")
		game.name_input.text="菜单测试%d" % i
		game.profession_input.select(i)
		game.finish_creation()
		check(game.character.profession==game.PROFESSIONS[i],"new profession save")
		check(game.store.load_slot(i).profession==game.PROFESSIONS[i],"profession persisted")
	game.character.stones=888
	var bar=game.screen.get_node("MenuBar").get_child(0)
	check(bar.get_child_count()==7,"seven bottom menus")
	for i in range(7):
		var item=bar.get_child(i)
		check(item.get_child(0) is Sprite2D,"generated menu icon integrated")
		check((item.get_child(0).texture.get_size()*item.get_child(0).scale).is_equal_approx(Vector2(42,42)),"icon rendered at 42px")
		key(game,game.MENU_KEYS[i])
		check(game.active_menu==i,"keyboard opens menu")
		var content=game.menu_window.get_node("Content")
		if i==0:
			var found=false
			for child in content.get_children():
				if child is HBoxContainer:
					var grid=child.get_node_or_null("EquipmentSlots")
					if grid!=null:
						found=true
						check(grid.get_child_count()==8,"eight equipment slots")
			check(found,"equipment grid visible")
		elif i==2:
			check(content.get_node("InventorySlots").get_child_count()==50,"forty bag slots")
			check(content.get_node("GoldBalance").text=="人物资产 · 灵石 888","only stones balance displayed")
		elif i==4:
			check(content.get_node("TaskTabs").get_child_count()==3,"three task categories")
			game.show_task_category("已接任务")
			check(game.task_category=="已接任务","task tab switches")
		elif i==6:
			content.get_node("Volume").value=35
			content.get_node("Mute").button_pressed=true
			check(is_equal_approx(float(game.character.settings.volume),0.35),"volume changes live")
			check(AudioServer.is_bus_mute(0),"mute applied")
			check(game.store.load_slot(3).settings.mute,"settings saved")
		key(game,KEY_ESCAPE)
		check(game.active_menu==-1,"escape closes menu")
	key(game,KEY_TAB)
	check(game.active_menu==2,"fixed Tab inventory binding")
	key(game,KEY_TAB,true)
	check(game.active_menu==2,"key echo ignored")
	key(game,KEY_TAB)
	check(game.active_menu==-1,"same shortcut toggles closed")
	key(game,KEY_Q)
	check(game.active_menu==4,"fixed Q task binding")
	var old_pos=game.player_pos
	game.destination=old_pos+Vector2(100,0)
	game._process(1.0)
	check(game.player_pos==old_pos,"menu blocks map movement")
	game.close_menu()
	var groups=game.get_task_groups()
	check(groups["可接任务"].size()==1 and groups["已接任务"].is_empty(),"new save has available first task")
	game.player_pos=game.TOWN_POS[0]+game.NPC_APPROACH
	game.talk(0)
	check(game.get_task_groups()["已接任务"].size()==1,"NPC dialogue records accepted task")
	game.close_dialog()
	game.complete_town(0)
	check(game.get_task_groups()["已完成任务"].size()==1,"reward marks task completed")
	check(game.get_task_groups()["可接任务"].size()==1,"next task becomes available")
	game.character.profession="法修"
	game.character.erase("stones")
	game.character.gold=321
	game.migrate()
	check(game.character.profession=="阴阳" and game.character.stones==321 and not game.character.has("gold"),"legacy profession and currency migration")
	game.migrate()
	check(game.character.stones==321,"currency conversion only once")
	game.toggle_menu(6)
	var content=game.menu_window.get_node("Content")
	var commands=content.get_child(content.get_child_count()-2)
	check(commands.get_child(2).text=="退出游戏" and commands.get_child(2).pressed.is_connected(game.save_and_exit),"exit saves before quitting")
	commands.get_child(1).pressed.emit()
	check(game.mode=="slots" and game.character.is_empty(),"select other character returns to slots")
	check(game.store.load_slot(3).stones==321,"switching character saves assets")
	game.enter_character(3)
	check(game.character.profession=="阴阳" and game.character.settings.mute,"reload restores migration and settings")
	for i in range(4): game.store.delete_slot(i)
	game.character={}
	print("MENU TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
