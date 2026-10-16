from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8')
s=s.replace('const Store = preload("res://save_store.gd")','const Store = preload("res://save_store.gd")\nconst Gear = preload("res://equipment_system.gd")')
s=s.replace('\tif not character.has("accepted_tasks"):', '\tGear.normalize(character)\n\tif not character.has("accepted_tasks"):')
s=s.replace('\t\tcharacter.progression_version=2\n','\t\tcharacter.progression_version=2\n\tvar gifted:=Gear.grant_gifts(character)\n\tif gifted and slot>=0 and character.has_all(["name","profession","created_at","logged_out_at"]): persist()\n')
s=s.replace('100+int(character.level)*10','max_hp()')
s=s.replace('\tcharacter.gold=int(character.gold)+20\n\tpersist()','\tcharacter.gold=int(character.gold)+20\n\tGear.grant_gifts(character)\n\tpersist()')
s=s.replace('\t\tcharacter.gold=int(character.gold)+100\n\tpersist()','\t\tcharacter.gold=int(character.gold)+100\n\tGear.grant_gifts(character)\n\tpersist()')
s=s.replace('32+int(character.level)*3+(18 if round_number%3==0 else 0)','32+int(character.level)*3+int(gear_stats().attack)+(18 if round_number%3==0 else 0)')
s=s.replace('mini(combat_hp,12+battle_group*7)','mini(combat_hp,maxi(1,12+battle_group*7-int(gear_stats().defense)))')
s=s.replace('\tvar won:=enemy_hp==0\n\tcharacter.hp', '\tvar won:=enemy_hp==0\n\tvar loot: Array=[]\n\tcharacter.hp')
s=s.replace('\t\t\tadd_experience(int(rewards.xp))','\t\t\tadd_experience(int(rewards.xp))\n\t\t\tloot=Gear.roll_wild(character,MONSTER_LEVELS[battle_group],3)')
s=s.replace('\t# Settlement must be acknowledged before returning to the map.','\tif won:\n\t\tvar names: PackedStringArray=[]\n\t\tfor item in loot: names.append(item.name)\n\t\tlabel_text(modal.get_child(0),"装备掉落："+("无" if names.is_empty() else "、".join(names))+ ("（背包满时已转待领取）" if not character.pending_loot.is_empty() else ""),16)\n\t# Settlement must be acknowledged before returning to the map.')
# Previously the last child was the leave button; loot label now added afterward.
s=s.replace('box.get_child(box.get_child_count()-1).queue_free()','box.get_child(3).queue_free()')
a=s.index('func build_character_menu(');b=s.index('\nfunc accept_task(',a)
s=s[:a]+'''func build_character_menu(content: VBoxContainer) -> void:
\tcontent.add_theme_constant_override("separation",10)
\tlabel_text(content,"%s · %s    %s / 等级%d" % [character.name,character.profession,character.realm,character.level],23)
\tvar stats:=gear_stats()
\tlabel_text(content,"气血 %d/%d    攻击 %d (+%d)    防御 %d\\n经验 %d/100    战斗胜场 %d    金币 %d" % [character.hp,max_hp(),32+int(character.level)*3+int(stats.attack),stats.attack,stats.defense,character.xp,character.victories,character.gold],17)
\tvar row:=HBoxContainer.new()
\trow.add_theme_constant_override("separation",20)
\tcontent.add_child(row)
\tvar preview:=Control.new()
\tpreview.custom_minimum_size=Vector2(180,190)
\trow.add_child(preview)
\tactor(preview,0,Vector2(90,160),character.name,2.0)
\tvar grid:=GridContainer.new()
\tgrid.name="EquipmentSlots"
\tgrid.columns=4
\tgrid.add_theme_constant_override("h_separation",10)
\tgrid.add_theme_constant_override("v_separation",10)
\trow.add_child(grid)
\tfor i in range(8):
\t\tvar item: Dictionary=character.equipment[i]
\t\tvar equipment:=Button.new()
\t\tequipment.custom_minimum_size=Vector2(117,82)
\t\tequipment.tooltip_text=Gear.describe(item)+("\\n点击卸下" if Gear.valid(item) else "")
\t\tequipment.pressed.connect(unequip_slot.bind(i))
\t\tgrid.add_child(equipment)
\t\tdecorate_gear_cell(equipment,item,i,true)
\tvar set_text: String="套装：未激活"
\tif int(stats.sets.get("xianyuan",0))>0:
\t\tset_text="仙缘套装 %d/2 · " % int(stats.sets.xianyuan)+("2件已激活：攻击+8 防御+4 气血+40" if int(stats.sets.xianyuan)>=2 else "2件效果：攻击+8 防御+4 气血+40")
\tlabel_text(content,set_text,17)
\tlabel_text(content,gear_notice if not gear_notice.is_empty() else "点击身上的装备卸下；悬停查看属性与套装效果",16)

func build_inventory_menu(content: VBoxContainer) -> void:
\tcontent.add_theme_constant_override("separation",8)
\tvar grid:=GridContainer.new()
\tgrid.name="InventorySlots"
\tgrid.columns=8
\tgrid.add_theme_constant_override("h_separation",10)
\tgrid.add_theme_constant_override("v_separation",8)
\tcontent.add_child(grid)
\tvar occupied:=0
\tfor i in range(40):
\t\tvar cell:=Button.new()
\t\tcell.custom_minimum_size=Vector2(82,56)
\t\tvar item: Dictionary=character.inventory[i]
\t\tif not item.is_empty(): occupied+=1
\t\tcell.tooltip_text=Gear.describe(item)+("\\n点击穿戴（同部位装备会换回此格）" if Gear.valid(item) else "")
\t\tcell.pressed.connect(equip_from_bag.bind(i))
\t\tgrid.add_child(cell)
\t\tdecorate_gear_cell(cell,item,int(item.get("slot",0)),false)
\tvar line:=HBoxContainer.new()
\tcontent.add_child(line)
\tlabel_text(line,"容量 %d/40 · 待领取 %d" % [occupied,character.pending_loot.size()],15)
\tif not character.pending_loot.is_empty(): button(line,"领取待领装备",claim_pending_equipment)
\tvar assets:=label_text(content,"人物资产 · 金币 %d" % character.gold,22)
\tassets.name="GoldBalance"
\tlabel_text(content,gear_notice if not gear_notice.is_empty() else "点击装备穿戴；悬停查看属性",14)
'''+s[b:]
s+='''
var gear_notice: String=""
func gear_stats() -> Dictionary:
\treturn Gear.totals(character.get("equipment",[]))

func max_hp() -> int:
\treturn 100+int(character.get("level",1))*10+int(gear_stats().hp)

func decorate_gear_cell(cell: Button, item: Dictionary, slot_id: int, equipped: bool) -> void:
\tvar exists:=Gear.valid(item)
\tvar color:=Color(Gear.QUALITY_COLORS[int(item.quality)]) if exists else Color("647781")
\tvar style:=StyleBoxFlat.new()
\tstyle.bg_color=Color("162a32")
\tstyle.border_color=color
\tstyle.set_border_width_all(2 if exists else 1)
\tstyle.set_corner_radius_all(4)
\tcell.add_theme_stylebox_override("normal",style)
\tvar hover:=style.duplicate()
\thover.bg_color=Color("304850")
\tcell.add_theme_stylebox_override("hover",hover)
\tif exists and FileAccess.file_exists("res://assets/equipment-icons.png"):
\t\tvar texture:=texture_file("res://assets/equipment-icons.png")
\t\tvar atlas:=AtlasTexture.new()
\t\tatlas.atlas=texture
\t\tvar size:=Vector2(texture.get_width()/4.0,texture.get_height()/2.0)
\t\tatlas.region=Rect2(Vector2(slot_id%4,slot_id/4)*size,size)
\t\tvar icon:=Sprite2D.new()
\t\ticon.texture=atlas
\t\ticon.scale=Vector2(30,30)/atlas.get_size()
\t\ticon.position=Vector2(21,27)
\t\tcell.add_child(icon)
\tvar nameplate:=Label.new()
\tnameplate.mouse_filter=Control.MOUSE_FILTER_IGNORE
\tnameplate.text=(Gear.SLOT_NAMES[slot_id]+"\\n未装备") if equipped and not exists else (str(item.get("name","")) if exists else "")
\tnameplate.position=Vector2(42,5) if exists else Vector2(6,6)
\tnameplate.size=Vector2(69 if equipped else 36,68 if equipped else 45)
\tnameplate.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
\tnameplate.add_theme_font_size_override("font_size",13 if equipped else 12)
\tnameplate.add_theme_color_override("font_color",color)
\tcell.add_child(nameplate)

func refresh_gear_panel(index: int) -> void:
\tif is_instance_valid(menu_layer):
\t\tclose_menu()
\t\ttoggle_menu(index)
\tif is_instance_valid(status_label): refresh_map()

func equip_from_bag(index: int) -> bool:
\tif mode!="map" or index<0 or index>=40 or not Gear.valid(character.inventory[index]): return false
\tvar previous:=character.duplicate(true)
\tvar item: Dictionary=character.inventory[index]
\tvar target:=int(item.slot)
\tcharacter.inventory[index]=character.equipment[target]
\tcharacter.equipment[target]=item
\tcharacter.hp=mini(int(character.hp),max_hp())
\tvar saved:=persist()
\tif not saved: character=previous
\tgear_notice="已穿戴："+item.name if saved else store.last_error
\trefresh_gear_panel(2)
\treturn saved

func unequip_slot(index: int) -> bool:
\tif mode!="map" or index<0 or index>=8 or not Gear.valid(character.equipment[index]): return false
\tvar free:=Gear.empty_bag_slot(character)
\tif free<0:
\t\tgear_notice="背包已满，请先腾出一格再卸下装备"
\t\trefresh_gear_panel(0)
\t\treturn false
\tvar previous:=character.duplicate(true)
\tvar item: Dictionary=character.equipment[index]
\tcharacter.inventory[free]=item
\tcharacter.equipment[index]={}
\tcharacter.hp=mini(int(character.hp),max_hp())
\tvar saved:=persist()
\tif not saved: character=previous
\tgear_notice="已卸下："+item.name if saved else store.last_error
\trefresh_gear_panel(0)
\treturn saved

func claim_pending_equipment() -> void:
\tvar previous:=character.duplicate(true)
\tvar count:=Gear.claim_pending(character)
\tif not persist():
\t\tcharacter=previous
\t\tgear_notice=store.last_error
\telse: gear_notice="已领取%d件装备；剩余%d件待领" % [count,character.pending_loot.size()]
\trefresh_gear_panel(2)
'''
p.write_text(s,encoding='utf-8')
