extends Node
class_name VectorSound

## Small original procedural sounds: no external audio licenses or downloads.
var clips: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var voice_index: int = 0

func _ready() -> void:
	for i in 10:
		var player = AudioStreamPlayer.new()
		add_child(player)
		voices.append(player)
	for sound in ["pistol", "rifle", "shotgun", "hit", "kill", "reload", "empty", "enemy", "start"]:
		clips[sound] = _synthesize(sound)

func play(sound: String, volume: float = 0.0) -> void:
	if voices.is_empty() or not clips.has(sound):
		return
	var voice = voices[voice_index % voices.size()]
	voice_index += 1
	voice.stream = clips[sound]
	voice.volume_db = -11.0 + volume
	voice.pitch_scale = randf_range(0.97, 1.03)
	voice.play()

func _synthesize(kind: String) -> AudioStreamWAV:
	var rate = 22050
	var duration = 0.20
	if kind == "shotgun": duration = 0.38
	if kind in ["hit", "empty"]: duration = 0.075
	if kind == "start": duration = 0.42
	var data = PackedByteArray()
	var count = int(duration * rate)
	data.resize(count * 2)
	var rng = RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var low_noise = 0.0
	for i in count:
		var t = float(i) / rate
		var env = exp(-t * (17.0 if kind == "shotgun" else 30.0))
		var noise = rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.35)
		var value = 0.0
		match kind:
			"pistol": value = (noise * 0.55 + sin(TAU * 105.0 * t) * 0.45) * env
			"rifle": value = (noise * 0.7 + sin(TAU * 135.0 * t) * 0.3) * env
			"shotgun": value = (low_noise * 0.95 + sin(TAU * 64.0 * t) * 0.5) * env
			"enemy": value = (noise * 0.4 + sin(TAU * 120.0 * t) * 0.35) * env
			"hit": value = sin(TAU * 1350.0 * t) * exp(-t * 65) * 0.45
			"kill": value = (sin(TAU * 700.0 * t) + sin(TAU * 1050.0 * t)) * env * 0.3
			"reload": value = noise * (exp(-t * 80) + 0.6 * exp(-absf(t - 0.13) * 150)) * 0.6
			"empty": value = noise * exp(-t * 95) * 0.35
			"start": value = sin(TAU * (440.0 if t < 0.18 else 660.0) * t) * sin(PI * t / duration) * 0.25
		value *= minf(t * 2500.0, 1.0)
		var sample = int(clampf(value, -1.0, 1.0) * 22000)
		data.encode_s16(i * 2, sample)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
