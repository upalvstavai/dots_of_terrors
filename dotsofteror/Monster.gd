extends Node3D
## ТОЧКИ УЖАСА — монстр. Перенос из HTML (updInWall / updMonster / updHaunt).
##
## Главное решение автора, которое надо сохранить любой ценой: в первых двух фазах
## монстра НЕ СУЩЕСТВУЕТ КАК ТЕЛА. Он внутри камня, не рисуется вообще и только
## слышен — с направлением. Пока он не вылез, вся угроза идёт через слух.
##
## Скорости заданы ДОЛЯМИ от скорости игрока, а не метрами. В прототипе они
## настраивались замерами при игроке 160 px/с; если переносить абсолютные числа,
## всё ломается от одной правки скорости игрока.

signal emerged                 ## вылез из стены — началась третья фаза
signal caught                  ## дотянулся до игрока
signal noticed                 ## заметил и пошёл на сближение

## ХОД В КАМНЕ задаётся в КЛЕТКАХ в секунду, а не долей от игрока — и это важно.
## Тут вопрос не «догонит или нет», а «через сколько дойдёт», то есть длина арки
## первых двух фаз. Доля от игрока сломалась при переносе: в браузере игрок шёл
## 3.33 клетки/с, в Godot — 1.33, и та же одна пятая дала монстру 0.27 клетки/с
## вместо 0.67. Замер: при 0.27 он НЕ ДОХОДИЛ за 400 секунд ни на одной из десяти карт.
const INWALL_CELLS := 0.667    ## клеток в секунду вблизи игрока
## Издалека он идёт БЫСТРЕЕ. Замер: против неподвижного игрока он выходил за
## 125–148 с, а против ходящего — от 28 до 391, потому что «ближайшая к игроку
## стена» скачет по карте быстрее, чем он ползёт. Плюс на каждом полотне он
## замирал. За восьмиминутный забег мог не дойти ни разу — так и вышло.
## Вблизи скорость прежняя: угроза должна нарастать медленно.
const INWALL_FAR := 1.7        ## во сколько раз быстрее, когда далеко
const INWALL_CAP := 200.0      ## через столько секунд выходит в любом случае
const INWALL_WANDER_F := 0.25  ## доля пересчётов «куда попало»: подход не прямой линией

## Доли от скорости ИГРОКА — тут наоборот, вопрос именно в том, убежишь ли.
const K_HUNT := 0.74
const K_CHASE := 0.91
const K_MAX := 1.50            ## потолок при максимальной ярости. Быстрее нельзя:
                               ## от такого не убежать в принципе, и лабиринт
                               ## превращается в коридор смерти
const ANGER_MAX := 30

const PH3_MEET_CELLS := 2.2    ## на каком расстоянии сквозь стену он решает вылезти
const CUT_FAR_CELLS := 12      ## обход по коридорам, после которого он режет напрямую
## Расстояние захвата считается ТОЛЬКО по горизонтали. Монстр стоит на полу
## (y = 0), а камера игрока — на 0.85 м выше, и объёмное расстояние между ними
## никогда не падало ниже этих 0.85. При пороге 0.9 ему надо было подойти
## на 29 сантиметров по горизонтали — а он и не может, он останавливается
## в центре клетки. Отсюда «подошёл вплотную и не нападает».
const CATCH_DIST := 1.3        ## метров по горизонтали
const REPATH := 0.45           ## как часто пересчитывать путь, сек

