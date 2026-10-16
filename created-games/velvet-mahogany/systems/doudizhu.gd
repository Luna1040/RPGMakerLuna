extends RefCounted
# Local three-seat Dou Dizhu: one round of bidding, full common combination set.
var hands: Array=[[],[],[]]
var bottom: Array=[]
var landlord: int=-1
var actor := 0
var phase := "ready"
var bid := 0
var bidder := -1
var bids_done := 0
var first_bidder := 0
var last: Array=[]
var last_seat := -1
var passes := 0
var multiplier := 1
var played_counts: Array=[0,0,0]
var scores: Array=[0,0,0]
var last_action: Array=["", "", ""]
var result := ""
const NAMES=["你","陆沉","阿岚"]

static func rank(c: int) -> int:
	if c>=52: return c-52+16
	var v:=c%13+1
	return v+13 if v<3 else v

static func sorted_cards(cards: Array) -> Array:
	var out:=cards.duplicate()
	out.sort_custom(func(a,b):return rank(a)<rank(b) or (rank(a)==rank(b) and a<b))
	return out

static func groups(cards: Array) -> Dictionary:
	var out: Dictionary={}
	for c in sorted_cards(cards):
		var r:=rank(c)
		if not out.has(r): out[r]=[]
		out[r].append(c)
	return out

static func combo(cards: Array) -> Dictionary:
	var n:=cards.size()
	if n==0: return {}
	var g:=groups(cards)
	var rs: Array=g.keys()
	rs.sort()
	if n==2 and rs==[16,17]: return {"type":"王炸","rank":17,"n":2}
	if g.size()==1:
		return {"type":["","单张","对子","三张","炸弹"][n],"rank":rs[0],"n":n} if n<=4 else {}
	for r in rs:
		if g[r].size()==3:
			if n==4: return {"type":"三带一","rank":r,"n":n}
			if n==5 and g.size()==2: return {"type":"三带二","rank":r,"n":n}
		if g[r].size()==4:
			if n==6: return {"type":"四带二","rank":r,"n":n}
			if n==8 and g.size()==3:
				var ok:=true
				for v in rs:
					if v!=r and g[v].size()!=2: ok=false
				if ok: return {"type":"四带两对","rank":r,"n":n}
	if rs.back()<=14 and rs.back()-rs[0]+1==rs.size():
		var counts: Array=g.values().map(func(v):return v.size())
		if n>=5 and counts.count(1)==rs.size(): return {"type":"顺子","rank":rs.back(),"n":n}
		if rs.size()>=3 and counts.count(2)==rs.size(): return {"type":"连对","rank":rs.back(),"n":n}
		if rs.size()>=2 and counts.count(3)==rs.size(): return {"type":"飞机","rank":rs.back(),"n":n}
	for width in [4,5]:
		if n%width!=0: continue
		var count:=int(n/width)
		if count<2: continue
		for start in range(3,16-count):
			var valid:=true
			var rest: Array=[]
			for r in range(start,start+count):
				if not g.has(r) or g[r].size()!=3: valid=false
			if not valid: continue
			for r in rs:
				if r<start or r>=start+count: rest.append_array(g[r])
			if width==4 and rest.size()==count: return {"type":"飞机带单","rank":start+count-1,"n":n}
			if width==5:
				var wings:=groups(rest)
				if wings.size()==count and wings.values().all(func(v):return v.size()==2): return {"type":"飞机带对","rank":start+count-1,"n":n}
	return {}

static func beats(cards: Array, previous: Array) -> bool:
	var a:=combo(cards)
	if a.is_empty(): return false
	if previous.is_empty(): return true
	var b:=combo(previous)
	if b.is_empty(): return false
	if b.type=="王炸": return false
	if a.type=="王炸": return true
	if a.type=="炸弹" and b.type!="炸弹": return true
	return a.type==b.type and a.n==b.n and a.rank>b.rank

static func combinations(items: Array, count: int, start: int=0, prefix: Array=[]) -> Array:
	if count==0: return [prefix]
	var out: Array=[]
	for i in range(start,items.size()-count+1): out.append_array(combinations(items,count-1,i+1,prefix+[items[i]]))
	return out

