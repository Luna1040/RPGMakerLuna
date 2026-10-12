extends CanvasLayer
## All menus share one modal gate, so paused combat never leaks through buttons.
var runtime
var overlay:=Control.new()
var body:=VBoxContainer.new()
var scroll:=ScrollContainer.new()
var message:=Label.new()
var status:=Label.new()
var heading:=Label.new()
var tab:="adventure"
var npc_id:="innkeeper"
var npc_portrait
var roster_id:="scout"
var capture_action:=""
var overwrite_slot:=0
var transition_confirm:=false
var campaign_launch_preview: Dictionary = {}
var summary_clock:=0.0

func setup(service) -> void:
	runtime=service
	layer=40
	var launcher:=Button.new()
	launcher.text="Esc · 冒险 / 存档"
	launcher.position=Vector2(1060,210)
	launcher.size=Vector2(198,36)
	launcher.pressed.connect(func(): close() if is_open() else open("adventure"))
	add_child(launcher)
	status.position=Vector2(28,112)
	status.size=Vector2(650,30)
	status.add_theme_font_size_override("font_size",17)
	status.add_theme_color_override("font_color",Color("f9deb0"))
	status.add_theme_color_override("font_shadow_color",Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x",1)
	status.add_theme_constant_override("shadow_offset_y",1)
	add_child(status)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim:=ColorRect.new()
	dim.color=Color(0,.015,.035,.8)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=PanelContainer.new()
	panel.position=Vector2(100,66)
	panel.size=Vector2(1080,678)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("101e2d")
	style.border_color=Color("bda575")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left=24
	style.content_margin_right=24
	style.content_margin_top=20
	style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style)
	overlay.add_child(panel)
	var layout:=VBoxContainer.new()
	layout.add_theme_constant_override("separation",12)
	panel.add_child(layout)
	var top:=HBoxContainer.new()
	layout.add_child(top)
	heading.text="苍石手记"
	heading.add_theme_font_size_override("font_size",28)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	button(top,"继续游戏 · Esc",close)
	var tabs:=HBoxContainer.new()
	layout.add_child(tabs)
	for entry in [["adventure","冒险"],["journal","任务"],["network","叙事网络"],["roster","角色图鉴"],["trade","补给与锻造"],["saves","存档"],["campaigns","战役"],["settings","设置"]]:
		var id:String=entry[0]
		button(tabs,entry[1],func(): open(id))
	layout.add_child(HSeparator.new())
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	scroll.add_child(body)
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y=42
	message.add_theme_font_size_override("font_size",17)
	message.add_theme_color_override("font_color",Color("a9d9dc"))
	layout.add_child(HSeparator.new())
	layout.add_child(message)
	overlay.hide()
	update_status()

func is_open() -> bool:
	return overlay.visible

func open(id: String) -> void:
	runtime.stage.interface.close_panels()
	tab=id
	capture_action=""
	overwrite_slot=0
	transition_confirm=false
	if id!="campaigns": campaign_launch_preview={}
	runtime.stage.sprint.reset()
	runtime.stage.knight.set_movement_axis(0)
	overlay.show()
	refresh()

func close() -> void:
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null and overlay.is_ancestor_of(focused):
		focused.release_focus()
	overlay.hide()
	capture_action=""
	overwrite_slot=0
	transition_confirm=false
	campaign_launch_preview={}

func button(parent: Node, text: String, action: Callable, enabled: bool = true) -> Button:
	var b:=Button.new()
	b.text=text
	b.custom_minimum_size.y=38
	b.add_theme_font_size_override("font_size",18)
	b.disabled=not enabled
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func words(text: String, color: Color = Color("d5dfec"), size: int = 18) -> Label:
	var label:=Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	body.add_child(label)
	return label

func row() -> HBoxContainer:
	var r:=HBoxContainer.new()
	r.add_theme_constant_override("separation",10)
	body.add_child(r)
	return r

func refresh() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical=0
	heading.text={"adventure":"苍石手记 · 冒险","journal":"任务与人情","network":"交织的线索","roster":"同行者与古塔敌影","trade":"补给与锻造","saves":"旅途存档","campaigns":"战役管理","settings":"游戏设置","dialogue":"城镇交谈"}.get(tab,"苍石手记")
	match tab:
		"adventure": render_adventure()
		"journal": render_journal()
		"network": render_network()
		"roster": render_roster()
		"trade": render_trade()
		"saves": render_saves()
		"campaigns": render_campaigns()
		"settings": render_settings()
		"dialogue": render_dialogue()
	update_status()

