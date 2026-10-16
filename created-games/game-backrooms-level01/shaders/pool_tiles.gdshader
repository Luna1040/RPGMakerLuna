shader_type spatial;
uniform vec4 tile_color : source_color = vec4(0.78,0.8,0.69,1.0);
uniform float tile_size = 0.18;
uniform vec2 cylinder_scale = vec2(0.0);
uniform float wetness = 0.0;
varying vec3 world_pos;
varying vec3 world_normal;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() {
 world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 if (CAMERA_POSITION_WORLD.y < 0.035 && world_pos.y < 0.04) { discard; }
 vec3 n=abs(world_normal);
 vec2 coord = n.y>0.5 ? world_pos.xz : (n.x>n.z ? world_pos.zy : world_pos.xy);
 if(cylinder_scale.x>0.0) { coord=UV*cylinder_scale; }
 vec2 grid=coord/tile_size;
 vec2 q=fract(grid);
 vec2 edge=min(q,1.0-q);
 float distance_to_edge=min(edge.x,edge.y);
 float aa=max(fwidth(grid.x),fwidth(grid.y));
 float tile=smoothstep(0.010,0.020+aa*0.35,distance_to_edge);
 float random=hash(floor(grid));
 vec3 ceramic=tile_color.rgb*(0.93+0.105*random);
 float grain=hash(floor(coord*650.0));
 ceramic*=0.985+grain*0.03;
 vec3 grout=tile_color.rgb*0.74;
 vec3 base=mix(grout,ceramic,tile);
 float submerged=1.0-smoothstep(-0.05,0.16,world_pos.y);
 base=mix(base,base*vec3(0.53,0.88,0.77),submerged*0.55);
 float waterline=exp(-abs(world_pos.y-0.045)*33.0);
 base*=1.0-waterline*0.14;
 ALBEDO=base;
 float bevel=(1.0-smoothstep(0.04,0.10,distance_to_edge))*tile;
 vec2 bevel_dir=vec2(edge.x<edge.y ? sign(q.x-0.5) : 0.0,edge.y<=edge.x ? sign(q.y-0.5) : 0.0);
 NORMAL_MAP=normalize(vec3(bevel_dir*bevel*0.09,1.0))*0.5+0.5;
 ROUGHNESS=mix(0.76,0.28+random*0.12,tile)-wetness*0.12;
 SPECULAR=0.48;
 float c1=sin(world_pos.x*4.3+sin(world_pos.z*3.1+TIME*0.45))+cos(world_pos.z*4.6+sin(world_pos.x*2.4-TIME*0.35));
 float c2=sin(world_pos.x*6.2-world_pos.z*2.2+TIME*0.6);
 float caustic=pow(max(0.0,1.0-abs(c1)*0.55),22.0)*0.6+pow(max(0.0,1.0-abs(c2)),32.0)*0.23;
 EMISSION=vec3(0.05,0.11,0.07)*caustic*submerged;
}
