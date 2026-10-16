extends SceneTree
const E=preload("res://estate_system.gd")
const G=preload("res://equipment_system.gd")
var failures:=0
var pictures:=0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1; push_error(message)
func grids(node: Node) -> Array:
	var found: Array=[]
	if node is GridContainer and node.columns==10 and node.get_child_count()==50: found.append(node)
	for child in node.get_children(): found.append_array(grids(child))
	return found
func verify_cells(grid: GridContainer) -> void:
	for cell in grid.get_children():
		check(cell.clip_contents,"slot clips its contents")
		for child in cell.get_children():
			if child is TextureRect:
				pictures+=1
				check(cell.get_global_rect().grow(0.1).encloses(child.get_global_rect()),"icon inside slot: "+str(child.get_global_rect())+" vs "+str(cell.get_global_rect()))
				check(child.size.x<=30 and child.size.y<=30,"icon has bounded pixel size")
				check(child.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"icon preserves aspect")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/slot-v13-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="物品格测试"; game.finish_creation()
	game.character.level=10
	var samples: Array=[G.make_item(0,0,5),E.seed_item("qing",123),E.stack("breakthrough_pill","foundation","筑基丹",2),E.stack("fragment","3","蓝色装备碎片",9999,3),G.make_item(1,3,10,"xiaoyao"),E.stack("potion","weak","青灵丹",88),E.seed_item("jade",30)]
	for i in range(samples.size()):
		game.character.inventory[i]=samples[i].duplicate(true)
		game.character.estate.storage[i]=samples[i].duplicate(true)
	game.character.inventory[499]=E.seed_item("sun",1)
	game.character.estate.storage[999]=G.make_item(5,3,10,"xiaoyao")
	game.toggle_menu(2)
	for frame in range(4): await process_frame
	verify_cells(game.menu_window.get_node("Content/InventorySlots"))
	var assets=game.menu_window.get_node("Content/GoldBalance")
	for child in assets.get_children():
		if child is TextureRect: check(assets.get_global_rect().grow(0.1).encloses(child.get_global_rect()),"currency art inside asset line")
	game.change_bag_page(9)
	for frame in range(4): await process_frame
	verify_cells(game.menu_window.get_node("Content/InventorySlots"))
	game.close_menu(); game.toggle_menu(3); game.estate_ui.navigate("仓库")
	for frame in range(4): await process_frame
	var storage_grids:=grids(game.menu_window)
	check(storage_grids.size()==2,"both bag and storage grids visible")
	for grid in storage_grids: verify_cells(grid)
	game.estate_ui.storage_turn(true,19)
	for frame in range(4): await process_frame
	for grid in grids(game.menu_window): verify_cells(grid)
	check(pictures>=20,"all item families and final pages exercised")
	game.store.delete_slot(0); game.character={}
	print("SLOT BOUNDS TEST: ", "PASS" if failures==0 else "FAIL", " failures=", failures, " icons=", pictures)
	quit(0 if failures==0 else 1)
