extends Node
## Composition root: scene nodes are views; only explicit snapshots cross scenes/saves.
const SaveStore = preload("core/save_store.gd")
const Progression = preload("core/progression.gd")
const Adventure = preload("adventure/adventure_state.gd")
const Encounters = preload("encounters/encounters.gd")
const Registry = preload("world_registry.gd")
const Settings = preload("game_settings.gd")
const EventBus = preload("event_bus.gd")
const TalentTree = preload("core/talent_tree.gd")
const BOONS := {
	"edge":{"name":"锋刃祝福","text":"本次试炼近战伤害 +8","stats":{"attack":8.0}},
	"ward":{"name":"守护祝福","text":"本次试炼生命上限 +25、护甲 +2","stats":{"health":25.0,"defense":2.0}},
	"arcane":{"name":"魔能祝福","text":"本次试炼法术伤害 +10、回蓝 +2","stats":{"magic":10.0,"regen":2.0}},
	"fleet":{"name":"轻灵祝福","text":"本次试炼移速 +20、法力上限 +15","stats":{"speed":20.0,"mana":15.0}}
}
var stage
var saves = SaveStore.new()
var progression = Progression.new()
var adventure = Adventure.new()
var encounters = Encounters.new()
var controls = Settings.new()
var events = EventBus.new()
var talents = TalentTree.new()
var audio = preload("game_audio.gd").new()
var panel
var party_hud
var zone := "town"
var worlds: Dictionary = {}
var run_state: Dictionary = {"phase":"none","wave":0,"seed":1,"boons":[],"offers":[]}
var companion_recruited := false
var companion_mode := "follow"
var current_slot := 1
var play_seconds := 0.0
var autosave_elapsed := 0.0
var death_pending := false
var transitioning := false
var persistence_enabled := true
var loaded_message := ""
var run_counter := 0
var autosave_armed := false
var last_autosave_error := ""
var content_registry = null
var workbench_bridge = null

func setup(map_stage) -> void:
	stage=map_stage
	content_registry=stage.get_node_or_null("/root/ContentRegistry")
	workbench_bridge=stage.get_node_or_null("/root/WorkbenchBridge")
	if content_registry != null: stage.knight.content_registry_override=content_registry
	if workbench_bridge != null: workbench_bridge.bind_runtime(self)
	zone=str(stage.contract.get("zone_id","town"))
	add_child(audio)
	add_child(encounters)
	encounters.setup(stage)
	# Companion is optional; passive alone should never spawn an unrecruited ally.
	encounters.set_companion(companion_mode)
	encounters.set_companion_enabled(false)
	adventure.set_up(stage.knight.equipment,stage.loot,progression)
	adventure.notice.connect(say)
	adventure.changed.connect(_adventure_changed)
	progression.changed.connect(refresh_bonuses)
	talents.changed.connect(refresh_bonuses)
	events.event_emitted.connect(_on_event)
	stage.loot.crate_destroyed.connect(func(id): events.publish("crate_destroyed",{"id":zone+":"+id}))
	stage.loot.collected.connect(_on_collected)
	stage.loot.chest_opened.connect(func(id): events.publish("chest_opened",{"id":zone+":"+id}))
	stage.knight.died.connect(func(): death_pending=true)
	stage.knight.equipment.changed.connect(func(): events.publish("equipment_changed"))
	encounters.enemy_defeated.connect(_enemy_defeated)
	encounters.wave_cleared.connect(_wave_cleared)
	encounters.notice.connect(say)
	controls.load_settings()
	controls.changed.connect(sync_keys)
	sync_keys()
	for arg in OS.get_cmdline_args():
		if arg=="--script": persistence_enabled=false
	var bridge=stage.get_node_or_null("/root/GameSession")
	if bridge != null and not bridge.pending.is_empty():
		var incoming: Dictionary=bridge.take()
		if not restore(incoming): say("场景数据恢复失败，已保留当前场景")
	else:
		stage.loot.materials["旧铜币"]=30
		stage.knight.refresh_equipment()
		# A fresh launch must never overwrite a previous character automatically.
		for slot in saves.list_slots():
			if not slot.exists:
				current_slot=int(slot.slot)
				autosave_armed=true
				break
	panel=preload("session_panel.gd").new()
	stage.add_child(panel)
	panel.setup(self)
	stage.interface.external_modal=panel.is_open
	stage.interface.close_external=panel.close
	party_hud=preload("party_hud.gd").new()
	stage.add_child(party_hud)
	party_hud.setup(self)
	if zone=="ruins":
		var backdrop=stage.get_node_or_null("CourtyardBackdrop")
		if backdrop != null: backdrop.modulate=Color(.65,.77,.95)
		panel.open("adventure")
	events.publish("zone_entered",{"id":zone})
	say("L 冒险手册 · Esc 暂停 / 存档 · 4/5 药水。先找艾琳或雷恩聊聊。" if zone=="town" else "古塔试炼场 · 在冒险手册选择开始本轮")

