extends Control

const Shapes := preload("res://Shapes.gd")
## ТОЧКИ УЖАСА — полотно. Перенос из HTML (startDraw / updDraw / renderDraw / drawClick).
##
## Это ядро игры: детская «соедини точки» под таймером и дрожащей рукой.
## Всё, что тут настроено, добыто замерами в прототипе — менять числа можно,
## но каждое из них за что-то отвечает.

signal solved                      ## полотно сдано
signal failed                      ## время вышло, рисунок осыпался
signal mistake                     ## нажал не ту точку

const R_HIT := 16.0                ## радиус попадания по точке
const TIME_STUB := 40.0            ## в финале таймер не идёт: там вместо него монстр
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
var t_global: float = 0.0
var madness_stage: int = 0
var final: bool = false      ## финальная дверь: таймера нет, вместо него монстр
var near: float = 0.0        ## насколько близко он подошёл, 0..1
var _rng := RandomNumberGenerator.new()
var _lamp_tex: GradientTexture2D
var tent_on: bool = false
var tent_t: float = 0.0
var tent_life: float = 0.0
var tent_idx: int = -1
var tent_seed: float = 0.0


func open(shape_data: Dictionary, canvas_index: int, fear: float, stage: int, seed_value: int) -> void:
	_rng.seed = seed_value
	shape = shape_data
	index = canvas_index
	madness_stage = stage
	tremor = clampf(fear, 1.0, Shapes.FEAR_MAX)
	mods = {}
	if not final:
		for m in Shapes.MODS[canvas_index]:
			mods[m] = true
	n = shape["pts"].size()
	time_max = TIME_STUB if final else Shapes.time_for(canvas_index, shape)
	time_left = time_max
	next_idx = 0
	dissolve = 0.0
	pen_t = 0.0
	if _lamp_tex == null:
		_make_lamp()
	tent_on = not final and (canvas_index % TENT_EVERY == 0)
	tent_t = _rng.randf_range(TENT_FIRST[0], TENT_FIRST[1])
	tent_idx = -1
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
	var noise_n := 12 if final else 6 + index * 2
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
	if dissolve > 0.0:
		dissolve -= delta
		if dissolve <= 0.0:
			failed.emit()
		queue_redraw()
		return
	if final:
		time_left = TIME_STUB      # в финале время не идёт: таймер — это он
	else:
		time_left -= delta
	_update_tent(delta)
	if time_left <= 0.0:
		dissolve = Shapes.DISSOLVE_T
	queue_redraw()


## Точка под щупальцем не нажимается, но это и НЕ ошибка: наказывать за то,
## что рисунок сам спрятал нужную точку, было бы нечестно.
func blocked(idx: int) -> bool:
	return tent_idx == idx and tent_life > 0.0


func _update_tent(delta: float) -> void:
	if not tent_on:
		return
	if tent_life > 0.0:
		tent_life -= delta
		if tent_life <= 0.0:
			tent_idx = -1
			tent_t = _rng.randf_range(TENT_REPEAT[0], TENT_REPEAT[1])
		return
	tent_t -= delta
	if tent_t <= 0.0 and next_idx < n:
		tent_idx = next_idx
		tent_life = _rng.randf_range(TENT_COVER[0], TENT_COVER[1])
		tent_seed = _rng.randf() * 99.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)


func _click(mouse_pos: Vector2) -> void:
	if dissolve > 0.0:
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
		if next_idx >= n:
			set_process(false)
			visible = false
			solved.emit()
	else:
		mistake.emit()


# ─────────────────────────── геометрия ───────────────────────────

func board_rect() -> Rect2:
	var w: float = minf(size.x * 0.72, 760.0)
	var h: float = minf(size.y * 0.7, 540.0)
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5 - 20.0, w, h)


## Дрейф считается ОДНОЙ функцией и для отрисовки, и для попадания. Иначе игрок
## целится в одно, а нажимает другое.
func _dot_pos(d: Dictionary) -> Vector2:
	var b := board_rect()
	var p: Vector2 = Vector2(b.position.x + d["nx"] * b.size.x, b.position.y + d["ny"] * b.size.y)
	if mods.has("drift"):
		var t: float = t_global * 0.9 + d["ph"]
		p += Vector2(cos(t) * 8.0, sin(t * 1.3) * 6.0)
	return p


## Яркость вместо номерка. Без номерков порядок читался только по цветной ленте,
## а точек одного цвета несколько — понять, какую жать, было нельзя вообще.
## Ступенька ~4.5%: разглядеть надо, но возможно. Шум — заметно ниже любой нужной.
func _dot_alpha(d: Dictionary) -> float:
	if d["done"]:
		return 1.0
	if not mods.has("no_nums"):
		return 0.95 if d["idx"] >= 0 else 0.8
	if d["idx"] < 0:
		return 0.34
	return 1.0 - 0.42 * (float(d["idx"]) / float(maxi(1, n - 1)))


