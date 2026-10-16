extends Control
const Holdem=preload("res://systems/holdem.gd")
const DDZ=preload("res://systems/doudizhu.gd")
const GOLD=Color("e6c58b")
const NAMES=Holdem.NAMES
var mode: String="holdem"
var poker=Holdem.new()
var ddz=DDZ.new()
var ui: Control
var motion: Control
var busy:=false
var settled:=true
var selected: Array=[]
var message: String="欢迎入座。五位牌友已就座，点击发牌开启六人德扑。"
var raise_box: SpinBox
var last_actor: int=-1
var npc_delay:=0.8
var board_visible_count:=0

func _ready() -> void:
	if get_tree().has_meta("npc_mode"): mode=get_tree().get_meta("npc_mode")
	var bg:=TextureRect.new()
	bg.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	bg.texture=preload("res://assets/salon.png")
	bg.size=Vector2(1280,720)
	bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	motion=preload("res://dealer_motion.gd").new()
	add_child(motion)
	ui=Control.new()
	add_child(ui)
	refresh()

func skin(color: Color, border: Color=Color("654c39")) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=color; s.border_color=border
	s.set_border_width_all(1); s.set_corner_radius_all(9)
	return s

func panel(pos: Vector2, dimensions: Vector2, color: Color=Color(0.06,0.04,0.05,0.94)) -> void:
	var p:=Panel.new()
	p.position=pos; p.size=dimensions
	p.mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",skin(color))
	ui.add_child(p)

func label(text: String, pos: Vector2, dimensions: Vector2, font_size: int=17, color: Color=GOLD) -> Label:
	var l:=Label.new()
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.text=text; l.position=pos; l.size=dimensions
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(l)
	return l

func button(text: String, pos: Vector2, dimensions: Vector2, callback: Callable, disabled: bool=false) -> Button:
	var b:=Button.new()
	b.text=text; b.position=pos; b.size=dimensions
	b.disabled=disabled
	b.add_theme_font_size_override("font_size",16)
	b.add_theme_color_override("font_color",GOLD)
	b.add_theme_stylebox_override("normal",skin(Color("241b20")))
	b.add_theme_stylebox_override("hover",skin(Color("634231"),GOLD))
	b.add_theme_stylebox_override("pressed",skin(Color("845a3b"),GOLD))
	b.add_theme_stylebox_override("disabled",skin(Color("19161a"),Color("353036")))
	b.pressed.connect(callback)
	ui.add_child(b)
	return b

func in_round() -> bool:
	return poker.active if mode=="holdem" else ddz.phase in ["bid","play"]

func current_actor() -> int:
	return poker.actor if mode=="holdem" else ddz.actor

func card(c: int, pos: Vector2, dimensions: Vector2=Vector2(68,90), hidden: bool=false, selectable: bool=false) -> void:
	var b:=Button.new()
	b.position=pos; b.size=dimensions
	var held:=selectable and selected.has(c)
	if held: b.position.y-=20
	var s:=skin(Color("4c1830") if hidden else Color("fff3de"),GOLD if held or hidden else Color("b9a27a"))
	s.set_border_width_all(3 if held else 1)
	for state in ["normal","hover","pressed"]: b.add_theme_stylebox_override(state,s)
	var face: String=""
	var red:=false
	if c>=52: face="小\n王" if c==52 else "大\n王"; red=c==53
	else:
		var r: int=c%13+1
		face=("A" if r==1 else (str(r) if r<=10 else ["J","Q","K"][r-11]))+"\n"+["♠","♥","♣","♦"][int(c/13)]
		red=int(c/13) in [1,3]
	b.text="◇\n◆" if hidden else face
	b.add_theme_font_size_override("font_size",20 if dimensions.x>=50 else 15)
	for state in ["font_color","font_hover_color","font_pressed_color"]:
		b.add_theme_color_override(state,GOLD if hidden else (Color("ad2d43") if red else Color("252532")))
	if selectable: b.pressed.connect(toggle.bind(c))
	else: b.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(b)

