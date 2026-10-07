extends Node
## Synthesized sound effects. Tones are generated once and cached.

const VOICES = 10
var enabled = false
var _cache = {}
var _voices: Array[AudioStreamPlayer] = []
var _next = 0

func _ready() -> void:
	for i in VOICES:
		var voice = AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)

static func make_tone(frequency: float,duration: float,shape: String,volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var length = ceili(duration*sample_rate)
	var data = PackedByteArray()
	data.resize(length*2)
	var phase = 0.0
	for i in length:
		var t = float(i)/sample_rate
		phase += frequency*pow(0.45,t/duration)/sample_rate
		var sample = sin(phase*TAU)
		if shape=="triangle": sample = 4*absf(fmod(phase,1.0)-0.5)-1
		if shape=="saw": sample = 2*fmod(phase,1.0)-1
		var envelope = volume*pow(0.001/volume,t/duration)*minf(1,t/0.003)
		data.encode_s16(i*2,int(clampf(sample*envelope,-1,1)*32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream

func play(frequency: float = 220,duration: float = 0.12,shape: String = "triangle",volume: float = 0.045) -> void:
	if not enabled or _voices.is_empty(): return
	var key = str([frequency,duration,shape,volume])
	if not _cache.has(key): _cache[key] = make_tone(frequency,duration,shape,volume)
	var voice = _voices[_next%_voices.size()]
	_next += 1
	voice.stream = _cache[key]
	voice.play()