func update_status() -> void:
	status.text="Lv.%d  经验 %d/%d   铜币 %d   %s  ·  %s" % [runtime.progression.level,runtime.progression.xp,runtime.progression.xp_to_next(),runtime.stage.loot.materials.get("旧铜币",0),"苍石庭院" if runtime.zone=="town" else "古塔试炼场", "城镇休整" if runtime.zone=="town" else "第 %d / 3 轮" % runtime.run_state.wave]

func _process(delta: float) -> void:
	summary_clock+=delta
	if summary_clock>=.25 and runtime!=null:
		summary_clock=0
		update_status()

func render_adventure() -> void:
	words("姬骑士 · 等级 %d / 经验 %d / 技能点 %d" % [runtime.progression.level,runtime.progression.xp,runtime.progression.skill_points],Color("f7d78e"),24)
	words("城镇接取委托、调查失踪物资；进入古塔完成三轮试炼。轮间选择祝福，装备、经验与人物关系随旅程保留。")
	if runtime.zone=="town":
		words("先靠近艾琳或雷恩按 %s 交谈。不同选择会汇入同一场危机，支线可以交叉推进。" % runtime.controls.key_name("interact"))
		var actions:=row()
		button(actions,"进入古塔试炼",func(): runtime.start_trial())
		button(actions,"旅店休息 · 10 铜币",rest)
	else:
		var phase:String=runtime.run_state.phase
		words({"ready":"休整完毕即可开始下一轮。","combat":"战斗已暂停；返回游戏继续应战。","boon":"本轮清场。选择一个祝福，为下一轮做好准备。","victory":"古塔已平定！回城后向委托人交付任务。","defeat":"挑战失败。回城重新整备，或读取上个检查点。"}.get(phase,"可返回庭院"),Color("f7d78e"),21)
		if phase=="boon":
			for id in runtime.run_state.offers:
				var boon:String=id
				button(body,runtime.BOONS[id].name+" · "+runtime.BOONS[id].text,func(): runtime.choose_boon(boon); refresh())
		if phase=="ready": button(body,"开始第 %d 轮" % (runtime.run_state.wave+1),func(): runtime.start_wave())
		if not runtime.run_state.boons.is_empty():
			var titles: Array[String]=[]
			for id in runtime.run_state.boons: titles.append(runtime.BOONS[id].name)
			words("本次祝福："+" / ".join(titles))
		button(body,"回城 / 撤退",func():
			if phase=="combat" and not transition_confirm:
				transition_confirm=true
				message.text="再次点击回城确认撤退；未拾取物品留在试炼场，本次祝福结束。"
			else: runtime.return_town())
	words("队友",Color("f7d78e"),21)
	if runtime.companion_recruited:
		var ally:Dictionary=runtime.encounters.companion_status()
		words("瑟琳 · 战牧  /  生命 %d/%d  ·  法力 %d/%d%s" % [ally.hp,ally.max_hp,ally.mp,ally.max_mp,"  ·  已倒下，回城休整可复苏" if ally.dead else ""],Color("a8ded7"),18)
		words("以圣光弹支援输出，自动治疗受伤同伴；危急时施放圣域盾。技能消耗她自己的法力。",Color("a9bccd"),17)
		var modes:=row()
		for entry in [["follow","跟随作战"],["guard","原地守卫"],["passive","停战跟随"]]:
			var mode:String=entry[0]
			button(modes,("● " if mode==runtime.companion_mode else "")+entry[1],func(): runtime.companion_mode=mode; runtime.encounters.set_companion(mode); refresh())
		button(modes,"职业与技能",func(): roster_id="serin"; open("roster"))
	else:
		words("与镇民建立信任后，可以通过对话邀请援手。")
	var potions:=row()
	button(potions,"4 · 使用生命药水",func(): runtime.use_potion("healing_potion"); refresh(),not runtime.stage.knight.defeated)
	button(potions,"5 · 使用法力药水",func(): runtime.use_potion("mana_potion"); refresh(),not runtime.stage.knight.defeated)
	words("成长与天赋 · 可分配 %d 点" % runtime.progression.skill_points,Color("f7d78e"),21)
	for id in runtime.talents.CATALOG:
		var talent:String=id
		var info:Dictionary=runtime.talents.CATALOG[id]
		button(body,"%s %d/3 · %s" % [info.name,runtime.talents.rank(id),info.description],func(): runtime.talents.spend(talent,runtime.progression); refresh(),runtime.talents.can_spend(id,runtime.progression))
	button(body,"重置天赋（测试版免费，城镇可用）",func(): runtime.talents.refund(runtime.progression); refresh(),runtime.zone=="town" and runtime.talents.spent_points()>0)

