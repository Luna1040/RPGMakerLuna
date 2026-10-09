extends Node2D

var viewport: SubViewport
var camera: Camera3D
var root: Node3D
var display: Sprite2D
var parts := {}
var mats := {}
var joints := {}
var outfit := "blue"
var show_cape := true
var show_hair := true
var show_weapon := true
var golden_weapon := false
var debug_bones := false
var angle := 0.0
var facing := 1
var current_action := "idle"
var current_frame := 0
var hand := Vector2.ZERO
var sword_angle := 0.0
var sword_grip := Vector3.ZERO
var sword_tip := Vector3.ZERO
var effect: MeshInstance3D
const UPPER_LEG := 43.0
const LOWER_LEG := 46.0
const UPPER_ARM := 36.0
const LOWER_ARM := 34.0
const SWORD_WIDTH := 138.0
const SWORD_GRIP_X := .16

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(448,448)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)
	root = Node3D.new()
	viewport.add_child(root)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 448.0
	camera.near = .1
	camera.far = 3000.0
	viewport.add_child(camera)
	camera.make_current()
	make_part("cape_blue",116,Vector2(.94,.07),-15)
	make_part("cape_red",116,Vector2(.94,.07),-15)
	make_part("hair",108,Vector2(.86,.10),-10)
	for side in ["far","near"]:
		var depth := -6.0 if side == "far" else 2.0
		make_part(side+"_thigh",UPPER_LEG/.78,Vector2(.50,.10),depth)
		make_part(side+"_shin",LOWER_LEG/.91,Vector2(.38,.03),depth+.2)
		make_part(side+"_boot",17.5,Vector2(.38,.17),depth+.3)
		make_part(side+"_upper_arm",UPPER_ARM/.72,Vector2(.5,.15),-5 if side == "far" else 10)
		make_part(side+"_forearm",LOWER_ARM/.82,Vector2(.5,.09),-4 if side == "far" else 13)
	make_part("torso_blue",78,Vector2(.50,.02),5)
	make_part("torso_red",78,Vector2(.50,.02),5)
	make_part("head",60,Vector2(.51,.94),8)
	make_part("sword",SWORD_WIDTH / aspect("sword"),Vector2(SWORD_GRIP_X,.52),11)
	make_part("near_joint",12,Vector2(.5,.5),13.1,"joint")
	make_part("far_joint",10,Vector2(.5,.5),-3.5,"joint")
	for key in mats:
		if key.begins_with("far"):
			mats[key].set_shader_parameter("tint",Color(.78,.84,.94))
	make_effect()
	display = Sprite2D.new()
	display.texture = viewport.get_texture()
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(display)
	set_pose("idle",0)

func aspect(name_: String) -> float:
	var texture: Texture2D = load("res://assets/%s.png" % name_)
	return texture.get_width()/float(texture.get_height())

func make_part(name_: String,height: float,pivot: Vector2,depth: float,asset := "") -> void:
	var file := name_ if asset == "" else asset
	# Asset bounds and attachment are independent of atlas cells.
	if FileAccess.file_exists("res://assets/corrections.json"):
		var fixes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/corrections.json"))
		if fixes.has(file):
			var fix: Dictionary = fixes[file]
			file = fix.asset
			if fix.has("height"): height = float(fix.height)
			if fix.has("pivot"): pivot = Vector2(fix.pivot[0],fix.pivot[1])
	var tex: Texture2D = load("res://assets/%s.png" % file)
	var width := height*tex.get_width()/float(tex.get_height())
	var attachment: Dictionary = {}
	if FileAccess.file_exists("res://assets/attachments.json"):
		var anchors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/attachments.json"))
		attachment = anchors.get(name_,{})
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Subdivided textured planes are actual 3D geometry, not Sprite2D frames.
	for row in range(8):
		for col in range(4):
			var corners := [Vector2(col/4.0,row/8.0),Vector2((col+1)/4.0,row/8.0),Vector2(col/4.0,(row+1)/8.0),Vector2((col+1)/4.0,(row+1)/8.0)]
			for i in [0,2,1,1,2,3]:
				var uv: Vector2 = corners[i]
				mesh.set_uv(uv)
				mesh.set_normal(Vector3(0,0,1))
				var local := Vector2((uv.x-pivot.x)*width,(uv.y-pivot.y)*height)
				if not attachment.is_empty():
					# Align the painted elbow and fist center, preserving aspect ratio.
					var size := Vector2(tex.get_width(),tex.get_height())
					var start := Vector2(attachment.start[0],attachment.start[1])
					var end := Vector2(attachment.end[0],attachment.end[1])
					var delta := (end-start)*size
					local = ((uv-start)*size).rotated(PI*.5-delta.angle())*float(attachment.length)/delta.length()
				mesh.add_vertex(Vector3(local.x,-local.y,0))
	var material := ShaderMaterial.new()
	material.shader = load("res://cutout.gdshader")
	material.set_shader_parameter("art",tex)
	var node := MeshInstance3D.new()
	node.mesh = mesh.commit()
	node.material_override = material
	node.position.z = depth
	root.add_child(node)
	parts[name_] = node
	mats[name_] = material

