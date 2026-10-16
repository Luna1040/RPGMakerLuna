extends Node3D
## Original articulated 3D office. No gameplay props, hit areas or layer-2 colliders.
const Geo=preload("res://desk_geometry.gd")
var game:Node3D
var boss:Node3D
var coworker:Node3D
var boss_chair:Node3D
var coworker_keyboard:=Vector3(1.88,.795,-1.54)
var clock:=0.0
var path_points:Array[Vector3]=[]
var path_lengths:Array[float]=[]
var path_length:=0.0
var step_distance:=0.0
var walking:=false
var turn_target:=0.0
var obstacles:Array[Rect2]=[Rect2(-1.07,-.65,2.14,1.28),Rect2(-.255,-1.98,1.35,.72),Rect2(1.24,-1.58,1.30,.72)]
var route:Array[Vector3]=[Vector3(.42,0,-2.43),Vector3(-.90,0,-2.43),Vector3(-1.48,0,-2.20),Vector3(-1.48,0,-1.12),Vector3(-1.29,0,-.90)]
var skin:Material
var shirt:Material
var pants:Material
var hair:Material
func _ready() -> void:
	name="office_root"
	skin=Geo.material("c5a18a",.49);skin.metallic_specular=.38;shirt=game.mats.folder.duplicate();shirt.albedo_color=Color("768ba1");shirt.uv1_triplanar=true;shirt.uv1_scale=Vector3.ONE*12
	pants=game.mats.folder.duplicate();pants.albedo_color=Color("343c48");pants.uv1_triplanar=true;pants.uv1_scale=Vector3.ONE*12
	hair=Geo.material("342c28",.72)
	room();workstation(Vector3(.42,0,-1.62),true);workstation(Vector3(1.89,0,-1.22),false)
	boss=actor("boss",true);boss.position=route[0];boss_chair=chair(route[0]+Vector3(0,0,-.04))
	coworker=actor("coworker",false);coworker.position=Vector3(1.89,0,-2.02);chair(coworker.position+Vector3(0,0,-.04))
	build_path()
	set_dynamic_layers(boss);set_dynamic_layers(coworker);set_dynamic_layers(boss_chair)
	pose("free",0)
