extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func key(stage, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.pressed=true
	stage._unhandled_key_input(event)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	stage.testing_motion=true
	key(stage,KEY_M)
	check(stage.interface.atlas.visible and stage.interface.is_modal(),"M did not open modal map")
	var foot: Vector2=stage.foot
	stage.test_input=Vector2.RIGHT
	stage._physics_process(.2)
	key(stage,KEY_J)
	check(stage.foot==foot and stage.knight.is_locomotion(),"Movement/combat leaked through map")
	stage.interface.atlas.set_world(true)
	check(stage.interface.atlas.canvas.terrain != null,"World terrain unavailable")
	var linked := false
	for place in stage.interface.atlas.canvas.world.places:
		if place.id == stage.contract.worldLocationId: linked=true
	check(linked,"Current region not linked to world place")
	key(stage,KEY_M)
	check(not stage.interface.is_modal(),"M did not close map")
	key(stage,KEY_I)
	key(stage,KEY_M)
	check(stage.interface.atlas.visible and not stage.interface.inventory.visible,"Backpack/map overlap")
	key(stage,KEY_ESCAPE)
	check(not stage.interface.is_modal(),"Esc did not close map")
	for error in failures: push_error(error)
	print("ATLAS_TEST ","PASS" if failures.is_empty() else "FAIL"," · M/Esc, modal input, inventory transition, world link")
	quit(0 if failures.is_empty() else 1)
