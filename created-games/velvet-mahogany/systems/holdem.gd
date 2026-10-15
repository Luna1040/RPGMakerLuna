extends RefCounted
# Six-player no-limit hold'em. NPCs only consult their own hole cards + board.
var stacks: Array = [1000,1000,1000]
var holes: Array = [[],[],[]]
var board: Array = []
var deck: Array = []
var folded: Array = [false,false,false]
var bets: Array = [0,0,0]
var total: Array = [0,0,0]
var rights: Array = [true,true,true]
var pending: Array = []
var button := 2
var actor := -1
var street := 0
var current_bet := 20
var min_raise := 20
var active := false
var result := ""
var last_action := ["", "", ""]
var payouts: Array = [0,0,0]
var show_cards := false
const NAMES = ["你", "陆沉", "阿岚", "老周", "林薇", "阿凯"]
const STYLES = ["玩家", "进攻型", "稳健型", "紧手型", "灵活型", "松手型"]
const RAISE_THRESHOLD = [1.0, 0.82, 0.95, 1.04, 0.88, 0.78]
const FOLD_THRESHOLD = [0.35, 0.33, 0.40, 0.48, 0.36, 0.24]

func _init(seats: int = 6) -> void:
	stacks=[]
	for i in seats: stacks.append(1000)
	button=seats-1
	reset_hand_arrays()

func filled(value: Variant) -> Array:
	var out: Array=[]
	for i in stacks.size(): out.append(value)
	return out

func reset_hand_arrays() -> void:
	holes=[]
	for i in stacks.size(): holes.append([])
	folded=filled(false); bets=filled(0); total=filled(0)
	rights=filled(true); last_action=filled(""); payouts=filled(0)
const STREETS = ["翻牌前", "翻牌", "转牌", "河牌", "摊牌"]

static func rank(c: int) -> int:
	var r := c%13+1
	return 14 if r==1 else r

static func five(cards: Array) -> int:
	var groups := {}
	var ranks: Array = []
	var flush := true
	for c in cards:
		var r := rank(c)
		ranks.append(r)
		groups[r]=groups.get(r,0)+1
		if int(c/13)!=int(cards[0]/13): flush=false
	ranks.sort()
	ranks.reverse()
	var straight := 0
	if groups.size()==5:
		if ranks[0]-ranks[4]==4: straight=ranks[0]
		elif ranks==[14,5,4,3,2]: straight=5
	var sorted: Array = groups.keys()
	sorted.sort_custom(func(a,b): return groups[a]>groups[b] or (groups[a]==groups[b] and a>b))
	var category:=0
	var tie: Array=sorted.duplicate()
	if flush and straight>0: category=8; tie=[straight]
	elif groups[sorted[0]]==4: category=7
	elif groups[sorted[0]]==3 and groups[sorted[1]]==2: category=6
	elif flush: category=5; tie=ranks
	elif straight>0: category=4; tie=[straight]
	elif groups[sorted[0]]==3: category=3
	elif groups[sorted[0]]==2 and groups[sorted[1]]==2: category=2
	elif groups[sorted[0]]==2: category=1
	var score:=category
	for i in 5: score=score*15+(int(tie[i]) if i<tie.size() else 0)
	return score

static func evaluate(cards: Array) -> int:
	var best := -1
	for a in range(cards.size()-4):
		for b in range(a+1,cards.size()-3):
			for c in range(b+1,cards.size()-2):
				for d in range(c+1,cards.size()-1):
					for e in range(d+1,cards.size()): best=maxi(best,five([cards[a],cards[b],cards[c],cards[d],cards[e]]))
	return best

static func hand_name(value: int) -> String:
	return ["高牌","一对","两对","三条","顺子","同花","葫芦","四条","同花顺"][clampi(int(value/759375),0,8)]

func start() -> bool:
	if active or stacks.count(0)>0: return false
	button=(button+1)%stacks.size()
	deck=range(52)
	deck.shuffle()
	reset_hand_arrays()
	for n in 2:
		for i in stacks.size(): holes[i].append(deck.pop_back())
	board=[]
	folded=filled(false)
	bets=filled(0); total=filled(0); rights=filled(true)
	last_action=filled(""); payouts=filled(0)
	street=0; current_bet=20; min_raise=20; result=""; show_cards=false
	active=true
	pay((button+1)%stacks.size(),10)
	pay((button+2)%stacks.size(),20)
	last_action[(button+1)%stacks.size()]="小盲 10"
	last_action[(button+2)%stacks.size()]="大盲 20"
	pending=[]
	for n in stacks.size():
		var i: int=(button+3+n)%stacks.size()
		if stacks[i]>0: pending.append(i)
	advance()
	return true

func pay(seat: int, amount: int) -> void:
	var cost:=mini(amount,int(stacks[seat]))
	stacks[seat]-=cost; bets[seat]+=cost; total[seat]+=cost

func owed(seat: int) -> int:
	return maxi(0,current_bet-int(bets[seat]))

func can_raise(seat: int) -> bool:
	return active and rights[seat] and stacks[seat]>owed(seat) and actable().size()>1

