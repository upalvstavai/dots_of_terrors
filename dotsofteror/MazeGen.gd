extends RefCounted
class_name MazeGen
## ТОЧКИ УЖАСА — генератор лабиринта.
##
## Это не учебный «идеальный лабиринт». Учебный — это дерево без циклов, и для нашей
## игры он плохой: одна кишка, игрок ходит туда-сюда, а стены получаются в одну клетку
## и разваливаются на острова. Здесь исправлены ровно те три беды, на которые
## напоролся HTML-прототип.
##
## 1. КОМНАТ НЕ БЫЛО ВОЗМОЖНО В ПРИНЦИПЕ.
##    Коридоры стояли по нечётным координатам, поэтому в любом квадрате 2×2 хотя бы
##    одна клетка — пол, и вырезать зал было не из чего. Здесь лабиринт строится
##    на УЗЛАХ, а потом растеризуется с любой толщиной стены и шириной коридора.
##
## 2. КАМЕНЬ РАЗВАЛИВАЛСЯ НА ОСТРОВА.
##    В первой и второй фазе монстр движется ВНУТРИ стен, и по островам ходить нельзя.
##    Замер: у стены в одну клетку самый большой кусок камня — 27% всего камня у пола,
##    у стены в две — 38%. Стало лучше, но не идеально, и это нормально: поиск пути
##    у монстра взвешенный (камень стоит 1, пол 9), он плывёт по камню и перескакивает
##    коридоры в самых узких местах. Полная связность не нужна, нужны большие куски.
##
## 3. ТУПИКИ СНОСИЛИСЬ ПОДЧИСТУЮ.
##    Первая версия подрезки оставляла 0.2 тупика на карту, а в них стоят столы
##    с записками. Здесь подрезка идёт ДО ЦЕЛИ, а не до нуля.
##
## Замер на 200 картах при настройках по умолчанию:
##   пол несвязен: 0 карт
##   клеток пола: 556–630, комнат 7, тупиков 2–15 (сред. 9.5), глубина 69–141

const DIRS := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]

var nodes_w: int = 14          ## узлов по горизонтали
var nodes_h: int = 11          ## узлов по вертикали
var corridor: int = 1          ## ширина коридора в тайлах
var wall: int = 2              ## толщина стены в тайлах — от неё зависит всё остальное
var rooms_want: int = 7        ## сколько залов пытаемся разместить
var loops: float = 0.12        ## доля лишних проходов: без них лабиринт — одна кишка
var dead_ends_want: int = 16   ## столько тупиков оставить под столы с записками

var grid: Array = []           ## grid[r][c]: 1 = камень, 0 = пол
var rooms: Array[Rect2i] = []  ## залы в координатах УЗЛОВ
var size: Vector2i             ## размер в тайлах
var _rng := RandomNumberGenerator.new()
var _step: int


## Собрать лабиринт. Один и тот же seed всегда даёт одну и ту же карту —
## это нужно, чтобы воспроизводить баги и делиться сидом.
func generate(seed_value: int) -> void:
	_rng.seed = seed_value
	_step = corridor + wall
	size = Vector2i(wall + nodes_w * _step, wall + nodes_h * _step)
	grid = []
	for r in size.y:
		var row := []
		row.resize(size.x)
		row.fill(1)
		grid.append(row)
	rooms.clear()

	_carve_maze()
	_carve_rooms()
	_add_loops()
	_trim_dead_ends()


# ─────────────────────────── шаги ───────────────────────────

## Рекурсивный бэктрекер по узлам. Даёт связное дерево: из любой точки достижима любая.
func _carve_maze() -> void:
	var seen := {}
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	seen[Vector2i.ZERO] = true
	_carve_node(Vector2i.ZERO)
	while not stack.is_empty():
		var cur: Vector2i = stack[-1]
		var free: Array[Vector2i] = []
		for dir in DIRS:
			var n: Vector2i = cur + dir
			if n.x >= 0 and n.y >= 0 and n.x < nodes_h and n.y < nodes_w and not seen.has(n):
				free.append(dir)
		if free.is_empty():
			stack.pop_back()
			continue
		var pick: Vector2i = free[_rng.randi() % free.size()]
		_carve_link(cur, pick)
		_carve_node(cur + pick)
		seen[cur + pick] = true
		stack.append(cur + pick)


