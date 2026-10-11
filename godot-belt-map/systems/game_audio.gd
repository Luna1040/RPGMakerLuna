extends Node
## Small original synthesized feedback, independent of external audio packs.
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0

func _ready() -> void:
	for i in 8:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -15
		add_child(voice)
		voices.append(voice)
	for kind in ["swing","hit","loot","level","hurt","ui"]:
		streams[kind] = make_tone(kind)

func make_tone(kind: String) -> AudioStreamWAV:
	var spec: Array = {"swing":[240.0,80.0,.10],"hit":[140.0,45.0,.12],"loot":[640.0,1000.0,.18],"level":[440.0,880.0,.38],"hurt":[130.0,65.0,.18],"ui":[520.0,520.0,.04]}[kind]
	var samples := int(22050*float(spec[2]))
	var bytes := PackedByteArray()
	bytes.resize(samples*2)
	var phase := 0.0
	for i in samples:
		var u := float(i)/samples
		phase += TAU*lerpf(spec[0],spec[1],u)/22050.0
		var value := sin(phase)*pow(1.0-u,2)*minf(1,u*50)*.6
		bytes.encode_s16(i*2,int(value*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	return stream

func play(kind: String) -> void:
	if not streams.has(kind) or voices.is_empty(): return
	var voice := voices[next_voice]
	next_voice = (next_voice+1)%voices.size()
	voice.stream = streams[kind]
	voice.play()

func _exit_tree() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream=null
	voices.clear()
	streams.clear()
