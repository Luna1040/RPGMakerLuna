extends RefCounted
static func ground(road: bool=false) -> ShaderMaterial:
 var shader:=Shader.new()
 shader.code="""shader_type spatial;
 render_mode cull_disabled;
 uniform sampler2D base_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
 uniform sampler2D alternate_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
 uniform sampler2D dry_tex:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
 varying vec3 p;
 float hash(vec2 q){return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);}
 float noise(vec2 q){vec2 i=floor(q);vec2 f=fract(q);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
 void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
 void fragment(){
  vec2 uv=p.xz*0.4;
  float patch=smoothstep(0.25,0.8,noise(p.xz*0.055));
  vec3 green=mix(texture(base_tex,uv).rgb,texture(alternate_tex,uv*0.91+0.37).rgb,patch);
  ALBEDO=mix(green,texture(dry_tex,uv*0.85).rgb,smoothstep(0.4,0.85,noise(p.zx*0.08+10.0))*0.42);
  ROUGHNESS=0.98;
  FEATHER
 }
 """
 shader.code=shader.code.replace("FEATHER","ALPHA=1.0-smoothstep(0.55,0.98,abs(UV.y-0.5)*2.0+(noise(p.xz*0.8)-0.5)*0.18);" if road else "")
 var material:=ShaderMaterial.new()
 material.shader=shader
 material.set_shader_parameter("base_tex",load("res://assets/client-wild/soil.png" if road else "res://assets/client-wild/lightgrass.png"))
 material.set_shader_parameter("alternate_tex",load("res://assets/client-wild/soil.png" if road else "res://assets/client-skills/alightgrass.png"))
 material.set_shader_parameter("dry_tex",load("res://assets/client-wild/soil.png" if road else "res://assets/client-skills/alightgrass02.png"))
 return material
