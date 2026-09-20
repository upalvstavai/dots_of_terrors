extends Control
## ВИДЕНИЕ: что проступает на полотне, когда точки соединены.
##
## До сих пор полотно не значило ничего. Игрок соединял точки, полотно
## сгоралось, счётчик прибавлял единицу — и всё; играющий сказал прямо:
## «полотна бесполезны, у них нет задачи, кроме как открыть последнюю дверь».
## Картинка и есть задача: за каждым полотном спрятан кадр чужой истории, и
## семь кадров складываются в неё целиком.
##
## ПОЧЕМУ РИСУЕТСЯ КОДОМ, А НЕ КАРТИНКОЙ ИЗ ФАЙЛА. Всю игру игрок ведёт линию
## светящейся краской по тёмному холсту. Если после этого показать
## нарисованную кем-то картинку, она придёт из другой игры. Здесь то же
## полотно, та же краска и та же рука: изображение ПРОЯВЛЯЕТСЯ штрих за
## штрихом, будто его дорисовали за игрока, и с него так же течёт краска.

const UI := preload("res://UI.gd")
const Lang := preload("res://Lang.gd")

signal closed

## Краска игрока. Тот же цвет, которым он вёл линии, — см. Board.PAINT.
const PAINT := Color(0.22, 1.0, 0.62)
## Синий — только для глаз твари. Единственный чужой цвет на всех семи листах:
## он и связывает картинки с тем, что ходит в стенах.
const EYE := Color(0.42, 0.72, 1.0)
const SHOW := 7.0              ## сколько держится, если не закрыть самому
const DRAW_T := 2.6            ## за сколько проявляется рисунок

var index: int = 0             ## какое полотно сдано, 0..6
var t: float = 0.0
var live: bool = false
var _rng := RandomNumberGenerator.new()
var _drips: Array = []
## ЛИСТ — ОТДЕЛЬНЫЙ УЗЕЛ, И ОН ОБРЕЗАЕТ. Свечение и подтёки рисовались поверх
## всего экрана: кольца света вылезали за раму, и картинка читалась не листом,
## а заставкой. Дочерний Control с clip_contents режет всё по краю бумаги.
var _sheet_node: Control
## Мягкое пятно света. Кольца кругов давали видимые ступени; радиальный
## градиент — то же свечение, что у лампы на полотне, и без полос.
var _glow: GradientTexture2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_glow = GradientTexture2D.new()
	_glow.width = 128
	_glow.height = 128
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.35))
	_glow.gradient = g
	_sheet_node = Control.new()
	_sheet_node.clip_contents = true
	_sheet_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_node.draw.connect(_draw_sheet)
	add_child(_sheet_node)
	set_process(false)


## Показать картинку номер n (0..6).
func show_one(n: int) -> void:
	index = clampi(n, 0, 6)
	_rng.seed = 4100 + index
	t = 0.0
	_drips.clear()
	live = true
	visible = true
	size = get_viewport().get_visible_rect().size
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	# РАЗМЕР БЕРЁМ У ОКНА КАЖДЫЙ КАДР. Узел лежит в своём слое, и preset
	# сам по себе его не растягивает: лист рисовался в углу размером с марку.
	size = get_viewport().get_visible_rect().size
	var b0 := _sheet()
	_sheet_node.position = b0.position
	_sheet_node.size = b0.size
	_sheet_node.queue_redraw()
	t += delta
	# Подтёки заводятся по ходу проявления: краска свежая и не держится.
	if t < DRAW_T and _drips.size() < 14 and _rng.randf() < delta * 9.0:
		var b := _sheet()
		_drips.append({
			"x": _rng.randf() * b.size.x,
			"y": b.size.y * _rng.randf_range(0.15, 0.8),
			"len": _rng.randf_range(18.0, 90.0),
			"w": _rng.randf_range(1.4, 3.2),
			"t": 0.0})
	for d in _drips:
		d["t"] += delta
	if t >= SHOW:
		_close()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not live:
		return
	# Закрыть можно в любой момент: держать человека перед картинкой силой —
	# верный способ сделать так, чтобы её возненавидели.
	if event.is_action_pressed("read") or event.is_action_pressed("sprint") \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if not live:
		return
	live = false
	visible = false
	set_process(false)
	closed.emit()


