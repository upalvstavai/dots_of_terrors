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


## Лист. Тот же прямоугольник, на котором игрок только что рисовал.
func _sheet() -> Rect2:
	var w: float = size.x * 0.62
	var h: float = w * 0.66
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


## Содержимое листа. Рисуется в СВОИХ координатах — от (0,0) до size — и всё,
## что выходит за край, обрезается узлом.
func _draw_sheet() -> void:
	var f: float = _fade()
	var b := Rect2(Vector2.ZERO, _sheet_node.size)
	_sheet_node.draw_rect(b, Color(0.035, 0.035, 0.045, f))
	var k: float = _k()
	_rng.seed = 4100 + index
	match index:
		0: _взрыв(b, k, f)
		1: _существо(b, k, f)
		_: _взрыв(b, k, f)
	# Подтёки поверх рисунка: краска свежая и не держится на холсте.
	for d in _drips:
		var a: float = clampf(1.0 - float(d["t"]) / 3.0, 0.0, 1.0) * 0.5 * f
		var от := Vector2(float(d["x"]), float(d["y"]))
		var до := от + Vector2(0.0, float(d["len"])
			* clampf(float(d["t"]) * 0.8, 0.0, 1.0))
		_sheet_node.draw_line(от, до, Color(PAINT.r, PAINT.g, PAINT.b, a), float(d["w"]))
		_sheet_node.draw_circle(до, float(d["w"]) * 0.8, Color(PAINT.r, PAINT.g, PAINT.b, a))


# ─────────────────────────── инструменты рисования ───────────────────────────

## Штрих от руки: прямая, но с дрожью и разной толщиной по длине. Ровная
## линия читается чертежом, а здесь рисовал человек.
func _штрих(a: Vector2, b: Vector2, w: float, col: Color, дрожь: float = 2.0) -> void:
	var n: int = maxi(3, int(a.distance_to(b) / 14.0))
	var pts := PackedVector2Array()
	for i in n + 1:
		var u: float = float(i) / float(n)
		var p: Vector2 = a.lerp(b, u)
		var нрм := (b - a).orthogonal().normalized()
		p += нрм * sin(u * 6.0 + float(_rng.randi() % 7)) * дрожь * sin(u * PI)
		pts.append(p)
	_sheet_node.draw_polyline(pts, col, w)


## Пятно краски: неровный многоугольник вокруг точки. Из них собираются тела,
## огонь и дым — всё, что не линия.
func _пятно(c: Vector2, r: float, col: Color, рв: float = 0.35, углов: int = 13) -> void:
	var pts := PackedVector2Array()
	for i in углов:
		var a: float = TAU * float(i) / float(углов)
		var rr: float = r * (1.0 - рв * 0.5 + _rng.randf() * рв)
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	_sheet_node.draw_colored_polygon(pts, col)


## Свечение мягким пятном. Кольца кругов давали видимые ступени — на кадре это
## читалось мишенью, а не светом.
func _свет(c: Vector2, r: float, col: Color, сила: float = 0.5) -> void:
	_sheet_node.draw_texture_rect(_glow, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
		false, Color(col.r, col.g, col.b, col.a * сила))


# ─────────────────────────── листы ───────────────────────────

