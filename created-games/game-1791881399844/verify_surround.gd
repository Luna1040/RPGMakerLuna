extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func run() -> void:
 var g=load("res://main.tscn").instantiate();g.save_enabled=false;g.save_path="user://surround-test-unused.json"
 root.add_child(g);g.set_process(false);g.launch();g.hazards.clear()
 var c=g.combat;c.muted=true
 var bounds: Rect2=g.FIELD.grow(-40)
 for player in [Vector2(500,440),Vector2(50,170),Vector2(950,710),Vector2(70,440)]:
  g.player=player
  for edge in 4:
   c.entry_edges=[edge]
   var pos: Vector2=c.entry_position()
   check(pos.distance_to(player)>=220,"No close spawns at edges/corners")
   check((pos.x==bounds.position.x if edge==0 else pos.x==bounds.end.x if edge==1 else pos.y==bounds.position.y if edge==2 else pos.y==bounds.end.y),"Requested edge honored")
   c.enemies.clear();var e=c.spawn(0,pos);c.spawn_cd=999;c.fire_cd=999;e.fire=999
   var distance: float=pos.distance_to(g.player)
   c.step(.1)
   check(e.p.distance_to(g.player)<distance,"Enemy moves inward from every edge")
 g.player=Vector2(500,440);c.reset();c.fire_cd=999
 c.step(1.01)
 check(c.enemies.size()==6,"First wave contains six ships")
 c.enemies.clear();c.reset();c.fire_cd=999
 for i in 250:
  g.hit_cd=999;c.step(.1)
 check(c.enemies.size()==28,"Sustained waves fill the enemy budget")
 for i in 100:c.step(.1)
 check(c.enemies.size()<=28 and c.bullets.size()<=160,"Both budgets remain enforced")
 print("SURROUND TEST ","PASS" if failures==0 else "FAIL"," checks=",checks)
 g.free();quit(failures)