## Лист. Отношение сторон — как у самих картинок (16:9): иначе по краям
## остаются чёрные поля, и лист перестаёт быть листом.
func _sheet() -> Rect2:
	var w: float = size.x * 0.66
	var h: float = w * 0.5627
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.46, w, h)


## Сколько рисунка уже проступило, 0..1. Проявляется не равномерно: сначала
## быстро — «вспомнилось», — потом дорисовывается медленнее.
func _k() -> float:
	var k: float = clampf(t / DRAW_T, 0.0, 1.0)
	return k * (2.0 - k)


## Гаснет к концу показа, чтобы не пропадать рывком.
func _fade() -> float:
	if t > SHOW - 0.8:
		return clampf((SHOW - t) / 0.8, 0.0, 1.0)
	return clampf(t / 0.25, 0.0, 1.0)


func _draw() -> void:
	var f: float = _fade()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.015, 0.92 * f))
	var b := _sheet()
	# Рама вокруг листа: тот же тёмный дуб, что у мольберта в мире.
	draw_rect(Rect2(b.position - Vector2(14, 14), b.size + Vector2(28, 28)),
		Color(0.16, 0.13, 0.11, f))
	# Подпись снизу: номер листа из семи. Ни слова о том, что на нём.
	draw_string(UI.text(500), Vector2(b.position.x, b.position.y + b.size.y + 36.0),
		"%d / 7" % (index + 1), HORIZONTAL_ALIGNMENT_RIGHT, b.size.x, 14,
		Color(0.52, 0.51, 0.49, f))


# ─────────────────────────── проявление ───────────────────────────

## ПРОЯВЛЯЕТСЯ, А НЕ ПОЯВЛЯЕТСЯ. Картинка не включается разом: сверху вниз
## идёт полоса, за которой бумага «намокает» и рисунок проступает. Это та же
## мысль, что и у прожига полотна: игрок должен видеть, как оно происходит.
func _draw_sheet() -> void:
	var f: float = _fade()
	var b := Rect2(Vector2.ZERO, _sheet_node.size)
	_sheet_node.draw_rect(b, Color(0.035, 0.035, 0.045, f))
	var tex: Texture2D = _tex_for(index)
	var k: float = _k()
	if tex != null:
		# ВПИСЫВАЕМ ЦЕЛИКОМ, не растягивая: у чужой картинки своё отношение
		# сторон, и растянутое лицо выдаёт подделку сильнее всего.
		var ts := Vector2(tex.get_width(), tex.get_height())
		var scale: float = minf(b.size.x / ts.x, b.size.y / ts.y)
		var вид := Rect2(b.position + (b.size - ts * scale) * 0.5, ts * scale)
		# Уже проявленная часть: сверху вниз.
		var h: float = вид.size.y * k
		# ПРИГЛУШАЕМ. Картинки светлее всего, что есть в игре: две из семи почти
		# белые. На тёмном коридоре такой лист бьёт по глазам, как вспышка.
		# Гасим на четверть — рисунок остаётся читаемым, а глаз не слепнет.
		# РИСУЕМ ЦЕЛИКОМ, А НЕПРОЯВЛЕННОЕ ЗАКРЫВАЕМ. Вырезание куска
		# (draw_texture_rect_region) на этих картинках отдавало ровную заливку —
		# лист выходил пустым и светлым. Полный кадр рисуется верно, а
		# проявление делает полоса, которая едет сверху вниз.
		_sheet_node.draw_texture_rect(tex, вид, false, Color(0.76, 0.76, 0.78, f))
		if k < 1.0:
			_sheet_node.draw_rect(Rect2(вид.position.x, вид.position.y + h,
				вид.size.x, вид.size.y - h), Color(0.035, 0.035, 0.045, f))
		# Полоса, за которой идёт проявление: мокрая бумага светится краской.
		if k < 1.0:
			var y: float = вид.position.y + h
			_sheet_node.draw_rect(Rect2(вид.position.x, y - 2.0, вид.size.x, 3.0),
				Color(PAINT.r, PAINT.g, PAINT.b, 0.55 * f))
			_свет(Vector2(вид.position.x + вид.size.x * 0.5, y),
				вид.size.x * 0.5, Color(PAINT.r, PAINT.g, PAINT.b, f), 0.35)
		# ЗЕРНО И ВИНЬЕТКА. Чужая картинка ложится в игру только если её
		# немного испортить: бумага не бывает идеально ровной, а свет в этой
		# игре всегда падает пятном.
		_rng.seed = 900 + index
		for i in 90:
			var p := вид.position + Vector2(_rng.randf() * вид.size.x,
				_rng.randf() * вид.size.y * k)
			_sheet_node.draw_circle(p, 0.6 + _rng.randf() * 1.6,
				Color(0.0, 0.0, 0.0, 0.05 + _rng.randf() * 0.10))
		# МЕЛКИМ ШАГОМ. Десять полос по краю давали видимые ступени — на светлых
		# листах (белая дверь) они читались полосатой рамкой. Двадцать восемь
		# слабых полос по всем четырём сторонам сходят в тень незаметно.
		for i in 28:
			var u: float = float(i) / 28.0
			var mx: float = вид.size.x * 0.13 * (1.0 - u)
			var my: float = вид.size.y * 0.10 * (1.0 - u)
			var a2: float = 0.022 * f
			_sheet_node.draw_rect(Rect2(вид.position, Vector2(mx, вид.size.y)),
				Color(0, 0, 0, a2))
			_sheet_node.draw_rect(Rect2(вид.position.x + вид.size.x - mx,
				вид.position.y, mx, вид.size.y), Color(0, 0, 0, a2))
			_sheet_node.draw_rect(Rect2(вид.position, Vector2(вид.size.x, my)),
				Color(0, 0, 0, a2))
			_sheet_node.draw_rect(Rect2(вид.position.x,
				вид.position.y + вид.size.y - my, вид.size.x, my),
				Color(0, 0, 0, a2))
	else:
		# Файла нет — лист остаётся пустым, и мы просто не задерживаем игру.
		# Так игра живёт и без картинок: они добавляются по одной.
		_sheet_node.draw_rect(b, Color(0.05, 0.05, 0.06, f))
	# Подтёки поверх: краска свежая и не держится на холсте.
	for d in _drips:
		var a: float = clampf(1.0 - float(d["t"]) / 3.0, 0.0, 1.0) * 0.45 * f
		var от := Vector2(float(d["x"]), float(d["y"]))
		var до := от + Vector2(0.0, float(d["len"])
			* clampf(float(d["t"]) * 0.8, 0.0, 1.0))
		_sheet_node.draw_line(от, до, Color(PAINT.r, PAINT.g, PAINT.b, a), float(d["w"]))
		_sheet_node.draw_circle(до, float(d["w"]) * 0.8, Color(PAINT.r, PAINT.g, PAINT.b, a))


