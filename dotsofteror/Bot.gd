extends Node
## СТЕНД. Играет в игру сам и рассказывает, что увидел.
##
## Зачем: чтобы посмотреть на третью фазу, нужно наделать ошибок, найти монстра,
## убежать и поймать момент. Руками это десять минут на один взгляд. Стенд
## ставит нужное состояние за секунду, проигрывает сцену и — главное — САМ
## говорит, что выглядит не так, как задумано.
##
## Он не заменяет игру руками: ощущения он не оценит. Он ловит то, что можно
## посчитать, — а посчитать можно почти все поломки, которые мы уже находили
## глазами: монстр виден в камне, руки тянутся в никуда, управление не вернули,
## звук подменён синтезом.

const PlayerScript := preload("res://Player.gd")
const Settings := preload("res://Settings.gd")
const Shapes := preload("res://Shapes.gd")

var w                          ## мир
var log_lines: Array = []      ## что рассказать в конце
var bad: Array = []            ## что выглядит не так
var _stuck: float = 0.0
var _last: Vector3 = Vector3.ZERO
var _side: float = 1.0         ## в какую сторону обходить
var _shots: int = 0
var _seen: Dictionary = {}     ## какие замечания уже говорили и сколько раз
var pushes: int = 0            ## сколько раз бота пришлось подтолкнуть
var _drawing: bool = false     ## сейчас решаем полотно
var gaps: Array = []           ## промежутки между хватами, с
var mon_near: float = 1e9      ## ближе всего монстр подходил сквозь камень, клеток
var mon_out: bool = false      ## выходил ли он из камня хоть раз за прогон
var mon_out_s: float = 0.0     ## сколько секунд он провёл В КОРИДОРЕ, не в камне
var mon_out_near: float = 1e9  ## ближе всего подходил ИМЕННО В КОРИДОРЕ, клеток
var reach: Dictionary = {}     ## секунды «он дотягивается», разложенные по помехе
var ph_log: Array = []         ## когда наступила каждая фаза, секунд от старта
var ph_last: int = -1
var _last_grab: float = 0.0
## Переживает перезагрузку сцены: второй заход стенда после смерти только докладывает.
static var _died_once: bool = false
var _grab_since: float = 0.0
var _grab_shots: int = 0
var watching: bool = false     ## параллельный присмотр во время полного прохода
var ev: Dictionary = {}        ## что случилось за проход


var froze_t: float = 0.0       ## сколько подряд управление выключено без причин
var tempo_gaps: Array = []     ## промежутки между появлениями твари, с
var tempo_last: float = 0.0
var tempo_watch: bool = false
var tempo_seen: bool = false
var sprints: int = 0           ## сколько раз стенд включал рывок
var sprint_s: float = 0.0      ## и сколько секунд реально бежал


func setup(world) -> void:
	w = world


## Нажатие клавиши НАСТОЯЩИМ событием. Привязка идёт по физической клавише,
## её и шлём: Input.action_press ставит состояние, а игра ждёт событие.
func _press(key: int) -> void:
	var key_ev := InputEventKey.new()
	key_ev.physical_keycode = key
	key_ev.pressed = true
	Input.parse_input_event(key_ev)


func say(s: String) -> void:
	log_lines.append(s)
	print("[стенд] ", s)


func warn(s: String) -> void:
	# ОДНО И ТО ЖЕ — ОДИН РАЗ. Проверки идут каждый кадр, и одна залипшая
	# ситуация выдавала полсотни одинаковых строк подряд, за которыми не было
	# видно ничего другого. Повторы считаем числом.
	var key: String = s
	if _seen.has(key):
		_seen[key] = int(_seen[key]) + 1
		return
	_seen[key] = 1
	bad.append(s)
	print("[стенд] !!! ", s)


## ─────────────────────────── проверки ───────────────────────────
##
## Всё, что здесь, — это правила игры, записанные так, чтобы их можно было
## проверить числом. Каждое из них когда-то сломалось на самом деле.
func check_now(tag: String) -> void:
	var m = w.monster
	var p = w.player_node
	if m == null or p == null:
		return
	var mc: Vector2i = w.world_to_cell(m.global_position)
	var pc: Vector2i = w.world_to_cell(p.global_position)
	# 1. В камне его видеть нельзя: на этом держится вся первая фаза. НО во
	#    время удара о стену и атаки второй формы он ТОРЧИТ из камня нарочно —
	#    это сцена, а не дефект, и ругаться на неё нельзя.
	var scene_on: bool = w.slam_stage > 0 or w.hf_stage > 0 or w.reel_t > 0.0 \
			or w.lift_on or (w.grab_ui != null and w.grab_ui.visible)
	if m.visible and w.maze.is_wall(mc.x, mc.y) and m.mode == "inwall" and not scene_on:
		warn("%s: монстр ВИДЕН, находясь в камне (клетка %s)" % [tag, mc])
	# 2. Игрок внутри стены — значит его куда-то затолкали. Кроме двух законных
	#    случаев: его ВДАВЛИВАЮТ в стену ударом, и он стоит на насыпи обвала,
	#    которая привалена к стене, — там клетка каменная, а человек на ней.
	var on_pile: bool = w.climb != null and w._on_climb(p.global_position)
	if w.maze.is_wall(pc.x, pc.y) and not scene_on and not on_pile:
		warn("%s: игрок ВНУТРИ камня (клетка %s)" % [tag, pc])
	# 3. Под полом или над потолком. На вершине обвала голова ВЫШЕ потолка — это
	#    и есть смысл того места.
	if p.global_position.y < -0.5 or (p.global_position.y > w.wall_height and not on_pile):
		warn("%s: игрок по высоте %.2f — вне комнаты" % [tag, p.global_position.y])
	# 4. Управление отобрано, а окон нет: значит забыли вернуть.
	# И ПАУЗА — тоже законная причина: при свободном курсоре без окна игра
	# намеренно выключает физику (см. paused() в world.gd). В безоконном
	# прогоне курсор свободен по умолчанию, и стенд ругался на это каждый раз,
	# перечислив все причины как нулевые — потому что паузы в списке не было.
	#
	# Обвал забирает управление НА ВСЮ СЦЕНУ, а не только пока тянут вниз:
	# состояние 5 — подъём рывками, 1 — смотрит наверху, 2 — тянут вниз,
	# 3 — уходит под землю. Прощали только 2, и стенд ругался на подъём.
	# Всплыло это, когда окно подсказки про насыпь расширили с метра до 2.4:
	# бот стал туда лазить, а раньше просто не попадал.
	# СМОТРИМ НА ДЛИТЕЛЬНОСТЬ, А НЕ НА МГНОВЕНИЕ.
	#
	# Здесь стояла проверка одного кадра, и она ругалась на исправную игру:
	# порядок _process у узлов не задан, и стенд успевал посмотреть ПОСЛЕ того,
	# как сцена выключила физику, но ДО того, как мир её вернул. В отчёте это
	# выглядело загадочно — все причины ноль, а управления нет.
	#
	# Настоящая беда — это когда управление не вернули СОВСЕМ. Полсекунды на
	# любой обмен между сценами хватает с запасом.
	if not p.is_physics_processing() and not w._busy() and w.drop_t <= 0.0 \
			and w.reel_t <= 0.0 and w.slam_stage == 0 and w.hf_stage == 0 \
			and w.climb_state == 0 and not w.paused():
		froze_t += w.get_process_delta_time()
		if froze_t > 0.5:
			warn("%s: управление отобрано больше полусекунды, а причин нет" % tag)
			froze_t = 0.0
	else:
		froze_t = 0.0
	# 5. Руки не должны тянуться дальше, чем могут: это признак того, что
	#    цель уехала, а решатель об этом не знает.
	for arm in m.arms:
		var jj: Array = arm["joints"]
		var root: Node3D = arm["root"]
		var tip: Node3D = jj[m.ARM_SEGS - 2]
		var reach: float = root.global_position.distance_to(tip.global_position)
		if reach > float(arm["len"]) * 2.2:
			warn("%s: щупальце растянуто на %.1f м при длине %.1f" % [
				tag, reach, float(arm["len"])])
			break


## Проверка звуков: не подменил ли банк синтезом.
func check_sound() -> void:
	for k in ["scream", "strain", "roar", "step_wet", "whip", "hit_low", "breath"]:
		var lst = w.sfx._bank.get(k, [])
		if lst.is_empty():
			warn("звук «%s» не загружен вовсе" % k)
		elif lst.size() == 1 and k in ["scream", "roar", "step_wet"]:
			warn("звук «%s» одиночный — похоже, взят запасной синтез" % k)
	say("звуки на месте: " + str(w.sfx._bank.keys().size()) + " банков")
	# И ЧЕМ ИМЕННО ОНИ ЗВУЧАТ. Число банков ничего не говорит: банк без файлов
	# собирается из синтеза и считается наравне с настоящим. Именно так уехала
	# сборка без шагов по снегу — записи в проекте были, в пакет не попали.
	if not w.sfx.synth_banks.is_empty():
		warn("СИНТЕЗ ВМЕСТО ЗАПИСЕЙ: " + ", ".join(w.sfx.synth_banks))
	if not w.sfx.short_banks.is_empty():
		warn("банки неполные: " + ", ".join(w.sfx.short_banks))
	if w.sfx.synth_banks.is_empty() and w.sfx.short_banks.is_empty():
		say("все банки из настоящих записей, ни одной подмены")


## СНИМОК — И СРАЗУ ЧИСЛА О НЁМ.
##
## Снимок нужен тому, кто МОЖЕТ смотреть картинки. Помощник без зрения (или я
## сам в прогоне без окна) о кадре не узнает ничего, а половина дефектов этой
## игры — именно про картинку: «пусто», «тварь за краем», «чёрный экран».
## Поэтому рядом с PNG кладём его пересказ числами: насколько кадр тёмный,
## сколько в нём светлого, где самое яркое пятно. Считаем по той же картинке,
## что и сохраняем, с шагом в восемь пикселей — это доли миллисекунды.
##
## Как читать: светлость 0.004 и 99% тьмы — это чёрный экран, «не видно
## ничего»; 0.05 и 70% — тёмный коридор, в котором игрок всё-таки видит пол.
func shot(name: String) -> void:
	# БЕЗ ОКНА КАДРА НЕТ. В headless сигнал frame_post_draw не приходит никогда,
	# и ожидание его вешает весь прогон намертво: сцена обвала висела двадцать
	# две минуты ровно на этой строке.
	if DisplayServer.get_name() == "headless":
		return
	var vp: Viewport = w.get_viewport()
	if vp == null or vp.get_texture() == null:
		return
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	img.save_png("user://bot_%02d_%s.png" % [_shots, name])
	_shots += 1
	кадр_числами(img, name)


## Пересказ кадра числами. Отдельной функцией — чтобы её можно было звать и на
## чужой картинке, и из сцены, которой снимок не нужен.
func кадр_числами(img: Image, name: String) -> void:
	var sum: float = 0.0
	var тьма: int = 0
	var свет: int = 0
	var n: int = 0
	var ярче: float = 0.0
	var где := Vector2.ZERO
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c: Color = img.get_pixel(x, y)
			var l: float = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			sum += l
			if l < 0.06:
				тьма += 1
			elif l > 0.45:
				свет += 1
			if l > ярче:
				ярче = l
				где = Vector2(float(x) / float(img.get_width()),
					float(y) / float(img.get_height()))
			n += 1
	if n == 0:
		return
	say("  [кадр %s] светлость %.3f, тьмы %d%%, светлого %d%%, ярчайшее %.2f в (%.2f, %.2f)"
		% [name, sum / float(n), 100 * тьма / n, 100 * свет / n, ярче, где.x, где.y])


## ВИДНО ЛИ ЭТУ ВЕЩЬ В КАДРЕ — числами, без картинки.
##
## Три вопроса, на которые раньше отвечал только мой глаз: попадает ли точка в
## кадр, насколько она в стороне от середины и не закрыта ли камнем. Именно
## так ловятся «монстр пропал из кадра» и «полотно за краем экрана».
func в_кадре(цель: Vector3, имя: String) -> Dictionary:
	var cam: Camera3D = w.player_node.camera
	var экран: Vector2 = w.get_viewport().get_visible_rect().size
	var сзади: bool = cam.is_position_behind(цель)
	var точка: Vector2 = Vector2(-1, -1) if сзади else cam.unproject_position(цель)
	var внутри: bool = not сзади and Rect2(Vector2.ZERO, экран).has_point(точка)
	var к: Vector3 = (цель - cam.global_position).normalized()
	var угол: float = rad_to_deg(acos(clampf(к.dot(-cam.global_transform.basis.z), -1.0, 1.0)))
	var камень: bool = not w._clear_line(cam.global_position, цель)
	var далеко: float = cam.global_position.distance_to(цель)
	say("  [вижу %s] в кадре %s, мимо середины %.0f°, до неё %.1f м, камень между: %s"
		% [имя, str(внутри), угол, далеко, str(камень)])
	return {"в кадре": внутри, "угол": угол, "метров": далеко, "камень": камень}


## ─────────────────────────── ходьба ───────────────────────────
##
## ОБХОД ПРЕПЯТСТВИЙ. Прямолинейный бот застревал у мольберта: он упирался и
## продолжал давить вперёд. Живой человек в такой ситуации делает шаг вбок —
## это и повторяем: уперся на полсекунды, значит идём боком, потом снова вперёд.
## `тихо` — не ругаться, если не дошёл. Нужно для бегства в убежище: не добежал
## — это не дефект игры, а обычное дело в погоне, и в списке «что выглядит не
## так» ему не место.
func goto_cell(goal: Vector2i, limit: float = 25.0, тихо: bool = false) -> bool:
	var p = w.player_node
	var path: Array = w._path(w.world_to_cell(p.global_position), goal)
	var t: float = 0.0
	_last = p.global_position
	_stuck = 0.0
	var strafe: float = 0.0
	var back: float = 0.0
	var nudges: int = 0
	var replan: float = 0.0
	while not path.is_empty() and t < limit:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		# Путь перестраиваем от того места, где он ОКАЗАЛСЯ: за две секунды его
		# успевает снести и захватом, и обходом угла, а старый путь ведёт из
		# точки, где его давно нет.
		replan -= 1.0 / 60.0
		if replan <= 0.0:
			replan = 2.0
			var fresh: Array = w._path(w.world_to_cell(p.global_position), goal)
			if not fresh.is_empty():
				path = fresh
		# РЫВОК. Он есть у игрока и копится сам; не пользоваться им — значит
		# ходить по лабиринту вдвое дольше, чем ходит человек.
		#
		# И ЖАТЬ ЕГО НАДО СОБЫТИЕМ. Здесь стоял `Input.action_press("sprint")`,
		# и он не работал НИ РАЗУ: рывок заводится в Player._input по
		# `is_action_pressed`, то есть ждёт СОБЫТИЕ, а action_press лишь ставит
		# состояние действия. Стенд год ходил пешком — и все замеры погони
		# сравнивали тварь с идущим игроком вместо бегущего. Ровно та же
		# ловушка, на которой уже попадалась клавиша вызова формы.
		if p.sprint_left <= 0.0 and p.sprint_cool <= 0.0:
			_press(KEY_SPACE)
			sprints += 1
		var want: Vector3 = w.cell_to_world(path[0], PlayerScript.STAND_Y)
		var d: Vector3 = want - p.global_position
		d.y = 0.0
		if d.length() < 0.75:
			path.remove_at(0)
			continue
		p.yaw = atan2(-d.x, -d.z)
		if back > 0.0:
			# Пятимся, не поворачиваясь: так выходят из угла.
			back -= 1.0 / 60.0
			Input.action_release("forward")
			Input.action_press("back")
		else:
			Input.action_release("back")
			Input.action_press("forward")
		if strafe > 0.0:
			# Идём боком, не переставая идти вперёд: так обходят угол.
			strafe -= 1.0 / 60.0
			Input.action_press("right" if _side > 0.0 else "left")
		else:
			Input.action_release("right")
			Input.action_release("left")
		if p.global_position.distance_to(_last) < 0.004:
			_stuck += 1.0 / 60.0
			# ПОСЛЕДНЕЕ СРЕДСТВО. Мой ходок туповат: там, где человек обойдёт
			# мольберт за полсекунды, он трётся об угол. Через полторы секунды
			# толкаем его на клетку вперёд по пути и считаем эти толчки —
			# это мера кривости бота, а не уровня.
			if _stuck > 1.5:
				p.global_position = w.cell_to_world(path[0], p.global_position.y)
				nudges += 1
				_stuck = 0.0
				path.remove_at(0)
				if path.is_empty():
					break
				continue
			if _stuck > 0.45 and strafe <= 0.0 and back <= 0.0:
				# СНАЧАЛА ОТОЙТИ, ПОТОМ ОБХОДИТЬ. Один только шаг вбок при
				# упоре в угол ничего не даёт: тело продолжает давить вперёд
				# и скребёт по стене. На прогоне бот так и застревал намертво
				# в одной клетке — три цели подряд провалились из одной точки.
				back = 0.45
				strafe = 0.9
				_side = -_side
				_stuck = 0.0
		else:
			_stuck = 0.0
			_last = p.global_position
	Input.action_release("forward")
	Input.action_release("back")
	Input.action_release("right")
	Input.action_release("left")
	if nudges > 0:
		pushes += nudges
	var here: Vector2i = w.world_to_cell(p.global_position)
	var ok: bool = here == goal or (absi(here.x - goal.x) + absi(here.y - goal.y)) <= 1
	if not ok:
		# РАЗНИЦА ВАЖНА. «Упёрся» — это дефект уровня: там не пройти. «Не успел»
		# — это просто далеко, и виноват мой лимит времени, а не игра. Первый
		# прогон свалил всё в одно слово, и я чуть не записал в баги семь
		# длинных дорог.
		if _stuck > 0.4:
			warn("УПЁРСЯ по дороге к %s: стоял на месте в %s" % [goal, here])
		else:
			if тихо:
				return false
			warn("не успел до %s за %.0f с (шёл, но далеко), остановился в %s"
				% [goal, limit, here])
	return ok


## ─────────────────────────── сценарии ───────────────────────────
##
## Каждый ставит нужное состояние, проигрывает сцену и проверяет её. Названия
## те же, что мы говорим вслух: «третья фаза», «погоня», «руки с потолка».
func set_phase(n: int) -> void:
	# ОСТАТОК ОТ СТАРОЙ СХЕМЫ, ПОЧИНЕНО. Здесь стояло `w._update_phase()` без
	# аргумента — а он давно принимает delta, — и каждый вызов молча падал
	# ошибкой в лог. Фазы теперь не выводятся из числа ошибок: у них свой
	# счётчик времени и полотен. Ошибки оставляем — из них растёт ярость.
	w.errors = [0, w.PHASE_STEP, w.PHASE_STEP * 2, w.PHASE_STEP * 3][clampi(n, 0, 3)]
	w.phase = clampi(n, 0, 3)
	if n >= 3:
		w._phase3_begin()
	w._apply_madness()
	if n >= 3:
		w.phase = 3
		w.monster.last_phase = true
		w.monster.allow_emerge = true
		w.monster.first_out = false
	say("фаза %d: ошибок %d, стадия безумия %d" % [n, w.errors, w._madness_stage()])


## Поставить монстра рядом и включить погоню. Возвращает, добежал ли он.
## ЗВУК ПОГОНИ. Вопрос простой: слышно ли его, когда он бежит за тобой, и
## становится ли громче вблизи. На слух это не проверить — в прогоне звука нет
## вообще, а 22% от 100% на слух и не отличишь. Зато можно измерить то, что
## игра ПРОСИТ сыграть: имя звука, точку, откуда он идёт, и громкость в
## децибелах, — и разложить по расстоянию до монстра.
const MON_SOUNDS := ["skitter", "scrape", "roar", "step_wet", "whip", "hit_low"]

func _bucket(d: float) -> String:
	if d < 1.0:
		return "0-1"
	if d < 2.0:
		return "1-2"
	if d < 4.0:
		return "2-4"
	if d < 6.0:
		return "4-6"
	if d < 10.0:
		return "6-10"
	return "10+"


