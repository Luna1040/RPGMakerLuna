extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("run")
func verify(game, title: String) -> void:
	for i in range(4): await process_frame
	var rect: Rect2=game.menu_window.get_global_rect()
	print(title," window ",rect)
	if rect.end.x>1280 or rect.end.y>800:
		failures+=1; push_error(title+" window overflow")
	var content=game.menu_window.get_node("Content")
	for item in content.get_children():
		if item is Control:
			if item.get_global_rect().end.x>rect.end.x+1 or item.get_global_rect().end.y>rect.end.y+1:
				failures+=1; push_error(title+" child overflow "+item.name)
func run() -> void:
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/estate-layout-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="布局测试"; game.finish_creation()
	game.toggle_menu(2); await verify(game,"backpack")
	game.close_menu(); game.toggle_menu(3)
	for title in ["","药园","洞府","仓库","炼丹炉","炼器室"]:
		game.estate_ui.navigate(title); await verify(game,"estate-"+title)
	game.store.delete_slot(0); game.character={}
	print("ESTATE LAYOUT TEST: ","PASS" if failures==0 else "FAIL")
	quit(failures)
