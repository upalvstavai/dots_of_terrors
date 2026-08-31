extends CharacterBody3D
## ТОЧКИ УЖАСА — игрок.
## Перенос из HTML-прототипа (dots_of_terror_3d.html, функции movePlayer / updNoise / tryFlash).
##
## ГЛАВНОЕ ПРО ЧИСЛА: переносить надо ОТНОШЕНИЯ, а не значения.
## В прототипе клетка = 48 пикселей, игрок = 160 пикселей в секунду, то есть клетка
## пересекается за 0.3 с. В метрах это было бы под 10 м/с — скорость велосипедиста,
## и ощущение вышло бы совсем другое. Поэтому абсолютную скорость берём человеческую,
## а сохраняем то, что настраивалось замерами:
##   охота монстра   = 0.74 от игрока  (было 118 из 160)
##   погоня          = 0.91 от игрока  (было 146 из 160)
##   потолок ярости  = 1.50 от игрока  (было 240 из 160)
## Эти три числа — результат плейтестов, их и надо беречь.

# ─────────── движение ───────────
@export var speed: float = 3.2          ## м/с. Быстрый шаг, не бег: от твари убегают редко
@export var accel: float = 14.0         ## разгон/торможение, м/с²
## РЫВОК на пробел. Дан не для удобства: он делает бегство РЕШЕНИЕМ, а не рефлексом.
## Потратил рано — двадцать секунд идёшь пешком, и это те самые секунды, когда оно
## подходит. Множитель держим ниже потолка монстра (1.5 от игрока), иначе погоня
## перестаёт существовать как угроза.
@export var sprint_mul: float = 1.9
@export var sprint_time: float = 10.0
@export var sprint_cd: float = 20.0
@export var eye_height: float = 1.62    ## в прототипе EYE=34 при стене 58 — то есть 0.59 высоты

# ─────────── камера ───────────
## Поворот с клавиатуры — основной способ для ноутбука без мыши, поэтому быстрый.
@export var turn_speed: float = 3.4     ## рад/с: разворот на 180° примерно за 0.9 с
@export var turn_boost: float = 1.9     ## множитель при зажатом Shift: ~0.5 с
@export var quick_turn_time: float = 0.16  ## рывковый разворот кругом по Q
@export var mouse_sens: float = 0.0022  ## при захвате мыши
@export var pitch_limit_deg: float = 70.0
@export var invert_look: bool = false   ## если вертикаль мыши кажется перевёрнутой

# ─────────── шум ───────────
## Единственный сенсор игрока — слух, и шум его отбирает. Но ХОДЬБА не должна
## забивать шкалу до потолка: в первой версии 2.5 секунды ходьбы давали шум 1.0,
## вторая фаза наступала через пять секунд после старта и вся арка схлопывалась.
## Поэтому у ходьбы свой потолок, а выше его гонят только громкие события.
@export var noise_move: float = 1.1
@export var noise_decay: float = 0.34
@export var noise_walk_cap: float = 0.55

# ─────────── вспышка (палочка) ───────────
@export var flash_cooldown: float = 60.0
@export var flash_range_cells: float = 6.0
@export var cell_size: float = 2.4      ## сколько метров в одной клетке лабиринта

signal noise_changed(value: float)
signal flash_fired
signal wall_touched(seconds: float)
signal stepped
signal sprint_started
signal sprint_ended

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var yaw: float = 0.0
var pitch: float = 0.0
var quick_turn_left: float = 0.0        ## сколько радиан осталось довернуть по Q
var noise: float = 0.0
var noise_peak: float = 0.0
var wall_touch: float = 0.0             ## сколько секунд подряд упираемся в камень
var invuln: float = 0.0
var has_wand: bool = false
var flash_charged: bool = true
var flash_cd: float = 0.0
var bob: float = 0.0
var shake_amt: float = 0.0      ## сила дрожи камеры
var shake_dir: float = 0.0      ## с какой стороны тряхнуло, -1 слева .. +1 справа
var sprint_left: float = 0.0    ## сколько секунд рывка осталось
var sprint_cool: float = 0.0    ## сколько до следующего
var _step_t: float = 0.0