func room() -> void:
	var wall:=Geo.material("667472",.95);var floor_mat:=Geo.material("394442",.85)
	Geo.box(self,Vector3(10,.06,10),Vector3(0,-.04,-1),floor_mat,0)
	Geo.box(self,Vector3(10,3.1,.10),Vector3(0,1.5,-4.5),wall,0)
	Geo.box(self,Vector3(.1,3.1,10),Vector3(-4.5,1.5,-1),wall,0)
	Geo.box(self,Vector3(.1,3.1,10),Vector3(4.5,1.5,-1),wall,0)
	Geo.box(self,Vector3(10,.05,10),Vector3(0,3.05,-1),Geo.material("a7ada3",.9),0)
	for x in [-3,-1.5,0,1.5,3]:Geo.box(self,Vector3(.007,.001,9),Vector3(x,-.006,-1),Geo.material("4e5955"),0)
	var window_mat:=Geo.material("83a1a9",.28);window_mat.emission_enabled=true;window_mat.emission=Color("607b83");window_mat.emission_energy_multiplier=.25
	Geo.box(self,Vector3(2.2,1.25,.025),Vector3(1.7,1.77,-4.43),window_mat,.002)
	for x in [.55,1.7,2.85]:Geo.box(self,Vector3(.045,1.34,.06),Vector3(x,1.77,-4.39),game.mats.plastic)
	for y in [1.1,2.44]:Geo.box(self,Vector3(2.36,.045,.06),Vector3(1.7,y,-4.39),game.mats.plastic)
	for i in range(12):Geo.box(self,Vector3(2.22,.018,.035),Vector3(1.7,1.22+i*.095,-4.32),Geo.material("99a7a3",.8),0)
	Geo.box(self,Vector3(1.1,.30,.18),Vector3(-1.1,2.54,-4.30),game.mats.plastic,.025)
	for i in range(9):Geo.box(self,Vector3(.92,.009,.035),Vector3(-1.1,2.45+i*.012,-4.20),game.mats.dark,0)
	for x in [-1.8,1.8]:
		Geo.box(self,Vector3(1.2,.04,.32),Vector3(x,2.91,-1.8),game.mats.plastic,.01)
		var panel:=Geo.material("bbc9c9");panel.emission_enabled=true;panel.emission=Color("91b4c4");panel.emission_energy_multiplier=.6
		Geo.box(self,Vector3(1.08,.006,.25),Vector3(x,2.88,-1.8),panel)
		var light:=OmniLight3D.new();light.position=Vector3(x,2.65,-1.8);light.light_color=Color("c0d7e0");light.light_energy=.72;light.omni_range=3.8;light.light_size=.65;light.light_specular=.20;add_child(light)
	# Broad luminaires face the workstations, rather than increasing exposure/ambient.
	for x in [-.5,1.9]:
		var soft:=SpotLight3D.new();soft.position=Vector3(x,2.68,-.55)
		add_child(soft);soft.look_at(Vector3(x,.95,-2.10),Vector3.UP)
		soft.light_color=Color("d2dfe3");soft.light_energy=1.15;soft.light_size=.52
		soft.light_specular=.20
		soft.spot_range=3.8;soft.spot_angle=48;soft.spot_attenuation=.65
		soft.shadow_enabled=true;soft.shadow_bias=.018;soft.shadow_normal_bias=.025
	var window_fill:=OmniLight3D.new();window_fill.position=Vector3(.5,1.9,-3.9)
	window_fill.light_color=Color("bcd4df");window_fill.light_energy=.6;window_fill.light_size=.7;window_fill.omni_range=3.3;window_fill.light_specular=.18;add_child(window_fill)
	for i in range(4):
		Geo.box(self,Vector3(.35,.26,.025),Vector3(-1.5+i*.42,1.75,-4.42),game.mats.edge)
		Geo.box(self,Vector3(.32,.23,.008),Vector3(-1.5+i*.42,1.75,-4.398),game.mats.paper)
func workstation(at:Vector3,is_boss:bool) -> void:
	var root:=Node3D.new();root.position=at;add_child(root)
	Geo.box(root,Vector3(1.35,.045,.72),Vector3(0,.742,0),game.mats.drawer_wood,.008)
	for x in [-.56,.56]:
		Geo.box(root,Vector3(.035,.70,.035),Vector3(x,.35,-.25),game.mats.steel)
		Geo.box(root,Vector3(.035,.70,.035),Vector3(x,.35,.25),game.mats.steel)
	var monitor:=Node3D.new();root.add_child(monitor);monitor.position=Vector3(0,.768,-.13);monitor.rotation.y=PI
	Geo.box(monitor,Vector3(.28,.02,.18),Vector3(0,.01,0),game.mats.dark,.006)
	Geo.box(monitor,Vector3(.034,.16,.035),Vector3(0,.10,0),game.mats.dark)
	Geo.box(monitor,Vector3(.55,.325,.038),Vector3(0,.295,0),game.mats.dark,.01)
	Geo.box(monitor,Vector3(.50,.28,.003),Vector3(0,.296,.023),game.mats.notes,.002)
	for i in range(9):Geo.box(monitor,Vector3(.23,.004,.001),Vector3(0,.24+i*.012,-.020),game.mats.steel,0)
	Geo.box(root,Vector3(.39,.018,.135),Vector3(0,.782,-.32),game.mats.plastic,.006)
	for i in range(12):
		for row in range(4):Geo.box(root,Vector3(.024,.007,.023),Vector3(-.165+i*.030,.794,-.37+row*.027),game.mats.key,.001)
	Geo.box(root,Vector3(.065,.025,.10),Vector3(.30,.783,-.32),game.mats.dark,.009)
	for i in range(3):Geo.box(root,Vector3(.17,.023,.25),Vector3(-.48,.78+i*.026,.02),game.mats.folder,.002)
	for i in range(4):Geo.box(root,Vector3(.025,.25,.20),Vector3(.40+i*.035,.894,-.08),game.mats.folder,.002)
	plant(root,Vector3(-.48,.769,-.21))
	Geo.rod(root,Vector3(0,.78,-.13),Vector3(.08,.23,-.32),.003,game.mats.dark)
