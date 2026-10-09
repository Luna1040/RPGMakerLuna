shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D art : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float bend = 0.0;
void vertex() {
    // Tiny trailing bend for cloth/hair only; limbs use rigid joint transforms.
    VERTEX.x += bend * UV.y * UV.y;
}
void fragment() {
    vec4 pixel = texture(art, UV);
    if (pixel.a < 0.5) discard;
    ALBEDO = pixel.rgb * tint.rgb;
}
