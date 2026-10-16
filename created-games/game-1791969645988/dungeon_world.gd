extends RefCounted
const S=preload("res://spell_system.gd")
const E=preload("res://estate_system.gd")
const P=preload("res://progression_system.gd")
const D=preload("res://dungeon_system.gd")
const G=preload("res://equipment_system.gd")
const R=preload("res://retainer_system.gd")
const POS=[Vector2(350,430),Vector2(580,380),Vector2(520,555),Vector2(850,535),Vector2(1030,270)]
var game
func draw(owner_game) -> void:
	game=owner_game
	var c: Dictionary=game.character
	if c.zone=="wilds":
		gate("extra_enter",Vector2(1080,365),"万妖窟 · 10级")
		for i in range(2): draw_monster(i,[Vector2(700,360),Vector2(870,535)][i],"谷地妖狼 Lv.%d" % (10+i*2),dead(i),1.0)
	elif c.zone=="cavern":
		var run: Dictionary=c.dungeon.run
		for i in range(5): draw_monster(i,POS[i],"镇层妖王 Lv.%d" % (12+int(run.floor)*2) if i==4 else "窟中妖狼 Lv.%d" % (9+int(run.floor)*2),i in run.cleared,1.5 if i==4 else 1.0)
		gate("extra_exit",Vector2(140,590),"离开 · 保留进度")
		if run.cleared.size()==5:
			gate("extra_next" if int(run.floor)<3 else "extra_exit",Vector2(1120,580),"进入下一层" if int(run.floor)<3 else "通关 · 返回镇妖谷")
func gate(id: String, pos: Vector2, title: String) -> void:
	game.add_portal({"id":id,"position":pos,"label":title,"target":"wilds","spawn":Vector2(950,500),"level":10})
func draw_monster(index: int, pos: Vector2, title: String, defeated: bool, scale: float) -> void:
	var unit=game.actor(game.map_layer,7,pos,title+(" · 已击杀" if defeated else ""),scale)
	if defeated: unit.modulate=Color(0.35,0.35,0.35)
	game.click_area(unit,Rect2(-100,-90,200,122),game.travel.bind(pos+Vector2(-60,35),"extra:mob:"+str(index)),title)
func dead(index: int) -> bool:
	return int(Time.get_unix_time_from_system())<int(game.character.monster_respawns.get("wilds_%d" % index,0))
func status() -> String:
	var c: Dictionary=game.character
	D.normalize(c,int(Time.get_unix_time_from_system()))
	if c.zone=="wilds": return "镇妖谷 · 拜访镇妖使；右侧洞口进入万妖窟 · 今日剩余%d次（基础5次+已购%d次，UTC+8）" % [D.remaining(c),int(c.dungeon.bought)]
	if bool(c.dungeon.run.get("completed",false)): return "万妖窟 · 三层已通关！点击东南漩涡返回镇妖谷"
	if c.dungeon.run.cleared.size()==5: return "万妖窟 · 本层已平定，点击东南漩涡前往下一层"
	return "万妖窟 · 第%d/3层 · 已击败%d/5堆 · 先清四堆小怪，再挑战妖王" % [c.dungeon.run.floor,c.dungeon.run.cleared.size()]
func handle(action: String) -> void:
	if action.begins_with("mob:"): attack(int(action.get_slice(":",1))); return
	match action:
		"enter":
			D.normalize(game.character,int(Time.get_unix_time_from_system()))
			var continuing: bool=not game.character.dungeon.run.is_empty() and bool(game.character.dungeon.run.get("active",false))
			game.dialog("万妖窟",("已有未完成进度，可继续挑战，不额外消耗次数。" if continuing else "每天基础五次，可额外购买；进入新挑战消耗一次；三层各有四堆小怪和一位妖王。")+"\n今日剩余%d次（基础5次+已购%d次，UTC+8零点刷新）。" % [D.remaining(game.character),int(game.character.dungeon.bought)],"继续挑战" if continuing else "进入 · 消耗一次",enter)
			var options: VBoxContainer=game.modal.get_child(0)
			var sweep_button: Button=game.button(options,"速刷一次 · 1000灵石（消耗1次挑战）",confirm_sweep)
			sweep_button.disabled=int(game.character.dungeon.wins)<1
			sweep_button.tooltip_text="需先完整通关一次；花1000灵石并消耗1次今日挑战"
			game.button(options,"购买额外挑战 · 3000灵石/次",confirm_purchase)
		"next":
			var before: Dictionary=game.character.duplicate(true)
			var old_position: Vector2=game.player_pos
			if not D.next_floor(game.character): return
			game.player_pos=Vector2(200,540)
			if not game.persist(): game.character=before; game.player_pos=old_position; return
			game.show_world()
		"exit":
			var before: Dictionary=game.character.duplicate(true)
			var old_position: Vector2=game.player_pos
			if bool(game.character.dungeon.run.get("completed",false)): game.character.dungeon.run.active=false
			game.character.zone="wilds"; game.player_pos=Vector2(950,500)
			if not game.persist(): game.character=before; game.player_pos=old_position; return
			game.show_world()
func enter() -> void:
	var before: Dictionary=game.character.duplicate(true)
	var old_position: Vector2=game.player_pos
	if not D.enter(game.character,int(Time.get_unix_time_from_system())):
		game.dialog("暂不能进入","需达到10级，且今日新挑战尚有次数。明日UTC+8零点恢复。","知道了",game.close_dialog); return
	game.character.zone="cavern"; game.player_pos=Vector2(180,550)
	if not game.persist(): game.character=before; game.player_pos=old_position; game.dialog("存档失败",game.store.last_error,"返回",game.close_dialog); return
	game.close_dialog(); game.show_world()