func _ready() -> void:
	_ensure_actions()
	yaw = rotation.y


## Заводим управление прямо из кода, если его ещё нет в настройках проекта.
## Так скрипт работает сразу после того, как ты повесил его на узел, — не надо
## руками добавлять девять действий в Проект → Настройки → Ввод. Если ты их там
## всё-таки заведёшь, победят твои: has_action вернёт true и мы не тронем.
func _ensure_actions() -> void:
	_ensure_action("forward",    [KEY_W, KEY_UP])
	_ensure_action("back",       [KEY_S, KEY_DOWN])
	_ensure_action("left",       [KEY_A])
	_ensure_action("right",      [KEY_D])
	_ensure_action("turn_left",  [KEY_LEFT])
	_ensure_action("turn_right", [KEY_RIGHT])
	_ensure_action("run",        [KEY_SHIFT])
	_ensure_action("quick_turn", [KEY_Q])
	_ensure_action("sprint",     [KEY_SPACE])
	_ensure_action("flash",      [KEY_F])


func _ensure_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Приводим тип ЯВНО. У базового InputEvent нет поля relative, поэтому всё,
		# что из него считано, для парсера — Variant, и вывести тип через := нельзя.
		# После приведения relative становится честным Vector2 и всё выводится само.
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * mouse_sens
		var vy := mm.relative.y * (-1.0 if invert_look else 1.0)
		pitch = clampf(pitch - vy * mouse_sens,
			deg_to_rad(-pitch_limit_deg), deg_to_rad(pitch_limit_deg))
	elif event.is_action_pressed("quick_turn") and is_zero_approx(quick_turn_left):
		quick_turn_left = PI                       # развернуться кругом, когда оно за спиной
	elif event.is_action_pressed("sprint"):
		try_sprint()
	elif event.is_action_pressed("flash"):
		try_flash()


func _physics_process(delta: float) -> void:
	_turn(delta)
	_move(delta)
	_update_noise(delta)
	if invuln > 0.0:
		invuln -= delta
	if not flash_charged:
		flash_cd -= delta
		if flash_cd <= 0.0:
			flash_charged = true
	if sprint_left > 0.0:
		sprint_left -= delta
		if sprint_left <= 0.0:
			sprint_cool = sprint_cd
			sprint_ended.emit()
	elif sprint_cool > 0.0:
		sprint_cool -= delta


func _turn(delta: float) -> void:
	var ts := turn_speed * (turn_boost if Input.is_action_pressed("run") else 1.0)
	# Input.get_axis(отрицательное, положительное) даёт +1 при нажатии ВТОРОГО.
	# То есть стрелка влево возвращала +1, а yaw -= уводил вправо: управление
	# с клавиатуры было зеркальным. В Godot положительный поворот вокруг Y — влево.
	yaw += Input.get_axis("turn_right", "turn_left") * ts * delta
	if not is_zero_approx(quick_turn_left):
		# доворачиваем рывком, но не перескакиваем цель
		var step := signf(quick_turn_left) * minf(absf(quick_turn_left), (PI / quick_turn_time) * delta)
		yaw += step
		quick_turn_left -= step
	rotation.y = yaw
	head.rotation.x = pitch


