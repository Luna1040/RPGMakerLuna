extends SceneTree
const FIXTURE="res://tests/pet-collection-fixture.json"
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 var g=load("res://canosa.gd").new()
 g.save_store.path=FIXTURE
 assert(g.create_character(0,"幻兽收藏者","法师"))
 var ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(g)
 g.player_ui=ui
 ui.toggle(1)
 var collection=ui.content.get_child(1)
 assert(collection.countdowns.size()==50)
 assert(g.pet_collection.add_egg(1071220))
 collection.selected_egg=0
 collection.incubator_clicked(0)
 assert(g.pet_collection.eggs[0]==null and g.pet_collection.incubators[0]!=null)
 g.pet_collection.incubators[0].ready_at=int(Time.get_unix_time_from_system())-1
 collection.update_countdowns()
 assert(collection.countdowns[0].button.text=="提取")
 collection.incubator_clicked(0)
 assert(g.pets.size()==3 and not g.pets[2].deployed)
 var main_id: int=g.pets[0].id
 collection.selected_main=main_id
 collection.rebuild()
 assert(collection.secondary_ids.size()==1)
 collection.pending_main=main_id
 collection.pending_secondary=g.pets[2].id
 collection.confirm.confirmed.emit()
 assert(g.pets.size()==2 and g.pets[0].star_xp==40)
 # Persist an expanded roster with a removed ID, star growth and a future deadline.
 for i in range(8): g.pets.append(g.pet_collection.make_pet(1071020 if i%2==0 else 1071220))
 g.pets[0].star=3
 g.pets[0].max=g.pets[0].base_max*1.24
 g.pets[0].star_xp=72
 assert(g.pet_collection.add_egg(1071020))
 assert(g.pet_collection.incubate(0,49,1000000000))
 var ids: Array=[]
 for pet in g.pets: ids.append(pet.id)
 assert(g.save_progress(true))
 ui.close()
 assert(g.load_character(0))
 assert(g.pets.size()==10 and g.pets[0].star==3 and g.pets[0].star_xp==72)
 assert(is_equal_approx(g.pets[0].max,99.2))
 assert(g.pet_collection.incubators[49].ready_at==1000043200)
 for i in range(10): assert(g.pets[i].id==ids[i])
 ui.toggle(1)
 collection=ui.content.get_child(1)
 collection.page=9
 collection.rebuild()
 assert(collection.page==9 and collection.countdowns.size()==50)
 g.player_ui=null
 ui.free()
 g.free()
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 print("PASS: panel incubation/extract/fusion callbacks, ten pages, stable IDs, expanded roster, star stats and offline incubation save roundtrip; real player saves untouched")
 quit()
