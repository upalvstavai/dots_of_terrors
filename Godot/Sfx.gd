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

const SettingsScript := preload("res://Settings.gd")

const RATE := 22050
const VARIANTS := 4          ## сколько вариантов каждого звука напечь
## Было -46..-11, и в третьей фазе фон выходил на -34 дБ — ТИШЕ ШАГОВ (-26).
## Услышать его было нельзя в принципе. Нижняя граница теперь на уровне гула
## полотна, верхняя давит по-настоящему.
const AMB_MIN := -34.0
const AMB_MAX := -6.0
const AMB_UP := 1.6          ## нарастает быстро: угроза приходит резко
const AMB_DOWN := 0.32       ## уходит медленно: облегчение не бывает мгновенным

# ───────── ХЛЮП: четыре числа, которые его целиком определяют ─────────
# Крути их и слушай — пересборка не нужна, звук печётся при запуске.
const SQ_Q := 0.955      ## добротность. 0.99+ звенит СВИСТОМ, 0.90 — глухой шлепок
const SQ_F0 := 430.0     ## частота в начале, Гц
const SQ_F1 := 165.0     ## частота в конце: падение вниз и есть «хлюп»
const SQ_DUR := 0.15     ## длительность, с. Больше 0.25 — уже хруст снега

var _bank := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _rng := RandomNumberGenerator.new()
var _hum_player: AudioStreamPlayer
var _amb_player: AudioStreamPlayer
## ВТОРОЙ СЛОЙ — ТРИТОН. Не украшение: 41 и 58 Гц дают самый неуютный интервал,
## какой есть, и он ПРИХОДИТ ПО БЕЗУМИЮ. Пока ты держишься, его нет; чем хуже
## лабиринт, тем громче под ним вторая нота. Мир портится не только на вид.
var _mad_player: AudioStreamPlayer
## Воздух третьей фазы: шорох на грани слышимости. Появляется, когда он вышел.
var _air_player: AudioStreamPlayer
var _mad_now: float = 0.0
var _mad_goal: float = 0.0
## ТИШИНА ПЕРЕД УДАРОМ. Пустота бьёт сильнее любого удара литавр: игрок не
## понимает почему, но подбирается. Считаем секунды, пока фон придавлен.
var _duck_t: float = 0.0
var _box_player: AudioStreamPlayer      ## шкатулка в детской
var _box_now: float = 0.0
var _box_goal: float = 0.0
var _shard_player: AudioStreamPlayer    ## её обрывки в лабиринте
var _amb_goal: float = 0.0     ## куда идём, 0..1
var _amb_now: float = 0.0      ## где сейчас — тянется к цели, без скачков