## ─────────── СКОЛЬКО КАДРОВ СТОИТ БАХРОМА ───────────
##
## Вопрос прямой: не просела ли частота кадров из-за полутора сотен щупалец на
## гуманоиде. Отвечать на него можно только замером ОДНОЙ И ТОЙ ЖЕ сцены с ними
## и без них — всё остальное сравнивает разные вещи.
func scene_cost() -> void:
	say("═══ СКОЛЬКО КАДРОВ СТОИТ БАХРОМА ═══")
	var m = w.monster
	var p = w.player_node
	p.invuln = 9999.0
	stage_clean()
	m.take_form(90.0, m.FORM_HUMAN)
	# Ставим фигуру в упор перед камерой: мерить надо худший случай, а не
	# силуэт в темноте, где её и так почти не рисуют.
	await w.get_tree().create_timer(2.5).timeout
	m.global_position = p.global_position - p.global_transform.basis.z * 3.0
	p.look_force(m.global_position + Vector3.UP * 1.4, 30.0, 40.0)
	await w.get_tree().create_timer(1.0).timeout
	say("щупалец на фигуре: %d" % [m.hum_tend.size()])
	for включены in [true, false]:
		m.hum_tend_on = включены
		await w.get_tree().create_timer(0.6).timeout
		var t: float = 0.0
		var sum: float = 0.0
		var worst: float = 999.0
		var n: int = 0
		while t < 3.0:
			await w.get_tree().process_frame
			t += w.get_process_delta_time()
			var f: float = Performance.get_monitor(Performance.TIME_FPS)
			if f > 1.0:
				sum += f
				worst = minf(worst, f)
				n += 1
		say("  бахрома %s: в среднем %.0f, худший %.0f, вызовов отрисовки %d"
			% ["включена" if включены else "выключена",
			sum / maxf(1.0, float(n)), worst,
			int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	m.hum_tend_on = true


## ─────────── ИЗ ЧЕГО СДЕЛАНА ФИГУРА ───────────
##
## «Пластмассово» — это впечатление, а решать по нему нельзя: непонятно, чинить
## шейдер, свет или саму модель. Считаем треугольники и сравниваем с комом,
## который выглядит мясом. Если у фигуры их в разы меньше — виновата геометрия,
## и никакой шейдер плоские грани не спрячет.
func scene_mesh() -> void:
	say("═══ ИЗ ЧЕГО СДЕЛАНА ФИГУРА ═══")
	var m = w.monster
	_count_mesh(m.human, "фигура (human.glb)")
	_count_mesh(m.blob, "ком (шар со смещением вершин)")


func _count_mesh(root: Node, имя: String) -> void:
	if root == null:
		say("%s: узла нет" % [имя])
		return
	var треугольников: int = 0
	var вершин: int = 0
	var поверхностей: int = 0
	for mi in _all_meshes(root):
		var ms: Mesh = mi.mesh
		if ms == null:
			continue
		for i in ms.get_surface_count():
			поверхностей += 1
			var arr: Array = ms.surface_get_arrays(i)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			вершин += verts.size()
			var idx = arr[Mesh.ARRAY_INDEX]
			треугольников += (idx.size() / 3) if idx != null else (verts.size() / 3)
	say("%s: %d треугольников, %d вершин, поверхностей %d"
		% [имя, треугольников, вершин, поверхностей])


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


## ─────────── ВАНШОТ НА ПОТОЛКЕ БЕЗУМИЯ ───────────
##
## Правило: пятнадцать ошибок — верхняя ступень, и на ней ЛЮБАЯ поимка
## смертельна. Полный проход его не проверяет: бота на этой ступени просто не
## ловят, и строка может быть сколь угодно сломана, а отчёт останется чистым.
## Проверяем прямо — даём поймать себя на второй ступени и на третьей.
func scene_edge() -> void:
	say("═══ ВАНШОТ НА ПОТОЛКЕ БЕЗУМИЯ ═══")
	for ошибок in [10, 15]:
		w.dead = false
		w.streak = 0
		w.mon_kills = 0
		w.errors = ошибок
		w.player_node.invuln = 0.0
		w.grab_cool = 0.0
		var ступень: int = w._madness_stage()
		# Поимка = проваленный хват. Зовём тот же путь, что и игра.
		w._capture("monster")
		await w.get_tree().create_timer(0.3).timeout
		say("ошибок %d (ступень %d): поимок подряд %d, умер=%s"
			% [ошибок, ступень, w.streak, str(w.dead)])
		if ошибок >= 15 and not w.dead:
			warn("на верхней ступени поимка НЕ убила — правило не работает")
		if ошибок < 15 and w.dead:
			warn("на ступени %d одна поимка уже убивает — это слишком рано"
				% [ступень])
		# Прибираем за собой: добивание могло уже запуститься.
		w.dead = false
		w.ending = 0
		w.fat_ending = false
		await w.get_tree().create_timer(0.2).timeout


## ─────────── ПРЕВРАЩЕНИЕ ПАЛОЧКИ В ЛЕЗВИЕ ───────────
##
## Проверяем, что переход ЕСТЬ и что он не мгновенный: лезвие растёт из рукояти,
## нож при этом доворачивается, бусина разгорается и садится, а резать
## недоросшим нельзя. Снимаем три кадра по дороге — начало, середина, конец.
func scene_blade() -> void:
	say("═══ ПАЛОЧКА СТАНОВИТСЯ ЛЕЗВИЕМ ═══")
	var p = w.player_node
	p.invuln = 0.0
	w.has_wand = true
	p.has_wand = true
	stage_clean()
	await w.get_tree().create_timer(1.0).timeout
	w._start_grab("стенд", "monster")
	# Ждём, пока бросок отыграет и откроется сам хват.
	var ждём: float = 0.0
	while not w.grab_ui.visible and ждём < 3.0:
		await w.get_tree().physics_frame
		ждём += 1.0 / 60.0
	if not w.grab_ui.visible:
		warn("хват не открылся — мерить нечего")
		return
	var g3 = w.grab3d
	var кадры: Array = []
	var резал_недоросшим: int = 0
	var t: float = 0.0
	var снято: int = 0
	while t < 1.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		var k: float = float(g3.blade_t)
		if k < 0.8 and g3.bot_slash():
			резал_недоросшим += 1
		if кадры.size() < 6 and int(t * 10.0) > кадры.size() * 2:
			кадры.append("%.2f с: выросло %.2f, длина %.2f, поворот %.0f°"
				% [t, k, g3.knife_blade.scale.y,
				rad_to_deg(g3.knife_blade.rotation.y)])
		if снято < 3 and ((снято == 0 and t > 0.08)
				or (снято == 1 and t > 0.24) or (снято == 2 and t > 0.52)):
			снято += 1
			await shot("лезвие_%d" % снято)
	for стр in кадры:
		say("  " + стр)
	say("рука: превращение %.2f (цель %.2f)" % [w.wand_morph, w.wand_morph_to])
	say("порезов недоросшим лезвием: %d" % [резал_недоросшим])
	if float(g3.blade_t) < 0.99:
		warn("за секунду лезвие так и не выросло: %.2f" % [float(g3.blade_t)])
	if резал_недоросшим > 0:
		warn("огрызком засчитали %d порезов" % [резал_недоросшим])
	if w.wand_morph < 0.99:
		warn("палочка в руке не доехала до лезвия: %.2f" % [w.wand_morph])
	if w.grab_ui.visible:
		w.grab_ui._end(false)


## ─────────── КАК ОН ХВАТАЕТ ───────────
##
## Задумано: тварь отшвыривает игрока ОТ СЕБЯ, всё это время он ничего не может,
## голову ему разворачивает на неё, и нож появляется ровно тогда, когда она
## встала в кадр. Мерим ровно эти четыре вещи — расстояние, управление, угол и
## момент появления ножа.
func scene_catch(гуманоид: bool = false) -> void:
	say("═══ КАК ОН ХВАТАЕТ ═══")
	var m = w.monster
	var p = w.player_node
	p.invuln = 0.0
	stage_clean()
	# ФИГУРОЙ. Она вдвое выше кома, и точка взгляда, верная для кома, у неё
	# приходится на пах. Ловить гуманоидом — отдельный прогон.
	if гуманоид:
		m.take_form(90.0, m.FORM_HUMAN)
		await w.get_tree().create_timer(2.5).timeout
		# В ПРЯМОМ КОРИДОРЕ, а не в стартовом тупике. Там бросок упирался в
		# стену через сорок сантиметров, и стенд принимал «прижат к стене» за
		# «затянуло в себя».
		if _line.is_empty():
			_find_line()
		if _line.size() >= 5:
			var mid: int = _line.size() / 2
			var a0: Vector3 = w.cell_to_world(_line[mid], PlayerScript.STAND_Y)
			var a1: Vector3 = w.cell_to_world(_line[mid - 1], PlayerScript.STAND_Y)
			p.global_position = a0
			m.global_position = Vector3(a0.x, m.global_position.y, a0.z) \
				+ (a1 - a0).normalized() * 2.2
		else:
			m.global_position = p.global_position - p.global_transform.basis.z * 2.2
	else:
		await w.get_tree().create_timer(1.0).timeout
	var было: float = m.global_position.distance_to(p.global_position)
	var физика_шла: bool = false
	w._start_grab("стенд", "monster")
	if w.hurl_t <= 0.0:
		warn("броска не было — хват начался сразу")
		return
	var дальше: float = было
	var угол_в_нож: float = -1.0
	# Расстояние между ними меряет ДВОИХ: тварь в это время тоже идёт, и по
	# нему не понять, отшвырнуло игрока или она подошла. Мерим смещение самого
	# игрока от точки, где его схватили.
	var откуда: Vector3 = p.global_position
	var улетел: float = 0.0
	var снимок: int = 0
	var ближе: float = 99.0
	var t: float = 0.0
	while t < 3.3:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		if w.hurl_t > 0.0 and p.is_physics_processing():
			физика_шла = true
		дальше = maxf(дальше, m.global_position.distance_to(p.global_position))
		улетел = maxf(улетел, откуда.distance_to(p.global_position))
		if гуманоид and fmod(t, 0.3) < 1.0 / 60.0:
			var cp: Vector2i = w.world_to_cell(p.global_position)
			say("  %.1f с: до твари %.2f, тварь %s, игрок %s клетка %s, hurl %.2f lift %s" % [t,
				m.global_position.distance_to(p.global_position),
				str(Vector2(m.global_position.x, m.global_position.z).snapped(Vector2(0.1,0.1))),
				str(Vector2(p.global_position.x, p.global_position.z).snapped(Vector2(0.1,0.1))),
				str(cp), w.hurl_t, str(w.lift_on)])
		if t > 0.9:
			# Ближе всего он подпускает к себе ПОСЛЕ броска: если и здесь
			# расстояние падает — значит всё-таки затягивает в себя.
			ближе = minf(ближе, m.global_position.distance_to(p.global_position))
		# КАДРЫ ПО ДОРОГЕ. Углы и метры не говорят, ВИДНО ли тварь: её может
		# закрыть собственными щупальцами, она может быть в темноте или за
		# спиной у края кадра. Снимаем бросок целиком.
		if снимок < 5 and t > [0.10, 0.50, 1.20, 2.00, 2.90][снимок]:
			снимок += 1
			var cm: Camera3D = p.camera
			var tl: Vector3 = (m.look_point() - cm.global_position).normalized()
			say("  %.1f с: взгляд мимо верха груди на %.0f°" % [t, rad_to_deg(acos(
				clampf(tl.dot(-cm.global_transform.basis.z), -1.0, 1.0)))])
			await shot("поимка_%d" % снимок)
		if w.grab_ui.visible and угол_в_нож < 0.0:
			var cam: Camera3D = p.camera
			var to: Vector3 = (m.look_point() - cam.global_position).normalized()
			say("точка взгляда на %.2f м над ногами твари" % [m.look_point().y - m.global_position.y])
			угол_в_нож = rad_to_deg(acos(clampf(
				to.dot(-cam.global_transform.basis.z), -1.0, 1.0)))
			say("нож дан через %.2f с после поимки" % [t])
			await w.get_tree().create_timer(0.4).timeout
			var g3 = w.grab3d
			var cm3: Camera3D = p.camera
			say("  щупалец хвата: %d, rig виден %s, live %s" % [g3.arms.size(), str(g3.rig.is_visible_in_tree()), str(g3.live)])
			for ai in mini(3, g3.arms.size()):
				var arm: Dictionary = g3.arms[ai]
				var cnt: int = 0
				var inframe: int = 0
				for jd in arm["joints"]:
					var mi3: MeshInstance3D = jd["mesh"]
					if mi3.is_visible_in_tree():
						cnt += 1
						if not cm3.is_position_behind(mi3.global_position):
							var sp: Vector2 = cm3.unproject_position(mi3.global_position)
							if Rect2(Vector2.ZERO, w.get_viewport().get_visible_rect().size).has_point(sp):
								inframe += 1
				if ai == 0:
					var hd: Node3D = p.head
					var line: String = ""
					for jd2 in arm["joints"]:
						line += str(hd.to_local((jd2["mesh"] as MeshInstance3D).global_position).snapped(Vector3(0.01,0.01,0.01))) + " "
					say("    звенья в осях головы: " + line)
					say("    точки дуги: " + str(arm["pts"][0].snapped(Vector3(0.01,0.01,0.01))) + " … " + str(arm["pts"][arm["pts"].size()-1].snapped(Vector3(0.01,0.01,0.01))))
					say("    камера в осях головы: " + str(hd.to_local(cm3.global_position).snapped(Vector3(0.01,0.01,0.01))) + ", rig: " + str(g3.rig.transform.origin) + " " + str(g3.rig.get_parent().name))
				var mk: MeshInstance3D = arm["mark"]
				say("  щупальце %d: звеньев видно %d, в кадре %d, до камеры %.2f м, метка %s, масштаб звена %s" % [ai, cnt, inframe,
					cm3.global_position.distance_to((arm["joints"][3]["mesh"] as MeshInstance3D).global_position),
					str(mk.is_visible_in_tree()), str((arm["joints"][3]["mesh"] as MeshInstance3D).global_transform.basis.get_scale().snapped(Vector3(0.01,0.01,0.01)))])
	say("игрока унесло на %.2f м от места поимки" % [улетел])
	say("во время борьбы ближе всего к твари: %.2f м (держит на %.1f)"
		% [ближе, w.HOLD_DIST])
	if ближе < w.HOLD_DIST - 1.0:
		warn("всё-таки затянуло: подпустило на %.2f м" % [ближе])
	say("расстояние до твари: было %.1f м, стало %.1f м" % [было, дальше])
	say("отклонение взгляда от твари в момент ножа: %.0f°" % [угол_в_нож])
	say("игрок управлял собой во время броска: %s" % [str(физика_шла)])
	if улетел < 1.2:
		warn("его почти не отбросило: всего %.2f м" % [улетел])
	if угол_в_нож < 0.0:
		warn("нож так и не появился за три секунды")
	elif угол_в_нож > w.HURL_SEEN + 4.0:
		warn("нож дан, когда тварь в %.0f° от центра — её толком не видно" % [угол_в_нож])
	if физика_шла:
		warn("во время броска игрок мог двигаться сам")
	await shot("поимка")
	if w.grab_ui.visible:
		w.grab_ui._end(false)


## ─────────── ПОИМКИ В РАЗНЫХ МЕСТАХ ───────────
##
## Один хват в одном коридоре ничего не говорит про углы и развилки. Играющий:
## «отшвырнуло куда-то, а монстр пропал из кадра» — бросок скользил вдоль стены
## за поворот. Ловим в восьми случайных местах и в конце каждой смотрим одно:
## есть ли камень между игроком и тварью и куда смотрит камера.
func scene_catches() -> void:
	say("═══ ПОИМКИ В РАЗНЫХ МЕСТАХ ═══")
	var m = w.monster
	var p = w.player_node
	stage_clean()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var floors: Array = []
	for r in w.maze.size.y:
		for c in w.maze.size.x:
			if not w.maze.is_wall(r, c):
				floors.append(Vector2i(r, c))
	var плохих: int = 0
	for k in 8:
		p.invuln = 0.0
		w.grab_cool = 0.0
		var cell: Vector2i = floors[rng.randi() % floors.size()]
		var dirs: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not w.maze.is_wall(cell.x + d.x, cell.y + d.y):
				dirs.append(d)
		if dirs.is_empty():
			continue
		var dd: Vector2i = dirs[rng.randi() % dirs.size()]
		var at: Vector3 = w.cell_to_world(cell, PlayerScript.STAND_Y)
		var nb: Vector3 = w.cell_to_world(cell + dd, PlayerScript.STAND_Y)
		p.global_position = at
		w.hurl_t = 0.0
		w.hurl_src = ""
		w.reel_t = 0.0
		w.lurk_t = 0.0
		w.lift_on = false
		w.grab_run = 0
		m.drop_hold()
		m.stun = 0.0
		m.resurface_t = 99.0
		m.visible = true
		m.mode = "chase"
		m.global_position = Vector3(at.x, 0.0, at.z) + (nb - at).normalized() * 2.2
		await w.get_tree().physics_frame
		w._start_grab("стенд", "monster")
		if w.hurl_t <= 0.0:
			say("  %d) хват не начался: ui=%s dead=%s pause=%s still=%.1f slam=%d hf=%d invuln=%.1f" % [k + 1,
				str(w._ui_blocking()), str(w.dead), str(w.paused()), w.still_t, w.slam_stage, w.hf_stage, p.invuln])
			continue
		var t: float = 0.0
		var откуда: Vector3 = p.global_position
		while t < 2.6:
			await w.get_tree().physics_frame
			t += 1.0 / 60.0
			if k == 0 and fmod(t, 0.25) < 1.0 / 60.0:
				say("       %.2f с: игрок %s тварь %s hurl %.2f lift %s reel %.2f" % [t,
					str(Vector2(p.global_position.x, p.global_position.z).snapped(Vector2(0.01, 0.01))),
					str(Vector2(m.global_position.x, m.global_position.z).snapped(Vector2(0.01, 0.01))),
					w.hurl_t, str(w.lift_on), w.reel_t])
		say("     отбросило на %.2f м, хват виден %s" % [откуда.distance_to(p.global_position), str(w.grab_ui.visible)])
		var cam: Camera3D = p.camera
		var tl: Vector3 = (m.look_point() - cam.global_position).normalized()
		var ang: float = rad_to_deg(acos(clampf(tl.dot(-cam.global_transform.basis.z), -1.0, 1.0)))
		var видно: bool = w._clear_line(m.global_position, p.global_position)
		var dist: float = Vector2(m.global_position.x - p.global_position.x,
			m.global_position.z - p.global_position.z).length()
		say("  %d) клетка %s: до твари %.1f м, камень между: %s, взгляд мимо %.0f°"
			% [k + 1, str(cell), dist, str(not видно), ang])
		if not видно or ang > 20.0:
			плохих += 1
			await shot("поимки_%d" % [k + 1])
		if w.grab_ui.visible:
			w.grab_ui._end(true)
		# Дать ему отыграть уход в камень и снять всё, что осталось.
		await w.get_tree().create_timer(0.5).timeout
		stage_clean()
		w.lurk_t = 0.0
		w.lift_on = false
		p.invuln = 0.0
	if плохих > 0:
		warn("в %d поимках из 8 тварь не видно" % [плохих])


## ─────────── СМЕРТЬ — НЕ С НУЛЯ ───────────
##
## Друг: «сбрасывают в самое начало». Умираем с тремя сданными полотнами,
## палочкой и безумием на пике, и после перезагрузки смотрим, что осталось.
## Стенд живёт в мире и перезагружается вместе с ним — флаг держит его от круга.
func scene_death() -> void:
	if _died_once:
		say("═══ ПОСЛЕ СМЕРТИ ═══")
		var pc: Vector2i = w.world_to_cell(w.player_node.global_position)
		say("полотен %d, ошибок %d (ступень %d), палочка %s, стоит в %s — убежище: %s, карта сид %d" % [
			w.done, w.errors, w._madness_stage(), str(w.has_wand), str(pc),
			str(w.safe_cells.has(pc)), w._seed_used])
		if w.done != 3:
			warn("сданные полотна не сохранились")
		if not w.has_wand:
			warn("палочка пропала")
		if not w.safe_cells.has(pc):
			warn("проснулся не в убежище")
		return
	_died_once = true
	say("═══ УМИРАЕМ С ТРЕМЯ ПОЛОТНАМИ ═══")
	w.done = 3
	w.errors = 16
	w.has_wand = true
	w.player_node.has_wand = true
	var far: Vector2i = w._far_cell_from(w.start_cell)
	w.player_node.global_position = w.cell_to_world(far, PlayerScript.STAND_Y)
	say("умираем в %s, ступень безумия %d, сид %d" % [str(far), w._madness_stage(), w._seed_used])
	await w.get_tree().create_timer(0.5).timeout
	w._restart_after_death()
	await w.get_tree().create_timer(30.0).timeout


## ─────────── УБЕЖАТЬ ПОСЛЕ ВЫРЫВА ───────────
##
## Играющий: «вырвался, он появился, разворачиваешься — и он быстро догоняет».
## Теперь после вырыва окно, в котором он медленнее. Меряем: вырвались в
## нескольких местах и бежим к ближайшему убежищу — добежали ли, не схватив
## снова, и как близко он подходил.
func scene_run_away(без_окна: bool = false) -> void:
	say("═══ УБЕЖАТЬ ПОСЛЕ ВЫРЫВА ═══")
	var m = w.monster
	var p = w.player_node
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ушёл: int = 0
	var всего: int = 0
	for k in 4:
		stage_clean()
		# Место — в 6–10 клетках от убежища, иначе бежать некуда или незачем.
		var safe: Vector2i = w.safe_cells[k % w.safe_cells.size()]
		var dist: Dictionary = w.maze.distances(safe)
		var pick: Array = []
		for c in dist:
			if int(dist[c]) >= 12 and int(dist[c]) <= 18:
				pick.append(c)
		if pick.is_empty():
			continue
		var cell: Vector2i = pick[rng.randi() % pick.size()]
		p.global_position = w.cell_to_world(cell, PlayerScript.STAND_Y)
		p.invuln = 0.0
		w.grab_cool = 0.0
		w.hurl_t = 0.0
		w.hurl_src = ""
		w.reel_t = 0.0
		m.visible = true
		m.mode = "chase"
		m.chase_t = 60.0
		m.global_position = p.global_position + Vector3(2.2, 0.0, 0.0)
		await w.get_tree().physics_frame
		w._grab_now("стенд", "monster")
		await w.get_tree().create_timer(0.8).timeout
		if w.grab_ui.visible:
			w.grab_ui._end(true)
		if без_окна:
			m.slow_t = 0.0
		всего += 1
		var ближе: float = 99.0
		var схватил: bool = false
		var t0: float = w._clock
		var дошёл: bool = false
		var path: Array = w._path(w.world_to_cell(p.global_position), safe)
		var t: float = 0.0
		while t < 25.0:
			await w.get_tree().physics_frame
			t += 1.0 / 60.0
			if w.grab_ui.visible or w.hurl_t > 0.0:
				схватил = true
				break
			if m.visible and m.mode != "inwall":
				ближе = minf(ближе, Vector2(m.global_position.x - p.global_position.x,
					m.global_position.z - p.global_position.z).length())
			if w.world_to_cell(p.global_position) == safe:
				дошёл = true
				break
			if path.is_empty():
				path = w._path(w.world_to_cell(p.global_position), safe)
				if path.is_empty():
					break
			var want: Vector3 = w.cell_to_world(path[0], PlayerScript.STAND_Y)
			var d: Vector3 = want - p.global_position
			d.y = 0.0
			if d.length() < 0.4:
				path.remove_at(0)
				continue
			# Рывок у человека десять секунд, дальше шагом.
			var rush: float = p.sprint_mul if t < p.sprint_time else 1.0
			var sp: float = p.speed * rush
			var mv: Vector3 = d.normalized() * minf(sp / 60.0, d.length())
			p.global_position += mv
			m.player_rush = rush
		say("  %d) от убежища %d клеток: %s за %.1f с, ближе всего %.1f м" % [k + 1,
			int(dist[cell]), "ДОБЕЖАЛ" if дошёл else ("СХВАТИЛ" if схватил else "не дошёл"),
			w._clock - t0, ближе])
		if дошёл:
			ушёл += 1
		if w.grab_ui.visible:
			w.grab_ui._end(true)
	say("добежал до убежища %d из %d" % [ушёл, всего])


## ─────────── ЯРКОСТЬ: НЕ СТАНОВИТСЯ ЛИ ЛАБИРИНТ ДНЁМ ───────────
func scene_gamma() -> void:
	say("═══ ЯРКОСТЬ ═══")
	stage_clean()
	w.monster.visible = false
	w.monster.mode = "inwall"
	var p = w.player_node
	if _line.is_empty():
		_find_line()
	if _line.size() > 3:
		p.global_position = w.cell_to_world(_line[1], PlayerScript.STAND_Y)
		var to: Vector3 = w.cell_to_world(_line[_line.size() - 1], PlayerScript.STAND_Y)
		p.look_force(to, 2.0, 30.0)
	await w.get_tree().create_timer(1.5).timeout
	var was: float = Settings.gamma
	for g in [1.0, 1.3, 1.6]:
		Settings.set_gamma(g)
		await w.get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var img: Image = w.get_viewport().get_texture().get_image()
		var sum: float = 0.0
		var dark: int = 0
		var n: int = 0
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				var c: Color = img.get_pixel(x, y)
				var l: float = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
				sum += l
				if l < 0.06:
					dark += 1
				n += 1
		say("  яркость %.1f: средняя светлость %.3f, тёмных точек %d%%" % [g, sum / n, 100 * dark / n])
		await shot("яркость_%.1f" % g)
	Settings.set_gamma(was)


## ─────────── ФИНАЛ: ДОХОДИТ ЛИ ОН ДО ДВЕРИ ───────────
##
## Играющий: «монстр не может пройти сквозь жёлтую дверь и из-за этого не
## может атаковать». Жёлтая дверь — выход, её рисуют на седьмом полотне, а он в
## это время идёт по коридорам. Стоим у выхода, не рисуем и смотрим, дойдёт ли.
func scene_finale() -> void:
	say("═══ ФИНАЛ: ДОХОДИТ ЛИ ОН ═══")
	var m = w.monster
	var p = w.player_node
	stage_clean()
	p.invuln = 0.0
	w.done = w.n_canv
	p.global_position = w.cell_to_world(w.exit_cell, PlayerScript.STAND_Y)
	await w.get_tree().create_timer(0.5).timeout
	w._open_finale()
	say("выход %s в убежищах мира: %s, у твари: %s; убежища %s" % [str(w.exit_cell),
		str(w.safe_cells.has(w.exit_cell)), str(m.safe_cells.has(w.exit_cell)), str(w.safe_cells)])
	var t: float = 0.0
	var сорвал: bool = false
	while t < 80.0:
		# Срок рисования двери не даём истечь: стенд не рисует, и на 50-й
		# секунде засчитывалась поимка по таймеру — ровно тогда, когда он
		# подходил. Здесь меряем другое: ДОХОДИТ ли он вообще.
		w.board.time_left = w.board.time_max
		await w.get_tree().create_timer(1.0).timeout
		t += 1.0
		var mc: Vector2i = w.world_to_cell(m.global_position)
		say("  %2.0f с: до игрока %.1f м, клетка твари %s (выход %s), близость %.2f, путь %d, полотно %s" % [t,
			m.global_position.distance_to(p.global_position), str(mc), str(w.exit_cell),
			m.finale_near, m.path.size(), str(w.board.visible)])
		if not w.board.visible or not w.finale:
			сорвал = true
			break
	if сорвал:
		say("дошёл и сорвал дверь за %.0f с" % [t])
		await w.get_tree().create_timer(3.0).timeout
		if w.finale:
			warn("после срыва финал открылся заново сам")
		else:
			say("после срыва финал закрыт, игрок в %.0f м от выхода" % [
				p.global_position.distance_to(w.cell_to_world(w.exit_cell, p.global_position.y))])
	else:
		warn("за 80 с так и не дошёл до двери")


## ─────────── ЧТО БЫВАЕТ ПОСЛЕ ТОГО, КАК ВЫРВАЛСЯ ───────────
##
## Задумано так: он мгновенно уходит в камень на пять секунд, погоня при этом
## НЕ кончается, а скрежет идёт из разных стен вокруг — понять, где он, нельзя.
## Мерим ровно это: пропал ли он, идёт ли погоня, из скольких РАЗНЫХ точек
## пришёл звук и как быстро он вернулся.
func scene_after_escape() -> void:
	say("═══ ПОСЛЕ ТОГО, КАК ВЫРВАЛСЯ ═══")
	var m = w.monster
	var p = w.player_node
	p.invuln = 9999.0
	stage_clean()
	await w.get_tree().create_timer(1.0).timeout
	w._grab_now("стенд", "monster")
	await w.get_tree().create_timer(0.6).timeout
	if not w.grab_ui.visible:
		warn("хват не открылся — мерить нечего")
		return
	# Вырываемся по-настоящему: тем же ножом, что и игрок.
	while w.grab_ui.visible:
		w.grab_ui.bot_slash()
		await w.get_tree().create_timer(0.14).timeout
	say("вырвался: монстр виден=%s, режим=%s" % [str(m.visible), m.mode])
	w.sfx.heard.clear()
	w.sfx.watch = true
	var точки: Dictionary = {}
	var звуков: int = 0
	var виден_через: float = -1.0
	var бит: bool = false
	var t: float = 0.0
	while t < 9.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		if w.lurk_t > 0.0:
			бит = бит or w.sfx.beat_on()
		if m.visible and виден_через < 0.0:
			виден_через = t
		for e in w.sfx.heard:
			if not bool(e["из точки"]):
				continue
			звуков += 1
			# Округляем до клетки: интересно, из СКОЛЬКИХ РАЗНЫХ мест он шумел.
			var c: Vector2i = w.world_to_cell(e["где"])
			точки[c] = int(точки.get(c, 0)) + 1
		w.sfx.heard.clear()
	w.sfx.watch = false
	say("звуков из точек: %d из %d разных клеток" % [звуков, точки.size()])
	say("снова стал виден через %.1f с" % [виден_через])
	say("погоня не прервалась: %s (режим %s, держит до убежища %s)"
		% [str(бит), m.mode, str(m.hunt_until_safe)])
	if точки.size() < 4:
		warn("шум шёл всего из %d мест — по нему его и вычислят" % [точки.size()])
	if виден_через < 3.5:
		warn("вернулся уже через %.1f с — это не пять секунд" % [виден_через])
	if звуков < 12:
		warn("звуков всего %d за пять секунд — в стенах его не слышно" % [звуков])


## ─────────── ВИДНО ЛИ ТВАРЬ И КАК ИМЕННО ───────────
##
## «Плохо видно» и «хорошо видно» до сих пор были на глаз. Мерим честно: снимаем
## один и тот же коридор дважды — с тварью и без неё — и вычитаем кадры. Разница
## и есть ровно то, что она добавляет к пустоте: сколько пикселей она меняет,
## насколько сильно и где — по всему телу или только по кромке.
##
## Последнее и есть вопрос: «видно очертания и форму» означает, что разница
## собрана НА КРАЮ силуэта, а внутри его почти нет. Если разница ровная по всей
## туше — мы показываем не силуэт, а пятно.
func scene_silhouette() -> void:
	say("═══ ВИДНО ЛИ ТВАРЬ ═══")
	var m = w.monster
	var p = w.player_node
	m.drop_hold()
	m.form_hold = 0.0
	m.form_t = 0.0
	m.form_kind = m.FORM_NONE
	m.parked = true
	m.prowl = false
	m.mode = "chase"
	m.stun = 0.0
	for клеток in [1, 2, 3, 6, 9]:
		var где: Vector2i = _clear_spot(клеток)
		if где.x < 0:
			warn("на карте нет прямого коридора длиной %d клеток" % [клеток])
			continue
		m.global_position = w.cell_to_world(где)
		m.visible = true
		m._grow_out()
		# Смотрим точно на него: мерим видимость, а не удачу поворота головы.
		p.look_force(m.global_position + Vector3.UP * 1.2, 2.0, 40.0)
		for i in 30:
			await w.get_tree().process_frame
		var d: float = m.global_position.distance_to(p.global_position)
		m.visible = false
		await w.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var пусто: Image = w.get_viewport().get_texture().get_image()
		m.visible = true
		await w.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var есть: Image = w.get_viewport().get_texture().get_image()
		_diff(пусто, есть, клеток, d)
		await shot("силуэт_%02d" % [клеток])
	m.visible = true


## Разница двух кадров. Печатаем: сколько пикселей она задела, насколько ярче
## самый яркий из них и как разница распределена — по краю или по всей туше.
func _diff(a: Image, b: Image, клеток: int, метров: float) -> void:
	var ш: int = a.get_width()
	var в: int = a.get_height()
	# Шаг 2 по обеим сторонам: четверть пикселей — этого хватает на статистику,
	# а полный проход по двум миллионам точек в GDScript занимает минуты.
	var задето: int = 0
	var сумма: float = 0.0
	var верх: float = 0.0
	var eps: float = 0.012                # ниже этого глаз не различает
	var x0: int = ш
	var x1: int = 0
	var y0: int = в
	var y1: int = 0
	for y in range(0, в, 2):
		for x in range(0, ш, 2):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			var dl: float = absf(cb.get_luminance() - ca.get_luminance())
			if dl <= eps:
				continue
			задето += 1
			сумма += dl
			верх = maxf(верх, dl)
			x0 = mini(x0, x)
			x1 = maxi(x1, x)
			y0 = mini(y0, y)
			y1 = maxi(y1, y)
	if задето == 0:
		say("  %2d клеток (%.0f м): НЕ ВИДНО ВООБЩЕ — кадр с тварью и без неё одинаков"
			% [клеток, метров])
		warn("на %d клетках тварь неотличима от пустого коридора" % [клеток])
		return
	var всего: int = (ш / 2) * (в / 2)
	var доля: float = float(задето) / float(всего) * 100.0
	var средне: float = сумма / float(задето)
	# Сколько из задетого приходится на яркую кромку, а сколько на слабый фон:
	# «очертания» — это когда почти вся разница собрана в тонкой яркой части.
	var кромка: int = 0
	for y in range(0, в, 2):
		for x in range(0, ш, 2):
			var dl: float = absf(b.get_pixel(x, y).get_luminance()
				- a.get_pixel(x, y).get_luminance())
			if dl > верх * 0.5:
				кромка += 1
	say("  %2d клеток (%.0f м): занимает %.2f%% кадра, в среднем +%.3f, ярче всего +%.3f"
		% [клеток, метров, доля, средне, верх])
	say("      силуэт %d×%d px, на яркую кромку приходится %.0f%% задетого"
		% [x1 - x0, y1 - y0, float(кромка) / float(задето) * 100.0])
	if верх < 0.02:
		warn("на %d клетках самый яркий пиксель тела ярче стены всего на %.3f"
			% [клеток, верх])


## Клетка пола в N шагах ПО ПРЯМОЙ от игрока. Искать её кольцом по карте
## расстояний оказалось нельзя: в лабиринте почти нет пар клеток, между которыми
## есть и ровно N шагов пути, и прямая видимость, — и замер молча падал на всех
## дистанциях дальше трёх. Ставим игрока в самый длинный прямой коридор карты и
## отмеряем вдоль него: тогда мерится видимость, а не везение с планировкой.
func _clear_spot(клеток: int) -> Vector2i:
	if _line.is_empty():
		_find_line()
	if _line.is_empty():
		return Vector2i(-1, -1)
	var старт: Vector2i = _line[0]
	w.player_node.global_position = w.cell_to_world(старт, PlayerScript.STAND_Y)
	if клеток >= _line.size():
		return Vector2i(-1, -1)
	return _line[клеток]


var _line: Array = []              ## самый длинный прямой коридор карты


## Самый длинный прямой отрезок пола на карте: по нему и мерим дальность.
func _find_line() -> void:
	_line = []
	var лучшая: Array = []
	for r in w.maze.size.y:
		for c in w.maze.size.x:
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var ход: Array = []
				var cur := Vector2i(r, c)
				while not w.maze.is_wall(cur.x, cur.y):
					ход.append(cur)
					cur += d
				if ход.size() > лучшая.size():
					лучшая = ход
	_line = лучшая
	if not _line.is_empty():
		say("самый длинный прямой коридор: %d клеток (%.0f м)"
			% [_line.size() - 1, float(_line.size() - 1) * w.cell_size])


## ─────────── СКОЛЬКО ВЗМАХОВ НУЖНО И КТО УСПЕВАЕТ ───────────
##
## Играющий сказал про хват: «невероятно залипательно, я бы резал их хоть час,
## но вообще не страшно и не опасно — пара взмахов и готово». Значит мерить
## надо не «проходится ли», а СКОЛЬКО РАБОТЫ и кто с ней не справляется:
## быстрый обязан вырываться всегда, обычный — почти всегда, медленный — нет.
##
## Режет стенд тем же bot_slash, что и раньше: он строит настоящий взмах
## поперёк петли и прогоняет его через ту же проверку попадания. Подменять хват
## зачётом нельзя — тогда мерится не игра, а своя доброта к себе.
func scene_swings() -> void:
	say("═══ СКОЛЬКО ВЗМАХОВ НУЖНО И КТО УСПЕВАЕТ ═══")
	var темпы: Array = [
		{"имя": "быстрый  ", "пауза": 0.30, "мимо": 0.05},
		{"имя": "обычный  ", "пауза": 0.45, "мимо": 0.18},
		{"имя": "медленный", "пауза": 0.62, "мимо": 0.30},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260917
	for темп in темпы:
		var строки: Array = []
		var работа: Array = []
		for стадия in [0, 1, 2]:
			var ушёл: int = 0
			var взмахов: int = 0
			var попаданий: int = 0
			var всего: int = 6
			for попытка in всего:
				var итог: Array = await _one_grab(стадия, float(темп["пауза"]),
					float(темп["мимо"]), rng)
				ушёл += int(итог[0])
				взмахов += int(итог[1])
				попаданий += int(итог[2])
			строки.append("%d-й: %d из %d" % [стадия + 1, ушёл, всего])
			работа.append("%.0f взмахов / %.0f в цель"
				% [float(взмахов) / float(всего), float(попаданий) / float(всего)])
		say("%s взмах раз в %.2f с, мимо %.0f%% → %s"
			% [темп["имя"], темп["пауза"], темп["мимо"] * 100.0,
			"   ".join(строки)])
		say("            работы за хват: %s" % [" | ".join(работа)])


## Один хват целиком. Возвращает [вырвался, взмахов, попаданий].
func _one_grab(стадия: int, пауза: float, мимо: float,
		rng: RandomNumberGenerator) -> Array:
	var g = w.grab_ui
	# СЧЁТ СМЕРТИ — ЗА СКОБКИ. Каждый проигранный хват стенда шёл в настоящие
	# ошибки и поимки; на верхней ступени безумия одна поимка теперь смерть,
	# сцена перезагружалась, и прогон обрывался на медленном игроке без отчёта.
	w.errors = 0
	w.streak = 0
	w.mon_kills = 0
	var исход: Array = [0]
	var взял := func(): исход[0] = 1
	g.escaped.connect(взял, CONNECT_ONE_SHOT)
	g.begin("стенд", false, rng.randi(), стадия, 1.0)
	if w.grab3d != null and w.player_node != null:
		w.grab3d.build(w.player_node.head, g.need, rng.randi())
		w.grab3d.begin()
	var взмахов: int = 0
	var попаданий: int = 0
	var копим: float = 0.0
	while g.visible:
		await w.get_tree().physics_frame
		копим += 1.0 / 60.0
		if копим < пауза:
			continue
		копим = 0.0
		взмахов += 1
		# Промах — это взмах, который не довели до петли: время он съедает,
		# а щупальце нет.
		if rng.randf() < мимо:
			continue
		if g.bot_slash():
			попаданий += 1
	if g.escaped.is_connected(взял):
		g.escaped.disconnect(взял)
	await w.get_tree().create_timer(0.2).timeout
	if w.grab_ui.visible:
		w.grab_ui._end(false)
	return [исход[0], взмахов, попаданий]


## ─────────── ФИНАЛЬНАЯ ДВЕРЬ: ЕСТЬ ЛИ ЕЙ НА ЧЁМ РИСОВАТЬСЯ ───────────
##
## Мольберта у выхода нет, а кадр полотна натягивается на лист в мире: без
## отдельного листа игрок дошёл бы до выхода и увидел пустой коридор.
func scene_final_door() -> void:
	say("═══ ФИНАЛЬНАЯ ДВЕРЬ ═══")
	var p = w.player_node
	p.invuln = 9999.0
	w.done = w.n_canv
	p.global_position = w.cell_to_world(w.exit_cell, PlayerScript.STAND_Y)
	await w.get_tree().process_frame
	w._open_finale()
	await w.get_tree().create_timer(1.0).timeout
	var лист: Node3D = w.board_face
	var камера: Camera3D = w.get_viewport().get_camera_3d()
	if лист == null or камера == null:
		warn("листа двери нет — рисовать не на чем")
		return
	var экран: Vector2 = камера.unproject_position(лист.global_position)
	var кадр: Vector2 = w.get_viewport().get_visible_rect().size
	say("лист двери: видим=%s, в %.2f м, на экране %.0f×%.0f из %.0f×%.0f"
		% [str(лист.visible), лист.global_position.distance_to(камера.global_position),
		экран.x, экран.y, кадр.x, кадр.y])
	say("полотно двери открыто: %s, точек %d" % [str(w.board.visible), w.board.n])
	if not лист.visible:
		warn("лист двери невидим")
	if камера.is_position_behind(лист.global_position) \
			or экран.x < 0.0 or экран.y < 0.0 \
			or экран.x > кадр.x or экран.y > кадр.y:
		warn("лист двери вне кадра: %.0f×%.0f" % [экран.x, экран.y])
	await _check_aim()
	await shot("дверь_на_стене")


## ─────────── СЛЫШНО ЛИ, С КАКОЙ СТОРОНЫ ОН ИДЁТ, ПОКА РИСУЕШЬ ───────────
##
## Панораму движок считает сам, из скрипта её не прочесть. Зато можно померить
## всё, от чего она зависит, и то, чего до сих пор не было вовсе:
##  — идёт ли звук ИЗ ТОЧКИ, где тварь, а не из головы игрока;
##  — совпадает ли сторона звука со стороной, с которой он реально подходит;
##  — меняется ли эта сторона (стоячий источник — это «звук ради звука»);
##  — держит ли он обещанный запас и не хватает ли рисующего.
func scene_draw_sound() -> void:
	say("═══ СЛЫШНО ЛИ ЕГО, ПОКА РИСУЕШЬ ═══")
	var m = w.monster
	var p = w.player_node
	p.global_position = w.cell_to_world(w.canv_cells[w.done], PlayerScript.STAND_Y)
	# КРУЖИТЬ ОН МОЖЕТ ТОЛЬКО СНАРУЖИ. В первой фазе он в камне и в полутора
	# сотнях метров — там и слышать нечего по замыслу. Мерим ту фазу, где он
	# уже вышел: ставим его в шести клетках и снаружи, как в погоне.
	w.phase = 2
	m.drop_hold()
	m.form_hold = 0.0
	m.form_t = 0.0
	m.form_kind = m.FORM_NONE
	m.global_position = w.cell_to_world(w.world_to_cell(p.global_position)
		+ Vector2i(0, 6))
	m.visible = true
	m.mode = "chase"
	m._grow_out()
	await w.get_tree().create_timer(0.4).timeout
	w._open_board()
	await w.get_tree().create_timer(1.2).timeout
	say("полотно открыто: %s, монстр кружит: %s" % [str(w.board.visible), str(m.prowl)])
	var cam: Camera3D = w.get_viewport().get_camera_3d()
	say("слушатель: %s" % ["камера игрока" if cam != null and p.is_ancestor_of(cam)
		else str(cam)])
	# И ЗАОДНО — ВИДНО ЛИ САМ ХОЛСТ. Полотно теперь висит в мире листом на
	# мольберте, и первый же снимок вышел чёрным: проверяем прямо, где лист,
	# куда смотрит камера и попадает ли лист в кадр.
	var лист: Node3D = w.board_face
	if лист == null:
		warn("листа полотна в мире нет вовсе")
	else:
		var камера: Camera3D = w.get_viewport().get_camera_3d()
		var до: float = лист.global_position.distance_to(камера.global_position)
		var к: Vector3 = (лист.global_position - камера.global_position).normalized()
		var угол: float = rad_to_deg(acos(clampf(к.dot(-камера.global_transform.basis.z),
			-1.0, 1.0)))
		var экран: Vector2 = камера.unproject_position(лист.global_position)
		say("лист: видим=%s, в %.2f м, отклонение взгляда %.0f°, на экране %.0f×%.0f"
			% [str(лист.visible), до, угол, экран.x, экран.y])
		if not лист.visible:
			warn("лист полотна невидим — рисовать нечем")
		if угол > 25.0:
			warn("камера смотрит мимо холста на %.0f°" % [угол])
			say("  куда велено смотреть: %s, лист в %s, игрок в %s, рысканье %.0f°"
				% [str(w.board_look.round()), str(лист.global_position.round()),
				str(p.global_position.round()), rad_to_deg(p.yaw)])
			# Крутим взгляд руками и смотрим, двигается ли он вообще.
			for i in 60:
				w._update_board3d(1.0 / 60.0)
			var к2: Vector3 = (лист.global_position
				- камера.global_position).normalized()
			say("  после 60 вызовов вручную: отклонение %.0f°, рысканье %.0f°, "
				% [rad_to_deg(acos(clampf(к2.dot(-камера.global_transform.basis.z),
				-1.0, 1.0))), rad_to_deg(p.yaw)]
				+ "голову вели %d раз" % [p.look_calls])
	await shot("холст_в_мире")
	w.sfx.heard.clear()
	w.sfx.lost3d = 0
	w.sfx.watch = true
	var steps: int = 0
	var из_головы: int = 0
	var расхождение: float = 0.0
	var стороны: Dictionary = {}
	var первые: Array = []
	var шум: int = 0
	var ближе: float = 999.0
	var дальше: float = 0.0
	var db_max: float = -99.0
	var t: float = 0.0
	var путь: float = 0.0
	var прыжок: float = 0.0
	var было: Vector3 = m.global_position
	var трасса: Array = []
	var такт: float = 0.0
	var толчков: int = 0
	var толчок: float = 0.0
	var было_jolt: float = 0.0
	while t < 34.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		var шаг: float = было.distance_to(m.global_position)
		путь += шаг
		прыжок = maxf(прыжок, шаг)
		было = m.global_position
		var d: float = m.global_position.distance_to(p.global_position)
		ближе = minf(ближе, d)
		дальше = maxf(дальше, d)
		# Толчок живёт доли секунды: ловим по подъёму, а не по значению.
		if w.board.jolt > было_jolt + 0.01:
			толчков += 1
			толчок = maxf(толчок, w.board.jolt)
		было_jolt = w.board.jolt
		такт += 1.0 / 60.0
		if такт >= 2.0:
			такт = 0.0
			var цель: Vector2i = m.prowl_goal
			var дц: float = 999.0
			var шагов_до: int = -1
			if цель.x >= 0:
				дц = w.cell_to_world(цель).distance_to(p.global_position)
				var карта: Dictionary = w.maze.distances(
					w.world_to_cell(p.global_position))
				шагов_до = int(карта.get(цель, -1))
			трасса.append("%.0f (цель %.0f м, %d клеток, путь %d)"
				% [d, дц, шагов_до, m.path.size()])
		for e in w.sfx.heard:
			var nm: String = String(e["имя"])
			if nm != "step_wet" and nm != "scrape" and nm != "skitter" \
					and nm != "шаг":
				continue
			if not bool(e["из точки"]):
				из_головы += 1
				continue
			var сторона: String = _side_of(e["где"])
			if nm == "шаг":
				# Поступь считаем по отметке самого шага, а не по step_wet:
				# тот же звук идёт от опоры руки о пол, а руки у него в
				# стороне от туши — первый замер на этом и обманулся, приняв
				# опору за «звук отстаёт от тела на 4.6 м».
				steps += 1
				db_max = maxf(db_max, float(e["дб"]))
				if первые.size() < 8:
					первые.append(сторона)
				расхождение = maxf(расхождение,
					Vector3(e["где"]).distance_to(m.global_position))
			else:
				шум += 1
			стороны[сторона] = int(стороны.get(сторона, 0)) + 1
		w.sfx.heard.clear()
	w.sfx.watch = false
	say("шагов слышно %d за 34 с (%.1f в секунду), громче всего %.0f дБ"
		% [steps, steps / 34.0, db_max])
	say("прошёл %.0f м, то есть %.2f м/с; самый большой скачок за кадр %.2f м"
		% [путь, путь / 34.0, прыжок])
	say("расстояние раз в 2 с: %s м" % [", ".join(трасса)])
	say("прочих звуков из точки (скрежет, опора руки): %d, «из головы»: %d"
		% [шум, из_головы])
	say("не нашли места в очереди: %d звуков" % [w.sfx.lost3d])
	say("рука дрожала от его шагов: толчков %d, сильнейший %.2f" % [толчков, толчок])
	if w.sfx.lost3d > 20:
		warn("очередь звуков переполнена: %d потеряно" % [w.sfx.lost3d])
	say("звук против тела: расхождение до %.2f м" % [расхождение])
	var список: Array = []
	for k in стороны:
		список.append("%s ×%d" % [k, int(стороны[k])])
	say("стороны: %s" % [", ".join(список)])
	say("первые шаги: %s" % [", ".join(первые)])
	say("расстояние: ближе всего %.1f м, дальше всего %.1f м" % [ближе, дальше])
	var порог: float = m.PROWL_KEEP * m.cell_size * 0.8
	if steps < 8:
		warn("шагов почти нет — рисующий его не слышит")
	if steps > 55:
		warn("шагов слишком много: это дробь, а не поступь")
	if из_головы > 0:
		warn("часть звуков идёт не из точки — сторона не читается")
	if расхождение > 0.6:
		warn("звук отстаёт от тела на %.2f м" % [расхождение])
	if стороны.size() < 2:
		warn("сторона не меняется — источник стоит, это звук ради звука")
	if ближе < порог:
		warn("подошёл на %.1f м при запасе %.1f м" % [ближе, порог])
	if дальше - ближе < 1.5:
		warn("он не двигается: разброс расстояния %.1f м" % [дальше - ближе])
	if w.grab_ui.visible:
		warn("схватил игрока за полотном — этого быть не должно")
	await shot("рисую_слышно")
	w.board.visible = false
	w._close_board()


## Сторона относительно взгляда: спереди/сзади × слева/справа.
func _side_of(from: Vector3) -> String:
	var cam: Camera3D = w.get_viewport().get_camera_3d()
	if cam == null:
		return "нет камеры"
	var d: Vector3 = from - cam.global_position
	d.y = 0.0
	if d.length() < 0.2:
		return "в голове"
	d = d.normalized()
	var b: Basis = cam.global_transform.basis
	return "%s-%s" % ["спереди" if d.dot(-b.z) > 0.0 else "сзади",
		"справа" if d.dot(b.x) > 0.0 else "слева"]


func scene_chase_sound(ph: int) -> void:
	say("═══ ЗВУК ПОГОНИ, фаза %d ═══" % ph)
	var m = w.monster
	var p = w.player_node
	w.phase = ph
	if ph >= 3:
		m.omniscient = true
		m.last_phase = true
	m.drop_hold()
	m.form_hold = 0.0
	m.form_t = 0.0
	m.form_kind = m.FORM_NONE
	m.global_position = p.global_position + Vector3(0, 0, w.cell_size * 9.0)
	m.visible = true
	m.mode = "chase"
	m._grow_out()
	var box: Dictionary = {}
	var span: Dictionary = {}
	w.sfx.heard.clear()
	w.sfx.watch = true
	var t: float = 0.0
	while t < 45.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		# Держим погоню насильно: мерим звук погони, а не то, как она кончается.
		m.mode = "chase"
		m.chase_t = 999.0
		var d: float = m.global_position.distance_to(p.global_position) / w.cell_size
		var b: String = _bucket(d)
		span[b] = float(span.get(b, 0.0)) + 1.0 / 60.0
		for e in w.sfx.heard:
			var nm: String = String(e["имя"])
			if not MON_SOUNDS.has(nm):
				continue
			var key: String = b + "|" + nm
			var cur: Array = box.get(key, [0, -99.0])
			box[key] = [int(cur[0]) + 1, maxf(float(cur[1]), float(e["дб"]))]
		w.sfx.heard.clear()
	w.sfx.watch = false
	for b in ["10+", "6-10", "4-6", "2-4", "1-2", "0-1"]:
		if not span.has(b):
			continue
		var parts: Array = []
		for k in box.keys():
			if String(k).begins_with(b + "|"):
				var v: Array = box[k]
				parts.append("%s ×%d до %.1f дБ" % [
					String(k).split("|")[1], int(v[0]), float(v[1])])
		say("  %s клеток (%.0f с): %s" % [
			b, float(span[b]), ", ".join(parts) if not parts.is_empty() else "ТИШИНА"])


func scene_chase(seconds: float) -> void:
	var m = w.monster
	var p = w.player_node
	# Погоню смотрим на БАЗОВОМ теле: фигура — отдельная сцена со своими
	# приёмами, и мешать их в одном замере значит мерить непонятно что.
	m.drop_hold()
	m.form_hold = 0.0
	m.form_t = 0.0
	m.form_kind = m.FORM_NONE
	m.global_position = p.global_position + Vector3(0, 0, w.cell_size * 3.0)
	m.visible = true
	m.mode = "chase"
	m.chase_t = seconds + 5.0
	# НЫРОК ОТКЛЮЧЁН НА ВРЕМЯ ЗАМЕРА. Сцена мерит, насколько она сближается, а
	# нырок уводит её в камень — и замер начинает мерить нырок, а не сближение.
	m.dive_t = 9999.0
	m._grow_out()
	var t: float = 0.0
	var seen_frames: int = 0
	var closest: float = 999.0
	while t < seconds:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		m.visible = true
		m.mode = "chase"
		var d: float = m.global_position.distance_to(p.global_position)
		closest = minf(closest, d)
		if d < 14.0:
			seen_frames += 1
		if int(t * 60.0) % 40 == 0:
			check_now("погоня")
	say("погоня %.0f с: подошёл на %.1f м, был в поле зрения %d%% времени" % [
		seconds, closest, int(100.0 * float(seen_frames) / maxf(1.0, t * 60.0))])
	if closest > w.cell_size * 2.5:
		warn("за %.0f с погони он так и не подошёл ближе %.1f м" % [seconds, closest])
	await shot("chase")


## Показать монстра в обеих версиях и сравнить, чем они отличаются на числах.
## Поставить обоих на честное место: игрок на полу, монстр рядом и НЕ в камне.
## Без этого стенд сам создаёт положения, которых в игре не бывает, и потом на
## них же ругается: «монстр виден, находясь в камне» — это была моя подстава.
func stage_clean() -> void:
	var p = w.player_node
	p.global_position = w.cell_to_world(w.start_cell, PlayerScript.STAND_Y)
	var m = w.monster
	var here: Vector2i = w.start_cell
	var spot: Vector2i = here
	for d in [Vector2i(0, 2), Vector2i(2, 0), Vector2i(0, -2), Vector2i(-2, 0)]:
		if not w.maze.is_wall(here.x + d.x, here.y + d.y):
			spot = here + d
			break
	m.global_position = w.cell_to_world(spot)
	m.mode = "chase"
	m.chase_t = 60.0
	m.path.clear()
	m.visible = true
	m._grow_out()


## ВРЕМЕННАЯ СЦЕНА. Жалоба на гуманоида — про ПОХОДКУ: шатается, меняет размер,
## не касается пола. Стоп-кадром это не поймать, нужен ряд кадров и числа.
## ВРЕМЕННАЯ СЦЕНА. Повторяет его сеанс: он ходил по карте, искал засаду и НЕ
## рисовал полотна. Вопрос один — наступает ли вторая фаза у того, кто не сдаёт
## полотна, и через сколько.
## ВРЕМЕННАЯ ПРОВЕРКА. Клавиша создателя — это код, который никто не вызывает
## в прогонах, и потому он ломается молча. Жмём её по-настоящему.
func scene_key_form() -> void:
	say("═══ КЛАВИША H ═══")
	say("инструменты создателя: %s" % str(Settings.creator_tools()))
	var before: int = w.forms_left
	# НАСТОЯЩЕЕ СОБЫТИЕ, а не Input.action_press: тот лишь ставит состояние
	# действия, а обработчик игры ждёт СОБЫТИЕ и про состояние не знает.
	# Первая проверка из-за этого сказала «клавиша не сработала» — врала она,
	# а не игра. Привязка идёт по ФИЗИЧЕСКОЙ клавише, её и шлём.
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_H
	ev.pressed = true
	Input.parse_input_event(ev)
	await w.get_tree().process_frame
	for i in 30:
		await w.get_tree().process_frame
	# МУЗЫКА. Слышать её я не могу, а проверить — могу: слой напряжения обязан
	# расти с близостью и опадать без неё.
	var quiet_db: float = 0.0
	var loud_db: float = 0.0
	for i2 in 90:
		w.sfx.music_near(0.0, 1.0 / 60.0)
		await w.get_tree().process_frame
	quiet_db = w.sfx._mus_tense.volume_db
	for i3 in 90:
		w.sfx.music_near(1.0, 1.0 / 60.0)
		await w.get_tree().process_frame
	loud_db = w.sfx._mus_tense.volume_db
	say("музыка: вдали %.0f дБ, вплотную %.0f дБ, тон %.2f, спокойный слой %.0f дБ" % [
		quiet_db, loud_db, w.sfx._mus_tense.pitch_scale, w.sfx._mus_calm.volume_db])
	if loud_db <= quiet_db + 5.0:
		warn("слой напряжения не растёт — музыка не следит за монстром")
	# ПЕРЕХВАТ УРОВНЕЙ. Он сказал: удары работают, музыка и бит — нет. Причина
	# в том, что мир задаёт эти уровни каждый кадр, и кнопка лаборатории
	# затиралась. Проверяем ровно это: задать насильно, дать миру поспорить и
	# посмотреть, кто победил.
	w.sfx.music_force(1.0)
	w.sfx.beat_force(1.0)
	var m0: float = w.sfx._mus_tense.volume_db
	var b0: float = w.sfx._beat_player.volume_db
	for i4 in 40:
		w.sfx.music_near(0.0, 1.0 / 60.0)
		w.sfx.beat_level(false, 0.0, 1.0 / 60.0)
	var m1: float = w.sfx._mus_tense.volume_db
	var b1: float = w.sfx._beat_player.volume_db
	say("перехват: музыка %.0f -> %.0f дБ, бит %.0f -> %.0f дБ" % [m0, m1, b0, b1])
	# А ИГРАЮТ ЛИ ОНИ ВООБЩЕ. Громкость можно двигать сколько угодно у
	# проигрывателя, который молчит: на слух это ровно «не работает».
	say("проигрыватели: спокойный %s, напряжение %s, бит %s" % [
		str(w.sfx._mus_calm.playing), str(w.sfx._mus_tense.playing),
		str(w.sfx._beat_player.playing)])
	# ГЛАВНАЯ ПРОВЕРКА ЗДЕСЬ. Громкость можно двигать сколько угодно у
	# проигрывателя, который молчит, — и всё выглядит исправным. Один раз я
	# так и отчитался: «музыка вдали −60, вплотную −3», а музыки не было
	# вовсе. Играет или нет — вот что надо спрашивать первым.
	if not (w.sfx._mus_calm.playing and w.sfx._mus_tense.playing
			and w.sfx._beat_player.playing):
		warn("МУЗЫКА МОЛЧИТ: проигрыватель не запустился, громкость тут ни при чём")
	say("потоки: спокойный %s, напряжение %s, бит %s" % [
		str(w.sfx._mus_calm.stream != null), str(w.sfx._mus_tense.stream != null),
		str(w.sfx._beat_player.stream != null)])
	say("длины потоков: спокойный %.1f с, напряжение %.1f с, бит %.1f с" % [
		w.sfx._mus_calm.stream.get_length(), w.sfx._mus_tense.stream.get_length(),
		w.sfx._beat_player.stream.get_length()])
	say("петли: спокойный режим %d, конец %d; бит режим %d, конец %d" % [
		w.sfx._mus_calm.stream.loop_mode, w.sfx._mus_calm.stream.loop_end,
		w.sfx._beat_player.stream.loop_mode, w.sfx._beat_player.stream.loop_end])
	w.sfx._mus_calm.play()
	await w.get_tree().process_frame
	say("после повторного play(): спокойный %s" % str(w.sfx._mus_calm.playing))
	say("шины: спокойный «%s», бит «%s»; шина Музыка есть: %s" % [
		w.sfx._mus_calm.bus, w.sfx._beat_player.bus,
		str(AudioServer.get_bus_index("Музыка") >= 0)])
	if not is_equal_approx(m0, m1) or not is_equal_approx(b0, b1):
		warn("мир пересилил лабораторию — кнопки музыки и бита снова мертвы")
	w.sfx.music_force(-1.0)
	w.sfx.beat_force(-1.0)
	# Спад НАМЕРЕННО медленный (0.45 в секунду): «он ушёл» не должно звучать
	# как выключенный приёмник. Значит и ждать надо по-настоящему — сорока
	# кадров хватало только до −20 дБ, и проверка ругалась на исправный код.
	for i5 in 300:
		w.sfx.music_near(0.0, 1.0 / 60.0)
		w.sfx.beat_level(false, 0.0, 1.0 / 60.0)
	say("после возврата игре: музыка %.0f дБ, бит %.0f дБ" % [
		w.sfx._mus_tense.volume_db, w.sfx._beat_player.volume_db])
	if w.sfx._mus_tense.volume_db > -50.0:
		warn("управление не вернулось игре — уровень так и держится насильно")
	for kind in ["лицо", "угол", "погоня"]:
		w.sfx.sting(kind, 0.0)
		_wave_report(kind, w.sfx._stings[kind])
		await w.get_tree().create_timer(0.4).timeout
	_wave_report("бит погони", w.sfx._beat_player.stream)
	w.sfx.beat_level(true, 1.0, 1.0)
	say("бит на полной близости: %.0f дБ, темп ×%.2f" % [
		w.sfx._beat_player.volume_db, w.sfx._beat_player.pitch_scale])
	say("бюджет формы: было %d, стало %d; форма=%d, держится %.1f с" % [
		before, w.forms_left, w.monster.form_kind, w.monster.form_hold])
	if w.forms_left == before:
		warn("клавиша НЕ СРАБОТАЛА и в редакторе — беда в коде, а не в сборке")


## СКОРОСТЬ ПОГОНИ. Отвечает на единственный вопрос, который меняла правка:
## с какой скоростью она едет за тобой, когда ты бежишь.
##
## Через лабиринт это мерить НЕЛЬЗЯ, и я на этом обжёгся трижды: бот упирается
## в стены, застревает, теряет рывок — и замер показывает поведение стенда, а
## не твари. Один прогон даже дал обратное правде. Поэтому здесь нет ни бегства,
## ни навигации: берём разгон подстройки и считаем скорость по формуле самой
## игры, той же, что двигает её в кадре.
func scene_flee() -> void:
	say("═══ СКОРОСТЬ ПОГОНИ ПРОТИВ РЫВКА ═══")
	var p = w.player_node
	var m = w.monster
	var walk: float = p.speed
	var rush: float = p.speed * p.sprint_mul
	say("игрок: шаг %.2f м/с, рывок %.2f м/с" % [walk, rush])
	for matching in [false, true]:
		w.rush_match = matching
		m.mode = "chase"
		m._rush_k = 1.0
		# Гоним подстройку два разгона подряд, чтобы поймать её установившееся
		# значение, а не середину нарастания.
		var t: float = 0.0
		while t < 2.0:
			await w.get_tree().physics_frame
			t += 1.0 / 60.0
			p.sprint_left = 5.0          # он бежит
			m.mode = "chase"
			m.player_rush = (p.sprint_mul if w.rush_match else 1.0)
			m._rush_k = move_toward(m._rush_k,
				m.player_rush * 0.92 if m.player_rush > 1.0 else 1.0,
				(1.0 / 60.0) * 1.8)
		var cap: float = (m.player_speed * m.player_rush * 1.12
			if m.player_rush > 1.0 else 1e9)
		var spd: float = minf(m._speed(m.K_CHASE, 0) * m._rush_k, cap)
		var mx: float = minf(m._speed(m.K_CHASE, m.ANGER_MAX) * m._rush_k, cap)
		say("%s: догоняет на %.2f м/с (в ярости %.2f), игрок %s на %.2f м/с" % [
			"ПОДСТРАИВАЕТСЯ" if matching else "старое",
			spd, mx, "УХОДИТ" if rush > mx else "НЕ УХОДИТ", absf(rush - mx)])
		if not matching and mx >= rush:
			warn("старое поведение и так догоняло — правка не нужна была")
		if matching and mx < rush:
			warn("ДАЖЕ В ЯРОСТИ НЕ ДОГОНЯЕТ — правка не сработала")
	w.rush_match = true
	p.sprint_left = 0.0


## РОСТ ИГРОКА. Мерит то, что в игре видно каждым кадром и чего никто ни разу
## не померил: на какой высоте находится глаз. Друг сказал «персонаж в первой
## комнате огромен», и это оказалось не ощущением, а числом.
func scene_height() -> void:
	say("═══ РОСТ ИГРОКА ═══")
	var p = w.player_node
	var cam: Camera3D = p.get_node("Head/Camera3D")
	for i in 20:
		await w.get_tree().process_frame
	var eye: float = cam.global_position.y
	var body: float = p.global_position.y
	say("глаз на %.2f м, тело на %.2f, голова местно на %.2f" % [
		eye, body, cam.global_position.y - body])
	say("задумано: рост %.2f, глаз %.2f (Player.STAND и Player.EYE_Y)" % [
		PlayerScript.STAND, PlayerScript.EYE_Y])
	if absf(eye - PlayerScript.EYE_Y) > 0.12:
		warn("ГЛАЗ НЕ ТАМ: %.2f вместо %.2f — игрок выше себя на %.2f м" % [
			eye, PlayerScript.EYE_Y, eye - PlayerScript.EYE_Y])


## ЛИНИЯ И ЗВУК СОЕДИНЕНИЯ. Главное действие игры: проверяем, что на КАЖДУЮ
## точку уходит сигнал, что линия при этом РАСТЁТ (а не появляется целиком) и
## что звук берётся из записи, а не из запасного синтеза.
func scene_line() -> void:
	say("═══ СОЕДИНЕНИЕ ТОЧЕК ═══")
	var b = w.board
	if b == null:
		warn("полотна нет — проверка ничего не значит")
		return
	var got: Array = [0]
	b.linked.connect(func(i: int, total: int): got[0] += 1)
	# Полотно открывается само, когда подойдёшь. Доходим до ближайшего.
	if not b.visible:
		await goto_cell(_canv_now(), 45.0)
	var tries: int = 0
	while not b.visible and tries < 240:
		await w.get_tree().process_frame
		tries += 1
	if not b.visible:
		warn("полотно не открылось")
		return
	var total: int = int(b.n)
	var grew: int = 0
	var seen_mid: int = 0
	while b.visible and int(b.next_idx) < total:
		var before: int = int(b.next_idx)
		b._click(b._dot_pos(b.dots[_dot_of(b, before)]))
		# Сразу после попадания рост обязан быть НЕ ЕДИНИЦЕЙ, иначе линия
		# появляется рывком — ровно то, что чинили.
		if float(b.grow) < 1.0:
			grew += 1
		for i in 5:
			await w.get_tree().process_frame
		if float(b.grow) > 0.05 and float(b.grow) < 1.0:
			seen_mid += 1
		for i in 10:
			await w.get_tree().process_frame
	say("точек %d, сигналов %d, из них с ростом %d, застали на середине %d" % [
		total, got[0], grew, seen_mid])
	if got[0] < total:
		warn("сигналов меньше, чем точек: %d из %d" % [got[0], total])
	if grew < total - 1:
		warn("линия появлялась рывком на %d точках" % (total - 1 - grew))


## Найти в массиве точку с нужным номером: порядок в dots не совпадает с idx.
func _dot_of(b, idx: int) -> int:
	for i in b.dots.size():
		if int(b.dots[i]["idx"]) == idx:
			return i
	return 0


## ПЕРВЫЕ КАДРЫ КОРИДОРА. Что человек видит сразу после провала — и, главное,
## как выглядят рука с палочкой, которые потом в кадре всё время.
func scene_start_shots() -> void:
	say("═══ ПЕРВЫЕ КАДРЫ КОРИДОРА ═══")
	var p = w.player_node
	p.invuln = 9999.0
	# КРУГОМ. Стол с палочкой стоит в 0.7 м от старта — вопрос только в том,
	# видно ли его. Снимаем четыре стороны, а не одну.
	for pair in [[0.0, "с00"], [90.0, "с90"], [180.0, "с180"], [270.0, "с270"]]:
		p.yaw = deg_to_rad(float(pair[0]))
		p.rotation.y = p.yaw
		p.pitch = deg_to_rad(-14.0)
		for i in 12:
			await w.get_tree().process_frame
		await shot(str(pair[1]))
	say("снято четыре стороны")


## КАК ОЩУЩАЕТСЯ ПОДЪЁМ. Мерит не картинку, а движение: высоту каждый кадр.
## Подъём рывками обязан давать РАЗНУЮ скорость и хотя бы раз — отрицательную
## (сполз). Ровная скорость — это и есть то «плавное вознесение», от которого
## уходим, и по числам оно видно сразу.
func scene_climb_feel() -> void:
	say("═══ ПОДЪЁМ В ПРОЛОМ ═══")
	if w.climb_cell.x < 0:
		warn("пролома с насыпью нет")
		return
	# МЕРИМ КРИВУЮ, А НЕ РАЗНОСТИ МЕЖДУ КАДРАМИ. Скорость «высота делить на
	# дельту» в headless показывала до 190 м/с на подъёме в четыре метра: это
	# ловились затянувшиеся кадры, а не движение. Кривая же задана точно, и по
	# ней видно ровно то, что нужно: есть ли рывки и сползания.
	var prev: float = 0.0
	var bursts: int = 0
	var slips: int = 0
	var holds: int = 0
	var steps: int = 120
	for n in range(1, steps + 1):
		var k: float = float(n) / float(steps)
		var h: float = w._heave(k)
		var v: float = (h - prev) * float(steps)
		prev = h
		if v > 1.4:
			bursts += 1
		elif v < -0.02:
			slips += 1
		elif absf(v) < 0.25:
			holds += 1
	say("кривая подъёма: разгонов %d, сползаний %d, зависаний %d из %d шагов" % [
		bursts, slips, holds, steps])
	var p = w.player_node
	p.invuln = 9999.0
	p.global_position = w.climb_a
	await w.get_tree().process_frame
	var y0: float = p.global_position.y
	w._start_climb_up()
	var t: float = 0.0
	while t < w.CLIMB_T - 0.05:
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
	say("в игре поднялся на %.2f м за %.1f с" % [p.global_position.y - y0, w.CLIMB_T])
	# УПРАВЛЕНИЕ ОБЯЗАНО ВЕРНУТЬСЯ. Сцена забирает его на всё время подъёма, и
	# если забыть отдать — игрок останется стоять столбом до конца забега, а
	# выглядеть это будет как «игра зависла», а не как ошибка в одной строке.
	# ЗАВЕРШЕНИЕ — ЭТО СОСТОЯНИЕ 4, А НЕ НОЛЬ. Четвёрка значит «отыграно
	# навсегда»: насыпь ушла под землю и удалена, второй раз наверх не попасть.
	# Я ждал возврата в ноль и получил ложную тревогу на исправной сцене.
	var waited: float = 0.0
	while w.climb_state != 4 and waited < 16.0:
		await w.get_tree().process_frame
		waited += w.get_process_delta_time()
	say("сцена отыграна за %.1f с, состояние %d, управление вернули: %s, насыпь убрана: %s" % [
		waited, w.climb_state, str(p.is_physics_processing()), str(w.climb == null)])
	if not p.is_physics_processing():
		warn("УПРАВЛЕНИЕ НЕ ВЕРНУЛИ после сцены подъёма")
	if w.climb_state != 4:
		warn("сцена подъёма не завершилась за 16 с: состояние %d" % w.climb_state)
	if bursts == 0 or slips == 0:
		warn("подъём снова ровный: разгонов %d, сползаний %d" % [bursts, slips])


## ТЕМП ПОЯВЛЕНИЙ. Меряет то, что чувствует игрок: сколько проходит между
## выходами твари из камня за настоящий проход. Раньше срок шёл сам по себе и
## давал ровный ритм; теперь копится давление, и промежутки обязаны РАЗЪЕХАТЬСЯ —
## короткие там, где игрок рисовал, длинные там, где он шёл.
## ХРОНОМЕТРАЖ СРЕЗА. Сколько игра займёт у ЧЕЛОВЕКА, а не у стенда.
##
## По времени бота судить нельзя: он знает, где полотна, и идёт к ним по прямой
## — 160 секунд там, где человек тратит сорок минут. Считать надо ДОРОГУ:
## сумму путей старт → полотна → выход в клетках, и переводить её в минуты по
## скорости шага. Плюс время на сами полотна и на осмотр.
## ОПИСЬ. Что физически есть на карте: полотна, убежища, гнёзда, столы,
## украшения, проломы, обвал. Нужна затем, что «сколько влезло в срез» — это
## вопрос о ФАКТАХ, а не о впечатлении, и отвечать на него надо счётом.
func scene_inventory() -> void:
	say("═══ ОПИСЬ КАРТЫ ═══")
	var nests: int = 0
	var decor: int = 0
	for c in w.get_children():
		if c is MeshInstance3D and c.has_meta("nest"):
			nests += 1
	say("карта %s, полотен %d, залов %d" % [
		str(w.maze.size), w.n_canv, w.room_cells.size()])
	say("убежищ %d, столов %d, гнёзд %d, проломов в потолке %d" % [
		w.safe_cells.size(), w.tables.size(), w.nests.size(), w.holes.size()])
	say("обвал с подъёмом наверх: %s" % str(w.climb_cell.x >= 0))
	say("фазы наступают: 1-я на %d полотне, 2-я на %d, 3-я на %d" % [
		w.ph1_canv, w.ph2_canv, w.ph3_canv])
	say("поимок до конца %d, форм фигуры %d" % [w.DEATH_LIMIT, w.FORM_TIMES])


func scene_timing() -> void:
	say("═══ СКОЛЬКО ИДЁТ ИГРА ═══")
	var cells: int = 0
	var from: Vector2i = w.start_cell
	for c in w.canv_cells:
		var pth: Array = w._path(from, c)
		cells += maxi(0, pth.size() - 1)
		from = c
	var to_exit: Array = w._path(from, w.exit_cell)
	cells += maxi(0, to_exit.size() - 1)
	var metres: float = float(cells) * w.cell_size
	# Человек не идёт по кратчайшему пути: он ищет. Коэффициент 2.6 взят из
	# того, что в полной игре кратчайший путь даёт ~15 минут, а на деле
	# проход без нити занимает сорок.
	var blind: float = 2.6
	var walk: float = metres * blind / w.player_node.speed
	# Полотно: у человека уходит около сорока секунд на каждое.
	var draw: float = float(w.n_canv) * 40.0
	# Пролог и сцена подъёма.
	var scenes: float = 90.0 + 30.0
	say("полотен %d, карта %s, дорога %d клеток = %.0f м" % [
		w.n_canv, str(w.maze.size), cells, metres])
	say("ходьба ~%.0f мин, полотна ~%.0f мин, сцены ~%.0f мин" % [
		walk / 60.0, draw / 60.0, scenes / 60.0])
	say("ИТОГО ~%.0f минут без нити (с нитью примерно втрое меньше ходьбы)" % [
		(walk + draw + scenes) / 60.0])


func scene_tempo() -> void:
	say("═══ ПРОМЕЖУТКИ МЕЖДУ ПОЯВЛЕНИЯМИ ═══")
	tempo_gaps.clear()
	tempo_last = 0.0
	# СНАЧАЛА ПОЛОТНО, ПОТОМ ПРОХОД. Наоборот не работает: проход сдаёт все
	# полотна, и открывать после него уже нечего — проверка молча пропускалась.
	await _tempo_at_canvas()
	tempo_watch = true
	await scene_walk_all()
	tempo_watch = false
	if tempo_gaps.size() < 2:
		say("появлений за сам проход меньше двух — промежутки считать не по чему")
		return
	var sum: float = 0.0
	var mn: float = 1e9
	var mx: float = 0.0
	for g in tempo_gaps:
		sum += float(g)
		mn = minf(mn, float(g))
		mx = maxf(mx, float(g))
	var avg: float = sum / float(tempo_gaps.size())
	var dev: float = 0.0
	for g in tempo_gaps:
		dev += pow(float(g) - avg, 2.0)
	dev = sqrt(dev / float(tempo_gaps.size()))
	var line: String = ""
	for g in tempo_gaps:
		line += "%.0f " % float(g)
	say("промежутки, с: %s" % line)
	say("самый короткий %.0f, самый длинный %.0f, в среднем %.0f, разброс %.0f" % [
		mn, mx, avg, dev])
	# Метроном — это когда разброс мал по сравнению со средним. Живой темп даёт
	# разброс хотя бы в треть среднего: тогда игрок не может предсказать.
	if dev < avg * 0.33:
		warn("ТЕМП РОВНЫЙ: разброс %.0f при среднем %.0f — это метроном" % [dev, avg])


## НЕ ПРОТЕКАЕТ ЛИ СОЛНЦЕ В ЛАБИРИНТ.## НЕ ПРОТЕКАЕТ ЛИ СОЛНЦЕ В ЛАБИРИНТ. Пейзаж наверху освещён настоящим
## направленным светом, и весь расчёт на то, что потолок лабиринта его не
## пропускает. Проверяем прямо: яркость коридора с солнцем и без него.
## Сколько она идёт к тому, кто сел рисовать. Полотно открываем и не решаем:
## именно это положение и есть самое беззащитное в игре.
func _tempo_at_canvas() -> void:
	var m = w.monster
	var p = w.player_node
	if m == null or w.board == null:
		return
	# Доходим до ближайшего полотна: оно открывается по близости, само собой
	# на другом конце карты не откроется.
	var target: Vector2i = _canv_now()
	if target.x >= 0:
		await goto_cell(target, 60.0)
	m.retreat_to_wall(1.0, 1.0)
	m.pressure = 0.0
	m.calm_t = 0.0
	m.first_out = false
	var waited: float = 0.0
	while not w.board.visible and waited < 25.0:
		await w.get_tree().process_frame
		waited += w.get_process_delta_time()
	if not w.board.visible:
		say("полотно не открылось — проверку «пока рисуешь» пропускаем")
		return
	var t1: float = w._clock
	var seen: bool = false
	while w._clock - t1 < 120.0:
		await w.get_tree().process_frame
		if m.visible and m.mode != "inwall":
			seen = true
			break
	if seen:
		say("пока полотно открыто: вышла через %.0f с (давление %.0f из %.0f)" % [
			w._clock - t1, m.pressure, m.PRESS_OUT])
	else:
		warn("за две минуты у открытого полотна она не вышла ни разу")
	# ЗА СОБОЙ УБИРАЕМ. Полотно оставалось открытым, и следующая сцена бежала
	# по лабиринту с открытым окном — стенд потом честно ругался на отобранное
	# управление, и ругался на мой же беспорядок, а не на игру.
	if w.board != null and w.board.visible:
		w.board.abandon()
		# И ВЗВОД ВОЗВРАЩАЕМ. Брошенное полотно теперь не открывается заново,
		# пока не отойдёшь, — это игровое правило, и оно верное. Но стенд
		# бросает холст, НЕ СХОДЯ С МЕСТА, а следом идёт полный проход: он
		# приходил к тому же полотну, оно не открывалось, и проход впустую
		# крутил семь шагов за четыре секунды. Игрок в этом месте отходит сам.
		w.canvas_arm = true
		for i in 20:
			await w.get_tree().process_frame


func scene_sun_leak() -> void:
	say("═══ ПРОТЕЧКА СВЕТА В ЛАБИРИНТ ═══")
	var p = w.player_node
	p.invuln = 9999.0
	var sun: DirectionalLight3D = null
	for c in w.get_children():
		if c is DirectionalLight3D:
			sun = c
			break
	if sun == null:
		warn("направленного света в сцене нет — проверять нечего")
		return
	# Встаём подальше от любых проломов: именно там протечка была бы видна.
	var far: Vector2i = w.canv_cells[w.canv_cells.size() - 1]
	for c in w.canv_cells:
		var ok := true
		for h in w.holes:
			if Vector2(c - h).length() < 9.0:
				ok = false
		if ok:
			far = c
			break
	p.global_position = w.cell_to_world(far, PlayerScript.STAND_Y)
	p.pitch = 0.0
	var res: Array = []
	for on in [true, false]:
		sun.light_energy = 1.9 if on else 0.0
		for i in 18:
			await w.get_tree().process_frame
		# В HEADLESS КАДРА НЕТ. Снимок возвращает пусто, и проверка сыпалась
		# ошибкой в каждом безоконном прогоне. Она и не может там работать:
		# яркость меряется по пикселям, а пикселей не рисуется.
		var vt: ViewportTexture = w.get_viewport().get_texture()
		if vt == null:
			say("яркость в headless не измерить — гонять эту проверку с окном")
			return
		var img: Image = vt.get_image()
		if img == null:
			say("яркость в headless не измерить — гонять эту проверку с окном")
			return
		var sum: float = 0.0
		var n: int = 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var col: Color = img.get_pixel(x, y)
				sum += (col.r * 0.299 + col.g * 0.587 + col.b * 0.114) * 255.0
				n += 1
		res.append(sum / float(n))
		say("солнце %s: средняя яркость коридора %.2f из 255" % [
			"ВКЛ" if on else "выкл", res[res.size() - 1]])
	sun.light_energy = 1.9
	var diff: float = absf(float(res[0]) - float(res[1]))
	say("разница: %.2f" % diff)
	if diff > 1.0:
		warn("СОЛНЦЕ ПРОТЕКАЕТ В ЛАБИРИНТ: коридор светлеет на %.2f" % diff)


## ВИД ИЗ ПРОЛОМА. Ставит камеру туда, куда игрок высовывает голову, и снимает.
func scene_climb_view() -> void:
	say("═══ ВИД ИЗ ПРОЛОМА ═══")
	if w.climb_cell.x < 0:
		warn("пролома с насыпью на этой карте нет")
		return
	var p = w.player_node
	p.invuln = 9999.0
	var at: Vector3 = w.cell_to_world(w.climb_cell, 0.0)
	for spec in [[0.0, 2.0, "01_прямо"], [-0.6, 6.0, "02_вдоль_дороги"], [2.2, 14.0, "03_вбок"]]:
		# Ровно та высота, на которую его поднимает сцена: ставить камеру ниже
		# значит смотреть из ямы, и в кадре снизу лезет небо из-под края земли.
		p.global_position = Vector3(w.climb_b.x, w.climb_b.y, w.climb_b.z)
		p.yaw = float(spec[0])
		p.rotation.y = p.yaw
		p.pitch = deg_to_rad(float(spec[1]))
		for i in 14:
			await w.get_tree().process_frame
		await shot(str(spec[2]))
	say("снято три вида")


## НИТЬ К УБЕЖИЩУ. Проверяет три вещи: лента появляется в погоне, тварь не
## отпускает, пока игрок не в убежище, и отпускает, как только он туда попал.
func scene_flee_line() -> void:
	say("═══ НИТЬ К УБЕЖИЩУ ═══")
	var p = w.player_node
	var m = w.monster
	p.invuln = 9999.0
	if w.safe_cells.is_empty():
		warn("убежищ в лабиринте НЕТ — проверять нечего")
		return
	say("убежищ на карте: %d" % w.safe_cells.size())
	# УВОДИМ С УБЕЖИЩА. Стартовая клетка сама является убежищем, и стоя на ней
	# игрок «уже добежал»: нить не нужна, тварь отпускает. Первый заход этого не
	# учёл и показал ноль — врал стенд, а не игра.
	var away: Vector2i = w.canv_cells[w.canv_cells.size() - 1]
	for c in w.canv_cells:
		if not w.safe_cells.has(c):
			away = c
			break
	p.global_position = w.cell_to_world(away, PlayerScript.STAND_Y)
	await w.get_tree().physics_frame
	say("игрок уведён в клетку %s (убежище? %s)" % [str(away), str(w.safe_cells.has(away))])
	m.dive_t = 9999.0
	m.global_position = p.global_position + Vector3(0, 0, w.cell_size * 2.0)
	m.visible = true
	m.first_out = false
	m.mode = "chase"
	m.chase_t = 4.0
	m._grow_out()
	var t: float = 0.0
	var seen_line: int = 0
	var held: int = 0
	while t < 14.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		if w.flee_line != null and w.flee_line.visible:
			seen_line += 1
		if m.hunt_until_safe:
			held += 1
		if w.grab_ui != null and w.grab_ui.visible:
			# РЕЖЕТ ТЕМ ЖЕ КОДОМ, ЧТО И ИГРОК. Мышью стенд не водит, но
			# bot_slash строит настоящий взмах поперёк петли и прогоняет его
			# через ту же проверку попадания: подменить хват «зачётом» значило
			# бы мерить не игру, а свою доброту к себе.
			w.grab_ui.bot_slash()
	say("за 14 с: лента видна %.0f%% времени, тварь держала погоню %.0f%%" % [
		100.0 * float(seen_line) / (14.0 * 60.0), 100.0 * float(held) / (14.0 * 60.0)])
	say("режим через 14 с: %s (таймер погони был 4 с)" % m.mode)
	if seen_line == 0:
		warn("ЛЕНТА НЕ ПОЯВИЛАСЬ НИ РАЗУ")
	if m.mode != "chase":
		warn("тварь отпустила, хотя игрок не в убежище: режим %s" % m.mode)
	# А теперь ставим игрока В убежище — должна отпустить.
	p.global_position = w.cell_to_world(w.safe_cells[0], PlayerScript.STAND_Y)
	for i in 90:
		await w.get_tree().physics_frame
	say("в убежище: держит=%s, лента видна=%s" % [
		str(m.hunt_until_safe), str(w.flee_line.visible)])
	if m.hunt_until_safe:
		warn("игрок в убежище, а тварь всё ещё держит погоню")


## НЫРОК ПОСРЕДИ ПОГОНИ. Тварь уходит в ближний камень и выходит заново —
## вплотную (ловит сразу) или спереди (ревёт, стоит, потом бежит).
##
## Мерим, ПОДПИСАВШИСЬ НА СИГНАЛ, а не разглядывая лабиринт: где именно она
## вылезла, зависит от карты и от того, куда забрёл бот, и через это мерить
## нельзя — на этом я уже трижды получил ложь.
func scene_dive() -> void:
	say("═══ НЫРОК ПОСРЕДИ ПОГОНИ ═══")
	var p = w.player_node
	var m = w.monster
	p.invuln = 9999.0
	var blank: Array = [0]
	var front: Array = [0]
	var dists: Array = []
	var roars: Array = []
	m.lunged.connect(func(pb: bool):
		var d: float = Vector2(m.global_position.x - p.global_position.x,
			m.global_position.z - p.global_position.z).length()
		dists.append(d)
		if pb:
			blank[0] += 1
		else:
			front[0] += 1
			# Спереди — значит В СТОРОНУ ВЗГЛЯДА. Считаем косинус: единица —
			# прямо по курсу, ноль — сбоку, минус — за спиной.
			var to := Vector2(m.global_position.x - p.global_position.x,
				m.global_position.z - p.global_position.z)
			var face: Vector3 = -p.global_transform.basis.z
			var fv := Vector2(face.x, face.z)
			if to.length() > 0.01 and fv.length() > 0.01:
				roars.append(fv.normalized().dot(to.normalized())))
	m.drop_hold()
	m.form_hold = 0.0
	m.form_t = 0.0
	m.form_kind = m.FORM_NONE
	# ФАЗУ И РЕЖИМ — ЯВНО. Первый заход этого не сделал, и тварь все три минуты
	# просидела в камне за полторы сотни метров: я выставил ей место и видимость,
	# а погоню — нет. «Ноль нырков» тогда означало «ноль погони».
	# ВТОРАЯ ФАЗА, А НЕ ТРЕТЬЯ: в третьей с шестидесятой секунды всё забирает
	# система засад, режим уходит в ambush, и нырков за три минуты четыре.
	set_phase(2)
	m.global_position = p.global_position + Vector3(0, 0, w.cell_size * 2.0)
	m.visible = true
	m.first_out = false
	m.mode = "chase"
	m.chase_t = 900.0
	m.dive_t = 1.0
	m._grow_out()
	# ИГРОК ДОЛЖЕН ОТДАЛЯТЬСЯ. Первый заход дал ноль нырков: игрок стоял, тварь
	# парковалась в 2.9 м, а нырять вблизи ей запрещено — и правильно, исчезать
	# у человека из-под носа это подарок, а не угроза. Гоняем его телепортом по
	# клеткам полотен: навигацию бота сюда пускать нельзя, на ней я уже горел.
	var spots: Array = []
	for c in w.canv_cells:
		spots.append(c)
	for c in w.room_cells:
		spots.append(c)
	var t: float = 0.0
	var hop: float = 0.0
	var si: int = 0
	while t < 180.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		hop += 1.0 / 60.0
		# ПЕРЕСТАВЛЯЕМ ОБОИХ. Гонять телепортом одного игрока не годится: он
		# улетал за девяносто метров, тварь полминуты добиралась, и на сами
		# нырки времени не оставалось. Переставляем пару разом и сохраняем
		# между ними разрыв в две клетки — ровно как в начале погони.
		if hop >= 6.0 and not spots.is_empty():
			hop = 0.0
			si = (si + 1) % spots.size()
			p.global_position = w.cell_to_world(spots[si], PlayerScript.STAND_Y)
			if m.mode != "inwall" and m.mode != "surfacing":
				m.global_position = p.global_position + Vector3(0, 0, w.cell_size * 2.0)
		# Держим погоню живой: нас интересуют нырки, а не то, сколько она
		# продержится. Но НЕ трогаем её, пока она в камне или ревёт.
		if m.mode == "chase" or m.mode == "roam" or m.mode == "hunt":
			m.mode = "chase"
			m.chase_t = 900.0
		if w.grab_ui != null and w.grab_ui.visible:
			# РЕЖЕТ ТЕМ ЖЕ КОДОМ, ЧТО И ИГРОК. Мышью стенд не водит, но
			# bot_slash строит настоящий взмах поперёк петли и прогоняет его
			# через ту же проверку попадания: подменить хват «зачётом» значило
			# бы мерить не игру, а свою доброту к себе.
			w.grab_ui.bot_slash()
		if int(t * 60.0) % 600 == 0:
			print("[нырок] t=%.0f режим=%s видно=%s dive_t=%.1f разрыв=%.1f нырков=%d" % [
				t, m.mode, str(m.visible), m.dive_t,
				Vector2(m.global_position.x - p.global_position.x,
					m.global_position.z - p.global_position.z).length(),
				int(blank[0]) + int(front[0])])
	var n: int = int(blank[0]) + int(front[0])
	say("за 180 с погони нырков: %d (вплотную %d, спереди %d)" % [
		n, blank[0], front[0]])
	if n == 0:
		warn("НЫРКОВ НЕ БЫЛО — проверка ничего не значит")
		return
	say("раз в %.0f с в среднем" % (180.0 / float(n)))
	var sum: float = 0.0
	for d in dists:
		sum += float(d)
	say("выходила в среднем в %.1f м от игрока (клетка %.1f м)" % [
		sum / float(dists.size()), w.cell_size])
	if not roars.is_empty():
		var c: float = 0.0
		var behind: int = 0
		for r in roars:
			c += float(r)
			if float(r) < 0.0:
				behind += 1
		say("выходы «спереди»: косинус к взгляду %.2f, за спиной %d из %d" % [
			c / float(roars.size()), behind, roars.size()])
		if behind > 0:
			warn("%d выходов «спереди» оказались ЗА СПИНОЙ" % behind)


## СТЕНЫ, КОТОРЫЕ ХЛЕЩУТ. Проверяет ровно одно: что выпрыгивания начинаются
## во второй фазе, а в третьей идут заметно чаще. Раньше они стояли под
## `phase < 3`, то есть игрок видел их за одно полотно до конца игры — или
## не видел вовсе.
func scene_bursts() -> void:
	say("═══ ВЫПРЫГИВАНИЯ ИЗ СТЕН ═══")
	w.player_node.invuln = 9999.0
	for ph in [2, 3]:
		w.phase = ph
		w.burst_t = 0.0
		var was: int = w.bursts
		var t0: float = float(Time.get_ticks_msec())
		while float(Time.get_ticks_msec()) - t0 < 120000.0:
			await w.get_tree().process_frame
		var got: int = w.bursts - was
		say("фаза %d: за 120 с хлестнуло %d раз (в среднем раз в %s)" % [
			ph, got, "%.0f с" % (120.0 / float(got)) if got > 0 else "НИ РАЗУ"])
		if got == 0:
			warn("в фазе %d стены не хлестнули ни разу" % ph)
	if w.bursts == 0:
		warn("ВЫПРЫГИВАНИЙ НЕТ ВООБЩЕ — проверка ничего не значит")


func scene_wander(minutes: float) -> void:
	say("═══ БРОЖЕНИЕ БЕЗ ПОЛОТЕН ═══")
	var t0: float = w._clock
	var last: int = -1
	var ends: Array = []
	for c in w.maze.dead_ends():
		ends.append(c)
	if ends.is_empty():
		warn("тупиков нет")
		return
	# СРАЗУ ВТОРАЯ ФАЗА. Ждать её по-настоящему — это четыре минуты на прогон,
	# а вопрос не в ней: он сам сказал, что монстр уже вылазит по кругу. Вопрос
	# в том, появляется ли ФИГУРА у того, кто просто ходит.
	w.phase = 2
	w.monster.allow_emerge = true
	var forms0: int = w.forms_left
	var seen_form: int = 0
	var i: int = 0
	while w._clock - t0 < minutes * 60.0:
		if w.phase != last:
			last = w.phase
			say("фаза %d на %.0f с (полотен сдано %d)" % [w.phase, w._clock - t0, w.done])
		if w.monster.form_kind == w.monster.FORM_HUMAN and w.monster.form_t > 0.5:
			if seen_form == 0:
				say("ФИГУРА ПОЯВИЛАСЬ на %.0f с" % [w._clock - t0])
			seen_form += 1
		if w.forms_left != forms0:
			say("бюджет формы: %d -> %d на %.0f с, превратился в %s" % [
				forms0, w.forms_left, w._clock - t0,
				"ЗАЛЕ (на четвереньках)" if w.last_form_room else "коридоре (в рост)"])
			forms0 = w.forms_left
		# Полотно открылось — УХОДИМ, не рисуя: он именно так и ходил.
		if w.board != null and w.board.visible:
			w.board.visible = false
			w.canvas_arm = false
		var goal: Vector2i = ends[i % ends.size()]
		i += 1
		# ПО ЧАСТЯМ. Целый goto_cell — это до 45 секунд без единого опроса, и
		# всё, что случилось внутри, стенд видел уже остывшим.
		await goto_cell(goal, 8.0)
	say("итог: фаза %d за %.0f с, полотен %d, форм осталось %d, кадров с фигурой %d" % [
		w.phase, w._clock - t0, w.done, w.forms_left, seen_form])
	if seen_form == 0:
		warn("ФИГУРА НЕ ПОЯВИЛАСЬ НИ РАЗУ — ровно то, на что он жалуется")


## УДАР ЛИ ЭТО. Три числа решают: пик (насколько громко вообще), громкость по
## среднему квадрату (насколько плотно) и время до пика (насколько резко).
## «Нота пианино» — это низкий пик, низкая плотность и медленная атака.
func _wave_report(name: String, w2) -> void:
	if w2 == null:
		return
	var d: PackedByteArray = w2.data
	var n: int = d.size() / 2
	if n <= 0:
		return
	var peak: int = 0
	var at_peak: int = 0
	var sum2: float = 0.0
	for i in n:
		var v: int = absi(d.decode_s16(i * 2))
		if v > peak:
			peak = v
			at_peak = i
		sum2 += float(v) * float(v)
	var rms: float = sqrt(sum2 / float(n))
	# Частоту берём У САМОЙ записи: в этом проекте она 22 050, а не 44 100, и
	# деление на «обычные» 44 100 занижало длину ровно вдвое.
	var sr: float = float(w2.mix_rate)
	say("%s: пик %.0f%% на %.0f мс, плотность %.0f%%, длина %.1f с" % [
		name, 100.0 * float(peak) / 32767.0,
		1000.0 * float(at_peak) / sr,
		100.0 * rms / 32767.0, float(n) / sr])


## ДОБИВАНИЕ. Играющий (21.09): «единственное, что видит игрок, — это низ
## монстра, а то, как его разрывают, не читается вообще». Снимаем всю сцену
## подряд, кадр за кадром: словами это не разобрать, только глазами.
func scene_fatality() -> void:
	say("═══ ДОБИВАНИЕ ═══")
	var m = w.monster
	if m == null:
		return
	set_phase(3)
	# В коридоре, а не в стартовом закутке: там стол и стены под носом.
	var где := Vector2i(-1, -1)
	for r in range(4, w.maze.size.y - 4):
		for c in range(4, w.maze.size.x - 4):
			if not w.maze.is_wall(r, c) and not w.safe_cells.has(Vector2i(r, c)):
				где = Vector2i(r, c)
				break
		if где.x >= 0:
			break
	w.player_node.global_position = w.cell_to_world(где, PlayerScript.STAND_Y)
	w.player_node.invuln = 9999.0
	await w.get_tree().process_frame
	w._start_fatality()
	var t: float = 0.0
	var i: int = 0
	while w.fat_stage != 0 and t < 12.0:
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
		if t >= float(i) * 0.5:
			say("  этап %d, %.1f с: игрок на %.2f м, тварь на %.2f м" % [
				w.fat_stage, t, w.player_node.global_position.y,
				m.global_position.y])
			await shot("добивание_%02d" % i)
			i += 1
	say("добивание длилось %.1f с, кадров %d" % [t, i])


## «СОБАКА»: ФИГУРА В КАМНЕ. Состояние из лога играющего — тварь в форме фигуры
## стоит в 2.8 м, все счётчики нулевые, и четырнадцать секунд ничего не
## происходит. Причина: оба приёма фигуры отказываются бить из камня, а вызов
## стоял так, что отказ уводил в никуда. Ставим её в стенную клетку рядом и
## смотрим, нападёт ли она хоть чем-нибудь.
func scene_dog() -> void:
	say("═══ СОБАКА: ФИГУРА В КАМНЕ ═══")
	var m = w.monster
	if m == null:
		return
	set_phase(2)
	w.player_node.invuln = 0.0
	w.grab_cool = 0.0
	w.lurk_t = 0.0
	# Ищем пол, у которого есть стена в соседях: туда игрока, в стену — тварь.
	var пол := Vector2i(-1, -1)
	var камень := Vector2i(-1, -1)
	for r in range(2, w.maze.size.y - 2):
		for c in range(2, w.maze.size.x - 2):
			var cell := Vector2i(r, c)
			if w.maze.is_wall(cell.x, cell.y) or w.safe_cells.has(cell):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if w.maze.is_wall(cell.x + d.x, cell.y + d.y):
					пол = cell
					камень = cell + d
					break
			if пол.x >= 0:
				break
		if пол.x >= 0:
			break
	if пол.x < 0:
		warn("не нашлось пола со стеной рядом")
		return
	w.player_node.global_position = w.cell_to_world(пол, PlayerScript.STAND_Y)
	await w.get_tree().process_frame
	var в_камне: Vector3 = w.cell_to_world(камень, 0.0)
	m.parked = false
	m.prowl = false
	m.mode = "chase"
	m.visible = true
	m.chase_t = 60.0
	m.stun = 0.0
	m.global_position = в_камне
	m.take_form(40.0, m.FORM_HUMAN)
	w.hf_cool = 0.0
	w.hf_stage = 0
	# ЖДЁМ, ПОКА ФИГУРА ПРОЯВИТСЯ. Ветка приёмов в _on_caught требует form_t
	# больше 0.6 — это доля «собранности» тела, и сразу после take_form она
	# нулевая. Без ожидания сцена шла мимо всей проверки и проходила даже на
	# сломанном коде: первый прогон так и сказал «напал за 0.5 с», хотя
	# проверять была должна совсем другую ветку.
	# И ДЕРЖИМ ОТКАТ ХВАТА, ПОКА ЖДЁМ. Иначе он берёт игрока обычным путём ещё
	# до того, как фигура проявится, — и сцена опять проходит мимо той ветки,
	# ради которой написана. Проверено: со сломанным кодом она тоже проходила.
	var t_form: float = w._clock
	while m.form_t < 0.7 and w._clock - t_form < 6.0:
		w.grab_cool = 5.0
		await w.get_tree().process_frame
		m.global_position = в_камне
	w.grab_cool = 0.0
	say("тварь в стенной клетке %s, игрок в %s, форма %d, проявлена %.2f" % [
		str(камень), str(пол), m.form_kind, m.form_t])
	if m.form_t < 0.7:
		warn("фигура так и не проявилась — проверка не состоялась")
		return
	# ПРЕМИССА: ИЗ КАМНЯ ОБА ПРИЁМА ОТКАЗЫВАЮТСЯ. Проверяем прямым вызовом, а
	# не через игру: страховка «в камне не стоять» выталкивает тварь в начале
	# такта, и к моменту, когда до ветки доходит дело, она уже на полу — два
	# прогона подряд сцена проходила и на сломанном коде именно поэтому.
	m.global_position = в_камне
	w.grab_cool = 0.0
	w.player_node.invuln = 0.0
	w.reel_t = 0.0
	w.hf_stage = 0
	w.hf_cool = 0.0
	w.lift_on = false
	w.hurl_t = 0.0
	w.still_t = 0.0
	var где: Vector2i = w.world_to_cell(m.global_position)
	var руки: bool = w._start_human_attack()
	w.hf_stage = 0
	w.hf_cool = 0.0
	w.lift_on = false
	var язык: bool = w._human_tongue()
	w.reel_t = 0.0
	say("тварь в клетке %s, это камень: %s; из камня руки %s, язык %s" % [
		str(где), str(w.maze.is_wall(где.x, где.y)), str(руки), str(язык)])
	if not w.maze.is_wall(где.x, где.y):
		warn("тварь не в камне — условие сцены не выполнено, проверять нечего")
		return
	if руки or язык:
		warn("приём фигуры сработал из камня — значит дело не в камне")
		return
	# А ТЕПЕРЬ САМА РАЗВИЛКА. Зовём обработчик так же, как его зовёт тварь,
	# когда дотянулась. Починенный уходит в обычный хват; сломанный — в никуда.
	w.reel_t = 0.0
	w.hf_stage = 0
	w.hf_cool = 0.0
	w.lift_on = false
	m.global_position = в_камне
	w._on_caught()
	# ЧИТАЕМ СРАЗУ, БЕЗ ОЖИДАНИЯ КАДРА. С ожиданием между вызовом и замером
	# успевал пройти целый такт игры: страховка выталкивала тварь из камня, она
	# честно нападала уже с пола — и сцена показывала «напал» даже на сломанном
	# коде. Третья ложь стенда за вечер, и все три об одном: замер должен
	# стоять ВПЛОТНУЮ к тому, что меряет.
	var напал: bool = w.grab_ui.visible or w.reel_t > 0.0 or w.hf_stage > 0 \
		or w.lift_on
	say("дотянулся из камня: напал %s (хват %s, тянет %.2f, приём %d, подъём %s)" % [
		str(напал), str(w.grab_ui.visible), w.reel_t, w.hf_stage, str(w.lift_on)])
	if not напал:
		warn("фигура дотянулась из камня и не сделала НИЧЕГО — это «собака»")
	if w.grab_ui.visible:
		w.grab_ui._end(true)
	m.take_form(0.01, m.FORM_NONE)
	m.retreat_to_wall(1.0, 1.0)


## ТИШИНА И ЛОЖНЫЕ ТРЕВОГИ. Страх числами не меряется, а вот звук — меряется, и
## проверять тут есть что: сколько всего тишины за три минуты, молчит ли в ней
## украшение (сердце, дыхание, музыка) и не бьют ли ложные тревоги тогда, когда
## тварь и правда рядом, — последнее хуже, чем не иметь их вовсе.
func scene_hush() -> void:
	say("═══ ТИШИНА И ЛОЖНЫЕ ТРЕВОГИ ═══")
	if w.sfx == null:
		return
	w.player_node.invuln = 9999.0
	set_phase(2)
	w.sfx.watch = true
	var было_тишин: int = w.hush_count
	var было_ложных: int = w.fake_count
	var seen: int = w.sfx.heard.size()
	var тихо: float = 0.0
	var лишнее: Dictionary = {}
	var ложных_вблизи: int = 0
	Engine.time_scale = 3.0
	var t0: float = w._clock
	while w._clock - t0 < 180.0:
		await w.get_tree().process_frame
		if w.hush_t > 0.0:
			тихо += w.get_process_delta_time()
		# Ложная тревога, пока он снаружи, — это порча настоящего звука.
		if w.fake_count > было_ложных + ложных_вблизи:
			if w.monster.mode != "inwall":
				ложных_вблизи += 1
		while seen < w.sfx.heard.size():
			var h = w.sfx.heard[seen]
			seen += 1
			if w.hush_t <= 0.0:
				continue
			var nm: String = str(h["имя"])
			if nm in ["heart", "breath"]:
				лишнее[nm] = int(лишнее.get(nm, 0)) + 1
	Engine.time_scale = 1.0
	w.sfx.watch = false
	var t: float = w._clock - t0
	say("за %.0f с: тишин %d, всего тихо %.0f с (%.0f%% времени), ложных тревог %d" % [
		t, w.hush_count - было_тишин, тихо, тихо / t * 100.0,
		w.fake_count - было_ложных])
	if w.hush_count - было_тишин < 1:
		warn("за три минуты тишина не наступила ни разу")
	if тихо / t < 0.05:
		warn("тишины %.0f%% времени — это не провал фона, а его дрожь" % [тихо / t * 100.0])
	if not лишнее.is_empty():
		warn("в тишине всё равно звучало: %s" % str(лишнее))
	if ложных_вблизи > 0:
		warn("ложных тревог при вышедшей твари: %d" % ложных_вблизи)


## КРАЯ И СВЕТ. Три места, на которые играющий указал 20.09: обод колодца
## наверху («дрожат края»), потолок над столом в начале («светит сверху какой-то
## свет вроде тумана») и палочка на столе («выглядит не так, как в руке»).
##
## Снимаем на ВЫСОКОМ качестве: объёмный туман включается только там, и именно
## на нём видна муть над столом. Дрожь стыка на одном кадре не поймать — она
## живёт в разнице между кадрами, — но видно другое, не менее важное: не
## появилось ли на месте починки щели, засветки или чёрного провала.
func scene_edges() -> void:
	say("═══ КРАЯ И СВЕТ ═══")
	var was: int = Settings.quality
	Settings.quality = 2
	w.apply_quality()
	var p = w.player_node
	p.invuln = 9999.0
	p.set_physics_process(false)
	var кадры := [
		# Стол в начале: палочка на нём и потолок над ним.
		[w.cell_to_world(w.start_cell, PlayerScript.STAND_Y) + Vector3(0.0, 0.0, -1.5),
			PI, -17.0, "01_стол_палочка"],
		[w.cell_to_world(w.start_cell, PlayerScript.STAND_Y) + Vector3(0.0, 0.0, -0.6),
			PI, 66.0, "02_потолок_над_столом"],
	]
	if w.climb_cell.x >= 0:
		var at: Vector3 = w.cell_to_world(w.climb_cell, 0.0)
		кадры.append([Vector3(at.x, PlayerScript.STAND_Y, at.z + 1.2), 0.0, 55.0,
			"03_колодец_снизу"])
		кадры.append([Vector3(w.climb_b.x, w.climb_b.y, w.climb_b.z), 0.6, -32.0,
			"04_обод_сверху"])
	for spec in кадры:
		p.global_position = spec[0]
		p.yaw = float(spec[1])
		p.rotation.y = p.yaw
		p.pitch = deg_to_rad(float(spec[2]))
		# И ГОЛОВУ ПОВОРАЧИВАЕМ САМИ. pitch кладётся на голову внутри _view, а
		# тот зовётся только при включённой физике — которую мы здесь как раз
		# выключили, чтобы игрок не съезжал. Первый прогон снял три кадра в пол:
		# камера осталась смотреть туда, куда смотрела при падении.
		if p.head != null:
			p.head.rotation.x = p.pitch
		for i in 16:
			await w.get_tree().process_frame
		await shot(str(spec[3]))
	Settings.quality = was
	w.apply_quality()
	p.set_physics_process(true)
	say("снято %d кадров" % кадры.size())


## НАБЕГ НА РИСУЮЩЕГО. Два исхода, и проверять надо оба: успел дорисовать —
## он должен уйти; не успел — сорвать полотно, схватить, а после освобождения
## полотно должно стоять уже в другом месте.
func scene_raid() -> void:
	say("═══ НАБЕГ НА РИСУЮЩЕГО ═══")
	if w.board == null or w.monster == null:
		return
	w.player_node.invuln = 9999.0
	set_phase(2)
	# ПАЛОЧКА В РУКУ. Она лежит на столе в стартовой комнате, а бот сюда
	# телепортируется — без неё нет ни света, ни мигания, и мерить было бы
	# нечего. Первый прогон так и показал: свет держался на 25.00 обе секунды,
	# потому что лампы в руке не было вовсе.
	w.has_wand = true
	w.player_node.has_wand = true
	if w.wand_lamp != null:
		w.wand_lamp.visible = true
	if w.wand_view != null:
		w.wand_view.visible = true
	# ── ИСХОД ПЕРВЫЙ: УСПЕЛ ──────────────────────────────────────────────
	w.done = 4
	if not await _stand_at_canvas():
		return
	# Рисуем до половины — до того места, с которого он и срывается.
	await _draw_until(0.55, 20.0)
	var t0: float = w._clock
	while w.raid == 0 and w._clock - t0 < 6.0 and w.board.visible:
		await w.get_tree().process_frame
	if w.raid == 0:
		warn("набег не начался на пятом полотне (точек %d из %d)"
			% [w.board.next_idx, w.board.n])
		return
	var путь: int = w.maze.path_weighted(
		w.world_to_cell(w.monster.global_position),
		w.world_to_cell(w.player_node.global_position), 1 << 20, 1).size()
	say("набег начался: он в %d клетках по коридорам" % путь)
	# МИГАНИЕ. Снимаем крайние значения света за секунду в начале и позже ещё
	# раз, у самого конца пути: «медленнее и тусклее» против «чаще и ярче» —
	# это две пары чисел, а не впечатление.
	var рано: Array = await _blink_range(1.0)
	# Дорисовываем — и он должен уйти.
	await _draw_until(1.1, 30.0)
	await w.get_tree().create_timer(0.8).timeout
	say("успел: сдано %d, набег %d, режим твари %s, доля пути %.2f" % [
		w.done, w.raid, w.monster.mode, w.monster.finale_near])
	if w.raid != 0 or w.monster.finale_mode:
		warn("набег не выключился после сданного полотна")
	if w.monster.mode != "inwall":
		warn("успел дорисовать, а он не ушёл: режим %s" % w.monster.mode)
	# ── ИСХОД ВТОРОЙ: НЕ УСПЕЛ ───────────────────────────────────────────
	# СНАЧАЛА УБИРАЕМ КАРТИНКУ. За сданным полотном показывают кадр чужой
	# истории, и пока он на экране, набег не начинается — это правило игры, а
	# не помеха: набег поверх картинки был бы набегом, которого не видно.
	if w.vision_ui != null and w.vision_ui.visible:
		w.vision_ui.visible = false
		w._on_vision_closed()
		await w.get_tree().process_frame
	w.done = 6
	w.player_node.invuln = 0.0
	if not await _stand_at_canvas():
		return
	await _draw_until(0.55, 20.0)
	t0 = w._clock
	while w.raid == 0 and w._clock - t0 < 6.0 and w.board.visible:
		await w.get_tree().process_frame
	if w.raid == 0:
		warn("набег не начался на седьмом полотне")
		return
	var где0: Vector2i = w.canv_cells[w.done]
	var поздно: Array = []
	# Дальше НЕ рисуем: пусть дойдёт.
	t0 = w._clock
	while w.raid != 0 and w._clock - t0 < 45.0:
		await w.get_tree().process_frame
		if w.monster.finale_near > 0.7 and поздно.is_empty():
			поздно = await _blink_range(1.0)
	say("мигание палочки: в начале %s, у конца %s (тускло, ярко, вспышек)"
		% [str(рано), str(поздно)])
	if рано.size() >= 3 and поздно.size() >= 3:
		if float(поздно[1]) <= float(рано[1]):
			warn("к концу палочка не стала ярче: было %.2f, стало %.2f"
				% [float(рано[1]), float(поздно[1])])
		if int(поздно[2]) <= int(рано[2]):
			warn("к концу палочка не стала мигать чаще: было %d, стало %d"
				% [int(рано[2]), int(поздно[2])])
	say("дошёл за %.0f с: хват %s, полотно к переезду %s" % [w._clock - t0,
		str(w.grab_ui.visible), str(w.raid_flee)])
	if not w.grab_ui.visible:
		warn("дошёл, но хвата нет")
	# Вырываемся — и смотрим, уехало ли полотно.
	if w.grab_ui.visible:
		w.grab_ui._end(true)
	await w.get_tree().create_timer(0.5).timeout
	var где1: Vector2i = w.canv_cells[w.done]
	say("полотно было в %s, стало в %s" % [str(где0), str(где1)])
	if где0 == где1:
		warn("полотно не ушло после сорванного набега")
	# «СОБАКА». Пока полотно открыто, тварь ходит кругами вокруг рисующего
	# (park+prowl). Сорванный холст гасили руками, минуя _close_board, — и она
	# оставалась в обходе навсегда: шла за игроком и не нападала. Проверяем
	# ровно это состояние, потому что словами его не отличить от погони.
	say("после срыва: обход %s, припаркован %s, режим %s" % [
		str(w.monster.prowl), str(w.monster.parked), w.monster.mode])
	if w.monster.parked or w.monster.prowl:
		warn("тварь осталась в обходе после сорванного полотна — это и есть «собака»")
	# И ПОЛОТНО ВО ВРЕМЯ ПОГОНИ НЕ ОТКРЫВАЕТСЯ. Стоим у мольберта, погоня идёт —
	# холст должен молчать.
	w.monster.mode = "chase"
	w.monster.visible = true
	w.canvas_arm = true
	w.player_node.global_position = w.cell_to_world(w.canv_cells[w.done],
		PlayerScript.STAND_Y)
	for _i in 12:
		await w.get_tree().process_frame
	say("у мольберта во время погони полотно открыто: %s" % str(w.board.visible))
	if w.board.visible:
		warn("полотно открылось во время погони")
		w._close_board()
	w.monster.retreat_to_wall(1.0, 1.0)


## Встать у нынешнего полотна и открыть его. Пешком бот туда идёт минуту и
## нередко не доходит вовсе — а меряем мы не его ходьбу.
func _stand_at_canvas() -> bool:
	if w.done >= w.canv_cells.size():
		return false
	w.player_node.global_position = w.cell_to_world(w.canv_cells[w.done],
		PlayerScript.STAND_Y)
	await w.get_tree().process_frame
	w._open_board()
	var ждём: float = 0.0
	while not w.board.visible and ждём < 6.0:
		await w.get_tree().process_frame
		ждём += w.get_process_delta_time()
	if not w.board.visible:
		warn("полотно %d не открылось" % (w.done + 1))
		return false
	return true


## Соединять точки, пока не пройдена доля рисунка (или пока не кончится срок).
## Доля больше единицы — значит до конца.
func _draw_until(frac: float, limit: float) -> void:
	var b = w.board
	var t: float = 0.0
	while b.visible and t < limit:
		if b.n > 0 and float(b.next_idx) / float(b.n) >= frac:
			return
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
		for d in b.dots:
			if int(d["idx"]) == b.next_idx and not bool(d["done"]):
				if not b.blocked(int(d["idx"])):
					b._click(b._dot_pos(d))
				break


## Крайние значения света палочки за столько секунд: [тусклее всего, ярче всего,
## сколько раз мигнуло].
func _blink_range(seconds: float) -> Array:
	var lo: float = 1e9
	var hi: float = -1e9
	var было: int = w.raid_n
	var t: float = 0.0
	while t < seconds:
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
		if w.wand_lamp == null:
			continue
		lo = minf(lo, w.wand_lamp.light_energy)
		hi = maxf(hi, w.wand_lamp.light_energy)
	return [snappedf(lo, 0.01), snappedf(hi, 0.01), w.raid_n - было]


## РЫВОК В ЛИЦО. Показ камерой, две секунды пустоты — и он перед лицом. Три
## вопроса, на которые нельзя ответить словами: пропадает ли он на эти секунды,
## выходит ли ИМЕННО СПЕРЕДИ (косинус со взглядом) и как близко.
func scene_face_jump() -> void:
	say("═══ РЫВОК В ЛИЦО ═══")
	var m = w.monster
	if m == null or w.player_node == null:
		return
	w.player_node.invuln = 9999.0
	set_phase(2)
	m.allow_emerge = true
	m.first_out = false
	# НЕ В УБЕЖИЩЕ И НЕ У МОЛЬБЕРТА. Стартовая комната — убежище целиком, а
	# рывок в лицо туда нарочно не ходит. У мольберта же само открывается
	# полотно, тварь переходит в обход вокруг рисующего — и рывок повисает
	# незаконченным: первый прогон так и показал «за восемь секунд не вышел».
	# Нужен обычный тупик: ни круга, ни холста.
	for c in w.maze.dead_ends():
		if w.safe_cells.has(c) or w.canv_cells.has(c):
			continue
		w.player_node.global_position = w.cell_to_world(c, PlayerScript.STAND_Y)
		# И ЛИЦОМ В КОРИДОР, А НЕ В СТЕНУ. Телепортированный бот смотрел куда
		# придётся, и в тупике это означало «в стену в двух метрах»: приём
		# честно уходил в запасную ветку, а замер показывал не его.
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if w.maze.is_wall(n.x, n.y):
				continue
			var to: Vector3 = w.cell_to_world(n, 0.0) - w.cell_to_world(c, 0.0)
			w.player_node.yaw = atan2(-to.x, -to.z)
			w.player_node.rotation = Vector3(0.0, w.player_node.yaw, 0.0)
			break
		break
	await w.get_tree().process_frame
	await w.get_tree().process_frame
	# ПОКАЗ — СИЛОЙ, а рывок взводим следом: доля рывков случайная, и ждать
	# нужного броска монетки значит мерить монетку, а не приём.
	m._begin_surface(w.player_node.global_position, false)
	w.jump_armed = true
	var t0: float = w._clock
	while w.cine != 0 and w._clock - t0 < 12.0:
		await w.get_tree().process_frame
	say("показ кончился через %.1f с, тварь видно: %s, счёт рывка %.1f с" % [
		w._clock - t0, str(m.visible), m.jump_t])
	if m.visible:
		warn("после показа он остался на виду — рывка в лицо не вышло")
	# Ждём выхода и считаем, сколько длилась пустота.
	var t1: float = w._clock
	while not m.visible and w._clock - t1 < 8.0:
		await w.get_tree().process_frame
	var пусто: float = w._clock - t1
	if not m.visible:
		warn("за 8 с после показа он так и не вышел")
		return
	# Даём ему ровно доехать: выезд длится 0.30 с, а дальше начинается обычная
	# погоня, и он сходит с точки — мерить надо приём, а не первый шаг погони.
	await w.get_tree().create_timer(0.32).timeout
	var to: Vector3 = m.global_position - w.player_node.global_position
	to.y = 0.0
	var fwd: Vector3 = -w.player_node.global_transform.basis.z
	fwd.y = 0.0
	var cosa: float = 0.0
	if to.length() > 0.01 and fwd.length() > 0.01:
		cosa = fwd.normalized().dot(to.normalized())
	say("пустота %.1f с, вышел в %.1f м, по взгляду %.2f (1.0 — прямо в лицо)" % [
		пусто, to.length(), cosa])
	if пусто < 0.8 or пусто > 4.0:
		warn("пустота перед рывком %.1f с — это не «через пару секунд»" % пусто)
	if to.length() > 5.0:
		warn("вышел за %.1f м — это не «перед лицом»" % to.length())
	if cosa < 0.35:
		warn("вышел мимо взгляда (косинус %.2f): игрок этого не увидит" % cosa)
	await shot("рывок_в_лицо")
	m.retreat_to_wall(1.0, 1.0)


## ЗАТИШЬЕ: ЖДЁТ ЛИ ОН ПОЛОТНА. Стоим на месте нарочно — навигация бота тут ни
## при чём, а меряем ровно одно: держит ли мир тварь в камне, пока не сдано
## следующее полотно, и выходит ли она вскоре после того, как оно сдано.
func scene_calm() -> void:
	say("═══ ЗАТИШЬЕ ═══")
	var m = w.monster
	if m == null:
		return
	w.player_node.invuln = 9999.0
	set_phase(2)
	m.allow_emerge = true
	# СОСТОЯНИЕ «ВСТРЕЧА ТОЛЬКО ЧТО КОНЧИЛАСЬ» — СТАВИМ РУКАМИ. Настоящая
	# встреча тянет за собой показ, рывок и погоню, и меряли бы мы их, а не
	# затишье: первый же прогон так и вышел — тварь вылезла «вопреки затишью»,
	# хотя это доигрывался рывок, начатый до него.
	m.retreat_to_wall(1.0, 1.0)
	m.first_out = false
	m.pressure = 0.0
	m.calm_t = 0.0
	w.outings = 1
	w.out_gap = 99.0
	w.calm_armed = false
	var t0: float = w._clock
	await w.get_tree().process_frame
	await w.get_tree().process_frame
	say("затишье взведено: %s (полотен %d)" % [str(m.hold_out), w.done])
	# БЕЗ ПОЛОТНА ОН ВЫХОДИТЬ НЕ ДОЛЖЕН. Ждём вдвое дольше обычного срока
	# давления (PRESS_OUT ≈ 46 с): если вышел — затишье не работает.
	t0 = w._clock
	var вышел: bool = false
	while w._clock - t0 < 95.0:
		await w.get_tree().process_frame
		if m.visible and m.mode != "inwall":
			вышел = true
			break
	if вышел:
		warn("вышел через %.0f с, хотя полотно не сдано (затишье %s)" % [
			w._clock - t0, str(m.hold_out)])
	else:
		say("без полотна за 95 с не вышел ни разу, давление %.0f из %.0f" % [
			m.pressure, m.press_need])
	# А ТЕПЕРЬ ПОЛОТНО СДАНО. Считаем, через сколько он появится: несколько
	# секунд — то, что надо; мгновенно — значит он ждал за углом.
	w.done += 1
	t0 = w._clock
	while w._clock - t0 < 60.0:
		await w.get_tree().process_frame
		if m.visible and m.mode != "inwall":
			break
	if m.visible and m.mode != "inwall":
		say("после сданного полотна вышел через %.0f с" % [w._clock - t0])
	else:
		warn("после сданного полотна не вышел и за минуту")
	m.retreat_to_wall(1.0, 1.0)
	w.done -= 1


## ВРЕМЕННАЯ СЦЕНА: открыть холст и снять кадр. Подсказку «E — бросить» надо
## увидеть, а не поверить, что она нарисована.
func scene_board_shot() -> void:
	say("═══ ХОЛСТ: КАДР ═══")
	w.player_node.invuln = 9999.0
	# У ХОЛСТА, А НЕ ГДЕ ПРИДЁТСЯ. Сцена открывала полотно из точки спавна, и
	# кадр выходил «мольберт в двух метрах» вместо «рисуем в упор».
	w.player_node.global_position = w.cell_to_world(w.canv_cells[w.done],
		PlayerScript.STAND_Y)
	await w.get_tree().process_frame
	w._open_board()
	await w.get_tree().create_timer(0.8).timeout
	say("холст открыт: %s" % str(w.board.visible))
	await shot("холст_спокойно")
	# КУРСОР ДОЛЖЕН ПОПАДАТЬ ТУДА, КУДА ЦЕЛИШЬСЯ. Полотно теперь висит в мире
	# листом, и щелчок идёт лучом из камеры: если это сопоставление уедет,
	# игрок будет жать мимо точек, не понимая почему. Гоним обратный путь —
	# пиксель кадра → точка на листе → экран → снова пиксель кадра.
	await _check_aim()
	# НАСКОЛЬКО ЧЕСТНА ДОГАДКА ПО ЦВЕТУ. Номерков больше нет: очередь читается
	# только по ленте, а какую из точек нужного цвета брать — решает игрок.
	# Если кандидатов всегда десяток, это не догадка, а лотерея; мерим.
	var bb = w.board
	var сумма: int = 0
	var худо: int = 0
	for i in bb.n:
		var цвет: int = -1
		for d in bb.dots:
			if int(d["idx"]) == i:
				цвет = int(d["col"])
				break
		var кандидатов: int = 0
		for d in bb.dots:
			if int(d["idx"]) >= i and int(d["col"]) == цвет:
				кандидатов += 1
		сумма += кандидатов
		худо = maxi(худо, кандидатов)
	say("догадка по цвету: точек %d, лишних %d, кандидатов в среднем %.1f, худший ход %d"
		% [bb.n, bb.dots.size() - bb.n, float(сумма) / float(maxi(1, bb.n)), худо])
	if float(сумма) / float(maxi(1, bb.n)) > 4.0:
		warn("кандидатов слишком много — это лотерея, а не догадка")
	# И тот же холст, когда он подходит: подсказка должна стать красной.
	w.board.show_near = true
	w.board.near = 0.8
	w.board.queue_redraw()
	await w.get_tree().create_timer(0.5).timeout
	await shot("холст_он_рядом")
	# И С ЩУПАЛЬЦАМИ. Надо увидеть, что закрытых точек несколько и что по ним
	# не вычислить нужную.
	w.board.show_near = false
	w.board.punish()
	await w.get_tree().create_timer(0.4).timeout
	var idxs: Array = []
	for tt in w.board.tents:
		idxs.append(int(tt["idx"]))
	say("щупальца закрыли точки %s, следующая по очереди %d" % [
		str(idxs), w.board.next_idx])
	await shot("холст_щупальца")
	# И САМ РИСУНОК. Мазок, потёки и прожиг на сдаче видно только тогда, когда
	# точки соединены, — а до сих пор ни один кадр стенда этого не показывал.
	w.board.tents.clear()
	w.board.tent_life = 0.0
	var b = w.board
	for i in b.n:
		# ЩУПАЛЬЦА СНИМАЕМ КАЖДЫЙ РАЗ: промах вызывает punish(), тот закрывает
		# нужную точку, и щелчки перестают засчитываться — первый прогон так и
		# встал на трёх точках из шести.
		b.tents.clear()
		b.tent_life = 0.0
		var цель = null
		for d in b.dots:
			if int(d["idx"]) == b.next_idx:
				цель = d
				break
		if цель == null:
			break
		b._click(b._dot_pos(цель))
		await w.get_tree().create_timer(0.16).timeout
		if i == 2:
			# Промах на третьей точке: смотрим, как течёт краска с ошибки.
			for d in b.dots:
				if int(d["idx"]) > b.next_idx:
					b._click(b._dot_pos(d))
					break
			await w.get_tree().create_timer(1.1).timeout
			await shot("холст_промах_потёк")
		if i == b.n - 3:
			await shot("холст_линия")
	say("соединено точек %d из %d, потёков %d, прожиг %.2f"
		% [b.next_idx, b.n, b.drips.size(), b.burn])
	await shot("холст_прожиг")


## Проверка прицела по холсту. Берём точки полотна, считаем, где каждая
## оказывается на экране, ставим туда курсор и смотрим, в какой пиксель кадра
## это переводит сам мир. Расхождение — это и есть промах игрока.
func _check_aim() -> void:
	var лист: Node3D = w.board_face
	var камера: Camera3D = w.get_viewport().get_camera_3d()
	if лист == null or камера == null:
		warn("прицел проверить нечем: нет листа или камеры")
		return
	var q: QuadMesh = лист.mesh
	var худо: float = 0.0
	var проверено: int = 0
	for d in w.board.dots:
		var px: Vector2 = w.board._dot_pos(d)
		var u: float = px.x / float(w.board_vp.size.x)
		var v: float = px.y / float(w.board_vp.size.y)
		# Обратное преобразование: доли листа → его местные координаты → мир.
		var loc := Vector3((u - 0.5) * q.size.x, (0.5 - v) * q.size.y, 0.0)
		var мир: Vector3 = лист.global_transform * loc
		if камера.is_position_behind(мир):
			continue
		var экран: Vector2 = камера.unproject_position(мир)
		Input.warp_mouse(экран)
		await w.get_tree().process_frame
		await w.get_tree().process_frame
		var назад := Vector2(w.board_uv.x * float(w.board_vp.size.x),
			w.board_uv.y * float(w.board_vp.size.y))
		худо = maxf(худо, назад.distance_to(px))
		проверено += 1
	say("прицел: проверено %d точек, худшее расхождение %.1f px (радиус попадания %.0f)"
		% [проверено, худо, w.board.R_HIT])
	if проверено == 0:
		warn("ни одну точку не удалось проверить — лист вне кадра")
	elif худо > w.board.R_HIT * 0.5:
		warn("курсор уезжает на %.1f px при радиусе попадания %.0f"
			% [худо, w.board.R_HIT])


## ВРЕМЕННАЯ СЦЕНА: витрина декораций. Вопрос «чему не хватает внешности»
## нельзя решить по памяти — надо посмотреть на каждую вещь при свете.
func scene_shelf() -> void:
	say("═══ ВИТРИНА ДЕКОРАЦИЙ ═══")
	w.player_node.invuln = 9999.0
	# ПОЛОТНА НЕ ОТКРЫВАТЬ. Первый прогон витрины: холст открылся у первой же
	# точки и остался поверх всех девяти кадров — снял я интерфейс, а не
	# декорации. Флаг lab для того и есть.
	w.lab = true
	if w.board != null and w.board.visible:
		w.board.abandon()
	w.monster.visible = false
	w.monster.parked = true
	# ИГРОВОЙ СВЕТ, А НЕ СТУДИЙНЫЙ. Первая витрина снималась с лампой на 22
	# единицы — она показывала, КАК СДЕЛАНА вещь, и заодно выбеливала её до
	# неузнаваемости: деревянный пюпитр вышел белой железякой. Здесь горит
	# только фонарь палочки, то есть ровно то, с чем ходит игрок.
	w.has_wand = true
	w.player_node.has_wand = true
	if w.wand_lamp != null:
		w.wand_lamp.visible = true
	if w.wand_view != null:
		w.wand_view.visible = true
	if w.dropped_wand != null:
		w.dropped_wand.queue_free()
		w.dropped_wand = null
	# ЧТО ВООБЩЕ ВИСИТ В РУКЕ. Бледная плита на кадре не менялась ни от одной
	# правки света — значит я правлю не тот предмет. Перечисляем.
	if w.wand_view != null:
		for ch in w.wand_view.get_children():
			var kind: String = ch.get_class()
			var extra: String = ""
			if ch is MeshInstance3D:
				var mm = (ch as MeshInstance3D).mesh
				extra = " меш=%s" % (mm.get_class() if mm != null else "нет")
				if mm is BoxMesh:
					extra += " размер=%s" % str((mm as BoxMesh).size)
				var mo = (ch as MeshInstance3D).material_override
				if mo is StandardMaterial3D:
					extra += " цвет=%s тень=%d" % [
						str((mo as StandardMaterial3D).albedo_color),
						(mo as StandardMaterial3D).shading_mode]
				extra += " слой=%d" % (ch as MeshInstance3D).layers
			say("в руке: %s (%s)%s видим=%s" % [ch.name, kind, extra, str(ch.visible)])
	# ЧТО СТОИТ РЯДОМ. Бледную плиту я искал четырьмя догадками подряд и все
	# четыре раза правил не тот предмет. Перебираем дерево сцены и печатаем
	# всё, что ближе двух с половиной метров, — гадать больше не о чем.
	_near_things(w, w.player_node.global_position, 2.5)
	var spots: Array = []
	if not w.canv_cells.is_empty():
		spots.append(["полотно", w.cell_to_world(w.canv_cells[0], 1.2), 3.2])
	for t in w.tables:
		spots.append(["стол с запиской", t["pos"] + Vector3(0, 0.5, 0), 2.4])
		break
	for n in w.nests:
		spots.append(["гнездо", n["pos"], 2.6])
		break
	if not w.safe_cells.is_empty():
		spots.append(["убежище", w.cell_to_world(w.safe_cells[0], 0.3), 4.0])
	for d in w.drips:
		spots.append(["капель", w.cell_to_world(d["cell"], 2.4), 3.0])
		break
	if not w.holes.is_empty():
		spots.append(["пролом", w.cell_to_world(w.holes[0], 3.0), 6.0])
	if w.climb_cell.x >= 0:
		spots.append(["насыпь", w.cell_to_world(w.climb_cell, 1.0), 5.0])
	spots.append(["стена вблизи", w.cell_to_world(w.start_cell, 1.6)
		+ Vector3(w.cell_size * 0.5, 0, 0), 1.6])
	spots.append(["выход", w.cell_to_world(w.exit_cell, 1.2), 3.4])
	for sp in spots:
		var at: Vector3 = sp[1]
		var back: float = float(sp[2])
		var pc: Vector3 = at + Vector3(0, 0, back)
		w.player_node.global_position = Vector3(pc.x, PlayerScript.STAND_Y, pc.z)
		var to: Vector3 = at - w.player_node.global_position
		w.player_node.rotation.y = atan2(-to.x, -to.z)
		w.player_node.yaw = w.player_node.rotation.y
		w.player_node.pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.2, 1.2)
		await w.get_tree().create_timer(0.6).timeout
		say("витрина: %s" % str(sp[0]))
		await shot(String(sp[0]))


func _near_things(root: Node, at: Vector3, r: float) -> void:
	var found: int = 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.global_position.distance_to(at) > r:
			continue
		var mm = mi.mesh
		var what: String = mm.get_class() if mm != null else "нет"
		if mm is BoxMesh:
			what += " " + str((mm as BoxMesh).size)
		var col: String = ""
		var mo = mi.material_override
		if mo is StandardMaterial3D:
			col = " цвет=" + str((mo as StandardMaterial3D).albedo_color)
		found += 1
		if found <= 14:
			say("рядом: %s | %s%s | %.2f м | слой %d" % [mi.name, what, col,
				mi.global_position.distance_to(at), mi.layers])
	say("рядом всего: %d" % found)


func _head_y(m) -> float:
	var sk = m.human_skel
	if sk == null or not m.hb.has("Head"):
		return -99.0
	return (sk.global_transform * sk.get_bone_global_pose(int(m.hb["Head"])).origin).y


func scene_human_walk() -> void:
	say("═══ ГУМАНОИД НА ХОДУ ═══")
	stage_clean()
	var m = w.monster
	var p = w.player_node
	w.player_node.invuln = 9999.0
	m.visible = true
	m._grow_out()
	m.drop_hold()
	m.take_form(60.0, m.FORM_HUMAN)
	# НА ПОЛ, А НЕ НА ВЫСОТУ ИГРОКА. p.global_position.y — это центр капсулы,
	# 0.85 м; поставив монстра туда, я поднял его над полом сам и потом мерил
	# «ступни в воздухе». Стенд врал, а не игра.
	m.global_position = Vector3(p.global_position.x, 0.0,
		p.global_position.z + w.cell_size * 5.0)
	# СВЕТ И ВЗГЛЯД. Без палочки в этой сцене темно совсем, а игрок стоит
	# спиной: первый прогон дал восемь чёрных кадров.
	w.has_wand = true
	p.has_wand = true
	if w.wand_lamp != null:
		w.wand_lamp.visible = true
	if w.wand_view != null:
		w.wand_view.visible = true
	var t: float = 0.0
	while t < 2.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
	var sk = m.human_skel
	var names: Array = []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	say("кости: " + ", ".join(names))
	for step in 8:
		var t2: float = 0.0
		while t2 < 0.55:
			await w.get_tree().physics_frame
			t2 += 1.0 / 60.0
			m.mode = "chase"
			m.chase_t = 99.0
			var to: Vector3 = m.global_position - p.global_position
			p.rotation.y = atan2(-to.x, -to.z)
			p.yaw = p.rotation.y
		var low: float = 1e9
		for i in sk.get_bone_count():
			var nm: String = sk.get_bone_name(i)
			if nm.to_lower().contains("foot") or nm.to_lower().contains("toe") \
					or nm.to_lower().contains("ankle"):
				var y: float = (sk.global_transform
					* sk.get_bone_global_pose(i).origin).y
				low = minf(low, y)
		var palm: String = ""
		if sk != null and m.hb.has("Palm.L") and m.hb.has("Palm.R"):
			var sd: Vector3 = m.side_dir if m.side_dir.length() > 0.1 else Vector3.RIGHT
			var pl: Vector3 = sk.global_transform * sk.get_bone_global_pose(int(m.hb["Palm.L"])).origin
			var pr: Vector3 = sk.global_transform * sk.get_bone_global_pose(int(m.hb["Palm.R"])).origin
			palm = ", ладони вбок %.2f / %.2f м (до стены %.2f)" % [
				(pl - m.global_position).dot(sd), (pr - m.global_position).dot(sd),
				w.cell_size * 0.5]
		say("кадр %d: ступня %.3f, ГОЛОВА на %.2f м (узел %.2f), масштаб %.3f/%.3f, высота %.2f, до игрока %.1f м" % [
			step, low if low < 1e8 else -99.0, _head_y(m), m.global_position.y,
			m.human.scale.x, m.human.scale.y, m.human.position.y,
			m.global_position.distance_to(p.global_position)] + palm)
		await shot("коридор_%d" % step)
	# И В ЗАЛЕ. Там он должен быть на четвереньках, а щупальца — из спины.
	if w.room_rects.is_empty():
		warn("залов на карте нет — вторую половину замера пропускаю")
		return
	var r = w.room_rects[0]
	var mid: Vector2i = Vector2i(int(r.position.x + r.size.x * 0.5),
		int(r.position.y + r.size.y * 0.5))
	p.global_position = w.cell_to_world(mid, PlayerScript.STAND_Y)
	m.global_position = w.cell_to_world(mid, 0.0) + Vector3(0, 0, w.cell_size * 2.2)
	for step2 in 3:
		var t3: float = 0.0
		while t3 < 0.7:
			await w.get_tree().physics_frame
			t3 += 1.0 / 60.0
			m.mode = "chase"
			m.chase_t = 99.0
			var to2: Vector3 = m.global_position - p.global_position
			p.rotation.y = atan2(-to2.x, -to2.z)
			p.yaw = p.rotation.y
		say("зал, кадр %d: тесно=%s, приседание %.2f, ГОЛОВА на %.2f м, до игрока %.1f м" % [
			step2, str(m.cramped), m.crawl_k, _head_y(m),
			m.global_position.distance_to(p.global_position)])
		await shot("зал_%d" % step2)


func scene_forms() -> void:
	stage_clean()
	var m = w.monster
	m.visible = true
	m._grow_out()
	m.drop_hold()
	await w.get_tree().create_timer(0.4).timeout
	var blob_h: float = m.blob.global_position.y + m.BLOB_R * m.MANTLE_H * m.body.scale.y
	say("ком: верх на %.2f м, рук %d, глаз %d" % [blob_h, m.arms.size(),
		m.eye_dirs.size()])
	await shot("form_blob")
	m.take_form(30.0, m.FORM_HUMAN)
	var t: float = 0.0
	while t < 2.5:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
	if m.human == null:
		warn("вторая форма не собралась: модель не загрузилась")
		return
	var sk = m.human_skel
	var head: float = (sk.global_transform
		* sk.get_bone_global_pose(sk.find_bone("Head")).origin).y
	var hand: float = (sk.global_transform
		* sk.get_bone_global_pose(sk.find_bone("Palm.L")).origin).y
	say("фигура: голова на %.2f м, кисть на %.2f м, пасть открыта на %.2f" % [
		head, hand, m.mouth_open])
	if m.blob.visible:
		warn("ком остался видимым, когда фигура уже встала")
	if m.core_mesh != null and m.core_mesh.visible:
		warn("ядро кома видно у фигуры — это тот самый шарик между ног")
	check_now("фигура")
	await shot("form_human")


## Проиграть атаку и проверить, что она КОНЧИЛАСЬ. Незавершённая атака — это
## зависшая игра, и поймать это можно только по времени.
func scene_attack(kind: String, seconds: float) -> void:
	var w2 = w
	var before: bool = w2.player_node.is_physics_processing()
	match kind:
		"руки с потолка":
			w2._start_human_attack()
		"язык":
			w2._human_tongue()
		"удар о стену":
			# Теперь это ЗАСАДА, и бьёт он из конкретной стены — значит стенду
			# надо саму стену и назвать. Берём соседнюю с игроком каменную клетку.
			var pc2: Vector2i = w2.world_to_cell(w2.player_node.global_position)
			var wall: Vector2i = pc2
			for d3 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if w2.maze.is_wall(pc2.x + d3.x, pc2.y + d3.y):
					wall = pc2 + d3
					break
			if wall == pc2:
				warn("рядом с игроком нет стены — засаде неоткуда бить")
			else:
				w2.monster.global_position = w2.cell_to_world(wall)
				w2.monster.mode = "inwall"
				w2._start_slam(wall)
		"хват":
			w2._grab_now("тест", "monster")
	var t: float = 0.0
	while t < seconds:
		await w2.get_tree().physics_frame
		t += 1.0 / 60.0
		if int(t * 60.0) % 30 == 0:
			check_now(kind)
	say("атака «%s»: %.0f с спустя окно борьбы %s, стадии удара %d, руки %d" % [
		kind, seconds, str(w2.grab_ui.visible), w2.slam_stage, w2.hf_stage])
	await shot("attack_" + kind.replace(" ", "_"))
	# Возвращаем управление, чтобы следующая сцена началась чисто.
	if w2.grab_ui.visible:
		w2.grab_ui._end(true)
	w2.slam_stage = 0
	w2.hf_stage = 0
	w2.lift_on = false
	w2._freeze_player(false)
	# Атака могла оттащить игрока куда угодно — возвращаем на пол, иначе
	# следующая проверка ругается на положение, созданное предыдущей.
	var pc2: Vector2i = w2.world_to_cell(w2.player_node.global_position)
	if w2.maze.is_wall(pc2.x, pc2.y):
		w2.player_node.global_position = w2.cell_to_world(w2.start_cell, PlayerScript.STAND_Y)
	if before and not w2.player_node.is_physics_processing():
		warn("после атаки «%s» управление не вернулось само" % kind)


## ─────────────────────────── прогон ───────────────────────────
##
## Сценарии перечислены строками — их же можно набрать в командной строке:
##   Godot --path . -- бот фаза3 погоня формы атаки полотно
## Без списка гоняется всё.
func run(want: Array) -> void:
	await w.get_tree().create_timer(1.0).timeout
	# Не через кнопку: «проснуться» ведёт в комнату-пролог, сцена сменится и
	# стенд останется работать на выброшенном из дерева мире.
	w.start_ui.skip()
	w._on_start()
	# После смерти игрок уже там, где его поставила игра: не трогаем.
	if not _died_once:
		w.player_node.global_position = w.cell_to_world(w.start_cell, PlayerScript.STAND_Y)
	w.player_node.invuln = 9999.0
	await w.get_tree().create_timer(0.3).timeout
	var all: bool = want.is_empty()
	check_sound()
	if all or want.has("фаза1"):
		set_phase(1)
		check_now("фаза 1")
	if all or want.has("полотно"):
		var goal: Vector2i = w.canv_cells[w.done]
		var ok: bool = await goto_cell(goal, 30.0)
		say("дошёл до полотна: %s" % str(ok))
		await shot("canvas")
	if all or want.has("фаза3"):
		set_phase(3)
	if want.has("клавиша"):
		await scene_key_form()
	if want.has("витрина"):
		await scene_shelf()
	if want.has("холст"):
		await scene_board_shot()
	# «слепая» — то же полотно, но четвёртое: на нём стоит помеха «порядок
	# скрыт», и лента там читается иначе. Играющий увидел её как поломку
	# («цвета чёрные, пока не попал по точке») — значит ленту надо уметь
	# снимать отдельно, а не выяснять это с его слов.
	if want.has("добивание"):
		await scene_fatality()
	if want.has("собака"):
		await scene_dog()
	if want.has("тишина"):
		await scene_hush()
	if want.has("края"):
		await scene_edges()
	if want.has("набег"):
		await scene_raid()
	if want.has("рывок"):
		await scene_face_jump()
	if want.has("затишье"):
		await scene_calm()
	if want.has("слепая"):
		w.done = 3
		await scene_board_shot()
	# «брожение» — две с половиной минуты, «брожение9» — девять. Длинное нужно
	# затем, что по часам фазы наступают на 420-й и 900-й секунде, а стенд
	# проходит игру за три минуты и до них не доживает. Настоящая сессия ближе
	# к девяти минутам, чем к трём.
	for a in want:
		var an: String = str(a)
		if an.begins_with("брожение"):
			var tail: String = an.substr("брожение".length())
			await scene_wander(float(tail) if tail.is_valid_float() else 2.5)
			break
	if want.has("убегание"):
		await scene_flee()
	if want.has("рост"):
		await scene_height()
	if want.has("линия"):
		await scene_line()
	if want.has("началокадры"):
		await scene_start_shots()
	if want.has("подъём"):
		await scene_climb_feel()
	if want.has("опись"):
		await scene_inventory()
	if want.has("хронометраж"):
		await scene_timing()
	if want.has("темп"):
		await scene_tempo()
	if want.has("протечка"):
		await scene_sun_leak()
	if want.has("вид"):
		await scene_climb_view()
	if want.has("убежище2"):
		await scene_flee_line()
	if want.has("нырок"):
		await scene_dive()
	if want.has("хлест"):
		await scene_bursts()
	if want.has("походка"):
		await scene_human_walk()
	if all or want.has("формы"):
		await scene_forms()
	if want.has("цена"):
		await scene_cost()
	if want.has("сетка"):
		await scene_mesh()
	if want.has("край"):
		await scene_edge()
	if all or want.has("лезвие"):
		await scene_blade()
	if all or want.has("поимка"):
		await scene_catch(want.has("гуманоид"))
	if want.has("пересидеть"):
		say("═══ СКОЛЬКО МОЖНО СТОЯТЬ В УБЕЖИЩЕ ═══")
		stage_clean()
		var p6 = w.player_node
		var m6 = w.monster
		p6.invuln = 0.0
		m6.visible = false
		m6.mode = "inwall"
		m6.resurface_t = 9999.0
		# GRACE: до 45-й секунды не бьёт ничего, ждать её честно — это и есть
		# условия игры.
		while w._clock < w.GRACE + 1.0:
			await w.get_tree().create_timer(0.5).timeout
		# 1. СТАРТОВАЯ КОМНАТА. Там записка и палочка, новичок стоит и читает.
		p6.global_position = w.cell_to_world(w.start_cell, PlayerScript.STAND_Y)
		var ударов: int = 0
		var t6: float = 0.0
		while t6 < 40.0:
			await w.get_tree().create_timer(0.5).timeout
			t6 += 0.5
			if w.grab_ui.visible:
				ударов += 1
				w.grab_ui._end(true)
		say("  на старте у стола, 40 с: ударов %d (ждём 0)" % [ударов])
		if ударов > 0:
			warn("стартовая комната бьёт, пока игрок ещё читает записку")
		# 2. ДРУГОЕ УБЕЖИЩЕ, погони нет: одно треснувшее за визит.
		var уб: Vector2i = w.safe_cells[1] if w.safe_cells.size() > 1 else w.safe_cells[0]
		p6.global_position = w.cell_to_world(уб, PlayerScript.STAND_Y)
		p6.invuln = 0.0
		ударов = 0
		var когда: Array = []
		t6 = 0.0
		while t6 < 75.0:
			await w.get_tree().create_timer(0.5).timeout
			t6 += 0.5
			if w.grab_ui.visible:
				ударов += 1
				когда.append(t6)
				w.grab_ui._end(true)
		say("  в убежище 75 с без погони: ударов %d, на секундах %s (ждём 1)" % [ударов, str(когда)])
		if ударов != 1:
			warn("за визит в убежище должно треснуть ровно один раз")
		# 3. ТА ЖЕ КОМНАТА, НО ИДЁТ ПОГОНЯ: убежище обязано защищать целиком.
		p6.global_position = w.cell_to_world(уб, PlayerScript.STAND_Y)
		p6.invuln = 0.0
		w.safe_used = false
		w.safe_sit = 0.0
		m6.visible = true
		m6.mode = "chase"
		m6.global_position = w.cell_to_world(w._far_cell_from(уб))
		m6.parked = true
		ударов = 0
		t6 = 0.0
		while t6 < 45.0:
			await w.get_tree().create_timer(0.5).timeout
			t6 += 0.5
			m6.mode = "chase"
			m6.visible = true
			if w.grab_ui.visible:
				ударов += 1
				w.grab_ui._end(true)
		say("  в убежище 45 с во время погони: ударов %d (ждём 0)" % [ударов])
		if ударов > 0:
			warn("убежище бьёт во время погони — тогда это не убежище")
	if want.has("мольберт"):
		say("═══ ЧТО ВИДНО НА ХОЛСТЕ ИЗДАЛЕКА ═══")
		stage_clean()
		var p7 = w.player_node
		p7.invuln = 9999.0
		w.monster.visible = false
		w.monster.mode = "inwall"
		w.monster.resurface_t = 9999.0
		await w.get_tree().create_timer(1.0).timeout
		# ПЕРЕД ХОЛСТОМ, А НЕ СБОКУ. У мольберта случайный поворот, и «встать в
		# двух метрах по X» — это встать к нему ребром: на кадре были три палки
		# с торца, и судить по нему было не о чем.
		var холст: MeshInstance3D = w.canv_marks[0]
		# ЛИЦЕВАЯ СТОРОНА ХОЛСТА — ПО +Z: туда он и смотрит на мольберте.
		var перед: Vector3 = холст.global_transform.basis.z.normalized()
		# Физику выключаем: иначе тело выталкивает из мольберта и стены, и
		# камера уезжает туда, где смотреть не на что.
		p7.set_physics_process(false)
		# Голову ведём сами: сценарный взгляд у стенда то включён, то нет, а
		# кадр нужен ровно один — в холст.
		# СНИМАЕМ СРАЗУ. Мир каждый кадр возвращает игроку физику, и тело
		# выталкивает от мольберта: если ждать секунду, камера уезжает.
		for _q in 3:
			p7.global_position = холст.global_position + перед * 4.6
			p7.global_position.y = холст.global_position.y \
				+ (PlayerScript.STAND_Y - PlayerScript.EYE_Y)
			p7.aim_head(холст.global_position, 40.0, 0.2)
			await w.get_tree().process_frame
		p7.global_position = холст.global_position + перед * 4.6
		p7.global_position.y = холст.global_position.y \
			+ (PlayerScript.STAND_Y - PlayerScript.EYE_Y)
		p7.aim_head(холст.global_position, 40.0, 0.2)
		# И ВЗВОД СНИМАЕМ: иначе игра откроет полотно, стоит подойти ближе
		# трёх с половиной метров, и в кадре будет открытый лист.
		w.canvas_arm = false
		# ПОЛОТНО ЗАКРЫВАЕМ. Проходя мимо, бот открывает его сам, а открытое
		# полотно ПРЯЧЕТ холст мольберта — и в кадре остаются три палки.
		if w.board != null and w.board.visible:
			w._close_board()
		if w.board_face != null:
			w.board_face.visible = false
		if w.board_easel != null:
			w.board_easel.visible = true
		var мат: StandardMaterial3D = холст.material_override
		say("холст: размер %s, положение %s" % [
			str((холст.mesh as BoxMesh).size), str(холст.global_position)])
		say("холст: виден %s, в дереве %s, детей %d, свечение %.2f, цвет %s" % [
			str(холст.visible), str(холст.is_visible_in_tree()),
			холст.get_child_count(), мат.emission_energy_multiplier,
			str(мат.albedo_color)])
		say("снимок на холсте: %s" % [str(мат.albedo_texture != null)])
		if мат.albedo_texture == null:
			warn("на мольберте нет картинки полотна")
		в_кадре(холст.global_position, "холст")
		await shot("мольберт_издали")
	if want.has("видение"):
		say("═══ КАРТИНКИ ЗА ПОЛОТНАМИ ═══")
		stage_clean()
		w.player_node.invuln = 9999.0
		w.monster.visible = false
		w.monster.mode = "inwall"
		w.monster.resurface_t = 9999.0
		for n in 7:
			if not w.vision_ui.есть(n):
				warn("нет картинки для полотна %d" % [n + 1])
				continue
			var t9: Texture2D = w.vision_ui._tex_for(n)
			say("картинка %d: %s, размер %dx%d" % [n + 1,
				str(t9.resource_path if t9 != null else "нет"),
				t9.get_width() if t9 != null else 0,
				t9.get_height() if t9 != null else 0])
			w.vision_ui.show_one(n)
			await w.get_tree().create_timer(3.0).timeout
			await shot("видение_%d" % (n + 1))
			w.vision_ui._close()
			await w.get_tree().create_timer(0.3).timeout
	if want.has("зрение"):
		say("═══ КАДР ЧИСЛАМИ: ЧТО ВИДНО БЕЗ ГЛАЗ ═══")
		stage_clean()
		var p5 = w.player_node
		var m5 = w.monster
		# Неуязвимость и парковка: сцена показательная, тварь должна стоять там,
		# куда её поставили, и не хватать бота.
		p5.invuln = 9999.0
		m5.visible = true
		m5.mode = "chase"
		m5.path.clear()
		m5.parked = true
		m5.prowl = false
		if _line.is_empty():
			_find_line()
		var mid5: int = _line.size() / 2
		# В КОРИДОРЕ, А НЕ В СТАРТОВОМ ТУПИКЕ. Первая версия ставила тварь «в
		# трёх метрах перед игроком», а там камень: страховка «в камне стоять
		# нельзя» выталкивала её на ближайший пол — ровно на игрока, и замер
		# мерил камеру внутри туши.
		p5.global_position = w.cell_to_world(_line[mid5], PlayerScript.STAND_Y)
		m5.global_position = w.cell_to_world(_line[mid5 + 1])
		p5.look_force(m5.look_point(), 5.0, 30.0)
		await w.get_tree().create_timer(1.2).timeout
		в_кадре(m5.look_point(), "тварь впереди")
		await shot("зрение_впереди")
		# 2. Та же тварь за спиной: разворачиваем игрока.
		p5.look_force(p5.global_position
			+ (p5.global_position - m5.global_position).normalized() * 10.0, 5.0, 30.0)
		await w.get_tree().create_timer(1.2).timeout
		в_кадре(m5.look_point(), "тварь за спиной")
		# 3. И за камнем: ищем клетку пола, которую от игрока закрывает стена.
		var спрятан: Vector2i = Vector2i(-1, -1)
		for r5 in w.maze.size.y:
			for c5 in w.maze.size.x:
				if спрятан.x >= 0 or w.maze.is_wall(r5, c5):
					continue
				var точка: Vector3 = w.cell_to_world(Vector2i(r5, c5))
				var д: float = точка.distance_to(p5.global_position)
				if д > 4.0 and д < 26.0 and not w._clear_line(p5.camera.global_position, точка):
					спрятан = Vector2i(r5, c5)
		if спрятан.x >= 0:
			m5.global_position = w.cell_to_world(спрятан)
			p5.look_force(m5.look_point(), 5.0, 30.0)
			await w.get_tree().create_timer(1.2).timeout
			в_кадре(m5.look_point(), "тварь за стеной")
			await shot("зрение_за_стеной")
		else:
			warn("не нашёл клетку за стеной — проверка неполная")
	if want.has("звон"):
		say("═══ ВЫБИТАЯ ПАЛОЧКА ЗВЕНИТ ═══")
		stage_clean()
		w.monster.visible = false
		w.monster.mode = "inwall"
		w.monster.resurface_t = 999.0
		w.has_wand = true
		w.player_node.has_wand = true
		w._drop_wand()
		var wp: Vector3 = w.dropped_wand.global_position
		w.player_node.global_position += (w.player_node.global_position - wp).normalized() * 3.0
		w.sfx.watch = true
		w.sfx.heard.clear()
		await w.get_tree().create_timer(6.0).timeout
		var звонов: int = 0
		for h in w.sfx.heard:
			if h["имя"] == "link" and h["из точки"] and (h["где"] as Vector3).distance_to(wp) < 0.1:
				звонов += 1
		say("за 6 с звенела %d раз из места, где лежит" % [звонов])
		if звонов < 3:
			warn("палочка почти не звенит")
		await w.get_tree().create_timer(36.0).timeout
		say("через 42 с: палочка в руке %s, на полу %s" % [str(w.has_wand), str(w.dropped_wand != null)])
		if not w.has_wand:
			warn("палочка сама не вернулась")
	if want.has("смерть"):
		await scene_death()
	if want.has("стол"):
		var p4 = w.player_node
		var t0 = w.tables[w.tables.size() - 1]
		for tt in w.tables:
			if tt["wand"]:
				t0 = tt
		p4.global_position = Vector3(t0["pos"].x - 0.3, PlayerScript.STAND_Y, t0["pos"].z + 1.3)
		p4.look_force(t0["pos"] + Vector3(0.3, 1.0, 0.0), 30.0, 30.0)
		await w.get_tree().create_timer(1.5).timeout
		say("палочка на столе: %s" % [str(t0.has("wand_node") and t0["wand_node"].visible)])
		await shot("стол_палочка")
		w._read_table()
		await w.get_tree().create_timer(0.5).timeout
		say("после E: на столе %s, в руке %s" % [str(t0["wand_node"].visible), str(w.has_wand)])
	if want.has("снег"):
		stage_clean()
		w.monster.visible = false
		w.monster.mode = "inwall"
		var p3 = w.player_node
		# Не под самим проломом (там небо и снег законно виден сверху), а в
		# соседней клетке под потолком: снег здесь — это и есть протечка.
		var hc: Vector2i = w.holes[0]
		var spot: Vector2i = hc
		for d in [Vector2i(0, 2), Vector2i(2, 0), Vector2i(0, -2), Vector2i(-2, 0), Vector2i(0, 1), Vector2i(1, 0)]:
			if not w.maze.is_wall(hc.x + d.x, hc.y + d.y):
				spot = hc + d
				break
		p3.global_position = w.cell_to_world(spot, PlayerScript.STAND_Y)
		p3.look_force(w.cell_to_world(spot, 3.5) + Vector3(0.3, 0, 0.3), 30.0, 30.0)
		await w.get_tree().create_timer(15.0).timeout
		await shot("снег_потолок")
		p3.look_force(w.cell_to_world(hc, 1.0), 5.0, 30.0)
		await w.get_tree().create_timer(1.0).timeout
		await shot("снег_пролом")
	if want.has("меню"):
		w.start_ui.visible = true
		w.start_ui.set_process(true)
		await w.get_tree().create_timer(0.6).timeout
		await shot("меню_старт")
		w.start_ui.settings.emit()
		await w.get_tree().create_timer(0.6).timeout
		say("меню настроек: видно %s, режим меню %s, стартовый экран виден %s" % [
			str(w.pause_ui.visible), str(w.pause_ui.menu_mode), str(w.start_ui.visible)])
		await shot("меню_настройки")
		w.pause_ui._go(2)
		await w.get_tree().create_timer(0.3).timeout
		await shot("меню_как_играть")
		w.pause_ui._go(0)
		w.pause_ui._on_resume()
		await w.get_tree().create_timer(0.3).timeout
		say("после «назад»: стартовый экран %s, меню %s" % [str(w.start_ui.visible), str(w.pause_ui.visible)])
		w.start_ui.skip()
		w._open_pause()
		await w.get_tree().create_timer(0.6).timeout
		await shot("меню_пауза")
		w._open_pause()
	if want.has("скорость"):
		say("═══ СКОРОСТЬ ПОГОНИ: ОКНО ПОСЛЕ ВЫРЫВА ═══")
		if _line.is_empty():
			_find_line()
		for вариант in [[false, true], [true, true], [false, false], [true, false]]:
			var окно: bool = вариант[0]
			var рывок: bool = вариант[1]
			stage_clean()
			var p2 = w.player_node
			var m2 = w.monster
			p2.invuln = 999.0
			p2.global_position = w.cell_to_world(_line[_line.size() - 1], PlayerScript.STAND_Y)
			m2.global_position = w.cell_to_world(_line[0])
			m2.visible = true
			m2.mode = "chase"
			m2.chase_t = 60.0
			m2.path.clear()
			var t2: float = 0.0
			var from: Vector3 = m2.global_position
			while t2 < 4.0:
				await w.get_tree().physics_frame
				t2 += 1.0 / 60.0
				p2.sprint_left = 5.0 if рывок else 0.0
				m2.chase_t = 60.0
				m2.slow_t = 5.0 if окно else 0.0
				if t2 < 1.0:
					from = m2.global_position
			var v: float = from.distance_to(m2.global_position) / 3.0
			say("  %s, %s: тварь %.2f м/с, игрок %.2f м/с" % [
				"рывок" if рывок else "трусца", "с окном" if окно else "без окна", v,
				p2.speed * (p2.sprint_mul if рывок else p2._jog_now)])
	if want.has("убежать"):
		await scene_run_away(want.has("без_окна"))
	if want.has("шкатулка"):
		stage_clean()
		w.monster.visible = false
		w.monster.mode = "inwall"
		await w.get_tree().create_timer(4.0).timeout
		var bp: AudioStreamPlayer = w.sfx._box_player
		say("шкатулка без твари: играет %s, %.1f дБ, тон %.2f, шина %s (%.1f дБ); музыка %.1f дБ" % [
			str(bp.playing), bp.volume_db, bp.pitch_scale, bp.bus,
			AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bp.bus)),
			w.sfx._mus_calm.volume_db])
		w.monster.mode = "chase"
		w.monster.visible = true
		w.monster.global_position = w.player_node.global_position + Vector3(6, 0, 0)
		await w.get_tree().create_timer(2.5).timeout
		say("шкатулка с тварью рядом: играет %s, %.1f дБ" % [str(bp.playing), bp.volume_db])
	if want.has("яркость"):
		await scene_gamma()
	if want.has("финал"):
		await scene_finale()
	if want.has("поимки"):
		await scene_catches()
	if all or want.has("вырвался"):
		await scene_after_escape()
	if all or want.has("силуэт"):
		await scene_silhouette()
	if all or want.has("взмахи"):
		await scene_swings()
	if all or want.has("дверь"):
		await scene_final_door()
	if all or want.has("шаги"):
		await scene_draw_sound()
	if want.has("слышно") or want.has("слышно2"):
		await scene_chase_sound(2)
	if want.has("слышно") or want.has("слышно3"):
		await scene_chase_sound(3)
	if all or want.has("погоня"):
		w.monster.drop_hold()
		w.monster.form_hold = 0.0
		await scene_chase(6.0)
	if all or want.has("фигуры"):
		# Открываем полотно и смотрим, что на нём: имя фигуры, число точек,
		# и рисуется ли она одним росчерком (нет ли прыжков через пол-листа).
		w.player_node.global_position = w.cell_to_world(w.canv_cells[w.done], PlayerScript.STAND_Y)
		w._open_board()
		await w.get_tree().create_timer(0.5).timeout
		say("полотно открыто: %s" % str(w.board.visible))
		# pick(rng) отдаёт СРАЗУ ВЕСЬ набор на забег, а не одну фигуру по номеру.
		var set_ := Shapes.pick(w._rng)
		for i in set_.size():
			var sh: Dictionary = set_[i]
			var pts: Array = sh["pts"]
			var jump: float = 0.0
			for k in range(pts.size() - 1):
				jump = maxf(jump, (pts[k + 1] - pts[k]).length())
			say("%d: «%s», точек %d, самый длинный отрезок %.2f" % [
				i, sh["name"], pts.size(), jump])
			if jump > 0.75:
				warn("в фигуре «%s» есть прыжок через весь лист" % sh["name"])
		await shot("board")
		w.board.visible = false
	if all or want.has("проход"):
		await scene_walk_all()
	if all or want.has("палочка"):
		await scene_wand()
	if all or want.has("убежище"):
		await scene_shelter()
	if want.has("качество"):
		await scene_quality()
	if all or want.has("кадры"):
		await scene_fps()
	if want.has("фото"):
		await scene_photo()
	if want.has("стены"):
		await scene_ghost()
	if want.has("карта"):
		await scene_map()
	if want.has("почему"):
		await scene_why()
	if all or want.has("обвал"):
		await scene_climb()
	if all or want.has("жижа"):
		await scene_goo()
	for phn in [0, 1, 2, 3]:
		if want.has("проход%d" % phn):
			await scene_full(phn)
	if all or want.has("атаки"):
		stage_clean()
		w.monster.take_form(30.0, w.monster.FORM_HUMAN)
		await w.get_tree().create_timer(1.5).timeout
		for a in ["руки с потолка", "язык"]:
			await scene_attack(a, 4.0)
		w.monster.drop_hold()
		w.monster.form_hold = 0.0
		await w.get_tree().create_timer(1.5).timeout
		for a2 in ["удар о стену", "хват"]:
			await scene_attack(a2, 4.0)
	_report()


