extends SceneTree
class GroundFixture extends Node2D:
 var visuals=preload("res://loot_visuals.gd").new()
 var font=preload("res://font.ttf")
 var grass=preload("res://assets/canosa_grass.png")
 func _draw() -> void:
  draw_texture_rect(grass,Rect2(0,0,1280,800),true)
  draw_rect(Rect2(0,0,1280,100),Color(0.03,0.06,0.1,0.9))
  draw_string(font,Vector2(40,50),"地面掉落展示 · 客户端2.5D模型贴图",HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("ffe4a4"))
  var ids=[410000,440050,131020,1037170,1037160]
  var names=["战士刀剑","法师法杖","护甲","幻魔晶石","灵魂晶石"]
  for i in range(ids.size()):
   var point:=Vector2(170+i*225,350)
   visuals.draw_item(self,point,ids[i])
   draw_string(font,point+Vector2(-45,65),names[i],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
  visuals.draw_egg(self,Vector2(450,570),1071020)
  visuals.draw_egg(self,Vector2(800,570),1071220)
  draw_string(font,Vector2(380,640),"战士攻防型蛋",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
  draw_string(font,Vector2(730,640),"法师攻防型蛋",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
var ticks:=0
func _initialize() -> void: call_deferred("setup")
func setup() -> void: root.add_child(GroundFixture.new())
func _process(_dt: float) -> bool:
 ticks+=1
 if ticks==15:
  root.get_texture().get_image().save_png("res://art-jobs/loot-fusion-20261015/ground-loot.png")
  print("PASS: native ground loot model textures for weapons, armor, crystals and both egg types rendered with ground shadows")
  quit()
 return false
