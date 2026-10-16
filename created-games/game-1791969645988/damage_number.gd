extends Label
const HOLD_SECONDS:=1.0
const FADE_SECONDS:=0.35
var age:=0.0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
	age+=delta
	modulate.a=1.0-clampf((age-HOLD_SECONDS)/FADE_SECONDS,0.0,1.0)
	if age>=HOLD_SECONDS+FADE_SECONDS: queue_free()
