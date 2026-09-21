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
## ЖУРНАЛ ДЛЯ СТЕНДА. Проверить «слышно ли монстра в погоне» на слух нельзя —
## в headless звука нет вообще, а на слух не отличить 22% от 100%. Поэтому
## каждый вызов можно записать: имя, громкость в децибелах и точку, откуда шёл.
## По умолчанию выключено и не стоит ничего.
var watch: bool = false
var heard: Array = []
var lost3d: int = 0                ## сколько звуков из точки не нашли места
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
## МУЗЫКА ЛАБИРИНТА. Два слоя, оба зациклены и звучат ВСЕГДА.
##
## Нижний — спокойный: редкие щипки минорного трезвучия, нота раз в две
## секунды. Он и есть «нормально в обычное время»: это музыка, а не гул
## комнаты, но она ничего не обещает и никуда не зовёт.
##
## Верхний — напряжение: та же тональность, но с малой секундой и тритоном,
## тянущимися без остановки. Он молчит, пока монстра нет рядом, и проступает
## тем сильнее, чем он ближе. Два слоя в одной тональности не спорят: пока
## верхний тих, слышна музыка; когда он громкий, та же музыка становится
## невыносимой, не меняя ни одной ноты.
##
## Шкатулка остаётся при своём — она вещь в детской, а не музыка игры.
var _mus_calm: AudioStreamPlayer
var _mus_tense: AudioStreamPlayer
var _mus_k: float = 0.0                 ## насколько близко он сейчас, 0..1
var _stings := {}                       ## удары под события, напечены при запуске
## БИТ ПОГОНИ. Отдельный зацикленный слой: он не «звучит в начале погони», он
## звучит ВСЮ погоню. Громкость и скорость зависят от того, насколько близко он
## за спиной, — значит бит сам по себе говорит, догоняет он или отстал.
var _beat_player: AudioStreamPlayer
var _beat_k: float = 0.0
## ПЕРЕХВАТ ДЛЯ ЛАБОРАТОРИИ. Музыка и бит — не разовые звуки, а УРОВНИ: мир
## задаёт их каждый кадр по расстоянию до монстра. Поэтому кнопка в
## лаборатории срабатывала и тут же затиралась миром — он сказал прямо:
## «удары работают, музыка и бит нет». Пока перехват включён, вызовы из мира
## игнорируются, и уровень держит тот, кто его задал.
var forced_mus: bool = false
var forced_beat: bool = false
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
	# СОЕДИНЕНИЕ ТОЧКИ. Стук стекла, 0.3 с, один удар. Отбирался мерками, как и
	# всё остальное: из пяти кандидатов пака только у него высоких на 6.7 дБ
	# ниже общего — остальные шипят, а этот звук игрок услышит пятнадцать раз
	# за одно полотно, и шипение на пятнадцатый раз становится пыткой.
	#
	# Синтез в запасе оставлен, но звучать он не должен: синтетические звуки в
	# этой игре уже пробовали и забраковали.
	# ШАГИ ПО СНЕГУ. Отдельный банк: мокрый хлюп из лабиринта на улице звучит
	# нелепо, а снег — единственная поверхность в игре, у которой свой голос.
	_load_pack("snow", "step_snow", 3, func(r): return _noise(0.16, 2200.0 * r, 0.5))
	# РЕЗ ПО ЖИВОМУ. Два банка, и разница между ними — это разница между
	# «задел» и «отрезал»: первый короткий и мокрый, второй длиннее и с низом.
	# Без них хват озвучивался ударом и хлыстом, то есть звуками драки, а не
	# звуками ножа в плоти.
	_load_pack("slice", "slice", 3, func(r): return _noise(0.22, 1800.0 * r, 0.6))
	_load_pack("sever", "sever", 3, func(r): return _noise(0.5, 900.0 * r, 0.8))
	# ШАГИ ПО ДОСКАМ. Третья поверхность: улица — снег, лабиринт — грязь, дом —
	# дерево. Без него в коридоре и детской стояла тишина, и она стала слышна
	# ровно в тот день, когда снаружи появился хруст.
	#
	# Глухие: у записей 98 и 93 процента энергии ниже 500 Гц — это башмак по
	# половице в жилом доме, а не костяшкой по фанере. Третья ярче и тише
	# остальных на пять децибел: так и ходят, не каждый шаг одинаков.
	_load_pack("wood", "step_wood", 3, func(r): return _noise(0.12, 900.0 * r, 0.6))
	_load_pack("link", "link", 1, func(r): return _tone(660.0 * r, 0.12, 0.3, "sine"))
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
	# УДАР ТЕПЕРЬ НАСТОЯЩИЙ, А НЕ СИНТЕЗ.
	#
	# Из трёх полос удара записью была одна, средняя; верх был щелчком белого
	# шума на шесть сотых секунды, низ — синтезированным «бумом». Вместе это
	# давало жидкий хлопок, и играющий три раза подряд сказал одно: звуки
	# резкой поимки слабые. Синтез остаётся запасным путём, если файлы
	# потеряются, — но звучать должны записи.
	_load_pack("hit_hi", "hit_hi", 3,
		func(r): return _noise(0.06, 7000.0 * r, 1.0, true))
	_load_pack("hit_mid", "hit_mid", 4, func(r): return _noise(0.45, 700.0 * r, 0.95))
	_load_pack("hit_low", "hit_low", 3, func(r): return _thump(r))
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
	# ЗАПИСИ, А НЕ СИНТЕЗ. Свои удары я делал дважды — «тихая нота пианино», а
	# потом «БУМ» на синусах, — и оба раза выходило то, что он назвал фигнёй.
	# Он прав: синтезом такое не делается. Здесь настоящие записи, сведённые
	# слоями (резкий транзиент плюс опущенный на полторы октавы гонг), а
	# синтез оставлен ровно на случай, когда файлов рядом нет: игра обязана
	# запускаться из голых скриптов.
	for pair in [["лицо", "sting_face"], ["угол", "sting_corner"],
			["погоня", "sting_chase"]]:
		var st = load("res://sfx/%s.wav" % pair[1])
		_stings[pair[0]] = st if st is AudioStreamWAV else _sting(pair[0])
	_beat_player = AudioStreamPlayer.new()
	_beat_player.stream = _loop_file("beat_loop", func(): return _beat())
	_beat_player.volume_db = -60.0
	add_child(_beat_player)
	_beat_player.play()
	_mus_calm = AudioStreamPlayer.new()
	_mus_calm.stream = _loop_file("mus_calm", func(): return _music_calm())
	_mus_calm.volume_db = MUS_CALM
	add_child(_mus_calm)
	_mus_calm.play()
	_mus_tense = AudioStreamPlayer.new()
	_mus_tense.stream = _loop_file("mus_tense", func(): return _music_tense())
	_mus_tense.volume_db = -60.0
	add_child(_mus_tense)
	_mus_tense.play()
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
	# ВОСЕМЬ, А НЕ ШЕСТЬ: шаги теперь звучат постоянно, и шести мест не хватало —
	# шаг вытеснял скрежет, скрежет вытеснял шаг.
	for i in 8:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 14.0
		p3.max_distance = 40.0
		# СТОРОНА ДОЛЖНА БЫТЬ СЛЫШНА. При обычной силе панорамы звук из точки
		# читается «где-то рядом»; игра же держится на том, чтобы понять, с
		# какой стороны он идёт, не видя его.
		p3.panning_strength = 2.6
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
	# ОГРАНИЧИТЕЛЬ НА МАСТЕРЕ. Бит погони, музыка на пике и удар могут сойтись
	# в одном кадре, и их сумма выйдет за шкалу. Цифровой перегруз звучит не
	# как «громко», а как треск оборванного динамика — то есть громкость,
	# которой он просил, обернулась бы браком. Ограничитель срезает вершины
	# мягко и только когда они есть.
	var m: int = AudioServer.get_bus_index("Master")
	if m >= 0:
		var has: bool = false
		for e in AudioServer.get_bus_effect_count(m):
			if AudioServer.get_bus_effect(m, e) is AudioEffectLimiter:
				has = true
				break
		if not has:
			var lim := AudioEffectLimiter.new()
			lim.ceiling_db = -0.8
			lim.threshold_db = -4.0
			lim.soft_clip_db = 2.0
			AudioServer.add_bus_effect(m, lim)


