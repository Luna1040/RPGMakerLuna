extends RefCounted
## One drop solver owns preview + release. Exact critically damped xyz tracking.
var game: Node3D
var id := ""
var start := Transform3D.IDENTITY
var start_parent: Node3D
var start_local := Transform3D.IDENTITY
var target := Vector3.ZERO
var velocity := Vector3.ZERO
var grab_offset := Vector3.ZERO
var pointer := Vector2.ZERO
var settling := false
var solution: Dictionary = {}
var released_solution: Dictionary = {}
var ghost: MeshInstance3D
var ghost_material: StandardMaterial3D
const EXTENTS := {"folder":Vector2(.327,.336),"handheld":Vector2(.312,.146),"tools":Vector2(.035,.168)}
const RATE := 28.0

func _init(owner: Node3D) -> void:game=owner
func project(mouse: Vector2, height: float) -> Variant:
	var ray:Vector3=game.camera.project_ray_normal(mouse)
	if absf(ray.y)<.001:return null
	var origin:Vector3=game.camera.project_ray_origin(mouse)
	var distance:float=(height-origin.y)/ray.y
	return origin+ray*distance if distance>0 else null

func surface_height(p: Vector3) -> float:
	# Continuous front-edge ramp for ray projection; no instant plane swap.
	if not game.drawer_open or p.x<.54 or p.x>.96:return .763
	var blend:=smoothstep(.610,.660,p.z)
	return lerpf(.763,game.drawer.global_position.y-.047,blend)

func surface_point(mouse: Vector2) -> Variant:
	var origin:Vector3=game.camera.project_ray_origin(mouse)
	var ray:Vector3=game.camera.project_ray_normal(mouse)
	if ray.y>=-.001:return null
	var lo:=maxf(0,(origin.y-.92)/-ray.y)
	var hi:float=(origin.y-.50)/-ray.y
	for i in range(24):
		var mid:float=(lo+hi)*.5
		var p:Vector3=origin+ray*mid
		if p.y>surface_height(p):lo=mid
		else:hi=mid
	return origin+ray*((lo+hi)*.5)

func begin(item: String, mouse: Vector2) -> bool:
	if item not in EXTENTS or game.moving or game.drawer_moving or not game.inspecting.is_empty() or game.phase not in ["free","warning"]:return false
	if game.props[item].get_parent()==game.drawer and not game.drawer_open:return false
	id=item;settling=false;pointer=mouse
	game.stop_pocket()
	game.controls.freeze_camera()
	var n:Node3D=game.props[id]
	start=n.global_transform;start_parent=n.get_parent();start_local=n.transform
	# Anchor the cursor at the actual picked top surface, not the lower drop plane.
	var point=project(mouse,n.global_position.y+.015)
	grab_offset=n.global_position-point if point!=null else Vector3.ZERO
	grab_offset.y=0
	if n.get_parent()!=game:n.reparent(game,true)
	if id=="tools":game.equipped=false
	velocity=Vector3.ZERO
	move(mouse)
	make_ghost()
	update_ghost()
	return true

