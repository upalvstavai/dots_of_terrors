extends Control

const Shapes := preload("res://Shapes.gd")
const UI := preload("res://UI.gd")
const Lang := preload("res://Lang.gd")
## ТОЧКИ УЖАСА — полотно. Перенос из HTML (startDraw / updDraw / renderDraw / drawClick).
##
## Это ядро игры: детская «соедини точки» под таймером и дрожащей рукой.
## Всё, что тут настроено, добыто замерами в прототипе — менять числа можно,
## но каждое из них за что-то отвечает.

signal solved                      ## полотно сдано
signal failed                      ## время вышло, рисунок осыпался
signal mistake                     ## нажал не ту точку
signal linked(i: int, total: int)  ## соединил очередную точку
signal abandoned                   ## бросил полотно и убежал

const R_HIT := 16.0                ## радиус попадания по точке
## Чёрные щупальца выхлёстывают из-за края картины и накрывают НУЖНУЮ точку.
## Не отнимают время и не считаются ошибкой — просто на доли секунды делают
## её ненажимаемой. Пугает не урон, а то, что рисунок перестаёт слушаться.
const TENT_EVERY := 2              ## через полотно
const TENT_FIRST := [3.0, 7.0]
const TENT_REPEAT := [3.5, 6.5]
const TENT_COVER := [0.25, 0.5]

var shape: Dictionary
var index: int = 0
var mods: Dictionary = {}
var dots: Array = []               ## {pos, idx, col, done, ph}
var next_idx: int = 0
var n: int = 0
var time_left: float = 0.0
var time_max: float = 0.0
var tremor: float = 1.0            ## множитель дрожи, копится за провалы
var dissolve: float = 0.0
var pen_t: float = 0.0             ## «кусок», отгрызенный последней точкой
## ЛИНИЯ РАСТЁТ, А НЕ ПОЯВЛЯЕТСЯ. Раньше отрезок возникал целиком в тот кадр,
## когда попал по точке, — рука игрока и линия не были связаны ничем. Теперь
## последний отрезок дорисовывается за GROW_T, и попадание читается как ДВИЖЕНИЕ
## карандаша, а не как включившаяся лампочка.
const GROW_T := 0.13
var grow: float = 1.0              ## насколько дорисован последний отрезок, 0..1
var pop_t: float = 0.0             ## вспышка только что соединённой точки
## КРАСКА, А НЕ ЛИНИЯ. Соединение точек было полилинией в два пикселя — то
## есть чертёж. Теперь это мазок: под ним тёмный след от нажима, поверх —
## тело краски, а по центру светящееся ядро; толщина гуляет по длине, потому
## что рука не линейка. Всё это рисуется на холсте В МИРЕ, и разница видна.
const PAINT := Color(0.22, 1.0, 0.62)
var drips: Array = []              ## потёки: {pos, len, t, life, col, w}
var burn: float = 0.0              ## вспышка по всей линии, когда полотно сдано
## СДАНО, НО ЕЩЁ НА ЭКРАНЕ. Раньше последняя точка гасила узел в тот же кадр.
## Теперь он живёт лишние доли секунды ради вспышки — и на это время обязан
## перестать быть полотном: ни хода таймера, ни осыпания, ни нажатий. Без
## этого сданное полотно успевало «провалиться по времени» перед закрытием.
var finished: bool = false
## ЕГО ШАГ ДЁРГАЕТ РУКУ. Пока рисуешь, тварь ходит вокруг, и слышно, с какой
## стороны. Но слух, который ни на что не влияет, — это украшение. Близкий шаг
## теперь коротко встряхивает всё полотно: звук перестаёт быть только звуком и
## начинает портить линию.
var jolt: float = 0.0
var t_global: float = 0.0
var madness_stage: int = 0
var final: bool = false      ## финальная дверь: и таймер, и монстр разом
var near: float = 0.0        ## насколько близко он подошёл, 0..1
var _rng := RandomNumberGenerator.new()
var _lamp_tex: GradientTexture2D
var tent_on: bool = false
var tutor: bool = false      ## обучающее полотно в прологе: без таймера и шума
## УЧЕБНЫЕ ПОЛОТНА. Друг (18.09): «в заданиях совсем нет объяснений — я вообще
## не понимаю, как их решать». Номерки мы убрали ради трудности, а правила
## лежали в настройках, куда новичок не заходит. На первых TEACH_N полотнах
## у точек снова номера и на листе одна строка — как рисовать. Дальше — без
## подсказок, как было: к третьему полотну правило уже в руках.
const TEACH_N := 2
var teach: bool = false
## СНИМОК ДЛЯ МОЛЬБЕРТА: только лист, без интерфейса. Холст, стоящий в
## коридоре, не должен показывать таймер, ленту порядка и подсказку — это
## вещи открытого полотна, а не рисунка на нём.
var preview: bool = false
## Полоска «ОНО ИДЁТ» теперь не только у двери: её включают, когда он
## действительно вышел за тобой.
var show_near: bool = false
var paper: Texture2D = load("res://tex/paper_color.jpg")
var wood: Texture2D = load("res://tex/wood_color.jpg")
var tent_t: float = 0.0
var tent_life: float = 0.0
## ЩУПАЛЬЦА ЗАКРЫВАЮТ НЕСКОЛЬКО ТОЧЕК, А НЕ ОДНУ.
##
## Было одно, и оно садилось ровно на ту точку, которую надо нажать следующей.
## Задумано это было наказанием — «труднее там, где промахнулся», — а на деле
## работало ПОДСКАЗКОЙ: человек, потерявший очередь, ждал пару секунд и видел
## ответ. Первый же игрок со стороны это и сказал: «штука, которая закрывает
## точки, вместо помехи подсказывает».
##
## Лечится не убиранием, а числом: закрываем нужную точку И ещё две случайные
## из нетронутых. Правильная по-прежнему закрыта — наказание осталось, — но
## какая из трёх правильная, по щупальцам не понять.
var tents: Array = []            ## [{idx, seed}] — что сейчас закрыто