## ─────────────────────── полный проход ───────────────────────
##
## Не проверка отдельной сцены, а ИГРА целиком: от старта до выхода, со всеми
## полотнами по очереди. Всё, что попадётся по дороге — хват, удар о стену,
## руки с потолка, обвал, жижа, смерть, — считаем и складываем в отчёт.
func _watch() -> void:
	var was := {}
	while watching:
		await w.get_tree().process_frame
		if w.player_node == null:
			continue
		if w.player_node.sprint_left > 0.0:
			sprint_s += w.get_process_delta_time()
		# ПОЯВЛЕНИЕ — это переход «её не видно» -> «видно». Считаем промежутки
		# между такими переходами: именно их игрок и ощущает как ритм.
		if tempo_watch and w.monster != null:
			var out_now: bool = w.monster.visible and w.monster.mode != "inwall"
			if out_now and not tempo_seen:
				if tempo_last > 0.0:
					tempo_gaps.append(w._clock - tempo_last)
				tempo_last = w._clock
			tempo_seen = out_now
		# ПОЛОТНО ОТКРЫЛОСЬ — РИСУЕМ. Оно открывается само, когда подошёл, в том
		# числе посреди дороги. Бот этого не замечал: стоял с открытым полотном,
		# таймер выходил, два провала подряд — и полотно УБЕГАЛО в другое место,
		# после чего бот честно стоял на пустом месте и ждал.
		if w.board != null and w.board.visible and not _drawing:
			_drawing = true
			ev["рисовал"] = int(ev.get("рисовал", 0)) + 1
			await solve_board()
			_drawing = false
			continue
		# КАРТИНКУ ЗАКРЫВАЕМ. После сданного полотна на весь экран проступает
		# кадр чужой истории; человек его смотрит, а стенд меряет игру — иначе
		# он будет стоять столбом по семь секунд на каждом полотне.
		if w.vision_ui != null and w.vision_ui.visible:
			ev["картинка"] = int(ev.get("картинка", 0)) + 1
			# Первую снимаем: так видно, что показывается на самом деле.
			if not was.get("снял_картинку", false):
				was["снял_картинку"] = true
				await w.get_tree().create_timer(3.0).timeout
				await shot("проход_картинка")
			w.vision_ui._close()
			continue
		# КАДР МОЛЬБЕРТА ПО ДОРОГЕ. Самый честный способ увидеть полотно так,
		# как его видит игрок: подходя к нему своими ногами.
		if not was.get("мольберт", false) and w.done < w.canv_cells.size():
			var до: float = w.player_node.global_position.distance_to(
				w.cell_to_world(w.canv_cells[w.done], PlayerScript.STAND_Y))
			if до < 3.6 and до > 2.2:
				was["мольберт"] = true
				say("кадр мольберта: до полотна %.1f м" % [до])
				await shot("проход_мольберт")
		# Хватают — ВЫРЫВАЕМСЯ. Именно так это и задумано: не ждать, а жать.
		if w.grab_ui != null and w.grab_ui.visible:
			# КАДР ХВАТА В НАСТОЯЩЕЙ ИГРЕ. Отдельная сцена «поимка» снимает хват
			# в чистых условиях, и там щупальца видны, а играющий в игре видел
			# «только точки». Поэтому первые 0.8 с не режем и снимаем кадр.
			if not was.get("хват", false):
				_grab_since = w._clock
			var прошло: float = w._clock - _grab_since
			if прошло < 0.8:
				if прошло > 0.7 and _grab_shots < 4 and not was.get("снят", false):
					was["снят"] = true
					_grab_shots += 1
					say("кадр хвата %d: фаза %d, форма %d, безумие %d" % [_grab_shots,
						w.phase, w.monster.form_kind, w._madness_stage()])
					await shot("проход_хват_%d" % _grab_shots)
				if not was.get("хват", false):
					ev["хват"] = int(ev.get("хват", 0)) + 1
					if _last_grab > 0.0:
						gaps.append(w._clock - _last_grab)
					_last_grab = w._clock
				was["хват"] = true
				continue
			was["снят"] = false
			# РЕЖЕТ ТЕМ ЖЕ КОДОМ, ЧТО И ИГРОК. Мышью стенд не водит, но
			# bot_slash строит настоящий взмах поперёк петли и прогоняет его
			# через ту же проверку попадания: подменить хват «зачётом» значило
			# бы мерить не игру, а свою доброту к себе.
			w.grab_ui.bot_slash()
			if not was.get("хват", false):
				ev["хват"] = int(ev.get("хват", 0)) + 1
				# СКОЛЬКО ПОКОЯ МЕЖДУ ХВАТАМИ. Само число хватов о балансе не
				# говорит: я жму на вырывание каждым кадром и выскакиваю за
				# доли секунды, чего человек не может. А вот промежуток между
				# ними — честная величина: после вырывания даётся 3.2 с
				# неуязвимости, и если промежутки заметно короче, значит хват
				# приходит откуда-то мимо этой проверки.
				if _last_grab > 0.0:
					gaps.append(w._clock - _last_grab)
				_last_grab = w._clock
			was["хват"] = true
		else:
			was["хват"] = false
		# ПОЙМАЛИ — СЧИТАЕМ И ИДЁМ ДАЛЬШЕ. Три поимки подряд — это конец игры и
		# перезагрузка сцены; вместе со сценой умирает и стенд, и проход
		# обрывался на втором полотне без единого слова. Для прогона поимки
		# считаем сами и обнуляем счётчик смерти — иначе проверить всю игру
		# нельзя в принципе.
		if w.streak > 0 or w.mon_kills > 0:
			ev["поймали"] = int(ev.get("поймали", 0)) + w.streak + w.mon_kills
			w.streak = 0
			w.mon_kills = 0
		for pair in [["удар о стену", w.slam_stage > 0], ["руки с потолка", w.hf_stage > 0],
				["ФИГУРА ГУМАНОИДА", w.monster != null
					and w.monster.form_kind == w.monster.FORM_HUMAN
					and w.monster.form_t > 0.5],
				["поднял над полом", w.lift_on],
				["обвал", w.climb_state > 0], ["жижа на экране", w.goo_amt > 0.6],
				["протёр глаза", w.goo_wipe > 0.0], ["выброс в коридор", w.drop_t > 0.0]]:
			var k: String = pair[0]
			var on: bool = pair[1]
			if on and not was.get(k, false):
				ev[k] = int(ev.get(k, 0)) + 1
			was[k] = on
		# ФАЗЫ. Их три, они наступают по времени или по полотнам, и увидеть их
		# в отчёте надо ОТДЕЛЬНО: «сдано семь из семи» одинаково выглядит и
		# когда игру прошли под тремя фазами, и когда под нулевой.
		if w.phase != ph_last:
			ph_last = w.phase
			ph_log.append("%d на %.0f с" % [w.phase, w._clock])
		# МОНСТР: ВЫШЕЛ ЛИ ОН ВООБЩЕ. Все остальные счётчики считают, что он уже
		# в коридоре. Но до третьей фазы он сидит в камне, и если игрок успевает
		# сдать полотна раньше, чем истечёт INWALL_CAP, то ничего из этого
		# просто не наступает. Расстояние сквозь камень — единственное, что
		# показывает, был ли он рядом или карта развела их по углам.
		if w.monster != null and w.player_node != null:
			if not w.monster.first_out:
				mon_out = true
			var dc: float = w.monster.global_position.distance_to(
				w.player_node.global_position) / w.cell_size
			mon_near = minf(mon_near, dc)
			# В КАМНЕ ОН НЕ ЛОВИТ. Поимка проверяется только в ветке коридора,
			# поэтому «подошёл на 0.3 клетки» сквозь стену ничего не значит:
			# честны лишь секунды в коридоре и расстояние, взятое там же.
			if w.monster.mode != "inwall":
				var dt: float = w.get_process_delta_time()
				mon_out_s += dt
				mon_out_near = minf(mon_out_near, dc)
				# ЧТО МЕШАЕТ ХВАТУ. Он стоит вплотную восемьдесят секунд и не
				# трогает — значит _on_caught выходит досрочно. Причин там
				# несколько, и пока не знаешь КАКАЯ, чинить нечего. Считаем
				# секунды дотягивания по виновнику.
				if dc * w.cell_size < w.monster.CATCH_DIST:
					var why: String = "ничего не мешало"
					if w.board != null and w.board.visible:
						why = "открыто полотно"
					elif w.note_ui != null and w.note_ui.visible:
						why = "открыта записка"
					elif w.scare_ui != null and w.scare_ui.visible:
						why = "испуг на экране"
					elif w.reel_t > 0.0:
						why = "подтягивание"
					elif w.player_node.invuln > 0.0:
						why = "неуязвимость после вырывания"
					elif w.safe_cells.has(w.world_to_cell(w.player_node.global_position)):
						why = "игрок в убежище"
					reach[why] = float(reach.get(why, 0.0)) + dt
		# Инварианты — на ходу, а не раз в сцену.
		if int(ev.get("_tick", 0)) % 90 == 0:
			check_now("проход")
		ev["_tick"] = int(ev.get("_tick", 0)) + 1