func _ready() -> void:
	_rng.randomize()
	_bake("step",  func(r): return _noise(0.14, 900.0 * r, 0.35))
	_load_pack("skitter", "skit", 3, func(r): return _noise(0.06, 4200.0 * r, 0.5, true))
	_load_pack("heart", "heart", 2, func(r): return _tone(52.0 * r, 0.16, 0.7, "sine"))
	_load_pack("breath", "breath", 1, func(r): return _noise(0.34, 700.0 * r, 0.3))
	_load_pack("scrape", "scrape", 4, func(r): return _noise(0.9, 520.0 * r, 0.45))
	# «door» — это ВСПЫШКА палочки, имя досталось от браузерной версии. Была
	# синусоида 520 Гц; стал резкий шумовой всплеск, как и положено вспышке.
	_load_pack("door", "flash", 1, func(r): return _tone(520.0 * r, 0.5, 0.35, "sine"))
	# Победа. Раньше её не было СОВСЕМ: единственный момент, ради которого игрок
	# прошёл весь лабиринт, проходил в тишине.
	_load_pack("win", "win", 2, func(r): return _tone(180.0 * r, 1.4, 0.6, "sine"))
	_bake("ok",    func(r): return _tone(380.0 * r, 0.12, 0.35, "sine"))
	# Промах звучит МОКРО, а не пищит. Прямоугольная волна 210 Гц читалась как
	# ошибка ввода в программе, а не как «полотно тебя не приняло».
	_load_pack("err", "err", 2, func(r): return _tone(210.0 * r, 0.3, 0.5, "square"))
	# ХЛЫСТ ТИШЕ. По построению это короткая вспышка белого шума: 0.09 с, срез
	# снизу на 5.2 кГц. На +6 дБ она встаёт на 25 дБ над всем вокруг — и слышно
	# её не как удар, а как включённые помехи, ровно в момент броска из стены.
	# Характер не трогаем: пробовал опустить срез и растянуть — стало только
	# больше верха, потому что фильтр здесь пологий. Уменьшаем саму громкость.
	_bake("whip",  func(r): return _noise(0.09, 5200.0 * r, 0.34, true))
	# УДАР ПОИМКИ. Раньше тут пищал квадратный тон на 210 Гц — звук ошибки
	# в меню, а не то, что тебя схватили. Настоящий удар состоит из трёх слоёв:
	# щелчок сверху (резкость), рык в середине (мясо), провал внизу (вес).
	_bake("hit_hi", func(r): return _noise(0.06, 7000.0 * r, 1.0, true))
	_load_pack("hit_mid", "hit_mid", 4, func(r): return _noise(0.45, 700.0 * r, 0.95))
	_bake("hit_low", func(r): return _thump(r))
	# Голос игрока. Синтезировать его я не взялся: подделка человеческого крика
	# звучит хуже тишины. Это записи, CC0, источник в sfx/ИСТОЧНИК.txt.
	_load_pack("scream", "scream", 3, func(r): return _noise(0.3, 900.0 * r, 0.8))
	_load_pack("strain", "strain", 2, func(r): return _noise(0.6, 700.0 * r, 0.7))
	# Рык. Им начинается атака фигуры: он замирает и тянет руки вверх.
	_load_pack("roar", "roar", 2, func(r): return _noise(1.2, 180.0 * r, 0.9))
	_bake("click", func(r): return _noise(0.05, 6000.0 * r, 1.0, true))
	_bake("drip", func(r): return _drop(r))
	_load_pack("step_wet", "step_wet", 3, func(r): return _squelch(r))
	_bake("pop", func(r): return _pop(r))
	_bake("splat", func(r): return _noise(0.13, 1400.0 * r, 0.4))
	_make_buses()
	_hum_player = AudioStreamPlayer.new()
	_hum_player.stream = _hum(48.0)
	_hum_player.volume_db = -60.0
	add_child(_hum_player)
	_amb_player = AudioStreamPlayer.new()
	_amb_player.stream = _drone(41.0)
	_amb_player.volume_db = AMB_MIN
	add_child(_amb_player)
	_mad_player = AudioStreamPlayer.new()
	# 58.0 к 41.0 — это почти ровно корень из двух, тритон. Тот самый интервал,
	# который в церковной музыке когда-то запрещали.
	_mad_player.stream = _drone(58.0)
	_mad_player.volume_db = -60.0
	add_child(_mad_player)
	_air_player = AudioStreamPlayer.new()
	_air_player.stream = _air()
	_air_player.volume_db = -60.0
	add_child(_air_player)
	_box_player = AudioStreamPlayer.new()
	_box_player.stream = _music_box()
	_box_player.volume_db = -60.0
	add_child(_box_player)
	_shard_player = AudioStreamPlayer.new()
	_shard_player.stream = _box_shard()
	_shard_player.volume_db = -16.0
	add_child(_shard_player)
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
	# Раскладка по шинам — ПОСЛЕ того, как все проигрыватели созданы.
	_route()
	# Шины родились только сейчас, а настройки читались раньше: разложить по ним
	# сохранённую громкость некому было. Зовём сами.
	SettingsScript.apply()


## Набор записей вместо синтеза. Если файлов нет — печём синтезированный
## запасной вариант: игра обязана запускаться из голых скриптов, без папки sfx.
##
## Записи все под CC0 (общественное достояние), источники — в sfx/ИСТОЧНИК.txt.
## Синтезом не даются ровно те звуки, у которых есть физическая история: хлюп
## босой ноги, камень по камню, вода. Шум с фильтром такое не подделывает.
## ДВЕ ШИНЫ ВМЕСТО ОДНОЙ. Громкость была общая, и убавить её можно было только
## целиком — а это разные вещи: мотив шкатулки человек может хотеть тише, потому
## что он лезет в уши через час, а удар щупальца обязан остаться громким, иначе
## пропадёт единственное предупреждение об опасности.
##
## Заводим прямо из кода, а не в настройках проекта: тогда звук работает сразу
## после того, как скрипт повесили на узел, и не разъезжается с проектом.
const BUS_MUS := "Музыка"
const BUS_SFX := "Звуки"