## С рождения узел НЕ СЧИТАЕТ. Godot включает _process всем, у кого есть такой
## метод, — и полотно тикало с первого кадра игры, задолго до того, как его
## открывали. У полотна из-за этого таймер уходил в ноль сам собой: полотно объявляло
## себя проваленным на второй секунде, закрывалось и ЗАБИРАЛО КУРСОР — на
## стартовом экране пропадала стрелка, и нажать «проснуться» было нечем.
func _ready() -> void:
	set_process(false)


func open(shape_data: Dictionary, canvas_index: int, fear: float, stage: int, seed_value: int) -> void:
	_rng.seed = seed_value
	shape = shape_data
	index = canvas_index
	teach = canvas_index < TEACH_N and not final and not tutor
	madness_stage = stage
	tremor = clampf(fear, 1.0, Shapes.FEAR_MAX)
	mods = {}
	if not final:
		for m in Shapes.MODS[canvas_index]:
			mods[m] = true
	n = shape["pts"].size()
	time_max = Shapes.door_time() if final else Shapes.time_for(canvas_index, shape)
	time_left = time_max
	next_idx = 0
	dissolve = 0.0
	pen_t = 0.0
	finished = false
	burn = 0.0
	drips.clear()
	if _lamp_tex == null:
		_make_lamp()
	# На обучающем полотне щупалец НЕТ. Первое знакомство с правилом не должно
	# происходить под рукой, которая закрывает нужную точку.
	tent_on = not final and canvas_index > 0 and (canvas_index % TENT_EVERY == 0)
	tent_t = _rng.randf_range(TENT_FIRST[0], TENT_FIRST[1])
	tents.clear()
	tent_life = 0.0
	_build_dots()
	visible = true
	set_process(true)


## Пятно света для правила «полотно в темноте». Строим один раз: градиент
## от прозрачного в центре к глухой темноте по краю.
func _make_lamp() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([
		Color(0.012, 0.012, 0.024, 0.0),
		Color(0.012, 0.012, 0.024, 0.0),
		Color(0.012, 0.012, 0.024, 0.97)])
	_lamp_tex = GradientTexture2D.new()
	_lamp_tex.gradient = g
	_lamp_tex.fill = GradientTexture2D.FILL_RADIAL
	_lamp_tex.fill_from = Vector2(0.5, 0.5)
	_lamp_tex.fill_to = Vector2(1.0, 0.5)
	_lamp_tex.width = 256
	_lamp_tex.height = 256


func _build_dots() -> void:
	dots.clear()
	for i in n:
		var p: Vector2 = shape["pts"][i]
		dots.append({"nx": p.x, "ny": p.y, "idx": i, "col": _rng.randi() % 3,
			"done": false, "ph": _rng.randf() * TAU})
	# Шум: чем дальше полотно, тем больше лишних точек. 6/8/10/12/14/16 —
	# при шаге 3 на шестом полотне доска забивалась до нечитаемости.
	# В прологе лишних точек нет: первое знакомство с правилом должно показать
	# само правило, а не умение отличать нужную точку от постороннего мусора.
	var noise_n := 0 if tutor else (12 if final else 6 + index * 2)
	for _k in noise_n:
		var ok := false
		var nx := 0.0
		var ny := 0.0
		var tries := 0
		while not ok and tries < 80:
			tries += 1
			nx = 0.08 + _rng.randf() * 0.84
			ny = 0.08 + _rng.randf() * 0.84
			ok = true
			for d in dots:
				if Vector2(d["nx"] - nx, d["ny"] - ny).length_squared() <= 0.006:
					ok = false
					break
		if ok:
			dots.append({"nx": nx, "ny": ny, "idx": -1, "col": _rng.randi() % 3,
				"done": false, "ph": _rng.randf() * TAU})