## Решаем полотно так же, как человек: по одной точке в порядке номеров.
func solve_board(limit: float = 40.0) -> bool:
	var b = w.board
	if b == null or not b.visible:
		return false
	var t: float = 0.0
	var last_idx: int = -1
	var stall: float = 0.0
	while b.visible and t < limit:
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
		for d in b.dots:
			if int(d["idx"]) == b.next_idx and not bool(d["done"]):
				if not b.blocked(int(d["idx"])):
					b._click(b._dot_pos(d))
				break
		if b.next_idx == last_idx:
			stall += w.get_process_delta_time()
			if stall > 2.0:
				warn("полотно не принимает нажатия: стоим на точке %d из %d" % [b.next_idx, b.n])
				return false
		else:
			last_idx = b.next_idx
			stall = 0.0
	return not b.visible


## СБЕЖАТЬ И ПЕРЕЖДАТЬ. То же, что делает игрок, когда за ним бегут: уходит в
## убежище и там пережидает. Без этого бот стоял у мольберта и ждал холста,
## которого правила ему сейчас не дадут.
func _flee_and_wait() -> void:
	var safe: Vector2i = w.active_safe
	if safe.x < 0 and not w.safe_cells.is_empty():
		safe = w.safe_cells[0]
	if safe.x >= 0:
		await goto_cell(safe, 40.0, true)
	var t: float = 0.0
	while w._chased_now() and t < 20.0:
		await w.get_tree().process_frame
		t += w.get_process_delta_time()


