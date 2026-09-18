extends RefCounted
## Настройки, которые переживают запуск игры.
##
## Все они одного рода: без них игру нельзя дать другому человеку. Вся ставка
## «Точек ужаса» сделана на звук и на темноту — а у чужого человека и колонки
## другие, и экран другой, и мышь другая. Если ему слишком громко, он снимет
## наушники; если слишком темно, увидит чёрный прямоугольник; если мышь летает,
## промахнётся и выйдет. Каждый раз он при этом решит, что игра такая.

const PATH := "user://settings.cfg"
const DEF_VOLUME := 0.8

static var volume: float = DEF_VOLUME
## МУЗЫКА И ЗВУКИ ПОРОЗНЬ. Это разные вещи, и убавлять их надо разными руками:
## мотив шкатулки через час лезет в уши и его хочется тише, а удар щупальца
## обязан остаться громким — он единственное предупреждение об опасности.
static var music: float = 1.0
static var sounds: float = 1.0
static var lang: String = "ru"
## 0 — низкое, 1 — среднее, 2 — высокое. Не «красивее/хуже», а сколько работы
## на каждый пиксель: на слабой машине разница между 25 и 50 кадрами.
static var quality: int = 1
## Своя мышь у каждого. Без этого рецензент крутанёт головой, промахнётся и
## закроет игру, ничего в ней не увидев.
static var mouse: float = 1.0
## ЯРКОСТЬ ЭКРАНА. Не «сделать красивее», а «увидеть вообще». Игра тёмная
## намеренно, но у одного OLED в тёмной комнате, у другого матовый ноутбук на
## кухне днём — и второй просто не увидит той работы, ради которой всё это
## делалось. Ниже 1.0 тоже разрешено: кому-то и так слишком светло.
static var gamma: float = 1.0
## ПАМЯТЬ МЕЖДУ ЗАПУСКАМИ. Нужна не для удобства, а для того, чтобы тварь могла
## сказать правду: сколько раз ты уже приходил, сколько раз умер и как давно
## тебя не было. Выдуманная угроза не работает, а названный факт работает.
static var runs: int = 0            ## сколько раз игру вообще запускали
static var deaths: int = 0          ## сколько раз доигрывали до смерти
static var last_seen: int = 0       ## время прошлого запуска, unix-секунды
## Фразы, которые дают ОДИН РАЗ ЗА ВСЮ ИГРУ. Они держатся на правде — «ты
## закрыл игру, я подождал», — и повторять их нельзя: во второй раз это уже не
## правда, а фокус.
static var said: PackedStringArray = PackedStringArray()


static func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		volume = clampf(float(cfg.get_value("audio", "volume", DEF_VOLUME)), 0.0, 1.0)
		lang = str(cfg.get_value("ui", "lang", "ru"))
		quality = clampi(int(cfg.get_value("ui", "quality", 1)), 0, 2)
		mouse = clampf(float(cfg.get_value("ui", "mouse", 1.0)), 0.25, 3.0)
		music = clampf(float(cfg.get_value("audio", "music", 1.0)), 0.0, 1.0)
		sounds = clampf(float(cfg.get_value("audio", "sounds", 1.0)), 0.0, 1.0)
		gamma = clampf(float(cfg.get_value("ui", "gamma", 1.0)), 0.6, 1.6)
		fullscreen = bool(cfg.get_value("ui", "fullscreen", false))
		binds = cfg.get_value("ui", "binds", {})
		runs = maxi(0, int(cfg.get_value("память", "runs", 0)))
		deaths = maxi(0, int(cfg.get_value("память", "deaths", 0)))
		last_seen = maxi(0, int(cfg.get_value("память", "last_seen", 0)))
		said = PackedStringArray(cfg.get_value("память", "said", PackedStringArray()))
	apply()


static func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sounds", sounds)
	cfg.set_value("ui", "lang", lang)
	cfg.set_value("ui", "quality", quality)
	cfg.set_value("ui", "mouse", mouse)
	cfg.set_value("ui", "gamma", gamma)
	cfg.set_value("ui", "fullscreen", fullscreen)
	cfg.set_value("ui", "binds", binds)
	cfg.set_value("память", "runs", runs)
	cfg.set_value("память", "deaths", deaths)
	cfg.set_value("память", "last_seen", last_seen)
	cfg.set_value("память", "said", said)
	cfg.save(PATH)


## Ползунок линейный, а слух — нет: на глаз половина ползунка должна звучать
## вдвое тише, а не на 6 дБ тише. Отсюда возведение в степень, а не прямое дБ.
static func apply() -> void:
	_apply_bus("Master", volume)
	_apply_bus("Музыка", music)
	_apply_bus("Звуки", sounds)