func _process(delta: float) -> void:
	t_global += delta
	if pen_t > 0.0:
		pen_t -= delta
	if grow < 1.0:
		grow = minf(1.0, grow + delta / GROW_T)
	if pop_t > 0.0:
		pop_t = maxf(0.0, pop_t - delta)
	if burn > 0.0:
		burn = maxf(0.0, burn - delta)
	if jolt > 0.0:
		jolt = maxf(0.0, jolt - delta * 3.4)
	# Потёки текут вниз и подсыхают. Считаем их всегда: они должны доползать
	# и после того, как полотно осыпается.
	var alive: Array = []
	for dr in drips:
		dr["t"] += delta
		dr["len"] += delta * dr["v"]
		if dr["t"] < dr["life"]:
			alive.append(dr)
	drips = alive
	if dissolve > 0.0:
		dissolve -= delta
		if dissolve <= 0.0:
			# ОСТАНОВИТЬСЯ ПОЛНОСТЬЮ. Раньше здесь только слался сигнал, а сам
			# узел продолжал считать: time_left уходил в минус и КАЖДЫЙ КАДР
			# заново взводил осыпание. Полотно кричало «провалено» раз в секунду
			# бесконечно — отсюда и вечно растущая ярость, и курсор, который
			# возвращался в игру через секунду после Esc.
			dissolve = 0.0
			_end_fail()
		queue_redraw()
		return
	if finished:
		# ПЕРЕРИСОВЫВАТЬ — ОБЯЗАТЕЛЬНО. Здесь стоял простой return, а
		# queue_redraw() живёт в конце этой функции: сданное полотно замирало
		# на последнем кадре, и вспышка, ради которой всё и задержано,
		# не рисовалась ни разу. Кадр стенда показал рисунок без прожига при
		# burn = 0.29 — то есть вспышка была, а перерисовки не было.
		queue_redraw()
		return                      # догорает вспышка, полотно уже сдано
	# На двери время идёт быстрее реального — это единственное место, где так.
	if not tutor:
		time_left -= delta * (Shapes.DOOR_RATE if final else 1.0)
	_update_tent(delta)
	if time_left <= 0.0:
		dissolve = Shapes.DISSOLVE_T
	queue_redraw()


## Точка под щупальцем не нажимается, но это и НЕ ошибка: наказывать за то,
## что рисунок сам спрятал нужную точку, было бы нечестно.
func blocked(idx: int) -> bool:
	if tent_life <= 0.0:
		return false
	for tt in tents:
		if int(tt["idx"]) == idx:
			return true
	return false


## Щупальце ВНЕ очереди — наказание за ошибку. Раньше промах стоил единицы в
## счётчике безумия: это сообщение об ошибке, а не последствие. Теперь из
## полотна лезет рука и закрывает ту самую точку, которую надо нажать, — задача
## становится труднее ровно там, где ты промахнулся.
func punish() -> void:
	if next_idx >= n:
		return
	_grow_tents(3)
	tent_life = 1.5 + _rng.randf() * 1.1


## Выбрать, что закрыть: обязательно следующую точку и ещё несколько из тех,
## до которых игрок ещё не дошёл. Уже соединённые не берём — закрывать
## пройденное бессмысленно, и по одному этому признаку ответ бы вычислялся.
func _grow_tents(want: int) -> void:
	tents.clear()
	if next_idx >= n:
		return
	tents.append({"idx": next_idx, "seed": _rng.randf() * 99.0})
	var free: Array = []
	for d in dots:
		var i: int = int(d["idx"])
		if i > next_idx:
			free.append(i)
	free.shuffle()
	for i2 in free:
		if tents.size() >= want:
			break
		tents.append({"idx": i2, "seed": _rng.randf() * 99.0})


func _update_tent(delta: float) -> void:
	# Дожитие щупальца считается ВСЕГДА, даже там, где по расписанию их нет:
	# иначе наказание за промах не гаснет на половине полотен.
	if tent_life > 0.0:
		tent_life -= delta
		if tent_life <= 0.0:
			tents.clear()
			tent_t = _rng.randf_range(TENT_REPEAT[0], TENT_REPEAT[1])
		return
	if not tent_on:
		return
	tent_t -= delta
	if tent_t <= 0.0 and next_idx < n:
		_grow_tents(3)
		tent_life = _rng.randf_range(TENT_COVER[0], TENT_COVER[1])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)


func _click(mouse_pos: Vector2) -> void:
	if dissolve > 0.0 or finished:
		return
	# Берём БЛИЖАЙШУЮ точку в радиусе, а не первую по списку: на полотнах с дрейфом
	# соседи сходятся до 21 px при радиусе 16, зоны захвата перекрываются, и порядок
	# в массиве не должен решать, что засчитать.
	var hit = null
	var best := R_HIT * R_HIT
	for d in dots:
		if d["done"]:
			continue
		var q: float = mouse_pos.distance_squared_to(_dot_pos(d))
		if q < best:
			best = q
			hit = d
	if hit == null:
		return
	if blocked(hit["idx"]):
		return                      # щупальце держит точку — не нажать, но и не ошибка
	if hit["idx"] == next_idx:
		hit["done"] = true
		next_idx += 1
		time_left -= Shapes.DOT_TIME_COST      # линия тянется — время утекает
		pen_t = 0.7
		grow = 0.0
		pop_t = 0.22
		_drip_at(_dot_pos(hit), PAINT, 1, 0.75)
		linked.emit(next_idx, n)
		if next_idx >= n:
			# ПРОЖЁГ. Раньше последняя точка просто гасила полотно в тот же
			# кадр — вся работа кончалась ничем. Теперь линия вспыхивает
			# насквозь; гасит её мир, когда вспышка отыграет.
			burn = 0.45
			finished = true
			solved.emit()
	else:
		# ПРОМАХ ВИДЕН НА ХОЛСТЕ. Был только звук и счётчик безумия — то есть
		# ошибка нигде не оставалась. Теперь с неверной точки течёт краска:
		# полотно портится на глазах, и это его цвет, а не зелёный.
		_drip_at(_dot_pos(hit), Shapes.PALETTE[hit["col"]], 3, 1.5)
		mistake.emit()