## Что считается музыкой: то, что звучит НОТАМИ. Шкатулка, её обрывки и тритон
## безумия — мотивы; гул, воздух, шаги и удары — мир, они на другой шине.
func _route() -> void:
	for pl in [_box_player, _shard_player, _mad_player, _mus_calm, _mus_tense,
			_beat_player]:
		if pl != null:
			pl.bus = BUS_MUS
	for pl in [_hum_player, _amb_player, _air_player]:
		if pl != null:
			pl.bus = BUS_SFX
	for pl in _pool:
		pl.bus = BUS_SFX
	for pl in _pool3d:
		pl.bus = BUS_SFX


## ЧЕГО НЕ ХВАТИЛО В СБОРКЕ — ЗАПИСЫВАЕМ.
##
## Пак, у которого не нашлось файлов, молча подменялся синтезом: в редакторе
## всё звучит записями, а в собранной игре — шипением, и разницы не видно
## ниоткуда. Так уехала к игроку сборка, где шагов по снегу не было вовсе:
## файлы лежали в проекте, но не попали в пакет, и банк собрался из шума.
##
## Теперь каждый такой случай остаётся в списке, а стенд его печатает.
var synth_banks: Array[String] = []
var short_banks: Array[String] = []

func _load_pack(name: String, prefix: String, count: int, fallback: Callable) -> void:
	var list: Array[AudioStreamWAV] = []
	for i in range(1, count + 1):
		var st = load("res://sfx/%s_%d.wav" % [prefix, i])
		if st is AudioStreamWAV:
			list.append(st)
	if list.is_empty():
		push_warning("Записи '%s' не найдены, беру синтез" % name)
		synth_banks.append(name)
		_bake(name, fallback)
	else:
		if list.size() < count:
			# Часть записей потерялась: банк работает, но вариантов меньше, чем
			# задумано, и на ходьбе это слышно как повтор.
			short_banks.append("%s (%d из %d)" % [name, list.size(), count])
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
	if watch:
		heard.append({"имя": name, "дб": volume_db, "где": Vector3.ZERO, "из точки": false})
	if not _bank.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _pick(name)
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + _rng.randf_range(-pitch, pitch)
			p.play()
			return