func _make_buses() -> void:
	for name in [BUS_MUS, BUS_SFX]:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		var i: int = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")


## Что считается музыкой: то, что звучит НОТАМИ. Шкатулка, её обрывки и тритон
## безумия — мотивы; гул, воздух, шаги и удары — мир, они на другой шине.
func _route() -> void:
	for pl in [_box_player, _shard_player, _mad_player]:
		if pl != null:
			pl.bus = BUS_MUS
	for pl in [_hum_player, _amb_player, _air_player]:
		if pl != null:
			pl.bus = BUS_SFX
	for pl in _pool:
		pl.bus = BUS_SFX
	for pl in _pool3d:
		pl.bus = BUS_SFX


func _load_pack(name: String, prefix: String, count: int, fallback: Callable) -> void:
	var list: Array[AudioStreamWAV] = []
	for i in range(1, count + 1):
		var st = load("res://sfx/%s_%d.wav" % [prefix, i])
		if st is AudioStreamWAV:
			list.append(st)
	if list.is_empty():
		push_warning("Записи '%s' не найдены, беру синтез" % name)
		_bake(name, fallback)
	else:
		_bank[name] = list


## Течение из пролома в потолке — зацикленное. Отдаётся наружу, потому что
## проигрыватель для него нужен свой на каждую дыру, с местом в пространстве.
func pour_stream() -> AudioStreamWAV:
	var st = load("res://sfx/pour_loop.wav")
	if not (st is AudioStreamWAV):
		return null
	var w: AudioStreamWAV = st
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	# НЕ -1. Для AudioStreamWAV это не «до конца», а петля нулевой длины, и звук
	# обрывается на первом же кадре. Границу считаем из длительности.
	w.loop_end = int(w.get_length() * float(w.mix_rate)) - 1
	return w


func _bake(name: String, maker: Callable) -> void:
	var list: Array[AudioStreamWAV] = []
	for i in VARIANTS:
		var r := 0.88 + 0.24 * float(i) / float(VARIANTS - 1)   # ±12% по высоте
		list.append(maker.call(r))
	_bank[name] = list


## pitch: разброс по высоте, ±доля. Нужен, когда вариантов записи мало: три
## образца без разброса приедаются за минуту ходьбы, с разбросом — нет.
func play(name: String, volume_db: float = 0.0, pitch: float = 0.0) -> void:
	if not _bank.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _pick(name)
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + _rng.randf_range(-pitch, pitch)
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


## ШЛЕПОК О КАМЕНЬ. Два слоя из места удара: вес толчка и мокрый хлюп massы.
## По отдельности первый — глухой стук без плоти, второй — шаг по луже; вместе
## это щупальце, которым приложились о стену.
func slap(pos: Vector3, volume_db: float = 0.0) -> void:
	play_at("hit_low", pos, volume_db)
	play_at("step_wet", pos, volume_db - 5.0)


func _pick(name: String) -> AudioStreamWAV:
	var list: Array = _bank[name]
	return list[_rng.randi() % list.size()]


# ─────────────────────────── синтез ───────────────────────────

