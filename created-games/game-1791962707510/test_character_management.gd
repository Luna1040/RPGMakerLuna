extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game = load("res://main.tscn").instantiate()
	game.saves.directory="res://art-jobs/chibi-05/character-test-%d" % Time.get_ticks_usec()
	root.add_child(game)
	await physics_frame
	assert(game.profession_input.item_count==3)
	assert(game.Saves.PROFESSIONS==["刀客","剑客","枪客"])
	game.name_input.text="远行刀客"
	game.select_slot(1)
	game.hero.position=Vector3(-5,0.05,2)
	game.yaw=2.2
	game.zoom=20
	game.training_state=3
	game.training_rewarded=true
	game.enemy_health=0
	game.enemy_cooldown=10
	game.click_target="enemy"
	assert(game.save_character())
	game.open_menu()
	var previous_world: int=game.world.get_instance_id()
	var generation: int=game.map_generation
	game.name_input.text="初来枪客"
	game.profession_input.select(2)
	game.select_slot(2)
	assert(game.world.get_instance_id()!=previous_world and game.map_generation>generation,"New role rebuilds map instance")
	assert(not game.grid.is_point_solid(game.cell_for(game.hero.position)),"New role spawns outside restored client structures")
	assert(game.yaw==0 and game.zoom==13 and game.training_state==0 and game.enemy_health==100 and game.enemy_cooldown==0)
	assert(game.click_target.is_empty() and game.route.is_empty())
	assert(game.character.profession=="枪客" and game.town_actors.size()==6)
	assert(game.hero_model.root.get_meta("client_skinned",false),"Original client model is active")
	game.open_menu()
	game.select_slot(1)
	assert(game.hero.position.x==-5 and game.hero.position.z==2 and abs(game.yaw-2.2)<0.001)
	assert(game.training_rewarded and game.enemy_health==0,"Old role keeps its own map progress")
	game.open_menu()
	var signature: String=game.saves.deletion_signature(1)
	game.ask_delete(1)
	assert(game.delete_dialog.visible and game.pending_delete==1)
	game.delete_dialog.get_cancel_button().pressed.emit()
	assert(game.saves.deletion_signature(1)==signature and game.active_slot==1,"Cancel leaves slot untouched")
	game.ask_delete(1)
	game.delete_dialog.get_ok_button().pressed.emit()
	assert(game.active_slot==0 and game.character.is_empty())
	assert(game.saves.read_slot(1).is_empty())
	for suffix in ["",".bak",".tmp"]: assert(not FileAccess.file_exists(game.saves.path_for(1)+suffix))
	assert(not game.save_character(),"Deleted active slot cannot autosave itself back")
	assert(game.saves.read_slot(2).name=="初来枪客","Other role is untouched")
	game.name_input.text="新建剑客"
	game.profession_input.select(1)
	game.select_slot(1)
	assert(game.character.profession=="剑客" and not game.grid.is_point_solid(game.cell_for(game.hero.position)))
	game.open_menu()
	game.ask_delete(2)
	var data: Dictionary=game.saves.read_slot(2)
	data.name="确认期间已更改"
	assert(game.saves.write_slot(2,data))
	game.delete_dialog.get_ok_button().pressed.emit()
	assert(not game.saves.read_slot(2).is_empty(),"Changed slot requires reconfirmation")
	assert(game.menu_status.text.contains("重新确认"))
	game.ask_delete(2)
	game.delete_dialog.get_ok_button().pressed.emit()
	assert(game.saves.read_slot(2).is_empty() and game.active_slot==1)
	assert(game.saves.create(2,"禁用弓手","弓手",game.snapshot()).is_empty())
	assert(game.Saves.display_profession("医师")=="刀客")
	var legacy: Dictionary=game.saves.create(3,"旧版医生","刀客",game.snapshot())
	assert(not legacy.is_empty())
	legacy.profession="医师"
	assert(game.saves.write_slot(3,legacy))
	game.select_slot(3)
	assert(game.character.profession=="刀客" and game.character.original_profession=="医师","Legacy healer migrates to blade and keeps progress")
	game.dialogue.hide()
	for title in ["金香玉","韦大宝","平十指","刀剑笑","银娇龙"]:
		game.talk_town_npc(title)
		assert(game.dialogue.visible and game.dialogue_text.text.begins_with(title))
		game.dialogue.hide()
	print("PASS: fresh map instance per character, spawn/camera/enemy/target reset, old-role resume, three professions, legacy healer migration, six NPCs, deletion confirmation/cancel, backup removal, no resurrection, other-slot isolation, race reconfirmation, deleted-slot reuse")
	print("TEST_ARTIFACTS: ",game.saves.directory)
	game.active_slot=0
	game.queue_free()
	quit(0)
