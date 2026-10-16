extends SceneTree
var failures:=0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1; push_error(text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/estate-art-v12-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="仙园美术测试"; game.finish_creation()
	game.toggle_menu(3)
	var hashes: Array=[]
	for room in ["药园","洞府","仓库","炼丹炉","炼器室"]:
		game.estate_ui.navigate(room)
		for frame in range(4): await process_frame
		var image: Image=game.menu_layer.get_node("EstateBackdrop").texture.get_image()
		check(image.get_size()==Vector2i(1280,800),"full-size room illustration")
		var checksum:=hash(image.get_data())
		check(not checksum in hashes,"each room has a different background")
		hashes.append(checksum)
		var rect: Rect2=game.menu_window.get_global_rect()
		check(rect.end.x<=1280 and rect.end.y<=800,"room panel within viewport")
		for child in game.menu_window.get_node("Content").get_children():
			if child is Control: check(child.get_global_rect().end.y<=rect.end.y+1,"controls fit illustrated room")
	for id in ["qing","ning","weak","strong","stones","foundation"]:
		check(game.estate_ui.item_icon({"id":id}) is AtlasTexture,"resource icon available")
	check(game.estate_ui.item_icon({"kind":"fragment","id":"3"}) is AtlasTexture,"fragment icon available")
	game.store.delete_slot(0); game.character={}
	print("ESTATE ART TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
