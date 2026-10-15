extends SceneTree
var game: Node
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
	if not ok: failures+=1; push_error(title)
func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.pressed=true
	Input.parse_input_event(event)
func run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.active_slot=1
	game.character={"name":"菜单测试","profession":"刀客"}
	game.menu.hide()
	game.paused=false
	var ui=game.get_node("GameMenus")
	key(KEY_TAB)
	await process_frame
	check(ui.current==1 and ui.bag_slots.size()==40,"Tab opens forty-slot bag")
	check(game.paused,"Menus freeze world")
	for i in range(4): await process_frame
	check(ui.window.position.y+ui.window.size.y<=685,"Bag stays above bottom bar")
	game.hp=1
	game.potions=3
	ui.use_potion()
	check(game.potions==2 and game.hp==61,"Potion inventory and health share live data")
	key(KEY_TAB)
	await process_frame
	check(ui.current==-1 and not game.paused,"Same key closes and restores pause")
	key(KEY_Q)
	await process_frame
	check(ui.current==2,"Q opens quests")
	game.training_state=2
	ui.quest_tab=1
	ui.rebuild()
	key(KEY_C)
	await process_frame
	check(ui.current==0,"C opens character")
	game.level=9
	ui.toggle(3)
	check(not game.lightness,"Level nine cannot learn lightness")
	game.level=10
	game.begin_leap()
	check(game.lightness,"Level ten lightness connects to game")
	key(KEY_ESCAPE)
	await process_frame
	check(ui.current==-1,"Escape closes focused menu")
	key(KEY_ESCAPE)
	await process_frame
	check(ui.current==4,"Escape opens system")
	ui.close()
	check(not game.paused,"Pause restored after switching panels")
	game.active_slot=0
	print("MENU_CHECK_PASS" if failures==0 else "MENU_CHECK_FAILED")
	game.free()
	quit(1 if failures else 0)
