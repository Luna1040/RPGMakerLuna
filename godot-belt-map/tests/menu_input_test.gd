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
	stage.set_physics_process(false)
	stage.runtime.controls.keys=stage.runtime.controls.DEFAULTS.duplicate()
	for binding in [[KEY_X,"attack1"],[KEY_Z,"skill_rising"],[KEY_Q,"skill_crescent"],[KEY_W,"skill_trinity"],[KEY_R,"cast"]]:
		stage.knight.reset_character()
		stage.grounded=true
		stage.height_z=0
		var action:=InputEventKey.new()
		action.keycode=binding[0]
		action.physical_keycode=binding[0]
		action.pressed=true
		stage._unhandled_key_input(action)
		check(stage.knight.state==binding[1],"New physical key must dispatch correct combat action: "+str(binding[0]))
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
	check(settings.keys==settings.DEFAULTS,"Old default settings migrate to arrow/X/C/Z layout")
	DirAccess.remove_absolute(test_path)
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	if not failed: print("MENU INPUT PASS")
	quit(1 if failed else 0)
