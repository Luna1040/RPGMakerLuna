extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func finish_walk(game) -> void:
	game._process(8.0)
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	game.store.directory="res://tests/test-saves"
	root.add_child(game)
	await process_frame
	game.create_character(0)
	game.name_input.text="青牛测试"
	game.finish_creation()
	for i in range(8):
		var image=Image.load_from_file(ProjectSettings.globalize_path("res://assets/characters/%d.png" % i))
		check(image!=null and image.get_format()==Image.FORMAT_RGBA8,"character PNG has alpha")
		if image==null: continue
		check(image.get_pixel(0,0).a==0,"transparent background corner")
		check(image.get_pixel(image.get_width()-1,image.get_height()-1).a==0,"transparent opposite corner")
	check(game.character.level==1,"new character level one")
	var found_mark:=false
	for node in game.map_layer.get_children():
		var mark=node.get_node_or_null("QuestMarker")
		if mark!=null:
			found_mark=true
			check(mark.position.y+mark.size.y<=-game.MAP_ACTOR_SIZE.y,"quest marker above head")
	check(found_mark,"current quest NPC has head marker")
	var count:=0
	for node in game.map_layer.get_children():
		var portrait=node.get_node_or_null("Portrait")
		if portrait is Sprite2D:
			count+=1
			if node==game.avatar:
				var profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/classes/profiles.json"))
				var profile: Dictionary=profiles[game.ClassProfile.role(game.character)]
				check(is_equal_approx(float(profile.height)*portrait.scale.y,72.0) and is_equal_approx(portrait.scale.x,portrait.scale.y),"player natural aspect and seventy two pixel body height")
			else:
				check((portrait.texture.get_size()*portrait.scale).is_equal_approx(game.MAP_ACTOR_SIZE),"NPC map model bounds")
	check(count==6,"five NPC models plus player")
	var clickable_npcs:=0
	for node in game.map_layer.get_children():
		var hit=node.get_node_or_null("ClickArea")
		if hit is Button and node.get_node_or_null("Portrait")!=null:
			clickable_npcs+=1
			check(hit.text.is_empty(),"no visible dialogue button text")
			check(Rect2(hit.position,hit.size).has_point(Vector2(0,-35)),"model clickable")
			check(Rect2(hit.position,hit.size).has_point(Vector2(0,14)),"name clickable")
	check(clickable_npcs==5,"all five NPCs clickable")
	game.talk(0)
	check(not is_instance_valid(game.modal),"no distant dialogue")
	finish_walk(game)
	check(is_instance_valid(game.modal),"arrival opens dialogue")
	game.close_dialog()
	game.travel(Vector2(95,535),"portal:town_field")
	finish_walk(game)
	check(game.character.zone=="town" and is_instance_valid(game.modal),"tutorial portal locked")
	game.close_dialog()
	for i in range(5):
		check(game.npc_has_task(i),"current NPC shows quest marker")
		game.player_pos=game.TOWN_POS[i]+game.NPC_APPROACH
		game.talk(i)
		check(is_instance_valid(game.modal),"nearby NPC dialogue")
		game.complete_town(i)
	check(game.character.level==5 and game.character.quest==5,"town ends at level five")
	var stones=int(game.character.stones)
	game.complete_town(4)
	check(game.character.stones==stones,"tutorial reward once")
	game.travel(Vector2(95,535),"portal:town_field")
	check(game.character.zone=="town","portal waits for arrival")
	finish_walk(game)
	check(game.character.zone=="field","portal arrives at field")
	for i in range(3):
		var monster=game.map_layer.get_node("Monster%d" % i)
		var hit=monster.get_node("ClickArea")
		check(hit.text.is_empty() and not hit.disabled,"monster click area has no attack button")
		check(Rect2(hit.position,hit.size).has_point(Vector2(0,-25)),"monster model clickable")
		check(Rect2(hit.position,hit.size).has_point(Vector2(0,15)),"monster name clickable")
	game.player_pos=game.FIELD_POS[0]+game.NPC_APPROACH
	game.talk(0)
	game.advance_field(1)
	game.player_pos=Vector2(330,555)
	game.map_layer.get_node("Monster0/ClickArea").pressed.emit()
	check(game.mode=="map","monster waits for approach")
	finish_walk(game)
	check(game.mode=="battle","arrival starts combat directly")
	for i in range(12): game.battle_turn()
	check(game.mode=="result" and game.character.level==5 and game.character.xp==60,"first combat gives level-based XP")
	check(game.character.cleared.size()==1,"first group cleared")
	stones=int(game.character.stones)
	game.settle_battle()
	check(game.character.stones==stones,"battle reward once")
	game.return_from_battle()
	check(game.player_pos==game.GROUP_POS[0]+Vector2(-55,35),"map return position")
	check(game.map_layer.get_node("Monster0/Portrait").material is ShaderMaterial,"cleared monster grayscale material")
	var before_stones=int(game.character.stones)
	game.map_layer.get_node("Monster0/ClickArea").pressed.emit()
	finish_walk(game)
	check(game.mode=="map" and is_instance_valid(game.modal),"cleared monster click gives notice")
	check(game.modal.get_child(0).get_child(0).text=="已经击杀","notice says already killed")
	check(game.character.stones==before_stones,"cleared monster cannot repeat reward")
	game.close_dialog()
	game.player_pos=game.FIELD_POS[1]+game.NPC_APPROACH
	check(game.npc_has_task(1),"followup NPC marker")
	game.talk(1)
	game.advance_field(2)
	for group in [1,2]:
		game.start_battle(group)
		for i in range(14): game.battle_turn()
		check(game.enemy_hp==0,"automatic combat won")
		game.return_from_battle()
	check(game.character.cleared.size()==3 and game.character.field_quest==3,"field combat complete")
	check(game.character.level==7 and game.character.xp==52,"monster XP is a small level-based reward")
	game.travel(Vector2(1130,595),"portal:field_sect")
	finish_walk(game)
	check(game.character.zone=="field","sect portal requires ten")
	game.close_dialog()
	game.player_pos=game.FIELD_POS[0]+game.NPC_APPROACH
	game.talk(0)
	game.advance_field(4)
	check(game.character.level==10,"field quest XP reaches ten")
	stones=int(game.character.stones)
	game.advance_field(4)
	check(game.character.stones==stones,"final reward once")
	game.travel(Vector2(1130,595),"portal:field_sect")
	finish_walk(game)
	check(game.character.zone=="sect","new map reachable")
	game.player_pos=game.SECT_POS[0]+game.NPC_APPROACH
	game.talk(0)
	game.advance_sect(1)
	check(game.character.realm=="练气期" and game.character.sect_quest==1,"accept cultivation path")
	game.player_pos=game.SECT_POS[1]+game.NPC_APPROACH
	game.talk(1)
	game.advance_sect(2)
	check(game.character.sect_quest==2,"new map linked quest complete")
	game.persist()
	game.logout()
	game.enter_character(0)
	check(game.character.zone=="sect" and game.character.level==10 and game.character.realm=="练气期","save roundtrip")
	game.travel(Vector2(160,590),"portal:sect_field")
	finish_walk(game)
	check(game.character.zone=="field","sect return portal")
	game.travel(Vector2(160,590),"portal:field_town")
	finish_walk(game)
	check(game.character.zone=="town","field return portal")
	game.character={"quest":5,"zone":"town","field_quest":0,"cleared":[],"position":[620,610],"level":10,"xp":999,"hp":200}
	game.migrate()
	check(game.character.level==5 and game.character.xp==0,"legacy tutorial migration")
	game.character={"quest":5,"zone":"field","field_quest":4,"cleared":[0,1,2],"position":[620,610],"level":10,"xp":440,"hp":200}
	game.migrate()
	check(game.character.level==10 and game.character.xp==0,"legacy full progress migration")
	game.store.delete_slot(0)
	game.character={}
	print("SMOKE TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