## Клетка ТЕКУЩЕГО полотна — или (-1,-1), если все сданы. Отдельная функция,
## потому что done меняется в чужой корутине: сторож дорисовывает полотно ровно
## между двумя моими строчками, done становится семёркой, и любое обращение к
## canv_cells[done] падает. Ровно так стенд и падал — в момент, когда проход
## УДАВАЛСЯ.
func _canv_now() -> Vector2i:
	if w.done >= w.n_canv or w.done >= w.canv_cells.size():
		return Vector2i(-1, -1)
	return w.canv_cells[w.done]


func scene_full(ph: int) -> void:
	say("═══ ПОЛНЫЙ ПРОХОД, фаза %d ═══" % ph)
	ev = {}
	# НЕ stage_clean! Он ставит монстра в двух клетках от игрока и включает
	# погоню на минуту — это нужно, чтобы ПОКАЗАТЬ монстра в отдельной сцене.
	# В полном проходе от этого игра начиналась с того, что тварь стоит рядом,
	# и дальше шли только поимки: три подряд — конец игры, перезагрузка сцены,
	# и вместе со сценой умирал сам стенд. Полный проход должен начинаться так
	# же, как начинается игра: он в камне, далеко, и его не видно.
	w.player_node.global_position = w.cell_to_world(w.start_cell, PlayerScript.STAND_Y)
	w.streak = 0
	w.mon_kills = 0
	w.anger = 0
	# «безблока» — прогон со снятым запретом «под погоней полотно не
	# открывается». Сравнивать надо два прохода: с правилом и без него, иначе
	# упавший проход ничего не доказывает.
	w.no_chase_lock = OS.get_cmdline_user_args().has("безблока")
	if w.no_chase_lock:
		say("запрет полотна во время погони СНЯТ (ключ «безблока»)")
	if w.monster != null:
		w.monster.drop_hold()
		w.monster.form_hold = 0.0
		w.monster.retreat_to_wall(8.0, 16.0)
		w.monster.global_position = w.cell_to_world(w.exit_cell, 0.0)
	# По-настоящему: без неуязвимости, иначе проверять нечего.
	w.player_node.invuln = 0.0
	set_phase(ph)
	watching = true
	_watch()
	# Втрое быстрее реального времени: полный проход по семи полотнам — это
	# минут пятнадцать живой игры, а проверить надо три таких.
	Engine.time_scale = 3.0
	var t0: int = Time.get_ticks_msec()
	var solved: int = 0
	# ПОПЫТОК БОЛЬШЕ, ЧЕМ ПОЛОТЕН. Цикл шёл ровно семь раз — по числу полотен, —
	# и каждая неудачная попытка съедала полотно, которое ещё не сдано: стоило
	# холсту не открыться (а теперь он честно не открывается под погоней), как
	# проход заканчивался на третьем-четвёртом. Полотен по-прежнему семь; просто
	# к каждому можно вернуться.
	for k in w.n_canv * 3:
		if w.won:
			break
		if w.done >= w.n_canv:
			break
		# Все полотна сданы — дальше только дверь. Без этой строки стенд лез в
		# canv_cells[7] и падал ровно в тот момент, когда проход УДАЛСЯ.
		if w.done >= w.n_canv:
			break
		# ХОДИМ, ПОКА НЕ ОТКРОЕТСЯ. Полотно УБЕГАЕТ после двух провалов подряд,
		# и убежать оно может прямо пока мы к нему идём или стоим рядом. Значит
		# цель надо перечитывать, а не запоминать один раз.
		var goal: Vector2i = _canv_now()
		var ok: bool = false
		var attempt: int = 0
		# ПО СТРОКЕ НА ЗАХОД К ПОЛОТНУ. Проход стал падать с семи полотен до
		# двух-четырёх, и падал МОЛЧА: ни одного предупреждения, цикл просто
		# кончался. Без этой строки причину не найти — она и не находилась
		# три захода подряд.
		say("  заход %d: сдано %d, цель %s, погоня %s" % [
			k + 1, w.done, str(goal), str(w._chased_now())])
		# Три попытки по минуте, а не четыре по две: мой лимит считает ФИЗИЧЕСКИЕ
		# кадры, то есть реальные секунды, — и на фазе 2 один упрямый мольберт
		# съедал восемь минут живого времени, за которые в отчёте не появлялось
		# ни строчки.
		while attempt < 3 and not w.board.visible and not _drawing:
			if w.done >= w.n_canv:
				break
			attempt += 1
			goal = _canv_now()
			if attempt > 1:
				ev["полотно убегало"] = int(ev.get("полотно убегало", 0)) + 1
			# ПОД ПОГОНЕЙ ПОЛОТНО НЕ ОТКРЫВАЕТСЯ — И ЭТО ПРАВИЛО ИГРЫ, А НЕ
			# ЗАМИНКА (см. world._chased_now). Бот стоял у мольберта и ждал,
			# пока оно откроется, тратил три попытки и шёл к следующему: проход
			# упал с семи полотен до четырёх, и выглядело это поломкой игры.
			# Игрок в этот момент делает единственное, что можно: бежит в
			# убежище, там погоня кончается, и он возвращается к холсту.
			if w._chased_now():
				var safe: Vector2i = w.active_safe
				if safe.x < 0 and not w.safe_cells.is_empty():
					safe = w.safe_cells[0]
				if safe.x >= 0:
					ev["бежал в убежище"] = int(ev.get("бежал в убежище", 0)) + 1
					await goto_cell(safe, 40.0)
					var st: float = 0.0
					while w._chased_now() and st < 15.0:
						await w.get_tree().process_frame
						st += w.get_process_delta_time()
			ok = await goto_cell(goal, 60.0)
			# Доходим ВПЛОТНУЮ: игра открывает полотно в 2.5 м от центра, а
			# «дошёл» засчитывается и в соседней клетке — оттуда 2.8.
			var wait: float = 0.0
			while not w.board.visible and not _drawing and wait < 8.0 \
					and _canv_now() == goal:
				await w.get_tree().physics_frame
				wait += 1.0 / 60.0
				var to: Vector3 = w.cell_to_world(goal, 0.0) - w.player_node.global_position
				to.y = 0.0
				if to.length() > 0.5:
					w.player_node.yaw = atan2(-to.x, -to.z)
					Input.action_press("forward")
				else:
					Input.action_release("forward")
			Input.action_release("forward")
		if not ok and not w.board.visible and not _drawing:
			if _canv_now().x >= 0:
				warn("фаза %d: не дошёл до полотна %d в %s" % [ph, w.done, goal])
			continue
		# Сторож мог уже начать рисовать — тогда просто ждём, пока он кончит.
		if _drawing:
			var g2: float = 0.0
			while _drawing and g2 < 60.0:
				await w.get_tree().process_frame
				g2 += w.get_process_delta_time()
			solved = w.done
			continue
		if not w.board.visible:
			if _canv_now().x < 0:
				break            # пока стояли, сторож дорисовал последнее
			warn("фаза %d: у полотна %d стоял, а оно не открылось (полотно в %s)"
				% [ph, w.done, str(_canv_now())])
			continue
		var было_сдано: int = w.done
		if await solve_board():
			solved += 1
		say("    полотно закрылось: было сдано %d, стало %d, видно %s" % [
			было_сдано, w.done, str(w.board.visible)])
		await w.get_tree().create_timer(0.4).timeout
		check_now("после полотна %d" % solved)
		# Отходим, иначе следующее полотно не взводится.
		await w.get_tree().create_timer(0.6).timeout
	if not w.won:
		var okx: bool = await goto_cell(w.exit_cell, 90.0)
		if not okx:
			warn("фаза %d: до выхода не дошёл" % ph)
	await w.get_tree().create_timer(1.0).timeout
	Engine.time_scale = 1.0
	watching = false
	var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
	# Считаем ПО ИГРЕ, а не по своей переменной: полотно чаще всего дорисовывает
	# сторож, и мой счётчик оставался нулём при семи сданных полотнах.
	say("фаза %d: полотен сдано %d из %d, выход: %s, %.0f с игрового времени, подтолкнул бота %d раз"
		% [ph, w.done, w.n_canv, str(w.won), secs, pushes])
	var parts: Array = []
	for k in ev.keys():
		if String(k).begins_with("_"):
			continue
		parts.append("%s ×%d" % [k, int(ev[k])])
	if gaps.size() > 4:
		gaps.sort()
		var mn: float = float(gaps[0])
		var med: float = float(gaps[int(gaps.size() / 2)])
		var short: int = 0
		for g in gaps:
			if float(g) < 3.0:
				short += 1
		say("фаза %d: между хватами — самый короткий %.2f с, серединный %.2f с, короче трёх секунд %d из %d"
			% [ph, mn, med, short, gaps.size()])
		if short > gaps.size() / 5:
			warn("хват приходит раньше, чем кончается неуязвимость: %d промежутков короче 3 с" % short)
	say("фаза %d: по дороге — %s" % [ph, ", ".join(parts) if not parts.is_empty() else "ничего"])