var maze
var cell_size: float = 2.4
var player_speed: float = 3.2
var mode: String = "inwall"
var stun: float = 0.0
var path: Array = []
var _path_t: float = 0.0
var _see_t: float = 0.0
var cutting: bool = false
var parked: bool = false        ## игрок рисует — монстр стоит и ждёт
var finale_mode: bool = false   ## идёт к двери: он и есть таймер
var finale_near: float = 0.0    ## 0 — далеко, 1 — дошёл
var _fin_start: int = 1
var _fin_speed: float = 0.27
var trail: Array = []
var _trail_t: float = 0.0
var _shiv: float = 0.0
var inwall_time: float = 0.0
var segs: Array[MeshInstance3D] = []
var shards: Array = []
const SHARDS := 22
## РОСТ. Первая версия была ростом с куст: осколки по метру, глаза на 1.42 —
## ниже глаз игрока (1.62). Снизу вверх смотреть должен ты, а не оно.
## Теперь он выше человека и почти достаёт до верха коридора (стены 2.9),
## а в ширину остаётся уже прохода (коридор 2.4), чтобы по нему проходить.
const HEIGHT := 2.7            ## метров до глаз
const WIDTH := 0.62            ## радиус разброса осколков

var body: MeshInstance3D
var eye_l: MeshInstance3D
var eye_r: MeshInstance3D
var eye_mats: Array = []
var _rng := RandomNumberGenerator.new()


func setup(maze_ref, cell: float, pspeed: float, seed_value: int) -> void:
	maze = maze_ref
	cell_size = cell
	player_speed = pspeed
	_rng.seed = seed_value
	_build_body()
	visible = false


func _build_body() -> void:
	# НЕ КАПСУЛА. Гладкое цельное тело читается как тупой предмет — в браузере
	# он был роем нитей, и силуэт говорил главное: эта штука НЕ ДЕРЖИТ ФОРМУ.
	# Здесь то же самое собирается из тонких осколков вокруг пустого центра.
	# Такое устройство и пригодится дальше: «принять любую форму» — это просто
	# другая раскладка осколков, тело переписывать не придётся.
	body = MeshInstance3D.new()
	add_child(body)
	var shell := StandardMaterial3D.new()
	# Оболочка цвета СТЕН: он читается как камень, в котором что-то живое,
	# а не как отдельная зелёная тварь.
	shell.albedo_color = Color(0.36, 0.37, 0.36)
	shell.emission_enabled = true
	shell.emission = Color(0.10, 0.40, 0.20)
	shell.emission_energy_multiplier = 0.25
	shell.roughness = 1.0
	for i in SHARDS:
		var sh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w: float = 0.07 + _rng.randf() * 0.07
		bm.size = Vector3(w, HEIGHT * (0.35 + _rng.randf() * 0.55), w)
		sh.mesh = bm
		sh.material_override = shell
		var a: float = TAU * float(i) / float(SHARDS)
		var rad: float = WIDTH * (0.30 + _rng.randf() * 0.70)
		sh.position = Vector3(cos(a) * rad, HEIGHT * (0.30 + _rng.randf() * 0.45), sin(a) * rad)
		sh.rotation = Vector3(_rng.randf() * 0.5 - 0.25, a, _rng.randf() * 0.5 - 0.25)
		body.add_child(sh)
		shards.append({"n": sh, "base": sh.position, "ph": _rng.randf() * TAU, "rot": sh.rotation})
	# Ядро — то, что внутри камня. Маленькое и зелёное, просвечивает сквозь осколки.
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.34
	cm.height = 0.68
	core.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.06, 0.20, 0.10)
	cmat.emission_enabled = true
	cmat.emission = Color(0.14, 0.75, 0.35)
	cmat.emission_energy_multiplier = 1.6
	core.material_override = cmat
	core.position = Vector3(0, HEIGHT * 0.55, 0)
	body.add_child(core)
	eye_l = _eye(-0.19)
	eye_r = _eye(0.19)
	_build_segments(shell)


## Хвост сороконожки: сегменты идут по СЛЕДУ головы с равным шагом.
## Пропадал с тех пор, как тело собрали из осколков, — старый цикл жил внутри
## прежнего _build_body и исчез вместе с ним.
func _build_segments(shell: StandardMaterial3D) -> void:
	for i in 12:
		var sgm := MeshInstance3D.new()
		var sm2 := SphereMesh.new()
		var rr: float = WIDTH * 0.95 * (1.0 - float(i) / 15.0)
		sm2.radius = rr
		sm2.height = rr * 2.0
		sgm.mesh = sm2
		sgm.material_override = shell
		sgm.top_level = true          # сегменты живут в мире, а не на голове
		sgm.visible = false
		add_child(sgm)
		segs.append(sgm)