func say(text: String) -> void:
	stage.notice=text
	if panel != null: panel.message.text=text

func sync_keys() -> void:
	stage.skill_bar.key_names={"crescent":controls.key_name("skill1"),"rising":controls.key_name("skill2"),"trinity":controls.key_name("skill3"),"spell":controls.key_name("spell")}

func _adventure_changed() -> void:
	refresh_bonuses()

func refresh_bonuses() -> void:
	stage.knight.progression_bonuses=progression.bonuses()
	var talent_bonus:Dictionary=talents.bonuses()
	for id in talent_bonus:
		stage.knight.progression_bonuses[id]=float(stage.knight.progression_bonuses.get(id,0))+float(talent_bonus[id])
	var bonus: Dictionary={}
	if zone=="ruins":
		for id in run_state.get("boons",[]):
			if BOONS.has(id):
				for stat in BOONS[id].stats:
					bonus[stat]=float(bonus.get(stat,0))+float(BOONS[id].stats[stat])
	stage.knight.run_bonuses=bonus
	stage.knight.refresh_equipment()

func _on_event(kind: String, data: Dictionary) -> void:
	adventure.record_event(kind,data)

func _on_collected(id: String, amount: int, gear: bool) -> void:
	if not gear: events.publish("material_collected",{"id":id,"amount":amount})
	audio.play("loot")

func _enemy_defeated(data: Dictionary) -> void:
	var identity:=str(run_state.seed)+":"+str(data.get("id","enemy"))
	events.publish("enemy_killed",{"id":identity,"kind":data.get("kind", "melee")})
	if str(data.get("kind",""))=="boss":
		events.publish("boss_killed",{"id":identity})
	var before: int=progression.level
	progression.add_xp(int(data.get("xp",15)))
	refresh_bonuses()
	if progression.level>before: audio.play("level")
	var p: Array=data.get("foot",[stage.foot.x,stage.foot.y])
	var drop_foot:=Vector2(float(p[0]),float(p[1]))
	stage.loot.spawn_drop("旧铜币",int(data.get("gold",5)),drop_foot,false)
	for drop in data.get("drops",[]):
		var id:=str(drop.get("id",""))
		if stage.knight.equipment.CATALOG.has(id):
			stage.loot.spawn_drop(id,int(drop.get("count",1)),drop_foot+Vector2(.35,.2),true)
		elif stage.loot.materials.has(id):
			stage.loot.spawn_drop(id,int(drop.get("count",1)),drop_foot+Vector2(-.3,.2),false)

func _wave_cleared(wave: int) -> void:
	events.publish("wave_cleared",{"id":str(run_state.seed)+":"+str(wave),"wave":wave})
	if wave>=3:
		run_state.phase="victory"
		run_state.offers=[]
		say("试炼完成！拾取战利品后回城，向委托人领取奖励。")
	else:
		run_state.phase="boon"
		var rng:=RandomNumberGenerator.new()
		rng.seed=int(run_state.seed)+wave*104729
		var pool: Array=BOONS.keys()
		var offers: Array=[]
		while offers.size()<3:
			var index:=rng.randi_range(0,pool.size()-1)
			offers.append(pool.pop_at(index))
		run_state.offers=offers
		say("本轮已清场。L 选择一项祝福，再开始下一轮。")
	# Do not interrupt picking up loot with an automatically opened modal.
	if persistence_enabled and autosave_armed: save_game(current_slot,true)