## ОБВАЛ. Подняться по насыпи, посмотреть на солнце, быть сдёрнутым вниз.
func scene_climb() -> void:
	if w.climb == null:
		warn("обвала в лабиринте нет вовсе")
		return
	stage_clean()
	w.player_node.invuln = 9999.0
	# Ставим у подножия ската: сцену проверяем саму по себе, а дорогу к ней —
	# отдельно, полным проходом. Иначе один застрявший угол в другом конце
	# лабиринта прячет всё, что мы хотели посмотреть здесь.
	# Ставим в СОСЕДНЮЮ клетку и идём на насыпь ногами: заодно проверяем, что на
	# неё вообще можно взойти с обычного пола, без ступенек и невидимых бортов.
	var near_cell: Vector2i = w.climb_cell
	for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not w.maze.is_wall(w.climb_cell.x + d2.x, w.climb_cell.y + d2.y):
			near_cell = w.climb_cell + d2
			break
	w.player_node.global_position = w.cell_to_world(near_cell, PlayerScript.STAND_Y)
	await w.get_tree().physics_frame
	say("поставлен рядом с обвалом, клетка %s" % str(near_cell))
	var t: float = 0.0
	var top: float = 0.0
	while t < 10.0 and not w.climb_ready:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		var d: Vector3 = w.cell_to_world(w.climb_cell, 0.0) - w.player_node.global_position
		d.y = 0.0
		w.player_node.yaw = atan2(-d.x, -d.z)
		Input.action_press("forward")
		top = maxf(top, w.player_node.global_position.y)
	Input.action_release("forward")
	if not w.climb_ready:
		warn("на насыпь не взойти ногами: поднялся всего на %.2f" % top)
		return
	say("взошёл на насыпь, высота %.2f, подсказка появилась" % top)
	# Жмём E — дальше сцена.
	var ev := InputEventAction.new()
	ev.action = "read"
	ev.pressed = true
	w._unhandled_input(ev)
	var t5: float = 0.0
	while w.climb_state == 5 and t5 < 4.0:
		await w.get_tree().physics_frame
		t5 += 1.0 / 60.0
		top = maxf(top, w.player_node.global_position.y)
	var eye: float = w.player_node.global_position.y + w.player_node.eye_height
	say("поднялся на %.2f м, глаза на %.2f при потолке %.2f" % [top, eye, w.wall_height])
	if eye < w.wall_height:
		warn("голова не вышла наружу: глаза на %.2f, потолок %.2f" % [eye, w.wall_height])
	# Смотрим ВВЕРХ — за этим он сюда и лез.
	w.player_node.pitch = 1.15
	if w.climb_state == 0:
		warn("по обвалу не подняться: выше %.2f не вышло" % top)
		return
	await w.get_tree().create_timer(0.3).timeout
	await shot("climb_top")
	# Смотрит на солнце, потом его тянут вниз.
	var t2: float = 0.0
	while w.climb_state < 3 and t2 < 8.0:
		await w.get_tree().process_frame
		t2 += w.get_process_delta_time()
		if w.climb_state == 2 and not w.climb_tent.visible:
			warn("тянет вниз, а щупальца не видно")
	say("сдёрнуло вниз за %.1f с после подъёма" % t2)
	var t3: float = 0.0
	while w.climb != null and t3 < 6.0:
		await w.get_tree().process_frame
		t3 += w.get_process_delta_time()
	if w.climb != null:
		warn("насыпь не ушла под землю — наверх можно полезть второй раз")
	else:
		say("насыпь провалилась, второй раз наверх не подняться")
	var p = w.player_node
	# 0.85 — это то, куда игрока СТАВЯТ; физика потом выталкивает капсулу из
	# пола на свои 1.02. Придираться к этим семнадцати сантиметрам нельзя,
	# а вот метр над полом — уже висит.
	if p.global_position.y > 1.3 or p.global_position.y < 0.5:
		warn("после обвала игрок на высоте %.2f" % p.global_position.y)
	if not p.is_physics_processing():
		warn("после обвала управление не вернули")
	# И САМОЕ ВАЖНОЕ: СЦЕНА ДОЛЖНА КОНЧИТЬСЯ. Состояние подъёма оставалось
	# равным четырём навсегда, а его проверяет _attack_busy — то есть после
	# первого подъёма игра до конца захода считала, что «идёт другая атака»:
	# ни набегов, ни показов камерой, ни приёмов фигуры, ни голоса твари.
	# В логе играющего это видно прямо.
	say("после обвала: состояние подъёма %d, занято атакой: %s" % [
		w.climb_state, w._attack_why()])
	if w.climb_state != 0:
		warn("состояние подъёма застряло на %d — это блокирует пол-игры" % w.climb_state)
	if w._attack_busy():
		warn("после обвала игра считает, что идёт атака: %s" % w._attack_why())
	check_now("после обвала")