func seat(index: int, pos: Vector2) -> void:
	if mode=="holdem":
		holdem_seat(index,pos)
		return
	var turn:=in_round() and current_actor()==index
	panel(pos,Vector2(226,93),Color("443024") if turn else Color(0.06,0.04,0.05,0.94))
	var portrait:=TextureRect.new()
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	var atlas:=AtlasTexture.new()
	atlas.atlas=preload("res://assets/npc-portraits.png")
	var half: float=atlas.atlas.get_width()/2.0
	atlas.region=Rect2((index-1)*half,0,half,atlas.atlas.get_height())
	portrait.texture=atlas
	portrait.position=pos+Vector2(8,10); portrait.size=Vector2(56,56)
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(portrait)
	var role: String="进攻型" if index==1 else "稳健型"
	var info: String="筹码 %d"%poker.stacks[index]
	var action_text: String=poker.last_action[index]
	if mode=="doudizhu":
		role="待定" if ddz.landlord<0 else ("地主" if index==ddz.landlord else "农民")
		info="余 %d 张 · 积分 %+d"%[ddz.hands[index].size(),ddz.scores[index]]
		action_text=ddz.last_action[index]
	label(NAMES[index]+"  ·  "+role,pos+Vector2(74,10),Vector2(146,25),18)
	label(info,pos+Vector2(74,37),Vector2(146,23),15)
	label(("思考中… " if turn and busy else "")+action_text,pos+Vector2(12,66),Vector2(210,22),13,Color("d9c6b4"))
	if mode=="holdem" and poker.holes[index].size()==2:
		for j in 2: card(poker.holes[index][j],pos+Vector2(43+j*65,103),Vector2(58,78),not poker.show_cards or poker.folded[index])
	elif mode=="doudizhu" and not ddz.hands[index].is_empty():
		for j in 3: card(0,pos+Vector2(62+j*24,103),Vector2(40,58),true)

func holdem_seat(index: int, pos: Vector2) -> void:
	var turn: bool=poker.active and poker.actor==index
	var tint:=Color("443024") if turn else Color(0.06,0.04,0.05,0.94)
	panel(pos,Vector2(226,132),tint)
	var portrait:=TextureRect.new()
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	if index<=2:
		var atlas:=AtlasTexture.new()
		atlas.atlas=preload("res://assets/npc-portraits.png")
		var half: float=atlas.atlas.get_width()/2.0
		atlas.region=Rect2((index-1)*half,0,half,atlas.atlas.get_height())
		portrait.texture=atlas
	else:
		var portraits=[preload("res://assets/npc-laozhou.png"),preload("res://assets/npc-linwei.png"),preload("res://assets/npc-akai.png")]
		portrait.texture=portraits[index-3]
	portrait.position=pos+Vector2(10,8); portrait.size=Vector2(60,60)
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(portrait)
	label(NAMES[index]+" · "+Holdem.STYLES[index],pos+Vector2(79,10),Vector2(141,26),16)
	label("筹码 %d"%poker.stacks[index],pos+Vector2(79,38),Vector2(141,24),16)
	var status: String=poker.last_action[index]
	if poker.active and poker.stacks[index]==0 and not poker.folded[index]: status="全下 · 等待摊牌"
	if turn: status="思考中…" if busy else "正在行动"
	label(status,pos+Vector2(12,70),Vector2(122,45),14,Color("fff1db") if turn else Color("c6b3a2"))
	if index==poker.button: label("D",pos+Vector2(12,111),Vector2(25,20),13)
	if poker.holes[index].size()==2:
		for j in 2: card(poker.holes[index][j],pos+Vector2(137+j*39,70),Vector2(34,50),not poker.show_cards or poker.folded[index])

