extends Control
## ТОЧКИ УЖАСА — стартовый экран.
##
## Это первое, что видит человек, и до сих пор это была стена текста шрифтом по
## умолчанию: двадцать четыре строки подряд — заголовок, три вступления, десять
## клавиш и одиннадцать правил. Играющий сказал коротко: «интерфейс нищий, а
## ведь это первое, что цепляет игрока».
##
## Переделан по трём правилам:
##
## 1. НА ПЕРВОМ ЭКРАНЕ — ТОЛЬКО ТО, БЕЗ ЧЕГО НЕ НАЧАТЬ. Заголовок, две строки
##    про то, куда ты идёшь, кнопка и клавиши. Правила ушли под кнопку: они
##    нужны тому, кто спросит, а не всем и сразу.
## 2. ТИПОГРАФИКА ОДНА НА ИГРУ. Гарнитуры и цвета берутся из UI.gd, своих тут
##    нет ни одного.
## 3. ФОН НЕ ПУСТОЙ. За текстом — та самая пентаграмма из первого полотна,
##    точками и линией: экран сразу говорит, чем в этой игре занимаются.

const Settings := preload("res://Settings.gd")
const Lang := preload("res://Lang.gd")
const Shapes := preload("res://Shapes.gd")
const UI := preload("res://UI.gd")

signal started
signal credits
signal viewer
signal settings

## Тексты живут в Lang.gd. Здесь только КЛЮЧИ и раскладка — чтобы правка
## формулировки не требовала лезть в разметку экрана.
##
## НИТИ ЗДЕСЬ БОЛЬШЕ НЕТ. Строка «нить: куда идти дальше» стояла на самом
## видном экране игры и предлагала включить подсказку раньше, чем человек
## успел растеряться. Клавиша осталась, и в паузе она описана — но приходить
## к ней надо от своей беспомощности, а не от стартового экрана.
const KEY_LEFT := [
	["W A S D", "k_move"],
	["", "k_look"],
	["", "k_dash"],
	["Q", "k_turn"],
]
const KEY_RIGHT := [
	["E", "k_read"],
	["F", "k_flash"],
	["J", "k_journal"],
	["ESC", "k_pause"],
]
const RULE_KEYS := ["r1", "r2", "r3", "r4", "r5", "r6", "", "r7", "r8", "", "r9"]

## Переживает перезагрузку сцены: после трёх поимок правила уже прочитаны,
## и заставлять читать их снова на пятой смерти — это наказание, а не подсказка.
static var seen: bool = false

var _t: float = 0.0
var _btn: Button
var _quit: Button
var _cred: Button
var _view: Button
var _set: Button

var _hot: float = 0.0            ## насколько «зажглась» кнопка под курсором
var _was_hot: bool = false       ## была ли она под курсором в прошлом кадре
var _snow: Array = []            ## снежинки на фоне: {x, y, скорость, снос, r}
var _trees: Array = []           ## силуэты ёлок, считаются один раз
var _sfx_hover: AudioStreamPlayer
var _sfx_click: AudioStreamPlayer

var _f_title: FontVariation
var _f_big: FontVariation
var _f_text: FontVariation
var _f_key: FontVariation
var _f_small: FontVariation


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, а не IGNORE: экран обязан ПЕРЕХВАТЫВАТЬ мышь, иначе щелчки уходят
	# в игру под ним — можно было крутить камеру и брать палочку сквозь заставку.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_f_title = UI.title(500, 18)
	_f_big = UI.title(400)
	_f_text = UI.text(400)
	_f_key = UI.text(600)
	_f_small = UI.text(400)
	_btn = UI.button(Lang.t("wake"), 19, UI.BLOOD, Color(1.0, 0.52, 0.44))
	_btn.custom_minimum_size = Vector2(260, 52)
	_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn.pressed.connect(_go)
	add_child(_btn)
	# НАСТРОЙКИ — ОТДЕЛЬНЫМ МЕНЮ. Здесь торчали ползунок громкости и язык, а
	# яркость, мышь и клавиши жили только в паузе. Играющий (18.09): «сделай
	# отдельное меню настроек в начале игры, снеси всё туда».
	_set = UI.button(Lang.t("settings"), 13, UI.DIM, UI.INK)
	_set.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_set.pressed.connect(func() -> void:
		_ping(_sfx_click)
		settings.emit())
	add_child(_set)
	_quit = UI.button(Lang.t("quit"), 13, UI.DIM, UI.INK)
	_quit.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_quit.pressed.connect(func() -> void: get_tree().quit())
	add_child(_quit)
	_cred = UI.button(Lang.t("credits"), 13, UI.DIM, UI.INK)
	_cred.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cred.pressed.connect(func() -> void: credits.emit())
	add_child(_cred)
	# СМОТРОВАЯ. Отдельная комната, где монстром можно управлять кнопками.
	# Это инструмент, а не часть игры, и В СОБРАННОЙ ИГРЕ ЭТОЙ КНОПКИ НЕТ:
	# решает Settings.creator_tools(), а не моя память — см. комментарий там.
	if Settings.creator_tools():
		_view = UI.button(Lang.t("viewer"), 12, Color(0.32, 0.46, 0.40),
			Color(0.55, 0.90, 0.70))
		_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_view.pressed.connect(func() -> void: viewer.emit())
		add_child(_view)
	_make_sound()
	set_process(true)


