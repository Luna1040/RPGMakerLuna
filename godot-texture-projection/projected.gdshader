shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D original : source_color, filter_nearest, repeat_disable;
uniform mat4 rest_transform;
uniform vec3 projection_right;
uniform bool cut_background = true;
varying vec2 source_uv;
void vertex() {
    vec3 rest = (rest_transform * vec4(VERTEX, 1.0)).xyz;
    source_uv = vec2(0.45 + dot(rest, projection_right) / 2.3, 0.975 - rest.y / 2.3);
}
void fragment() {
    vec4 tex = texture(original, source_uv);
    bool outside = any(lessThan(source_uv, vec2(0.0))) || any(greaterThan(source_uv, vec2(1.0)));
    if (cut_background && (outside || tex.a < 0.5)) discard;
    ALBEDO = (outside || tex.a < 0.5) ? vec3(0.12,0.19,0.31) : tex.rgb;
}
