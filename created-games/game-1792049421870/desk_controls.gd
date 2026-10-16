extends RefCounted
var game: Node3D
var anchor:=Transform3D.IDENTITY
var pointer:=Vector2(640,400)
var pointer_origin:=Vector2(640,400)
var look:=Vector2.ZERO
var target_look:=Vector2.ZERO
var dolly:=0.0
var target_dolly:=0.0
var right_mode:=""
var right_item:=""
var press_position:=Vector2.ZERO
var press_time:=0.0
var press_travel:=0.0
var rotating:=false
var focused:=true
const TAP_TIME:=.18
const TAP_PIXELS:=6.0
func _init(owner: Node3D) -> void:
	game=owner;anchor=game.camera.transform
func locked() -> bool:
	return not game.inspecting.is_empty() or game.pocket_playing or game.moving or game.drawer_moving or not game.drag.id.is_empty() or not right_mode.is_empty() or not focused
func freeze_camera() -> void:
	# Discard latent zoom/look targets, preserving every actual xyz/basis component.
	anchor=game.camera.transform;look=Vector2.ZERO;target_look=Vector2.ZERO
	dolly=0;target_dolly=0;pointer_origin=pointer
func rebase() -> void:freeze_camera()
func tick(delta: float) -> void:
	if not right_mode.is_empty():press_time+=delta
	if locked():return
	var size:Vector2=game.get_viewport().get_visible_rect().size
	var relative:Vector2=(pointer-pointer_origin)/(size*.5)
	for axis in range(2):
		var value:=relative[axis]
		var dead:=.11
		target_look[axis]=signf(value)*clampf((absf(value)-dead)/(1-dead),0,1)
	look=look.lerp(target_look,1-exp(-delta*32))
	dolly=lerpf(dolly,target_dolly,1-exp(-delta*26))
	var angles:=anchor.basis.get_euler()
	var basis:=Basis.from_euler(Vector3(angles.x-look.y*deg_to_rad(10),angles.y-look.x*deg_to_rad(15),0))
	var position:Vector3=anchor.origin-anchor.basis.z*dolly
	position.y=maxf(position.y,1.09)
	position.z=clampf(position.z,.90,1.95)
	game.camera.transform=Transform3D(basis,position)
	game.yaw=game.camera.rotation.y;game.pitch=game.camera.rotation.x
	game.target_yaw=game.yaw;game.target_pitch=game.pitch
func right_press(pos: Vector2) -> void:
	if game.moving or game.drawer_moving:return
	press_position=pos;pointer=pos;press_time=0;press_travel=0;rotating=false
	right_mode="pocket" if game.pocket_playing else ("inspect" if not game.inspecting.is_empty() else "desk")
	right_item=game.pick_id(pos) if right_mode=="desk" else ""
	freeze_camera()
func right_release(pos: Vector2) -> void:
	if right_mode.is_empty():return
	var mode:=right_mode
	var tap:=press_time<TAP_TIME and press_travel<TAP_PIXELS and not rotating
	right_mode="";right_item=""
	if not game.drag.id.is_empty():
		if not game.drag.settling:game.drag.end(pos)
	elif tap and mode in ["inspect","pocket"]:
		game.stop_pocket();game.return_item()
	rotating=false
func motion(event: InputEventMouseMotion) -> void:
	pointer=event.position
	if right_mode.is_empty():return
	press_travel=maxf(press_travel,event.position.distance_to(press_position))
	# relative fallback also handles events from host/test injection.
	press_travel=maxf(press_travel,event.relative.length())
	if right_mode=="pocket":return
	if right_mode=="inspect":
		if press_travel>=TAP_PIXELS or press_time>=TAP_TIME:
			rotating=true
			game.target_inspect_rotation.x=clampf(game.target_inspect_rotation.x+event.relative.y*.009,-1.6,1.6)
			game.target_inspect_rotation.y+=event.relative.x*.011
	elif right_mode=="desk":
		if game.drag.id.is_empty() and press_travel>=TAP_PIXELS:
			game.drag.begin(right_item,press_position)
		if not game.drag.id.is_empty():game.drag.move(event.position)
func wheel(direction: float) -> void:
	if game.moving or game.drawer_moving or game.pocket_playing or not game.drag.id.is_empty() or not right_mode.is_empty():return
	if not game.inspecting.is_empty():game.target_inspect_distance=clampf(game.target_inspect_distance-direction*.035,.39,.70)
	else:target_dolly=clampf(target_dolly+direction*.055,-.24,.26)
func release_inputs(pause: bool) -> void:
	right_mode="";right_item="";rotating=false;game.look_drag=false
	game.stop_pocket()
	if not game.drag.id.is_empty():game.drag.cancel()
	freeze_camera()
	if pause and game.started and game.phase in ["free","warning","checking","returning"]:
		game.set_meta("resume_phase",game.phase);game.phase="paused";game.title_layer.show()