func rest() -> void:
	runtime.rest_party()
	refresh()

func render_roster() -> void:
	var roster:=preload("roster_panel.gd").new()
	roster.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(roster)
	roster.setup(runtime,roster_id)

func render_journal() -> void:
	words("任务记录与当前目标",Color("f7d78e"),23)
	for quest in runtime.adventure.quest_rows():
		var state_name:String={"locked":"未解锁","available":"可接取","active":"进行中","ready":"可交付","claimed":"已完成"}.get(quest.get("status",""),"")
		words(str(quest.get("title",quest.get("id","")))+"  ·  "+state_name,Color("e6c78b"),21)
		words(str(quest.get("description","")),Color("a9bccd"),17)
		var objectives=quest.get("objectives",[])
		if objectives is String: words(objectives)
		elif objectives is Array:
			for objective in objectives:
				if objective is Dictionary:
					words("  %s  %s / %s" % [objective.get("text",objective.get("label",objective.get("type","目标"))),objective.get("current",0),objective.get("target",1)])
				else: words(str(objective))
		if quest.get("can_claim",false):
			var id:String=quest.id
			button(body,"领取奖励" if runtime.zone=="town" else "回城后交付",func(): var result:Dictionary=runtime.adventure.claim_quest(id); runtime.say(str(result.get("message",""))); refresh(),runtime.zone=="town")
		body.add_child(HSeparator.new())
	words("任务可同时推进。未接取的任务请先与镇民交谈；分支承诺会保留在存档里。",Color("91a9bd"))

func render_network() -> void:
	words("不同线索、承诺与任务结果相互连接。选择一条解决路线后，其他互斥路线会锁定。",Color("c9d6e3"))
	var graph:=preload("narrative_graph.gd").new()
	graph.graph=runtime.adventure.narrative_graph()
	graph.custom_minimum_size=Vector2(992,440)
	graph.node_selected.connect(func(data): message.text=str(data.get("title",""))+"："+str(data.get("description","")))
	body.add_child(graph)
	words("点击节点查看完整说明。亮金：已完成  ·  青色：进行中 / 可用  ·  灰色：未解锁  ·  红色：互斥锁定",Color("a2bed0"),16)

func render_trade() -> void:
	if runtime.zone!="town":
		words("商店与锻造只在城镇开放。")
		return
	words("铜币 %d · 木料 %d · 碎布 %d · 秘银碎屑 %d" % [runtime.stage.loot.materials["旧铜币"],runtime.stage.loot.materials["木料"],runtime.stage.loot.materials["碎布"],runtime.stage.loot.materials["秘银碎屑"]],Color("f7d78e"),21)
	for item in runtime.adventure.shop_rows():
		var id:String=item.id
		button(body,"%s · %s · 已持有 %s" % [item.get("name",id),format_cost(item.get("cost",{})),str(item.get("owned",0))],func(): var result:Dictionary=runtime.adventure.buy(id); runtime.say(str(result.get("message",""))); refresh(),bool(item.get("can_buy",false)))
		if not str(item.get("reason","")).is_empty(): words(str(item.reason),Color("91a9bd"),16)
	words("锻造与调配",Color("f7d78e"),21)
	for recipe in runtime.adventure.recipe_rows():
		var id:String=recipe.id
		words(format_cost(recipe.get("cost",{})))
		button(body,str(recipe.get("name",id)),func(): var result:Dictionary=runtime.adventure.craft(id); runtime.say(str(result.get("message",""))); refresh(),bool(recipe.get("can_craft",false)))

func format_cost(cost: Dictionary) -> String:
	var result:Array[String]=[]
	for key in cost: result.append("%s ×%d" % [key,int(cost[key])])
	return " / ".join(result)

