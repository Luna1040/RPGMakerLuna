extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var system=load("res://pet_collection.gd").new()
 system.reset()
 assert(system.eggs.size()==50 and system.incubators.size()==50)
 for slot in range(50):
  assert(system.duration(slot)==(1 if slot<10 else (60 if slot<20 else (3600 if slot<30 else 43200))))
  assert(system.add_egg(1071020))
 assert(not system.add_egg(1071220))
 for slot in range(50): assert(system.incubate(slot,slot,1000))
 assert(system.eggs.count(null)==50)
 assert(not system.incubate(0,0,1001))
 var pets: Array=[]
 assert(not system.extract_pet(0,1000,pets))
 assert(system.extract_pet(0,1001,pets))
 assert(not system.extract_pet(0,1001,pets))
 assert(not system.extract_pet(10,1059,pets))
 assert(system.extract_pet(10,1060,pets))
 assert(not system.extract_pet(20,4599,pets))
 assert(system.extract_pet(20,4600,pets))
 assert(not system.extract_pet(30,44199,pets))
 assert(system.extract_pet(30,44200,pets))
 while pets.size()<50: pets.append(system.make_pet(1071020))
 assert(not system.extract_pet(1,44200,pets) and system.incubators[1]!=null)
 pets[49].deployed=true
 assert(system.sorted_indices(pets)[0]==49)
 var main_id: int=pets[49].id
 assert(not system.fuse(pets,main_id,main_id))
 pets[0].type_id=1071220
 pets[0].deployed=true
 assert(not system.fuse(pets,main_id,pets[0].id))
 pets[1].deployed=true
 assert(not system.fuse(pets,main_id,pets[1].id))
 for i in range(3): assert(system.fuse(pets,main_id,pets[2].id))
 var main: Dictionary=pets.back()
 assert(main.star==1 and main.star_xp==20 and is_equal_approx(main.max,86.4))
 assert(system.extract_pet(1,44200,pets))
 var encoded:=JSON.stringify(system.snapshot())
 var restored=load("res://pet_collection.gd").new()
 restored.restore(JSON.parse_string(encoded),pets)
 assert(restored.incubators[31].ready_at==44200)
 var g=load("res://canosa.gd").new()
 g.new_run()
 for i in range(50): assert(g.pet_collection.add_egg(1071220))
 g.egg_drops.append({"type_id":1071020,"pos":g.hero})
 assert(not g.pickup_egg(0) and g.egg_drops.size()==1)
 g.pet_collection.eggs[0]=null
 assert(g.pickup_egg(0) and g.egg_drops.is_empty())
 g.pets.append(g.pet_collection.make_pet(1071220))
 g.toggle_pet(2)
 assert(not g.pets[2].deployed)
 g.toggle_pet(0)
 g.toggle_pet(2)
 assert(g.pets[2].deployed and g.pets[2].role=="attack")
 var enemy: Dictionary=g.enemies[0]
 g.damage(enemy,9999)
 var count: int=g.kills
 g.damage(enemy,9999)
 assert(g.kills==count)
 seed(271828)
 g.egg_drops.clear()
 for i in range(100):
  enemy.hp=1
  g.damage(enemy,9999)
 assert(g.egg_drops.size()>0 and g.egg_drops.size()<100)
 var types: Array=[]
 for drop in g.egg_drops:
  assert(drop.type_id in [1071020,1071220])
  if not drop.type_id in types: types.append(drop.type_id)
 assert(types.size()==2)
 var data: Dictionary=g.snapshot()
 assert(data.pet_collection.eggs.size()==50 and data.pets.size()==3)
 g.new_run()
 assert(g.pets.size()==2 and g.pet_collection.eggs.count(null)==50)
 g.free()
 print("PASS: 50 eggs, 50 timed incubation slots, 50 pets, offline deadlines, extraction capacity, deployed sorting, safe fusion and star growth, pickup capacity, deploy limit, kill deduplication, fresh character isolation")
 quit()