## Шины «Музыка» и «Звуки» заводит Sfx при рождении, а настройки читаются
## раньше — поэтому молча пропускаем то, чего ещё нет, и зовём apply() снова,
## когда ползунок трогают.
static func _apply_bus(name: String, level: float) -> void:
	var bus := AudioServer.get_bus_index(name)
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, level <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(pow(level, 1.6)))


static func set_quality(v: int) -> void:
	quality = clampi(v, 0, 2)
	save_all()


static func set_mouse(v: float) -> void:
	mouse = clampf(v, 0.25, 3.0)
	save_all()


# ─────────────────────────── яркость ───────────────────────────
## Полноэкранный слой со степенной кривой. Держим СПИСОК слоёв, а не один:
## сцен несколько (детская, лабиринт, смотровая), и ползунок в паузе должен
## менять картинку сразу, а не с перезапуска.
static var _gamma_rects: Array = []
const GAMMA_SHADER := preload("res://gamma.gdshader")


## Повесить слой яркости на сцену. Слой ОТРИЦАТЕЛЬНЫЙ: экранная текстура берёт
## всё, что нарисовано до неё, — при layer 0 и выше сюда попал бы и интерфейс,
## и надписи с меню поехали бы вместе с миром.
static func attach_gamma(root: Node) -> void:
	var cl := CanvasLayer.new()
	cl.layer = -1
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = GAMMA_SHADER
	r.material = m
	cl.add_child(r)
	root.add_child(cl)
	_gamma_rects.append(r)
	apply_gamma()


## При единице слой ПРЯЧЕТСЯ целиком. pow(c, 1.0) и так ничего не меняет, но
## это лишний полноэкранный проход у тех, кто настройку не трогал, — а таких
## большинство.
static func apply_gamma() -> void:
	var live: Array = []
	for r in _gamma_rects:
		if not is_instance_valid(r):
			continue
		live.append(r)
		r.visible = absf(gamma - 1.0) > 0.001
		(r.material as ShaderMaterial).set_shader_parameter("gamma", gamma)
	_gamma_rects = live


static func set_gamma(v: float) -> void:
	gamma = clampf(v, 0.6, 1.6)
	apply_gamma()
	save_all()


# ─────────────────────── инструменты создателя ───────────────────────
## ИНСТРУМЕНТЫ СОЗДАТЕЛЯ ТОЛЬКО У СОЗДАТЕЛЯ, и решает это СБОРКА, А НЕ ПАМЯТЬ.
##
## Дважды подряд я отдавал человеку сборку, забыв убрать кнопку смотровой со
## стартового экрана. Человек, который откроет смотровую раньше игры, увидит
## тварь целиком, при свете, и будет вертеть её кнопками — после этого играть
## уже не во что, весь первый акт держится на том, что её НЕ видно.
##
## Ручной шаг «не забыть убрать перед сборкой» я забыл два раза из двух. Значит,
## шага быть не должно: экспорт в релиз сам не берёт эти кнопки. У меня они на
## месте, потому что я запускаю ПРОЕКТ, а не собранную игру.
static func creator_tools() -> bool:
	return OS.is_debug_build() or OS.get_cmdline_user_args().has("создатель")


## ВЕРТИКАЛЬНЫЙ СРЕЗ — ОТДЕЛЬНАЯ СБОРКА, а не режим внутри игры.
##
## Срез отвечает на вопрос «как выглядит игра, когда она готова», и потому в нём
## не может быть ничего «пока грубовато». Отсюда единственный способ его сделать:
## не улучшать качество, а РЕЗАТЬ минуты, — меньше минут, значит каждую можно
## довести. Полная игра идёт сорок минут без нити; срез — пятнадцать.
##
## И главное, ради чего он вообще: в полной игре третья фаза наступает с шестого
## полотна из семи или с пятнадцатой минуты. То есть в пятнадцатиминутном показе
## её НЕ УВИДЯТ — человек уйдёт, не встретив того, чем игра хороша. В срезе вся
## дуга твари укладывается внутрь показа.
static func slice() -> bool:
	return OS.has_feature("srez") or OS.get_cmdline_user_args().has("срез")


# ─────────────────────── переназначение клавиш ───────────────────────
## СВОИ КЛАВИШИ. WASD лежит не у всех: на AZERTY это ZQSD, у кого-то стрелки,
## у кого-то левая рука занята. Физические коды спасают раскладку, но не привычку.
##
## Переназначается ТОЛЬКО клавиатура. Кнопки геймпада оставлены жёсткими: там
## раскладка стандартная, её не переучивают, а возможность снять нижнюю кнопку
## с рывка — это возможность запереть себя в захвате без выхода.
## НИТИ В СПИСКЕ НЕТ.
##
## Клавиша работает — G по-прежнему тянет ленту к цели, — но игра о ней больше
## нигде не рассказывает: ни на первом экране, ни в списке управления. Это
## подсказка для того, кто уже потерялся и сам её нашёл, а не предложение
## включить лёгкий режим до того, как стало трудно.
const BIND_ACTIONS := ["forward", "back", "left", "right", "run", "sprint",
	"quick_turn", "flash", "read", "journal"]

