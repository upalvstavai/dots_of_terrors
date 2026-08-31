extends Control
## ТОЧКИ УЖАСА — захват. Перенос из HTML (startMash / updMash / renderFaceArms).
##
## Раньше это была красная надпись и полоска. Теперь захват видно на себе:
## с краёв экрана к лицу тянутся щупальца, и отпускают они не по таймеру,
## а от твоих нажатий.

signal escaped
signal failed

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

var count: int = 0
var need: int = NEED_BASE
var time_left: float = 0.0
var grip: float = 0.55
var arms: Array = []
var label: String = "ЖМИ ПРОБЕЛ! ВЫРЫВАЙСЯ!"
var t: float = 0.0
var _rng := RandomNumberGenerator.new()


func begin(text: String, loud: bool, seed_value: int, stage: int = 0) -> void:
	_rng.seed = seed_value
	need = NEED_BASE + stage * NEED_PER_STAGE
	label = text
	count = 0
	time_left = TIME
	grip = 0.55
	t = 0.0
	_make_arms(8 if loud else 6)
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
	grip = clampf(0.55 + 0.80 * (1.0 - time_left / TIME) - relief, 0.0, 1.0)
	if count >= need:
		_end(true)
	elif time_left <= 0.0:
		_end(false)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.016, 0.016, 0.40 + 0.30 * grip))
	var c := size * 0.5
	# Материал тот же, что у стен и у монстра: это не отдельная тварь,
	# это стена дотянулась.
	for a in arms:
		var root := _edge(a["u"])
		var reach: float = clampf((0.30 + 0.85 * grip) * float(a["lead"]), 0.0, 1.18)
		var dir := c - root
		var l: float = maxf(dir.length(), 1.0)
		var ort := Vector2(-dir.y, dir.x) / l
		var pts := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var s: float = float(i) / float(n)
			var w: float = sin(t * 3.2 + float(a["seed"]) + s * 4.4) * 26.0 * s * (1.0 - s * 0.35) \
				+ float(a["curl"]) * s * s * 30.0 * grip
			pts.append(root + dir * s * reach + ort * w)
		for i in n:
			var th: float = float(a["w"]) * (1.0 - float(i) / float(n) * 0.72)
			draw_line(pts[i], pts[i + 1], Color(0.81, 0.79, 0.75, 0.28 + 0.5 * grip), th)
			draw_line(pts[i], pts[i + 1], Color(0.02, 0.03, 0.04, 0.75), maxf(1.0, th * 0.42))
		for i in range(2, n, 2):
			var r: float = maxf(1.0, float(a["w"]) * (1.0 - float(i) / float(n) * 0.72) * 0.30)
			draw_circle(pts[i], r, Color(0.91, 0.89, 0.85, 0.18 + 0.45 * grip))

	var f := ThemeDB.fallback_font
	var jit := Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5) * (3.0 + 7.0 * grip)
	draw_string(f, Vector2(0, size.y * 0.80) + jit, label, HORIZONTAL_ALIGNMENT_CENTER,
		size.x, 21, Color(1.0, 0.42, 0.35))
	var w := 260.0
	var frac: float = clampf(float(count) / float(need), 0.0, 1.0)
	draw_rect(Rect2((size.x - w) * 0.5, size.y * 0.835, w, 12), Color(1.0, 0.42, 0.35), false, 1.0)
	draw_rect(Rect2((size.x - w) * 0.5, size.y * 0.835, w * frac, 12), Color(1.0, 0.42, 0.35))
