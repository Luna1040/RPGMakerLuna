extends SceneTree

func _initialize() -> void:
 var g = load("res://canosa.gd").new()
 g.new_run()
 assert(g.enemies.size()==36)
 for kind in range(3):
  var count := 0
  for e in g.enemies:
   if e.kind==kind:
    count+=1
    assert(e.level==[1,5,7][kind] and e.pos.x>g.WALL_X)
  assert(count==12)
 assert(g.move_allowed(Vector2(2770,1800),Vector2(2830,1800)).x>2800)
 for i in range(5):
  g.hero = g.npcs[i].pos
  var key := InputEventKey.new()
  key.keycode = KEY_F
  key.pressed = true
  g._unhandled_input(key)
  assert(g.dialog_npc==i)
  g.choose_dialog(0)
  g.close_dialog()
 assert(g.level==5 and g.quest==5)
 g.hero = g.npcs[4].pos
 g.talk()
 g.choose_dialog(0)
 g.close_dialog()
 assert(g.level==5, "Rewards must be idempotent")
 assert(g.move_allowed(Vector2(2770,1800),Vector2(2830,1800)).x>2800)
 assert(g.move_allowed(Vector2(2770,500),Vector2(2830,500)).x<2800)
 g.hero = g.SPAWN
 g.enemies[0].pos = g.hero
 g.enemies[0].aggro = true
 g._process(0.1)
 assert(g.hp==180 and not g.enemies[0].aggro)
 g.enemies[0].pos = g.enemies[0].spawn
 g.hero = g.enemies[0].pos+Vector2(80,0)
 g._process(0.1)
 assert(not g.enemies[0].aggro, "Passive creature must not initiate combat")
 g.damage(g.enemies[0],1)
 assert(g.enemies[0].aggro)
 g.hero = g.enemies[12].pos+Vector2(100,0)
 g._process(0.1)
 assert(g.enemies[12].aggro)
 g.damage(g.enemies[0],1000)
 assert(g.enemies[0].hp<=0 and g.defeated[0]==1)
 g.hero = g.SPAWN
 g._process(19)
 assert(g.enemies[0].hp==g.enemies[0].max and not g.enemies[0].aggro)
 g.hero = g.SPAWN
 g._process(0.1)
 assert(g.hp==180)
 g.defeated = [3,3,3]
 g._process(0)
 assert(g.state=="play")
 g.new_run()
 g.hp = 0
 g._process(0)
 assert(g.state=="dead")
 g.new_run()
 assert(g.level==1 and g.quest==0 and g.hero==g.SPAWN and g.enemies.size()==36)
 g.free()
 print("PASS: 36 monsters, quest chain, idempotent rewards, level gate, walls, safe zone, passive/active AI, hunt completion keeps farming, death/restart")
 quit()