func _eye(dx: float) -> MeshInstance3D:
	var e := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.125
	sm.height = 0.25
	e.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.15, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.18, 0.14)
	mat.emission_energy_multiplier = 3.0
	e.material_override = mat
	# Глаза ВЫШЕ глаз игрока (1.62): смотреть снизу вверх должен ты.
	e.position = Vector3(dx, HEIGHT, -0.42)
	eye_mats.append(mat)
	add_child(e)
	return e


## Ставим как можно дальше от игрока, ВНУТРИ камня.
func place_far_from(from_cell: Vector2i, skin: Array) -> void:
	var best: Vector2i = from_cell
	var bd := -1
	for c in skin:
		var d: int = absi(c.x - from_cell.x) + absi(c.y - from_cell.y)
		if d > bd:
			bd = d
			best = c
	global_position = _to_world(best)
	mode = "inwall"
	visible = false
	path.clear()


func tick(delta: float, player_pos: Vector3, anger: int, in_finale: bool) -> void:
	if mode == "gone":
		return
	if stun > 0.0:
		stun -= delta
		return
	# Пока игрок рисует, монстр НЕ движется: он замер там, где его застало полотно.
	# Иначе он подходил вплотную и хватал сразу на выходе — доделать рисунок
	# означало попасться, и полотно превращалось в ловушку.
	if finale_mode:
		_tick_finale(delta, player_pos)
		return
	if parked:
		return
	if mode == "inwall":
		_tick_inwall(delta, player_pos)
	else:
		_tick_out(delta, player_pos, anger, in_finale)


## Скорость от ярости: линейно от базовой до потолка, и упирается ровно на ANGER_MAX.
func _speed(base_k: float, anger: int) -> float:
	var k: float = clampf(float(anger) / float(ANGER_MAX), 0.0, 1.0)
	return player_speed * (base_k + (K_MAX - base_k) * k)


# ─────────────────────────── фазы 1–2: он в камне ───────────────────────────

func _tick_inwall(delta: float, player_pos: Vector3) -> void:
	# Страховка: третья фаза — центральное событие игры, и она не должна
	# зависеть от того, повезло ли ему найти дорогу.
	inwall_time += delta
	if inwall_time > INWALL_CAP:
		_emerge(player_pos)
		return
	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = 0.6
		var me := _to_cell(global_position)
		var target: Vector2i
		var skin: Array = maze.wall_skin()
		if _rng.randf() < INWALL_WANDER_F and not skin.is_empty():
			# иногда просто бродит по камню: подход не должен быть прямой линией
			target = skin[_rng.randi() % skin.size()]
		else:
			# Цель выбираем ТОЛЬКО по близости к игроку. Если подмешать стоимость
			# пути, побеждает собственная клетка монстра — она стоит ноль,
			# и он стоит на месте.
			var pc := _to_cell(player_pos)
			var bd := 1 << 30
			target = me
			for c in skin:
				var d: int = absi(c.x - pc.x) + absi(c.y - pc.y)
				if d < bd:
					bd = d
					target = c
		path = maze.path_weighted(me, target, 1, 9)
	var far: float = _flat_dist(player_pos) / (cell_size * 18.0)
	var sp: float = INWALL_CELLS * lerpf(1.0, INWALL_FAR, clampf(far, 0.0, 1.0))
	_follow(sp * cell_size * delta)
	# вылез?
	if _flat_dist(player_pos) < PH3_MEET_CELLS * cell_size:
		_emerge(player_pos)


func _emerge(player_pos: Vector3) -> void:
	mode = "chase"
	visible = true
	stun = 1.4
	path.clear()
	_path_t = 0.0
	emerged.emit()


