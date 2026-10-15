extends SceneTree
const H=preload("res://systems/holdem.gd")
const D=preload("res://systems/doudizhu.gd")
var checks:=0
var failed:=false
func check(ok: bool, title: String) -> void:
	checks+=1
	if not ok: failed=true; push_error("FAIL: "+title)
func _initialize() -> void:
	call_deferred("run")
func cs(ranks: Array) -> Array:
	var used: Dictionary={}
	var out: Array=[]
	for r in ranks:
		if r>=16: out.append(52+r-16); continue
		var value: int=r-13 if r>=14 else r
		var suit: int=used.get(r,0)
		out.append(suit*13+value-1); used[r]=suit+1
	return out
func run() -> void:
	check(H.hand_name(H.evaluate([0,9,10,11,12,20,30]))=="同花顺","royal seven")
	check(H.evaluate(cs([14,2,3,4,5]))<H.evaluate(cs([2,3,4,5,6])),"wheel below six straight")
	check(H.evaluate(cs([14,14,13,12,11]))>H.evaluate(cs([14,14,13,12,10])),"pair kicker")
	check(H.evaluate(cs([7,7,7,2,2]))>H.evaluate([1,3,6,8,11]),"full house beats flush")
	var h=H.new(3)
	h.button=2; h.board=[1,2,3,4,5]; h.holes=[[0,13],[6,19],[7,20]]
	h.total=[100,200,300]; h.stacks=[0,0,0]; h.folded=[false,false,false]
	h.showdown()
	check(h.payouts==[0,500,100],"three contribution levels / side pots")
	check(h.stacks.reduce(func(a,b):return a+b,0)==600,"sidepot conservation")
	h=H.new(3); h.stacks=[1000,1000,35]; h.start()
	h.act("call"); h.act("call"); h.act("raise",35)
	check(not h.rights[0] and not h.can_raise(0),"short allin does not reopen")
	check(h.owed(0)==15,"short allin extra call")
	for sample in 100:
		h=H.new(3)
		h=H.new()
		h.stacks=[]
		for seat in 6: h.stacks.append(randi_range(1,1000))
		var sum_before: int=h.stacks.reduce(func(a,b):return a+b,0)
		h.start()
		check(h.holes.size()==6 and h.actor==(h.button+3)%6,"six seats / UTG starts")
		var dealt: Dictionary={}
		for hand in h.holes:
			for c in hand: dealt[c]=true
		check(dealt.size()==12,"twelve unique hole cards")
		var guard:=0
		while h.active and guard<150:
			guard+=1
			if h.actor==0:
				if h.can_raise(0) and randf()<0.3: h.act("raise",h.bets[0]+h.stacks[0])
				else: h.act("call")
			else: h.npc_move()
		check(not h.active,"holdem terminates %d"%sample)
		check(h.stacks.reduce(func(a,b):return a+b,0)==sum_before,"holdem conservation %d"%sample)
		check(h.stacks.all(func(v):return v>=0),"no negative stacks %d"%sample)
	for entry in [
		[[3],"单张"],[[4,4],"对子"],[[7,7,7],"三张"],[[9,9,9,9],"炸弹"],[[16,17],"王炸"],
		[[3,4,5,6,7],"顺子"],[[11,12,13,14,15],""],[[3,3,4,4,5,5],"连对"],
		[[6,6,6,8],"三带一"],[[6,6,6,8,8],"三带二"],[[3,3,3,4,4,4],"飞机"],
		[[3,3,3,4,4,4,8,9],"飞机带单"],[[3,3,3,4,4,4,8,8,9,9],"飞机带对"],
		[[3,3,3,3,8,9],"四带二"],[[3,3,3,3,8,8,9,9],"四带两对"]]:
		check(D.combo(cs(entry[0])).get("type","")==entry[1],"DDZ classify "+str(entry))
	check(D.beats(cs([3,3,3,3]),cs([14])),"bomb beats ace")
	check(not D.beats(cs([14,14]),cs([3])),"types must match")
	check(not D.beats(cs([3,3,3,3]),cs([16,17])),"cannot beat rocket")
	for sample in 30:
		var d=D.new(); d.start()
		var all: Array=d.hands[0]+d.hands[1]+d.hands[2]+d.bottom
		var unique: Dictionary={}
		for c in all: unique[c]=true
		check(unique.size()==54,"54 distinct cards")
		var guard:=0
		while d.phase!="done" and guard<250:
			guard+=1
			if d.actor==0:
				if d.phase=="bid": d.bid_action(3)
				else:
					var move: Array=d.hint()
					check(d.play(move),"player hint legal")
			else: d.npc_move()
		check(d.phase=="done","DDZ terminates %d"%sample)
		check(d.scores.reduce(func(a,b):return a+b,0)==0,"DDZ points conserved")
	print("PASS: " if not failed else "FAIL: ",checks," NPC rules checks")
	quit(1 if failed else 0)