func plant(parent:Node3D,pos:Vector3) -> void:
	Geo.cylinder(parent,.05,.065,pos+Vector3(0,.032,0),game.mats.ceramic,.045)
	var green:=Geo.material("53775c",.8)
	for i in range(7):
		var angle:=i*2.4;var end:=pos+Vector3(cos(angle)*.047,.10+i*.014,sin(angle)*.047)
		Geo.rod(parent,pos+Vector3(0,.05,0),end,.0015,green)
		var leaf:=oval(parent,Vector3(.018,.004,.047),end,green);leaf.rotation=Vector3(.4,angle,.3)
func chair(pos:Vector3) -> Node3D:
	var root:=Node3D.new();root.position=pos;add_child(root)
	Geo.box(root,Vector3(.43,.065,.39),Vector3(0,.46,.02),pants,.025)
	Geo.box(root,Vector3(.43,.49,.065),Vector3(0,.76,-.20),pants,.022)
	Geo.cylinder(root,.028,.34,Vector3(0,.23,0),game.mats.steel)
	for i in range(5):
		var dir:=Vector3(cos(i*TAU/5),0,sin(i*TAU/5));Geo.rod(root,Vector3(0,.07,0),dir*.27+Vector3(0,.065,0),.015,game.mats.dark)
		Geo.cylinder(root,.03,.028,dir*.27+Vector3(0,.035,0),game.mats.dark)
	return root
func oval(parent:Node3D,size:Vector3,pos:Vector3,mat:Material) -> MeshInstance3D:
	var shape:=SphereMesh.new();shape.radius=1;shape.height=2;shape.radial_segments=40;shape.rings=24
	var mesh:=Geo.mesh(parent,shape,pos,mat);mesh.scale=size;mesh.layers=2
	return mesh
func tapered(parent:Node3D,a:Vector3,b:Vector3,radius:Vector2,mat:Material) -> MeshInstance3D:
	# Cloth/limb mesh with varying anatomical cross-section, not a coarse cylinder.
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length:=a.distance_to(b);var rings:Array=[]
	for k in range(9):
		var t:=float(k)/8;var r:=lerpf(radius.x,radius.y,t)*(1+.04*sin(t*PI*3));var ring:Array=[]
		for i in range(33):ring.append(Vector3(cos(i*TAU/32)*r,length*t,sin(i*TAU/32)*r*.84))
		rings.append(ring)
	for k in range(8):
		for i in range(32):
			var vs:=[rings[k][i],rings[k+1][i],rings[k+1][i+1],rings[k][i+1]]
			var ns:Array=[]
			for v in vs:ns.append(Vector3(v.x,0,v.z/.84/.84).normalized())
			Geo.surface_quad(st,vs,ns,[Vector2(float(i)/32,float(k)/8),Vector2(float(i)/32,float(k+1)/8),Vector2(float(i+1)/32,float(k+1)/8),Vector2(float(i+1)/32,float(k)/8)])
	st.generate_tangents();var n:=Geo.mesh(parent,st.commit(),a,mat);n.quaternion=Quaternion(Vector3.UP,(b-a).normalized());n.layers=2;return n