func refresh() -> void:
	for child in ui.get_children():
		ui.remove_child(child); child.queue_free()
	panel(Vector2(20,18),Vector2(410,80))
	label("绯夜 · NPC 牌桌",Vector2(42,27),Vector2(370,40),28)
	label("THE MAHOGANY CLUB  /  私人牌局",Vector2(43,68),Vector2(360,22),13)
	panel(Vector2(930,18),Vector2(330,80))
	label("德州扑克 · 六人桌" if mode=="holdem" else "斗地主 · 三人桌",Vector2(950,31),Vector2(290,30),22)
	label("虚拟筹码  /  NPC 本地对局",Vector2(950,66),Vector2(290,22),13)
	panel(Vector2(20,120),Vector2(262,584))
	label("常驻牌桌",Vector2(40,133),Vector2(220,30),20)
	button("德州扑克",Vector2(40,177),Vector2(222,45),switch_mode.bind("holdem"),busy or in_round() or mode=="holdem")
	button("斗地主",Vector2(40,233),Vector2(222,45),switch_mode.bind("doudizhu"),busy or in_round() or mode=="doudizhu")
	button("其他牌桌 · 二十一点等",Vector2(40,289),Vector2(222,45),classics,busy or in_round())
	label("本桌规则",Vector2(40,355),Vector2(220,25),18)
	var text: String="六人无限注德州扑克。\n小盲 10 / 大盲 20，庄位轮转。\n翻牌前 → 翻牌 → 转牌 → 河牌。\n两张底牌＋五张公共牌取最佳五张。\n支持边池、平分、短筹码全下。\nNPC 仅使用自己的底牌和公共牌。\n任一人筹码耗尽后可重开牌桌。"
	if mode=="doudizhu": text="54 张牌，叫分 1–3 分确定地主。\n地主 20 张，农民各 17 张。\n支持顺子、连对、三带、飞机、\n四带二、四带两对、炸弹、王炸。\n顺子 / 连牌不含 2 和王。\n两家不出后，上一家重新领出。\n炸弹与春天翻倍，底分 20。\n本桌飞机单翅可带对子。"
	label(text,Vector2(40,393),Vector2(220,190),14,Color("d8c7b6"))
	button("重开牌桌 / 积分归零",Vector2(40,637),Vector2(222,44),reset_table,busy or in_round())
	panel(Vector2(930,115),Vector2(330,100))
	label(message,Vector2(948,126),Vector2(295,80),16,Color("fff1db"))
	if mode=="holdem":
		var positions=[Vector2(310,445),Vector2(310,285),Vector2(310,125),Vector2(1034,245),Vector2(1034,425)]
		for i in range(1,6): seat(i,positions[i-1])
	else:
		seat(1,Vector2(310,224)); seat(2,Vector2(1034,224))
	panel(Vector2(310,627),Vector2(950,77),Color("130e12"))
	if mode=="holdem": draw_holdem()
	else: draw_ddz()
	if not in_round():
		button("入座发牌" if settled else "结算中…",Vector2(335,644),Vector2(160,44),start_hand,busy or (mode=="holdem" and poker.stacks.count(0)>0))
		label("点击左侧可换桌；筹码不足时可重开。",Vector2(525,653),Vector2(610,26),15)

