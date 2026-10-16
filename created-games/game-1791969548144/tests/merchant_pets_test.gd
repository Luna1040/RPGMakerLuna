extends SceneTree
const FIXTURE="res://tests/merchant-pets-fixture.json"
func _initialize() -> void: call_deferred("run")
func first_grid(node: Node) -> GridContainer:
 if node is GridContainer: return node
 for child in node.get_children():
  var result:=first_grid(child)
  if result!=null: return result
 return null
func run() -> void:
 var g=load("res://canosa.gd").new()
 g.new_run()
 var shop=load("res://merchant_system.gd").new()
 assert(not shop.buy(g,1071020))
 g.gold=1000
 assert(shop.buy(g,1071020) and g.gold==900)
 assert(g.pet_collection.auto_incubate(0,100))
 assert(g.pet_collection.incubators[0].ready_at==101)
 for i in range(50):
  if g.pet_collection.incubators[i]==null: g.pet_collection.incubators[i]={"type_id":1071020,"ready_at":1000}
 assert(g.pet_collection.add_egg(1071220))
 assert(not g.pet_collection.auto_incubate(0,100) and g.pet_collection.eggs[0]!=null)
 g.pet_collection.incubators[13]=null
 assert(g.pet_collection.auto_incubate(0,100) and g.pet_collection.incubators[13].ready_at==160)
 assert(shop.buy(g,1020010))
 assert(shop.buy(g,1020020))
 var before: Vector2=g.hero
 var random_slot:=-1
 for i in range(40):
  if g.equipment.bag[i]!=null and g.equipment.bag[i].id==1020020: random_slot=i
 assert(g.use_scroll(random_slot) and g.hero!=before)
 var return_slot:=-1
 for i in range(40):
  if g.equipment.bag[i]!=null and g.equipment.bag[i].id==1020010: return_slot=i
 assert(g.use_scroll(return_slot) and g.hero==g.map_spawn() and g.safe(g.hero))
 assert(g.equipment.add_item(410000))
 var item: Dictionary={}
 for value in g.equipment.bag:
  if value!=null and value.id==410000: item=value
 var old_gold: int=g.gold
 assert(shop.sell_item(g,item.uid) and g.gold>old_gold)
 assert(not shop.sell_item(g,item.uid))
 g.pets.append(g.pet_collection.make_pet(1071220))
 var secondary_id: int=g.pets.back().id
 assert(g.pet_collection.fuse(g.pets,g.pets[0].id,secondary_id))
 assert(not shop.sell_pet(g,g.pets[0].id))
 g.toggle_pet(0)
 assert(shop.sell_pet(g,g.pets[0].id))
 for q in range(8):
  var data={"quality":q}
  assert(g.equipment.quality_name(data)==["下品","中品","上品","精品","极品"][mini(q,4)])
 assert(g.equipment.target({"id":410003},"quality").id==410007)
 var ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(g)
 g.player_ui=ui
 g.dialog_npc=6
 assert(g.dialog_options()[1].contains("杂货"))
 g.choose_dialog(1)
 assert(ui.opened==7 and ui.content.get_child(1).tabs.get_tab_count()==3)
 ui.close()
 ui.toggle(1)
 var panel=ui.content.get_child(1)
 g.pet_collection.reset()
 g.pet_collection.add_egg(1071020)
 g.pet_collection.incubators[0]={"type_id":1071220,"ready_at":9999999999}
 panel.rebuild()
 var double_click=InputEventMouseButton.new()
 double_click.button_index=MOUSE_BUTTON_LEFT
 double_click.pressed=true
 double_click.double_click=true
 first_grid(panel).get_child(0).gui_input.emit(double_click)
 assert(g.pet_collection.eggs[0]==null and g.pet_collection.incubators[1]!=null)
 var id: int=g.pets[0].id
 panel.discard_id=id
 panel.discard_popup.confirmed.emit()
 assert(g.pets.is_empty())
 g.player_ui=null
 ui.free()
 g.save_store.path=FIXTURE
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 assert(g.save_store.create(0,"杂货测试","战士",1704067200))
 g.active_slot=0
 assert(g.save_progress())
 assert(g.load_character(0) and g.pets.is_empty())
 for region in [1000,2000]:
  g.client_map=load("res://client_canosa_map.gd" if region==1000 else "res://client_tree_city.gd").new()
  g.client_map.setup()
  g.current_region=region
  g.hero=g.map_spawn()
  for use_id in [1020020,1020010]:
   assert(g.equipment.add_item(use_id))
   var slot:=-1
   for i in range(40):
    if g.equipment.bag[i]!=null and g.equipment.bag[i].id==use_id: slot=i
   assert(g.use_scroll(slot))
   assert(g.client_map.clearance(g.hero))
   if use_id==1020010: assert(g.safe(g.hero))
 g.free()
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 print("PASS: merchant buy/sell gold, capacity-safe eggs, ordered incubation, random/return scroll, cross-type fusion, deployed pet protection, discard all pets and empty roster save, five quality colors, NPC merchant tabs")
 quit()
