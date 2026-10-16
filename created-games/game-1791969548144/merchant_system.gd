extends RefCounted
const EGG_WARRIOR=1071020
const EGG_MAGE=1071220
const RETURN_SCROLL=1020010
const RANDOM_SCROLL=1020020
const PRICES={1071020:100,1071220:100,1020010:20,1020020:10}
var message:=""
func buy(game: Node,id: int) -> bool:
 if not PRICES.has(id): return false
 var price: int=PRICES[id]
 if game.gold<price:
  message="金币不足。"
  return false
 var added: bool=game.pet_collection.add_egg(id) if id in [EGG_WARRIOR,EGG_MAGE] else game.equipment.add_item(id)
 if not added:
  message="幻兽蛋区域或背包已满，购买失败，未扣金币。"
  return false
 game.gold-=price
 message="购买成功。"
 game.save_progress()
 return true
func item_price(game: Node,item: Dictionary) -> int:
 var data: Dictionary=game.equipment.definition(item)
 if data.has("slot"): return 10+int(data.level)*2+game.equipment.quality_rank(data)*20
 return 25 if int(item.id)==1037170 else (60 if int(item.id)==1037160 else 1)
func sell_item(game: Node, uid: int) -> bool:
 for i in range(40):
  var item=game.equipment.bag[i]
  if item!=null and int(item.uid)==uid:
   var value:=item_price(game,item)*int(item.count)
   game.equipment.bag[i]=null
   game.gold+=value
   message="已出售，获得%d金币。" % value
   game.save_progress()
   return true
 message="物品不存在；已穿戴装备请先卸下。"
 return false
func pet_price(pet: Dictionary) -> int:
 return 50+int(pet.level)*5+int(pet.star)*100
func sell_pet(game: Node, uid: int) -> bool:
 for pet in game.pets:
  if int(pet.id)==uid:
   if pet.deployed:
    message="请先收回出征幻兽，再出售。"
    return false
   var value:=pet_price(pet)
   if game.pet_collection.discard(game.pets,uid):
    game.refresh_pet_actors()
    game.gold+=value
    message="幻兽已出售，获得%d金币。" % value
    game.save_progress()
    return true
 return false