# ─────────────────────────── геометрия ───────────────────────────

## ХОЛСТ ЗАНИМАЕТ ПОЧТИ ВЕСЬ КАДР.
##
## Раньше это окно рисовалось поверх экрана, и вокруг него оставался мир —
## отсюда и поля. Теперь кадр НАТЯНУТ НА ХОЛСТ в мире: всё, что не рисунок, —
## это светлая кайма вокруг настоящего полотна, то есть брак. Оставляем поля
## только сверху и снизу, где лежат лента порядка и предупреждение.
func board_rect() -> Rect2:
	var w: float = size.x * 0.94
	var h: float = size.y * 0.74
	return Rect2((size.x - w) * 0.5, size.y * 0.055, w, h)


## Холст в раме. Экран, за которым игрок проводит половину игры, был тёмным
## прямоугольником с обводкой в один пиксель — то есть окном интерфейса, а не
## вещью, которую сняли со стены и поставили перед тобой.
##
## Точки читаются по-прежнему: холст ТЁМНЫЙ. Светлая бумага под цветными
## точками убила бы всю различимость, ради которой мы правили яркость и номера.
func _draw_canvas(b: Rect2) -> void:
	var pad := 14.0
	var f := Rect2(b.position - Vector2(pad, pad), b.size + Vector2(pad * 2.0, pad * 2.0))
	if wood != null:
		draw_texture_rect(wood, f, true, Color(0.30, 0.24, 0.20))
	else:
		draw_rect(f, Color(0.22, 0.18, 0.15))
	# Тень внутрь от рамы: холст утоплен, а не наклеен поверх.
	draw_rect(Rect2(b.position - Vector2(3, 3), b.size + Vector2(6, 6)),
		Color(0.05, 0.04, 0.03, 0.8))
	if paper != null:
		# Тёмный множитель: та же фактура, но холст остаётся почти чёрным.
		draw_texture_rect(paper, b, false, Color(0.115, 0.115, 0.128))
	else:
		draw_rect(b, Color(0.10, 0.10, 0.115))
	# Фаска рамы: светлая сверху-слева, тёмная снизу-справа. Без неё дерево
	# читается плоской заливкой.
	draw_line(f.position, f.position + Vector2(f.size.x, 0), Color(0.52, 0.44, 0.36, 0.5), 2.0)
	draw_line(f.position, f.position + Vector2(0, f.size.y), Color(0.52, 0.44, 0.36, 0.5), 2.0)
	draw_line(f.position + Vector2(0, f.size.y), f.position + f.size, Color(0.10, 0.08, 0.06, 0.7), 2.0)
	draw_line(f.position + Vector2(f.size.x, 0), f.position + f.size, Color(0.10, 0.08, 0.06, 0.7), 2.0)


## Дрейф считается ОДНОЙ функцией и для отрисовки, и для попадания. Иначе игрок
## целится в одно, а нажимает другое.
func _dot_pos(d: Dictionary) -> Vector2:
	var b := board_rect()
	var p: Vector2 = Vector2(b.position.x + d["nx"] * b.size.x, b.position.y + d["ny"] * b.size.y)
	if mods.has("drift"):
		var t: float = t_global * 0.9 + d["ph"]
		p += Vector2(cos(t) * 8.0, sin(t * 1.3) * 6.0)
	return p


## ЯРКОСТЬ БОЛЬШЕ НЕ РАССКАЗЫВАЕТ ПОРЯДОК.
##
## Тут была лестница: чем дальше точка по очереди, тем она тусклее, — и вместе
## с номерками и дышащим ободком это означало, что полотно само показывает, куда
## вести линию. Играющий сказал прямо: «стали проще, мигания подсказывают куда
## тащить». Всё три подсказки убраны; порядок читается ТОЛЬКО по цветной ленте
## внизу, а какую из точек нужного цвета брать — догадка и форма рисунка.
##
## Что яркость по-прежнему говорит — это где рисунок, а где мусор. Это не про
## очередь: без этого различия полотно превращается в лотерею.
func _dot_alpha(d: Dictionary) -> float:
	if d["done"]:
		return 1.0
	return 0.95 if d["idx"] >= 0 else 0.5


## Замедление к концу: линия выходит из точки быстро и мягко причаливает.
## Ровный ход читался механически — как ползунок загрузки, а не как рука.
func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 2.4)


func _jit(a: float) -> float:
	return (_rng.randf() - 0.5) * a


