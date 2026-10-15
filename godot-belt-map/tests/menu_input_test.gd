extends SceneTree
var failed:=false
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool, label:String) -> void:
	if not ok:
		failed=true
		push_error(label)
func send_key(code:int, pressed:bool=true) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
func run() -> void:
	var stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.runtime.persistence_enabled=false
	var panel=stage.runtime.panel
	panel.open("adventure")
	var button=panel.body.find_children("*","Button",true,false)[0]
	button.grab_focus()
	await process_frame
	send_key(KEY_ESCAPE)
	send_key(KEY_ESCAPE,false)
	await process_frame
	check(not panel.is_open(),"Escape closes a menu with a focused Button")
	check(root.gui_get_focus_owner()==null,"Closing releases hidden menu focus")
	send_key(KEY_ESCAPE)
	send_key(KEY_ESCAPE,false)
	await process_frame
	check(panel.is_open(),"Escape opens exactly once, without double toggling")
	panel.body.find_children("*","Button",true,false)[0].grab_focus()
	send_key(KEY_L)
	send_key(KEY_L,false)
	await process_frame
	check(not panel.is_open(),"Journal shortcut closes a focused menu")
	stage.runtime.open_npc(stage.townsfolk.residents[1])
	var dialogue=panel.dialogue_view
	while not dialogue.at_choices: dialogue.advance()
	var selected:int=dialogue.selected_choice
	dialogue.keyboard(KEY_DOWN)
	check(dialogue.selected_choice!=selected,"Arrow selects a different dialogue row")
	dialogue.keyboard(KEY_UP)
	check(dialogue.selected_choice==selected,"Up returns to prior enabled choice")
	var chosen:Button=dialogue.choices.get_child(dialogue.selected_choice)
	check(chosen.get_theme_stylebox("normal").border_width_left==2,"Selected row has visible highlight")
	dialogue.keyboard(KEY_SPACE)
	check(not dialogue.at_choices and not dialogue.pending_choice.is_empty(),"Space opens selected topic without mouse")
	while not dialogue.at_choices: dialogue.advance()
	dialogue.keyboard(KEY_SPACE)
	check(dialogue.pending_choice.is_empty(),"Space confirms topic through quest service")
	panel.close()
	stage.set_physics_process(false)
	stage.runtime.controls.keys=stage.runtime.controls.DEFAULTS.duplicate()
	# Use real key dispatch: calling demo_companion directly missed the confusing 7 entry.
	check(not stage.runtime.companion_recruited,"Companion starts uncalled")
	send_key(KEY_7)
	send_key(KEY_7,false)
	await process_frame
	check(stage.runtime.companion_recruited and stage.runtime.encounters.companion_root.is_visible_in_tree(),"7 summons a visible companion when none is present")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../.game-assistant/companion-review.png"))
	send_key(KEY_7)
	send_key(KEY_7,false)
	await process_frame
	check(stage.runtime.companion_mode=="guard","7 changes orders once companion exists")
	send_key(KEY_6)
	send_key(KEY_6,false)
	await process_frame
	check(not stage.runtime.companion_recruited,"6 still dismisses companion")
	stage.runtime.companion_mode="follow"
	stage.runtime.encounters.set_companion("follow")
	for binding in [[KEY_X,"attack1"],[KEY_W,"skill_rising"],[KEY_Q,"skill_crescent"],[KEY_A,"skill_trinity"],[KEY_R,"cast"]]:
		stage.knight.reset_character()
		stage.grounded=true
		stage.height_z=0
		var action:=InputEventKey.new()
		action.keycode=binding[0]
		action.physical_keycode=binding[0]
		action.pressed=true
		stage._unhandled_key_input(action)
		check(stage.knight.state==binding[1],"New physical key must dispatch correct combat action: "+str(binding[0]))
	for code in [KEY_6,KEY_7,KEY_8]:
		var shortcut:=InputEventKey.new()
		shortcut.keycode=code
		shortcut.pressed=true
		stage._unhandled_key_input(shortcut)
	check(stage.runtime.companion_recruited and stage.runtime.companion_mode=="guard","Demo number keys join ally and change orders")
	check(stage.runtime.encounters.companion_hp==140,"Demo recovery key restores ally")
	stage.knight.reset_character()
	var jump:=InputEventKey.new()
	jump.keycode=KEY_C
	jump.pressed=true
	stage._unhandled_key_input(jump)
	check(stage.vertical_speed>0,"C must jump")
	var settings=preload("res://systems/game_settings.gd").new()
	settings.keys=settings.ACTION_CODES.duplicate()
	var test_path:="user://test-legacy-keys.cfg"
	check(settings.save_settings(test_path),"Legacy settings fixture saved")
	settings.load_settings(test_path)
	check(settings.keys==settings.DEFAULTS,"Old default settings migrate to arrow/X/C/W layout")
	DirAccess.remove_absolute(test_path)
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	if not failed: print("MENU INPUT PASS")
	quit(1 if failed else 0)