func draw_holdem() -> void:
	var pot:=0
	for v in poker.total: pot+=v
	label("%s · 底池 %d · 庄位 %s"%[Holdem.STREETS[poker.street],pot,NAMES[poker.button]],Vector2(565,331),Vector2(450,30),18)
	for i in mini(board_visible_count,poker.board.size()): card(poker.board[i],Vector2(575+i*80,380))
	if board_visible_count==0: label("公共牌等待翻开",Vector2(625,402),Vector2(330,30),20,Color("bca789"))
	label("你 · 筹码 %d · 本轮已投 %d"%[poker.stacks[0],poker.bets[0]],Vector2(550,477),Vector2(500,26),17)
	for i in poker.holes[0].size(): card(poker.holes[0][i],Vector2(670+i*82,513))
	if poker.active:
		var enabled: bool=poker.actor==0 and not busy
		button("弃牌",Vector2(329,644),Vector2(90,44),holdem_action.bind("fold"),not enabled)
		button("过牌" if poker.owed(0)==0 else "跟注 %d"%mini(poker.owed(0),poker.stacks[0]),Vector2(430,644),Vector2(140,44),holdem_action.bind("call"),not enabled)
		raise_box=SpinBox.new()
		raise_box.position=Vector2(585,649); raise_box.size=Vector2(135,38)
		raise_box.min_value=mini(poker.current_bet+poker.min_raise,poker.bets[0]+poker.stacks[0])
		raise_box.max_value=poker.bets[0]+poker.stacks[0]
		raise_box.value=raise_box.min_value; raise_box.step=1
		raise_box.editable=enabled and poker.can_raise(0)
		ui.add_child(raise_box)
		button("加注至",Vector2(735,644),Vector2(105,44),holdem_action.bind("raise"),not enabled or not poker.can_raise(0))
		button("全下",Vector2(852,644),Vector2(105,44),holdem_action.bind("allin"),not enabled or (poker.stacks[0]>poker.owed(0) and not poker.can_raise(0)))
		label("轮到 "+NAMES[poker.actor],Vector2(984,651),Vector2(250,28),18)

func draw_ddz() -> void:
	var info: String="等待发牌"
	if ddz.phase!="ready":
		info="叫地主 · 当前 %d 分"%ddz.bid if ddz.phase=="bid" else "地主 %s · %d 分 × %d"%[NAMES[ddz.landlord],ddz.bid,ddz.multiplier]
	label(info,Vector2(570,323),Vector2(450,27),18)
	for i in ddz.bottom.size(): card(ddz.bottom[i],Vector2(685+i*46,357),Vector2(40,58),ddz.landlord<0)
	if not ddz.last.is_empty():
		label(NAMES[ddz.last_seat]+" · "+str(DDZ.combo(ddz.last).get("type","")),Vector2(565,418),Vector2(420,25),16)
		var spacing:=minf(48.0,630.0/ddz.last.size())
		var start:=790.0-float(ddz.last.size())*spacing/2
		for i in ddz.last.size(): card(ddz.last[i],Vector2(start+i*spacing,449),Vector2(43,58))
	label("你 · %s · %d 张 · 积分 %+d"%["待定" if ddz.landlord<0 else ("地主" if ddz.landlord==0 else "农民"),ddz.hands[0].size(),ddz.scores[0]],Vector2(330,508),Vector2(550,25),16)
	var hand: Array=ddz.hands[0]
	var spread:=minf(48.0,870.0/maxi(1,hand.size()))
	for i in hand.size(): card(hand[i],Vector2(330+i*spread,548),Vector2(48,72),false,ddz.phase=="play" and ddz.actor==0 and not busy)
	if ddz.phase=="bid":
		var enabled: bool=ddz.actor==0 and not busy
		button("不叫",Vector2(329,644),Vector2(100,44),bid_action.bind(0),not enabled)
		for value in range(1,4): button("叫 %d 分"%value,Vector2(329+value*115,644),Vector2(105,44),bid_action.bind(value),not enabled or value<=ddz.bid)
		label("轮到 "+NAMES[ddz.actor],Vector2(840,652),Vector2(360,27),18)
	elif ddz.phase=="play":
		var enabled: bool=ddz.actor==0 and not busy
		button("出牌",Vector2(329,644),Vector2(120,44),play_selected,not enabled or selected.is_empty())
		button("不出",Vector2(462,644),Vector2(120,44),pass_turn,not enabled or ddz.last.is_empty())
		button("提示",Vector2(595,644),Vector2(120,44),hint,not enabled)
		button("清空选择",Vector2(728,644),Vector2(130,44),clear_selection,not enabled)
		label("轮到 "+NAMES[ddz.actor],Vector2(890,652),Vector2(330,27),18)