func _jit(a: float) -> float:
	return (_rng.randf() - 0.5) * a


# ─────────────────────────── отрисовка ───────────────────────────

func _draw() -> void:
	var b := board_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.012, 0.024, 0.9))
	draw_rect(b, Color(0.78, 0.77, 0.72, 0.4), false, 1.0)

	# Дрожь: чем меньше времени и чем хуже лабиринт, тем сильнее
	# В финале дрожь считается от БЛИЗОСТИ монстра, а не от таймера.
	var fear: float
	if final:
		fear = clampf(near * 0.9 + madness_stage * 0.1, 0.0, 1.0) * tremor
	else:
		fear = clampf((1.0 - time_left / time_max) * 0.8 + madness_stage * 0.15, 0.0, 1.0) * tremor
	var amp := fear * 5.0
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
		draw_polyline(pts, Color(0.22, 1.0, 0.62, 0.85 * fade), 2.0)

	# точки
	for d in dots:
		var p := _dot_pos(d) + Vector2(_jit(amp * 0.4), _jit(amp * 0.4))
		var col: Color = Color(0.22, 1.0, 0.62) if d["done"] else Shapes.PALETTE[d["col"]]
		col.a = _dot_alpha(d) * fade
		draw_circle(p, 5.0 if d["done"] else 4.0, col)
		if d["idx"] >= 0 and not d["done"] and not mods.has("no_nums"):
			# Было 9px при непрозрачности 0.3 — приходилось всматриваться вплотную.
			# Читаемость номерка не должна быть частью испытания.
			var txt: String = str(d["idx"] + 1)
			var f := ThemeDB.fallback_font
			draw_string(f, p + Vector2(7, -7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1, 1, 1, 0.92 * fade))

	# Полотно в темноте: видно только пятно вокруг курсора. Рисуем ПОСЛЕ точек,
	# но ДО ленты и таймера — иначе игроку нечем целиться и не видно, сколько осталось.
	if tent_idx >= 0 and tent_life > 0.0 and dissolve <= 0.0:
		for d in dots:
			if d["idx"] == tent_idx:
				var tp := _dot_pos(d)
				for k in 4:
					var a0: float = tent_seed + float(k) * 1.6 + t_global * 2.0
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
	if dissolve <= 0.0:
		_draw_hud(b)


func _draw_hud(b: Rect2) -> void:
	var f := ThemeDB.fallback_font
	# лента порядка цветов
	var sw := 22.0
	var total := n * (sw + 8.0)
	var x0 := (size.x - total) * 0.5
	var y0 := b.position.y + b.size.y + 26.0
	draw_string(f, Vector2(x0 - 84, y0 + 14), "ПОРЯДОК:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.48, 0.66, 0.56, 0.8))
	for i in n:
		for d in dots:
			if d["idx"] == i:
				var col: Color = Shapes.PALETTE[d["col"]]
				col.a = 0.25 if i < next_idx else 1.0
				draw_rect(Rect2(x0 + i * (sw + 8.0), y0, sw, sw), col)
				if i == next_idx:
					draw_rect(Rect2(x0 + i * (sw + 8.0) - 2, y0 - 2, sw + 4, sw + 4),
						Color.WHITE, false, 1.5)
				break
	# Полоска. На обычном полотне — секунды. В финале секунд нет: она НАПОЛНЯЕТСЯ
	# по мере того, как он подходит. Тот же таймер, но у него есть шаги и голос.
	draw_rect(Rect2(b.position.x, b.position.y - 16, b.size.x, 6), Color(0.08, 0.08, 0.11))
	if final:
		draw_rect(Rect2(b.position.x, b.position.y - 16, b.size.x * clampf(near, 0.0, 1.0), 6),
			Color(0.88, 0.31, 0.24))
		draw_string(f, Vector2(b.position.x, b.position.y - 24), "ОНО ИДЁТ",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.88, 0.31, 0.24))
	else:
		var frac: float = clampf(time_left / time_max, 0.0, 1.0)
		draw_rect(Rect2(b.position.x, b.position.y - 16, b.size.x * frac, 6),
			Color(0.22, 1.0, 0.62) if frac > 0.35 else Color(0.88, 0.31, 0.24))
	if tremor > 1.0:
		draw_string(f, Vector2(b.position.x, b.position.y - 24), "СТРАХ x%.1f" % tremor,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.88, 0.31, 0.24))
	if not mods.is_empty():
		var names := []
		for m in mods:
			names.append(Shapes.MOD_NAME[m])
		draw_string(f, Vector2(b.position.x, b.position.y - 40), " . ".join(names),
			HORIZONTAL_ALIGNMENT_RIGHT, b.size.x, 12, Color(0.72, 0.64, 0.29))


## Он дошёл — полотно сорвано.
func force_fail() -> void:
	if visible:
		_end_fail()


func _end_fail() -> void:
	visible = false
	set_process(false)
	failed.emit()
