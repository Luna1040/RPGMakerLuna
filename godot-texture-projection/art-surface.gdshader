shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D original : source_color, filter_nearest, repeat_disable;
uniform float deformation = 0.0;
uniform float clock = 0.0;
void vertex() {
    // UV stays attached to the source vertices. This is a deformation test,
    // not a rigged walk: the original image has no hidden limb artwork.
    float lower = smoothstep(0.66, 0.95, UV.y);
    float side = UV.x < 0.44 ? -1.0 : 1.0;
    VERTEX.x += deformation * sin(clock * 3.0) * lower * side * 0.11;
    VERTEX.y += deformation * max(0.0, side * sin(clock * 3.0)) * lower * 0.06;
}
void fragment() {
    vec4 tex = texture(original, UV);
    if (tex.a < 0.5) discard;
    ALBEDO = tex.rgb;
}
