extends Control

const Shapes := preload("res://Shapes.gd")
## ТОЧКИ УЖАСА — скример. Перенос из HTML (startScare / renderScare).
##
## Скример — событие, а не реакция на каждую поимку. Бюджет и запреты живут
## в world.gd; здесь только сам удар.

signal done

const HIT := 0.18            ## секунд полной тишины перед ударом

var dur: float = 1.9
var big: bool = true
var t: float = 0.0
var strands: Array = []
var _rng := RandomNumberGenerator.new()


func begin(is_big: bool, is_fatal: bool, seed_value: int) -> void:
	_rng.seed = seed_value
	big = is_big
	dur = 2.6 if is_fatal else (1.9 if is_big else 1.0)
	t = 0.0
	_make_strands(is_fatal)
	visible = true
	set_process(true)


## Точки высыпаются не случайной кашей, а бредущими нитями: так это читается как
## «кто-то доводит рисунок за тебя», а не как помехи на экране.
func _make_strands(fatal: bool) -> void:
	strands.clear()
	var n := (6 if fatal else 4) if big else 1
	var per := 16 if big else 5
	var t0: float = HIT + (0.15 if big else 0.05)
	var t1: float = dur * (0.72 if fatal else 0.62)
	for k in n:
		var pos := Vector2(_rng.randf() * size.x, _rng.randf() * size.y)
		var ang: float = _rng.randf() * TAU
		var pts := []
		for i in per:
			pts.append({"p": pos, "at": t0 + (t1 - t0) * (float(k) + float(i) / float(per)) / float(n)})
			ang += (_rng.randf() - 0.5) * 1.5
			var stp: float = minf(size.x, size.y) * (0.10 + _rng.randf() * 0.10)
			pos += Vector2(cos(ang), sin(ang)) * stp
			if pos.x < 12.0 or pos.x > size.x - 12.0:
				ang = PI - ang
				pos.x = clampf(pos.x, 12.0, size.x - 12.0)
			if pos.y < 12.0 or pos.y > size.y - 12.0:
				ang = -ang
				pos.y = clampf(pos.y, 12.0, size.y - 12.0)
		strands.append({"col": Shapes.PALETTE[_rng.randi() % 3], "pts": pts})


func _process(delta: float) -> void:
	t += delta
	if t >= dur:
		visible = false
		set_process(false)
		done.emit()
		return
	queue_redraw()


func _draw() -> void:
	var u: float = clampf(t / dur, 0.0, 1.0)
	var pre: bool = t < HIT
	var bg: float = (0.58 + 0.36 * (t / HIT)) if pre else 0.94
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, bg))

	# ГЛАЗА ГОЛУБЫЕ — это цвет точек. Красный означал бы просто «опасность»;
	# голубой говорит без слов: оно сделано из того же, из чего твой рисунок.
	var et: float = t - HIT
	var grow: float = clampf(et / 0.5, 0.0, 1.0)
	var ease: float = 1.0 - pow(1.0 - grow, 3.0)
	var r: float = 4.0 if pre else (7.0 + ease * minf(size.x, size.y) * 0.26 if big else 5.0 + ease * 22.0)
	var a: float = (clampf(t / HIT, 0.0, 1.0) * 0.25) if pre else 1.0
	a *= clampf((1.0 - u) / 0.3, 0.0, 1.0)
	_eyes(Vector2(size.x * 0.5, size.y * 0.47), r, a)

	# точки и линии съедают экран — мир доигрывает за игрока его же полотно
	var fade: float = clampf((1.0 - u) / 0.25, 0.0, 1.0)
	for st in strands:
		var live := PackedVector2Array()
		for q in st["pts"]:
			if t >= float(q["at"]):
				live.append(q["p"])
		if live.size() < 1:
			continue
		var col: Color = st["col"]
		col.a = fade * 0.9
		if live.size() > 1:
			draw_polyline(live, col, 1.6)
		for i in live.size():
			draw_circle(live[i], 3.0, col)
	if u > 0.78:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, clampf((u - 0.78) / 0.22, 0.0, 1.0)))


func _eyes(c: Vector2, r: float, a: float) -> void:
	if a <= 0.0:
		return
	var sep := r * 1.15
	for s in [-1.0, 1.0]:
		var p := c + Vector2(s * sep, 0)
		draw_circle(p, r * 1.9, Color(0.31, 0.85, 1.0, 0.16 * a))
		draw_circle(p, r, Color(0.31, 0.85, 1.0, 0.93 * a))
		draw_circle(p, r * 0.16, Color(0.008, 0.024, 0.04, 0.96 * a))