## С ЗАДАННЫМ ТОНОМ. Третий параметр play() — разброс вокруг единицы, а не тон,
## и пять вызовов в мире передавали туда тон: 0.55, 0.72, 0.92+… Разброс ±1.3
## уводил pitch_scale в ноль и ниже — Godot ругался в логе, а звук соединения
## точек то пищал, то пропадал. Здесь тон задаётся прямо, с лёгкой живостью.
func play_tone(name: String, volume_db: float, tone: float) -> void:
	if watch:
		heard.append({"имя": name, "дб": volume_db, "где": Vector3.ZERO, "из точки": false})
	if not _bank.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _pick(name)
			p.volume_db = volume_db
			p.pitch_scale = maxf(0.05, tone * (1.0 + _rng.randf_range(-0.03, 0.03)))
			p.play()
			return


## Звук с местом в пространстве: по нему игрок понимает, с какой стороны скребёт.
## must — «этот звук пропасть не должен». Восьми мест в пространстве хватало,
## пока тварь шумела раз в секунду; теперь у неё разом скрежет, опора восьми
## рук о пол и своя поступь — четыре-пять звуков в секунду, и очередь
## переполняется. Тихий шорох при этом молча вытеснял ШАГ, то есть ровно то
## единственное, по чему игрок понимает, с какой стороны он идёт. Обязательный
## звук забирает место у самого тихого из играющих.
func play_at(name: String, pos: Vector3, volume_db: float = 0.0,
		pitch: float = 1.0, must: bool = false) -> void:
	if watch:
		heard.append({"имя": name, "дб": volume_db, "где": pos, "из точки": true})
	if not _bank.has(name):
		return
	for p in _pool3d:
		if not p.playing:
			p.stream = _pick(name)
			p.global_position = pos
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return
	if not must:
		lost3d += 1
		return
	var тихий: AudioStreamPlayer3D = null
	for p in _pool3d:
		if тихий == null or p.volume_db < тихий.volume_db:
			тихий = p
	if тихий == null or тихий.volume_db > volume_db:
		lost3d += 1
		return
	тихий.stream = _pick(name)
	тихий.global_position = pos
	тихий.volume_db = volume_db
	тихий.pitch_scale = pitch
	тихий.play()