func contour(parent:Node3D,profile:Array,mat:Material,face:bool=false,hair_cap:bool=false) -> MeshInstance3D:
	# Continuous loft in local metres; shared smooth normals, UV and tangent frame.
	# Nose bridge, lips and chin are deformations of the same facial surface.
	var rings:Array=[];var segments:=48
	for band in range(profile.size()-1):
		for sub in range(4):
			var p:Vector4=profile[band].lerp(profile[band+1],float(sub)/4)
			var ring:Array=[]
			for j in range(segments+1):ring.append(contour_vertex(p,float(j)*TAU/segments,face,hair_cap,band==0,float(sub)/4))
			rings.append(ring)
	var last:Array=[]
	for j in range(segments+1):last.append(contour_vertex(profile[-1],float(j)*TAU/segments,face,hair_cap,false,1))
	rings.append(last)
	var normals:Array=[]
	for k in range(rings.size()):
		var ns:Array=[]
		for j in range(segments+1):
			var index:=j%segments
			var around:Vector3=rings[k][(index+1)%segments]-rings[k][(index+segments-1)%segments]
			var vertical:Vector3=rings[mini(k+1,rings.size()-1)][j]-rings[maxi(0,k-1)][j]
			ns.append(around.cross(vertical).normalized())
		normals.append(ns)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(rings.size()-1):
		for j in range(segments):
			Geo.surface_quad(st,[rings[k][j],rings[k+1][j],rings[k+1][j+1],rings[k][j+1]],[normals[k][j],normals[k+1][j],normals[k+1][j+1],normals[k][j+1]],[Vector2(float(j)/segments,float(k)/(rings.size()-1)),Vector2(float(j)/segments,float(k+1)/(rings.size()-1)),Vector2(float(j+1)/segments,float(k+1)/(rings.size()-1)),Vector2(float(j+1)/segments,float(k)/(rings.size()-1))])
	for k in [0,rings.size()-1]:
		var centre:=Vector3.ZERO
		for j in range(segments):centre+=rings[k][j]/segments
		for j in range(segments):Geo.tri(st,centre,rings[k][j+1] if k==0 else rings[k][j],rings[k][j] if k==0 else rings[k][j+1],Vector3(.3,.6,.3))
	st.generate_tangents();var mesh:=Geo.mesh(parent,st.commit(),Vector3.ZERO,mat);mesh.layers=2;return mesh
func contour_vertex(p:Vector4,angle:float,face:bool,hair_cap:bool,first_band:bool,t:float) -> Vector3:
	var v:=Vector3(sin(angle)*p.y,p.x,cos(angle)*p.z+p.w)
	var front:=pow(maxf(0,cos(angle)),12)
	if face:
		var nose:=.010*exp(-pow(v.x/.014,2)-pow((v.y+.008)/.022,2))
		var bridge:=.004*exp(-pow(v.x/.013,2)-pow((v.y-.018)/.029,2))
		var lip:=.0017*exp(-pow(v.x/.023,4)-pow((v.y+.052)/.005,2))
		v.z+=front*(nose+bridge+lip)
	if hair_cap and first_band:v.y+=.031*pow(maxf(0,cos(angle)),3)*(1-t)
	return v
func inspection_yaw() -> float:
	# Face the player's seated face, with no instantaneous +90-degree turn.
	var direction:=Vector3(0,1.265,1.27)-route[-1]
	return atan2(direction.x,direction.z)
