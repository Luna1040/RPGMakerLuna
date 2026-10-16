extends SceneTree

func _initialize() -> void:
 var g=load("res://canosa.gd").new()
 g.new_run()
 g.load_walk()
 assert(g.walk_frames.size()==12)
 g.hero+=Vector2(10,0)
 g.update_walk(g.hero-Vector2(10,0),0.1)
 assert(g.walking and not g.facing_left and g.walk_clock>0)
 g.update_walk(g.hero+Vector2(10,0),0.1)
 assert(g.walking and g.facing_left)
 g.update_walk(g.hero,0.1)
 assert(not g.walking and g.walk_clock==0)
 g.hero=g.npcs[0].pos
 g.talk()
 assert(g.dialog_npc==0 and g.quest==0)
 var before: Vector2=g.hero
 g.navigate(g.hero+Vector2(500,0))
 g._process(1)
 assert(g.hero==before,"Dialogue must freeze movement")
 var event:=InputEventMouseButton.new()
 event.button_index=MOUSE_BUTTON_LEFT
 event.pressed=true
 event.position=g.dialog_button_rect(1).get_center()
 g._unhandled_input(event)
 assert(g.dialog_text.contains("安全区") and g.quest==0)
 event.position=g.dialog_button_rect(0).get_center()
 g._unhandled_input(event)
 assert(g.quest==1 and g.level==2)
 g._unhandled_input(event)
 assert(g.level==2,"Repeated option must not duplicate reward")
 event.position=g.dialog_button_rect(2).get_center()
 g._unhandled_input(event)
 assert(g.dialog_npc==-1 and g.route.is_empty())
 g.talk()
 var key:=InputEventKey.new()
 key.pressed=true
 key.keycode=KEY_ESCAPE
 g._unhandled_input(key)
 assert(g.dialog_npc==-1 and g.state=="play")
 g.new_run()
 assert(not g.walking and not g.facing_left and g.dialog_npc==-1)
 g.free()
 print("PASS: walk frames, moving/idle/facing, modal freeze, mouse options, idempotent rewards, close, Escape, reset")
 quit()
