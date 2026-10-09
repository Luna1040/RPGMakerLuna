extends RefCounted
## A second distinct press, after release, within 500 ms starts a held sprint.
const DOUBLE_TAP_WINDOW := 0.5
const SPEED_MULTIPLIER := 1.8
var clock := 0.0
var last_direction := Vector2.ZERO
var last_press := -100.0
var direction := Vector2.ZERO
var active := false
var held_keys: Dictionary = {}

func key_direction(key: int) -> Vector2:
	if key in [KEY_A, KEY_LEFT]: return Vector2.LEFT
	if key in [KEY_D, KEY_RIGHT]: return Vector2.RIGHT
	if key in [KEY_W, KEY_UP]: return Vector2.UP
	if key in [KEY_S, KEY_DOWN]: return Vector2.DOWN
	return Vector2.ZERO

func register_key(key: int, pressed: bool, echo: bool = false) -> void:
	var vector := key_direction(key)
	if vector == Vector2.ZERO or echo:
		return
	if not pressed:
		held_keys.erase(key)
		if active and not held_keys.values().has(direction):
			active = false
		return
	if held_keys.has(key) or held_keys.values().has(vector):
		held_keys[key] = vector
		return
	held_keys[key] = vector
	if vector == last_direction and clock-last_press <= DOUBLE_TAP_WINDOW:
		active = true
		direction = vector
	elif active and vector.dot(direction) < 0:
		active = false
	last_direction = vector
	last_press = clock

func step(delta: float, movement: Vector2) -> void:
	clock += delta
	if active and movement.dot(direction) <= 0.05:
		active = false

func reset() -> void:
	active = false
	direction = Vector2.ZERO
	last_direction = Vector2.ZERO
	last_press = -100.0
	held_keys.clear()
