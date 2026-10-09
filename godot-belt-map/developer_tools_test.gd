extends SceneTree
var failures: Array[String]=[]
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func press(tools, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.pressed=true
	tools._input(event)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage=load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	stage.testing_motion=true
	var tools=stage.developer_tools
	press(tools,KEY_F2)
	check(stage.debug_collision,"F2 did not enable volumes")
	press(tools,KEY_F3)
	check(tools.panel.visible,"F3 panel missing")
	press(tools,KEY_F8)
	check(is_equal_approx(Engine.time_scale,.25),"Slow motion missing")
	press(tools,KEY_F8)
	press(tools,KEY_F6)
	check(paused,"Pause failed")
	var before: float=stage.knight.elapsed
	tools.single_step()
	check(stage.knight.elapsed>before,"Single step did not advance animation")
	check(paused,"Single step resumed world")
	tools.record_hit({"action":"attack1","range":240,"damage":22,"facing":1},1)
	check(tools.last_hit.contains("命中 1"),"Hit diagnostics missing")
	press(tools,KEY_F6)
	check(not paused,"Resume failed")
	press(tools,KEY_F2)
	check(not stage.debug_collision,"F2 did not disable volumes")
	for error in failures: push_error(error)
	print("DEVELOPER_TOOLS_TEST ","PASS" if failures.is_empty() else "FAIL"," · toggles, pause/resume, fixed step, speed, hit record")
	quit(0 if failures.is_empty() else 1)
