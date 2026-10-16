extends RefCounted
class_name RunState

const Data = preload("res://game_data.gd")

const ENDING_IDS := ["shot_prevented", "shot_preserved", "death_faked"]
const DEFAULT_DRINKS := ["still_sea", "empathy", "stable"]

var credits := 0
var unlocked_drinks: Array[String] = ["still_sea", "empathy", "stable"]
var facility := ""
var reward_claimed := false
var reward_amount := 0
var final_score := 0
var clues: Array[String] = []
var paradox := 0.0
var reached_room := 0
var buff_rerolls := 0
var medical_reroll_claimed := false
var causal_flags := {
	"shot_prevented": false,
	"shot_preserved": false,
	"death_faked": false
}

func choose_ending(id: String) -> void:
	assert(id in ENDING_IDS)
	for key in causal_flags:
		causal_flags[key] = key == id

func ending_id() -> String:
	for id in ENDING_IDS:
		if causal_flags[id]: return id
	return ""

func causal_count() -> int:
	var count := 0
	for value in causal_flags.values():
		if value: count += 1
	return count

func add_clue(id: String) -> void:
	if not id in clues: clues.append(id)

func claim_medical_reroll() -> bool:
	if medical_reroll_claimed: return false
	medical_reroll_claimed = true
	buff_rerolls += 1
	return true

func calculate_score(alignment: int) -> int:
	var depth_score: int = [0, 8, 16, 25][clampi(reached_room, 0, 3)]
	var evidence_score: int = mini(25, clues.size() * 7)
	var stability_score: int = clampi(25 - int(paradox * 0.25), 0, 25)
	return clampi(depth_score + evidence_score + alignment + stability_score, 0, 100)

func claim_reward(score: int, multiplier := 1.0) -> int:
	if reward_claimed: return 0
	final_score = score
	reward_amount = int(round((100 + score * 3) * multiplier))
	credits += reward_amount
	reward_claimed = true
	return reward_amount

func buy_facility(id: String, cost := 150) -> bool:
	if not facility.is_empty() or credits < cost: return false
	facility = id
	credits -= cost
	return true

func is_drink_unlocked(id: String) -> bool:
	return id in unlocked_drinks

func buy_drink(id: String) -> bool:
	var drink: Dictionary = Data.drink_by_id(id)
	if drink.is_empty() or is_drink_unlocked(id): return false
	var cost := int(drink.cost)
	if cost <= 0 or credits < cost: return false
	credits -= cost
	unlocked_drinks.append(id)
	return true