## 1/7. ЧИСТЫЙ ВЗРЫВ. Ни земли, ни людей: только свет, который разорвало
## изнутри. Это первое, что было, и объяснять его некому.
func _взрыв(b: Rect2, k: float, f: float) -> void:
	var c := b.position + b.size * Vector2(0.5, 0.52)
	var R: float = b.size.y * 0.42
	# Ядро.
	_свет(c, R * 1.9 * k, Color(PAINT.r, PAINT.g, PAINT.b, f), 0.55)
	_пятно(c, R * 0.30 * k, Color(0.85, 1.0, 0.92, 0.9 * f), 0.30)
	_пятно(c, R * 0.20 * k, Color(1.0, 1.0, 1.0, 0.95 * f), 0.25)
	# Лучи: длинные и короткие вперемешку, все из одной точки.
	var лучей: int = 34
	for i in лучей:
		var a: float = TAU * float(i) / float(лучей) + _rng.randf_range(-0.05, 0.05)
		var дл: float = R * _rng.randf_range(0.5, 1.5) * k
		var w: float = 1.0 + _rng.randf() * 2.6
		var от: Vector2 = c + Vector2(cos(a), sin(a)) * R * 0.18
		var до: Vector2 = c + Vector2(cos(a), sin(a)) * дл
		_штрих(от, до, w, Color(PAINT.r, PAINT.g, PAINT.b, (0.35 + _rng.randf() * 0.5) * f), 3.0)
	# Кольца ударной волны: три, самое дальнее еле видно.
	for i in 3:
		var rr: float = R * (0.55 + float(i) * 0.42) * k
		var кольцо := PackedVector2Array()
		for j in 41:
			var a2: float = TAU * float(j) / 40.0
			кольцо.append(c + Vector2(cos(a2), sin(a2)) * rr
				* (0.94 + _rng.randf() * 0.12))
		_sheet_node.draw_polyline(кольцо, Color(PAINT.r, PAINT.g, PAINT.b,
			(0.30 - float(i) * 0.08) * f), 1.6)
	# Осколки: точки, разлетающиеся наружу. Те самые точки, которые он соединял.
	for i in 40:
		var a3: float = _rng.randf() * TAU
		var d3: float = R * _rng.randf_range(0.7, 1.9) * k
		var p := c + Vector2(cos(a3), sin(a3)) * d3
		if not b.has_point(p):
			continue
		_sheet_node.draw_circle(p, 1.2 + _rng.randf() * 2.2,
			Color(PAINT.r, PAINT.g, PAINT.b, (0.3 + _rng.randf() * 0.5) * f))