func solve(item: String, mouse: Vector2) -> Dictionary:
	var point=surface_point(mouse)
	if point==null:return {"legal":false,"transform":start,"parent":start_parent,"reason":"移回可见桌面或抽屉空位"}
	var pos:Vector3=point+grab_offset
	var basis:Basis=game.board.global_basis if item=="folder" else Basis.IDENTITY
	var parent:Node3D=game
	var reason:="这里没有足够空位"
	var legal:=false
	if game.drawer_open and pos.z>.68 and pos.x>.52 and pos.x<.98 and item in ["handheld","tools"]:
		parent=game.drawer
		var local:Vector3=game.drawer.to_local(pos)
		local.y=-.041 if item=="tools" else -.047
		var slot:=Vector3(0,local.y,-.13 if item=="tools" else .060)
		# Preview includes the same nearby slot attraction used at release.
		if Vector2(local.x-slot.x,local.z-slot.z).length()<.070:local=slot
		pos=game.drawer.to_global(local)
		var candidate:=Transform3D(basis,pos)
		legal=fits(item,candidate) and not overlaps_stored(item,candidate)
		reason="对准抽屉内空位；别让手柄露出" if not legal else "松开放稳，再左键关抽屉"
	else:
		pos.y=.7655 if item=="folder" else (.763 if item=="handheld" else .7645)
		var half:Vector2=EXTENTS[item]*.5
		legal=pos.x-half.x>-.99 and pos.x+half.x<.99 and pos.z-half.y>-.16 and pos.z+half.y<.59
		if item=="folder":
			var relative:=Vector2(pos.x-game.board.global_position.x,pos.z-game.board.global_position.z)
			if relative.length()<.045:pos=game.board.global_position+Vector3(0,.025,0)
			elif relative.length()<.39:pos.y=game.board.global_position.y+.025
			legal=legal and pos.x<.37
		# Reject contact with other tabletop props; folder may cover the bead board.
		for other in ["handheld","tools","board","tray"]:
			if other==item or (item=="folder" and other=="board"):continue
			var n:Node3D=game.props[other]
			if n.get_parent()!=game or game.inspecting==other or (other=="tools" and game.equipped):continue
			var size:Vector2=EXTENTS.get(other,Vector2(.26,.26) if other=="board" else Vector2(.22,.12))
			if absf(pos.x-n.global_position.x)<(half.x+size.x*.5)-.005 and absf(pos.z-n.global_position.z)<(half.y+size.y*.5)-.005:legal=false
		reason="暖绿轮廓处松开放下" if legal else "红色不可放；松手会回抓取处"
	return {"legal":legal,"transform":Transform3D(basis,pos),"parent":parent,"reason":reason}

func move(mouse: Vector2) -> void:
	if id.is_empty() or settling:return
	pointer=mouse;solution=solve(id,mouse)
	var end:Transform3D=solution.transform
	target=end.origin+Vector3(0,.065,0)
	if solution.parent==game.drawer:
		target.y=lerpf(.81,end.origin.y+.065,cavity_weight(id,game.props[id].global_transform))
	update_ghost()

func fully_inside(item: String, transform: Transform3D) -> bool:
	for p in corners(item,transform):
		var q:Vector3=game.drawer.to_local(p)
		if absf(q.x)>.173 or absf(q.z)>.216:return false
	return true

func cavity_clearance(item: String, transform: Transform3D) -> float:
	var clearance:=1.0
	for p in corners(item,transform):
		var q:Vector3=game.drawer.to_local(p)
		clearance=minf(clearance,minf(.173-absf(q.x),.216-absf(q.z)))
	return clearance

func cavity_weight(item: String, transform: Transform3D) -> float:
	return smoothstep(0,.016,cavity_clearance(item,transform))

func minimum_height(item: String, position: Vector3, basis: Basis) -> float:
	if game.drawer_open and fully_inside(item,Transform3D(basis,position)):
		return game.drawer.global_position.y+(-.041 if item=="tools" else -.047)
	if game.drawer_open and position.z+EXTENTS[item].y*.5>.60 and position.x>.48:return .79
	if item=="folder" and Vector2(position.x-game.board.global_position.x,position.z-game.board.global_position.z).length()<.39:return .7905
	return .763 if item=="handheld" else .7645