# ─────────────────────────── фаза 3: он снаружи ───────────────────────────

## Осколки всё время шевелятся — форма не держится. Это и есть его силуэт.
func _shiver(delta: float, seen: bool) -> void:
	_shiv += delta
	for sd in shards:
		var n: MeshInstance3D = sd["n"]
		var ph: float = float(sd["ph"])
		var amp: float = HEIGHT * (0.016 + (0.022 if seen else 0.0))
		n.position = Vector3(sd["base"]) + Vector3(
			sin(_shiv * 3.1 + ph) * amp,
			sin(_shiv * 2.3 + ph * 1.7) * amp * 1.6,
			cos(_shiv * 2.7 + ph) * amp)
		n.rotation = Vector3(sd["rot"]) + Vector3(0, sin(_shiv * 1.7 + ph) * 0.25, 0)
	# Глаза — самое яркое, что есть, и загораются, только когда он тебя ВИДИТ.
	# Пока не видит, силуэт остаётся безглазым куском камня.
	var want: float = 4.5 if seen else 0.35
	for m in eye_mats:
		m.emission_energy_multiplier = lerpf(m.emission_energy_multiplier, want, delta * 6.0)


func _update_trail(delta: float) -> void:
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	_trail_t = 0.05
	trail.push_front(global_position)
	if trail.size() > 60:
		trail.resize(60)
	for i in segs.size():
		var idx: int = (i + 1) * 5
		if idx < trail.size():
			segs[i].global_position = trail[idx] + Vector3(0, HEIGHT * 0.42, 0)
			segs[i].visible = visible
		else:
			segs[i].visible = false


func _tick_out(delta: float, player_pos: Vector3, anger: int, in_finale: bool) -> void:
	_update_trail(delta)
	_shiver(delta, _see_t > 0.0)
	var me := _to_cell(global_position)
	var pc := _to_cell(player_pos)
	var sees: bool = maze.los(me, pc)
	if sees:
		_see_t = 2.5                      # заметил — держит направление ещё пару секунд
		if mode == "roam":
			mode = "hunt"
			noticed.emit()
	else:
		_see_t = maxf(0.0, _see_t - delta)
		if mode == "hunt" and _see_t <= 0.0:
			mode = "roam"

	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = REPATH
		# Сквозь стены он ходит НЕ всегда. Мера «далеко» — длина ОБХОДА ПО КОРИДОРАМ,
		# а не прямая: в лабиринте прямая почти всегда мала, и порог по ней не срабатывал.
		var cut: bool = maze.is_wall(me.x, me.y)   # уже в камне — выбираться всё равно сквозь
		if not cut and in_finale:
			var corridor_path: Array = maze.path_weighted(me, pc, 1 << 20, 1)
			cut = corridor_path.is_empty() or corridor_path.size() > CUT_FAR_CELLS
		cutting = cut
		path = maze.path_weighted(me, pc, 7 if cut else (1 << 20), 1)

	var k: float = K_CHASE if mode == "chase" else (K_HUNT if mode == "hunt" else K_HUNT * 0.8)
	var step: float = _speed(k, anger) * delta
	_follow(step)
	# Путь ведёт по КЛЕТКАМ и кончается в центре той, где стоит игрок, — то есть
	# в полутора метрах от него. Последний шаг надо делать прямо на игрока,
	# иначе монстр честно доходит и останавливается рядом.
	if path.is_empty():
		var to := player_pos - global_position
		to.y = 0.0
		var l := to.length()
		if l > 0.05:
			global_position += to / l * minf(step, l)

	if _flat_dist(player_pos) < CATCH_DIST:
		caught.emit()

	# смотрим на игрока
	var to_p := player_pos - global_position
	to_p.y = 0.0
	if to_p.length_squared() > 0.01:
		look_at(global_position - to_p, Vector3.UP)


# ─────────────────────────── движение по пути ───────────────────────────