## 2/7. СВЕТ И ТО, ЧТО В НЁМ. Бесформенное тело почти во весь лист, синие
## глаза — те же, что смотрят из стен лабиринта, — и кулак, идущий в лицо
## смотрящему. Кулак нарисован КРУПНЕЕ всего остального: так рисуют то, что
## помнят, а не то, что видели.
func _существо(b: Rect2, k: float, f: float) -> void:
	var c := b.size * Vector2(0.5, 0.5)
	# СВЕТ ЗА СПИНОЙ. Без него тело — просто клякса; с ним оно силуэт, а силуэт
	# страшнее любой прорисовки. Жёсткого круга нет: только мягкое пятно.
	_свет(c + Vector2(0.0, -b.size.y * 0.10), b.size.y * 1.25 * k,
		Color(0.88, 1.0, 0.96, f), 0.85)
	_свет(c + Vector2(0.0, -b.size.y * 0.10), b.size.y * 0.55 * k,
		Color(1.0, 1.0, 1.0, f), 0.55)
	# ТЕЛО. Девять пятен друг на друге, каждое со своим смещением и рваным
	# краем: ни одной узнаваемой формы, и ни одного прямого угла. Оно не
	# человек и не зверь — в этом всё дело.
	# СПЛОШНОЙ, А НЕ ПОЛУПРОЗРАЧНЫЙ. При альфе 0.62 края пятен просвечивали
	# друг сквозь друга, и тело читалось стопкой серых листов.
	var тело := Color(0.015, 0.035, 0.030, f)
	var ц := c + Vector2(0.0, b.size.y * 0.12)
	for i in 9:
		var сдв := Vector2(_rng.randf_range(-0.24, 0.24) * b.size.x,
			_rng.randf_range(-0.12, 0.18) * b.size.y)
		_пятно(ц + сдв, b.size.y * _rng.randf_range(0.17, 0.32) * k, тело, 0.5, 21)
	# Штрихи по краю: тело не вырезано ножницами, оно лохматое.
	for i in 22:
		var a: float = _rng.randf() * TAU
		var r0: float = b.size.y * _rng.randf_range(0.26, 0.34)
		var от := ц + Vector2(cos(a), sin(a) * 0.8) * r0
		_штрих(от, от + Vector2(cos(a), sin(a) * 0.8)
			* b.size.y * _rng.randf_range(0.03, 0.12) * k,
			1.4 + _rng.randf() * 2.2, Color(0.02, 0.05, 0.045, 0.75 * f), 2.0)
	# ГЛАЗА. Два, синие, на разной высоте: ровная пара читается маской.
	var гл: float = b.size.y * 0.042 * k
	for сд in [-1.0, 1.0]:
		var e := ц + Vector2(сд * b.size.x * 0.080, -b.size.y * 0.16
			+ сд * b.size.y * 0.014)
		_свет(e, гл * 6.0, Color(EYE.r, EYE.g, EYE.b, f), 0.9)
		_sheet_node.draw_circle(e, гл, Color(EYE.r, EYE.g, EYE.b, 0.95 * f))
		_sheet_node.draw_circle(e, гл * 0.42, Color(0.88, 0.96, 1.0, 0.95 * f))
	# КУЛАК В ЛИЦО. Он ближе всего к смотрящему, поэтому крупнее всего
	# остального и перекрывает тело: так рисуют то, что помнят, а не то, что
	# видели. Собран как кулак: масса, четыре костяшки дугой, пальцы под ними
	# и большой палец сбоку.
	var кул := b.size * Vector2(0.55, 0.76)
	var R: float = b.size.y * 0.26 * k
	var плоть := Color(0.015, 0.035, 0.030, f)
	for i in 4:
		_пятно(кул + Vector2(_rng.randf_range(-0.22, 0.22),
			_rng.randf_range(-0.10, 0.14)) * R, R * _rng.randf_range(0.72, 0.95),
			плоть, 0.22, 19)
	for i in 4:
		var u: float = (float(i) + 0.5) / 4.0
		var кост := кул + Vector2((u - 0.5) * R * 1.5, -R * (0.62 - abs(u - 0.5) * 0.5))
		_пятно(кост, R * 0.27, плоть, 0.22, 15)
		# Пальцы уходят вниз от костяшек: короткие, плотно прижатые.
		_пятно(кост + Vector2(0.0, R * 0.42), R * 0.21, плоть, 0.25, 13)
	# Большой палец сбоку, поперёк остальных.
	_пятно(кул + Vector2(-R * 0.86, R * 0.22), R * 0.30, плоть, 0.30, 15)
	_пятно(кул + Vector2(-R * 0.55, R * 0.42), R * 0.24, плоть, 0.30, 13)
	# КОНТУР И КОСТЯШКИ КРАСКОЙ. Чёрное на чёрном не читается ничем, кроме
	# света: кулак обведён той же краской, которой игрок ведёт линии, и этой
	# же краской намечены костяшки и борозды между пальцами. Без них в кадре
	# просто тёмный ком.
	var обвод := PackedVector2Array()
	for i in 31:
		var a7: float = TAU * float(i) / 30.0
		var rr7: float = R * (1.12 + 0.10 * sin(a7 * 3.0)) * (1.0 if a7 < PI else 0.96)
		обвод.append(кул + Vector2(cos(a7) * rr7, sin(a7) * rr7 * 0.92))
	_sheet_node.draw_polyline(обвод, Color(PAINT.r, PAINT.g, PAINT.b, 0.55 * f), 2.4)
	for i in 4:
		var u2: float = (float(i) + 0.5) / 4.0
		var кост2 := кул + Vector2((u2 - 0.5) * R * 1.5, -R * (0.62 - abs(u2 - 0.5) * 0.5))
		var дуга := PackedVector2Array()
		for j in 11:
			var aa: float = PI * (1.05 + float(j) / 10.0 * 0.9)
			дуга.append(кост2 + Vector2(cos(aa), sin(aa)) * R * 0.30)
		_sheet_node.draw_polyline(дуга, Color(PAINT.r, PAINT.g, PAINT.b, 0.5 * f), 2.0)
		# Борозда между пальцами.
		if i < 3:
			var м := кул + Vector2((u2 - 0.5 + 0.125) * R * 1.5, -R * 0.18)
			_штрих(м, м + Vector2(0.0, R * 0.62), 1.6,
				Color(PAINT.r, PAINT.g, PAINT.b, 0.35 * f), 1.2)
	# Штрихи движения: сходятся к кулаку, показывая, что он идёт НА тебя.
	for i in 12:
		var a6: float = _rng.randf() * TAU
		var от2 := кул + Vector2(cos(a6), sin(a6)) * R * 1.5
		_штрих(от2, кул + Vector2(cos(a6), sin(a6)) * R * 2.4,
			1.0 + _rng.randf() * 1.3, Color(PAINT.r, PAINT.g, PAINT.b, 0.22 * f), 2.5)