func tick(delta: float) -> void:
	if id.is_empty():return
	var n:Node3D=game.props[id]
	var remaining:=delta
	while remaining>.000001:
		var dt:=minf(remaining,1.0/120);remaining-=dt
		if not settling:
			var end:Transform3D=solution.transform
			target=end.origin+Vector3(0,.065,0)
			if solution.parent==game.drawer:target.y=lerpf(.81,end.origin.y+.065,cavity_weight(id,n.global_transform))
		var goal:Vector3=target
		# A quick release/cancel still follows the same spatial clearance corridor.
		# Aim above the lip while crossing, then descend only inside the destination.
		# Without this, a low cavity -> table return could wait forever below the rim.
		if settling and game.drawer_open and id in ["handheld","tools"]:
			if fully_inside(id,solution.transform):
				# Narrow slots (tweezers) have less edge clearance than the console.
				# Normalize by the actual destination so every valid slot reaches rest.
				var width:=clampf(cavity_clearance(id,solution.transform)*.5,.0001,.016)
				goal.y=lerpf(.81,target.y,smoothstep(0,width,cavity_clearance(id,n.global_transform)))
			elif minimum_height(id,n.global_position,n.global_basis)>=.79 or fully_inside(id,n.global_transform):
				goal.y=maxf(goal.y,.81)
		var error:Vector3=n.global_position-goal
		var j:Vector3=velocity+RATE*error
		var decay:=exp(-RATE*dt)
		var next:Vector3=goal+(error+j*dt)*decay
		velocity=(velocity-RATE*j*dt)*decay
		var step:Vector3=next-n.global_position
		if step.length()>1.65*dt:
			next=n.global_position+step.normalized()*1.65*dt
			velocity=velocity.limit_length(1.65)
		var basis_goal:Basis=solution.transform.basis
		var basis:=Basis(n.global_basis.get_rotation_quaternion().slerp(basis_goal.get_rotation_quaternion(),1-exp(-dt*24)))
		# Spatial clearance constraint, not a time gate: an item below the lip rises
		# while its footprint is still confined to the cavity; all xyz remain continuous.
		if n.global_position.y<.789 and next.z+EXTENTS[id].y*.5>.60 and next.x>.48 and game.drawer_open and not fully_inside(id,Transform3D(basis,next)):
			next.x=n.global_position.x;next.z=n.global_position.z
			velocity.x=0;velocity.z=0
		var floor_y:=minimum_height(id,next,basis)
		if next.y<floor_y:
			if n.global_position.y<floor_y-.002:
				next.x=n.global_position.x;next.z=n.global_position.z
				velocity.x=0;velocity.z=0
			else:next.y=floor_y;velocity.y=maxf(0,velocity.y)
		n.global_transform=Transform3D(basis,next)
	if settling and n.global_position.distance_to(target)<.00035 and velocity.length()<.015:
		n.global_transform=solution.transform
		var parent:Node3D=solution.parent
		if is_instance_valid(parent) and n.get_parent()!=parent:n.reparent(parent,true)
		id="";settling=false;velocity=Vector3.ZERO;game.moving=false
		game.controls.rebase()
		game.play_sound("paper" if n==game.props.folder else "place",-15)
		game.covered=cover_ratio()>=.97
		game.update_hud()

func end(mouse: Vector2) -> void:
	if id.is_empty() or settling:return
	move(mouse)
	released_solution=solution.duplicate()
	if not solution.legal:
		game.toast(solution.reason,3)
		solution={"legal":true,"transform":start,"parent":start_parent,"reason":"回到抓取处"}
	else:game.toast(solution.reason,2)
	settling=true;game.moving=true;target=solution.transform.origin
	if ghost:ghost.hide()
	# No additional lift, tween reset or second arc on release: keep xyz velocity.

func cancel() -> void:
	if id.is_empty():return
	solution={"legal":true,"transform":start,"parent":start_parent,"reason":"取消拖动"}
	settling=true;game.moving=true;target=start.origin
	if ghost:ghost.hide()

func make_ghost() -> void:
	if ghost:return
	ghost=MeshInstance3D.new()
	ghost.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost_material=StandardMaterial3D.new()
	ghost_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	ghost.material_override=ghost_material
	game.add_child(ghost)