## ШАГ ТВАРИ. Мокрый шлепок из точки, где он стоит, и под ним глухой низ:
## тяжесть и сырость. Высота ниже обычной — он больше человека.
func stomp(pos: Vector3, volume_db: float = 0.0) -> void:
	# Отдельная отметка для стенда. Шаг собран из step_wet и hit_low, а те же
	# два звука бьют ещё и от опоры руки о пол и от щупальца о стену: считать
	# поступь по ним значит считать кашу. Первый замер на этом и обманулся.
	if watch:
		heard.append({"имя": "шаг", "дб": volume_db, "где": pos, "из точки": true})
	play_at("step_wet", pos, volume_db, 0.55, true)
	play_at("hit_low", pos, volume_db - 7.0, 0.7, true)


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
## Громкость спокойного слоя. Тише всего прочего нарочно: музыка, которую
## замечаешь, перестаёт быть фоном и начинает мешать слушать камень.
## ГРОМЧЕ. Первая версия была −19 и −11: он послушал и сказал «тихо». Музыку,
## которой не слышно, можно было и не писать.
const MUS_CALM := -12.0
const MUS_TENSE_MAX := -3.0
## Длина петли. Восемь секунд — это четыре щипка; короче слышен стык, длиннее
## незачем: музыку здесь никто не слушает целиком.
const MUS_LOOP := 8.0

## СПОКОЙНЫЙ СЛОЙ. Ля минор, щипки с длинным затуханием, нота раз в две
## секунды, плюс еле слышная выдержанная основа. Ноты берутся по кругу, но
## разной громкости — иначе за три петли рисунок выучивается наизусть.
func _music_calm() -> AudioStreamWAV:
	var n := int(RATE * MUS_LOOP)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var notes := [110.0, 164.81, 130.81, 220.0]      # ля, ми, до, ля
	var gains := [0.9, 0.62, 0.78, 0.44]
	for k in notes.size():
		var f: float = float(notes[k])
		var at: int = int(RATE * 2.0 * float(k))
		var len_i: int = int(RATE * 2.6)
		for i in len_i:
			var idx: int = at + i
			if idx >= n:
				break
			var t: float = float(i) / float(RATE)
			# Затухание быстрое в начале и длинный хвост: так звучит струна,
			# а не орган.
			var env: float = exp(-t * 1.7)
			var v: float = sin(t * f * TAU) * 0.62 \
				+ sin(t * f * 2.0 * TAU) * 0.20 \
				+ sin(t * f * 3.0 * TAU) * 0.08
			buf[idx] += v * env * float(gains[k]) * 0.30
	# Основа: выдержанное ля, почти неслышное. Оно склеивает щипки в музыку.
	for i in n:
		var t2: float = float(i) / float(RATE)
		buf[i] += sin(t2 * 55.0 * TAU) * 0.10 + sin(t2 * 55.3 * TAU) * 0.07
	return _from_float(buf, n)


## СЛОЙ НАПРЯЖЕНИЯ. Та же тональность — и малая секунда к основе. Два тона в
## полутоне друг от друга бьются с частотой их разности: чем громче слой, тем
## заметнее это биение, и оно читается как «что-то не так», а не как «играет
## страшная музыка».
func _music_tense() -> AudioStreamWAV:
	var n := int(RATE * MUS_LOOP)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t: float = float(i) / float(RATE)
		# 110 и 116.54 — малая секунда; 155.56 сверху — тритон, он и делает
		# созвучие нерешаемым.
		var v: float = sin(t * 110.0 * TAU) * 0.34 \
			+ sin(t * 116.54 * TAU) * 0.30 \
			+ sin(t * 155.56 * TAU) * 0.18 \
			+ sin(t * 233.08 * TAU) * 0.10
		# Медленное дыхание громкости: ровный тон ухо перестаёт слышать за
		# полминуты, а качающийся — нет.
		var breathe: float = 0.72 + 0.28 * sin(t * 0.37 * TAU)
		buf[i] = v * breathe * 0.5
	return _from_float(buf, n)