func start_trial(seed_value: int = 0) -> bool:
	if zone!="town" or stage.knight.defeated: return false
	run_counter+=1
	var seed_number:=seed_value if seed_value>0 else int(Time.get_unix_time_from_system())+run_counter*7919
	run_state={"phase":"ready","wave":0,"seed":seed_number,"boons":[],"offers":[]}
	worlds.erase("ruins")
	return travel("ruins")

func start_wave() -> bool:
	if zone!="ruins" or run_state.phase!="ready" or encounters.active: return false
	var next:=int(run_state.wave)+1
	if next<1 or next>3: return false
	if not encounters.begin_wave(next,int(run_state.seed)+next): return false
	run_state.wave=next
	run_state.phase="combat"
	panel.close()
	say("第 %d / 3 轮 · 留意敌人的红色攻击预警" % next)
	return true

func choose_boon(id: String) -> bool:
	if run_state.phase!="boon" or id not in run_state.offers: return false
	run_state.boons.append(id)
	run_state.offers=[]
	run_state.phase="ready"
	refresh_bonuses()
	stage.knight.health=minf(stage.knight.max_health,stage.knight.health+20)
	stage.knight.mana=minf(stage.knight.max_mana,stage.knight.mana+25)
	stage.knight.stats_changed.emit(stage.knight.health,stage.knight.mana)
	say("获得"+str(BOONS[id].name)+"，恢复少量生命与法力。")
	if persistence_enabled and autosave_armed: save_game(current_slot,true)
	return true

func return_town() -> bool:
	if zone!="ruins": return false
	encounters.clear()
	run_state.phase="none"
	run_state.boons=[]
	run_state.offers=[]
	stage.knight.reset_character()
	return travel("town")

func prepare_transfer(target: String) -> Dictionary:
	if not Registry.ZONES.has(target): return {}
	var data:=snapshot()
	data.zone=target
	var map_data:=Registry.load_zone(target)
	data.player.foot=[map_data.spawn.x,map_data.spawn.depth]
	data.player.height=0.0
	data.player.health=stage.knight.max_health if target=="town" else stage.knight.health
	data.player.mana=stage.knight.max_mana if target=="town" else stage.knight.mana
	return data

func travel(target: String) -> bool:
	if transitioning or not Registry.ZONES.has(target): return false
	var bridge=stage.get_node_or_null("/root/GameSession")
	if bridge==null or get_tree().current_scene != stage:
		say("场景路由只在正式游戏主场景运行")
		return false
	bridge.pending=prepare_transfer(target)
	bridge.target_zone=target
	transitioning=true
	get_tree().call_deferred("change_scene_to_file","res://stage.tscn")
	return true

func safe_to_save() -> bool:
	return not transitioning and not stage.knight.defeated and not encounters.active and stage.grounded and stage.knight.is_locomotion() and stage.projectiles.is_empty()

func snapshot() -> Dictionary:
	worlds[zone]=stage.loot.snapshot_world()
	return {"schema":1,"zone":zone,"worlds":worlds.duplicate(true),"player":{"foot":[stage.foot.x,stage.foot.y],"height":stage.height_z,"health":stage.knight.health,"mana":stage.knight.mana,"facing":stage.knight.facing},"equipment":{"owned":stage.knight.equipment.owned.duplicate(),"equipped":stage.knight.equipment.equipped.duplicate()},"materials":stage.loot.materials.duplicate(),"progression":progression.snapshot(),"talents":talents.snapshot(),"adventure":adventure.snapshot(),"run":run_state.duplicate(true),"companion":{"recruited":companion_recruited,"mode":companion_mode,"state":encounters.companion_snapshot()},"content":content_registry.export_runtime_state() if content_registry != null else {},"play_seconds":play_seconds,"run_counter":run_counter,"slot":current_slot,"autosave_armed":autosave_armed}

func whole(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value))==float(value) and float(value)>=low and float(value)<=high

