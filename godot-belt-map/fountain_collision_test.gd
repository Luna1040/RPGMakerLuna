extends SceneTree
const Physics = preload("belt_physics.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	check(Physics.blocked(stage.volumes,Vector2(14.5,5.4),0),"Front-left wall permits penetration")
	check(Physics.blocked(stage.volumes,Vector2(17.8,5.4),0),"Front-right wall permits penetration")
	check(not Physics.blocked(stage.volumes,Vector2(16.15,3.9),0),"Old oversized footprint still blocks rear walkway")
	for start in [Vector2(13,5.4),Vector2(19,5.4),Vector2(16.15,7)]:
		var stopped := Physics.step_position(stage.volumes,stage.bounds,start,Vector2(16.15,5)-start,0,true)
		check(not Physics.blocked(stage.volumes,stopped,0),"Swept dash stops inside pool")
		check(stopped.distance_to(Vector2(16.15,5))>0.8,"Swept movement crossed basin")
	check(not Physics.support(stage.volumes,Vector2(15,5)).valid,"Water allows landing")
	check(Physics.blocked(stage.volumes,Vector2(16.15,5),1.3),"Airborne character passes column")
	var fountain: Node2D = stage.sorting.get_node("pool")
	check(is_equal_approx(fountain.position.y,stage.project(Vector2(16.15,5)).y),"Fountain sort anchor not at base center")
	var sprite: Sprite2D = fountain.get_child(0)
	var bottom := fountain.position.y+sprite.position.y+sprite.texture.get_height()*sprite.scale.y/2
	check(is_equal_approx(bottom,stage.project(Vector2(16.15,5.7)).y),"Art moved when correcting sort origin")
	for error in failures: push_error(error)
	print("FOUNTAIN_COLLISION_TEST ","PASS" if failures.is_empty() else "FAIL"," · front corners, rear walkway, swept approaches, water/column, fixed artwork and center sorting")
	quit(0 if failures.is_empty() else 1)