func render_saves() -> void:
	words("安全检查点 · 自动保存每 45 秒检查一次",Color("f7d78e"),22)
	words("可在城镇或清场后存档。战斗中暂停会冻结敌人，但不能保存到攻击中途。读档会恢复当前槽中的角色、任务、宝箱与地面掉落。")
	var slots:Array=runtime.saves.list_slots()
	for index in range(1,4):
		var slot:=index
		var metadata:Dictionary={}
		for entry in slots:
			if int(entry.get("slot",0))==slot: metadata=entry
		var r:=row()
		var label:=Label.new()
		var meta:Dictionary=metadata.get("metadata",{})
		var date:=Time.get_datetime_string_from_unix_time(int(meta.updated_at)).replace("T"," ")+" UTC" if meta.has("updated_at") else "空槽" if not metadata.get("exists",false) else "读取异常"
		label.text="存档 %d%s  %s" % [slot," · 自动保存" if slot==runtime.current_slot and runtime.autosave_armed else "",date]
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		r.add_child(label)
		button(r,"保存",func():
			if overwrite_slot!=slot and not metadata.is_empty() and metadata.get("exists",true):
				overwrite_slot=slot
				message.text="再次点击保存，确认覆盖存档 %d。" % slot
				return
			runtime.save_game(slot)
			overwrite_slot=0
			refresh(),runtime.safe_to_save())
		button(r,"读取",func(): runtime.load_game(slot))
	words("Mac / Windows 共用存档格式；保存在各系统的 Godot user:// 目录。网页存档留在当前浏览器的站点数据中，清理站点数据会丢失。",Color("91a9bd"),17)

func render_campaigns() -> void:
	words("已安装战役",Color("f7d78e"),23)
	words("切换战役会结束当前会话，但不会自动加载、复制或覆盖任何存档。每个生成战役拥有独立三槽存档。",Color("c9d6e3"),17)
	var bridge=runtime.workbench_bridge
	if bridge==null:
		words("战役服务不可用。",Color("ef9a9a"))
		return
	var library:Dictionary=bridge.list_campaigns()
	var context:Dictionary=library.get("active_context",{})
	words("当前内容：%s  ·  %s" % ["官方战役" if context.get("kind")=="official" else "自定义战役",str(context.get("campaign_id","未知"))],Color("a8ded7"),18)
	if not library.get("ok",false) and library.get("campaigns",[]).is_empty():
		words("无法读取战役库："+"；".join(library.get("errors",[])),Color("ef9a9a"))
		return
	if library.get("truncated",false):
		words("战役数量超过安全展示上限，仅显示前 256 个有效目录。",Color("efc879"),16)
	for entry in library.get("campaigns",[]):
		if not entry is Dictionary: continue
		var campaign:Dictionary=entry.duplicate(true)
		body.add_child(HSeparator.new())
		words(("● " if campaign.get("active",false) else "")+str(campaign.get("display_name",campaign.get("campaign_id","未命名战役"))),Color("f7d78e") if campaign.get("active",false) else Color("d5dfec"),21)
		words("%s / %s  ·  %s" % [campaign.get("project_id",""),campaign.get("campaign_id",""),"官方内容" if campaign.get("kind")=="official" else "来源 "+str(campaign.get("source_draft_id","未知"))],Color("91a9bd"),15)
		if campaign.get("available",false):
			words(_campaign_slots_text(campaign.get("slots",[])),Color("a9bccd"),16)
			var label:=("重新开始此战役 · " if campaign.get("active",false) else "预览并开始 · ")+str(campaign.get("display_name",campaign.get("campaign_id","")))
			button(body,label,func(): _preview_campaign(campaign))
		else:
			words("战役包损坏或不完整："+"；".join(campaign.get("errors",[])),Color("ef9a9a"),16)
			button(body,"不可启动",func(): pass,false)
	if not campaign_launch_preview.is_empty():
		body.add_child(HSeparator.new())
		words("确认开始新会话",Color("efc879"),23)
		words("即将结束当前会话并启动「%s」。请先在“存档”页保存需要保留的进度。此次操作不会自动读取目标战役的存档。" % campaign_launch_preview.get("display_name","所选战役"),Color("f2d7aa"),18)
		words("目标存档："+str(campaign_launch_preview.get("save_directory","")),Color("91a9bd"),15)
		var actions:=row()
		button(actions,"确认结束当前会话并启动",_confirm_campaign_launch)
		button(actions,"取消",func(): campaign_launch_preview={}; message.text="已取消战役切换"; refresh())

func _campaign_slots_text(slots: Array) -> String:
	var summaries:Array[String]=[]
	for entry in slots:
		if not entry is Dictionary: continue
		var slot:=int(entry.get("slot",0))
		if not entry.get("exists",false):
			summaries.append("槽 %d：空" % slot)
		elif not entry.get("ok",false):
			summaries.append("槽 %d：异常" % slot)
		else:
			var updated:=int(entry.get("updated_at",0))
			var date:=Time.get_datetime_string_from_unix_time(updated).replace("T"," ")+" UTC" if updated>0 else "已有存档"
			summaries.append("槽 %d：%s%s" % [slot,date,"（备份恢复）" if entry.get("recovered",false) else ""])
	return "  ·  ".join(summaries) if not summaries.is_empty() else "暂无可用存档信息"