## Собрать зацикленный WAV из плавающей буферизации, с защитой от перегруза.
func _from_float(buf: PackedFloat32Array, n: int) -> AudioStreamWAV:
	var peak: float = 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	var k: float = 1.0 if peak < 0.001 else minf(1.0, 0.92 / peak)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * k, -1.0, 1.0) * 32767.0))
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## БЛИЗОСТЬ, 0..1. Мир зовёт это каждый кадр; здесь только сглаживание, чтобы
## музыка не дёргалась, когда монстр мелькнул за углом и пропал.
func music_near(k: float, delta: float) -> void:
	if forced_mus:
		return
	var want: float = clampf(k, 0.0, 1.0)
	# Вверх быстрее, чем вниз: подкрадывание должно быть слышно сразу, а отпускать
	# надо медленно — иначе «он ушёл» звучит как выключенный приёмник.
	var sp: float = 2.2 if want > _mus_k else 0.45
	_mus_k = move_toward(_mus_k, want, delta * sp)
	if _mus_tense != null:
		_mus_tense.volume_db = lerpf(-60.0, MUS_TENSE_MAX, _mus_k) \
			if _mus_k > 0.02 else -60.0
		# И выше по тону: к самому близкому расстоянию созвучие ползёт вверх
		# на полтора полутона. Слух не назовёт это, но напряжётся.
		_mus_tense.pitch_scale = 1.0 + _mus_k * 0.09
	if _mus_calm != null:
		# Спокойный слой при этом ПРИГЛУШАЕТСЯ: музыка уступает место тому,
		# что важнее, а не соревнуется с ним.
		_mus_calm.volume_db = MUS_CALM - _mus_k * 9.0


## УДАРЫ ПОД СОБЫТИЯ. Три момента, ради которых игра и существует, до сих пор
## озвучивались тем же, чем всё остальное: крик, хлыст, скрежет. Это работает
## как «что-то случилось» и не работает как «случилось ИМЕННО ЭТО».
##
## Делаем их в той же тональности, что музыка (ля), — тогда удар не звучит
## приклеенным поверх, он звучит как то, во что музыка сорвалась.
##
## Заводим один раз при запуске и держим в банке: печь такое на лету — это
## полсекунды тишины ровно там, где нужен удар.
func _sting(kind: String) -> AudioStreamWAV:
	# БУМ, А НЕ НОТА. Первая версия была построена как аккорд с затуханием —
	# музыкально и совершенно не страшно: «тихая нота пианино», как он и сказал.
	# Удар пугает не высотой и не громкостью, а ДВУМЯ вещами: мгновенной атакой
	# (первые двадцать миллисекунд — щелчок и широкополосный шум) и массой в
	# низу, которая уезжает ещё ниже.
	#
	# И перегрузом. Чистая синусоида даже на полной шкале звучит мягко; то, что
	# ухо зовёт «жёстким», — это срезанная вершина, то есть добавленные
	# гармоники. Поэтому в конце всё прогоняется через ограничение с запасом.
	var dur: float = 2.6 if kind == "лицо" else (2.2 if kind == "угол" else 1.6)
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# Низ, с которого начинается падение, и во сколько раз он падает.
	var f0: float = 150.0 if kind == "лицо" else 110.0
	var drive: float = 3.4 if kind == "лицо" else 2.8
	for i in n:
		var t: float = float(i) / float(RATE)
		# Скольжение вниз: экспонентой, а не прямой — так падает всё тяжёлое.
		var f: float = f0 * exp(-t * 2.1) + 26.0
		var ph: float = f * t
		var v: float = sin(ph * TAU) * 0.95 + sin(ph * 0.5 * TAU) * 0.55
		# УДАРНАЯ ЧАСТЬ. Двадцать миллисекунд шума во всю ширину: именно она
		# читается как «бум», а не как «загудело».
		if t < 0.022:
			var e: float = 1.0 - t / 0.022
			v += (randf() * 2.0 - 1.0) * 1.5 * e * e
		# Металлический призвук сверху, короткий: он даёт удару край.
		if t < 0.30:
			var e2: float = exp(-t * 16.0)
			v += (sin(t * 1870.0 * TAU) * 0.5 + sin(t * 2490.0 * TAU) * 0.35) * e2 * 0.6
		if kind == "лицо":
			# Крик струн: три тона в полутоне, скользящие вниз вместе с низом.
			var sl: float = 1.0 - t * 0.18
			var e3: float = exp(-t * 2.6)
			v += (sin(t * 440.0 * sl * TAU) + sin(t * 466.16 * sl * TAU)
				+ sin(t * 493.88 * sl * TAU)) * 0.22 * e3
		var env: float = exp(-t * (1.5 if kind == "лицо" else 1.9))
		buf[i] = clampf(v * env * drive, -1.0, 1.0)
	return _from_float_flat(buf, n)