func validate_snapshot(data: Dictionary) -> bool:
	if not whole(data.get("schema"),1,1) or not data.get("zone") is String or not Registry.ZONES.has(data.zone): return false
	for field in ["worlds","player","equipment","materials","progression","adventure","run","companion"]:
		if not data.get(field) is Dictionary: return false
	var p: Dictionary=data.player
	if not p.get("foot") is Array or p.foot.size()!=2: return false
	for value in p.foot+[p.get("height",0),p.get("health",0),p.get("mana",0)]:
		if not (value is float or value is int) or not is_finite(float(value)): return false
	if not data.equipment.get("owned") is Array or not data.equipment.get("equipped") is Dictionary: return false
	if data.equipment.equipped.size()!=stage.knight.equipment.SLOTS.size() or data.equipment.owned.size()>stage.knight.equipment.CATALOG.size(): return false
	var seen: Array=[]
	for id in data.equipment.owned:
		if not id is String or not stage.knight.equipment.CATALOG.has(id) or id in seen: return false
		seen.append(id)
	for slot in stage.knight.equipment.SLOTS:
		if not data.equipment.equipped.has(slot): return false
		var id=data.equipment.equipped.get(slot,"")
		if not id is String: return false
		if id!="" and (id not in data.equipment.owned or stage.knight.equipment.CATALOG[id].slot!=slot): return false
	for id in data.materials:
		var value=data.materials[id]
		if not stage.loot.materials.has(id) or not whole(value,0,999999): return false
	var trial: Dictionary=data.run
	if trial.get("phase","") not in ["none","ready","boon","victory","combat","defeat"]: return false
	if not trial.get("boons") is Array or not trial.get("offers") is Array or trial.boons.size()>3 or trial.offers.size()>3: return false
	for id in trial.boons+trial.offers:
		if not BOONS.has(id): return false
	if not whole(trial.get("wave"),0,3) or not whole(trial.get("seed"),1,9007199254740991): return false
	if not whole(p.get("facing"),-1,1) or int(p.facing)==0: return false
	if float(p.height)<0 or float(p.height)>20 or float(p.health)<=0 or float(p.health)>100000 or float(p.mana)<0 or float(p.mana)>100000: return false
	if not whole(data.get("slot",1),1,3) or not whole(data.get("run_counter",0),0,1000000): return false
	var played=data.get("play_seconds",0)
	if not (played is int or played is float) or not is_finite(float(played)) or float(played)<0 or float(played)>1e10: return false
	if not data.companion.get("recruited") is bool or not data.get("autosave_armed",false) is bool: return false
	if data.has("content"):
		var registry=_content_registry()
		if registry==null or not data.content is Dictionary or not registry.validate_runtime_state(data.content).is_empty(): return false
	if data.companion.get("mode","") not in ["follow","guard","passive"]: return false
	if data.companion.has("state"):
		if not data.companion.state is Dictionary or data.companion.state.is_empty() or not encounters.validate_companion(data.companion.state): return false
		if data.companion.state.get("enabled",false)!=data.companion.recruited: return false
		if data.companion.state.get("mode","follow")!=data.companion.mode: return false
	for id in data.worlds:
		if not Registry.ZONES.has(id) or not data.worlds[id] is Dictionary: return false
		var world: Dictionary=data.worlds[id]
		for key in ["broken","opened","drops"]:
			if not world.get(key) is Array or world[key].size()>500: return false
		for entry in world.broken+world.opened:
			if not entry is String: return false
		for drop in world.drops:
			if not drop is Dictionary or not drop.get("foot") is Array or drop.foot.size()!=2: return false
			if not drop.get("id") is String or not drop.get("equipment") is bool or not whole(drop.get("amount"),1,9999): return false
			if drop.equipment and not stage.knight.equipment.CATALOG.has(drop.id): return false
			if not drop.equipment and not stage.loot.materials.has(drop.id): return false
			for value in drop.foot:
				if not (value is float or value is int) or not is_finite(float(value)): return false
	var check_progression=Progression.new()
	if not check_progression.restore(data.progression): return false
	if not data.get("talents",{}) is Dictionary: return false
	var check_talents=TalentTree.new()
	if data.has("talents") and not check_talents.restore(data.talents): return false
	if check_talents.spent_points()+check_progression.skill_points!=check_progression.level-1: return false
	var check_adventure=Adventure.new()
	check_adventure.set_up(stage.knight.equipment,stage.loot,check_progression)
	if not check_adventure.restore(data.adventure): return false
	return true