## МАЗОК ПО ТОЧКАМ. Четыре прохода на отрезок, от широкого тёмного следа до
## светящегося ядра, и толщина гуляет по длине пути — одна полилиния ровной
## ширины читалась чертежом, а здесь краска.
##
## Считаем по отрезкам, а не через draw_polyline: у полилинии одна ширина на
## всю длину, а нам нужна разная.
func _draw_paint(pts: PackedVector2Array, fade: float) -> void:
	if pts.size() < 2:
		return
	# Вспышка сдачи прожигает линию насквозь: к белому и в два раза шире.
	var bk: float = clampf(burn / 0.45, 0.0, 1.0)
	var run: float = 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b2: Vector2 = pts[i]
		var l: float = a.distance_to(b2)
		# Толщина считается от пройденной длины, а не от номера отрезка: иначе
		# на коротких отрезках она скакала, а на длинных стояла.
		var w0: float = 1.0 + 0.28 * sin(run * 0.055 + float(i) * 1.7)
		run += l
		var w1: float = 1.0 + 0.28 * sin(run * 0.055 + float(i) * 1.7)
		var w: float = (w0 + w1) * 0.5
		# Тёмный след под краской: вдавленный в холст желобок.
		draw_line(a, b2, Color(0.02, 0.10, 0.06, 0.75 * fade),
			(5.4 + bk * 4.0) * w, true)
		# Тело краски.
		draw_line(a, b2, Color(PAINT.r * 0.55, PAINT.g * 0.55, PAINT.b * 0.55,
			0.55 * fade), (3.6 + bk * 3.0) * w, true)
		draw_line(a, b2, Color(PAINT.r, PAINT.g, PAINT.b, 0.9 * fade),
			(2.2 + bk * 2.4) * w, true)
		# Ядро: почти белое, тонкое. Это оно и даёт «светится», а не заливка.
		draw_line(a, b2, Color(lerpf(0.62, 1.0, bk), 1.0, lerpf(0.86, 1.0, bk),
			(0.6 + 0.4 * bk) * fade), (0.9 + bk * 1.6) * w, true)
		# СТЫК. draw_line рисует отрезок с плоскими торцами, и на каждом
		# повороте между двумя мазками оставался угловой вырез — линия
		# распадалась на палочки. Круг в вершине сшивает их.
		if i < pts.size() - 1:
			draw_circle(b2, (2.7 + bk * 2.0) * w,
				Color(0.02, 0.10, 0.06, 0.75 * fade))
			draw_circle(b2, (1.1 + bk * 1.2) * w,
				Color(PAINT.r, PAINT.g, PAINT.b, 0.9 * fade))


## Капля краски вниз от точки. count — сколько, fat — насколько жирные.
func _drip_at(p: Vector2, col: Color, count: int, fat: float) -> void:
	for i in count:
		# ЖИРНЕЕ И ДОЛЬШЕ, ЧЕМ БЫЛО. С первыми числами (десять пикселей в
		# секунду при толщине в один) капля к моменту, когда на неё смотрят,
		# успевала отрасти на пять пикселей — на кадре её просто не было.
		# Кадр стенда показал шесть потёков, которых не видно ни одного.
		drips.append({
			"pos": p + Vector2(_jit(7.0), 2.0),
			"len": 0.0,
			"v": (26.0 + _rng.randf() * 30.0) * fat,
			"t": 0.0,
			"life": 2.2 + _rng.randf() * 2.2,
			"col": col,
			"w": (1.8 + _rng.randf() * 1.4) * fat,
		})


# ─────────────────────────── отрисовка ───────────────────────────