## ЗВУК КНОПКИ. Берём тот же стеклянный звоночек, которым в игре соединяются
## точки: меню должно звучать той же игрой, а не системным щелчком.
##
## Шину «Звуки» заводит Sfx при рождении мира; если её ещё нет — идём на мастер,
## чтобы кнопка звучала всегда, а не молчала из-за порядка создания узлов.
func _make_sound() -> void:
	var st = load("res://sfx/link_1.wav")
	if st == null:
		return
	_sfx_hover = AudioStreamPlayer.new()
	_sfx_hover.stream = st
	# Наведение — намёк: тише на двенадцать децибел и выше по тону.
	_sfx_hover.volume_db = -16.0
	_sfx_hover.pitch_scale = 1.6
	add_child(_sfx_hover)
	_sfx_click = AudioStreamPlayer.new()
	_sfx_click.stream = st
	_sfx_click.volume_db = -4.0
	_sfx_click.pitch_scale = 0.92
	add_child(_sfx_click)


## Шину выбираем В МОМЕНТ ЗВУКА, а не при рождении узла: меню создаётся раньше,
## чем мир заводит шины «Музыка» и «Звуки», и намертво записанная шина оставляла
## кнопку висеть на мастере — то есть мимо ползунка «звуки».
func _ping(pl: AudioStreamPlayer) -> void:
	if pl == null or pl.stream == null:
		return
	pl.bus = "Звуки" if AudioServer.get_bus_index("Звуки") >= 0 else "Master"
	pl.play()


func _process(delta: float) -> void:
	_t += delta
	# Размер берём у окна прямо: экран обязан закрывать мир целиком при любом
	# разрешении и после разворота на весь экран.
	size = get_viewport().get_visible_rect().size
	if _btn == null:
		return
	# РАСКЛАДКА ОТ СЕРЕДИНЫ, а не от края: на широком окне текст жался влево.
	var cx: float = size.x * 0.5
	# РАЗМЕР ЗАДАЁМ ЯВНО. custom_minimum_size узел вне контейнера считает
	# по-своему: кнопка выходила уже заданного, и рамка вокруг неё, которую
	# рисует _draw, обнимала пустоту рядом с текстом, а не текст.
	_btn.size = Vector2(260, 52)
	_btn.position = Vector2(cx - _btn.size.x * 0.5, size.y * 0.44)
	var bottom: float = size.y - 40.0
	_set.position = Vector2(cx - _set.size.x * 0.5 - 170.0, bottom)
	_cred.position = Vector2(cx - _cred.size.x * 0.5, bottom)
	_quit.position = Vector2(cx - _quit.size.x * 0.5 + 170.0, bottom)
	if _view != null:
		_view.position = Vector2(size.x - _view.size.x - 24.0, size.y - 40.0)
	# КНОПКА ЗАЖИГАЕТСЯ НЕ РЫВКОМ. Наведение и уход тянутся треть секунды:
	# мгновенное переключение читается ошибкой отрисовки, а не откликом.
	var hot_now: bool = _btn.is_hovered()
	if hot_now and not _was_hot:
		_ping(_sfx_hover)
	_was_hot = hot_now
	_hot = move_toward(_hot, 1.0 if hot_now else 0.0, delta * (3.4 if hot_now else 2.2))
	_fall_snow(delta)
	queue_redraw()