## Залы вырезаются ПОВЕРХ готового лабиринта. Так они связаны без единой проверки:
## все узлы под ними уже были достижимы. Заодно зал сам по себе создаёт петли.
func _carve_rooms() -> void:
	var tries := rooms_want * 30
	while rooms.size() < rooms_want and tries > 0:
		tries -= 1
		var rh := _rng.randi_range(2, 3)
		var rw := _rng.randi_range(2, 3)
		var i0 := _rng.randi_range(0, nodes_h - rh)
		var j0 := _rng.randi_range(0, nodes_w - rw)
		var box := Rect2i(i0 - 1, j0 - 1, rw + 1, rh + 1)   # с зазором, чтобы залы не слипались
		var clash := false
		for other in rooms:
			if box.intersects(Rect2i(other.position, other.size + Vector2i.ONE)):
				clash = true
				break
		if clash:
			continue
		rooms.append(Rect2i(j0, i0, rw, rh))
		var r0 := wall + i0 * _step
		var c0 := wall + j0 * _step
		var r1 := wall + (i0 + rh - 1) * _step + corridor
		var c1 := wall + (j0 + rw - 1) * _step + corridor
		for r in range(r0, r1):
			for c in range(c0, c1):
				grid[r][c] = 0


## Лишние проходы. Дерево без циклов читается как «одна кишка»: заблудиться в нём
## нельзя, можно только ходить туда-сюда. Петли дают развилки и настоящую потерянность.
func _add_loops() -> void:
	var cand: Array = []
	for i in nodes_h:
		for j in nodes_w:
			for dir in [Vector2i(0, 1), Vector2i(1, 0)]:
				var n = Vector2i(i, j) + dir
				if n.x >= nodes_h or n.y >= nodes_w:
					continue
				var mid_r = wall + i * _step + dir.x * corridor
				var mid_c = wall + j * _step + dir.y * corridor
				if grid[mid_r][mid_c] == 1:
					cand.append([Vector2i(i, j), dir])
	cand.shuffle()
	for k in int(cand.size() * loops):
		_carve_link(cand[k][0], cand[k][1])


## Тупики нам НУЖНЫ — в них столы с записками. Убираем только лишние.
func _trim_dead_ends() -> void:
	for _pass in 60:
		var ends := _dead_ends()
		if ends.size() <= dead_ends_want:
			return
		ends.shuffle()
		var kill: int = maxi(1, (ends.size() - dead_ends_want) / 2)
		for k in kill:
			var p: Vector2i = ends[k]
			grid[p.x][p.y] = 1


# ─────────────────────────── помощники ───────────────────────────

func _carve_node(n: Vector2i) -> void:
	var r0 := wall + n.x * _step
	var c0 := wall + n.y * _step
	for r in range(r0, r0 + corridor):
		for c in range(c0, c0 + corridor):
			grid[r][c] = 0


func _carve_link(n: Vector2i, d: Vector2i) -> void:
	var r0 := wall + n.x * _step
	var c0 := wall + n.y * _step
	for k in range(corridor, _step + corridor):
		for t in corridor:
			var r := r0 + d.x * k + (t if d.x == 0 else 0)
			var c := c0 + d.y * k + (t if d.y == 0 else 0)
			if r >= 0 and c >= 0 and r < size.y and c < size.x:
				grid[r][c] = 0


func is_wall(r: int, c: int) -> bool:
	return r < 0 or c < 0 or r >= size.y or c >= size.x or grid[r][c] == 1


func _open_neighbours(r: int, c: int) -> int:
	var n := 0
	for dir in DIRS:
		if not is_wall(r + dir.x, c + dir.y):
			n += 1
	return n


func _dead_ends() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(1, size.y - 1):
		for c in range(1, size.x - 1):
			if grid[r][c] == 0 and _open_neighbours(r, c) == 1:
				out.append(Vector2i(r, c))
	return out


func dead_ends() -> Array[Vector2i]:
	return _dead_ends()


## Камень, граничащий с полом. В фазах 1–2 монстр сидит и движется именно здесь:
## оттуда его слышно и оттуда он может вылезти.
func wall_skin() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(1, size.y - 1):
		for c in range(1, size.x - 1):
			if grid[r][c] == 1 and _open_neighbours(r, c) > 0:
				out.append(Vector2i(r, c))
	return out


