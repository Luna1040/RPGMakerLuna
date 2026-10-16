from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8')
a=s.index('func migrate()');b=s.index('\nvar map_layer:',a)
s=s[:a]+'''func migrate() -> void:
	for key in {"quest":0,"zone":"town","field_quest":0,"cleared":[],"position":[620,610],"sect_quest":0,"realm":"凡人"}:
		if not character.has(key): character[key] = {"quest":0,"zone":"town","field_quest":0,"cleared":[],"position":[620,610],"sect_quest":0,"realm":"凡人"}[key]
	if int(character.get("progression_version",0))<2:
		# Recalculate only the old tutorial/field progression, once per save.
		var base: int=[1,2,3,4,4,5][mini(int(character.quest),5)]
		var earned:=0
		for group in character.cleared:
			if int(group)>=0 and int(group)<3: earned+=MONSTER_XP[int(group)]
		if int(character.field_quest)==4: earned+=100
		character.level=base+earned/100
		character.xp=earned%100
		character.hp=100+int(character.level)*10
		character.progression_version=2

const MONSTER_XP := [100,150,150]
const SECT_POS := [Vector2(680,380),Vector2(930,465)]
const ZONES := {
	"town":{"title":"青牛镇 · 山村初识","background":"res://assets/town.png","names":TOWN_NAMES,"positions":TOWN_POS,"portraits":[1,2,3,4,5]},
	"field":{"title":"云雾山 · 初试锋芒","background":"res://assets/field.png","names":["林守卫","云游道长"],"positions":FIELD_POS,"portraits":[6,5]},
	"sect":{"title":"青云宗 · 修仙之始","background":"res://assets/sect.png","names":["接引长老","传功师姐"],"positions":SECT_POS,"portraits":[5,2]}
}
# New maps declare their gates here and share arrival-triggered transport.
const PORTALS := {
	"town":[{"id":"town_field","position":Vector2(1110,595),"target":"field","spawn":Vector2(210,590),"label":"云雾山","level":5,"tutorial":true}],
	"field":[{"id":"field_town","position":Vector2(160,590),"target":"town","spawn":Vector2(1050,595),"label":"青牛镇","level":1}, {"id":"field_sect","position":Vector2(1100,350),"target":"sect","spawn":Vector2(250,590),"label":"青云宗 · 10级","level":10}],
	"sect":[{"id":"sect_field","position":Vector2(160,590),"target":"field","spawn":Vector2(1040,350),"label":"云雾山","level":1}]
}

func add_experience(amount: int) -> void:
	character.xp=int(character.xp)+amount
	while int(character.xp)>=100:
		character.xp=int(character.xp)-100
		character.level=int(character.level)+1
		character.hp=100+int(character.level)*10

func npc_has_task(index: int) -> bool:
	if character.zone=="town": return index==int(character.quest) and int(character.quest)<5
	if character.zone=="field":
		return (index==0 and int(character.field_quest) in [0,3]) or (index==1 and int(character.field_quest)==1 and 0 in character.cleared)
	return int(character.level)>=10 and ((index==0 and int(character.sect_quest)==0) or (index==1 and int(character.sect_quest)==1))

func click_area(parent: Node, rect: Rect2, action: Callable, title: String) -> Button:
	var hit:=Button.new()
	hit.name="ClickArea"
	hit.position=rect.position
	hit.size=rect.size
	hit.flat=true
	hit.tooltip_text=title
	hit.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	hit.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","focus"]: hit.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	hit.pressed.connect(action)
	parent.add_child(hit)
	return hit

func add_portal(data: Dictionary) -> void:
	var holder:=Control.new()
	holder.position=data.position
	holder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(holder)
	var vortex:=Sprite2D.new()
	vortex.texture=texture_file("res://assets/portal.png")
	vortex.scale=Vector2(88,100)/vortex.texture.get_size()
	vortex.position=Vector2(0,-40)
	var glow:=CanvasItemMaterial.new()
	glow.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	vortex.material=glow
	holder.add_child(vortex)
	var caption:=Label.new()
	caption.text=data.label
	caption.position=Vector2(-90,12)
	caption.size=Vector2(180,28)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",16)
	caption.add_theme_color_override("font_color",Color("baf5ff"))
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",2)
	caption.add_theme_constant_override("shadow_offset_y",2)
	caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	holder.add_child(caption)
	click_area(holder,Rect2(-90,-90,180,135),travel.bind(data.position,"portal:"+data.id),"前往"+data.label)

func use_portal(id: String) -> void:
	for data in PORTALS.get(character.zone,[]):
		if data.id!=id: continue
		if player_pos.distance_to(data.position)>8:
			travel(data.position,"portal:"+id)
			return
		if int(character.level)<int(data.level) or (data.get("tutorial",false) and int(character.quest)<5):
			dialog("传送尚未开放","完成当前地图历练，达到%d级后可前往%s。" % [data.level,data.label],"继续历练",close_dialog)
			return
		character.zone=data.target
		player_pos=data.spawn
		character.hp=100+int(character.level)*10
		persist()
		show_world()
		return
'''+s[b:]
s=s.replace('"新手任务已完成，前往东侧出口进入云雾山"','"新手任务已完成（5级），点击东侧云雾漩涡前往云雾山"')
# Actor loads transparent per-character images after matte processing.
a=s.index('\tif FileAccess.file_exists("res://assets/cast.png"):');b=s.index('\tvar nameplate:=Label.new()',a)
s=s[:a]+'''\tvar portrait_path: String="res://assets/characters/%d.png" % index
\tif FileAccess.file_exists(portrait_path):
\t\tvar source: Texture2D=texture_file(portrait_path)
\t\tvar portrait:=Sprite2D.new()
\t\tportrait.name="Portrait"
\t\tportrait.texture=source
\t\tportrait.scale=MAP_ACTOR_SIZE*scale_value/source.get_size()
\t\tportrait.position=Vector2(0,-MAP_ACTOR_SIZE.y*scale_value/2.0)
\t\tholder.add_child(portrait)
'''+s[b:]
a=s.index('\tbackground("res://assets/town.png"',s.index('func show_world'));b=s.index('\tif not town:',a)
s=s[:a]+'''\tvar zone: Dictionary=ZONES[character.zone]
\tbackground(zone.background)
\tmap_layer=Control.new()
\tmap_layer.size=Vector2(1280,800)
\tmap_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
\tscreen.add_child(map_layer)
\tvar town: bool=character.zone=="town"
\tvar names: Array=zone.names
\tvar locations: Array=zone.positions
\tfor i in range(names.size()):
\t\tvar npc:=actor(map_layer,int(zone.portraits[i]),locations[i],names[i])
\t\tif npc_has_task(i):
\t\t\tvar mark:=Label.new()
\t\t\tmark.text="?"
\t\t\tmark.position=Vector2(-60,-3)
\t\t\tmark.add_theme_font_size_override("font_size",26)
\t\t\tmark.add_theme_color_override("font_color",Color("ffe300"))
\t\t\tmark.add_theme_color_override("font_shadow_color",Color.BLACK)
\t\t\tmark.add_theme_constant_override("shadow_offset_x",2)
\t\t\tmark.mouse_filter=Control.MOUSE_FILTER_IGNORE
\t\t\tnpc.add_child(mark)
\t\tclick_area(npc,Rect2(-70,-76,140,106),travel.bind(locations[i]+NPC_APPROACH,"npc:"+str(i)),names[i])
\tfor data in PORTALS.get(character.zone,[]): add_portal(data)
'''+s[b:]
s=s.replace('\tif not town:\n\t\tfor i in range(3):','\tif character.zone=="field":\n\t\tfor i in range(3):')
s=s.replace('("青牛镇 · 山村初识" if town else "云雾山 · 初试锋芒")','str(zone.title)')
s=s.replace('\tbutton(buttons,"前往云雾山" if town else "返回青牛镇",travel.bind(Vector2(1140,600),"exit"))','\tlabel_text(buttons,"点击地图云雾漩涡传送",16)')
s=s.replace('等级 %d   气血 %d   灵石 %d" % [character.name,character.profession,character.level,character.hp,character.stones]','等级 %d   经验 %d/100   %s   气血 %d   灵石 %d" % [character.name,character.profession,character.level,character.xp,character.realm,character.hp,character.stones]')
s=s.replace('\telse:\n\t\tvar stage:=int(character.field_quest)','\telif character.zone=="field":\n\t\tvar stage:=int(character.field_quest)',1)
s=s.replace('text="云雾山任务完成！可返回青牛镇调息"','text="云雾山任务完成！点击东北漩涡前往青云宗，接取练气入门任务"')
s=s.replace('\t\tquest_label.text="历练 · "+text\n','\t\tquest_label.text="历练 · "+text\n\telse:\n\t\tquest_label.text=["仙途 · 达到10级，拜访接引长老","仙途 · 已入练气期，拜访传功师姐学习周天功法","仙途 · 入门功法已掌握，修仙之路正式开启"][mini(int(character.sect_quest),2)]\n')
a=s.index('\tif action=="exit":',s.index('func interact'));b=s.index('\telif action.begins_with("npc:"):',a)
s=s[:a]+'''\tif action.begins_with("portal:"):
\t\tuse_portal(action.get_slice(":",1))
\telif action=="exit":
\t\t# Legacy action routes through the shared approach/arrival logic.
\t\tvar gates: Array=PORTALS.get(character.zone,[])
\t\tif not gates.is_empty(): use_portal(gates[0].id)
'''+s[b:]
s=s.replace('var locations: Array=TOWN_POS if character.zone=="town" else FIELD_POS','var locations: Array=ZONES[character.zone].positions')
s=s.replace('\tif character.zone=="town":\n\t\tvar q:=int(character.quest)','''\tif character.zone=="sect":
\t\tif int(character.level)<10:
\t\t\tdialog("接引长老","需达到10级才能拜入仙门。","继续历练",close_dialog)
\t\telif index==0 and int(character.sect_quest)==0:
\t\t\tdialog("接引长老","凡尘历练已满。拜入青云宗，纳天地灵气，自此进入练气期。再向传功师姐学习周天功法。","接取 · 修仙之路",advance_sect.bind(1))
\t\telif index==1 and int(character.sect_quest)==1:
\t\t\tdialog("传功师姐","气沉丹田，周天循环。你已掌握入门功法，修仙之路从今日开始。","完成 · 领悟周天功法",advance_sect.bind(2))
\t\telse: dialog(str(ZONES.sect.names[index]),"静心修炼，仙途漫漫。", "继续",close_dialog)
\t\treturn
\tif character.zone=="town":
\t\tvar q:=int(character.quest)''')
s=s.replace('这是你的历练奖励：200修为，100灵石。','这是你的历练奖励：100经验，100灵石。至此可达到10级，前往青云宗拜师。')
s=s.replace('[3,5,7,9,10][index]','[2,3,4,4,5][index]')
s=s.replace('character.xp=int(character.xp)+200','add_experience(100)')
s=s.replace('character.xp=int(character.xp)+80','add_experience(MONSTER_XP[battle_group])')
s=s.replace('"获得80修为、30灵石。进度已保存，确认后返回原位置。"','"获得%d经验、30灵石。当前等级%d。确认后返回原位置。" % [MONSTER_XP[battle_group],character.level]')
s=s.replace('func start_battle(group: int) -> void:\n','func start_battle(group: int) -> void:\n\tif character.zone!="field" or group<0 or group>=3: return\n')
s=s.replace('func persist() -> bool:', '''func advance_sect(stage: int) -> void:
\tif int(character.level)<10 or int(character.sect_quest)!=stage-1: return
\tcharacter.sect_quest=stage
\tcharacter.realm="练气期"
\tif stage==2: character.stones=int(character.stones)+100
\tpersist()
\tshow_world()

func persist() -> bool:''')
p.write_text(s,encoding='utf-8')
