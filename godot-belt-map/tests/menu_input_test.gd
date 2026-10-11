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
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	if not failed: print("MENU INPUT PASS")
	quit(1 if failed else 0)
