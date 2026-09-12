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
var _moving: bool = false   ## идёт ли: покачивание считается в кадре, а не в физике
## ХРОМОТА. После удара о стену игрок ковыляет: на каждый второй шаг тело
## проседает и заваливается вбок. Живёт здесь, а не в мире, потому что положение
## головы переписывается тут каждый физический кадр — снаружи его не удержать.
var limp: float = 0.0
## Насколько глаз опущен: 0 — стоит, 1 — лежит на полу.
var down: float = 0.0
var shake_amt: float = 0.0      ## сила дрожи камеры
var shake_dir: float = 0.0      ## с какой стороны тряхнуло, -1 слева .. +1 справа
var shake_hold: float = 0.0     ## затяжная дрожь: руки трясутся ещё долго после
var sprint_left: float = 0.0    ## сколько секунд рывка осталось
var sprint_cool: float = 0.0    ## сколько до следующего
var sprint_drain: float = 1.0   ## во сколько раз быстрее тает недозаряженный
var _step_t: float = 0.0


func _ready() -> void:
	_ensure_actions()
	yaw = rotation.y


## Заводим управление прямо из кода, если его ещё нет в настройках проекта.
## Так скрипт работает сразу после того, как ты повесил его на узел, — не надо
## руками добавлять девять действий в Проект → Настройки → Ввод. Если ты их там
## всё-таки заведёшь, победят твои: has_action вернёт true и мы не тронем.
## ГЕЙМПАД. Хоррор от первого лица в наше время пробуют с геймпада — и стример,
## и рецензент. Раньше с ним нельзя было даже пойти вперёд, и игра выглядела
## сломанной ещё до первого коридора.
##
## Ходьба и кнопки заводятся как обычные события действий, а ВЗГЛЯД — руками в
## _pad_look: у стика нужна мёртвая зона и своя кривая, а событием этого не
## задать. Мышь при этом никуда не девается, оба живут одновременно.
const PAD_DEAD := 0.18          ## мёртвая зона стика
const PAD_SPEED := 3.1          ## рад/с при полном отклонении


func _ensure_actions() -> void:
	_ensure_action("forward",    [KEY_W, KEY_UP],    [[JOY_AXIS_LEFT_Y, -1.0]])
	_ensure_action("back",       [KEY_S, KEY_DOWN],  [[JOY_AXIS_LEFT_Y, 1.0]])
	_ensure_action("left",       [KEY_A],            [[JOY_AXIS_LEFT_X, -1.0]])
	_ensure_action("right",      [KEY_D],            [[JOY_AXIS_LEFT_X, 1.0]])
	_ensure_action("turn_left",  [KEY_LEFT],         [])
	_ensure_action("turn_right", [KEY_RIGHT],        [])
	_ensure_action("run",        [KEY_SHIFT],        [JOY_BUTTON_LEFT_SHOULDER])
	_ensure_action("quick_turn", [KEY_Q],            [JOY_BUTTON_RIGHT_SHOULDER])
	# РЫВОК И ВЫРЫВАНИЕ — на нижнюю кнопку. Это единственное действие, которое
	# в игре колотят как попало, и оно должно лежать под большим пальцем.
	_ensure_action("sprint",     [KEY_SPACE],        [JOY_BUTTON_A])
	_ensure_action("flash",      [KEY_F],            [JOY_BUTTON_X])


