extends RefCounted
## Reusable target reactions. Height is positive above its ground anchor.
const SHOCK_DURATION := 4.0
const MAX_AIR_HITS := 6
var height := 0.0
var rise_speed := 0.0
var shock_left := 0.0
var shock_tick := 0.5
var combo := 0
var combo_left := 0.0
var air_hits := 0
var air_hold := 0.0
var stun_left := 0.0

func reset() -> void:
	height = 0.0
	rise_speed = 0.0
	shock_left = 0.0
	shock_tick = 0.5
	combo = 0
	combo_left = 0.0
	air_hits = 0
	air_hold = 0.0
	stun_left = 0.0

func airborne() -> bool:
	return height > 0.01 or rise_speed > 0.0

func hit(action: String) -> Dictionary:
	var was_airborne := airborne()
	var bonus := 6.0 if shock_left > 0 and action.begins_with("attack") else 0.0
	combo += 1
	combo_left = 1.4
	stun_left = 0.18
	if action == "magic":
		shock_left = SHOCK_DURATION
		shock_tick = 0.5
	if was_airborne:
		air_hits += 1
		if air_hits <= MAX_AIR_HITS:
			rise_speed = maxf(rise_speed,210.0)
			air_hold = 0.055
	elif action == "attack3":
		rise_speed = 360.0
		height = 1.0
		air_hits = 0
	return {"bonus":bonus,"air_hit":was_airborne,"launched":action=="attack3" and not was_airborne}

func step(delta: float) -> float:
	var dot := 0.0
	var remaining := delta
	while remaining > 0:
		var dt := minf(remaining,1.0/120.0)
		remaining -= dt
		stun_left = maxf(0,stun_left-dt)
		combo_left = maxf(0,combo_left-dt)
		if combo_left <= 0 and not airborne():
			combo = 0
		if shock_left > 0:
			var active := minf(dt,shock_left)
			shock_left = maxf(0,shock_left-dt)
			shock_tick -= active
			if shock_tick <= 0.00001:
				dot += 4
				shock_tick += 0.5
		if air_hold > 0:
			air_hold = maxf(0,air_hold-dt)
		elif airborne():
			rise_speed -= 600.0 * dt
			height += rise_speed * dt
			if height > 180:
				height = 180
				rise_speed = minf(0,rise_speed)
			if height <= 0:
				height = 0
				rise_speed = 0
				air_hits = 0
	return dot