func actable() -> Array:
	var out: Array=[]
	for i in stacks.size():
		if not folded[i] and stacks[i]>0: out.append(i)
	return out

func survivors() -> Array:
	var out: Array=[]
	for i in stacks.size():
		if not folded[i]: out.append(i)
	return out

func act(kind: String, target: int = 0) -> bool:
	if not active or actor<0: return false
	var seat:=actor
	if kind=="raise":
		if not can_raise(seat): return false
		var cap: int=bets[seat]+stacks[seat]
		if target<=current_bet or target>cap: return false
		if target<current_bet+min_raise and target!=cap: return false
	elif kind not in ["fold","call"]: return false
	pending.erase(seat)
	rights[seat]=false
	if kind=="fold": folded[seat]=true; last_action[seat]="弃牌"
	elif kind=="call":
		var cost:=mini(owed(seat),int(stacks[seat]))
		pay(seat,cost)
		last_action[seat]="过牌" if cost==0 else ("全下 %d"%cost if stacks[seat]==0 else "跟注 %d"%cost)
	else:
		var increase:=target-current_bet
		pay(seat,target-int(bets[seat]))
		current_bet=target
		last_action[seat]="全下至 %d"%target if stacks[seat]==0 else "加注至 %d"%target
		if increase>=min_raise:
			min_raise=increase
			for i in stacks.size():
				if i!=seat: rights[i]=true
		pending=[]
		for n in range(1,stacks.size()):
			var i: int=(seat+n)%stacks.size()
			if not folded[i] and stacks[i]>0 and bets[i]<current_bet: pending.append(i)
	advance()
	return true

func advance() -> void:
	if survivors().size()==1:
		var winner: int=survivors()[0]
		var pot:=0
		for v in total: pot+=v
		stacks[winner]+=pot; payouts[winner]=pot
		result=NAMES[winner]+" 赢得底池 %d（其他玩家弃牌）"%pot
		active=false; actor=-1
		return
	pending=pending.filter(func(i): return not folded[i] and stacks[i]>0)
	var able:=actable()
	if able.size()<=1:
		if able.size()==1 and owed(able[0])>0: pending=[able[0]]
		else: pending=[]
	if not pending.is_empty(): actor=pending[0]; return
	if street==3:
		showdown()
		return
	street+=1
	deck.pop_back() # burn
	for i in (3 if street==1 else 1): board.append(deck.pop_back())
	bets=filled(0); current_bet=0; min_raise=20; rights=filled(true)
	pending=[]
	for n in range(1,stacks.size()+1):
		var i: int=(button+n)%stacks.size()
		if not folded[i] and stacks[i]>0: pending.append(i)
	advance()

func showdown() -> void:
	active=false; actor=-1; street=4; show_cards=true
	payouts=filled(0)
	var levels: Array=[]
	for x in total:
		if x>0 and not levels.has(x): levels.append(x)
	levels.sort()
	var previous:=0
	var messages: Array=[]
	for level in levels:
		var donors: Array=[]
		var eligible: Array=[]
		for i in stacks.size():
			if total[i]>=level:
				donors.append(i)
				if not folded[i]: eligible.append(i)
		var pot: int=(level-previous)*donors.size()
		previous=level
		if eligible.is_empty():
			for i in donors: payouts[i]+=int(pot/donors.size())
			continue
		var best: int=-1
		var winners: Array=[]
		for i in eligible:
			var score:=evaluate(holes[i]+board)
			if score>best: best=score; winners=[i]
			elif score==best: winners.append(i)
		var share:=int(pot/winners.size())
		var remainder:=pot%winners.size()
		for i in winners: payouts[i]+=share
		for n in range(1,stacks.size()+1):
			var i: int=(button+n)%stacks.size()
			if remainder>0 and winners.has(i): payouts[i]+=1; remainder-=1
		messages.append("底池 %d → %s（%s）"%[pot," / ".join(winners.map(func(i):return NAMES[i])),hand_name(best)])
	for i in stacks.size(): stacks[i]+=payouts[i]
	result="；".join(messages)

func npc_move() -> void:
	if actor<=0 or not active: return
	var seat:=actor
	var a:=rank(holes[seat][0]); var b:=rank(holes[seat][1])
	var strength:=float(a+b)/36.0
	if a==b: strength+=0.35
	if int(holes[seat][0]/13)==int(holes[seat][1]/13): strength+=0.08
	if board.size()>=3:
		var value:=evaluate(holes[seat]+board)
		strength=0.28+float(int(value/759375))*0.15+float(maxi(a,b))/90.0
	var cost:=owed(seat)
	var pot:=0
	for x in total: pot+=x
	var pressure:=float(cost)/maxf(1.0,float(pot+cost))
	var noise:=randf_range(-0.13,0.13)
	if cost>0 and strength+noise<FOLD_THRESHOLD[seat]+pressure*0.5:
		act("fold")
	elif can_raise(seat) and strength+noise>RAISE_THRESHOLD[seat] and randf()<0.45:
		var to:=mini(current_bet+maxi(min_raise,int(pot/2)),bets[seat]+stacks[seat])
		act("raise",to)
	else: act("call")