## ВОЗДУХ. Шум, придавленный простым однополюсным фильтром и медленно дышащий
## по громкости. Ровный белый шум звучит телевизором; такой — сквозняком в
## камне, которого там быть не должно.
func _air() -> AudioStreamWAV:
	var n := int(RATE * 6.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / float(RATE)
		lp = lp * 0.986 + rng.randf_range(-1.0, 1.0) * 0.014
		# Два медленных дыхания разной длины: вместе они не повторяются на слух.
		var breath: float = 0.55 + 0.45 * sin(t * 0.21 * TAU) * cos(t * 0.13 * TAU)
		# 9.0 упиралось в предел и резало вершины: шум превращался в треск.
		# 4.6 оставляет запас, а громкость всё равно ведёт микшер.
		# 4.6 мерил по первой секунде и не увидел, что дыхание выводит пик к
		# 0.98 позже: вершины всё равно резались. 2.8 держит весь буфер.
		var s2: int = int(clampf(lp * 2.8 * breath, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s2)
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## ШКАТУЛКА. Восемь нот в ля миноре: ля до ми ре до ля соль-диез ля.
##
## Мотив нарочно простой — такой, какой напевают ребёнку. Неправильная в нём
## одна нота: предпоследняя, повышенная седьмая. Она тянет обратно в тонику
## слишком настойчиво, и от этого колыбельная звучит не уютно, а настойчиво.
## Заметить это нельзя, а почувствовать можно — на том и расчёт.
##
## Играет в детской. В лабиринте от неё останутся обрывки: те же ноты, ниже и
## медленнее. Так девочка, комната и тварь связываются звуком, без единого слова.
const BOX_NOTES := [440.0, 523.25, 659.25, 587.33, 523.25, 440.0, 415.30, 440.0]
const BOX_STEP := 0.46      ## секунд на ноту
## Хвоста нет. Раньше в конце петли стояли 2.6 с тишины — и на слух это была
## не «шкатулка кончила крутиться», а провал посреди музыки, каждые шесть секунд.
## Теперь мотив идёт без разрыва: затухание последних нот ЗАВОРАЧИВАЕТСЯ в
## начало буфера, поэтому и стыка не слышно, и щелчка на петле нет.
const BOX_TAIL := 0.0


## Одна нота шкатулки. Гребёнка звучит негармонично: обертоны сидят не на целых
## кратных, и верхние гаснут быстрее нижних — отсюда «стеклянный» звук.
func _bell(data: PackedByteArray, at: int, freq: float, dur: float,
		gain: float, wrap: bool = false) -> void:
	var n := int(RATE * dur)
	var parts := [[1.0, 1.00, 2.4], [2.02, 0.42, 3.6], [3.94, 0.22, 5.5],
		[6.18, 0.11, 7.8]]
	for i in n:
		var k: int = at + i
		# ЗАВОРАЧИВАЕМ. У петли нет «конца»: хвост последней ноты должен
		# доиграть поверх начала, иначе на стыке слышен обрыв.
		if wrap:
			k = k % (data.size() / 2)
		elif k * 2 + 1 >= data.size():
			return
		var t: float = float(i) / float(RATE)
		var v: float = 0.0
		for pr in parts:
			v += sin(t * freq * float(pr[0]) * TAU) * float(pr[1]) \
				* exp(-t * float(pr[2]))
		# Мягкая атака: без неё в начале ноты щелчок.
		v *= minf(1.0, t * 220.0) * gain
		var old: int = data.decode_s16(k * 2)
		data.encode_s16(k * 2, clampi(old + int(v * 9000.0), -32768, 32767))


## Мотив целиком.
func _music_box(pitch: float = 1.0, step: float = BOX_STEP,
		gain: float = 1.0) -> AudioStreamWAV:
	var total: float = step * float(BOX_NOTES.size()) + BOX_TAIL
	var n := int(RATE * total)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in BOX_NOTES.size():
		_bell(data, int(RATE * step * float(i)), float(BOX_NOTES[i]) * pitch,
			minf(step * 2.4, 1.5), gain, true)
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## ОБРЫВОК. Три ноты из той же восьмёрки, ниже на треть и втрое медленнее.
## В лабиринте узнаётся не мелодия, а её испорченность.
func _box_shard() -> AudioStreamWAV:
	var n := int(RATE * 4.2)
	var data := PackedByteArray()
	data.resize(n * 2)
	var pick := [0, 2, 6]
	for i in pick.size():
		_bell(data, int(RATE * (0.15 + 1.25 * float(i))),
			float(BOX_NOTES[int(pick[i])]) * 0.5, 2.2, 0.8)
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return w


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


## ГУЛ ПОЛОТНА. Зацикленный низкий тон: пока рисуешь, он тихо растёт.
## Это не музыка и не подсказка — это давление. Игрок не замечает, что стало
## громче, но начинает торопиться.
func _hum(freq: float) -> AudioStreamWAV:
	var n := int(RATE * 2.0)       # ровно два периода по секунде: стык не слышен
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t: float = float(i) / float(RATE)
		var v: float = sin(t * freq * TAU) * 0.6 \
			+ sin(t * freq * 1.5 * TAU) * 0.25 \
			+ sin(t * freq * 0.5 * TAU) * 0.3
		var s: int = int(clampf(v * 0.4, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## Фоновый гул мира — НЕ тот, что у полотна. Тот привязан к рисованию и звенит
## на 48 Гц; этот ниже и с биением: две почти одинаковые частоты расходятся на
## четверть герца и раз в четыре секунды сходятся заново. Ухо не слышит биение
## как звук, оно слышит его как беспокойство.
##
## Длина петли ровно четыре секунды, и каждая частота укладывается в неё целым
## числом периодов — иначе на стыке щёлкает, а петля играет часами.
func _drone(freq: float) -> AudioStreamWAV:
	var n := int(RATE * 4.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t: float = float(i) / float(RATE)
		# Обертоны обязательны. На одной основной ноутбучный динамик не отдаёт
		# ничего: он режет всё ниже полутора сотен герц. Вторая, третья и
		# четвёртая гармоники несут звук туда, где динамик ещё живой, а низ
		# остаётся для наушников.
		var v: float = sin(t * freq * TAU) * 0.50 \
			+ sin(t * (freq + 0.25) * TAU) * 0.42 \
			+ sin(t * freq * 2.0 * TAU) * 0.26 \
			+ sin(t * freq * 3.0 * TAU) * 0.14 \
			+ sin(t * freq * 4.0 * TAU) * 0.07
		var s: int = int(clampf(v * 0.34, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## Шипения телевизора БОЛЬШЕ НЕТ. Оно затыкало тишину в начале, но постоянный
## широкополосный шум за полчаса игры выматывает: от него нельзя отвернуться и
## нельзя к нему привыкнуть, он просто давит на слух. Начало теперь держат
## редкая капель и шаги.

## Хлюп. Шум, у которого полоса пропускания ЕДЕТ вниз по ходу звука: начинается
## широко, как удар по луже, и схлопывается в глухое чмоканье. Ровный фильтр
## давал бы обычный шаг по гравию.
func _squelch(r: float) -> AudioStreamWAV:
	var dur: float = SQ_DUR
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var y1 := 0.0
	var y2 := 0.0
	var lp := 0.0
	for i in n:
		var u: float = float(i) / float(n)
		# Возбуждение — короткий мягкий всплеск, и только он. Долгий шум сам по
		# себе звучит как снег под ногами, сколько его ни фильтруй.
		var drive: float = smoothstep(0.0, 0.06, u) * exp(-u * 7.0)
		var white: float = _rng.randf() * 2.0 - 1.0
		lp += 0.11 * (white - lp)
		# Резонатор с ПОЛЗУЩЕЙ ВНИЗ частотой. Вот в этом и есть хлюп: не в тембре
		# шума, а в том, что полость под подошвой схлопывается и тон падает.
		var f: float = (SQ_F0 - (SQ_F0 - SQ_F1) * u) * r
		var w: float = TAU * f / float(RATE)
		# Добротность НИЗКАЯ. При 0.9955 резонатор звенел чистым тоном — свист,
		# а не хлюп. Нужна окраска шума, а не собственный голос у фильтра.
		var q: float = SQ_Q
		var y: float = 2.0 * q * cos(w) * y1 - q * q * y2 + lp * drive
		y2 = y1
		y1 = y
		buf[i] = y * pow(1.0 - u, 1.5)
	# Нормировка обязательна: резонатор раскачивается непредсказуемо, и без неё
	# один вариант из четырёх выходит вдвое громче и в клиппинге.
	var pk := 0.0001
	for i in n:
		pk = maxf(pk, absf(buf[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] / pk * 0.72, -1.0, 1.0) * 32767.0))
	return _wav(data)


## НИЖНИЙ СЛОЙ УДАРА. Был пилообразный тон 58 Гц длиной 0.8 с — то есть ровно
## тот низкий тянущийся тон, который мы уже трижды опознавали как звук изо рта.
## Под ударом он гудел ещё полсекунды после того, как всё кончилось.
##
## Теперь это короткий толчок: шум возбуждает низкий резонанс, и тот гаснет за
## пятую долю секунды. Удар должен УДАРИТЬ и замолчать.
func _thump(r: float) -> AudioStreamWAV:
	var dur := 0.22
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var y1 := 0.0
	var y2 := 0.0
	for i in n:
		var u: float = float(i) / float(n)
		var drive: float = exp(-u * 34.0) * (_rng.randf() * 2.0 - 1.0)
		var f: float = (86.0 - 28.0 * u) * r
		var w: float = TAU * f / float(RATE)
		var q := 0.982
		var y: float = 2.0 * q * cos(w) * y1 - q * q * y2 + drive
		y2 = y1
		y1 = y
		buf[i] = y * pow(1.0 - u, 1.4)
	var pk := 0.0001
	for i in n:
		pk = maxf(pk, absf(buf[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] / pk * 0.9, -1.0, 1.0) * 32767.0))
	return _wav(data)


## КАПЛЯ. Высота ползёт ВВЕРХ, а не стоит на месте — и это не украшение, а
## физика: у попавшего в воду пузырька полость схлопывается, резонанс растёт,
## и именно по этому подъёму ухо узнаёт каплю.
##
## Раньше здесь был чистый тон 1250 Гц. Чистый ровный тон — это по определению
## писк прибора, и сорок точек капели вокруг давали очередь писков.


## КАПЛЯ. Высота ползёт ВВЕРХ, а не стоит на месте — и это не украшение, а
## физика: у попавшего в воду пузырька полость схлопывается, резонанс растёт,
## и именно по этому подъёму ухо узнаёт каплю.
##
## Раньше здесь был чистый тон 1250 Гц. Чистый ровный тон — это по определению
## писк прибора, и сорок точек капели вокруг давали очередь писков.
func _drop(r: float) -> AudioStreamWAV:
	var dur := 0.075
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var u: float = float(i) / float(n)
		var f: float = (620.0 + 1150.0 * pow(u, 0.7)) * r
		ph += f / float(RATE)
		var white: float = _rng.randf() * 2.0 - 1.0
		lp += 0.45 * (white - lp)
		# Шум только в первые миллисекунды — это удар о поверхность, дальше поёт
		# уже сама полость.
		var env: float = smoothstep(0.0, 0.004, u) * pow(1.0 - u, 2.2)
		buf[i] = (sin(ph * TAU) * 0.8 + lp * 0.5 * exp(-u * 26.0)) * env
	var pk := 0.0001
	for i in n:
		pk = maxf(pk, absf(buf[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] / pk * 0.8, -1.0, 1.0) * 32767.0))
	return _wav(data)


## ХЛОПОК лопнувшего пузыря. Один короткий удар с быстрым падением высоты —
## как «блоп» по поверхности воды.
##
## Раньше здесь был хруст костей: россыпь щелчков со случайными промежутками.
## Задумка была про ломающиеся кости, а ухо читало это как ТРЕЩИНУ — будто
## что-то раскололось. Пузырь лопается одним звуком, не серией.
func _pop(r: float) -> AudioStreamWAV:
	# 0.035 с, а не 0.11. И скольжение по высоте почти убрано: за сотню
	# миллисекунд ухо УСПЕВАЕТ проследить падение тона, и падающий свип — это
	# канонический выстрел из бластера. За тридцать пять миллисекунд следить
	# нечего, слышен просто «плип».
	var dur := 0.035
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var u: float = float(i) / float(n)
		var f: float = (610.0 - 90.0 * u) * r
		ph += f / float(RATE)
		var white: float = _rng.randf() * 2.0 - 1.0
		lp += 0.20 * (white - lp)
		var env: float = smoothstep(0.0, 0.006, u) * pow(1.0 - u, 1.8)
		buf[i] = (sin(ph * TAU) * 0.55 + lp * 0.7) * env
	var pk := 0.0001
	for i in n:
		pk = maxf(pk, absf(buf[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] / pk * 0.85, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Куда вести фон: 0 — тишина, 1 — полная громкость. Тянется сам, каждый кадр.
func amb_level(level: float) -> void:
	_amb_goal = clampf(level, 0.0, 1.0)


## Насколько испорчен мир: 0 — чисто, 1 — потолок безумия. Ведёт тритон и воздух.
func amb_madness(level: float) -> void:
	_mad_goal = clampf(level, 0.0, 1.0)


## Шкатулка в детской. level 0 — молчит. Громкость едет ПЛАВНО: обрыв мотива
## на полуноте слышен как поломка, а не как конец сцены.
func box_level(level: float) -> void:
	_box_goal = clampf(level, 0.0, 1.0)


## РАССТРОИТЬ ШКАТУЛКУ. Тот же мотив, но ниже и медленнее — вещь из детской,
## которую испортили. Это дешевле любой новой музыки и работает сильнее: мотив
## уже знаком, и узнаётся он раньше, чем игрок успевает понять, что узнал.
func box_pitch(v: float) -> void:
	if _box_player != null:
		_box_player.pitch_scale = clampf(v, 0.35, 1.6)


## Обрывок мотива в лабиринте. Редко и без предупреждения.
func box_shard() -> void:
	if _shard_player != null and not _shard_player.playing:
		_shard_player.play()


## ПРИДАВИТЬ ФОН. Зовётся ПЕРЕД ударом, а не во время: смысл в том, что за
## секунду до происходящего мир замолкает.
func amb_duck(seconds: float) -> void:
	_duck_t = maxf(_duck_t, seconds)


func _process(delta: float) -> void:
	if _amb_player == null:
		return
	if not is_equal_approx(_amb_now, _amb_goal):
		var speed: float = AMB_UP if _amb_goal > _amb_now else AMB_DOWN
		_amb_now = move_toward(_amb_now, _amb_goal, delta * speed)
		if _amb_now <= 0.002:
			if _amb_player.playing:
				_amb_player.stop()
		else:
			if not _amb_player.playing:
				_amb_player.play()
	# Придавливание считаем ПОСЛЕ разгона: оно должно перебивать всё остальное.
	if _duck_t > 0.0:
		_duck_t = maxf(0.0, _duck_t - delta)
	var duck: float = -40.0 if _duck_t > 0.0 else 0.0
	if _amb_player.playing:
		_amb_player.volume_db = lerpf(AMB_MIN, AMB_MAX, _amb_now) + duck
	# Шкатулка: вверх быстро, вниз медленно — уходит она дольше, чем приходит.
	if _box_player != null:
		var bs: float = 1.2 if _box_goal > _box_now else 0.35
		_box_now = move_toward(_box_now, _box_goal, delta * bs)
		if _box_now <= 0.002:
			if _box_player.playing:
				_box_player.stop()
		else:
			if not _box_player.playing:
				_box_player.play()
			_box_player.volume_db = lerpf(-34.0, -13.0, _box_now)
	_mad_now = move_toward(_mad_now, _mad_goal, delta * 0.25)
	if _mad_now <= 0.002:
		if _mad_player.playing:
			_mad_player.stop()
		if _air_player.playing:
			_air_player.stop()
	else:
		if not _mad_player.playing:
			_mad_player.play()
		_mad_player.volume_db = lerpf(-34.0, -11.0, _mad_now) + duck
		# Воздух приходит позже тритона: он про третью фазу, а не про вторую.
		var air_k: float = clampf((_mad_now - 0.45) / 0.55, 0.0, 1.0)
		if air_k <= 0.002:
			if _air_player.playing:
				_air_player.stop()
		else:
			if not _air_player.playing:
				_air_player.play()
			_air_player.volume_db = lerpf(-30.0, -14.0, air_k) + duck


func hum_start() -> void:
	if _hum_player == null:
		return
	_hum_player.volume_db = -22.0
	_hum_player.play()


## level 0..1 — насколько далеко зашло полотно.
## duck — насколько ЗАГЛУШИТЬ гул сверх обычного. Нужен отдельным множителем,
## а не через level: в начале полотна level и так на дне, и умножать там нечего,
## а провал в тишину должен работать с первой секунды.
func hum_level(level: float, duck: float = 0.0) -> void:
	if _hum_player == null or not _hum_player.playing:
		return
	# Было -34..-6 — почти не слышно. Гул должен ДАВИТЬ, а не намекать:
	# он начинается на грани заметности и к концу полотна заполняет собой всё.
	_hum_player.volume_db = lerpf(-22.0, 4.0, clampf(level, 0.0, 1.0)) - clampf(duck, 0.0, 1.0) * 34.0


func hum_stop() -> void:
	if _hum_player != null:
		_hum_player.stop()


## Схватили. Три слоя разом — резкость, мясо и вес. По отдельности каждый
## звучит бедно, вместе читается как удар.
func hit(volume_db: float = 6.0) -> void:
	play("hit_hi", volume_db)
	play("hit_mid", volume_db - 2.0)
	play("hit_low", volume_db)
