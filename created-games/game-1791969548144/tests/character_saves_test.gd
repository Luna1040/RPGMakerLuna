extends SceneTree

const FIXTURE := "res://tests/character-test-fixture.json"

func clean_fixture() -> void:
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))

func _initialize() -> void:
 clean_fixture()
 var store=load("res://character_saves.gd").new()
 store.path=FIXTURE
 assert(store.utc_plus_8(1704067200)=="2024-01-01T08:00:00+08:00")
 for i in range(6): assert(store.create(i,"中文角色"+str(i),"战士" if i%2==0 else "法师",1704067200))
 assert(not store.create(6,"第七人","战士",0))
 assert(not store.create(0,"覆盖","法师",0))
 var reload_store=load("res://character_saves.gd").new()
 reload_store.path=FIXTURE
 assert(reload_store.read_slots())
 assert(reload_store.slots[0].name=="中文角色0")
 assert(reload_store.slots[0].created_at.ends_with("+08:00"))
 assert(not reload_store.delete_character(0,false))
 assert(reload_store.slots[0]!=null)
 assert(reload_store.delete_character(0,true))
 assert(reload_store.slots[0]==null)
 var g=load("res://canosa.gd").new()
 g.save_store=reload_store
 assert(g.create_character(0,"星辰法师","法师"))
 assert(g.hero==g.SPAWN and g.level==1 and g.pets.size()==2)
 assert(g.pets[0].profession=="法师" and g.pets[1].role=="defense")
 g.hero=Vector2(3500,1800)
 g.level=12
 g.quest=5
 g.hp=130
 g.gold=321
 g.master_volume=43
 g.show_nameplates=false
 g.save_progress(true)
 var created: String=g.save_store.slots[0].created_at
 assert(g.save_store.slots[0].offline_at.ends_with("+08:00"))
 assert(g.load_character(2))
 assert(g.profession=="战士" and g.level==1 and g.hero==g.SPAWN)
 assert(g.load_character(0))
 assert(g.profession=="法师" and g.level==12 and g.hp==130 and g.hero==Vector2(3500,1800))
 assert(g.gold==321 and g.master_volume==43 and not g.show_nameplates)
 assert(g.save_store.slots[0].created_at==created)
 assert(g.save_store.delete_character(3,true))
 g.enemies[0].hp=0
 g.dialog_npc=0
 assert(g.create_character(3,"新的战士","战士"))
 assert(g.level==1 and g.quest==0 and g.hero==g.SPAWN and g.enemies[0].hp>0 and g.dialog_npc==-1)
 assert(g.pets.size()==2 and g.pets[0].profession=="战士")
 g.hero=Vector2(3500,1800)
 var before: float=g.pets[1].hp
 g.take_hit(20)
 assert(g.hp==170 and g.pets[1].hp==before-10)
 g.profession="法师"
 g.attack_cd=0
 g.enemies[0].pos=g.hero+Vector2(200,0)
 g.strike(false)
 assert(g.enemies[0].last_damage_type=="magic")
 g.profession="战士"
 g.attack_cd=0
 var hp_before: float=g.enemies[0].hp
 g.strike(false)
 assert(g.enemies[0].hp==hp_before,"Warrior must be melee")
 g.enemies[0].pos=g.hero+Vector2(50,0)
 g.attack_cd=0
 g.strike(false)
 assert(g.enemies[0].last_damage_type=="physical")
 assert(g.save_store.save_character(5,{"level":7},false,1704067200))
 var interrupted=load("res://character_saves.gd").new()
 interrupted.path=FIXTURE
 assert(interrupted.read_slots())
 assert(interrupted.slots[5].offline_at=="2024-01-01T08:00:00+08:00" and interrupted.slots[5].offline_estimated)
 g.free()
 clean_fixture()
 print("PASS: six slots, UTF8 Chinese, UTC+8, metadata, cancel/confirm deletion, persistence, fresh map, classes, two pets, defense")
 quit()
