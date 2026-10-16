shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D scene_color : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D reflection_tex : filter_linear_mipmap;
uniform mat4 reflection_view;
uniform mat4 reflection_projection;
varying vec3 world_pos;
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
 vec2 p=world_pos.xz;
 float a=sin(p.x*2.8+p.y*1.3+TIME*0.62);
 float b=cos(p.y*3.2-p.x*0.7-TIME*0.47);
 float detail=sin(p.x*11.0+p.y*7.0+TIME*0.75)*0.13;
 vec2 ripple=vec2(a+detail,b-detail);
 vec3 nw=normalize(vec3(ripple.x*0.014,1.0,ripple.y*0.014));
 vec3 nv=normalize((VIEW_MATRIX*vec4(nw,0.0)).xyz);
 float fresnel=0.08+0.78*pow(1.0-max(dot(nv,normalize(VIEW)),0.0),4.0);
 vec3 below=textureLod(scene_color,clamp(SCREEN_UV+ripple*0.0014,vec2(0.002),vec2(0.998)),0.0).rgb;
 vec4 projected=reflection_projection*reflection_view*vec4(world_pos,1.0);
 vec2 ruv=projected.xy/projected.w*0.5+0.5;
 ruv.y=1.0-ruv.y;
 vec3 reflection=textureLod(reflection_tex,clamp(ruv+ripple*0.0010,vec2(0.002),vec2(0.998)),0.5).rgb;
 vec3 turquoise=mix(below*vec3(0.60,0.92,0.80),vec3(0.035,0.23,0.18),0.13);
 ALBEDO=mix(turquoise,reflection,fresnel);
}
