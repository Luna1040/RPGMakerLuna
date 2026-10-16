extends Control
const Rules = preload("res://rules.gd")
const GOLD = Color("e6c58b")
var mode := 0
var bankroll := 2000
var wager := 50
var stake := 0
var shoe: Array = []
var player: Array = []
var dealer: Array = []
var held: Array = []
var active := false
var busy := false
var revealed := false
var target := 0
var rounds := 0
var wins := 0
var ui: Control
var cards: Control
var status_label: Label
var cash_label: Label
var action_row: HBoxContainer
var choice_row: HBoxContainer
var mode_buttons: Array = []
var log_lines: Array = []
var message := "晚上好，我是薇拉。选一种玩法，开始今晚的牌局。"
var sound: AudioStreamPlayer
var motion: Control

func _ready() -> void:
	load_progress()
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture = preload("res://assets/salon.png")
	bg.position = Vector2.ZERO
	bg.size = Vector2(1280,720)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(1280,720)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	motion = preload("res://dealer_motion.gd").new()
	add_child(motion)
	ui = Control.new()
	add_child(ui)
	cards = Control.new()
	add_child(cards)
	sound = AudioStreamPlayer.new()
	add_child(sound)
	build_ui()

func style(color: Color, border: Color = Color("5e4837")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(9)
	s.content_margin_left = 14
	s.content_margin_right = 14
	return s

func panel(pos: Vector2, dimensions: Vector2, color: Color) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = dimensions
	p.add_theme_stylebox_override("panel", style(color))
	ui.add_child(p)
	return p

func label_at(text: String, pos: Vector2, dimensions: Vector2, font_size: int = 18, color: Color = GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = dimensions
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",color)
	ui.add_child(l)
	return l

func button(text: String, callback: Callable, parent: Node, width: int = 110) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width,44)
	b.add_theme_stylebox_override("normal",style(Color("211b1c")))
	b.add_theme_stylebox_override("hover",style(Color("594032"),GOLD))
	b.add_theme_stylebox_override("pressed",style(Color("765137"),GOLD))
	b.add_theme_stylebox_override("disabled",style(Color("201c20"),Color("383036")))
	b.add_theme_color_override("font_color",GOLD)
	b.add_theme_font_size_override("font_size",16)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func build_ui() -> void:
	for c in ui.get_children(): c.queue_free()
	mode_buttons.clear()
	var hold_button:=button("德州扑克 · NPC",goto_npc.bind("holdem"),ui,180)
	hold_button.position=Vector2(310,110)
	hold_button.disabled=active or busy
	var ddz_button:=button("斗地主 · NPC",goto_npc.bind("doudizhu"),ui,180)
	ddz_button.position=Vector2(310,165)
	ddz_button.disabled=active or busy
	panel(Vector2(20,18),Vector2(420,80),Color(0.055,0.035,0.04,0.94))
	panel(Vector2(928,18),Vector2(332,80),Color(0.055,0.035,0.04,0.94))
	label_at("绯 夜",Vector2(44,25),Vector2(180,40),30)
	label_at("THE MAHOGANY CLUB  /  红木会所",Vector2(45,65),Vector2(450,23),13)
	cash_label = label_at("",Vector2(945,30),Vector2(290,50),22)
	panel(Vector2(24,120),Vector2(262,570),Color(0.055,0.035,0.04,0.94))
	label_at("选择牌桌",Vector2(44,134),Vector2(220,30),20)
	for i in 3:
		var b := button(["01   二十一点", "02   百家乐", "03   五张换牌扑克"][i], switch_mode.bind(i),ui,220)
		b.position = Vector2(44,181+i*56)
		b.disabled = active or busy or i == mode
		mode_buttons.append(b)
	label_at("桌面规则",Vector2(44,363),Vector2(220,24),17)
	var rules_text: String = ["A 计 1 或 11，尽量接近 21。\n庄家不足 17 必须要牌，软 17 停牌。\n自然黑杰克净赢 3:2；普通胜 1:1。\n首两张可加倍并再取一张。\n本桌不设分牌与保险。", "选择闲、庄或和，荷官自动补牌。\n牌点总和取个位，8 / 9 自然停牌。\n闲胜净赢 1:1；庄胜 0.95:1。\n和局净赢 8:1，庄闲注退回。\n每局使用重新洗好的八副牌。", "发五张牌，点击想保留的牌。\n其余牌可更换一次，再结算。\nJ 起对子 ×1，两对 ×2，三条 ×3。\n顺子 ×4，同花 ×6，葫芦 ×9。\n四条 ×25，同花顺 ×50，皇家 ×250。\n倍数为含本金的总返还。 "][mode]
	var rule_label := label_at(rules_text,Vector2(44,401),Vector2(225,170),14,Color("d0c1b3"))
	rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_at("本地虚拟筹码 · 单人体验",Vector2(44,592),Vector2(220,24),14)
	var reset := button("补充体验筹码", reset_bank,ui,220)
	reset.position = Vector2(44,630)
	reset.disabled = active or busy
	panel(Vector2(928,264),Vector2(330,106),Color(0.055,0.035,0.04,0.85))
	label_at("V E R A  /  薇拉",Vector2(948,279),Vector2(280,28),19)
	label_at("您的私人荷官  ·  欢迎入席",Vector2(948,319),Vector2(280,30),15,Color("d0c1b3"))
	panel(Vector2(928,120),Vector2(330,126),Color(0.055,0.035,0.04,0.87))
	status_label = label_at(message,Vector2(948,132),Vector2(285,100),16,Color("f6ead9"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_at("%s   /   第 %d 局 · 获胜 %d 局" % [["BLACKJACK", "BACCARAT", "DRAW POKER"][mode],rounds+1,wins],Vector2(330,308),Vector2(540,25),14)
	panel(Vector2(310,566),Vector2(950,138),Color("130e12"))
	choice_row = HBoxContainer.new()
	choice_row.position = Vector2(330,594)
	choice_row.add_theme_constant_override("separation",8)
	ui.add_child(choice_row)
	for amount in [20,50,100,200]:
		var b := button(("● " if amount == wager else "")+str(amount),set_wager.bind(amount),choice_row,76)
		b.disabled = active or busy
	if mode == 1:
		for i in 3:
			var b := button(("✓ " if target==i else "")+["闲", "庄", "和"][i],set_target.bind(i),choice_row,70)
			b.disabled = active or busy
	action_row = HBoxContainer.new()
	action_row.position = Vector2(330,647)
	action_row.add_theme_constant_override("separation",12)
	ui.add_child(action_row)
	if not active:
		var start := button("发牌  ·  %d" % wager, start_round,action_row,170)
		start.disabled = busy or bankroll < wager
	elif mode == 0:
		button("要牌",hit,action_row,120).disabled = busy
		button("停牌",stand,action_row,120).disabled = busy
		button("加倍",double_down,action_row,120).disabled = busy or player.size()!=2 or bankroll < stake
	elif mode == 2:
		button("换牌并结算",draw_poker,action_row,180).disabled = busy
		label_at("点击牌面：保留 / 取消",Vector2(560,657),Vector2(300,24),16)
	if not log_lines.is_empty():
		label_at(str(log_lines.back()),Vector2(906,653),Vector2(350,30),14)
	cash_label.text = "筹码  %s   /   下注 %d" % [bankroll,wager]

func switch_mode(index: int) -> void:
	if active or busy: return
	mode=index
	player=[]
	dealer=[]
	message="牌桌已准备好。选择筹码，点击发牌。"
	clear_cards()
	build_ui()

func set_wager(amount: int) -> void:
	if active or busy: return
	wager=amount
	build_ui()

func set_target(index: int) -> void:
	if active or busy: return
	target=index
	build_ui()

func clear_cards() -> void:
	for c in cards.get_children():
		cards.remove_child(c)
		c.queue_free()

func render_hand(hand: Array, y: float, hide_second: bool = false, selectable: bool = false) -> void:
	var spacing := minf(94,620.0/maxi(hand.size(),1))
	var start_x := 760.0-(hand.size()-1)*spacing/2.0-39
	for i in hand.size():
		var c: int = hand[i]
		var hidden := hide_second and i==1
		var b := Button.new()
		b.size=Vector2(78,102)
		b.position=Vector2(start_x+i*spacing,y)
		b.add_theme_font_size_override("font_size",23)
		var suit: int = int(c/13)
		var r := Rules.rank(c)
		var face: String = "A" if r==1 else (str(r) if r<=10 else ["J","Q","K"][r-11])
		b.text="◆\nV" if hidden else face+"\n"+["♠","♥","♣","♦"][suit]
		var ink := Color("a82d46") if suit in [1,3] else Color("202436")
		b.add_theme_color_override("font_color",GOLD if hidden else ink)
		b.add_theme_color_override("font_hover_color",ink)
		b.add_theme_color_override("font_pressed_color",ink)
		var is_held := selectable and held.has(i)
		var s := style(Color("542235") if hidden else Color("fff3dd"),GOLD if is_held else Color("bea97d"))
		s.set_border_width_all(4 if is_held else 1)
		b.add_theme_stylebox_override("normal",s)
		b.add_theme_stylebox_override("hover",s)
		b.add_theme_stylebox_override("pressed",s)
		if selectable:
			b.pressed.connect(toggle_hold.bind(i))
		else: b.mouse_filter=Control.MOUSE_FILTER_IGNORE
		cards.add_child(b)
		if is_held:
			var l := Label.new()
			l.text="保留"
			l.position=Vector2(19,102)
			l.add_theme_color_override("font_color",GOLD)
			b.add_child(l)
		b.pivot_offset=b.size/2
		b.scale=Vector2(0.88,0.88)
		create_tween().tween_property(b,"scale",Vector2.ONE,0.18)

func refresh_cards() -> void:
	clear_cards()
	if mode == 2: render_hand(player,453,false,active and not busy)
	else:
		render_hand(dealer,365,mode==0 and not revealed)
		render_hand(player,480)
		for entry in [["庄家" if mode==0 else "庄",dealer,339],["玩家" if mode==0 else "闲",player,465]]:
			var l:=Label.new()
			var score: String = "?" if mode==0 and not revealed and entry[0]=="庄家" else str(Rules.blackjack(entry[1]) if mode==0 else Rules.baccarat(entry[1]))
			l.text=entry[0]+"  /  "+score
			l.position=Vector2(350,entry[2])
			l.add_theme_color_override("font_color",GOLD)
			cards.add_child(l)

func deal_to(hand: Array) -> void:
	hand.append(shoe.pop_back())
	refresh_cards()
	play_card_sound()
	await get_tree().create_timer(0.28).timeout

func play_card_sound() -> void:
	var wave := AudioStreamWAV.new()
	wave.format=AudioStreamWAV.FORMAT_8_BITS
	wave.mix_rate=22050
	var data:=PackedByteArray()
	data.resize(1500)
	for i in 1500: data[i]=int(128+randf_range(-24,24)*(1.0-float(i)/1500))
	wave.data=data
	sound.stream=wave
	sound.volume_db=-16
	sound.play()

func start_round() -> void:
	if active or busy or bankroll < wager: return
	active=true
	busy=true
	revealed=false
	stake=wager
	bankroll-=stake
	# Reserve the stake immediately, so closing mid-hand cannot refund it.
	save_progress()
	player=[]
	dealer=[]
	held=[]
	shoe=Rules.deck(8 if mode==1 else 1)
	message="请稍候，正在为您发牌……"
	build_ui()
	clear_cards()
	await motion.begin("deal")
	if mode==2:
		for i in 5: await deal_to(player)
		await motion.complete()
		busy=false
		message="点击想保留的牌，然后换牌。祝您好运。"
		build_ui()
		refresh_cards()
		return
	for i in 2:
		await deal_to(player)
		await deal_to(dealer)
	await motion.complete()
	if mode==1:
		revealed=true
		await resolve_baccarat()
		return
	busy=false
	if Rules.blackjack(player)==21 or Rules.blackjack(dealer)==21:
		revealed=true
		if Rules.blackjack(player)==Rules.blackjack(dealer): finish(stake,"双方黑杰克，平局。")
		elif Rules.blackjack(player)==21: finish(int(stake*2.5),"Blackjack！自然二十一点。")
		else: finish(0,"庄家黑杰克。下一局见。")
	else:
		message="您可以要牌、停牌，或加倍下注。"
		build_ui()
		refresh_cards()

func hit() -> void:
	if not active or busy: return
	busy=true
	build_ui()
	await motion.begin("deal")
	await deal_to(player)
	await motion.complete()
	busy=false
	if Rules.blackjack(player)>21: finish(0,"超过 21 点，爆牌。")
	elif Rules.blackjack(player)==21: await stand()
	else:
		build_ui()
		refresh_cards()

func stand() -> void:
	if not active or busy: return
	busy=true
	revealed=true
	build_ui()
	refresh_cards()
	if Rules.blackjack(dealer)<17:
		await motion.begin("deal")
		while Rules.blackjack(dealer)<17: await deal_to(dealer)
		await motion.complete()
	var p:=Rules.blackjack(player)
	var d:=Rules.blackjack(dealer)
	if d>21 or p>d: finish(stake*2,"您赢了！庄家 %d，您 %d。" % [d,p])
	elif p==d: finish(stake,"同点，退回下注。")
	else: finish(0,"庄家 %d，您 %d。庄家获胜。" % [d,p])

func double_down() -> void:
	if not active or busy or player.size()!=2 or bankroll<stake: return
	bankroll-=stake
	stake*=2
	save_progress()
	busy=true
	build_ui()
	await motion.begin("deal")
	await deal_to(player)
	await motion.complete()
	busy=false
	if Rules.blackjack(player)>21: finish(0,"加倍后爆牌。")
	else: await stand()

func resolve_baccarat() -> void:
	var p:=Rules.baccarat(player)
	var d:=Rules.baccarat(dealer)
	if p<8 and d<8:
		await motion.begin("deal")
		var third: int = -1
		if p<=5:
			await deal_to(player)
			third=mini(Rules.rank(player.back()),10)%10
		if Rules.banker_draw(d,third): await deal_to(dealer)
	await motion.complete()
	p=Rules.baccarat(player)
	d=Rules.baccarat(dealer)
	var outcome:=2 if p==d else (0 if p>d else 1)
	var returned:=0
	if outcome==target: returned=int(stake*[2.0,1.95,9.0][target])
	elif outcome==2 and target!=2: returned=stake
	finish(returned,"闲 %d · 庄 %d，%s。" % [p,d,["闲胜","庄胜","和局"][outcome]])

func toggle_hold(index: int) -> void:
	if not active or busy or mode!=2: return
	if held.has(index): held.erase(index)
	else: held.append(index)
	refresh_cards()

func draw_poker() -> void:
	if not active or busy or mode!=2: return
	busy=true
	build_ui()
	if held.size()<5: await motion.begin("deal")
	for i in 5:
		if not held.has(i):
			player[i]=shoe.pop_back()
			refresh_cards()
			play_card_sound()
			await get_tree().create_timer(0.25).timeout
	await motion.complete()
	var result:=Rules.poker(player)
	finish(stake*result.pay,"%s · 总返还 ×%d" % [result.name,result.pay])

func finish(returned: int, text: String) -> void:
	busy=true
	revealed=true
	message=text+" 正在结算……"
	build_ui()
	refresh_cards()
	if returned>0:
		await motion.begin("payout")
		animate_chips(returned)
	bankroll+=returned
	cash_label.text = "筹码  %s   /   下注 %d" % [bankroll,wager]
	rounds+=1
	if returned>stake: wins+=1
	var net:=returned-stake
	message=text+"  筹码 %+d" % net
	log_lines.append("上局 %+d  /  返还 %d" % [net,returned])
	save_progress()
	if returned>0: await motion.complete()
	active=false
	busy=false
	revealed=true
	build_ui()
	refresh_cards()

func reset_bank() -> void:
	if active or busy: return
	bankroll=2000
	rounds=0
	wins=0
	save_progress()
	message="已补充至 2,000 枚体验筹码，请入席。"
	build_ui()

func save_progress() -> void:
	var f:=FileAccess.open("user://salon-save.json",FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"bankroll":bankroll,"rounds":rounds,"wins":wins}))

func load_progress() -> void:
	if not FileAccess.file_exists("user://salon-save.json"): return
	var data=JSON.parse_string(FileAccess.get_file_as_string("user://salon-save.json"))
	if data is Dictionary:
		bankroll=maxi(0,int(data.get("bankroll",2000)))
		rounds=maxi(0,int(data.get("rounds",0)))
		wins=maxi(0,int(data.get("wins",0)))




func animate_chips(amount: int) -> void:
	var stack := Label.new()
	stack.text = "● ● ●  +%d" % amount
	stack.add_theme_font_size_override("font_size",26)
	stack.add_theme_color_override("font_color",GOLD)
	stack.position=Vector2(650,410)
	stack.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	var tween:=create_tween()
	tween.tween_property(stack,"position",Vector2(760,575),0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.45)
	tween.tween_property(stack,"modulate:a",0.0,0.3)
	tween.tween_callback(stack.queue_free)



func goto_npc(value: String) -> void:
	if active or busy: return
	get_tree().set_meta("npc_mode",value)
	get_tree().change_scene_to_file("res://multiplayer.tscn")