static func moves(hand: Array, previous: Array=[]) -> Array:
	var g:=groups(hand)
	var rs: Array=g.keys()
	rs.sort()
	var candidates: Array=[]
	for r in rs:
		for n in range(1,mini(g[r].size(),4)+1): candidates.append(g[r].slice(0,n))
		if g[r].size()>=3:
			for w in rs:
				if w==r: continue
				candidates.append(g[r].slice(0,3)+g[w].slice(0,1))
				if g[w].size()>=2: candidates.append(g[r].slice(0,3)+g[w].slice(0,2))
		if g[r].size()==4:
			var rest: Array=[]
			var pair_ranks: Array=[]
			for w in rs:
				if w!=r:
					rest.append_array(g[w])
					if g[w].size()>=2: pair_ranks.append(w)
			for wing in combinations(rest,2): candidates.append(g[r]+wing)
			for wing in combinations(pair_ranks,2): candidates.append(g[r]+g[wing[0]].slice(0,2)+g[wing[1]].slice(0,2))
	if g.has(16) and g.has(17): candidates.append([52,53])
	for copies in [1,2,3]:
		var minimum: int=5 if copies==1 else (3 if copies==2 else 2)
		for start in range(3,15):
			var body: Array=[]
			for end in range(start,15):
				if not g.has(end) or g[end].size()<copies: break
				body.append_array(g[end].slice(0,copies))
				var count:=end-start+1
				if count<minimum: continue
				candidates.append(body.duplicate())
				if copies!=3: continue
				var rest: Array=[]
				var pairs: Array=[]
				for w in rs:
					if w<start or w>end:
						rest.append_array(g[w])
						if g[w].size()>=2: pairs.append(w)
				for wings in combinations(rest,count): candidates.append(body+wings)
				for wings in combinations(pairs,count):
					var cards:=body.duplicate()
					for w in wings: cards.append_array(g[w].slice(0,2))
					candidates.append(cards)
	var seen: Dictionary={}
	var valid: Array=[]
	for move in candidates:
		if not beats(move,previous): continue
		var key:=str(move.map(func(c):return rank(c)))
		if seen.has(key): continue
		seen[key]=true
		valid.append(sorted_cards(move))
	valid.sort_custom(func(a,b):
		var ca:=combo(a); var cb:=combo(b)
		var ba: bool=ca.type in ["炸弹","王炸"]; var bb: bool=cb.type in ["炸弹","王炸"]
		if ba!=bb: return not ba
		if previous.is_empty() and a.size()!=b.size(): return a.size()>b.size()
		return ca.rank<cb.rank)
	return valid

func start() -> void:
	var deck: Array=range(54)
	deck.shuffle()
	hands=[[],[],[]]
	for n in 17:
		for i in 3: hands[i].append(deck.pop_back())
	for i in 3: hands[i]=sorted_cards(hands[i])
	bottom=deck.duplicate()
	landlord=-1; bid=0; bidder=-1; bids_done=0
	actor=first_bidder; first_bidder=(first_bidder+1)%3
	phase="bid"; last=[]; last_seat=-1; passes=0; multiplier=1
	played_counts=[0,0,0]; last_action=["", "", ""]; result=""

func bid_action(value: int) -> bool:
	if phase!="bid" or value<0 or value>3 or (value>0 and value<=bid): return false
	last_action[actor]="不叫" if value==0 else "%d 分"%value
	if value>bid: bid=value; bidder=actor
	bids_done+=1
	if bid==3 or bids_done==3:
		if bidder<0:
			start()
			result="无人叫分，重新发牌。"
		else:
			landlord=bidder
			hands[landlord].append_array(bottom)
			hands[landlord]=sorted_cards(hands[landlord])
			actor=landlord; phase="play"
			last_action=["", "", ""]
		return true
	actor=(actor+1)%3
	return true

func play(cards: Array) -> bool:
	if phase!="play": return false
	if cards.is_empty():
		if last.is_empty() or last_seat==actor: return false
		last_action[actor]="不出"
		passes+=1
		actor=(actor+1)%3
		if passes==2:
			actor=last_seat; last=[]; passes=0
		return true
	var remaining: Array=hands[actor].duplicate()
	for c in cards:
		if not remaining.has(c): return false
		remaining.erase(c)
	if not beats(cards,last): return false
	hands[actor]=remaining
	last=sorted_cards(cards); last_seat=actor; passes=0
	played_counts[actor]+=1
	var kind: Dictionary=combo(cards)
	last_action[actor]=kind.type
	if kind.type in ["炸弹","王炸"]: multiplier*=2
	if remaining.is_empty():
		phase="done"
		var landlord_won:=actor==landlord
		var spring:=true
		if landlord_won:
			for i in 3:
				if i!=landlord and played_counts[i]>0: spring=false
		else: spring=played_counts[landlord]==1
		if spring: multiplier*=2
		var amount:=20*bid*multiplier
		for i in 3:
			scores[i]+=amount*(2 if i==landlord else -1)*(1 if landlord_won else -1)
		result=("地主获胜" if landlord_won else "农民获胜")+(" · 春天 ×2" if spring else "")+" · 每份 %d 分"%amount
		actor=-1
		return true
	actor=(actor+1)%3
	return true

func hint() -> Array:
	if phase!="play": return []
	var options:=moves(hands[actor],last)
	return [] if options.is_empty() else options[0]

func npc_move() -> void:
	if actor<=0: return
	if phase=="bid":
		var strength:=0
		var g:=groups(hands[actor])
		for r in g:
			if r>=15: strength+=g[r].size()*2
			if g[r].size()==4: strength+=4
		var value:=3 if strength>=10 else (2 if strength>=6 else (1 if strength>=3 else 0))
		bid_action(value if value>bid else 0)
	elif phase=="play":
		var options:=moves(hands[actor],last)
		if options.is_empty(): play([]); return
		# Farmers yield to their partner unless they can finish immediately.
		if not last.is_empty() and actor!=landlord and last_seat!=landlord and options[0].size()<hands[actor].size():
			play([]); return
		for option in options:
			if option.size()==hands[actor].size(): play(option); return
		play(options[0])