## ЖИЖА. Пройти под проломом насквозь и проверить, что заливает на подходе,
## что в середине он протирает глаза, и что на выходе заливает снова.
func scene_goo() -> void:
	if w.holes.is_empty():
		warn("проломов нет")
		return
	stage_clean()
	w.player_node.invuln = 9999.0
	var h: Vector2i = w.holes[0]
	for hh in w.holes:
		if hh != w.climb_cell:
			h = hh
			break
	# Встаём в двух клетках от пролома и идём насквозь.
	var far: Vector2i = h
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var c: Vector2i = h + d
		if not w.maze.is_wall(c.x, c.y) and not w.maze.is_wall(h.x + d.x / 2, h.y + d.y / 2):
			far = c
			break
	if far == h:
		warn("у пролома %s нет прямого прохода — пройти насквозь нельзя" % str(h))
		return
	w.player_node.global_position = w.cell_to_world(far, PlayerScript.STAND_Y)
	# Насквозь — если есть куда. В тупиковом закутке выходят той же дорогой,
	# и второе протирание должно случаться и там.
	var out: Vector2i = h + (h - far)
	if w.maze.is_wall(out.x, out.y):
		out = far
	var goal: Vector2i = h
	await w.get_tree().physics_frame
	var peak_in: float = 0.0
	var mid_after: float = 1.0
	var t: float = 0.0
	var wipes: int = 0
	var was_wipe: bool = false
	# Флаги в игре сбрасываются, когда он отошёл от пролома, — запоминаем их
	# ПО ХОДУ. Первый прогон читал их после выхода и уверял, что протирания не
	# было, хотя рука прошла по экрану у меня на глазах.
	var saw_in: bool = false
	var saw_out: bool = false
	var shot_full: bool = false
	var shot_hand: bool = false
	var shot_sky: bool = false
	while t < 30.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		var pc: Vector2i = w.world_to_cell(w.player_node.global_position)
		var d: Vector3 = w.cell_to_world(goal, 0.0) - w.player_node.global_position
		d.y = 0.0
		if goal == h and d.length() < 0.55:
			# В середине: смотрим наверх, как и должен человек, — а потом идём
			# НАСКВОЗЬ. Пока бот целился в середину, он там и топтался, и
			# второго протирания на выходе просто неоткуда было взяться.
			w.player_node.pitch = 1.0
			goal = out
		w.player_node.yaw = atan2(-d.x, -d.z)
		Input.action_press("forward")
		if w.goo_amt > 0.92 and not shot_full:
			shot_full = true
			await shot("goo_full")
		if w.goo_wipe > 0.35 and w.goo_wipe < 0.6 and not shot_hand:
			shot_hand = true
			await shot("goo_hand")
		if w.goo_wiped_in and goal == out and w.goo_amt < 0.1 and not shot_sky:
			shot_sky = true
			await shot("goo_sky")
		if w.goo_wipe > 0.0 and not was_wipe:
			wipes += 1
		if w.goo_wiped_in:
			saw_in = true
		if w.goo_wiped_out:
			saw_out = true
		was_wipe = w.goo_wipe > 0.0
		if pc != h and w.goo_wiped_in == false:
			peak_in = maxf(peak_in, w.goo_amt)
		if w.goo_wiped_in and pc == h:
			mid_after = minf(mid_after, w.goo_amt)
		if w.goo_wiped_out:
			break
	Input.action_release("forward")
	w.player_node.pitch = 0.0
	say("жижа: на подходе залило до %.2f, после протирания в середине %.2f, протёр %d раз"
		% [peak_in, mid_after, wipes])
	if peak_in < 0.7:
		warn("на подходе к пролому экран почти не залило (%.2f)" % peak_in)
	if not saw_in:
		warn("в середине пролома глаза не протёр")
	if mid_after > 0.3:
		warn("протёр глаза, а видно всё равно не стало (%.2f)" % mid_after)
	if not saw_out:
		warn("на выходе из-под пролома второго протирания не было")
	await shot("goo")