## keys — физические клавиши, pad — кнопки (int) и оси ([ось, знак]).
func _ensure_action(action: String, keys: Array, pad: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for j in pad:
		if j is Array:
			var am := InputEventJoypadMotion.new()
			am.axis = int(j[0])
			am.axis_value = float(j[1])
			InputMap.action_add_event(action, am)
		else:
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(j)
			InputMap.action_add_event(action, jb)


## ВЗГЛЯД СТИКОМ. Мёртвая зона обязательна: стик почти никогда не возвращается
## ровно в ноль, и без неё камера сама медленно ползёт — со стороны это выглядит
## как чужая рука на мыши.
##
## Квадрат по модулю, а не прямая: мелкое отклонение даёт мелкий доворот, чтобы
## можно было прицелиться в точку на полотне, а полное — быстрый разворот, чтобы
## успеть обернуться на звук.
func _pad_look(delta: float) -> void:
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var l: float = v.length()
	if l < PAD_DEAD:
		return
	v = v.normalized() * ((l - PAD_DEAD) / (1.0 - PAD_DEAD))
	var k: float = PAD_SPEED * mouse_sens * 320.0 * delta
	yaw -= v.x * absf(v.x) * k
	var vy: float = v.y * absf(v.y) * (-1.0 if invert_look else 1.0)
	pitch = clampf(pitch - vy * k,
		deg_to_rad(-pitch_limit_deg), deg_to_rad(pitch_limit_deg))


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
		sprint_left -= delta * sprint_drain
		if sprint_left <= 0.0:
			sprint_cool = sprint_cd
			sprint_drain = 1.0
			sprint_ended.emit()
	elif sprint_cool > 0.0:
		sprint_cool -= delta


func _turn(delta: float) -> void:
	_pad_look(delta)
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


func _move(delta: float) -> void:
	var input := Input.get_vector("left", "right", "forward", "back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var target := dir * (speed * sprint_mul if sprint_left > 0.0 else speed)
	# Разгон, а не мгновенный старт: мгновенный читается как «скольжение по льду»
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	# ПРИЖИМ К ПОЛУ, А НЕ РОВНЫЙ НОЛЬ. Прыжков и падений в игре нет, поэтому
	# здесь стоял velocity.y = 0.0 — и тело НИКОГДА не садилось на пол: капсула
	# так и стояла вдавленной в него на полтора сантиметра. Движку это не
	# нравилось, и он раз в несколько шагов выталкивал её наружу рывком на
	# двенадцать сантиметров, а потом возвращал обратно. Стоя на месте это и
	# была та самая дёргающаяся камера: раз в десятую долю секунды взгляд
	# подпрыгивал на высоту ступеньки.
	#
	# Полметра в секунду вниз ничего не ломают — под ногами всегда пол, — но
	# капсула лежит НА полу, а не в нём, и выталкивать её больше нечему.
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

	# ШАГИ И ТАЙМЕРЫ — здесь, в физике: это правила, а не картинка.
	_moving = dir.length_squared() > 0.0
	if _moving:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.34
			stepped.emit()
	if shake_hold > 0.0:
		shake_hold -= delta
		shake_amt = maxf(shake_amt, 0.45)
	if shake_amt > 0.0:
		shake_amt = maxf(0.0, shake_amt - delta * (1.6 if shake_hold <= 0.0 else 0.2))
		head.rotation.z = shake_dir * 0.05 * shake_amt * shake_amt
	else:
		head.rotation.z = 0.0
	if limp > 0.0:
		limp = maxf(0.0, limp - delta * 0.055)
		head.rotation.z += sin(bob * 0.5) * 0.045 * limp



## ВИД СОБИРАЕТСЯ КАЖДЫЙ КАДР, А НЕ КАЖДЫЙ ШАГ ФИЗИКИ. Раньше поворот головы и
## покачивание выставлялись только в _physics_process — ровно шестьдесят раз в
## секунду, — а рисуется игра со своей частотой, и на весь экран это далеко не
## шестьдесят. Когда частоты не совпадают, камера получает новое положение то
## через один кадр, то через два: движение идёт рывками при совершенно ровном
## счётчике кадров.
##
## Заметнее всего это СТОЯ НА МЕСТЕ. В движении рывок теряется в общем беге, а
## когда стоишь, всё движение камеры — медленное дыхание, и рваная выдача видна
## как дрожь. Отсюда и «камера дёргается, если начать стоять».
##
## Правила при этом остаются в физике: шаги, дрожь от удара, хромота считаются
## там же, где и были. Здесь только СБОРКА позы из уже посчитанного.
func _view(delta: float) -> void:
	rotation.y = yaw
	head.rotation.x = pitch
	bob += delta * (9.0 if _moving else 1.5)
	# ДРОЖЬ КАМЕРЫ. Предупреждение о том, что сзади трещит камень, нельзя отдавать
	# текстом в углу: его читают только те, кто уже знает, что там что-то бывает.
	# Толчок чувствуется всем телом и приходит С ТОЙ СТОРОНЫ, откуда ударят.
	var sh := Vector3.ZERO
	# Крен (rotation.z) здесь НЕ трогаем: его пишут и сцены снаружи.
	if shake_amt > 0.0:
		var w: float = shake_amt * shake_amt
		sh = Vector3(sin(bob * 7.3) * 0.05 * w + shake_dir * 0.06 * w,
			sin(bob * 9.1) * 0.05 * w, 0.0)
	if limp > 0.0:
		# Пол-частоты от шага: проседает через раз, на одну ногу.
		sh.y += -absf(sin(bob * 0.5)) * 0.085 * limp
	var eh: float = lerpf(eye_height, 0.40, clampf(down, 0.0, 1.0))
	head.position = Vector3(sh.x, eh + sin(bob) * 0.013 * eh + sh.y, sh.z)


func _process(delta: float) -> void:
	# ТОЛЬКО КОГДА КАМЕРА НАША. Захват, полотно, смерть, подъём по насыпи и
	# пролог отбирают у игрока физику и ведут голову сами. Раньше это работало
	# само собой: поза собиралась в _physics_process, а его и выключали. Теперь
	# сборка живёт в кадре, и признак «физика выключена» стал разрешением
	# не трогать чужое.
	if is_physics_processing():
		_view(delta)


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
## Рывок можно сорвать ДОСРОЧНО, не дожидаясь полной перезарядки, — но тогда
## он и сгорает быстрее. Это превращает «ждать или бежать» в живой выбор:
## недозаряженный рывок вытащит из беды сейчас и подведёт через минуту.
func try_sprint() -> void:
	if sprint_left > 0.0:
		return
	var ready: float = 1.0 - clampf(sprint_cool / sprint_cd, 0.0, 1.0)
	if ready < 0.15:
		return                       # совсем пустой не сорвёшь
	sprint_left = sprint_time * ready
	sprint_drain = 1.0 + (1.0 - ready) * 1.5    # чем меньше зарядка, тем быстрее тает
	sprint_cool = 0.0
	sprint_started.emit()


## Возвращает, СРАБОТАЛА ли вспышка. Раньше метод молчал, и вызывающий код
## считал, что она ушла в откат, — а при рассинхроне «палочка в руке» у мира и
## у игрока она гасла впустую и при этом оставалась заряженной навсегда.
func try_flash() -> bool:
	if not has_wand or not flash_charged:
		return false
	flash_charged = false
	flash_cd = flash_cooldown
	add_noise(0.55)                    # вспышка громкая — после неё какое-то время глухо
	flash_fired.emit()
	return true


## Тряхнуть камеру. dir: -1 слева, +1 справа — чтобы толчок ощущался с той
## стороны, откуда идёт угроза, и игрок поворачивался туда рефлекторно.
func shake(amount: float, dir: float) -> void:
	shake_amt = maxf(shake_amt, amount)
	shake_dir = clampf(dir, -1.0, 1.0)


## Долгая дрожь — не удар, а отходняк. Он отстал, ты цел, и вот теперь тебя колотит.
func shake_long(seconds: float) -> void:
	shake_hold = maxf(shake_hold, seconds)
	shake_amt = maxf(shake_amt, 0.6)
