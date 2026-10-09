shader_type canvas_item;
uniform vec4 ink : source_color = vec4(0.035,0.045,0.07,1.0);
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 p = TEXTURE_PIXEL_SIZE;
	float adjacent = max(max(texture(TEXTURE,UV+vec2(p.x,0)).a,texture(TEXTURE,UV-vec2(p.x,0)).a),max(texture(TEXTURE,UV+vec2(0,p.y)).a,texture(TEXTURE,UV-vec2(0,p.y)).a));
	COLOR = source.a < 0.5 && adjacent > 0.5 ? ink : source;
}