func place(name_: String,at: Vector2,rotation_ := 0.0) -> void:
	var node: MeshInstance3D = parts[name_]
	node.position.x = at.x
	node.position.y = -at.y
	node.rotation.z = -rotation_

func segment(name_: String,a: Vector2,b: Vector2) -> void:
	place(name_,a,(b-a).angle()-PI*.5)

func solve(a: Vector2,target: Vector2,upper: float,lower: float,hint: Vector2) -> Array:
	var delta := target-a
	var distance := clampf(delta.length(),absf(upper-lower)+.001,upper+lower-.001)
	var dir := delta.normalized()
	var projected := (upper*upper-lower*lower+distance*distance)/(2*distance)
	var h := sqrt(maxf(0.0,upper*upper-projected*projected))
	var normal := Vector2(-dir.y,dir.x)
	var first := a+dir*projected+normal*h
	var second := a+dir*projected-normal*h
	return [first if first.distance_squared_to(hint) < second.distance_squared_to(hint) else second,a+dir*distance]

func targets(action: String,frame: int) -> Dictionary:
	var p := {"near_ankle":Vector2(18,-14.5),"far_ankle":Vector2(-18,-14.5),"near_hand":Vector2(19,-98),"far_hand":Vector2(-32,-108),"body":Vector2.ZERO,"head":0.0,"angle":.37}
	if action == "walk":
		p.near_ankle = [Vector2(31,-14.5),Vector2(0,-14.5),Vector2(-30,-14.5),Vector2(-13,-32)][frame]
		p.far_ankle = [Vector2(-30,-14.5),Vector2(-13,-32),Vector2(31,-14.5),Vector2(0,-14.5)][frame]
		p.body = Vector2(0,[0,-2,0,-2][frame])
		p.near_hand = [Vector2(24,-100),Vector2(17,-97),Vector2(10,-99),Vector2(19,-99)][frame]
		p.far_hand = [Vector2(-27,-108),Vector2(-34,-107),Vector2(-39,-108),Vector2(-32,-107)][frame]
	if action == "slash":
		p.near_ankle = Vector2(31,-14.5)
		p.far_ankle = Vector2(-27,-14.5)
		p.near_hand = [Vector2(-25,-187),Vector2(5,-208),Vector2(59,-158),Vector2(55,-112),Vector2(34,-101),Vector2(19,-98)][frame]
		p.body = [Vector2(-3,0),Vector2(-2,-1),Vector2(5,0),Vector2(7,1),Vector2(3,0),Vector2.ZERO][frame]
		p.angle = [-2.65,-1.60,-.12,.68,.46,.37][frame]
		p.head = [-.06,-.05,.02,.04,.02,0.0][frame]
		p.far_hand = [Vector2(-29,-110),Vector2(-26,-114),Vector2(-40,-108),Vector2(-43,-105),Vector2(-36,-107),Vector2(-32,-108)][frame]
	return p