## Свечение мягким пятном — то же, что у лампы на полотне.
func _свет(c: Vector2, r: float, col: Color, сила: float = 0.5) -> void:
	_sheet_node.draw_texture_rect(_glow,
		Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false,
		Color(col.r, col.g, col.b, col.a * сила))


## ПОРЯДОК — ПО СЮЖЕТУ, А НЕ ПО ИМЕНАМ ФАЙЛОВ. Картинки пришли из генератора
## пронумерованными по-своему: взрыв лежит седьмым, хотя по рассказу он первый.
## Здесь они выстроены так, как их задумал автор:
##   1. взрыв
##   2. свет и то, что в нём: синие глаза, кулак в лицо
##   3. женщина падает в огонь
##   4. человек перед светящейся дверью
##   5. он оборачивается, а сбоку стоит тёмная фигура
##   6. они вдвоём перед второй дверью
##   7. мужчина падает в котёл, тянет руку
const ЛИСТЫ := [
	"07-explosion",
	"01-blue-eyed-creature",
	"02-woman-falling-into-fire",
	"03-man-before-yellow-door",
	"04-man-and-shadow-figure",
	"05-two-before-second-door",
	"06-man-falling-into-black-cauldron",
]


func _tex_for(n: int) -> Texture2D:
	if n >= 0 and n < ЛИСТЫ.size():
		var p: String = "res://tex/story_images_v2/%s.png" % ЛИСТЫ[n]
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	# Запасной путь: простые имена лист_1 … лист_7 рядом с остальными текстурами.
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var p2: String = "res://tex/лист_%d.%s" % [n + 1, ext]
		if ResourceLoader.exists(p2):
			return load(p2) as Texture2D
	return null


## Есть ли вообще картинка для этого полотна. Мир спрашивает ДО показа: пустой
## лист на семь секунд — худшее, что можно сделать с игроком.
func есть(n: int) -> bool:
	return _tex_for(clampi(n, 0, 6)) != null
