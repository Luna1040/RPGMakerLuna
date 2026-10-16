extends Node2D
# Two GPU batches replace hundreds of individual circle/line draw commands.
var combat
var enemies_batch: MultiMeshInstance2D
var friendly_batch: MultiMeshInstance2D
const LIMIT:=240
func make_batch() -> MultiMeshInstance2D:
 var node:=MultiMeshInstance2D.new()
 var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_2D;mm.use_colors=true
 var quad:=QuadMesh.new();quad.size=Vector2.ONE;mm.mesh=quad
 mm.instance_count=LIMIT;mm.visible_instance_count=0;node.multimesh=mm
 var gradient:=Gradient.new();gradient.offsets=PackedFloat32Array([0,.25,.65,.82,1])
 gradient.colors=PackedColorArray([Color.WHITE,Color.WHITE,Color(.9,.9,.9),Color(.1,.1,.15),Color(0,0,0,0)])
 var texture:=GradientTexture2D.new();texture.gradient=gradient;texture.width=32;texture.height=32
 texture.fill=GradientTexture2D.FILL_RADIAL;texture.fill_from=Vector2(.5,.5);texture.fill_to=Vector2(1,.5)
 node.texture=texture;add_child(node);return node
func _ready() -> void:
 enemies_batch=make_batch();friendly_batch=make_batch()
func _process(_dt: float) -> void:
 visible=combat!=null and combat.game.mode=="flight" and not combat.choice
 if not visible:return
 var count:=mini(LIMIT,combat.bullets.size());enemies_batch.multimesh.visible_instance_count=count
 for i in count:
  var b: Dictionary=combat.bullets[i]
  enemies_batch.multimesh.set_instance_transform_2d(i,Transform2D(0,Vector2(18,18),0,b.p))
  enemies_batch.multimesh.set_instance_color(i,[Color("ff7e94"),Color("ffcc71"),Color("e997ff")][b.kind])
 count=mini(LIMIT,combat.shots.size());friendly_batch.multimesh.visible_instance_count=count
 for i in count:
  var s: Dictionary=combat.shots[i]
  friendly_batch.multimesh.set_instance_transform_2d(i,Transform2D(Vector2(s.v).angle(),Vector2(52 if s.kind==1 else 24,10)*float(s.get("size",1)),0,s.p))
  friendly_batch.multimesh.set_instance_color(i,(Color("86cfff") if combat.stacks("frost")>0 else combat.COLORS[s.kind]))
