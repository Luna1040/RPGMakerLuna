extends SceneTree
const Geo=preload("res://desk_geometry.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func require(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		push_error("DESK_GEOMETRY_FAIL "+why)

func inspect_mesh(mesh: ArrayMesh, hollow: bool) -> void:
	var a:=mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=a[Mesh.ARRAY_NORMAL]
	var uvs:PackedVector2Array=a[Mesh.ARRAY_TEX_UV]
	var bad_winding:=0
	var bad_uv:=0
	var cap_errors:=0
	var wall_errors:=0
	for i in range(0,vertices.size(),3):
		var p:=vertices[i];var q:=vertices[i+1];var r:=vertices[i+2]
		var face:Vector3=(r-p).cross(q-p).normalized()
		var normal:Vector3=(normals[i]+normals[i+1]+normals[i+2]).normalized()
		if face.dot(normal)<0.99:bad_winding+=1
		var uv1:=uvs[i+1]-uvs[i];var uv2:=uvs[i+2]-uvs[i]
		if absf(uv1.cross(uv2))<0.0000001:bad_uv+=1
		var centre:Vector3=(p+q+r)/3.0
		if hollow:
			if absf(face.y)>0.99:
				if centre.y>0.02 and normal.y<0.99:cap_errors+=1
				if centre.y<0.001 and normal.y>-.99:cap_errors+=1
			else:
				var radial:=Vector3(centre.x,0,centre.z).normalized()
				var radius:=Vector2(centre.x,centre.z).length()
				if radius>0.04 and normal.dot(radial)<.99:wall_errors+=1
				if radius<0.04 and normal.dot(radial)>-.99:wall_errors+=1
		else:
			if face.dot(centre)<0:wall_errors+=1
			if absf(centre.y)>.0499 and absf(normal.y)<.999:cap_errors+=1
	require(bad_winding==0,"clockwise winding agrees with physical normals "+str(bad_winding))
	require(bad_uv==0,"UV triangles nondegenerate "+str(bad_uv))
	require(cap_errors==0,"planar caps have independent outward normals "+str(cap_errors))
	require(wall_errors==0,"inner and outer walls face their physical sides "+str(wall_errors))

func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var mat:=Geo.material("ffffff")
	var box:=Geo.box(world,Vector3(.4,.1,.3),Vector3.ZERO,mat,.01)
	inspect_mesh(box.mesh,false)
	var tube:=Geo.tube(world,.044,.038,.094,Vector3.ZERO,mat)
	inspect_mesh(tube.mesh,true)
	require(mat.cull_mode==BaseMaterial3D.CULL_BACK,"backface culling remains enabled")
	world.queue_free()
	if failures.is_empty():
		print("DESK_GEOMETRY_PASS clockwise_normals planar_caps hollow_walls uv_tangents backface_culling")
		quit(0)
	else:quit(1)