## ФОТОСЕССИЯ. Прогон по всему, что видно глазами: игрок и его палочка, камень,
## пол и потолок, мебель, полотно, пролом с жижей, обвал, обе формы монстра и его
## приёмы. Стенд умеет проверять числа, но «выглядит смешно» числом не ловится —
## поэтому здесь он просто расставляет камеру и снимает, а смотрю уже я.
var _cam: Camera3D


func _look(nm: String, eye: Vector3, at: Vector3, fov: float = 70.0) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		w.add_child(_cam)
	_cam.fov = fov
	_cam.current = true
	_cam.global_position = eye
	if eye.distance_to(at) > 0.05:
		_cam.look_at(at, Vector3.UP)
	await w.get_tree().create_timer(0.35).timeout
	await shot(nm)


## Камера от лица игрока: так видно ровно то, что видит он, — включая палочку.
func _eyes(nm: String, cell: Vector2i, yaw: float, pitch: float = 0.0) -> void:
	if _cam != null:
		_cam.current = false
	var p = w.player_node
	p.global_position = w.cell_to_world(cell, PlayerScript.STAND_Y)
	p.yaw = yaw
	p.pitch = pitch
	p.rotation.y = yaw
	p.head.rotation.x = pitch
	await w.get_tree().create_timer(0.4).timeout
	await shot(nm)


## Ставит монстра в n клетках перед игроком по прямому куску коридора и наводит
## взгляд игрока на него. Возвращает false, если такого куска рядом нет.
func _face(nm: String, cells: int) -> bool:
	var here: Vector2i = w.world_to_cell(w.player_node.global_position)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var ok := true
		for k in range(1, cells + 1):
			var c: Vector2i = here + d * k
			if w.maze.is_wall(c.x, c.y):
				ok = false
				break
		if not ok:
			continue
		var target: Vector2i = here + d * cells
		w.monster.global_position = w.cell_to_world(target, 0.0)
		var to: Vector3 = w.cell_to_world(target, 0.0) - w.player_node.global_position
		await _eyes(nm, here, atan2(-to.x, -to.z), 0.1)
		return true
	# Прямого куска нет — отходим на клетку и пробуем оттуда.
	for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c2: Vector2i = here + d2
		if w.maze.is_wall(c2.x, c2.y):
			continue
		w.player_node.global_position = w.cell_to_world(c2, PlayerScript.STAND_Y)
		await w.get_tree().physics_frame
		return await _face(nm, cells)
	warn("для кадра «%s» не нашлось прямого коридора" % nm)
	return false


func scene_photo() -> void:
	w.player_node.invuln = 9999.0
	var start: Vector2i = w.start_cell
	# 1. ИГРОК И ПАЛОЧКА. Стартовый стол за спиной: палочка, первая записка.
	await _eyes("01_старт_взгляд", start, PI)
	w.has_wand = true
	w.player_node.has_wand = true
	if w.wand_lamp != null:
		w.wand_lamp.visible = true
	if w.wand_view != null:
		w.wand_view.visible = true
	await _eyes("02_палочка_в_руке", start, 0.0)
	await _eyes("03_палочка_вниз", start, 0.0, -0.55)
	# 2. КАМЕНЬ, ПОЛ, ПОТОЛОК — вблизи и вдаль.
	var corr: Vector2i = w.canv_cells[0]
	await _eyes("04_коридор_вдаль", corr, 0.0)
	await _look("05_камень_вплотную", w.cell_to_world(corr, 1.6),
		w.cell_to_world(corr, 1.6) + Vector3(1.4, 0, 0), 60.0)
	await _look("06_потолок", w.cell_to_world(corr, 1.6), w.cell_to_world(corr, 4.2), 80.0)
	await _look("07_пол", w.cell_to_world(corr, 2.4), w.cell_to_world(corr, 0.0), 80.0)
	# 3. МЕБЕЛЬ И ПОЛОТНО.
	await _eyes("08_мольберт", w.canv_cells[0] + Vector2i(0, 1),
		atan2(0.0, 1.0))
	w.player_node.global_position = w.cell_to_world(w.canv_cells[w.done], PlayerScript.STAND_Y)
	w._open_board()
	await w.get_tree().create_timer(0.9).timeout
	await shot("09_полотно")
	# И ПОЛОТНО В РАБОТЕ. Пустой холст показывает предмет, а не механику: краска,
	# потёки и прожиг на сдаче — это и есть то, ради чего к нему подходят.
	var b = w.board
	for i in b.n:
		b.tents.clear()
		b.tent_life = 0.0
		var цель = null
		for d in b.dots:
			if int(d["idx"]) == b.next_idx:
				цель = d
				break
		if цель == null:
			break
		b._click(b._dot_pos(цель))
		await w.get_tree().create_timer(0.14).timeout
		if i == b.n - 4:
			await shot("10_полотно_в_работе")
	await w.get_tree().create_timer(0.12).timeout
	await shot("11_прожиг")
	await w.get_tree().create_timer(0.7).timeout
	w.board.visible = false
	w._close_board()
	if not w.safe_cells.is_empty():
		await _eyes("10_убежище", w.safe_cells[0], 0.0)
	# 4. ПРОЛОМ С ЖИЖЕЙ.
	var hole: Vector2i = w.holes[0]
	for h2 in w.holes:
		if h2 != w.climb_cell:
			hole = h2
			break
	await _look("11_пролом_издали", w.cell_to_world(hole, 1.6) + Vector3(0, 0, 6.5),
		w.cell_to_world(hole, 2.6), 75.0)
	await _eyes("12_под_проломом", hole, 0.0, 0.9)
	# 5. ОБВАЛ.
	await _look("13_насыпь", w.cell_to_world(w.climb_cell, 1.9) + Vector3(3.6, 0, 0),
		w.cell_to_world(w.climb_cell, 0.4), 70.0)
	# 6. МОНСТР. Ставим ЕГО в коридоре перед игроком и смотрим глазами игрока с
	# зажжённой палочкой — то есть ровно так, как его видно в игре. Свободная
	# камера в стороне почти всегда оказывалась внутри камня: коридор шириной в
	# одну клетку, отойти некуда.
	stage_clean()
	await w.get_tree().create_timer(1.2).timeout
	await _face("14_осьминог_в_коридоре", 3)
	await _face("15_осьминог_вплотную", 2)
	# 7. ФОРМА ВТОРАЯ.
	w.monster.take_form(40.0, w.monster.FORM_HUMAN)
	await w.get_tree().create_timer(2.2).timeout
	await _face("16_фигура_в_коридоре", 3)
	await _face("17_фигура_вплотную", 2)
	# 8. ПРИЁМЫ.
	await _face("18_перед_приёмом", 3)
	w._start_human_attack()
	await w.get_tree().create_timer(1.4).timeout
	await shot("19_руки_с_потолка")
	await w.get_tree().create_timer(3.0).timeout
	w.hf_stage = 0
	w._human_tongue()
	await w.get_tree().create_timer(0.8).timeout
	await shot("20_язык")
	await w.get_tree().create_timer(2.0).timeout
	# 9. ХВАТ.
	# СНАЧАЛА УБИРАЕМ ПРЕДЫДУЩИЙ ПРИЁМ. Без этого хват снимался поверх ещё
	# идущего языка: в кадре надпись «ЯЗЫК ИЗ ПАСТИ», камера внутри туши и
	# белёсая каша вместо щупалец. Кадр был браком, а выглядел как поломка игры.
	w.hf_stage = 0
	w.hf_t = 0.0
	w.reel_t = 0.0
	w.lift_on = false
	w.monster.arms_up = 0.0
	w.monster.ceiling_release()
	w.monster.take_form(0.0, w.monster.FORM_NONE)
	w.monster.form_hold = 0.0
	w.monster.form_t = 0.0
	w.monster.drop_hold()
	stage_clean()
	await w.get_tree().create_timer(2.0).timeout
	w._grab_now("ЖМИ ПРОБЕЛ! ВЫРЫВАЙСЯ!", "monster")
	await w.get_tree().create_timer(1.0).timeout
	await shot("21_хват")
	# И ХВАТ В РАБОТЕ. Первый кадр — это «тебя схватили»; сочное начинается
	# дальше: перерубленные щупальца, жижа в воздухе и капли на объективе.
	for i in 7:
		w.grab_ui.bot_slash()
		await w.get_tree().create_timer(0.22).timeout
		if i == 3:
			await shot("22_нож_режет")
	await shot("23_обрубки")
	w.grab_ui.visible = false
	w.grab_ui.set_process(false)
	w._freeze_player(false)
	# 10. ОЧЕРТАНИЯ В КОРИДОРЕ. То, как его видно, когда он ещё далеко.
	w.monster.drop_hold()
	w.monster.parked = true
	w.monster.prowl = false
	w.monster.mode = "chase"
	for клеток in [6, 3]:
		var где: Vector2i = _clear_spot(клеток)
		if где.x < 0:
			continue
		w.monster.global_position = w.cell_to_world(где)
		w.monster.visible = true
		w.monster._grow_out()
		w.player_node.look_force(w.monster.global_position + Vector3.UP * 1.2,
			2.0, 40.0)
		for i in 30:
			await w.get_tree().process_frame
		await shot("24_очертания_%02d_клеток" % [клеток])
	# 11. ФИНАЛЬНАЯ ДВЕРЬ. Её рисуют на стене, и это последнее, что игрок делает.
	w.monster.visible = false
	w.done = w.n_canv
	w.player_node.global_position = w.cell_to_world(w.exit_cell,
		PlayerScript.STAND_Y)
	await w.get_tree().process_frame
	w._open_finale()
	await w.get_tree().create_timer(1.1).timeout
	await shot("25_дверь_на_стене")
	say("фотосессия: снято %d кадров" % _shots)



## НЕВИДИМЫЕ СТЕНЫ. Проходим ВСЕ соседние пары свободных клеток и стреляем
## лучом из середины одной в середину другой на высоте груди. Если между двумя
## клетками пола что-то стоит — это и есть та стена, которой не видно: коллизия
## осталась от предмета, которого либо нет, либо он далеко.
func scene_ghost() -> void:
	# Луч можно пускать ТОЛЬКО внутри физического кадра: состояние мира вне его
	# либо заблокировано, либо врёт. Поэтому ждём кадр, берём состояние заново
	# и в этом кадре стреляем небольшой пачкой.
	await w.get_tree().physics_frame
	# Тип пишем руками: «w» — нетипизированная ссылка на мир, и вывести из неё
	# тип Godot не может. Такой := не компилируется вовсе, и весь стенд молча
	# не грузится — ровно поэтому проверка и «висела» без единой строки.
	var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
	var found: Dictionary = {}
	var checked: int = 0
	for r in w.maze.size.y:
		for c in w.maze.size.x:
			if w.maze.is_wall(r, c):
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nb: Vector2i = Vector2i(r, c) + d
				if nb.x >= w.maze.size.y or nb.y >= w.maze.size.x or w.maze.is_wall(nb.x, nb.y):
					continue
				for h in [0.35, 1.0, 1.7]:
					checked += 1
					if checked % 400 == 0:
						await w.get_tree().physics_frame
						space = w.get_world_3d().direct_space_state
					var a: Vector3 = w.cell_to_world(Vector2i(r, c), h)
					var b: Vector3 = w.cell_to_world(nb, h)
					var q := PhysicsRayQueryParameters3D.create(a, b)
					var hit: Dictionary = space.intersect_ray(q)
					if hit.is_empty():
						continue
					var node: Node = hit["collider"]
					# Имя узла в Godot часто безымянное (@Node3D@258) — тогда
					# ищем по детям: у любой моей мебели рядом с телом лежит меш,
					# и по его форме сразу видно, что именно там стоит.
					var par: Node = node.get_parent()
					var nm: String = str(node.name) if par == null else str(par.name)
					if nm.begins_with("@") and par != null:
						var kids: Array = []
						for kid in par.get_children():
							if kid is MeshInstance3D:
								var mm = (kid as MeshInstance3D).mesh
								kids.append("%s %s" % [mm.get_class(),
									str((kid as MeshInstance3D).position.round())])
						nm = "безымянный узел с детьми " + str(kids.slice(0, 3))
					var key: String = "%s на высоте %.2f" % [nm, h]
					if not found.has(key):
						found[key] = []
					if found[key].size() < 4:
						found[key].append("%s→%s" % [str(Vector2i(r, c)), str(nb)])
	say("невидимые стены: проверено %d проходов между клетками" % checked)
	if found.is_empty():
		say("между клетками пола ничего не стоит")
		return
	for k in found.keys():
		warn("проход перекрыт: %s, например %s" % [k, str(found[k])])


## КАРТА ОДНИМ ЧИСЛОМ. Нужна, чтобы перебрать сиды и выбрать тот, по которому
## приятно идти: не слишком длинный путь, без одного огромного перегона между
## полотнами, с обвалом на дороге и с убежищами там, где они пригодятся.
func scene_map() -> void:
	var legs: Array = []
	var prev: Vector2i = w.start_cell
	for c in w.canv_cells:
		legs.append(w._path_cells(prev, c).size())
		prev = c
	legs.append(w._path_cells(prev, w.exit_cell).size())
	var total: int = 0
	var longest: int = 0
	for l in legs:
		total += int(l)
		longest = maxi(longest, int(l))
	# Насколько обвал в стороне от дороги «полотно N/2-1 → N/2».
	var mi: int = int(w.canv_cells.size() / 2)
	var road: Array[Vector2i] = w._path_cells(w.canv_cells[mi - 1], w.canv_cells[mi])
	var off: float = 999.0
	for c in road:
		off = minf(off, Vector2(w.climb_cell - c).length())
	# Убежища — по дороге ли они, или в стороне.
	var safe_off: float = 999.0
	var full: Array[Vector2i] = []
	prev = w.start_cell
	for c in w.canv_cells:
		full.append_array(w._path_cells(prev, c))
		prev = c
	for sc in w.safe_cells:
		var d: float = 999.0
		for c in full:
			d = minf(d, Vector2(sc - c).length())
		safe_off = minf(safe_off, d)
	say("КАРТА: путь %d клеток, перегоны %s, самый длинный %d, до первого полотна %d"
		% [total, str(legs), longest, int(legs[0])])
	say("КАРТА: обвал %s (в стороне от дороги на %.1f), проломов %d, убежищ %d (ближайшее к пути %.1f)"
		% [str(w.climb_cell), off, w.holes.size(), w.safe_cells.size(), safe_off])
	var score: int = 0
	if longest <= 42:
		score += 1
	if total >= 110 and total <= 200:
		score += 1
	if int(legs[0]) <= 12:
		score += 1
	if off < 0.5:
		score += 1
	if w.climb != null:
		score += 1
	say("КАРТА: оценка %d из 5" % score)


## ПОЧЕМУ СТОИТ. Отдельная короткая проверка: ставим игрока, жмём вперёд и
## смотрим, сдвинулся ли он и что в этот момент с игрой.
func scene_why() -> void:
	w.player_node.global_position = w.cell_to_world(w.start_cell, PlayerScript.STAND_Y)
	await w.get_tree().physics_frame
	_state("сразу после постановки")
	var p = w.player_node
	var from: Vector3 = p.global_position
	var t: float = 0.0
	while t < 3.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		Input.action_press("forward")
	Input.action_release("forward")
	say("за 3 с прошёл %.2f м" % from.distance_to(p.global_position))
	_state("после трёх секунд ходьбы")
	# И то же самое у полотна.
	w.player_node.global_position = w.cell_to_world(w.canv_cells[w.done], PlayerScript.STAND_Y)
	await w.get_tree().create_timer(1.5).timeout
	say("на клетке полотна %s: полотно открыто %s, взведено %s, близко %s"
		% [str(w.canv_cells[w.done]), str(w.board.visible), str(w.canvas_arm),
			str(w._near(w.canv_cells[w.done]))])


func _state(tag: String) -> void:
	var p = w.player_node
	say("%s: физика %s, мёртв %s, победа %s, окна %s, занят %s, поимки %d/%d, выброс %.1f, старт %s"
		% [tag, str(p.is_physics_processing()), str(w.dead), str(w.won),
			str(w._ui_blocking()), str(w._busy()), w.streak, w.mon_kills,
			w.drop_t, str(w.started)])


func _report() -> void:
	print("")
	print("──────── ОТЧЁТ СТЕНДА ────────")
	for l in log_lines:
		print("  ", l)
	if bad.is_empty():
		print("  странного не замечено")
	else:
		print("  ЧТО ВЫГЛЯДИТ НЕ ТАК (", bad.size(), "):")
		for b in bad:
			var n: int = int(_seen.get(b, 1))
			print("   - ", b, (" — и ещё %d раз" % (n - 1)) if n > 1 else "")
	print("──────────────────────────────")
	w.get_tree().quit()


## ─────────────────────────── не мешает ли играть ───────────────────────────
##
## Всё, что ниже, отвечает на один вопрос: можно ли в это играть. Не «красиво
## ли», а «доходит ли ноги, работает ли палочка, не заперли ли мы игрока».
## ПРОХОД ТЕПЕРЬ ИГРАЕТ, А НЕ ТОЛЬКО ХОДИТ.
##
## Раньше здесь был один goto_cell на каждую клетку — и ни одного нажатия на
## точку. Полотна в этой сцене не рисовал никто: подходишь, оно открывается,
## таймер выходит, два провала — и оно убегает в другое место. А в отчёте всё
## это время стояло «обошёл все 7 полотен», и я читал это как «прошёл игру».
## Обошёл — значит дошёл до семи клеток, не больше.
##
## Рисует _watch, и он тут просто не был включён. Включаем: тогда «проход»
## проверяет то, ради чего игра существует, — соединение точек.
func scene_walk_all() -> void:
	var fails: int = 0
	var t0: float = Time.get_ticks_msec()
	# БЕЗ БОГА. На старте прогона стенд ставит invuln = 9999, чтобы сцену не
	# обрывала смерть, — и в проходе это никогда не снималось. Замер показал,
	# чего это стоило: монстр дотягивался до бота 41 секунду и все 41 не мог его
	# тронуть, а отчёт при этом говорил «семь из семи, странного не замечено».
	# Фазовые прогоны неуязвимость снимают (строка про «по-настоящему»), проход
	# — нет, и поэтому именно он врал громче всех.
	w.player_node.invuln = 0.0
	watching = true
	_watch()
	# ПО ПОЛОТНУ ЗА КРУГ — НО КРУГОВ БОЛЬШЕ, ЧЕМ ПОЛОТЕН.
	#
	# Здесь стоял «for i in canv_cells.size()»: ровно семь заходов, по одному на
	# полотно. Пока холст открывался сам, стоило подойти, этого хватало. Теперь
	# под погоней он НЕ открывается (правило игры, а не заминка), и каждый такой
	# заход сгорал впустую: проход падал с семи полотен до двух-четырёх, причём
	# молча — ни одного предупреждения, цикл просто кончался.
	#
	# Теперь круг кончается только вместе с полотнами, а бот ведёт себя как
	# игрок: гонятся — бежит в убежище и пережидает, а не стоит у мольберта.
	# ВДВОЕ БЫСТРЕЕ РЕАЛЬНОГО ВРЕМЕНИ. Бот теперь пережидает погони, как игрок,
	# и проход занимает одиннадцать минут живого времени — столько ждать ради
	# одной проверки нельзя. Игра при этом идёт своим чередом, просто быстрее.
	Engine.time_scale = 2.5
	var guard: int = 0
	while w.done < w.n_canv and guard < w.n_canv * 4:
		guard += 1
		var цель: Vector2i = _canv_now()
		if цель.x < 0:
			break
		say("  круг %d: сдано %d, цель %s, погоня %s" % [
			guard, w.done, str(цель), str(w._chased_now())])
		if w._chased_now():
			ev["бежал в убежище"] = int(ev.get("бежал в убежище", 0)) + 1
			await _flee_and_wait()
			continue
		var ok: bool = await goto_cell(цель, 70.0)
		if not ok:
			fails += 1
			continue
		check_now("путь к полотну %d" % guard)
		# ЖДЁМ, ПОКА ОТКРОЕТСЯ. Открывает его близость, но не сразу: игра может
		# держать холст закрытым, пока тварь рядом.
		var t: float = 0.0
		while not (w.board != null and w.board.visible) and t < 12.0 \
				and _canv_now() == цель and not w._chased_now():
			await w.get_tree().create_timer(0.2).timeout
			t += 0.2
		if w.board == null or not w.board.visible:
			say("    не открылось за %.0f с (погоня %s)" % [t, str(w._chased_now())])
			continue
		# Открылось — дальше его дорисовывает сторож; ждём, пока закроется.
		var wait: float = 0.0
		while (w.board != null and w.board.visible) and wait < 45.0:
			await w.get_tree().create_timer(0.2).timeout
			wait += 0.2
		await w.get_tree().create_timer(0.6).timeout
	Engine.time_scale = 1.0
	watching = false
	var secs: float = (Time.get_ticks_msec() - t0) / 1000.0
	say("прошёл: сдано %d полотен из %d за %.0f с, не дошёл до %d" % [
		w.done, w.n_canv, secs, fails])
	# ЧАСТОТА ВСТРЕЧ — мера баланса, а не прохождения. Сами хваты о страхе не
	# говорят (я жму на вырывание каждым кадром, человек так не может), но
	# СКОЛЬКО ИХ и КАК ЧАСТО — величина честная, и по ней видно, изменилась
	# угроза или только показалось.
	var mid: float = 0.0
	for g in gaps:
		mid += float(g)
	if not gaps.is_empty():
		mid /= float(gaps.size())
	say("встреч: хватов %d, поимок %d, промежуток между хватами в среднем %.0f с" % [
		int(ev.get("хват", 0)), w.captures, mid])
	# ВЕСЬ СПИСОК СОБЫТИЙ, а не только хваты: ноль хватов сам по себе двусмыслен
	# — он значит и «не ловил», и «наблюдатель не работал». Отличить одно от
	# другого можно только по остальным счётчикам в той же строке.
	var seen: Array = []
	for k in ev.keys():
		if String(k).begins_with("_"):
			continue
		seen.append("%s ×%d" % [k, int(ev[k])])
	say("по дороге: %s" % [", ".join(seen) if not seen.is_empty() else "ничего"])
	say("монстр: %s, сквозь камень подходил на %.1f клетки" % [
		"выходил из камня" if mon_out else "НИ РАЗУ НЕ ВЫШЕЛ", mon_near])
	say("в коридоре: %.0f с из %.0f (%.0f%% прохода), ближе всего на %.1f клетки" % [
		mon_out_s, secs, 100.0 * mon_out_s / maxf(secs, 1.0),
		mon_out_near if mon_out_near < 1e8 else -1.0])
	var rp: Array = []
	for k in reach.keys():
		rp.append("%s %.0f с" % [k, float(reach[k])])
	say("форма: осталось попыток %d, откат %.0f с, накоплено ожидания %.0f с, фаза %d" % [
		w.forms_left, w.form_cool, w.form_want, w.phase])
	say("фазы: %s" % [" → ".join(ph_log) if not ph_log.is_empty() else "ни одной"])
	say("дотягивался: %s" % [", ".join(rp) if not rp.is_empty() else "ни секунды"])
	# РЫВОК — УСЛОВИЕ ЗАМЕРА, А НЕ УКРАШЕНИЕ. Пока стенд жал его несуществующим
	# способом, он ходил пешком, и любая проверка погони отвечала на вопрос
	# «догонит ли она идущего» вместо «догонит ли она бегущего». Если счётчик
	# снова обнулится — все выводы про погоню в этом прогоне недействительны.
	say("рывок: включал %d раз, бежал %.0f с" % [sprints, sprint_s])
	say("стены хлестнули: %d раз" % w.bursts)
	if sprints == 0 or sprint_s < 1.0:
		warn("СТЕНД НЕ БЕГАЛ — про погоню этот прогон не говорит ничего")
	if w.done < w.n_canv:
		warn("сдано только %d полотен из %d — до остальных не дошёл или не нарисовал" % [
			w.done, w.n_canv])


## Палочка: выпадает, находится, поднимается. Без неё игра встаёт совсем.
func scene_wand() -> void:
	var stone: int = 0
	for i in 60:
		w.has_wand = true
		w.player_node.has_wand = true
		if w.dropped_wand != null:
			w.dropped_wand.queue_free()
			w.dropped_wand = null
		w._drop_wand()
		var c: Vector2i = w.world_to_cell(w.dropped_wand.global_position)
		if w.maze.is_wall(c.x, c.y):
			stone += 1
	say("палочка: из 60 падений в камень попало %d" % stone)
	if stone > 0:
		warn("палочка падает в камень (%d из 60) — её оттуда не достать" % stone)
	# И поднимается ли по E с разумного расстояния.
	w.player_node.global_position = w.dropped_wand.global_position + Vector3(1.4, 0.85, 0)
	w.has_wand = false
	w.player_node.has_wand = false
	var got: bool = w._pick_wand()
	say("палочка поднимается по E с 1.4 м: %s" % str(got))
	if not got:
		warn("палочку не поднять по E с полутора метров")


## Убежище: он туда не заходит. Это единственное место, где можно выдохнуть.
func scene_shelter() -> void:
	if w.safe_cells.size() < 2:
		warn("убежищ меньше двух — прятаться негде")
		return
	var cell: Vector2i = w.safe_cells[1]
	w.player_node.global_position = w.cell_to_world(cell, PlayerScript.STAND_Y)
	var m = w.monster
	m.global_position = w.cell_to_world(cell) + Vector3(0, 0, w.cell_size * 2.0)
	m.visible = true
	m.mode = "chase"
	m.chase_t = 30.0
	var closest: float = 999.0
	var t: float = 0.0
	while t < 4.0:
		await w.get_tree().physics_frame
		t += 1.0 / 60.0
		var mc: Vector2i = w.world_to_cell(m.global_position)
		if mc == cell:
			warn("монстр ВОШЁЛ в убежище — прятаться негде")
			break
		closest = minf(closest, m.global_position.distance_to(
			w.player_node.global_position))
	say("убежище: за 4 с он подошёл на %.1f м и внутрь не зашёл" % closest)


## Кадры в секунду: не проседает ли игра там, где всего много.
## КАДР НА ТРЁХ КАЧЕСТВАХ. Смысл настройки в том, что на слабой машине она
## возвращает проценты; проверить это можно только замером всех трёх подряд, в
## одном прогоне и на одном месте — иначе сравниваешь разные забеги.
func scene_quality() -> void:
	say("═══ КАДР ПО КАЧЕСТВУ ═══")
	var was: int = Settings.quality
	for q in 3:
		Settings.quality = q
		w.apply_quality()
		# Даём кадру устояться: перестройка стен идёт не мгновенно.
		var t0: float = 0.0
		while t0 < 1.2:
			await w.get_tree().process_frame
			t0 += w.get_process_delta_time()
		var t: float = 0.0
		var worst: float = 999.0
		var sum: float = 0.0
		var n: int = 0
		while t < 3.0:
			await w.get_tree().process_frame
			t += w.get_process_delta_time()
			var f: float = Performance.get_monitor(Performance.TIME_FPS)
			if f > 1.0:
				worst = minf(worst, f)
				sum += f
				n += 1
		say("качество %d (%s): в среднем %.0f, худший %.0f" % [q,
			["низкое", "среднее", "высокое"][q], sum / maxf(1.0, float(n)), worst])
	# И ОТДЕЛЬНО — ЦЕНА САМОГО ЗЕРНА. Разница между качествами складывается из
	# сетки, тумана и теней; чтобы знать, сколько стоит именно шум на стенах,
	# гасим одну эту ручку, не трогая остального.
	Settings.quality = 2
	w.apply_quality()
	for g in [1.0, 0.0]:
		w.wall_mat.set_shader_parameter("grain_k", g)
		var t2: float = 0.0
		while t2 < 0.8:
			await w.get_tree().process_frame
			t2 += w.get_process_delta_time()
		var t3: float = 0.0
		var sum2: float = 0.0
		var n2: int = 0
		while t3 < 3.0:
			await w.get_tree().process_frame
			t3 += w.get_process_delta_time()
			var f2: float = Performance.get_monitor(Performance.TIME_FPS)
			if f2 > 1.0:
				sum2 += f2
				n2 += 1
		say("высокое, зерно %s: в среднем %.0f" % [
			"включено" if g > 0.5 else "выключено", sum2 / maxf(1.0, float(n2))])
	Settings.quality = was
	w.apply_quality()


func scene_fps() -> void:
	var t: float = 0.0
	var worst: float = 999.0
	var sum: float = 0.0
	var n: int = 0
	while t < 3.0:
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
		var f: float = Performance.get_monitor(Performance.TIME_FPS)
		if f > 1.0:
			worst = minf(worst, f)
			sum += f
			n += 1
	say("кадры: в среднем %.0f, худший %.0f, вызовов отрисовки %d" % [
		sum / maxf(1.0, float(n)), worst,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	if worst < 30.0:
		warn("кадры проседали до %.0f — на слабой машине будет хуже" % worst)
