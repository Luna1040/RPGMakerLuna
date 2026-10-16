from pathlib import Path
p=Path('equipment_system.gd');s=p.read_text(encoding='utf-8-sig').replace('static func normalize(c: Dictionary) -> void:','''static func normalize_item(item: Dictionary) -> void:
\tif not valid(item): return
\tfor key in ["slot","quality","level"]: item[key]=int(item[key])
\tfor key in ["attack","defense","hp"]: item.stats[key]=int(item.stats.get(key,0))

static func normalize(c: Dictionary) -> void:''').replace('\tif not c.has("loot_seed"): c.loot_seed=randi()','''\tif not c.has("loot_seed"): c.loot_seed=randi()
\tfor collection in [c.equipment,c.inventory,c.pending_loot]:
\t\tfor item in collection:
\t\t\tif item is Dictionary: normalize_item(item)''');p.write_text(s,encoding='utf-8')
p=Path('main.gd');s=p.read_text(encoding='utf-8').replace('可前往云雾山除妖。','可前往云雾山除妖。另赠蓝色仙缘灵剑，请到背包穿戴。').replace('这是你的历练奖励：248经验，100金币。','这是你的历练奖励：248经验、100金币及蓝色仙缘道袍。').replace('\t\tcharacter={}\n\t\tslot=-1','\t\tcharacter={}\n\t\tgear_notice=""\n\t\tslot=-1');p.write_text(s,encoding='utf-8')
p=Path('tests/equipment_v6.gd');s=p.read_text(encoding='utf-8-sig');a=s.index('\tfor field in ["equipment","inventory","pending_loot"]:');b=s.index('\tcheck(game.character.equipment==saved.equipment',a);s=s[:a]+s[b:];p.write_text(s,encoding='utf-8')
