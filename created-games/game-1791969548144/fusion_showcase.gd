extends Control
signal finished
var main_pet: Dictionary={}
var secondary_pet: Dictionary={}
var main_actor: Node
var secondary_actor: Node
var circle: Texture2D
var circle_layer: TextureRect
var foreground: Node2D
var phase:="review"
var clock:=0.0
var old_star:=0
var old_xp:=0
var font: Font=preload("res://font.ttf")

func _ready() -> void:
 custom_minimum_size=Vector2(760,390)
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 circle=load("res://assets/client_fusion/compose1bg.dds")
 circle_layer=TextureRect.new()
 circle_layer.texture=circle
 circle_layer.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 circle_layer.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 circle_layer.size=Vector2(360,360)
 circle_layer.pivot_offset=Vector2(180,180)
 circle_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
 circle_layer.z_index=0
 var additive=CanvasItemMaterial.new()
 additive.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
 circle_layer.material=additive
 circle_layer.modulate=Color(1,1,1,0.65)
 add_child(circle_layer)
 foreground=Node2D.new()
 foreground.z_index=1
 foreground.draw.connect(draw_foreground)
 add_child(foreground)

func prepare(main: Dictionary, secondary: Dictionary={}) -> void:
 for actor in [main_actor,secondary_actor]:
  if is_instance_valid(actor):
   remove_child(actor)
   actor.queue_free()
 main_pet=main.duplicate(true)
 secondary_pet=secondary.duplicate(true)
 old_star=int(main.get("star",0))
 old_xp=int(main.get("star_xp",0))
 phase="review"
 clock=0
 main_actor=load("res://native_client_actor.gd").new()
 add_child(main_actor)
 main_actor.setup("petwarrior" if main.type_id==1071020 else "petmage")
 secondary_actor=null
 if not secondary.is_empty():
  secondary_actor=load("res://native_client_actor.gd").new()
  add_child(secondary_actor)
  secondary_actor.setup("petwarrior" if secondary.type_id==1071020 else "petmage")
 queue_redraw()
 if foreground!=null: foreground.queue_redraw()

func begin_result(main: Dictionary) -> void:
 main_pet=main.duplicate(true)
 phase="channel"
 clock=0
 if is_instance_valid(main_actor): main_actor.play_attack(Vector2.ZERO)
 queue_redraw()
 if foreground!=null: foreground.queue_redraw()

func _process(dt: float) -> void:
 clock+=dt
 if circle_layer!=null:
  circle_layer.position=Vector2(size.x/2-180,10)
  circle_layer.rotation=clock*0.07
 if phase=="channel" and clock>=1.8:
  phase="result"
  finished.emit()
 queue_redraw()
 if foreground!=null: foreground.queue_redraw()

func caption(point: Vector2,value: String,size_px: int,color: Color=Color("ffe4ad")) -> void:
 foreground.draw_string(font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func draw_model(actor: Node, center: Vector2, alpha: float=1.0) -> void:
 if not is_instance_valid(actor): return
 var extent:=Vector2(260,260)
 foreground.draw_texture_rect(actor.texture(),Rect2(center-actor.foot_anchor/256*extent,extent),false,Color(1,1,1,alpha))

func _draw() -> void:
 draw_style_box(make_style(),Rect2(Vector2.ZERO,size))

func draw_foreground() -> void:
 var center:=Vector2(size.x/2,190)
 if main_pet.is_empty(): return
 var progress:=clampf(clock/1.8,0,1) if phase=="channel" else (1.0 if phase=="result" else 0.0)
 var main_pos:=Vector2(size.x*0.31,245).lerp(Vector2(size.x/2,245),progress)
 var secondary_pos:=Vector2(size.x*0.72,245).lerp(Vector2(size.x/2,245),progress)
 if phase!="result": draw_model(secondary_actor,secondary_pos,1-progress)
 draw_model(main_actor,main_pos)
 if phase=="channel":
  for i in range(18):
   var angle:=TAU*i/18+clock*2
   var radius:=135*(1-progress)+25
   var point:=center+Vector2(cos(angle)*radius,sin(angle)*radius*0.5)
   foreground.draw_circle(point,2+sin(clock*8+i),Color(1,0.75,0.3,0.8))
  foreground.draw_arc(center,145,0,TAU*progress,72,Color("ffe9a0"),3)
 caption(Vector2(24,30),"幻兽幻化 · 主属性成长",22)
 if phase=="review":
  caption(Vector2(30,76),"主幻兽 #%d · Lv.%d · %d星" % [main_pet.id,main_pet.level,main_pet.star],16)
  caption(Vector2(size.x-285,76),"副幻兽 #%d · %d星（将消耗）" % [secondary_pet.id,secondary_pet.star] if not secondary_pet.is_empty() else "请在右侧选择副幻兽",16)
  caption(Vector2(30,320),"星级经验 %d / %d   →   增加 %d" % [old_xp,100*(old_star+1),40+int(secondary_pet.get("star",0))*20],18)
  caption(Vector2(30,351),"主幻兽保留；副幻兽可跨类型，消耗后无法恢复。",16,Color("d4d9df"))
 elif phase=="channel":
  caption(Vector2(30,335),"灵魂共鸣 · 能量汇聚…",21)
 else:
  caption(Vector2(30,310),"幻化成功"+(" · 星级提升！" if main_pet.star>old_star else " · 获得星级经验"),23)
  caption(Vector2(30,342),"%d星 → %d星    星经验 %d / %d    成长 +%d%%" % [old_star,main_pet.star,main_pet.star_xp,100*(int(main_pet.star)+1),main_pet.star*8],18)
  caption(Vector2(30,370),"生命上限 %d · %s" % [main_pet.max,"幻化结果已保存" if get_meta("saved",false) else "请手动保存进度"],15,Color("a9deb7"))

func make_style() -> StyleBoxFlat:
 var style=StyleBoxFlat.new()
 style.bg_color=Color("111a26")
 style.border_color=Color("bc8248")
 style.set_border_width_all(1)
 style.set_corner_radius_all(12)
 return style
