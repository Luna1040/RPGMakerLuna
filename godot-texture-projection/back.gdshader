shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D original : source_color, filter_nearest, repeat_disable;
void fragment() {
    if (texture(original,UV).a < 0.5) discard;
    ALBEDO = vec3(0.055,0.12,0.25);
}