## СНЕГ НА ФОНЕ. Он тут не для красоты: экран обязан ЖИТЬ, иначе первая
## картинка игры — неподвижный текст, и человек не понимает, загрузилось ли.
func _fall_snow(delta: float) -> void:
	if _snow.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = 20260917
		for i in 110:
			_snow.append([r.randf(), r.randf(), r.randf_range(0.012, 0.045),
				r.randf_range(-0.010, 0.010), r.randf_range(0.8, 2.2), r.randf() * TAU])
	for f in _snow:
		f[1] += f[2] * delta
		f[5] += delta * 1.4
		if f[1] > 1.04:
			f[1] = -0.04
		f[0] += f[3] * delta + sin(f[5]) * delta * 0.006
		if f[0] < -0.05:
			f[0] += 1.1
		elif f[0] > 1.05:
			f[0] -= 1.1


## Только кнопка. «Любая клавиша» плоха тем, что игра начинается от случайного
## нажатия, пока человек ещё читает управление, — а читать там есть что.
## Подписи заново — после меню настроек, где могли сменить язык.
func relabel() -> void:
	_set.text = Lang.t("settings")
	_btn.text = Lang.t("wake")
	_quit.text = Lang.t("quit")
	_cred.text = Lang.t("credits")
	if _view != null:
		_view.text = Lang.t("viewer")
	queue_redraw()


func _go() -> void:
	_ping(_sfx_click)
	seen = true
	skip()
	started.emit()


## Спрятать без запуска: экран не нужен, но и тратить кадры на перерисовку
## невидимого узла незачем.
func skip() -> void:
	visible = false
	set_process(false)