## Взять запись и зациклить её. Петля задаётся ЗДЕСЬ, а не в настройках
## импорта: файл может прийти из архива без .import рядом, и тогда настройка
## потеряется молча — музыка сыграет один раз и замолчит.
func _loop_file(name: String, fallback: Callable) -> AudioStreamWAV:
	var st = load("res://sfx/%s.wav" % name)
	if not (st is AudioStreamWAV):
		push_warning("Запись '%s' не найдена, беру синтез" % name)
		return fallback.call()
	var w: AudioStreamWAV = st
	# КОНЕЦ ПЕТЛИ ЗАДАЁМ ВСЕГДА И САМИ.
	#
	# В .import стоит edit/loop_mode=1 и edit/loop_end=-1, и я решил, что этого
	# хватит. Не хватило: в движок это приходит как режим «вперёд» и конец
	# НОЛЬ, то есть петля нулевой длины. Godot такую не играет вообще —
	# проигрыватель молчит, play() не запускается даже повторно, а громкость
	# при этом послушно меняется. Поэтому всё выглядело исправным: я мерил
	# уровни у того, что не звучало ни секунды.
	#
	# Считаем конец от самих данных. Это верно, потому что эти файлы
	# импортируются без сжатия (compress/mode=0) — тот же режим, что у всех
	# остальных записей проекта.
	var bytes: int = 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var chans: int = 2 if w.stereo else 1
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = w.data.size() / (bytes * chans)
	return w


## БИТ ПОГОНИ. Не удар, а ПЕТЛЯ: пока он гонится, это должно долбить всё
## время, а не звякнуть один раз в начале. Четыре доли на два такта, бочка на
## каждой, между ними подбой — тот самый «жёсткий бит», который и напрягает,
## и гонит вперёд.
##
## Темп выбран быстрее пульса покоя и медленнее паники: 140 ударов в минуту.
## Ровно на этой границе тело начинает подстраиваться под звук.
func _beat() -> AudioStreamWAV:
	var bpm: float = 140.0
	var beat: float = 60.0 / bpm
	var bars: int = 2
	var dur: float = beat * 4.0 * float(bars)
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var beats: int = 4 * bars
	for b in beats:
		var at: int = int(float(b) * beat * RATE)
		# БОЧКА. Синус, падающий с 95 до 40 Гц за сто миллисекунд.
		for i in int(RATE * 0.34):
			var idx: int = at + i
			if idx >= n:
				break
			var t: float = float(i) / float(RATE)
			var f: float = 95.0 * exp(-t * 22.0) + 40.0
			var e: float = exp(-t * 9.0)
			var v: float = sin(f * t * TAU) * 1.2
			if t < 0.006:
				v += (randf() * 2.0 - 1.0) * 0.9 * (1.0 - t / 0.006)
			buf[idx] += v * e
		# ПОДБОЙ между долями: сухой шум, тише бочки вдвое.
		var at2: int = at + int(beat * 0.5 * RATE)
		for i2 in int(RATE * 0.09):
			var idx2: int = at2 + i2
			if idx2 >= n:
				break
			var t2: float = float(i2) / float(RATE)
			buf[idx2] += (randf() * 2.0 - 1.0) * 0.5 * exp(-t2 * 46.0)
	# Низкий гул под всем этим: он склеивает удары в бег, а не в метроном.
	for i3 in n:
		var t3: float = float(i3) / float(RATE)
		buf[i3] += sin(t3 * 55.0 * TAU) * 0.22 + sin(t3 * 82.41 * TAU) * 0.12
	for i4 in n:
		buf[i4] = clampf(buf[i4] * 1.35, -1.0, 1.0)
	return _from_float_flat(buf, n)


