extends SceneTree
const FIXTURE="res://tests/equipment-fixture.json"
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var sys=load("res://equipment_system.gd").new()
 assert(sys.definitions.size()==374)
 for item in sys.definitions.values():
  assert(ResourceLoader.exists(item.icon))
  if item.has("slot"): assert(item.level>=1 and item.level<=35 and item.profession in ["战士","法师"])
 assert(sys.add_item(410000))
 assert(not sys.equip(0,"法师",35))
 assert(sys.equip(0,"战士",1))
 assert(sys.stats().physical_max==39)
 var uid: int=sys.equipped["武器"].uid
 assert(not sys.forge(uid,"level",35))
 assert(sys.add_item(sys.PHANTOM))
 assert(not sys.forge(uid,"level",1))
 assert(sys.count_material(sys.PHANTOM)==1)
 assert(sys.forge(uid,"level",9))
 assert(sys.equipped["武器"].id==410010 and sys.count_material(sys.PHANTOM)==0)
 assert(sys.add_item(sys.SOUL))
 assert(sys.forge(uid,"quality",9))
 assert(sys.equipped["武器"].id==410011 and sys.stats().physical_max>39)
 assert(not sys.forge(uid,"quality",9))
 assert(sys.unequip("武器"))
 for i in range(39): assert(sys.add_item(440000))
 assert(not sys.add_item(410000))
 var encoded: String=JSON.stringify(sys.snapshot())
 var restored=load("res://equipment_system.gd").new()
 restored.restore(JSON.parse_string(encoded))
 assert(restored.bag.size()==40 and restored.bag.count(null)==0)
 assert(restored.bag[0].id==410011)
 restored.reset()
 for i in range(100): assert(restored.add_item(restored.PHANTOM))
 assert(restored.count_material(restored.PHANTOM)==100 and restored.bag.count(null)==38)
 var g=load("res://canosa.gd").new()
 g.new_run()
 g.save_store.path=FIXTURE
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 assert(g.create_character(0,"锻造测试","战士"))
 g.level=30
 assert(g.equipment.add_item(410000))
 assert(g.equipment.equip(0,"战士",30))
 assert(g.equipment.add_item(1037170))
 assert(g.save_progress())
 assert(g.load_character(0))
 assert(g.equipment.equipped["武器"].id==410000 and g.equipment.count_material(1037170)==1)
 seed(314159)
 var enemy: Dictionary=g.enemies[0]
 for i in range(1000):
  enemy.hp=1
  g.damage(enemy,2)
 var types: Array=[]
 for drop in g.item_drops:
  if not int(drop.id) in types: types.append(int(drop.id))
 assert(1037160 in types and 1037170 in types and types.size()>30)
 var n: int=g.item_drops.size()
 assert(g.pickup_item(0) and g.item_drops.size()==n-1)
 var ui=load("res://player_panels.gd").new()
 root.add_child(ui)
 ui.setup(g)
 g.player_ui=ui
 g.dialog_npc=2
 assert(g.dialog_options()[1].contains("锻造"))
 g.choose_dialog(1)
 assert(ui.opened==6 and g.dialog_npc==-1)
 var forge=ui.content.get_child(1)
 assert(forge.uids.size()>0)
 var current: Dictionary=g.equipment.equipped["武器"]
 forge.pending_uid=current.uid
 forge.pending_mode="level"
 forge.confirmation.canceled.emit()
 assert(current.id==410000)
 forge.pending_uid=current.uid
 forge.pending_mode="level"
 forge.confirmation.confirmed.emit()
 assert(current.id==410010)
 ui.toggle(2)
 var discard_index:=-1
 for i in range(40):
  if g.equipment.bag[i]!=null:
   discard_index=i
   break
 assert(discard_index>=0)
 ui.request_discard(discard_index)
 ui.discard_confirm.canceled.emit()
 assert(g.equipment.bag[discard_index]!=null)
 ui.request_discard(discard_index)
 ui.discard_confirm.confirmed.emit()
 assert(g.equipment.bag[discard_index]==null)
 g.player_ui=null
 ui.free()
 # Full inventory pickup must leave the ground drop untouched.
 g.equipment.reset()
 for i in range(40): assert(g.equipment.add_item(410000))
 g.item_drops.clear()
 g.add_item_drop(440000,g.hero)
 assert(not g.pickup_item(0) and g.item_drops.size()==1)
 g.equipment.reset()
 g.level=35
 assert(g.equipment.add_item(131010))
 assert(g.equipment.add_item(1037170))
 var armor_uid: int=g.equipment.bag[0].uid
 assert(g.equipment.forge(armor_uid,"level",35))
 assert(g.equipment.bag[0].id==131020)
 assert(g.equipment.add_item(1037170))
 assert(not g.equipment.forge(armor_uid,"level",35) and g.equipment.count_material(1037170)==1)
 g.equipment.reset()
 assert(g.equipment.add_item(410000) and g.equipment.equip(0,"战士",35))
 g.hero=Vector2(3500,1800)
 g.enemies[0].pos=g.hero
 g.enemies[0].hp=1000
 g.attack_cd=0
 g.strike(false)
 assert(g.enemies[0].hp==931,"Equipped weapon must change actual strike damage")
 assert(g.equipment.add_item(111000) and g.equipment.equip(0,"战士",35))
 g.hp=180
 g.take_hit(20)
 assert(g.hp>170,"Equipped armor must reduce actual incoming damage")
 g.new_run()
 assert(g.equipment.equipped.is_empty() and g.equipment.bag.count(null)==40 and g.item_drops.is_empty())
 g.free()
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE+suffix))
 print("PASS: 370 original equipment definitions and 2 stones, all icons, class/level checks, equip stats, forging costs, insufficient resources, bag capacity, stacks, persistence, real kill loot and pickup, NPC forge UI, cancel/confirm, fresh character isolation")
 quit()