func _draw() -> void:
	_draw_forest()
	# ВИНЬЕТКА: к краям экран уходит в чёрное. Ровная заливка читается
	# страницей, а нам нужно, чтобы свет был только там, где текст.
	var steps := 18
	for i in steps:
		var t: float = float(i) / float(steps)
		var w: float = size.x * 0.5 * (1.0 - t)
		draw_rect(Rect2(Vector2(0, 0), Vector2(w * 0.24, size.y)),
			Color(0, 0, 0, 0.055))
		draw_rect(Rect2(Vector2(size.x - w * 0.24, 0), Vector2(w * 0.24, size.y)),
			Color(0, 0, 0, 0.055))
	# ПОДПИСЬ ГРОМКОСТИ И РАМКА КНОПКИ — НА ОБЕИХ СТРАНИЦАХ. Раньше страница
	# правил выходила из _draw раньше них, и на ней ползунок оставался без
	# подписи, а кнопка — без рамки: одна и та же кнопка выглядела на двух
	# экранах по-разному.
	_draw_btn_frame()
	var cx: float = size.x * 0.5
	var y: float = maxf(96.0, size.y * 0.17)
	draw_string(_f_title, Vector2(0, y), Lang.t("title"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 74, UI.INK)
	y += 26.0
	UI.rule(self, Vector2(cx, y), 420.0, UI.BLOOD)
	y += 26.0
	draw_string(_f_small, Vector2(0, y), Lang.t("sub"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, UI.DIM)
	y += 58.0
	for k in ["intro1", "intro2", "intro3"]:
		draw_string(_f_text, Vector2(0, y), Lang.t(k),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, UI.INK if k != "intro3" else UI.DIM)
		y += 28.0
	# ОДНА СТРОКА — ГДЕ ИСКАТЬ. Без неё новичок не знает, что управление и
	# правила вообще где-то есть: друг (18.09) так и не нашёл объяснений.
	draw_string(_f_small, Vector2(0, size.y * 0.44 + 92.0), Lang.t("howto_hint"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, UI.DIM)
	# КЛАВИШ И ПРАВИЛ ЗДЕСЬ БОЛЬШЕ НЕТ — они в настройках, на странице «Как
	# играть». Играющий (18.09): «снеси всё туда, про управление…». На первом
	# экране — только решение играть.
func _draw_btn_frame() -> void:
	# РАМКА КНОПКИ — ЭТО ПОЛОТНО В МИНИАТЮРЕ.
	#
	# Просто рамка ничего не говорит. Здесь по углам лежат четыре точки, а
	# когда наводишь курсор, между ними ПРОВОДИТСЯ ЛИНИЯ — ровно то, что игрок
	# будет делать всю игру. Уводишь курсор — линия сходит обратно.
	#
	# Рисуется залитыми полосками, а не draw_rect(filled=false) и не линиями:
	# незаполненный прямоугольник рисует только боковые стороны, а линия
	# толщиной в пиксель пропадает при сжатии кадра с 1920 до размера окна.
	var p0: Vector2 = _btn.position - Vector2(2, 2)
	var wsz: Vector2 = _btn.size + Vector2(4, 4)
	var corners: Array[Vector2] = [p0, p0 + Vector2(wsz.x, 0.0), p0 + wsz,
		p0 + Vector2(0.0, wsz.y)]
	# Дыхание остаётся, но только пока курсора нет: под курсором мигать нечему,
	# там идёт линия.
	var idle: float = (0.24 + 0.16 * sin(_t * 2.0)) * (1.0 - _hot)
	var base := Color(UI.BLOOD.r, UI.BLOOD.g, UI.BLOOD.b, idle)
	var th: float = 1.5
	draw_rect(Rect2(p0, Vector2(wsz.x, th)), base)
	draw_rect(Rect2(Vector2(p0.x, p0.y + wsz.y - th), Vector2(wsz.x, th)), base)
	draw_rect(Rect2(p0, Vector2(th, wsz.y)), base)
	draw_rect(Rect2(Vector2(p0.x + wsz.x - th, p0.y), Vector2(th, wsz.y)), base)
	# ТОЧКИ ПО УГЛАМ — всегда, и разгораются под курсором.
	var dot := Color(UI.BLOOD.r, UI.BLOOD.g, UI.BLOOD.b, 0.45 + 0.55 * _hot)
	for c in corners:
		draw_circle(c, 2.0 + 1.4 * _hot, dot)
	if _hot <= 0.001:
		return
	# ЛИНИЯ ПО ПЕРИМЕТРУ. Идёт от левого верхнего угла по часовой стрелке
	# ровно на ту долю, до которой успела разгореться кнопка.
	var per: float = 2.0 * (wsz.x + wsz.y)
	var want: float = per * _hot
	var head: Vector2 = corners[0]
	var gone: float = 0.0
	var line := Color(1.0, 0.52, 0.44, 0.30 + 0.55 * _hot)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var seg: float = a.distance_to(b)
		if gone + seg <= want:
			_bar(a, b, line)
			head = b
		else:
			var k: float = clampf((want - gone) / maxf(seg, 0.001), 0.0, 1.0)
			if k > 0.0:
				head = a.lerp(b, k)
				_bar(a, head, line)
			break
		gone += seg
	# Кончик линии — светлая точка: это «карандаш», который её ведёт.
	draw_circle(head, 3.0, Color(1.0, 0.72, 0.62, 0.85))


## Отрезок залитой полоской: годится только для сторон прямоугольника, зато
## переживает сжатие кадра, в отличие от draw_line толщиной в пиксель.
func _bar(a: Vector2, b: Vector2, col: Color) -> void:
	var th: float = 1.8
	if absf(a.y - b.y) < 0.5:
		draw_rect(Rect2(Vector2(minf(a.x, b.x), a.y - th * 0.5),
			Vector2(absf(b.x - a.x), th)), col)
	else:
		draw_rect(Rect2(Vector2(a.x - th * 0.5, minf(a.y, b.y)),
			Vector2(th, absf(b.y - a.y))), col)


## ФОН: ЗИМНИЙ ЛЕС ЗА ОКРАИНОЙ.
##
## Был чёрный прямоугольник с еле видной пентаграммой — то есть фона не было
## вовсе. Играющий сказал: «просто текст на чёрном».
##
## Картинку не берём: фотография зимнего леса спорила бы с самой игрой, где
## всё собрано из простых форм. Лес рисуется тут же, из тех же форм: небо
## полосами, луна, три ряда елей от светлого к чёрному и снег, который падает
## по-настоящему. Дальний ряд светлее и синее ближнего — это и есть воздух,
## из-за него лес читается глубоким, а не наклейкой.
func _draw_forest() -> void:
	var w: float = size.x
	var h: float = size.y
	var horizon: float = h * 0.66
	# НЕБО. Сверху ночь, к горизонту — холодный отсвет, как над снегом.
	var bands := 30
	for i in bands:
		var t: float = float(i) / float(bands)
		var c: Color = Color(0.016, 0.018, 0.030).lerp(
			Color(0.10, 0.13, 0.19), pow(t, 2.2))
		draw_rect(Rect2(0.0, horizon * t, w, horizon / float(bands) + 1.0), c)
	# ЛУНА. Ореол собирается из восьми колец, а не из двух: два давали серый
	# блин с видимой границей — на кадре это читалось кляксой интерфейса, а не
	# луной. И ниже к горизонту, чтобы не спорить с заглавием.
	var moon := Vector2(w * 0.80, h * 0.27)
	for i in 8:
		var t: float = float(i) / 8.0
		draw_circle(moon, h * (0.075 - 0.062 * t),
			Color(0.74, 0.82, 1.0, 0.012 + 0.016 * t))
	draw_circle(moon, h * 0.013, Color(0.95, 0.96, 1.0, 0.62))
	# Отсвет над лесом: у горизонта небо всегда светлее, и от этого лес
	# читается стоящим В воздухе, а не наклеенным на небо.
	for i in 10:
		var tg: float = float(i) / 10.0
		draw_rect(Rect2(0.0, horizon - h * 0.10 * (1.0 - tg), w, h * 0.011),
			Color(0.30, 0.38, 0.52, 0.020 * tg))
	# ЗЕМЛЯ. Снег светлее неба и к низу светлеет ещё: под ногами он ближе.
	# СОРОК ПОЛОС, А НЕ ЧЕТЫРНАДЦАТЬ: на светлом снегу ступеньки градиента
	# видно глазом, и ровное поле распадалось на грядки.
	for i in 40:
		var t2: float = float(i) / 40.0
		draw_rect(Rect2(0.0, horizon + (h - horizon) * t2, w,
			(h - horizon) / 40.0 + 1.0),
			Color(0.11, 0.14, 0.21).lerp(Color(0.26, 0.30, 0.38), t2))
	if _trees.is_empty():
		_grow_trees()
	for t3 in _trees:
		_fir(float(t3[0]) * w, horizon + float(t3[1]) * h, float(t3[2]) * h,
			float(t3[3]) * h, t3[4])
	# СНЕГ поверх леса.
	for f in _snow:
		var a: float = 0.10 + float(f[4]) * 0.16
		draw_circle(Vector2(float(f[0]) * w, float(f[1]) * h), float(f[4]),
			Color(0.90, 0.94, 1.0, a))
	# ВИНЬЕТКА: к краям всё уходит в чёрное, чтобы текст читался поверх леса.
	# Виньетка тоже мельче шагом: на снегу её ступени читались вертикальными
	# полосами поперёк леса.
	for i in 44:
		var t4: float = float(i) / 44.0
		var ww: float = w * 0.32 * (1.0 - t4)
		draw_rect(Rect2(0.0, 0.0, ww, h), Color(0, 0, 0, 0.026))
		draw_rect(Rect2(w - ww, 0.0, ww, h), Color(0, 0, 0, 0.026))
	# И ПОЛОСА ПОД ТЕКСТОМ. Лес красив, но заглавие важнее: середину экрана
	# притеняем, иначе белый текст ложится на светлое небо и пропадает.
	for i in 32:
		var t5: float = float(i) / 32.0
		draw_rect(Rect2(0.0, h * (0.04 + 0.48 * t5), w, h * 0.48 / 32.0 + 1.0),
			Color(0.01, 0.01, 0.02, 0.030))


## Ряды елей: дальние мелкие и синие, ближние крупные и чёрные. Сид постоянный —
## лес не должен перерисовываться заново при каждом возврате в меню.
func _grow_trees() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4711
	var rows := [
		[0.030, 0.012, Color(0.15, 0.19, 0.27), 34, -0.010],
		[0.070, 0.026, Color(0.08, 0.10, 0.16), 22, 0.020],
		[0.150, 0.055, Color(0.028, 0.032, 0.050), 12, 0.080],
	]
	for row in rows:
		var hh: float = float(row[0])
		var ww: float = float(row[1])
		var col: Color = row[2]
		var n: int = int(row[3])
		var base: float = float(row[4])
		for i in n:
			var x: float = (float(i) + r.randf_range(-0.42, 0.42)) / float(n)
			_trees.append([x, base + r.randf_range(-0.004, 0.004),
				hh * r.randf_range(0.7, 1.3), ww * r.randf_range(0.8, 1.2), col])


## Одна ель: три яруса лап. Треугольник читается горой, а не деревом, — ярусы
## и есть вся разница.
func _fir(x: float, base_y: float, hgt: float, wid: float, col: Color) -> void:
	var tiers := 3
	for i in tiers:
		var t: float = float(i) / float(tiers)
		var top: float = base_y - hgt * (0.42 + 0.58 * t)
		var bot: float = base_y - hgt * t * 0.52
		var half: float = wid * (1.0 - t * 0.62)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, top), Vector2(x + half, bot), Vector2(x - half, bot)]), col)
	# Ствол: две-три точки внизу, иначе ель висит в воздухе.
	draw_rect(Rect2(x - wid * 0.06, base_y - hgt * 0.06, wid * 0.12, hgt * 0.08), col)