## Волновой поиск по полу. Возвращает карту расстояний в клетках от точки.
## По ней расставляются полотна (по нарастающей глубине) и выход (самая дальняя точка).
func distances(from: Vector2i) -> Dictionary:
	var d := {from: 0}
	var q: Array[Vector2i] = [from]
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		for dir in DIRS:
			var n: Vector2i = cur + dir
			if not is_wall(n.x, n.y) and not d.has(n):
				d[n] = int(d[cur]) + 1
				q.append(n)
	return d


## Годна ли карта. Плохие сиды дешевле выбросить, чем чинить: на 200 картах
## отбраковка срабатывала редко, но без неё изредка выпадает тесная или мелкая карта.
func is_good(start: Vector2i, min_floor: int = 480, min_depth: int = 55) -> bool:
	var floor_n := 0
	for r in size.y:
		for c in size.x:
			if grid[r][c] == 0:
				floor_n += 1
	if floor_n < min_floor:
		return false
	var d := distances(start)
	if d.size() != floor_n:
		return false                      # пол распался на куски
	var deepest := 0
	for v in d.values():
		deepest = maxi(deepest, int(v))
	if deepest < min_depth:
		return false
	if rooms.size() < rooms_want - 2:
		return false
	return true


## Взвешенный поиск: камень проходим, но стоит дорого. Нужен монстру в фазах 1–2,
## когда он движется ВНУТРИ стен.
## Почему не «только по камню»: стены в лабиринте не связаны в одно целое — это
## отдельные острова, и поиск строго по ним запирал монстра на месте навсегда.
## С весами он плывёт по камню и лишь перескакивает коридоры в самых узких местах.
func path_weighted(from: Vector2i, to: Vector2i, wall_cost: int, floor_cost: int) -> Array:
	var dist := {from: 0}
	var prev := {}
	# Дейкстра на двоичной куче. Обычной очереди мало: рёбра разного веса.
	var hd: Array[int] = [0]
	var hp: Array[Vector2i] = [from]
	while not hd.is_empty():
		# снимаем минимум
		var d: int = hd[0]
		var cur: Vector2i = hp[0]
		var last := hd.size() - 1
		hd[0] = hd[last]
		hp[0] = hp[last]
		hd.remove_at(last)
		hp.remove_at(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < hd.size() and hd[l] < hd[m]:
				m = l
			if r < hd.size() and hd[r] < hd[m]:
				m = r
			if m == i:
				break
			var td := hd[m]; hd[m] = hd[i]; hd[i] = td
			var tp := hp[m]; hp[m] = hp[i]; hp[i] = tp
			i = m
		if d > int(dist.get(cur, 1 << 30)):
			continue
		if cur == to:
			break
		for dir in DIRS:
			var n: Vector2i = cur + dir
			if n.x < 0 or n.y < 0 or n.x >= size.y or n.y >= size.x:
				continue
			var w: int = wall_cost if grid[n.x][n.y] == 1 else floor_cost
			var nd: int = d + w
			if nd < int(dist.get(n, 1 << 30)):
				dist[n] = nd
				prev[n] = cur
				hd.append(nd)
				hp.append(n)
				var j := hd.size() - 1
				while j > 0:
					var par := (j - 1) / 2
					if hd[par] <= hd[j]:
						break
					var a1 := hd[par]; hd[par] = hd[j]; hd[j] = a1
					var a2 := hp[par]; hp[par] = hp[j]; hp[j] = a2
					j = par
	if not prev.has(to) and to != from:
		return []
	var out: Array[Vector2i] = []
	var c: Vector2i = to
	while c != from:
		out.append(c)
		c = prev[c]
	out.reverse()
	return out


## Прямая видимость по сетке. Клетка камня на пути — значит не видно.
func los(a: Vector2i, b: Vector2i) -> bool:
	var dx: int = absi(b.y - a.y)
	var dy: int = absi(b.x - a.x)
	var sx: int = 1 if a.y < b.y else -1
	var sy: int = 1 if a.x < b.x else -1
	var err: int = dx - dy
	var r: int = a.x
	var c: int = a.y
	for _step in 512:
		if r == b.x and c == b.y:
			return true
		if is_wall(r, c):
			return false
		var e2: int = err * 2
		if e2 > -dy:
			err -= dy
			c += sx
		if e2 < dx:
			err += dx
			r += sy
	return false