func _draw() -> void:
	# Кадр целиком заливаем чернотой: он натянут на холст, и всё, что светлее
	# рисунка, читается каймой вокруг полотна.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.025))
	var b := board_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.012, 0.024, 0.9))
	_draw_canvas(b)

	# Дрожь: чем меньше времени и чем хуже лабиринт, тем сильнее
	# В финале дрожь считается от БЛИЗОСТИ монстра, а не от таймера.
	var fear: float
	if final:
		# Берём худшее из двух: подошёл он близко или кончается время — трясёт
		# одинаково. Раньше время на дрожь не влияло, потому что не шло.
		fear = maxf(clampf(near * 0.9 + madness_stage * 0.1, 0.0, 1.0),
			clampf((1.0 - time_left / time_max) * 0.8, 0.0, 1.0)) * tremor
	else:
		fear = clampf((1.0 - time_left / time_max) * 0.8 + madness_stage * 0.15, 0.0, 1.0) * tremor
	var amp := fear * 5.0 + jolt * 7.0
	var dis: float = clampf(1.0 - dissolve / Shapes.DISSOLVE_T, 0.0, 1.0) if dissolve > 0.0 else 0.0
	var fade := 1.0 - dis

	# соединённая линия
	var done_dots := []
	for d in dots:
		if d["idx"] >= 0 and d["done"]:
			done_dots.append(d)
	done_dots.sort_custom(func(a, c): return a["idx"] < c["idx"])
	if done_dots.size() > 1:
		var pts := PackedVector2Array()
		for d in done_dots:
			pts.append(_dot_pos(d) + Vector2(_jit(amp * 0.4), _jit(amp * 0.4)))
		# ПОСЛЕДНИЙ ОТРЕЗОК ДОРИСОВЫВАЕТСЯ. Все, кроме него, — целиком; он сам
		# тянется от предыдущей точки к новой за GROW_T. Из-за этого попадание
		# выглядит движением карандаша, а не мгновенным появлением отрезка.
		if grow < 1.0:
			var last: Vector2 = pts[pts.size() - 1]
			var prev: Vector2 = pts[pts.size() - 2]
			pts[pts.size() - 1] = prev.lerp(last, _ease_out(grow))
		_draw_paint(pts, fade)
		# И КОНЧИК СВЕТИТСЯ, пока идёт. Точка на острие даёт понять, где сейчас
		# «карандаш», — без неё рост линии заметен только боковым зрением.
		if grow < 1.0:
			var tip: Vector2 = pts[pts.size() - 1]
			var kk: float = 1.0 - grow
			draw_circle(tip, 7.0 + kk * 3.0, Color(PAINT.r, PAINT.g, PAINT.b, 0.16 * kk * fade))
			draw_circle(tip, 3.4, Color(0.72, 1.0, 0.88, (0.35 + 0.6 * kk) * fade))

	# ПОТЁКИ. Свежая краска не держится на вертикальном холсте: от каждой взятой
	# точки вниз ползёт капля, а от промаха — сразу три и жирнее. Это и делает
	# рисунок мокрым, и отмечает ошибку на самом полотне, а не только в счётчике.
	for dr in drips:
		var k3: float = 1.0 - dr["t"] / dr["life"]
		var col3: Color = dr["col"]
		var a3: float = clampf(k3, 0.0, 1.0) * 0.8 * fade
		var от: Vector2 = dr["pos"]
		var до: Vector2 = от + Vector2(0.0, dr["len"])
		draw_line(от, до, Color(col3.r, col3.g, col3.b, a3 * 0.45), dr["w"] + 1.6)
		draw_line(от, до, Color(col3.r, col3.g, col3.b, a3), dr["w"])
		# Набухшая головка капли — то, что и делает её каплей, а не чертой.
		draw_circle(до, dr["w"] * 0.85 + 0.6,
			Color(col3.r, col3.g, col3.b, a3))

	# точки
	# ПОРЯДОК РИСОВАНИЯ. Фигуры замкнутые: первая и последняя точки лежат в
	# одном месте, и последняя, нарисованная позже, закрывала первую. Лента
	# говорила «начни с зелёной», а зелёной на полотне не было — её прятала
	# розовая шестёрка. Теперь сверху всегда точка с МЕНЬШИМ номером из ещё не
	# взятых: мусор первым, потом фигура от последней к первой.
	var order: Array = dots.duplicate()
	order.sort_custom(func(a, c):
		var ka: int = -1000 if int(a["idx"]) < 0 else (-int(a["idx"]) - (500 if a["done"] else 0))
		var kc: int = -1000 if int(c["idx"]) < 0 else (-int(c["idx"]) - (500 if c["done"] else 0))
		return ka < kc)
	for d in order:
		var p := _dot_pos(d) + Vector2(_jit(amp * 0.4), _jit(amp * 0.4))
		var done: bool = d["done"]
		var col: Color = PAINT if done else Shapes.PALETTE[d["col"]]
		var a: float = _dot_alpha(d) * fade
		# ТОЧКА — ЭТО СЛЕД НАЖИМА. Сначала тёмная лунка (краска вдавлена в
		# холст), потом свечение вокруг, потом само пятно, и по центру блик.
		# Плоский круг читался как пиксель интерфейса; это — капля краски.
		var big: bool = done or int(d["idx"]) >= 0
		draw_circle(p, 6.4 if big else 4.8, Color(0.0, 0.0, 0.0, 0.55 * fade))
		draw_circle(p, 9.5 if big else 6.8, Color(col.r, col.g, col.b, 0.13 * a))
		# РАЗМЕР ГОВОРИТ, ЧТО ВХОДИТ В РИСУНОК, — И ТОЛЬКО ЭТО. Про очередь он
		# не говорит ничего: номерки, ободок и лестница яркости убраны, а вот
		# «эта точка вообще часть фигуры или мусор» знать надо, иначе первый же
		# ход становится лотереей между шестью посторонними точками.
		var r: float = 5.2 if done else (4.3 if int(d["idx"]) >= 0 else 3.1)
		draw_circle(p, r, Color(col.r, col.g, col.b, a))
		draw_circle(p - Vector2(1.1, 1.3), 1.7,
			Color(minf(1.0, col.r + 0.5), minf(1.0, col.g + 0.35),
			minf(1.0, col.b + 0.45), 0.8 * a))
		# НОМЕР У ТОЧКИ — только на учебных полотнах.
		if teach and not done and int(d["idx"]) >= 0 and not _twin_below(d):
			var nf := UI.text(700)
			var np: Vector2 = p + Vector2(8.0, -8.0)
			var ns: String = _twin_label(d)
			draw_string_outline(nf, np, ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4,
				Color(0, 0, 0, 0.9 * fade))
			draw_string(nf, np, ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(0.92, 0.95, 0.90, (1.0 if int(d["idx"]) == next_idx else 0.7) * fade))
		# ВСПЫШКА НА ТОЛЬКО ЧТО ВЗЯТОЙ. Короткое кольцо, которое расходится и
		# гаснет: подтверждение попадания, которого раньше не было ничем, кроме
		# самой линии. Стоит один draw_arc и живёт 0.22 с.
		if pop_t > 0.0 and done and d["idx"] == next_idx - 1:
			var k2: float = pop_t / 0.22
			draw_arc(p, 6.0 + (1.0 - k2) * 11.0, 0.0, TAU, 20,
				Color(0.55, 1.0, 0.80, k2 * 0.75 * fade), 2.0)

	# Полотно в темноте: видно только пятно вокруг курсора. Рисуем ПОСЛЕ точек,
	# но ДО ленты и таймера — иначе игроку нечем целиться и не видно, сколько осталось.
	if not tents.is_empty() and tent_life > 0.0 and dissolve <= 0.0:
		for tt in tents:
			for d in dots:
				if int(d["idx"]) != int(tt["idx"]):
					continue
				var tp := _dot_pos(d)
				for k in 4:
					var a0: float = float(tt["seed"]) + float(k) * 1.6 + t_global * 2.0
					var arm := PackedVector2Array()
					for i in 7:
						var s2: float = float(i) / 6.0
						arm.append(tp + Vector2(cos(a0 + s2 * 2.2), sin(a0 + s2 * 2.2)) * (44.0 * (1.0 - s2)))
					draw_polyline(arm, Color(0.02, 0.02, 0.03, 0.95), 5.0)
				draw_circle(tp, 13.0, Color(0.02, 0.02, 0.03, 0.95))
				break
	if mods.has("lamp") and dissolve <= 0.0:
		var m := get_local_mouse_position()
		var R := 118.0
		draw_texture_rect(_lamp_tex, Rect2(m - Vector2(R, R), Vector2(R * 2, R * 2)), false)
		var dark := Color(0.012, 0.012, 0.024, 0.97)
		draw_rect(Rect2(0, 0, size.x, maxf(0.0, m.y - R)), dark)
		draw_rect(Rect2(0, minf(size.y, m.y + R), size.x, maxf(0.0, size.y - m.y - R)), dark)
		draw_rect(Rect2(0, maxf(0.0, m.y - R), maxf(0.0, m.x - R), minf(size.y, R * 2)), dark)
		draw_rect(Rect2(minf(size.x, m.x + R), maxf(0.0, m.y - R), maxf(0.0, size.x - m.x - R), minf(size.y, R * 2)), dark)
	if dissolve <= 0.0 and not preview:
		_draw_hud(b)
		if teach:
			var tf := UI.text(600)
			var tp2 := Vector2(b.position.x, b.position.y + 30.0)
			draw_string_outline(tf, tp2, Lang.t("teach_line"), HORIZONTAL_ALIGNMENT_CENTER,
				b.size.x, 17, 5, Color(0, 0, 0, 0.9))
			draw_string(tf, tp2, Lang.t("teach_line"), HORIZONTAL_ALIGNMENT_CENTER,
				b.size.x, 17, Color(0.92, 0.90, 0.80))
	# ПРОЖИГ НА СДАЧЕ. Толщины линий на это одной мало: на кадре сданное
	# полотно отличалось от несданного разве что оттенком. Полотно — то
	# единственное, что игрок здесь делает; закончить его должно быть ВИДНО.
	# Вспышка по всему листу и белый ореол вокруг рисунка.
	if burn > 0.0:
		var bk: float = clampf(burn / 0.45, 0.0, 1.0)
		var kk: float = bk * bk
		draw_rect(Rect2(Vector2.ZERO, size),
			Color(0.62, 1.0, 0.86, 0.42 * kk))