func switch_mode(value: String) -> void:
	if busy or in_round(): return
	mode=value; selected=[]; message="牌桌准备好了，点击入座发牌。"
	refresh()

func classics() -> void:
	if busy or in_round(): return
	get_tree().change_scene_to_file("res://main.tscn")

func reset_table() -> void:
	if busy or in_round(): return
	poker=Holdem.new(); ddz=DDZ.new(); selected=[]
	message="已重开牌桌，牌友均已就座。"; refresh()

func start_hand() -> void:
	if busy or in_round(): return
	busy=true; settled=false; selected=[]; board_visible_count=0
	message="薇拉正在为六位玩家发牌……" if mode=="holdem" else "薇拉正在为三位玩家发牌……"; refresh()
	await motion.begin("deal")
	if mode=="holdem": poker.start()
	else: ddz.start()
	refresh()
	await motion.complete()
	busy=false
	await drive_npcs()

func holdem_action(kind: String) -> void:
	if busy or not poker.active or poker.actor!=0: return
	var ok:=false
	var before: int=poker.street
	if kind=="allin":
		ok=poker.act("call") if poker.stacks[0]<=poker.owed(0) else poker.act("raise",poker.bets[0]+poker.stacks[0])
	else: ok=poker.act(kind,int(raise_box.value) if kind=="raise" else 0)
	if not ok:
		message="加注必须达到最小加注额，或用剩余筹码全下。"; refresh(); return
	if poker.street!=before and poker.active: message="进入"+Holdem.STREETS[poker.street]
	await drive_npcs()

func bid_action(value: int) -> void:
	if busy or ddz.actor!=0: return
	if ddz.bid_action(value): await drive_npcs()

func toggle(c: int) -> void:
	if busy or ddz.actor!=0: return
	if selected.has(c): selected.erase(c)
	else: selected.append(c)
	refresh()

func clear_selection() -> void:
	selected=[]; refresh()

func hint() -> void:
	selected=ddz.hint()
	message="已选出建议牌，可点击出牌。" if not selected.is_empty() else "没有可压过的牌，可以不出。"
	refresh()

func play_selected() -> void:
	if busy or ddz.actor!=0: return
	if not ddz.play(selected): message="牌型不合法，或无法压过上一手。"; refresh(); return
	selected=[]
	await drive_npcs()

func pass_turn() -> void:
	if busy or ddz.actor!=0: return
	if ddz.play([]): selected=[]; await drive_npcs()

func drive_npcs() -> void:
	busy=true
	await reveal_board()
	refresh()
	while in_round() and current_actor()>0:
		message=NAMES[current_actor()]+" 正在思考……"
		refresh()
		await get_tree().create_timer(npc_delay * randf_range(0.8,1.35)).timeout
		if mode=="holdem": poker.npc_move()
		else: ddz.npc_move()
		await reveal_board()
		refresh()
	if not in_round() and not settled:
		message=poker.result if mode=="holdem" else ddz.result
		refresh()
		var won: bool=poker.payouts[0]>0 if mode=="holdem" else (ddz.last_seat==ddz.landlord)==(ddz.landlord==0)
		if won: await motion.begin("payout"); await motion.complete()
		settled=true
	else:
		message="轮到你：检查下注额后决定跟注、加注或弃牌。" if mode=="holdem" else ("轮到你叫地主：可以不叫，或叫更高分。" if ddz.phase=="bid" else "轮到你出牌，点选手牌，也可以使用提示。")
	busy=false
	refresh()


func reveal_board() -> void:
	if mode!="holdem" or poker.board.size()<=board_visible_count: return
	message="薇拉正在发出公共牌……"
	refresh()
	await motion.begin("deal")
	board_visible_count=poker.board.size()
	refresh()
	await motion.complete()