func _preview_campaign(campaign: Dictionary) -> void:
	var result:Dictionary
	if campaign.get("kind")=="official":
		result=runtime.workbench_bridge.preview_official_launch()
	else:
		result=runtime.workbench_bridge.preview_campaign_launch(str(campaign.get("project_id","")),str(campaign.get("campaign_id","")))
	if not result.get("ok",false):
		campaign_launch_preview={}
		message.text="无法预览战役："+"；".join(result.get("errors",[]))
		refresh()
		return
	campaign_launch_preview=result.duplicate(true)
	message.text="已完成启动前复检；确认后才会结束当前会话。"
	refresh()

func _confirm_campaign_launch() -> void:
	if campaign_launch_preview.is_empty() or runtime.workbench_bridge==null: return
	var preview:=campaign_launch_preview.duplicate(true)
	var result:Dictionary
	if preview.get("kind")=="official":
		result=runtime.workbench_bridge.start_official_session()
	else:
		result=runtime.workbench_bridge.start_campaign_session(str(preview.get("project_id","")),str(preview.get("campaign_id","")),str(preview.get("launch_token","")))
	if not result.get("ok",false):
		message.text="战役启动失败："+"；".join(result.get("errors",[]))
		campaign_launch_preview={}
		refresh()
		return
	message.text="正在结束当前会话并载入战役……"
	overlay.hide()

func render_settings() -> void:
	var volume:=HSlider.new()
	volume.min_value=0
	volume.max_value=1
	volume.step=.05
	volume.value=runtime.controls.master_volume
	words("音量（攻击 / 命中 / 拾取提示音）")
	body.add_child(volume)
	volume.value_changed.connect(func(value): runtime.controls.master_volume=value; runtime.controls.apply(); runtime.controls.save_settings())
	var shake:=CheckButton.new()
	shake.text="命中时镜头震动"
	shake.button_pressed=runtime.controls.screen_shake
	shake.toggled.connect(func(value): runtime.controls.screen_shake=value; runtime.controls.save_settings())
	body.add_child(shake)
	if not OS.has_feature("web"):
		var full:=CheckButton.new()
		full.text="全屏"
		full.button_pressed=runtime.controls.fullscreen
		full.toggled.connect(func(value): runtime.controls.fullscreen=value; runtime.controls.apply(); runtime.controls.save_settings())
		body.add_child(full)
	words("按键设置 · 点击后按新的字母 / 数字 / 空格",Color("f7d78e"),21)
	var grid:=GridContainer.new()
	grid.columns=3
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",8)
	body.add_child(grid)
	for action in runtime.controls.DEFAULTS:
		var id:String=action
		var b:=button(grid,runtime.controls.TITLES[id]+"  ["+runtime.controls.key_name(id)+"]",func(): capture_action=id; message.text="请按新按键，Esc 取消")
		b.custom_minimum_size.x=310
	button(body,"恢复默认按键",func(): runtime.controls.keys=runtime.controls.DEFAULTS.duplicate(); runtime.controls.save_settings(); refresh())

func capture_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo: return true
	var key:=int(event.physical_keycode if event.physical_keycode!=0 else event.keycode)
	if key==KEY_ESCAPE:
		capture_action=""
		message.text="已取消修改"
		return true
	if runtime.controls.rebind(capture_action,key):
		runtime.controls.save_settings()
		capture_action=""
		message.text="按键已更新"
		refresh()
	else: message.text=runtime.controls.error
	return true

func render_dialogue() -> void:
	var data:Dictionary=runtime.adventure.dialogue_for(npc_id)
	if npc_portrait is Texture2D:
		var portrait:=TextureRect.new()
		portrait.texture=npc_portrait
		portrait.custom_minimum_size=Vector2(180,140)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		body.add_child(portrait)
	words(str(data.get("name",npc_id)),Color("f7d78e"),24)
	words(str(data.get("text","")))
	for choice in data.get("choices",[]):
		var id:String=choice.id
		var enabled:=bool(choice.get("enabled",true))
		button(body,str(choice.get("label",id))+(" · "+str(choice.get("reason","")) if not enabled else ""),func(): runtime.choose_dialogue(id),enabled)