## Как _from_float, но БЕЗ выравнивания по пику: ударам и биту громкость уже
## задана в самом расчёте, и нормировка их только пригасит.
func _from_float_flat(buf: PackedFloat32Array, n: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## БИТ: включён или нет, и насколько близко он за спиной (0..1).
##
## Нарастание почти мгновенное — погоня начинается рывком, и бит должен
## успеть за ней. Спад медленный: когда он отстал, напряжение отпускает не
## сразу, и это правда о том, как это переживается.
const BEAT_MAX := -4.0

## Звучит ли сейчас бит погони. Нужно стенду: «погоня не прервалась» — это
## утверждение о звуке, и проверять его надо по звуку, а не по флагам мира.
func beat_on() -> bool:
	return _beat_k > 0.05


func beat_level(on: bool, near: float, delta: float) -> void:
	if _beat_player == null or forced_beat:
		return
	var want: float = clampf(near, 0.0, 1.0) if on else 0.0
	var sp: float = 5.0 if want > _beat_k else 0.7
	_beat_k = move_toward(_beat_k, want, delta * sp)
	if _beat_k <= 0.02:
		_beat_player.volume_db = -60.0
		return
	# Громкость идёт от нуля близости, но НЕ до нуля громкости: если он гонится,
	# бит слышен всегда, просто далеко — глуше.
	_beat_player.volume_db = lerpf(-17.0, BEAT_MAX, _beat_k)
	# И БЫСТРЕЕ, когда ближе: от 140 ударов в минуту до 168. Темп подгоняет
	# сильнее громкости — по нему слышно, что расстояние сокращается.
	_beat_player.pitch_scale = 1.0 + _beat_k * 0.20


## Задать уровень насильно и не отдавать его миру. Отрицательное значение
## снимает перехват и возвращает управление игре.
func music_force(k: float) -> void:
	forced_mus = k >= 0.0
	if not forced_mus:
		return
	_mus_k = clampf(k, 0.0, 1.0)
	if _mus_tense != null:
		_mus_tense.volume_db = lerpf(-60.0, MUS_TENSE_MAX, _mus_k) \
			if _mus_k > 0.02 else -60.0
		_mus_tense.pitch_scale = 1.0 + _mus_k * 0.09
	if _mus_calm != null:
		_mus_calm.volume_db = MUS_CALM - _mus_k * 9.0


func beat_force(k: float) -> void:
	forced_beat = k >= 0.0
	if _beat_player == null:
		return
	if not forced_beat:
		return
	_beat_k = clampf(k, 0.0, 1.0)
	if _beat_k <= 0.02:
		_beat_player.volume_db = -60.0
		return
	_beat_player.volume_db = lerpf(-17.0, BEAT_MAX, _beat_k)
	_beat_player.pitch_scale = 1.0 + _beat_k * 0.20


## ОБОРВАТЬ ВСЁ РАЗОВОЕ. Петли (музыка, бит, воздух) не трогаем — они фон.
## Нужно лаборатории: там жмут кнопки подряд, звуки ложатся друг на друга и
## каша выдаётся за поломку. В игре это не зовут: там наложение — правда.
func hush() -> void:
	for pl in _pool:
		pl.stop()
	for pl in _pool3d:
		pl.stop()


## Сыграть удар. Имена русские нарочно: их зовут из мира, где всё остальное
## тоже по-русски, и «sting_face» среди них читается как чужая строка.
func sting(kind: String, volume_db: float = 0.0) -> void:
	if watch:
		heard.append({"имя": "удар:" + kind, "дб": volume_db,
			"где": Vector3.ZERO, "из точки": false})
	if not _stings.has(kind):
		# МОЛЧА — ЗНАЧИТ НЕЗАМЕТНО. Ключи здесь русские («лицо», «угол»,
		# «погоня»), и вызовы с английскими именами просто ничего не играли:
		# три удара, добавленных ради страха, не звучали вовсе, и узналось это
		# случайно. Незнакомый ключ теперь виден в логе.
		push_warning("удар «%s» не найден: есть %s" % [kind, str(_stings.keys())])
		return
	for pl in _pool:
		if not pl.playing:
			pl.stream = _stings[kind]
			pl.volume_db = volume_db
			pl.pitch_scale = 1.0
			pl.play()
			return


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
			# ГРОМЧЕ МУЗЫКИ, А НЕ ПОД НЕЙ. Шкала была −34…−13 дБ, а спокойная
			# музыка идёт на −12: шкатулку на −29 (фон) и −26 (тварь рядом)
			# не слышал никто и никогда — «шкатулки не слышно» (18.09).
			_box_player.volume_db = lerpf(-30.0, -8.0, _box_now)
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