func actor(id:String,is_boss:bool) -> Node3D:
	var root:=Node3D.new();root.name=id;add_child(root)
	var body:=Node3D.new();body.name="body";root.add_child(body)
	contour(body,[Vector4(.81,.12,.085,0),Vector4(.86,.161,.108,0),Vector4(.93,.165,.110,0),Vector4(.96,.148,.104,0)],pants)
	var torso:=contour(body,[Vector4(-.25,.147,.105,0),Vector4(-.18,.151,.110,0),Vector4(-.08,.169,.118,-.005),Vector4(.035,.181,.123,-.009),Vector4(.12,.191,.113,-.011),Vector4(.17,.183,.092,-.01),Vector4(.225,.080,.058,0),Vector4(.244,.054,.048,0)],shirt);torso.position.y=1.18;torso.name="torso"
	# Collar, shirt placket, seam, buttons, folded cloth layers.
	for side in [-1,1]:
		var collar:=Geo.box(body,Vector3(.07,.02,.09),Vector3(side*.045,1.41,.09),game.mats.paper,.005);collar.rotation.z=side*.28;collar.layers=2
	for i in range(5):oval(body,Vector3(.003,.003,.002),Vector3(0,1.14+i*.046,.131),game.mats.ceramic)
	tapered(body,Vector3(0,.91,.125),Vector3(0,1.35,.131),Vector2(.003,.003),game.mats.paper)
	Geo.box(body,Vector3(.075,.085,.007),Vector3(-.12,1.24,.121),shirt,.008).layers=2
	tapered(body,Vector3(0,1.42,0),Vector3(0,1.50,0),Vector2(.054,.048),skin)
	var head:=Node3D.new();head.name="head";head.position=Vector3(0,1.565,0);body.add_child(head)
	var face:=contour(head,[Vector4(-.114,.029,.031,.003),Vector4(-.097,.049,.049,.002),Vector4(-.073,.061,.061,-.004),Vector4(-.037,.075,.072,-.008),Vector4(.006,.082,.078,-.009),Vector4(.045,.080,.080,-.012),Vector4(.081,.073,.074,-.014),Vector4(.109,.051,.055,-.014),Vector4(.123,.006,.006,-.014)],skin,true);face.name="face_contour"
	var cap:=contour(head,[Vector4(.028,.081,.081,-.014),Vector4(.064,.083,.081,-.014),Vector4(.098,.068,.070,-.014),Vector4(.123,.042,.045,-.014),Vector4(.132,.002,.002,-.014)],hair,false,true);cap.name="hair_cap"
	for side in [-1,1]:
		oval(head,Vector3(.010,.022,.011),Vector3(side*.083,-.010,-.013),skin)
		oval(head,Vector3(.014,.004,.002),Vector3(side*.032,.024,.066),Geo.material("c9c5b7",.48))
		oval(head,Vector3(.003,.003,.002),Vector3(side*.032,.024,.068),hair)
		tapered(head,Vector3(side*.018,.036,.066),Vector3(side*.051,.036,.061),Vector2(.0018,.0012),hair)
		if is_boss:
			var frame:=Geo.torus(head,.019,.020,Vector3(side*.032,.024,.071),game.mats.steel);frame.rotation.x=PI/2;frame.scale.y=.60
			Geo.rod(head,Vector3(side*.051,.026,.060),Vector3(side*.078,.026,-.016),.0012,game.mats.steel)
	if is_boss:Geo.rod(head,Vector3(-.011,.024,.073),Vector3(.011,.024,.073),.001,game.mats.steel)
	for side in [-1,1]:
		var shoulder:=joint(body,"arm"+str(side),Vector3(side*.19,1.34,0))
		tapered(shoulder,Vector3.ZERO,Vector3(0,-.28,0),Vector2(.064,.043),shirt).name="upper_arm"
		var elbow:=joint(shoulder,"elbow",Vector3(0,-.28,0))
		oval(elbow,Vector3(.044,.045,.042),Vector3.ZERO,shirt)
		tapered(elbow,Vector3.ZERO,Vector3(0,-.27,0),Vector2(.044,.028),shirt).name="forearm"
		var wrist:=joint(elbow,"wrist",Vector3(0,-.27,0))
		Geo.torus(wrist,.027,.032,Vector3.ZERO,game.mats.paper)
		var hand:=joint(wrist,"hand",Vector3.ZERO)
		oval(hand,Vector3(.030,.034,.015),Vector3(0,-.025,0),skin)
		for digit in range(4):tapered(hand,Vector3(-.020+digit*.013,-.04,0),Vector3(-.020+digit*.013,-.078+absf(digit-1.5)*.005,.003),Vector2(.006,.0045),skin)
		tapered(hand,Vector3(side*.025,-.015,.003),Vector3(side*.041,-.043,.005),Vector2(.008,.006),skin)
		var hip:=joint(body,"leg"+str(side),Vector3(side*.095,.87,0))
		tapered(hip,Vector3.ZERO,Vector3(0,-.40,0),Vector2(.083,.060),pants).name="thigh"
		var knee:=joint(hip,"knee",Vector3(0,-.40,0))
		oval(knee,Vector3(.059,.060,.055),Vector3.ZERO,pants)
		tapered(knee,Vector3.ZERO,Vector3(0,-.40,0),Vector2(.058,.039),pants).name="calf"
		var ankle:=joint(knee,"ankle",Vector3(0,-.40,0))
		var shoe:=joint(ankle,"shoe",Vector3.ZERO)
		oval(shoe,Vector3(.055,.044,.12),Vector3(0,-.025,.055),game.mats.dark)
	root.set_meta("is_boss",is_boss);return root
