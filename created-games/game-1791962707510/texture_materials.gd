extends RefCounted
## Original generated source PNGs remain untouched; repeat borders blend in the material.
static var images: Dictionary = {}
static var materials: Dictionary = {}

static func image_texture(kind: String) -> ImageTexture:
	if images.has(kind): return images[kind]
	var path := "res://assets/textures/%s.png" % kind
	var refined := "res://assets/textures/chibi/%s.png" % kind
	if FileAccess.file_exists(refined): path=refined
	if not FileAccess.file_exists(path): return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))!=OK or image.is_empty(): return null
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	images[kind] = texture
	return texture

static func surface(kind: String) -> ShaderMaterial:
	if materials.has(kind): return materials[kind]
	var texture := image_texture(kind)
	if texture == null: return null
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D color_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.35;
uniform bool roof_tiles = false;
uniform bool earth_edge = false;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}
vec3 periodic_color(vec2 coord) {
    vec2 p = fract(coord);
    vec2 q = fract(p + vec2(0.5));
    vec2 weight = smoothstep(vec2(0.0),vec2(0.12),p) * (vec2(1.0)-smoothstep(vec2(0.88),vec2(1.0),p));
    vec3 a = texture(color_texture,p).rgb;
    vec3 b = texture(color_texture,vec2(q.x,p.y)).rgb;
    vec3 c = texture(color_texture,vec2(p.x,q.y)).rgb;
    vec3 d = texture(color_texture,q).rgb;
    return mix(mix(d,c,weight.x),mix(b,a,weight.x),weight.y);
}
void fragment() {
    vec3 weights = pow(abs(normalize(world_normal)),vec3(8.0));
    weights /= max(weights.x+weights.y+weights.z,0.001);
    vec2 top_coordinates = roof_tiles ? world_position.zx : world_position.xz;
    ALBEDO = periodic_color(world_position.zy*scale)*weights.x
           + periodic_color(top_coordinates*scale)*weights.y
           + periodic_color(world_position.xy*scale)*weights.z;
    ROUGHNESS = 0.92;
    if (earth_edge) { ALPHA = smoothstep(0.0,0.12,UV.y)*(1.0-smoothstep(0.88,1.0,UV.y)); }
}
"""
	if kind!="earth-road": shader.code=shader.code.replace("if (earth_edge) { ALPHA = smoothstep(0.0,0.12,UV.y)*(1.0-smoothstep(0.88,1.0,UV.y)); }","")
	var result := ShaderMaterial.new()
	result.shader = shader
	result.set_shader_parameter("color_texture",texture)
	result.set_shader_parameter("roof_tiles",kind=="roof")
	result.set_shader_parameter("earth_edge",kind=="earth-road")
	result.set_shader_parameter("scale",0.22 if kind=="stone" else (0.38 if kind=="wood" else 0.3))
	materials[kind] = result
	return result

static func apply_building(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node
		var kind := str(mesh.get_meta("material_kind",""))
		if not kind.is_empty():
			var material := surface(kind)
			if material != null: mesh.material_override = material
	for child in node.get_children(): apply_building(child)
