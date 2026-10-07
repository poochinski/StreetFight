extends Node
## Synthesized sound effects and synthwave music.
##
## Effects are built from code, like an 80s analog synth: two detuned
## oscillators, a sub sine, a noise click and a lowpass filter that closes
## as the note fades. Each sound is generated once and cached. They play on
## an "SFX" bus with a short reverb, so hits sound like they are in a room.
##
## Music is two looping tracks in assets/audio, rendered by
## tools/synthwave.py: "street" for the city floors and "boss" for the last
## floor. The sound button turns effects and music on and off together.

const VOICES = 12
const TRACKS = {
	"street": "res://assets/audio/music_street.wav",
	"boss": "res://assets/audio/music_boss.wav",
}
## Music volume in decibels. The tracks are mastered loud, so they sit under the effects.
const MUSIC_DB = -9.0

var enabled = false:
	set(value):
		enabled = value
		_refresh_music()
		_refresh_effects()
var music_enabled = true:
	set(value):
		music_enabled = value
		_refresh_music()
var effects_enabled = true:
	set(value):
		effects_enabled = value
		_refresh_effects()
var preferences_path = "user://audio-settings.cfg"
var track = ""
var _cache = {}
var _voices: Array[AudioStreamPlayer] = []
var _next = 0
var _music: AudioStreamPlayer

func _ready() -> void:
	var sfx_bus = _bus("SFX")
	var music_bus = _bus("Music")
	if AudioServer.get_bus_effect_count(sfx_bus)==0:
		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.35
		reverb.damping = 0.6
		reverb.wet = 0.14
		reverb.dry = 1.0
		AudioServer.add_bus_effect(sfx_bus,reverb)
	if AudioServer.get_bus_effect_count(music_bus)==0:
		var limiter = AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(music_bus,limiter)
	for i in VOICES:
		var voice = AudioStreamPlayer.new()
		voice.bus = "SFX"
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = MUSIC_DB
	add_child(_music)
	_refresh_music()

## Stops the music and removes the bus effects on exit, which belong to the
## audio server (otherwise Godot reports them as leaked).
func _exit_tree() -> void:
	if _music:
		_music.stop()
		_music.stream = null
	for bus_name in ["SFX","Music"]:
		var index = AudioServer.get_bus_index(bus_name)
		while index>=0 and AudioServer.get_bus_effect_count(index)>0: AudioServer.remove_bus_effect(index,0)

static func _bus(bus_name: String) -> int:
	var index = AudioServer.get_bus_index(bus_name)
	if index>=0: return index
	AudioServer.add_bus()
	index = AudioServer.bus_count-1
	AudioServer.set_bus_name(index,bus_name)
	AudioServer.set_bus_send(index,"Master")
	return index

## Builds one sound. "saw" is a punchy bass hit with a noise click (swings,
## impacts, explosions), "triangle" a soft square pluck (menus, footfalls) and
## "sine" a bright FM bell (loot, level ups, magic).
static func make_tone(frequency: float,duration: float,shape: String,volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var length = ceili(duration*sample_rate)
	var data = PackedByteArray()
	data.resize(length*2)
	var phase_a = 0.0
	var phase_b = 0.0
	var phase_sub = 0.0
	var low = 0.0
	var low2 = 0.0
	var noise_seed = 22222 + int(frequency*7)
	var drop = 0.45 if shape=="saw" else 0.7 if shape=="triangle" else 0.94
	for i in length:
		var t = float(i)/sample_rate
		var fade = t/duration
		var pitch = frequency*pow(drop,fade)
		phase_a += pitch*1.006/sample_rate
		phase_b += pitch*0.994/sample_rate
		phase_sub += pitch*0.5/sample_rate
		noise_seed = (noise_seed*1103515245+12345)&0x7fffffff
		var noise = float(noise_seed)/0x3fffffff-1.0
		var sample = 0.0
		var cutoff = 0.0
		match shape:
			"saw":
				sample = (2*fmod(phase_a,1.0)-1)*0.5+(2*fmod(phase_b,1.0)-1)*0.5
				sample = sample*0.7+sin(phase_sub*TAU)*0.6
				sample += noise*1.1*exp(-t*90)
				cutoff = 0.04+0.55*exp(-fade*5)
			"triangle":
				var square_a = 1.0 if fmod(phase_a,1.0)<0.5 else -1.0
				var square_b = 1.0 if fmod(phase_b,1.0)<0.42 else -1.0
				sample = (square_a+square_b)*0.35+(4*absf(fmod(phase_a,1.0)-0.5)-1)*0.5
				cutoff = 0.06+0.35*exp(-fade*4)
			_:
				var modulator = sin(phase_a*3.5*TAU)*2.2*exp(-fade*3)
				sample = sin(phase_a*TAU+modulator)*0.75+sin(phase_b*2*TAU)*0.25
				cutoff = 0.6
		# Two one-pole lowpass stages: a filter sweep from bright to dark.
		low += (sample-low)*cutoff
		low2 += (low-low2)*cutoff
		var envelope = volume*pow(0.001/volume,fade)*minf(1,t/0.003)
		var out = tanh(low2*1.4)*envelope*1.25
		data.encode_s16(i*2,int(clampf(out,-1,1)*32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream

func play(frequency: float = 220,duration: float = 0.12,shape: String = "triangle",volume: float = 0.045) -> void:
	if not enabled or not effects_enabled or _voices.is_empty(): return
	var key = str([frequency,duration,shape,volume])
	if not _cache.has(key): _cache[key] = make_tone(frequency,duration,shape,volume)
	var voice = _voices[_next%_voices.size()]
	_next += 1
	voice.stream = _cache[key]
	voice.play()

## Picks the music for a floor. It only restarts when the track changes.
func set_track(track_name: String) -> void:
	if track_name==track: return
	track = track_name
	if _music: _music.stop()
	_refresh_music()

func _refresh_music() -> void:
	if not _music: return
	if not enabled or not music_enabled or not TRACKS.has(track):
		_music.stop()
		return
	var stream = load(TRACKS[track])
	if _music.stream!=stream: _music.stream = stream
	if not _music.playing: _music.play()

func _refresh_effects() -> void:
	var bus = AudioServer.get_bus_index("SFX")
	if bus>=0: AudioServer.set_bus_mute(bus, not enabled or not effects_enabled)

func load_preferences() -> void:
	var config = ConfigFile.new()
	if config.load(preferences_path)!=OK: return
	enabled = bool(config.get_value("audio","enabled",true))
	music_enabled = bool(config.get_value("audio","music",true))
	effects_enabled = bool(config.get_value("audio","effects",true))

func save_preferences() -> bool:
	var config = ConfigFile.new()
	config.set_value("audio","enabled",enabled)
	config.set_value("audio","music",music_enabled)
	config.set_value("audio","effects",effects_enabled)
	return config.save(preferences_path)==OK
