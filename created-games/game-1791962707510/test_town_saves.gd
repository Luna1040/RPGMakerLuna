extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var store = load("res://character_saves.gd").new()
	store.directory = "res://art-jobs/save-test-%d" % Time.get_ticks_usec()
	assert(store.utc_minus_8(0) == "1969-12-31T16:00:00-08:00")
	assert(store.utc_minus_8(28800) == "1970-01-01T00:00:00-08:00")
	var game = load("res://town_game.gd").new()
	game.saves = store
	root.add_child(game)
	assert(game.menu.visible and game.slot_buttons.size() == 6)
	game.name_input.text = "江湖侠客甲"
	game.select_slot(1)
	assert(game.active_slot == 1 and game.state == "play" and game.player == Vector2(640,450) and game.facing == Vector2.UP)
	assert(game.stage == 0 and game.NPCS.size() == 6)
	game.player = Vector2(640,420)
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_E
	game._unhandled_input(event)
	assert(game.quest_accepted and game.stage == 0)
	game.player = Vector2(1160,450)
	game._unhandled_input(event)
	assert(game.stage == 1 and game.enemies.size() == 4)
	game.enemies[0].hp = 31
	game.level = 2
	game.coins = 53
	game.potions = 2
	game.skill_cd = 2.5
	assert(game.save_character())
	var created = game.character.created_at
	var loaded = store.read_slot(1)
	assert(loaded.name == "江湖侠客甲" and loaded.profession == "刀客" and loaded.level == 2)
	assert(loaded.progress.enemies[0].hp == 31 and loaded.progress.skill_cd == 2.5)
	var raw: String = FileAccess.get_file_as_string(store.path_for(1))
	assert(raw.contains("江湖侠客甲") and not raw.contains("�"))
	game.reset_game()
	game.restore(loaded.progress)
	assert(game.stage == 1 and game.enemies.size() == 4 and game.enemies[0].hp == 31 and game.coins == 53 and game.level == 2)
	assert(game.minimap_point(Vector2(55,220)) == Vector2(1057,63))
	assert(game.minimap_point(Vector2(1225,665)) == Vector2(1235,178))
	for slot in range(2,7):
		var data = store.create(slot,"侠客%d" % slot,"剑客",game.snapshot())
		assert(not data.is_empty())
	assert(store.create(7,"第七人","刀客",game.snapshot()).is_empty())
	assert(store.create(1,"覆盖者","刀客",game.snapshot()).is_empty())
	assert(store.read_slot(1).name == "江湖侠客甲")
	assert(game.save_character(true))
	loaded = store.read_slot(1)
	assert(loaded.created_at == created and loaded.last_offline_at.ends_with("-08:00"))
	game.open_menu()
	assert(game.menu.visible)
	game.select_slot(1)
	assert(not game.menu.visible and game.level == 2 and game.stage == 1)
	var before = game.player
	game.open_menu()
	game._process(1)
	assert(game.player == before)
	# Recover an intact backup rather than replacing damaged data with a new role.
	var broken := FileAccess.open(store.path_for(1),FileAccess.WRITE)
	broken.store_string("broken")
	broken.close()
	assert(store.read_slot(1).name == "江湖侠客甲" and not store.error.is_empty())
	assert(store.write_slot(1,loaded))
	assert(store.read_slot(1).name == "江湖侠客甲")
	assert(DirAccess.remove_absolute(store.path_for(1)) == OK)
	assert(store.read_slot(1).name == "江湖侠客甲")
	assert(store.create(1,"不能覆盖备份","刀客",game.snapshot()).is_empty())
	assert(store.write_slot(1,loaded))
	# Test all town interactions and safety without disturbing real saves.
	game.reset_game()
	game.coins = 30
	for npc in game.NPCS:
		game.player = npc.pos+Vector2(0,25)
		game.interact()
	assert(game.quest_accepted and game.potions == 4 and game.coins == 15)
	game.attack_cd = 0
	game.strike(false)
	assert(game.attack_cd == 0)
	print("PASS: six slots, UTF-8 Chinese, UTC-8 rollover, creation metadata, logout metadata, keyboard NPC quest, all NPCs, minimap, town safety, disk roundtrip, combat restoration, cooldown restoration, backup recovery, no overwrite")
	print("TEST_ARTIFACTS: ",store.directory)
	game.active_slot = 0
	game.queue_free()
	quit(0)