func _follow(step: float) -> void:
	while step > 0.0 and not path.is_empty():
		var target: Vector3 = _to_world(path[0])
		var d: Vector3 = target - global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.05:
			path.remove_at(0)
			continue
		var m: float = minf(step, l)
		global_position += d / l * m
		step -= m


func _to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.y + 0.5) * cell_size, 0.0, (cell.x + 0.5) * cell_size)


func _to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.z / cell_size), int(pos.x / cell_size))


## Отойти и замереть, пока игрок рисует. Не телепорт через полкарты: отступает
## на несколько клеток по коридору, чтобы это читалось как «отошёл и ждёт».
func park(player_cell: Vector2i, back_cells: int) -> void:
	# Пока он в камне, замирать незачем: схватить он всё равно не может,
	# а заморозка на каждом полотне съедала минуты его подхода.
	if mode == "inwall":
		return
	parked = true
	path.clear()
	_path_t = 0.0
	var me := _to_cell(global_position)
	if maze.is_wall(me.x, me.y):
		return                      # он в камне — там и остаётся
	# Из клеток в паре шагов от себя выбираем ту, что ДАЛЬШЕ всего от игрока.
	var near: Dictionary = maze.distances(me)
	var from_player: Dictionary = maze.distances(player_cell)
	var best := me
	var bd := -1
	for c in near:
		if int(near[c]) > back_cells:
			continue
		var d: int = int(from_player.get(c, -1))
		if d > bd:
			bd = d
			best = c
	global_position = _to_world(best)


func unpark() -> void:
	parked = false
	_path_t = 0.0


## Финал: он выходит на FINAL_DIST клеток и идёт по КОРИДОРАМ, не срезая.
## Срезать тут нельзя — иначе обещанный игроку запас времени превращается
## во вдвое меньший, и дверь срывается не по его вине.
func to_finale(player_cell: Vector2i, cells_away: int, speed_cells: float) -> void:
	finale_mode = true
	parked = false
	visible = true
	mode = "chase"
	stun = 0.0
	_fin_speed = speed_cells
	_fin_start = maxi(1, cells_away)
	finale_near = 0.0
	var dist: Dictionary = maze.distances(player_cell)
	var best := player_cell
	var bd := 1 << 30
	for c in dist:
		var d: int = absi(int(dist[c]) - cells_away)
		if d < bd:
			bd = d
			best = c
	global_position = _to_world(best)
	path.clear()
	_path_t = 0.0


func _tick_finale(delta: float, player_pos: Vector3) -> void:
	var me := _to_cell(global_position)
	var pc := _to_cell(player_pos)
	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = 0.4
		var b: Array = maze.path_weighted(me, pc, 1 << 20, 1)
		if b.is_empty():
			b = maze.path_weighted(me, pc, 7, 1)   # коридором не дойти — только тогда сквозь камень
		path = b
	_follow(_fin_speed * cell_size * delta)
	var left: Array = maze.path_weighted(_to_cell(global_position), pc, 1 << 20, 1)
	finale_near = clampf(1.0 - float(left.size()) / float(_fin_start), 0.0, 1.0)
	var to_p := player_pos - global_position
	to_p.y = 0.0
	if to_p.length_squared() > 0.01:
		look_at(global_position - to_p, Vector3.UP)


## По горизонтали: высота камеры игрока не должна мешать расчётам расстояния.
func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Показать монстра СКВОЗЬ стены. Только для режима создателя: в игре видеть его
## через камень нельзя, на этом держится вся первая фаза.
func set_xray(on: bool) -> void:
	for sd in shards:
		var n: MeshInstance3D = sd["n"]
		var m: StandardMaterial3D = n.material_override
		m.no_depth_test = on
		n.sorting_offset = 100.0 if on else 0.0
	for m2 in eye_mats:
		m2.no_depth_test = on
	for sg in segs:
		var sm: StandardMaterial3D = sg.material_override
		sm.no_depth_test = on
		sg.sorting_offset = 100.0 if on else 0.0
	if not visible and on:
		visible = true          # в камне его иначе просто нет на экране