func joint(parent:Node3D,id:String,pos:Vector3) -> Node3D:
	var node:=Node3D.new();node.name=id;node.position=pos;parent.add_child(node);return node
func set_dynamic_layers(node:Node) -> void:
	if node is VisualInstance3D:node.layers=2
	for child in node.get_children():set_dynamic_layers(child)
func aim_bone(node:Node3D,end:Vector3,mesh_name:String,rest_length:float) -> void:
	var direction:Vector3=end-node.position
	node.quaternion=Quaternion(Vector3.DOWN,direction.normalized())
	var mesh:MeshInstance3D=node.get_node(mesh_name);mesh.scale.y=direction.length()/rest_length
func articulation(root:Node3D,seated:float,walk:float=0,typing:bool=false,gait:float=0.0) -> void:
	var body:Node3D=root.get_node("body");body.position.y=-.36*seated;body.rotation.x=0
	body.get_node("torso").scale.y=1+.005*sin(clock*2)
	body.get_node("head").rotation.x=.055*seated if root==boss else .10
	for side in [-1,1]:
		var shoulder:Node3D=body.get_node("arm"+str(side))
		var elbow:Node3D=shoulder.get_node("elbow");var wrist:Node3D=elbow.get_node("wrist")
		var oscillation:=sin(walk+side*PI*.5)*.10*gait
		var elbow_body:=Vector3(side*.24,1.08,oscillation).lerp(Vector3(side*.25,.36*seated+.807,.19),seated)
		var wrist_body:=Vector3(side*.24,.84,oscillation*.7).lerp(Vector3(side*.13,.36*seated+.817,.46),seated)
		if typing:wrist_body.y+=sin(clock*8+side)*.002
		aim_bone(shoulder,elbow_body,"upper_arm",.28)
		elbow.position=shoulder.to_local(body.to_global(elbow_body))
		var wrist_local:Vector3=shoulder.to_local(body.to_global(wrist_body))
		aim_bone(elbow,wrist_local,"forearm",.27)
		wrist.position=elbow.to_local(body.to_global(wrist_body))
		wrist.global_basis=root.global_basis*Basis.IDENTITY
		var hand:Node3D=wrist.get_node("hand");hand.rotation.x=-PI/2 if seated>.5 else 0
		var hip:Node3D=body.get_node("leg"+str(side));var knee:Node3D=hip.get_node("knee");var ankle:Node3D=knee.get_node("ankle")
		var stride:=sin(walk+side*PI*.5)*.19*(1-seated)*gait
		var knee_body:=Vector3(side*.095,.47,stride*.6).lerp(Vector3(side*.095,.36*seated+.46,.34),seated)
		var lift:=maxf(0,sin(walk+side*PI*.5))*.045*(1-seated)*gait
		var ankle_body:=Vector3(side*.095,.07+lift,stride).lerp(Vector3(side*.095,.36*seated+.07,.36),seated)
		aim_bone(hip,knee_body,"thigh",.40);knee.position=hip.to_local(body.to_global(knee_body))
		aim_bone(knee,hip.to_local(body.to_global(ankle_body)),"calf",.40);ankle.position=knee.to_local(body.to_global(ankle_body))
		ankle.global_basis=root.global_basis
