extends Control
## ТОЧКИ УЖАСА — захват. Перенос из HTML (startMash / updMash / renderFaceArms).
##
## Раньше это была красная надпись и полоска. Теперь захват видно на себе:
## с краёв экрана к лицу тянутся щупальца, и отпускают они не по таймеру,
## а от твоих нажатий.

signal escaped
signal failed

## Два ТИПА захвата. Один требует долбить пробел, другой — НЕ трогать ничего.
## Пока требование одно, руки делают его сами: хват читается не как опасность,
## а как обязанность. Ломается это только сменой требования, потому что тогда
## сначала надо ПРОЧИТАТЬ, чего от тебя хотят, — а читать в панике трудно.
## Режим «не шевелись» отсюда УБРАН вместе с полем kind. Он требовал обратного —
## не нажимать ничего и переждать, — и этим ломал главное чувство захвата:
## из щупалец надо выдираться. Ожидание — это не борьба.

## Двенадцать нажатий за 2.8 с проходились не глядя: кто играл в игры, тапает
## быстрее. База поднята, а с ростом безумия становится ещё хуже — лабиринт
## отбирает не только слух, но и руки.
## Темп нажатий, а не их число — вот что решает. Первая версия просила 17 за 2.5 с,
## то есть 6.8 нажатия в секунду, а на третьей стадии безумия 26 за те же 2.5 —
## это 10.4 в секунду, и такое не проходится вообще никем.
## Держим ставку в человеческих пределах: 4.3 нажатия в секунду в начале
## и 5.8 на самой злой карте. Быстро, но выполнимо.
const NEED_BASE := 17
const NEED_PER_STAGE := 2
const TIME := 4.0
## ПОТОЛОК СТАВКИ. В третьей фазе окно короче (мир передаёт rush), а безумие к
## тому времени обычно уже высокое — и эти два множителя, встретившись, дают
## ставку, которую не берёт никто. Поэтому число нажатий здесь урезается под
## окно: быстрее — да, невозможно — нет.
const HUMAN_MAX := 6.2

var count: int = 0
var need: int = NEED_BASE
var time_left: float = 0.0
var window: float = TIME       ## сколько было дано с самого начала: окно меняется
var grip: float = 0.55
var arms: Array = []
## Значение по умолчанию — на случай, если окно откроют без текста; настоящую
## строку всегда передаёт мир, и она уже переведена.
var label: String = "ЖМИ ПРОБЕЛ! ВЫРЫВАЙСЯ!"
var t: float = 0.0
var _rng := RandomNumberGenerator.new()
var vign: ColorRect
## Рисовать ли петли. Когда держит САМ МОНСТР, вокруг тебя уже сомкнулись его
## настоящие руки — трёхмерные, с той стороны экрана. Дорисовывать поверх них
## плоскую спираль незачем: именно она и читалась как «спираль перед экраном».
## Петли остаются для щупалец из стен, где никакого тела рядом нет.
var coils: bool = true


## С рождения узел НЕ СЧИТАЕТ. Godot включает _process всем, у кого есть такой
## метод, — и захват тикал с первого кадра игры, задолго до того, как его
## открывали. У захвата из-за этого таймер уходил в ноль сам собой: полотно объявляло
## себя проваленным на второй секунде, закрывалось и ЗАБИРАЛО КУРСОР — на
## стартовом экране пропадала стрелка, и нажать «проснуться» было нечем.
func _ready() -> void:
	# Виньетка отдельным узлом с шейдером: _draw не умеет градиент, а нам нужна
	# именно плавная темнота по краям при прозрачной середине.
	vign = ColorRect.new()
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://grab.gdshader")
	vign.material = m
	add_child(vign)
	move_child(vign, 0)
	set_process(false)


func begin(text: String, loud: bool, seed_value: int, stage: int = 0,
		rush: float = 1.0) -> void:
	_rng.seed = seed_value
	need = NEED_BASE + stage * NEED_PER_STAGE
	label = text
	count = 0
	window = TIME * clampf(rush, 0.5, 1.0)
	need = mini(need, int(HUMAN_MAX * window))
	time_left = window
	grip = 0.55
	t = 0.0
	_make_arms(5 if loud else 4)
	visible = true
	set_process(true)


func _make_arms(n: int) -> void:
	arms.clear()
	for i in n:
		# корни разбросаны по периметру, но не строго равномерно — иначе читается как узор
		var u: float = (float(i) + 0.5) / float(n) + (_rng.randf() - 0.5) * 0.09
		arms.append({"u": u, "seed": _rng.randf() * 99.0, "w": 8.0 + _rng.randf() * 7.0,
			"curl": 1.0 if _rng.randf() < 0.5 else -1.0, "lead": 0.78 + _rng.randf() * 0.44})