func _move(delta: float) -> void:
	var input := Input.get_vector("left", "right", "forward", "back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var target := dir * (speed * sprint_mul if sprint_left > 0.0 else speed)
	# Разгон, а не мгновенный старт: мгновенный читается как «скольжение по льду»
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	velocity.y = 0.0

	var before := global_position
	move_and_slide()

	# Упираемся в стену? В прототипе это отдельная угроза: прижался — стена оживает.
	# Считаем по фактическому смещению, а не по вводу: так ловится и упор в угол.
	var moved := global_position.distance_to(before)
	if dir.length_squared() > 0.0 and moved < speed * delta * 0.35:
		wall_touch += delta
		wall_touched.emit(wall_touch)
	else:
		wall_touch = maxf(0.0, wall_touch - delta)

	# покачивание головы и шаги
	if dir.length_squared() > 0.0:
		bob += delta * 9.0
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.34
			stepped.emit()
	else:
		bob += delta * 1.5
	# ДРОЖЬ КАМЕРЫ. Предупреждение о том, что сзади трещит камень, нельзя отдавать
	# текстом в углу: его читают только те, кто уже знает, что там что-то бывает.
	# Толчок чувствуется всем телом и приходит С ТОЙ СТОРОНЫ, откуда ударят.
	var sh := Vector3.ZERO
	if shake_amt > 0.0:
		shake_amt = maxf(0.0, shake_amt - delta * 1.6)
		var w: float = shake_amt * shake_amt
		sh = Vector3(sin(bob * 7.3) * 0.05 * w + shake_dir * 0.06 * w,
			sin(bob * 9.1) * 0.05 * w, 0.0)
		head.rotation.z = shake_dir * 0.05 * w
	else:
		head.rotation.z = 0.0
	head.position = Vector3(sh.x, eye_height + sin(bob) * 0.013 * eye_height + sh.y, sh.z)


func _update_noise(delta: float) -> void:
	var moving := Input.get_vector("left", "right", "forward", "back").length_squared() > 0.0
	# «Место» под шум кончается на потолке ходьбы: чем ближе к нему, тем медленнее растёт
	var room := 0.0
	if moving:
		room = maxf(0.0, (noise_walk_cap - noise) / noise_walk_cap)
	noise = clampf(noise + noise_move * room * delta - noise_decay * delta, 0.0, 1.0)
	noise_peak = maxf(noise_peak * (1.0 - delta * 0.15), noise)
	noise_changed.emit(noise)


## Громкие события гонят шум выше потолка ходьбы: вспышка, QTE, осыпавшийся рисунок.
func add_noise(amount: float) -> void:
	noise = clampf(noise + amount, 0.0, 1.0)
	noise_peak = maxf(noise_peak, noise)


## Слышимость: 1.0 — тишина, 0.15 — почти глухота. Множит громкость монстра.
## Это заставляет игрока ОСТАНАВЛИВАТЬСЯ и слушать — лучшая тишина в игре его собственная.
func hearing() -> float:
	return maxf(0.15, 1.0 - noise * 0.85)


## Смотрит ли игрок на точку. Конус широкий (±70°) и БЕЗ проверки прямой видимости:
## удар щупалец назначается за спину, там часто угол коридора, и «обернулся, но между
## вами камень» срывало спасение в половине случаев. Реагируешь ты на звук, а не
## на картинку — значит и засчитывать надо поворот, а не обзор.
func is_looking_at(point: Vector3, cos_limit: float = 0.35) -> bool:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length_squared() < 0.0001:
		return true
	var forward := -global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().dot(to_point.normalized()) > cos_limit


## Рывок. Шум от него не начисляем: бежит игрок и так громко — ходьба уже упирается
## в свой потолок, а сверх него гонят только события вроде вспышки.
func try_sprint() -> void:
	if sprint_left > 0.0 or sprint_cool > 0.0:
		return
	sprint_left = sprint_time
	sprint_started.emit()


func try_flash() -> void:
	if not has_wand or not flash_charged:
		return
	flash_charged = false
	flash_cd = flash_cooldown
	add_noise(0.55)                    # вспышка громкая — после неё какое-то время глухо
	flash_fired.emit()


## Тряхнуть камеру. dir: -1 слева, +1 справа — чтобы толчок ощущался с той
## стороны, откуда идёт угроза, и игрок поворачивался туда рефлекторно.
func shake(amount: float, dir: float) -> void:
	shake_amt = maxf(shake_amt, amount)
	shake_dir = clampf(dir, -1.0, 1.0)