func build_path() -> void:
	path_points.clear();path_lengths.clear();path_length=0;path_points.append(route[0])
	for i in range(1,route.size()-1):
		var corner:Vector3=route[i];var incoming:Vector3=(corner-route[i-1]).normalized();var outgoing:Vector3=(route[i+1]-corner).normalized()
		var before:=corner-incoming*.16;var after:=corner+outgoing*.16
		path_points.append(before)
		for k in range(1,17):
			var t:=float(k)/16;path_points.append(before.lerp(corner,t).lerp(corner.lerp(after,t),t))
	path_points.append(route[-1])
	for i in range(path_points.size()-1):var length:=path_points[i].distance_to(path_points[i+1]);path_lengths.append(length);path_length+=length
func route_point(t:float) -> Vector3:
	var distance:=clampf(t,0,1)*path_length
	for i in range(path_lengths.size()):
		if distance<=path_lengths[i]:return path_points[i].lerp(path_points[i+1],distance/path_lengths[i])
		distance-=path_lengths[i]
	return path_points[-1]
func pose(state:String,progress:float,delta:float=1.0/60) -> void:
	if not boss:return
	var seated:=0.0;var before:Vector3=boss.position;var target_yaw:=boss.rotation.y
	walking=false
	match state:
		"free":boss.position=route[0];target_yaw=0;seated=1
		"warning":
			if progress<.20:boss.position=route[0];seated=1-smoothstep(.055,.20,progress);target_yaw=0
			else:
				var t:=smoothstep(0,1,(progress-.20)/.80);boss.position=route_point(t);var direction:=route_point(minf(1,t+.015))-route_point(maxf(0,t-.005))
				if direction.length()>.001:target_yaw=atan2(direction.x,direction.z)
				if t>.96:target_yaw=lerp_angle(target_yaw,inspection_yaw(),smoothstep(.96,1,t))
				walking=progress<.99
		"checking":boss.position=route[-1];target_yaw=inspection_yaw()
		"returning":
			if progress<.80:
				var t:=1-smoothstep(0,1,progress/.80);boss.position=route_point(t);var direction:=route_point(maxf(0,t-.015))-route_point(minf(1,t+.005))
				if direction.length()>.001:target_yaw=atan2(direction.x,direction.z)
				walking=progress>.01
			else:boss.position=route[0];target_yaw=0;seated=smoothstep(.80,1,progress)
	boss.rotation.y=lerp_angle(boss.rotation.y,target_yaw,1-exp(-delta*7))
	var moved:=before.distance_to(boss.position)
	if moved<.20:step_distance+=moved
	var walk:=step_distance/.38*PI
	var stop_blend:=1.0 if walking else 0.0
	if state=="warning":stop_blend*=1-smoothstep(.94,1,progress)
	if state=="returning":stop_blend*=1-smoothstep(.74,.80,progress)
	# Chair rolls back before standing, then the route exits laterally.
	var back:=.38*(1-seated)
	if state=="warning" and progress<.20:back=.38*smoothstep(0,.055,progress)
	boss_chair.position=route[0]+Vector3(0,0,-.04-back)
	articulation(boss,seated,walk,seated>.9,stop_blend);articulation(coworker,1,0,true)
func tick(delta:float) -> void:
	clock+=delta
	if game.phase=="free":pose("free",0,delta)
	elif game.phase=="checking":pose("checking",0,delta)
	articulation(coworker,1,0,true)
