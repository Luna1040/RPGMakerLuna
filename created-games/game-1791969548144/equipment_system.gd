extends RefCounted
const PHANTOM=1037170
const SOUL=1037160
const SLOTS=["武器","头盔","护甲","项链","手镯","腰带","戒指","鞋子"]
var definitions: Dictionary={}
var bag: Array=[]
var equipped: Dictionary={}
var serial:=1
var message:=""
func _init() -> void:
 var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/client_equipment/catalog.json"))
 for item in catalog.equipment+catalog.materials: definitions[int(item.id)]=item
 for item in [
  {"id":1020010,"name":"回城符","kind":"scroll","icon":"res://assets/client_shop/1020010.dds","description":"使用后回到当前地图城区。"},
  {"id":1020020,"name":"随机符","kind":"scroll","icon":"res://assets/client_shop/1020020.dds","description":"使用后随机传送到当前地图可行走地点。"}]: definitions[item.id]=item
 reset()
func reset() -> void:
 bag.resize(40)
 bag.fill(null)
 equipped.clear()
 message=""
 serial=1
func definition(item: Dictionary) -> Dictionary:
 return definitions.get(int(item.get("id",0)),{})
func add_item(id: int) -> bool:
 if not definitions.has(id): return false
 var data: Dictionary=definitions[id]
 if data.get("kind","")in ["material","scroll"]:
  for item in bag:
   if item!=null and int(item.id)==id and int(item.count)<99:
    item.count+=1
    return true
 var empty:=bag.find(null)
 if empty<0:
  message="背包已满，无法拾取。"
  return false
 bag[empty]={"id":id,"uid":serial,"count":1}
 serial+=1
 return true
func count_material(id: int) -> int:
 var result:=0
 for item in bag:
  if item!=null and int(item.id)==id: result+=int(item.count)
 return result
func consume(id: int) -> bool:
 for i in range(bag.size()):
  if bag[i]!=null and int(bag[i].id)==id:
   bag[i].count-=1
   if bag[i].count<=0: bag[i]=null
   return true
 return false
func equip(index: int, profession: String, level: int) -> bool:
 if index<0 or index>=40 or bag[index]==null: return false
 var item: Dictionary=bag[index]
 var data:=definition(item)
 if not data.has("slot"):
  message="晶石请在锻造师处使用。"
  return false
 if data.profession!=profession:
  message="职业不符，无法穿戴。"
  return false
 if int(data.level)>level:
  message="需要角色等级 %d。" % data.level
  return false
 bag[index]=equipped.get(data.slot,null)
 equipped[data.slot]=item
 message="已装备："+data.name
 return true
func unequip(slot: String) -> bool:
 if not equipped.has(slot): return false
 var empty:=bag.find(null)
 if empty<0:
  message="背包已满，不能卸下装备。"
  return false
 bag[empty]=equipped[slot]
 equipped.erase(slot)
 message="装备已卸下。"
 return true
func stats() -> Dictionary:
 var total={"physical_min":0,"physical_max":0,"magic":0,"defense":0,"magic_defense":0}
 for item in equipped.values():
  var data:=definition(item)
  for key in total: total[key]+=int(data.get(key,0))
 return total
func target(item: Dictionary, mode: String) -> Dictionary:
 var data:=definition(item)
 if not data.has("slot"): return {}
 if mode=="quality": return definitions.get(int(data.id)-int(data.quality)+(7 if int(data.quality)==3 else int(data.quality)+1),{}) if quality_rank(data)<4 else {}
 var candidates: Array=[]
 for value in definitions.values():
  if value.get("family",-1)==data.family and value.get("quality",-1)==data.quality and int(value.level)>int(data.level): candidates.append(value)
 candidates.sort_custom(func(a,b): return a.level<b.level)
 return candidates[0] if not candidates.is_empty() else {}
func find_instance(uid: int) -> Dictionary:
 for item in bag+equipped.values():
  if item!=null and int(item.uid)==uid: return item
 return {}
func forge(uid: int, mode: String, level: int) -> bool:
 if mode not in ["level","quality"]: return false
 var item:=find_instance(uid)
 if item.is_empty():
  message="装备已不存在，请重新选择。"
  return false
 var next:=target(item,mode)
 if next.is_empty():
  message="已达到当前35级以下装备库的等级或品质上限。"
  return false
 if int(next.level)>level:
  message="升级后需 %d级，请先提升角色等级。" % next.level
  return false
 var stone:=PHANTOM if mode=="level" else SOUL
 if not consume(stone):
  message="缺少"+definitions[stone].name+"。"
  return false
 item.id=int(next.id)
 message="锻造成功：%s · Lv.%d · %s" % [next.name,next.level,quality_name(next)]
 return true
func tooltip(item: Dictionary) -> String:
 var data:=definition(item)
 if data.is_empty(): return ""
 if not data.has("slot"): return data.name+"\n"+data.description
 return "%s · %s · %s\n需求等级%d · %s\n物攻%d–%d 魔攻%d 物防%d 魔防%d\n%s" % [data.name,data.profession,data.slot,data.level,quality_name(data),data.physical_min,data.physical_max,data.magic,data.defense,data.magic_defense,data.description]
func snapshot() -> Dictionary:
 return {"version":1,"bag":bag.duplicate(true),"equipped":equipped.duplicate(true),"serial":serial}
func restore(data: Dictionary) -> void:
 reset()
 var source=data.get("bag",[])
 var seen: Array=[]
 if source is Array:
  for i in range(mini(40,source.size())):
   var item=source[i]
   if item is Dictionary and definitions.has(int(item.get("id",0))) and int(item.get("uid",0))>0 and not int(item.uid) in seen:
    bag[i]={"id":int(item.id),"uid":int(item.uid),"count":clampi(int(item.get("count",1)),1,99) if definition(item).get("kind","")in ["material","scroll"] else 1}
    seen.append(int(item.uid))
 for slot in data.get("equipped",{}):
  var item=data.equipped[slot]
  if item is Dictionary and definitions.has(int(item.get("id",0))) and definition(item).get("slot","")==slot and not int(item.get("uid",0)) in seen:
   equipped[slot]={"id":int(item.id),"uid":int(item.uid),"count":1}
   seen.append(int(item.uid))
 serial=maxi(1,int(data.get("serial",1)))
 for uid in seen: serial=maxi(serial,uid+1)

static func quality_rank(data: Dictionary) -> int:
 return clampi(int(data.get("quality",0)),0,4)
static func quality_name(data: Dictionary) -> String:
 return ["下品","中品","上品","精品","极品"][quality_rank(data)]
static func quality_color(data: Dictionary) -> Color:
 return [Color("a5a5a5"),Color("68d689"),Color("6ca9ff"),Color("f07777"),Color("cf8aff")][quality_rank(data)]
