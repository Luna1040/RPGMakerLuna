extends RefCounted
const CAPACITY=50
var eggs: Array=[]
var incubators: Array=[]
var serial:=1

func reset() -> void:
 eggs.resize(CAPACITY)
 eggs.fill(null)
 incubators.resize(CAPACITY)
 incubators.fill(null)
 serial=1

static func duration(slot: int) -> int:
 return 1 if slot<10 else (60 if slot<20 else (3600 if slot<30 else 43200))

func make_pet(type_id: int, deployed: bool=false, role: String="attack") -> Dictionary:
 var job:="战士" if type_id==1071020 else "法师"
 var base:=80.0 if role=="attack" else 120.0
 var result={"id":serial,"name":job+"攻防型","type_id":type_id,"profession":job,"role":role,"deployed":deployed,"level":1,"exp":0,"star":0,"star_xp":0,"base_max":base,"max":base,"hp":base,"pos":Vector2.ZERO}
 serial+=1
 return result

func add_egg(type_id: int) -> bool:
 var index=eggs.find(null)
 if index<0: return false
 eggs[index]={"type_id":type_id}
 return true

func incubate(egg_slot: int, slot: int, now: int) -> bool:
 if egg_slot<0 or egg_slot>=50 or slot<0 or slot>=50 or eggs[egg_slot]==null or incubators[slot]!=null: return false
 incubators[slot]={"type_id":eggs[egg_slot].type_id,"ready_at":now+duration(slot)}
 eggs[egg_slot]=null
 return true

func extract_pet(slot: int, now: int, pets: Array) -> bool:
 if slot<0 or slot>=50 or incubators[slot]==null or now<int(incubators[slot].ready_at) or pets.size()>=50: return false
 pets.append(make_pet(int(incubators[slot].type_id)))
 incubators[slot]=null
 return true

static func threshold(pet: Dictionary) -> int:
 return 100*(int(pet.get("star",0))+1)

static func growth(pet: Dictionary) -> float:
 return 1.0+0.08*int(pet.get("star",0))

func fuse(pets: Array, main_id: int, secondary_id: int) -> bool:
 var main_index:=-1
 var secondary_index:=-1
 for i in range(pets.size()):
  if int(pets[i].id)==main_id: main_index=i
  if int(pets[i].id)==secondary_id: secondary_index=i
 if main_index<0 or secondary_index<0 or main_index==secondary_index: return false
 var main: Dictionary=pets[main_index]
 var secondary: Dictionary=pets[secondary_index]
 if secondary.deployed: return false
 main.star_xp+=40+int(secondary.star)*20
 while main.star_xp>=threshold(main):
  main.star_xp-=threshold(main)
  main.star+=1
 var previous_max: float=main.max
 main.max=float(main.base_max)*growth(main)
 main.hp=minf(main.max,float(main.hp)+main.max-previous_max)
 pets.remove_at(secondary_index)
 return true

func sorted_indices(pets: Array) -> Array:
 var indices: Array=[]
 for i in range(pets.size()): indices.append(i)
 indices.sort_custom(func(a,b):
  if pets[a].deployed!=pets[b].deployed: return pets[a].deployed
  return int(pets[a].id)<int(pets[b].id)
 )
 return indices

func snapshot() -> Dictionary:
 return {"version":1,"eggs":eggs.duplicate(true),"incubators":incubators.duplicate(true),"serial":serial}

func restore(data: Dictionary, pets: Array) -> void:
 reset()
 for key in ["eggs","incubators"]:
  var source=data.get(key,[])
  if source is Array:
   for i in range(mini(50,source.size())):
    if source[i] is Dictionary and int(source[i].get("type_id",0)) in [1071020,1071220]:
     if key=="eggs": eggs[i]=source[i].duplicate(true)
     elif source[i].has("ready_at"): incubators[i]=source[i].duplicate(true)
 serial=maxi(1,int(data.get("serial",1)))
 for pet in pets: serial=maxi(serial,int(pet.id)+1)

func auto_incubate(egg_slot: int, now: int) -> bool:
 var slot:=incubators.find(null)
 return incubate(egg_slot,slot,now) if slot>=0 else false

func discard(pets: Array, uid: int) -> bool:
 for i in range(pets.size()):
  if int(pets[i].id)==uid:
   pets.remove_at(i)
   return true
 return false