func attack(index: int) -> void:
	var c: Dictionary=game.character
	if c.zone=="wilds":
		if index<0 or index>=2: return
		if dead(index): game.dialog("已经击杀","妖狼将在击杀30秒后重生。","知道了",game.close_dialog); return
		game.next_encounter={"zone":"wilds","id":index,"level":10+index*2,"count":3,"name":"谷地妖狼","hp":230+index*60,"damage":18+index*3,"kind":"wild","background":"res://assets/demon-valley.png"}
	elif c.zone=="cavern":
		if not D.ready(c,index): game.dialog("暂不能挑战","已击杀的怪物不会在本次副本重生；妖王需先击败本层四堆小怪。","知道了",game.close_dialog); return
		var floor:=int(c.dungeon.run.floor)
		game.next_encounter={"zone":"cavern","id":index,"level":(12+floor*2) if index==4 else (9+floor*2),"count":1 if index==4 else 3,"name":"镇层妖王" if index==4 else "窟中妖狼","hp":(400+floor*80) if index==4 else (180+floor*50),"damage":(25+floor*3) if index==4 else (16+floor*2),"kind":"dungeon","boss":index==4,"background":"res://assets/demon-cavern.png"}
	else: return
	game.start_battle(0)
func settle() -> void:
	var c: Dictionary=game.character
	var previous: Dictionary=c.duplicate(true)
	var spec: Dictionary=game.battle_spec
	var won: bool=game.enemy_hp==0
	var loot: Array=[]
	var reward: Dictionary=game.encounter_rewards(int(spec.level),int(spec.count),str(spec.kind))
	if spec.zone=="cavern": reward.xp=P.dungeon_xp(int(c.dungeon.run.floor),bool(spec.get("boss",false)))
	var credited:=false
	c.hp=maxi(int(game.combat_hp),1)
	if won:
		if spec.zone=="cavern": credited=D.win(c,int(spec.id))
		else:
			credited=not dead(int(spec.id))
			if credited: c.monster_respawns["wilds_%d" % int(spec.id)]=int(Time.get_unix_time_from_system())+30
		if credited:
			c.victories=int(c.victories)+1; c.stones=int(c.stones)+int(reward.stones)
			game.add_experience(int(reward.xp)); R.award_battle(c,int(reward.xp))
			loot=D.loot(c,bool(spec.get("boss",false)),int(spec.count),int(spec.level)) if spec.zone=="cavern" else G.roll_wild(c,int(spec.level),int(spec.count))
			if spec.zone=="wilds": loot.append_array(S.drop_wild(c,int(spec.count)))
			if spec.zone=="cavern" and bool(spec.get("boss",false)):
				var seed_id: String=["jade","violet","sun"][int(c.dungeon.run.floor)-1]
				var seed:=E.seed_item(seed_id,1)
				if not E.put(c.inventory,seed): c.pending_loot.append(seed)
				loot.append(seed)
	else: c.hp=game.max_hp()
	if not game.persist():
		game.character=previous
		game.dialog("结算保存失败",game.store.last_error+"；本次奖励未入账，请重试保存。","重试结算",retry_settlement)
		game.modal.get_child(0).get_child(3).queue_free()
		return
	var names: PackedStringArray=[]
	for item in loot: names.append(item.name)
	game.dialog("战斗胜利" if won else "战斗失利",("获得%d经验、%d灵石\n掉落：%s\n随行散修各获得%d经验。" % [reward.xp,reward.stones,"无" if names.is_empty() else "、".join(names),int(reward.xp)*2]) if credited else "未获得奖励，可返回地图再挑战。","确定 · 返回地图",game.return_from_battle)
	var box: VBoxContainer=game.modal.get_child(0)
	box.get_child(3).queue_free()

func retry_settlement() -> void:
	game.close_dialog()
	game.settled=false
	game.settle_battle()

func confirm_sweep() -> void:
	game.dialog("确认速刷万妖窟","消耗1000灵石和1次今日挑战，结算完整三层奖励：200经验、5160灵石、三种种子各1份及按原概率掷出的装备。", "确认速刷",sweep_once)
func confirm_purchase() -> void:
	game.dialog("购买额外挑战","花费3000灵石，增加1次今日挑战次数。额外次数当日有效，UTC+8零点重置。","确认购买",purchase_once)
func purchase_once() -> void:
	var before: Dictionary=game.character.duplicate(true)
	if not D.purchase(game.character,int(Time.get_unix_time_from_system())):
		game.dialog("购买失败","需达到10级并持有3000灵石。","返回",game.close_dialog); return
	if not game.persist(): game.character=before; game.dialog("保存失败",game.store.last_error,"返回",game.close_dialog); return
	game.dialog("购买成功","已增加1次挑战，今日剩余%d次。" % D.remaining(game.character),"返回副本入口",handle.bind("enter"))
	game.refresh_map()
func sweep_once() -> void:
	var before: Dictionary=game.character.duplicate(true)
	var reward:=D.sweep(game.character,int(Time.get_unix_time_from_system()))
	if reward.has("error"): game.character=before; game.dialog("无法速刷",reward.error,"返回",game.close_dialog); return
	game.character.hp=game.max_hp()
	if not game.persist(): game.character=before; game.dialog("保存失败",game.store.last_error+"；扣费、次数和奖励已回滚。","返回",game.close_dialog); return
	var names: PackedStringArray=[]
	for item in reward.loot: names.append(item.name)
	game.dialog("万妖窟速刷完成","花费1000灵石，消耗1次挑战。获得200经验、5160灵石、三种种子和%d件装备。\n随行散修各获400经验。满包物品在背包待领取。今日剩余%d次。" % [reward.loot.size()-3,D.remaining(game.character)],"确定",game.close_dialog)
	game.refresh_map()
