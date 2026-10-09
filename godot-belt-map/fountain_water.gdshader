shader_type canvas_item;
uniform float water_time = 0.0;
float water_mask(vec3 c) {
	return smoothstep(0.02, 0.16, min(c.g-c.r, c.b-c.r)) * smoothstep(0.23, 0.6, c.b);
}
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float mask = water_mask(base.rgb) * base.a;
	// Animate only cool-colored water. Warm stone, gold and vegetation stay fixed.
	float flow = sin(UV.y*310.0-water_time*15.0 + sin(UV.x*120.0)*1.8);
	float sparkle = pow(max(0.0, sin(UV.x*420.0+water_time*4.0)*sin(UV.y*270.0-water_time*7.0)), 8.0);
	vec3 color = base.rgb * (1.0 + mask*flow*0.15);
	color = mix(color, vec3(0.88, 0.98, 1.0), mask*sparkle*0.55);
	COLOR = vec4(color, base.a);
}
