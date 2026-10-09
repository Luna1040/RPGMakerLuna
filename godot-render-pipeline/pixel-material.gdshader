shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_color : source_color = vec4(0.8,0.6,0.4,1.0);
varying vec3 world_normal;
void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	float illumination = dot(normalize(world_normal),normalize(vec3(-0.35,0.75,0.65)));
	float level = illumination > 0.45 ? 1.0 : (illumination > -0.2 ? 0.73 : 0.48);
	ALBEDO = base_color.rgb * level;
}
