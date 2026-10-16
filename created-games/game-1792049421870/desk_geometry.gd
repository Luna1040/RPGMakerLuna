extends RefCounted
## All prop silhouettes are real, original 3D geometry in metre units.

static func material(hex: String, roughness: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = roughness
	m.metallic = metal
	return m

static func textured(path: String, hex: String = "ffffff", roughness: float = 0.7) -> StandardMaterial3D:
	var m := material(hex, roughness)
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func mesh(parent: Node3D, shape: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = shape
	n.material_override = mat
	n.position = pos
	parent.add_child(n)
	return n

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.003) -> MeshInstance3D:
	if bevel <= 0.0001:
		var b := BoxMesh.new()
		b.size = size
		return mesh(parent, b, pos, mat)
	# Three eight-sided rings give physical bevels on every edge.
	var b := minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.24)
	var rings: Array[PackedVector3Array] = []
	for k in range(4):
		var yy: float = [-size.y/2, -size.y/2+b, size.y/2-b, size.y/2][k]
		var inset: float = b if k == 0 or k == 3 else 0.0
		var xx := size.x/2-inset
		var zz := size.z/2-inset
		var c := b * 0.7
		rings.append(PackedVector3Array([Vector3(-xx+c,yy,-zz),Vector3(xx-c,yy,-zz),Vector3(xx,yy,-zz+c),Vector3(xx,yy,zz-c),Vector3(xx-c,yy,zz),Vector3(-xx+c,yy,zz),Vector3(-xx,yy,zz-c),Vector3(-xx,yy,-zz+c)]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(3):
		for i in range(8):
			var j := (i+1)%8
			tri(st, rings[k][i], rings[k+1][i], rings[k+1][j], size)
			tri(st, rings[k][i], rings[k+1][j], rings[k][j], size)
	for i in range(8):
		var j := (i+1)%8
		tri(st, Vector3(0,-size.y/2,0), rings[0][i], rings[0][j], size)
		tri(st, Vector3(0,size.y/2,0), rings[3][j], rings[3][i], size)
	st.generate_tangents()
	return mesh(parent, st.commit(), pos, mat)

static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, size: Vector3) -> void:
	# Source triangles are CCW with outward cross products; Godot fronts are CW.
	var normal := (b-a).cross(c-a).normalized()
	for v in [a,c,b]:
		# Never average broad caps into the bevel rings: it creates diagonal shading.
		st.set_normal(normal)
		# Dominant-axis projection prevents collapsed UVs on vertical sides.
		var uv: Vector2
		if absf(normal.y) >= maxf(absf(normal.x),absf(normal.z)):
			uv=Vector2(v.x/size.x+0.5,v.z/size.z+0.5)
		elif absf(normal.x) > absf(normal.z):
			uv=Vector2(v.z/size.z+0.5,0.5-v.y/size.y)
		else:
			uv=Vector2(v.x/size.x+0.5,0.5-v.y/size.y)
		st.set_uv(uv)
		st.add_vertex(v)

static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, top: float = -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius if top < 0 else top
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 48
	return mesh(parent, c, pos, mat)

static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius*2
	s.radial_segments = 24
	s.rings = 12
	return mesh(parent,s,pos,mat)

static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 32
	t.ring_segments = 12
	return mesh(parent,t,pos,mat)

static func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var n := cylinder(parent,radius,a.distance_to(b),(a+b)/2,mat)
	n.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return n

static func tube(parent: Node3D, outer: float, inner: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	# Separate analytic wall/cap normals, a cylindrical UV unwrap, and a closed seam.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 64
	for i in range(SEGMENTS):
		var u0 := float(i)/SEGMENTS
		var u1 := float(i+1)/SEGMENTS
		var a := u0*TAU
		var b := u1*TAU
		var oa := Vector3(cos(a)*outer,0,sin(a)*outer)
		var ob := Vector3(cos(b)*outer,0,sin(b)*outer)
		var ia := Vector3(cos(a)*inner,0,sin(a)*inner)
		var ib := Vector3(cos(b)*inner,0,sin(b)*inner)
		var h := Vector3(0,height,0)
		var na := Vector3(cos(a),0,sin(a))
		var nb := Vector3(cos(b),0,sin(b))
		surface_quad(st,[oa,oa+h,ob+h,ob],[na,na,nb,nb],[Vector2(u0,1),Vector2(u0,0),Vector2(u1,0),Vector2(u1,1)])
		surface_quad(st,[ia,ib,ib+h,ia+h],[-na,-nb,-nb,-na],[Vector2(u0,1),Vector2(u1,1),Vector2(u1,0),Vector2(u0,0)])
		var cap_uv := [Vector2(oa.x,oa.z),Vector2(ia.x,ia.z),Vector2(ib.x,ib.z),Vector2(ob.x,ob.z)]
		for k in range(4):cap_uv[k]=cap_uv[k]/(outer*2)+Vector2(0.5,0.5)
		surface_quad(st,[oa+h,ia+h,ib+h,ob+h],[Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP],cap_uv)
		surface_quad(st,[oa,ob,ib,ia],[Vector3.DOWN,Vector3.DOWN,Vector3.DOWN,Vector3.DOWN],[cap_uv[0],cap_uv[3],cap_uv[2],cap_uv[1]])
	st.generate_tangents()
	return mesh(parent,st.commit(),pos,mat)

static func surface_quad(st: SurfaceTool, vertices: Array, normals: Array, uvs: Array) -> void:
	# Pick clockwise winding by the supplied physical normal, then use it consistently.
	for indices in [[0,1,2],[0,2,3]]:
		var a: Vector3=vertices[indices[0]]
		var b: Vector3=vertices[indices[1]]
		var c: Vector3=vertices[indices[2]]
		var expected: Vector3=(normals[indices[0]]+normals[indices[1]]+normals[indices[2]]).normalized()
		if (c-a).cross(b-a).dot(expected)<0:indices.reverse()
		for k in indices:
			st.set_normal(normals[k])
			st.set_uv(uvs[k])
			st.add_vertex(vertices[k])

static func hit(parent: Node3D, id: String, size: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	var a := Area3D.new()
	a.set_meta("id", id)
	a.collision_layer = 2
	a.collision_mask = 0
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	c.position = offset
	a.add_child(c)
	parent.add_child(a)

static func label(parent: Node3D, text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://font.ttf")
	l.font_size = size
	l.pixel_size = 0.0006
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)
	return l
