extends RefCounted

static func deck(packs: int = 1) -> Array:
	var cards: Array = []
	for p in packs:
		for c in 52: cards.append(c)
	cards.shuffle()
	return cards

static func rank(card: int) -> int:
	return card % 13 + 1

static func blackjack(cards: Array) -> int:
	var total := 0
	var aces := 0
	for c in cards:
		var r := rank(c)
		total += 11 if r == 1 else mini(r, 10)
		if r == 1: aces += 1
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total

static func baccarat(cards: Array) -> int:
	var total := 0
	for c in cards: total += rank(c) if rank(c) < 10 else 0
	return total % 10

static func banker_draw(total: int, third: int) -> bool:
	if third < 0: return total <= 5
	if total <= 2: return true
	if total == 3: return third != 8
	if total == 4: return third >= 2 and third <= 7
	if total == 5: return third >= 4 and third <= 7
	return total == 6 and third >= 6 and third <= 7

static func poker(cards: Array) -> Dictionary:
	var ranks: Array = []
	var counts := {}
	var flush := true
	for c in cards:
		var r := rank(c)
		ranks.append(14 if r == 1 else r)
		counts[r] = counts.get(r, 0) + 1
		if int(c / 13) != int(cards[0] / 13): flush = false
	ranks.sort()
	var straight: bool = counts.size() == 5 and (ranks[4] - ranks[0] == 4 or ranks == [2,3,4,5,14])
	var groups: Array = counts.values()
	groups.sort()
	var category := 0
	if straight and flush: category = 9 if ranks[0] == 10 else 8
	elif groups.has(4): category = 7
	elif groups == [2,3]: category = 6
	elif flush: category = 5
	elif straight: category = 4
	elif groups.has(3): category = 3
	elif groups == [1,2,2]: category = 2
	else:
		for r in counts:
			if counts[r] == 2 and (r == 1 or r >= 11): category = 1
	return {"name": ["未中奖", "J 或更高对子", "两对", "三条", "顺子", "同花", "葫芦", "四条", "同花顺", "皇家同花顺"][category], "pay": [0,1,2,3,4,6,9,25,50,250][category]}
