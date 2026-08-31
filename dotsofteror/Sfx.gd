extends Node
## ТОЧКИ УЖАСА — звук. Синтезируется в коде, как и в браузерной версии:
## ни одного внешнего файла, всё считается при загрузке.
##
## Единственный сенсор игрока в первых двух фазах — СЛУХ. Пока монстр в камне,
## его не видно вообще, и вся угроза идёт только отсюда.
##
## РАЗБРОС обязателен. Шумовая начинка каждый раз своя, а вот высота, длина
## и огибающая в браузере повторялись один в один — ухо цепляется именно за них,
## и удар приедался за десяток повторов. Здесь каждый образец делается в нескольких
## вариантах, и при воспроизведении берётся случайный.

const RATE := 22050
const VARIANTS := 4          ## сколько вариантов каждого звука напечь

var _bank := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_bake("step",  func(r): return _noise(0.14, 900.0 * r, 0.35))
	_bake("skitter", func(r): return _noise(0.06, 4200.0 * r, 0.5, true))
	_bake("heart", func(r): return _tone(52.0 * r, 0.16, 0.7, "sine"))
	_bake("breath", func(r): return _noise(0.34, 700.0 * r, 0.3))
	_bake("scrape", func(r): return _noise(0.9, 520.0 * r, 0.45))
	_bake("door",  func(r): return _tone(520.0 * r, 0.5, 0.35, "sine"))
	_bake("ok",    func(r): return _tone(380.0 * r, 0.12, 0.35, "sine"))
	_bake("err",   func(r): return _tone(210.0 * r, 0.3, 0.5, "square"))
	_bake("ring",  func(r): return _tone(3100.0 * r, 0.45, 0.25, "sine"))
	_bake("whip",  func(r): return _noise(0.09, 5200.0 * r, 0.6, true))
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 6:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 14.0
		p3.max_distance = 40.0
		add_child(p3)
		_pool3d.append(p3)


func _bake(name: String, maker: Callable) -> void:
	var list: Array[AudioStreamWAV] = []
	for i in VARIANTS:
		var r := 0.88 + 0.24 * float(i) / float(VARIANTS - 1)   # ±12% по высоте
		list.append(maker.call(r))
	_bank[name] = list


func play(name: String, volume_db: float = 0.0) -> void:
	if not _bank.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _pick(name)
			p.volume_db = volume_db
			p.play()
			return


## Звук с местом в пространстве: по нему игрок понимает, с какой стороны скребёт.
func play_at(name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	if not _bank.has(name):
		return
	for p in _pool3d:
		if not p.playing:
			p.stream = _pick(name)
			p.global_position = pos
			p.volume_db = volume_db
			p.play()
			return


func _pick(name: String) -> AudioStreamWAV:
	var list: Array = _bank[name]
	return list[_rng.randi() % list.size()]


# ─────────────────────────── синтез ───────────────────────────

func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## Шум с однополюсным фильтром: низкий cutoff даёт глухой гул, высокий — шипение.
func _noise(dur: float, cutoff: float, vol: float, highpass: bool = false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var a: float = clampf(cutoff / float(RATE), 0.01, 0.95)
	var last := 0.0
	for i in n:
		var white: float = _rng.randf() * 2.0 - 1.0
		last = last + a * (white - last)
		var v: float = (white - last) if highpass else last
		var env: float = pow(1.0 - float(i) / float(n), 2.2)    # затухание
		var s: int = int(clampf(v * env * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	return _wav(data)


func _tone(freq: float, dur: float, vol: float, kind: String) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t: float = float(i) / float(RATE)
		var ph: float = fmod(t * freq, 1.0)
		var v: float
		match kind:
			"square":
				v = 1.0 if ph < 0.5 else -1.0
			"saw":
				v = ph * 2.0 - 1.0
			_:
				v = sin(ph * TAU)
		var env: float = pow(1.0 - float(i) / float(n), 1.6)
		var s: int = int(clampf(v * env * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	return _wav(data)
