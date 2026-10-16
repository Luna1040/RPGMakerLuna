extends SceneTree

func _initialize() -> void:
 call_deferred("run")

func key(code: int) -> InputEventKey:
 var event=InputEventKey.new()
 event.pressed=true
 event.keycode=code
 return event

func run() -> void:
 var g=load("res://canosa.gd").new()
 g.new_run()
 var ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(g)
 g.player_ui=ui
 assert(ui.menu_buttons.size()==6)
 for button in ui.menu_buttons: assert(button.icon!=null)
 ui.handle_key(key(KEY_C))
 assert(ui.opened==0 and ui.equipment_grid.get_child_count()==8)
 ui.handle_key(key(KEY_H))
 assert(ui.opened==1 and g.pets.size()==2)
 ui.handle_key(key(KEY_TAB))
 assert(ui.opened==2 and ui.bag_grid.get_child_count()==40)
 var before: Vector2=g.hero
 g.navigate(before+Vector2(300,0))
 g._process(1)
 assert(g.hero==before,"Panels must prevent world click-through/movement")
 ui.handle_key(key(KEY_Q))
 assert(ui.opened==3 and ui.task_tabs.get_tab_count()==3 and g.skill_cd==0)
 assert(ui.task_text("可接任务").contains(g.npcs[0].name))
 g.quest=2
 assert(ui.task_text("已完成任务").contains(g.npcs[1].name))
 ui.handle_key(key(KEY_K))
 assert(ui.opened==4 and ui.content.get_child_count()==2)
 ui.handle_key(key(KEY_ESCAPE))
 assert(ui.opened==-1)
 ui.handle_key(key(KEY_ESCAPE))
 assert(ui.opened==5)
 assert(ui.content.get_child_count()>=8)
 g.gold=1234
 g.master_volume=37
 g.show_nameplates=false
 var data: Dictionary=g.snapshot()
 assert(data.gold==1234 and data.master_volume==37 and not data.show_nameplates)
 ui.close()
 g.hero=Vector2(3500,1800)
 g.enemies[0].pos=g.hero
 g.damage(g.enemies[0],1000)
 assert(g.gold>1234)
 g.new_run()
 assert(g.gold==0 and ui.opened==-1)
 ui.free()
 g.player_ui=null
 g.free()
 print("PASS: six icons, shortcuts, eight equipment slots, two pets, forty bag slots, task categories, empty skills, settings, modal freeze, gold persistence")
 quit()