static var binds: Dictionary = {}
## Снимок заводской раскладки. Нужен для «вернуть заводские»: сбросить список
## своих клавиш мало — в живой раскладке останется назначенное, и кнопка будет
## врать до перезапуска. Снимается ОДИН раз, до того как применили свои.
static var _factory: Dictionary = {}


## Запомнить заводские клавиши. Зовётся один раз, перед apply_binds.
static func remember_defaults() -> void:
	if not _factory.is_empty():
		return
	for a in BIND_ACTIONS:
		var act: String = str(a)
		if not InputMap.has_action(act):
			continue
		for e in InputMap.action_get_events(act):
			if e is InputEventKey:
				_factory[act] = (e as InputEventKey).physical_keycode
				break


## Применить сохранённые привязки поверх заводских. Зовётся ПОСЛЕ того, как
## действия заведены (их заводят игрок и мир при рождении).
static func apply_binds() -> void:
	for a in binds.keys():
		var act: String = str(a)
		if not InputMap.has_action(act):
			continue
		# Снимаем только клавиатурные события: кнопки геймпада должны остаться.
		for e in InputMap.action_get_events(act):
			if e is InputEventKey:
				InputMap.action_erase_event(act, e)
		var ev := InputEventKey.new()
		ev.physical_keycode = int(binds[a])
		InputMap.action_add_event(act, ev)


static func bind_key(action: String, keycode: int) -> void:
	binds[action] = keycode
	apply_binds()
	save_all()


## Какая клавиша сейчас на действии — для показа в меню.
static func key_of(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k: int = (e as InputEventKey).physical_keycode
			return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k))
	return "—"


static func reset_binds() -> void:
	binds = {}
	save_all()
	# И вернуть живую раскладку, а не только забыть список.
	for a in _factory.keys():
		var act: String = str(a)
		if not InputMap.has_action(act):
			continue
		for e in InputMap.action_get_events(act):
			if e is InputEventKey:
				InputMap.action_erase_event(act, e)
		var ev := InputEventKey.new()
		ev.physical_keycode = int(_factory[a])
		InputMap.action_add_event(act, ev)


static func set_lang(v: String) -> void:
	lang = v
	save_all()


static func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	apply()
	save_all()


static func set_music(v: float) -> void:
	music = clampf(v, 0.0, 1.0)
	apply()
	save_all()


static func set_sounds(v: float) -> void:
	sounds = clampf(v, 0.0, 1.0)
	apply()
	save_all()


## СКОЛЬКО ДНЕЙ ПРОШЛО С ПРОШЛОГО РАЗА. Ноль — если запускают впервые или если
## возвращались в тот же день. Считаем ДО того, как отметим новый запуск.
static func days_away() -> int:
	if last_seen <= 0:
		return 0
	var gone: int = int(Time.get_unix_time_from_system()) - last_seen
	if gone < 0:
		return 0
	return gone / 86400


## Отметить запуск. Зовётся один раз при старте игры, после days_away().
static func note_run() -> void:
	runs += 1
	last_seen = int(Time.get_unix_time_from_system())
	save_all()


static func was_said(key: String) -> bool:
	return said.has(key)


static func note_said(key: String) -> void:
	if said.has(key):
		return
	said.append(key)
	save_all()


static func note_death() -> void:
	deaths += 1
	save_all()


## ПОЛНЫЙ ЭКРАН. Годо сам ничего на это не вешает: пока не заведёшь клавишу,
## окно так и остаётся окном, что бы игрок ни жал. F11 и Alt+Enter — то, что
## пробуют первым.
##
## ИСКЛЮЧИТЕЛЬНЫЙ, А НЕ ОБЫЧНЫЙ. На macOS обычный полный экран оставляет Dock и
## строку меню, которые выезжают, стоит мыши дойти до края, — играющий
## (18.09): «чтобы на полный экран становилась реально на полный экран».
## Исключительный режим уводит игру на свой рабочий стол и прячет их.
## И это настройка: помнится между запусками и ставится из меню.
static var fullscreen: bool = false


static func is_fullscreen() -> bool:
	var m: int = DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func apply_window() -> void:
	# Стенду окно не трогаем: прогоны сами по себе, и полный экран поверх
	# всего посреди работы — последнее, что нужно.
	if DisplayServer.get_name() == "headless" \
			or OS.get_cmdline_user_args().has("бот"):
		return
	if fullscreen:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	elif is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_window()
	save_all()


static func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())
