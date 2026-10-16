extends Node3D
var game:Node3D
var air:AudioStreamPlayer
var typing:AudioStreamPlayer3D
var steps:AudioStreamPlayer3D
var rng:=RandomNumberGenerator.new()
var key_clock:=.4
var step_clock:=0.0
var step_count:=0
var last_distance:=0.0
var muted:=true
func _ready() -> void:
	rng.seed=2026101609
	air=AudioStreamPlayer.new();air.stream=wav("air",true);air.volume_db=-21;add_child(air)
	typing=AudioStreamPlayer3D.new();typing.position=game.office.coworker_keyboard;typing.volume_db=-15;typing.unit_size=1.1;typing.max_distance=8;add_child(typing)
	steps=AudioStreamPlayer3D.new();steps.volume_db=-6;steps.unit_size=.85;steps.max_distance=8;add_child(steps)
func wav(id:String,loop:bool=false) -> AudioStreamWAV:
	var stream:AudioStreamWAV=load("res://assets/audio/office-v9/"+id+".wav").duplicate()
	if loop:stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=stream.data.size()/2
	return stream
func suspend(value:bool) -> void:
	muted=value
	if not air:return
	air.stream_paused=value;typing.stream_paused=value;steps.stream_paused=value
	# Keep current one-shot paused; stop() clears stream_paused in Godot.
	# Checking/idle separately stop footsteps after focus returns.
	if not value and not air.playing and DisplayServer.get_name()!="headless":air.play()
func tick(delta:float) -> void:
	var active:bool=game.started and game.phase in ["free","warning","checking","returning"] and game.controls.focused
	suspend(not active)
	if not active:return
	key_clock-=delta
	if key_clock<=0:
		key_clock=rng.randf_range(.16,.7) if rng.randf()<.8 else rng.randf_range(1.5,3)
		if DisplayServer.get_name()!="headless":typing.stream=wav("key"+str(rng.randi_range(0,3)));typing.play()
	steps.global_position=game.office.boss.global_position+Vector3(0,.065,0)
	var moved:float=maxf(0,game.office.step_distance-last_distance);last_distance=game.office.step_distance
	if game.office.walking:
		step_clock+=moved
		while step_clock>=.38:
			step_clock-=.38;step_count+=1
			if DisplayServer.get_name()!="headless":steps.stream=wav("step"+str(step_count%3));steps.play()
	else:step_clock=0;steps.stop()
func _exit_tree() -> void:
	if air:air.stop()
	if typing:typing.stop()
	if steps:steps.stop()