func update_ghost() -> void:
	if not ghost or solution.is_empty():return
	var size:Vector2=EXTENTS[id]
	var mesh:=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts:=[Vector3(-size.x/2,0,-size.y/2),Vector3(size.x/2,0,-size.y/2),Vector3(size.x/2,0,size.y/2),Vector3(-size.x/2,0,size.y/2)]
	for i in range(4):
		var a:Vector3=pts[i];var b:Vector3=pts[(i+1)%4]
		var inset:Vector3=(b-a).cross(Vector3.UP).normalized()*.003
		for v in [a,b,b+inset,a,b+inset,a+inset]:mesh.surface_add_vertex(v)
	mesh.surface_end()
	ghost.mesh=mesh
	ghost.global_transform=solution.transform
	ghost.global_position.y+=.0025
	ghost_material.albedo_color=Color(.55,.83,.59,.55) if solution.legal else Color(.93,.30,.24,.55)
	ghost.show()
func corners(item: String, transform: Transform3D) -> Array[Vector3]:
	var size:Vector2=EXTENTS[item]
	var result:Array[Vector3]=[]
	for c in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:result.append(transform*Vector3(c.x*size.x/2,0,c.y*size.y/2))
	return result

func fits(item: String, transform: Transform3D) -> bool:
	if not game.drawer_open:return false
	if transform.basis.y.dot(Vector3.UP)<.995:return false
	for point in corners(item,transform):
		var p:Vector3=game.drawer.to_local(point)
		if absf(p.x)>.173 or p.z<-.216 or p.z>.216:return false
	var height:float=.037 if item=="handheld" else .005
	var y:float=game.drawer.to_local(transform.origin).y
	return y>=-.049 and y+height<.028

func overlaps_stored(item: String, transform: Transform3D) -> bool:
	for other in ["tools","handheld"]:
		if other==item or game.props[other].get_parent()!=game.drawer:continue
		var a:Vector3=game.drawer.to_local(transform.origin)
		var b:Vector3=game.props[other].position
		var sa:Vector2=EXTENTS[item];var sb:Vector2=EXTENTS[other]
		if absf(a.x-b.x)<(sa.x+sb.x)/2+.004 and absf(a.z-b.z)<(sa.y+sb.y)/2+.004:return true
	return false

func stowed(item: String) -> bool:
	var n:Node3D=game.props[item]
	if n.get_parent()!=game.drawer:return false
	# Same volume verification after closure, independent of a boolean flag.
	for p in corners(item,n.global_transform):
		var q:Vector3=game.drawer.to_local(p)
		if absf(q.x)>.173 or absf(q.z)>.216:return false
	return n.position.y>=-.049 and n.position.y+(.037 if item=="handheld" else .005)<.028

func cover_ratio() -> float:
	if id=="folder" or game.inspecting=="folder":return 0
	var n:Node3D=game.props.folder
	var height:float=n.global_position.y-game.board.global_position.y
	if height<.018 or height>.035 or n.global_basis.y.dot(Vector3.UP)<.995:return 0
	var poly:Array[Vector2]=[]
	for p in corners("folder",n.global_transform):
		var q:Vector3=game.board.to_local(p);poly.append(Vector2(q.x,q.z))
	for side in range(4):
		var clipped:Array[Vector2]=[]
		if poly.is_empty():return 0
		for i in range(poly.size()):
			var a:Vector2=poly[i];var b:Vector2=poly[(i+1)%poly.size()]
			var da:float=distance_inside(a,side);var db:float=distance_inside(b,side)
			if da>=0:clipped.append(a)
			if (da>=0)!=(db>=0):clipped.append(a.lerp(b,da/(da-db)))
		poly=clipped
	var area:=0.0
	for i in range(poly.size()):area+=poly[i].cross(poly[(i+1)%poly.size()])
	return clampf(absf(area)*.5/(.256*.256),0,1)

func distance_inside(p: Vector2, side: int) -> float:
	match side:
		0:return p.x+.128
		1:return .128-p.x
		2:return p.y+.128
		_:return .128-p.y

func can_close() -> bool:
	if not id.is_empty() or game.moving or not game.inspecting.is_empty():return false
	for item in ["handheld","tools"]:
		var n:Node3D=game.props[item]
		if n.get_parent()==game.drawer:
			if not stowed(item):return false
		elif n.global_position.x>.51 and n.global_position.x<.99 and n.global_position.z>-.03 and n.global_position.y<.75:return false
	return true