func set_pose(action: String,frame: int,blend := 0.0,time_ := 0.0) -> void:
	if root == null:
		return
	current_action = action
	current_frame = frame
	var p := targets(action,frame)
	if blend > 0:
		var count := 4 if action == "walk" else (6 if action == "slash" else 1)
		var next := targets(action,mini(frame+1,count-1) if action == "slash" else (frame+1)%count)
		for key in p:
			p[key] = lerp(p[key],next[key],blend)
	var body: Vector2 = p.body
	joints.clear()
	for side in ["far","near"]:
		var hip := Vector2(-8 if side == "far" else 4,-96)+body
		var ankle: Vector2 = p[side+"_ankle"]
		var hint := hip.lerp(ankle,.5)+Vector2(25,0)
		var leg := solve(hip,ankle,UPPER_LEG,LOWER_LEG,hint)
		var knee: Vector2 = leg[0]
		ankle = leg[1]
		segment(side+"_thigh",hip,knee)
		segment(side+"_shin",knee,ankle)
		place(side+"_boot",ankle)
		joints[side+"_hip"] = hip
		joints[side+"_knee"] = knee
		joints[side+"_ankle"] = ankle
		var shoulder := Vector2(13 if side == "far" else -13,-149)+body
		var target: Vector2 = p[side+"_hand"]+body
		var elbow_hint := shoulder.lerp(target,.55)+Vector2(-24,-2)
		if action == "slash" and frame <= 1 and side == "near":
			elbow_hint += Vector2(-15,-15)
		var arm := solve(shoulder,target,UPPER_ARM,LOWER_ARM,elbow_hint)
		var elbow: Vector2 = arm[0]
		target = arm[1]
		segment(side+"_upper_arm",shoulder,elbow)
		segment(side+"_forearm",elbow,target)
		place(side+"_joint",elbow)
		joints[side+"_shoulder"] = shoulder
		joints[side+"_elbow"] = elbow
		joints[side+"_hand"] = target
		if side == "near":
			hand = target
	for color in ["blue","red"]:
		place("torso_"+color,Vector2(0,-163)+body)
		parts["torso_"+color].visible = color == outfit
		place("cape_"+color,Vector2(-14,-149)+body,-.03*sin(time_*3.0))
		parts["cape_"+color].visible = show_cape and color == outfit
		mats["cape_"+color].set_shader_parameter("bend",sin(time_*3.0)*3.0 if action != "idle" else 0.0)
	place("head",Vector2(5,-161)+body,p.head)
	place("hair",Vector2(-8,-205)+body,-.025*sin(time_*3.0))
	parts.hair.visible = show_hair
	mats.hair.set_shader_parameter("bend",sin(time_*3.0-1.0)*2.0 if action != "idle" else 0.0)
	sword_angle = p.angle
	place("sword",hand,sword_angle)
	parts.sword.visible = show_weapon
	mats.sword.set_shader_parameter("tint",Color(1,.83,.52) if golden_weapon else Color.WHITE)
	sword_grip = parts.sword.global_transform*Vector3.ZERO
	sword_tip = parts.sword.global_transform*Vector3(SWORD_WIDTH*(1-SWORD_GRIP_X),0,0)
	effect.visible = show_weapon and action == "slash" and frame in [2,3]
	effect.position = Vector3(body.x,-body.y,16)
	update_camera()
	queue_redraw()

func update_camera() -> void:
	var target := Vector3(42,126,0)
	var radians := deg_to_rad(angle)
	camera.position = target+Vector3(sin(radians)*800,0,cos(radians)*800)
	camera.look_at(target)
	var floor_ := camera.unproject_position(Vector3.ZERO)
	display.position = -floor_
	display.scale.x = facing
	if facing < 0:
		display.position.x *= -1

func make_effect() -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(24):
		var a := -1.65+i/24.0*2.40
		var b := -1.65+(i+1)/24.0*2.40
		var center := Vector2(-5,-136)
		var points := [center+Vector2(cos(a),sin(a))*138,center+Vector2(cos(b),sin(b))*138,center+Vector2(cos(a),sin(a))*130,center+Vector2(cos(b),sin(b))*130]
		for index in [0,1,2,1,3,2]:
			var p: Vector2 = points[index]
			mesh.add_vertex(Vector3(p.x,-p.y,0))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color("b6ecff")
	effect = MeshInstance3D.new()
	effect.mesh = mesh.commit()
	effect.material_override = material
	root.add_child(effect)

func _draw() -> void:
	if not debug_bones:
		return
	for side in ["far","near"]:
		var color := Color("4fa7d7") if side == "far" else Color("ffd478")
		for chain in [["hip","knee","ankle"],["shoulder","elbow","hand"]]:
			for i in range(2):
				var a: Vector2 = joints[side+"_"+chain[i]]
				var b: Vector2 = joints[side+"_"+chain[i+1]]
				a.x *= facing
				b.x *= facing
				draw_line(a,b,color,1)
				draw_circle(a,2,color)