func _process(delta: float) -> void:
	t += delta
	time_left -= delta
	# ОТПУСКАНИЕ НЕЛИНЕЙНОЕ (степень 1.7). При линейном щупальца слетали с лица
	# за первые же нажатия — борьба кончалась раньше, чем игрок успевал её увидеть.
	# Теперь держат почти до конца и срываются на последних ударах.
	var relief: float = 0.95 * pow(clampf(float(count) / float(need), 0.0, 1.0), 1.7)
	grip = clampf(0.55 + 0.80 * (1.0 - time_left / window) - relief, 0.0, 1.0)
	if count >= need:
		_end(true)
	elif time_left <= 0.0:
		_end(false)
	if vign != null and vign.material != null:
		vign.material.set_shader_parameter("grip", grip)
		vign.size = size
	queue_redraw()


func press() -> void:
	count += 1


func _end(ok: bool) -> void:
	visible = false
	set_process(false)
	if ok:
		escaped.emit()
	else:
		failed.emit()


func _edge(u: float) -> Vector2:
	var per: float = 2.0 * (size.x + size.y)
	var d: float = fposmod(u, 1.0) * per
	if d < size.x:
		return Vector2(d, 0)
	d -= size.x
	if d < size.y:
		return Vector2(size.x, d)
	d -= size.y
	if d < size.x:
		return Vector2(size.x - d, size.y)
	d -= size.x
	return Vector2(0, size.y - d)


func _draw() -> void:
	# Глухой заливки больше нет: её заменила виньетка по краям. Мир видно, и это
	# главное — пока тебя держат, к тебе идут, и ты должен это видеть.
	var c := size * 0.5
	# ЗМЕИ, А НЕ РУКИ ИЗ УГЛОВ. Раньше отсюда к центру тянулись щупальца от краёв
	# экрана — со стороны это читалось как «его язык лижет камеру». Тебя не лижут,
	# тебя ОБВИВАЮТ: каждая петля идёт по спирали вокруг обзора и с каждой
	# секундой затягивается ближе к лицу.
	var base: float = minf(size.x, size.y)
	for a in (arms if coils else []):
		var seed_a: float = float(a["seed"])
		var turn: float = float(a["u"]) * TAU
		# Кольцо сжимается вместе с хваткой. Это и есть весь показатель:
		# видно, сколько тебе осталось, не глядя на полоску.
		var r0: float = base * (0.74 - 0.34 * grip) * float(a["lead"])
		var pts := PackedVector2Array()
		var n := 30
		for k in n + 1:
			var u: float = float(k) / float(n)
			# Три четверти оборота на петлю, с сужением к хвосту: полный круг
			# читался бы обручем, а не змеёй.
			var th: float = turn + u * TAU * 0.78 * float(a["curl"])
			var wob: float = 1.0 + sin(t * 2.6 + seed_a + u * 6.5) * 0.10
			var rr: float = r0 * (1.0 - u * 0.26) * wob
			pts.append(c + Vector2(cos(th) * rr, sin(th) * rr * 0.74))
		for k in n:
			var taper: float = (1.0 - float(k) / float(n) * 0.75)
			# ТОЛЩЕ. На тонких линиях это читалось мотком проволоки, а не телами,
			# которые тебя обвивают.
			var th2: float = float(a["w"]) * 2.1 * taper * (0.60 + 0.70 * grip)
			draw_line(pts[k], pts[k + 1], Color(0.74, 0.73, 0.70, 0.45 + 0.45 * grip), th2)
			draw_line(pts[k], pts[k + 1], Color(0.02, 0.03, 0.04, 0.78),
				maxf(1.0, th2 * 0.45))
		# Присоски по телу петли: без них это шланг, а не живое.
		for k in range(2, n, 3):
			var rr2: float = maxf(1.5, float(a["w"]) * 0.55
				* (1.0 - float(k) / float(n) * 0.75))
			draw_circle(pts[k], rr2, Color(0.91, 0.89, 0.85, 0.16 + 0.42 * grip))

	var f := ThemeDB.fallback_font
	var jit := Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5) * (3.0 + 7.0 * grip)
	draw_string(f, Vector2(0, size.y * 0.80) + jit, label, HORIZONTAL_ALIGNMENT_CENTER,
		size.x, 21, Color(1.0, 0.42, 0.35))
	var w := 260.0
	var frac: float = clampf(float(count) / float(need), 0.0, 1.0)
	draw_rect(Rect2((size.x - w) * 0.5, size.y * 0.835, w, 12), Color(1.0, 0.42, 0.35), false, 1.0)
	draw_rect(Rect2((size.x - w) * 0.5, size.y * 0.835, w * frac, 12), Color(1.0, 0.42, 0.35))