func restore(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	# Validation completes before changing any current gameplay state.
	var registry=_content_registry()
	if registry!=null:
		var content_state: Dictionary=data.get("content",registry.empty_runtime_state())
		if not registry.restore_runtime_state(content_state): return false
	encounters.clear()
	progression.restore(data.progression)
	talents.restore(data.get("talents",TalentTree.new().snapshot()))
	adventure.restore(data.adventure)
	stage.knight.equipment.owned=data.equipment.owned.duplicate()
	stage.knight.equipment.equipped=data.equipment.equipped.duplicate()
	for id in stage.loot.materials: stage.loot.materials[id]=int(data.materials.get(id,0))
	worlds=data.worlds.duplicate(true)
	zone=str(data.zone)
	run_state=data.run.duplicate(true)
	companion_recruited=bool(data.companion.get("recruited",false))
	companion_mode=str(data.companion.mode)
	current_slot=clampi(int(data.get("slot",1)),1,3)
	play_seconds=maxf(0,float(data.get("play_seconds",0)))
	run_counter=maxi(0,int(data.get("run_counter",0)))
	autosave_armed=bool(data.get("autosave_armed",false))
	stage.loot.restore_world(worlds.get(zone,{"broken":[],"opened":[],"drops":[]}))
	refresh_bonuses()
	stage.knight.reset_character()
	stage.knight.health=clampf(float(data.player.health),1,stage.knight.max_health)
	stage.knight.mana=clampf(float(data.player.mana),0,stage.knight.max_mana)
	stage.knight.facing=1 if int(data.player.get("facing",1))>=0 else -1
	stage.foot=Vector2(float(data.player.foot[0]),float(data.player.foot[1]))
	var height:=maxf(0,float(data.player.get("height",0)))
	var ground: Dictionary=stage.Physics.support(stage.volumes,stage.foot,height+stage.Physics.STEP)
	if not stage.bounds.has_point(stage.foot) or not ground.valid or stage.Physics.blocked(stage.volumes,stage.foot,float(ground.z)):
		stage.foot=Vector2(stage.contract.spawn.x,stage.contract.spawn.depth)
		ground=stage.Physics.support(stage.volumes,stage.foot)
	stage.height_z=float(ground.z)
	stage.grounded=true
	stage.vertical_speed=0
	stage.platform=str(ground.platform)
	stage.last_safe=stage.foot
	stage.sprint.reset()
	stage.hit_pause=0
	stage.shake_left=0
	for projectile in stage.projectiles: projectile.node.queue_free()
	stage.projectiles.clear()
	stage.loot.pending_equipment.clear()
	stage.knight.equipment.changed.emit()
	stage.knight.stats_changed.emit(stage.knight.health,stage.knight.mana)
	stage.foot_node.position=stage.project(stage.foot)
	stage.knight.position=Vector2(0,-stage.height_z*stage.ppm)
	stage.camera.position=Vector2(clampf(stage.foot.x*stage.ppm,640,2432),clampf(stage.project(stage.foot).y-220,400,570))
	encounters.set_companion_enabled(companion_recruited)
	encounters.set_companion(companion_mode)
	var ally_state:Dictionary=data.companion.get("state",{})
	encounters.restore_companion(ally_state)
	# Older saves have no independent vitals; preserve their recruitment and orders.
	if ally_state.is_empty():
		encounters.set_companion_enabled(companion_recruited)
		encounters.set_companion(companion_mode)
	return true

func rest_party() -> bool:
	if zone!="town" or stage.knight.defeated: return false
	var actor=stage.knight
	var ally:Dictionary=encounters.companion_status()
	var hero_needs_rest:bool=actor.health<actor.max_health or actor.mana<actor.max_mana
	var ally_needs_rest:bool=companion_recruited and (bool(ally.dead) or float(ally.hp)<float(ally.max_hp) or float(ally.mp)<float(ally.max_mp))
	if not hero_needs_rest and not ally_needs_rest:
		say("全队已经恢复到最佳状态。")
		return false
	if int(stage.loot.materials.get("旧铜币",0))<10:
		say("休息需要 10 铜币。")
		return false
	stage.loot.materials["旧铜币"]-=10
	actor.health=actor.max_health
	actor.mana=actor.max_mana
	actor.stats_changed.emit(actor.health,actor.mana)
	if companion_recruited: encounters.rest_companion()
	say("休整完毕，全队生命与法力已恢复；倒下的同伴已复苏。" if ally_needs_rest else "休整完毕，生命与法力已恢复。")
	return true

func save_game(slot: int = 1, automatic: bool = false) -> bool:
	if automatic and not autosave_armed: return false
	if slot<1 or slot>3: return false
	if not safe_to_save():
		if not automatic: say("战斗、跳跃或动作中不可存档；清场后可保存检查点。")
		return false
	var previous_slot:=current_slot
	current_slot=slot
	if not saves.save_slot(current_slot,snapshot()):
		current_slot=previous_slot
		say("存档失败："+saves.last_error)
		return false
	autosave_elapsed=0
	autosave_armed=true
	events.publish("saved",{"slot":current_slot})
	if not automatic: say("已保存到存档 %d" % current_slot)
	return true

func load_game(slot: int) -> bool:
	if encounters.active:
		say("战斗中请先撤退，或失败后读档。")
		return false
	var result: Dictionary=saves.load_slot(slot)
	if not result.ok or not validate_snapshot(result.get("data",{})):
		if result.ok: saves.protect_slot(slot,"Gameplay payload validation failed")
		say("无法读取存档："+str(result.get("error","内容校验失败")))
		return false
	var data: Dictionary=result.data
	if data.run.phase in ["combat","defeat"]:
		saves.protect_slot(slot,"Save is not a safe checkpoint")
		say("该存档不是安全检查点，未改变当前进度。")
		return false
	data.slot=slot
	data.autosave_armed=true
	if data.zone!=zone:
		var bridge=stage.get_node_or_null("/root/GameSession")
		if bridge==null or get_tree().current_scene!=stage: return false
		bridge.pending=data
		bridge.target_zone=data.zone
		transitioning=true
		get_tree().call_deferred("change_scene_to_file","res://stage.tscn")
	else:
		restore(data)
		panel.close()
	events.publish("loaded",{"slot":slot})
	say("已从备份恢复存档" if result.get("recovered",false) else "存档已读取")
	return true

func step(delta: float) -> void:
	if transitioning: return
	play_seconds+=delta
	if death_pending:
		death_pending=false
		run_state.phase="defeat"
		encounters.clear()
		events.publish("player_died",{"zone":zone})
		audio.play("hurt")
		panel.open("adventure")
		say("挑战失败。可保留已拾取的战利品回城，或读取上个检查点。")
		return
	encounters.step(delta)
	if workbench_bridge != null: workbench_bridge.process_pending()
	autosave_elapsed+=delta
	if autosave_elapsed>=45 and persistence_enabled and autosave_armed and safe_to_save():
		autosave_elapsed=0
		if not save_game(current_slot,true): autosave_armed=false

func _content_registry():
	if content_registry != null:
		return content_registry
	return get_node_or_null("/root/ContentRegistry")

func open_npc(npc: Dictionary) -> void:
	panel.npc_id=str(npc.id)
	panel.npc_portrait=npc.get("portrait")
	panel.open("dialogue")

func choose_dialogue(choice: String) -> void:
	var result: Dictionary=adventure.choose(panel.npc_id,choice)
	say(str(result.get("message","")))
	if not result.get("ok",false): return
	match str(result.get("action","")):
		"shop", "craft": panel.open("trade")
		"journal": panel.open("journal")
		"request_trial": panel.open("adventure")
		"recruit_companion":
			companion_recruited=true
			encounters.set_companion_enabled(true)
			encounters.set_companion(companion_mode)
			panel.refresh()
		_: panel.refresh()

func use_potion(id: String) -> bool:
	if stage.knight.defeated: return false
	var result: Dictionary=adventure.use_consumable(id,stage.knight)
	say(str(result.get("message","")))
	if result.get("ok",false): audio.play("loot")
	return bool(result.get("ok",false))

func handle_key(event: InputEventKey) -> bool:
	if panel.capture_action!="": return panel.capture_key(event)
	var code:=controls.canonical(event)
	if code==KEY_ESCAPE:
		if stage.interface.is_modal(): stage.interface.close_panels()
		else: panel.open("adventure")
		stage.sprint.reset()
		return true
	if panel.is_open():
		if code==KEY_L: panel.close()
		return true
	if code==KEY_L and not stage.interface.is_modal():
		panel.open("journal")
		return true
	if not stage.interface.is_modal() and code in [KEY_4,KEY_5]:
		use_potion("healing_potion" if code==KEY_4 else "mana_potion")
		return true
	return false
