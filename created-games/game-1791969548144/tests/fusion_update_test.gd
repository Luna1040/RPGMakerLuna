extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var g=load("res://canosa.gd").new()
 g.new_run()
 assert(g.EGG_DROP_CHANCE==0.5)
 seed(314159)
 var enemy: Dictionary=g.enemies[0]
 for i in range(10000):
  enemy.hp=1
  g.damage(enemy,2)
 assert(g.egg_drops.size()>4800 and g.egg_drops.size()<5200)
 print("Egg drops /10000: ",g.egg_drops.size())
 g.new_run()
 g.pets[0].star=12
 g.pets[0].level=34
 assert(g.pet_overhead_text(g.pets[0])=="Lv.34 · 12星")
 g.pets[0].star=0
 g.pets[0].star_xp=80
 g.pets.append(g.pet_collection.make_pet(1071020))
 var ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(g)
 ui.toggle(1)
 var collection=ui.content.get_child(1)
 collection.pending_main=g.pets[0].id
 collection.pending_secondary=g.pets[2].id
 collection.showcase.prepare(g.pets[0],g.pets[2])
 collection.confirm.canceled.emit()
 assert(g.pets.size()==3 and g.pets[0].star_xp==80)
 collection.confirm.confirmed.emit()
 assert(g.pets.size()==2 and g.pets[0].star==1 and g.pets[0].star_xp==20)
 collection.confirm.confirmed.emit()
 assert(g.pets.size()==2 and g.pets[0].star_xp==20)
 collection.showcase._process(2)
 assert(collection.fusion_done and not collection.fusion_busy)
 collection.confirm.confirmed.emit()
 assert(not collection.confirm.visible and g.pets[0].star_xp==20)
 ui.free()
 g.free()
 print("PASS: 50 percent drop configuration and distribution, level/star overhead text, fusion cancellation, native scene/model setup, exactly-once consumption, busy phase and result close")
 quit()
