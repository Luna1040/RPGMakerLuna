extends RefCounted
const E=preload("res://estate_system.gd")
const P=preload("res://progression_system.gd")
static func can_attempt(c: Dictionary) -> bool: return int(c.level)==20 and not P.foundation(c) and str(c.get("realm","")) in ["练气期","炼气期"]
static func resolve(c: Dictionary, use_pill: bool, roll: float) -> String:
	if not can_attempt(c): return "blocked"
	if use_pill and not E.consume(c.inventory,"breakthrough_pill","foundation",1): return "missing_pill"
	c.breakthrough_attempts=int(c.get("breakthrough_attempts",0))+1
	if roll<(0.8 if use_pill else 0.3):
		c.realm="筑基期"; c.foundation_established=true; c.xp=0
		return "success"
	c.level=19; c.xp=0
	return "failure"
static func attempt(c: Dictionary, use_pill: bool) -> String:
	if not can_attempt(c): return "blocked"
	if use_pill and E.count(c.inventory,"breakthrough_pill","foundation")==0: return "missing_pill"
	var rng:=RandomNumberGenerator.new()
	if c.has("breakthrough_rng_state"): rng.state=int(str(c.breakthrough_rng_state))
	else: rng.randomize()
	var result:=resolve(c,use_pill,rng.randf())
	c.breakthrough_rng_state=str(rng.state)
	return result
