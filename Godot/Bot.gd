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
var watching: bool = false     ## параллельный присмотр во время полного прохода
var ev: Dictionary = {}        ## что случилось за проход


func setup(world) -> void:
	w = world


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
	# Обвал тоже забирает управление — на те полторы секунды, пока его тянут
	# вниз. Без этой оговорки стенд честно ругался на собственную сцену.
	if not p.is_physics_processing() and not w._busy() and w.drop_t <= 0.0 \
			and w.reel_t <= 0.0 and w.slam_stage == 0 and w.hf_stage == 0 \
			and w.climb_state != 2:
		warn("%s: управление отобрано, а причин для этого нет" % tag)
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
	vp.get_texture().get_image().save_png("user://bot_%02d_%s.png" % [_shots, name])
	_shots += 1


## ─────────────────────────── ходьба ───────────────────────────
##
## ОБХОД ПРЕПЯТСТВИЙ. Прямолинейный бот застревал у мольберта: он упирался и
## продолжал давить вперёд. Живой человек в такой ситуации делает шаг вбок —
## это и повторяем: уперся на полсекунды, значит идём боком, потом снова вперёд.
func goto_cell(goal: Vector2i, limit: float = 25.0) -> bool:
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
		if p.sprint_left <= 0.0 and p.sprint_cool <= 0.0:
			Input.action_press("sprint")
		else:
			Input.action_release("sprint")
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
	Input.action_release("sprint")
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
			warn("не успел до %s за %.0f с (шёл, но далеко), остановился в %s"
				% [goal, limit, here])
	return ok


## ─────────────────────────── сценарии ───────────────────────────
##
## Каждый ставит нужное состояние, проигрывает сцену и проверяет её. Названия
## те же, что мы говорим вслух: «третья фаза», «погоня», «руки с потолка».
func set_phase(n: int) -> void:
	# Фаза считается от числа ошибок — ставим их напрямую, а не рисуем криво.
	w.errors = [0, w.PHASE_STEP, w.PHASE_STEP * 2, w.PHASE_STEP * 3][clampi(n, 0, 3)]
	w._update_phase()
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


## ВРЕМЕННАЯ СЦЕНА: открыть холст и снять кадр. Подсказку «E — бросить» надо
## увидеть, а не поверить, что она нарисована.
func scene_board_shot() -> void:
	say("═══ ХОЛСТ: КАДР ═══")
	w.player_node.invuln = 9999.0
	w._open_board()
	await w.get_tree().create_timer(0.8).timeout
	say("холст открыт: %s" % str(w.board.visible))
	await shot("холст_спокойно")
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
	if want.has("брожение"):
		await scene_wander(2.5)
	if want.has("походка"):
		await scene_human_walk()
	if all or want.has("формы"):
		await scene_forms()
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
		# Хватают — ВЫРЫВАЕМСЯ. Именно так это и задумано: не ждать, а жать.
		if w.grab_ui != null and w.grab_ui.visible:
			w.grab_ui.press()
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


## Клетка ТЕКУЩЕГО полотна — или (-1,-1), если все сданы. Отдельная функция,
## потому что done меняется в чужой корутине: сторож дорисовывает полотно ровно
## между двумя моими строчками, done становится семёркой, и любое обращение к
## canv_cells[done] падает. Ровно так стенд и падал — в момент, когда проход
## УДАВАЛСЯ.
func _canv_now() -> Vector2i:
	if w.done >= Shapes.N_CANV or w.done >= w.canv_cells.size():
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
	for k in Shapes.N_CANV:
		if w.won:
			break
		# Все полотна сданы — дальше только дверь. Без этой строки стенд лез в
		# canv_cells[7] и падал ровно в тот момент, когда проход УДАЛСЯ.
		if w.done >= Shapes.N_CANV:
			break
		# ХОДИМ, ПОКА НЕ ОТКРОЕТСЯ. Полотно УБЕГАЕТ после двух провалов подряд,
		# и убежать оно может прямо пока мы к нему идём или стоим рядом. Значит
		# цель надо перечитывать, а не запоминать один раз.
		var goal: Vector2i = _canv_now()
		var ok: bool = false
		var attempt: int = 0
		# Три попытки по минуте, а не четыре по две: мой лимит считает ФИЗИЧЕСКИЕ
		# кадры, то есть реальные секунды, — и на фазе 2 один упрямый мольберт
		# съедал восемь минут живого времени, за которые в отчёте не появлялось
		# ни строчки.
		while attempt < 3 and not w.board.visible and not _drawing:
			if w.done >= Shapes.N_CANV:
				break
			attempt += 1
			goal = _canv_now()
			if attempt > 1:
				ev["полотно убегало"] = int(ev.get("полотно убегало", 0)) + 1
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
		if await solve_board():
			solved += 1
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
		% [ph, w.done, Shapes.N_CANV, str(w.won), secs, pushes])
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
	await w.get_tree().create_timer(0.6).timeout
	await shot("09_полотно")
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
	w.monster.drop_hold()
	w.monster.form_hold = 0.0
	await w.get_tree().create_timer(1.5).timeout
	w._grab_now("ЖМИ ПРОБЕЛ! ВЫРЫВАЙСЯ!", "monster")
	await w.get_tree().create_timer(1.0).timeout
	await shot("21_хват")
	w.grab_ui.visible = false
	w.grab_ui.set_process(false)
	w._freeze_player(false)
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
	for i in w.canv_cells.size():
		# Клетку берём СВЕЖУЮ на каждом шаге: полотно может убежать, пока идём.
		if _canv_now().x < 0:
			break
		var ok: bool = await goto_cell(_canv_now(), 70.0)
		if not ok:
			fails += 1
		else:
			check_now("путь к полотну %d" % i)
		# Ждём, пока сторож дорисует открывшееся полотно, и отходим.
		var wait: float = 0.0
		while (w.board != null and w.board.visible) and wait < 45.0:
			await w.get_tree().create_timer(0.2).timeout
			wait += 0.2
		await w.get_tree().create_timer(0.6).timeout
	watching = false
	var secs: float = (Time.get_ticks_msec() - t0) / 1000.0
	say("прошёл: сдано %d полотен из %d за %.0f с, не дошёл до %d" % [
		w.done, Shapes.N_CANV, secs, fails])
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
	if w.done < Shapes.N_CANV:
		warn("сдано только %d полотен из %d — до остальных не дошёл или не нарисовал" % [
			w.done, Shapes.N_CANV])


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
