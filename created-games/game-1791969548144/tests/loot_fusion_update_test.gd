extends SceneTree
const FIXTURE="res://tests/loot-fusion-fixture.json"
func _initialize() -> void: call_deferred("run")
func find_button(node: Node, caption: String) -> Button:
 if node is Button and node.text==caption: return node
 for child in node.get_children():
  var result:=find_button(child,caption)
  if result!=null: return result
 return null
func run() -> void:
 var g=load("res://canosa.gd").new()
 g.new_run()
 var enemy: Dictionary=g.enemies[0]
 for i in range(3):
  enemy.hp=1
  g.damage(enemy,2)
 assert(g.level==2 and g.combat_xp==20)
 assert(g.pets[0].level==2 and g.pets[0].exp==20)
 for i in range(2):
  enemy.hp=1
  g.damage(enemy,2)
 assert(g.level==3 and g.combat_xp==0)
 assert(g.snapshot().combat_xp==0)
 assert(g.PHANTOM_DROP_CHANCE==0.3 and g.SOUL_DROP_CHANCE==0.1)
 g.new_run()
 enemy=g.enemies[0]
 seed(90210)
 for i in range(1000):
  enemy.hp=1
  g.damage(enemy,2)
 var phantom:=0
 var soul:=0
 for drop in g.item_drops:
  if drop.id==1037170: phantom+=1
  if drop.id==1037160: soul+=1
 assert(phantom>240 and phantom<360 and soul>70 and soul<130)
 print("Crystal drops /1000: ",phantom," / ",soul)
 for path in g.loot_visuals.mapping.values(): assert(ResourceLoader.exists(path))
 assert(ResourceLoader.exists("res://assets/client_loot/egg1.dds"))
 g.new_run()
 g.pets.append(g.pet_collection.make_pet(1071020))
 g.pets.append(g.pet_collection.make_pet(1071020))
 g.pets[3].star=1
 g.pets.append(g.pet_collection.make_pet(1071220))
 var ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(g)
 ui.toggle(1)
 var collection=ui.content.get_child(1)
 find_button(collection,"幻化").pressed.emit()
 assert(collection.confirm.visible and collection.pending_main==g.pets[0].id)
 assert(collection.secondary_ids.size()==3 and collection.candidate_list.get_child_count()==3)
 assert(collection.pending_secondary==-1 and collection.confirm.get_ok_button().disabled)
 collection.select_secondary(g.pets[1].id)
 assert(collection.pending_secondary==-1)
 collection.select_secondary(g.pets[4].id)
 assert(collection.pending_secondary==g.pets[4].id)
 collection.open_fusion(g.pets[0].id)
 collection.select_secondary(g.pets[3].id)
 assert(collection.star_warning.visible and collection.pending_secondary==-1)
 assert(collection.star_warning.dialog_text.contains("1星"))
 collection.star_warning.get_cancel_button().pressed.emit()
 assert(collection.pending_secondary==-1 and g.pets.size()==5)
 collection.select_secondary(g.pets[3].id)
 collection.star_warning.get_ok_button().pressed.emit()
 assert(collection.pending_secondary==g.pets[3].id and not collection.confirm.get_ok_button().disabled)
 collection.confirm_fusion()
 assert(g.pets.size()==4 and g.pets[0].star_xp==60)
 collection.confirm_fusion()
 assert(g.pets.size()==4)
 ui.free()
 g.save_store.path=FIXTURE
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 assert(g.create_character(0,"经验测试","战士"))
 enemy=g.enemies[0]
 enemy.hp=1
 g.damage(enemy,2)
 assert(g.combat_xp==40 and g.save_progress())
 assert(g.load_character(0) and g.combat_xp==40)
 var data: Dictionary=g.snapshot()
 data.erase("combat_xp")
 data.kills=7
 assert(g.save_store.save_character(0,data,false,1704067200))
 assert(g.load_character(0) and g.combat_xp==40)
 g.free()
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 print("PASS: double character/pet kill XP, carry and legacy save migration, increased crystal rates, native ground resources, direct fusion button, visual eligible cards, deployed/type exclusion, 1-star cancel/accept warning, exact-once consumption")
 quit()