func _draw_hud(b: Rect2) -> void:
	var f := UI.text(500)
	# лента порядка цветов
	var sw := 22.0
	var total := n * (sw + 8.0)
	var x0 := (size.x - total) * 0.5
	var y0 := b.position.y + b.size.y + 26.0
	# Лента порядка лежит на бумажной полоске, а не висит в пустоте: это часть
	# того же предмета, что и холст, а не строка интерфейса под ним.
	var strip := Rect2(x0 - 96.0, y0 - 9.0, total + 108.0, sw + 18.0)
	if paper != null:
		draw_texture_rect(paper, strip, false, Color(0.20, 0.19, 0.18))
	else:
		draw_rect(strip, Color(0.16, 0.15, 0.14))
	draw_rect(strip, Color(0.34, 0.28, 0.23, 0.7), false, 1.5)
	draw_string(f, Vector2(x0 - 84, y0 + 14), Lang.t("order"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.62, 0.76, 0.68, 0.9))
	for i in n:
		for d in dots:
			if d["idx"] == i:
				var col: Color = Shapes.PALETTE[d["col"]]
				col.a = 0.25 if i < next_idx else 1.0
				# СЛЕПАЯ ЛЕНТА. Раз номерков больше нет, лента — единственное,
				# что вообще известно про порядок. Значит её и надо забирать:
				# на поздних полотнах видно только СЛЕДУЮЩИЙ цвет, а что будет
				# дальше — нет. Считать наперёд нельзя, можно только идти.
				if mods.has("blind") and i > next_idx:
					draw_rect(Rect2(x0 + i * (sw + 8.0), y0, sw, sw),
						Color(0.13, 0.12, 0.14))
					draw_rect(Rect2(x0 + i * (sw + 8.0), y0, sw, sw),
						Color(0.30, 0.27, 0.24, 0.6), false, 1.0)
					break
				draw_rect(Rect2(x0 + i * (sw + 8.0), y0, sw, sw), col)
				if i == next_idx:
					draw_rect(Rect2(x0 + i * (sw + 8.0) - 2, y0 - 2, sw + 4, sw + 4),
						Color.WHITE, false, 1.5)
				break
	# Полоска. На обычном полотне — секунды. В финале секунд нет: она НАПОЛНЯЕТСЯ
	# по мере того, как он подходит. Тот же таймер, но у него есть шаги и голос.
	if not tutor:
		draw_rect(Rect2(b.position.x, b.position.y - 34, b.size.x, 6),
			Color(0.08, 0.08, 0.11))
		var frac: float = clampf(time_left / time_max, 0.0, 1.0)
		draw_rect(Rect2(b.position.x, b.position.y - 34, b.size.x * frac, 6),
			Color(0.22, 1.0, 0.62) if frac > 0.35 else Color(0.88, 0.31, 0.24))
	if final or show_near:
		# Две полосы, одна над другой. Умереть от таймера, которого не видно,
		# нечестно — а раньше в финале показывали только подход монстра.
		draw_rect(Rect2(b.position.x, b.position.y - 48, b.size.x, 6), Color(0.08, 0.08, 0.11))
		draw_rect(Rect2(b.position.x, b.position.y - 48, b.size.x * clampf(near, 0.0, 1.0), 6),
			Color(0.88, 0.31, 0.24))
		draw_string(f, Vector2(b.position.x, b.position.y - 34), Lang.t("it_comes"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.88, 0.31, 0.24))
	if tremor > 1.0:
		draw_string(f, Vector2(b.position.x, b.position.y - 42), Lang.t("fear") % tremor,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.88, 0.31, 0.24))
	# БРОСИТЬ МОЖНО — И ОБ ЭТОМ НАДО СКАЗАТЬ. Клавиша была с самого начала, а
	# подсказки не было ни одной: первый же человек со стороны решил, что из
	# полотна не выйти, и что монстр бьёт по беззащитному. Механика оказалась
	# исправной, а игра — молчаливой, и это одно и то же для того, кто играет.
	#
	# Внизу, под холстом, и КРАСНЫМ, когда он подходит: в этот момент подсказка
	# из справки становится решением.
	var drop_col: Color = Color(0.88, 0.31, 0.24) if (show_near and near > 0.35) \
		else Color(0.62, 0.60, 0.55, 0.75)
	draw_string(f, Vector2(b.position.x, b.position.y + b.size.y + 22),
		Lang.t("b_drop"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, drop_col)
	if not mods.is_empty():
		var names := []
		for m in mods:
			names.append(Lang.t("mod_" + str(m)))
		draw_string(f, Vector2(b.position.x, b.position.y - 40), " . ".join(names),
			HORIZONTAL_ALIGNMENT_RIGHT, b.size.x, 12, Color(0.72, 0.64, 0.29))


## Он дошёл — полотно сорвано.
## Бросить полотно и бежать. Без этого приход монстра к холсту — гарантированный
## проигрыш, а значит нечестность. С этим каждое полотно превращается в решение:
## ещё три точки или уже поздно? Вот это и страшно, а не таймер.
## Толчок от шага твари рядом. Сила 0..1 — по тому, насколько он близко.
func step_jolt(force: float) -> void:
	jolt = maxf(jolt, clampf(force, 0.0, 1.0))


func abandon() -> void:
	visible = false
	set_process(false)
	abandoned.emit()


func force_fail() -> void:
	if visible:
		_end_fail()


func _end_fail() -> void:
	visible = false
	set_process(false)
	failed.emit()


## Точка фигуры, с которой совпадает другая, ещё не взятая, с МЕНЬШИМ номером:
## её подпись рисует та, меньшая, — «1 · 6» одной строкой, а не две цифры
## друг на друге.
func _twin_below(d: Dictionary) -> bool:
	for o in dots:
		if o == d or int(o["idx"]) < 0 or o["done"]:
			continue
		if int(o["idx"]) < int(d["idx"]) and _dot_pos(o).distance_to(_dot_pos(d)) < 12.0:
			return true
	return false


func _twin_label(d: Dictionary) -> String:
	var ns: String = str(int(d["idx"]) + 1)
	for o in dots:
		if o == d or int(o["idx"]) < 0 or o["done"]:
			continue
		if int(o["idx"]) > int(d["idx"]) and _dot_pos(o).distance_to(_dot_pos(d)) < 12.0:
			ns += " · " + str(int(o["idx"]) + 1)
	return ns
