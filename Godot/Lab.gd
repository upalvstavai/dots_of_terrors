extends Control

## ЛАБОРАТОРИЯ «ТОЧЕК УЖАСА» — отдельная сборка, в которой игру можно разбирать
## по частям, не заходя в игру. В самой игре разбирать нечего: там монстр ходит
## по лабиринту и мешает смотреть, а половину декораций видно полторы секунды
## из-за угла.
##
## ГЛАВНОЕ РЕШЕНИЕ ЗДЕСЬ ОДНО: окна декораций, анимаций и звуков смотрят в
## НАСТОЯЩИЙ МИР — тот же world.tscn, что запускается в игре, — а не в мою
## копию лампы и моё представление о том, как он вылезает из стены. Копия
## однажды уже обманула: смотровая открывалась с коридором 4.6 м при игровых
## 2.8, и коридорная походка там годами выглядела нормально, пока в игре
## половина ноги стояла в камне. Мир один, у окон только свои камеры: Godot
## умеет отдавать один World3D нескольким областям отрисовки.
##
## Окно монстра — исключение: смотровая (Viewer.gd) строит себе свою комнату со
## своим светом, и ей чужой мир не нужен. Поэтому у неё свой World3D.

const ViewerScene := preload("res://viewer.tscn")
const WorldScene := preload("res://world.tscn")
const LabFly := preload("res://LabFly.gd")

## Одно место, где перечислено, какие бывают окна. Порядок — порядок кнопок.
const WINDOWS := [
	["монстр", "МОНСТР", "его тело, походка и все приёмы — в своей комнате"],
	["звуки", "ЗВУКИ", "каждая ситуация игры и что в ней слышно"],
	["анимации", "АНИМАЦИИ", "засада, выход из стены, руки с потолка"],
	["декорации", "ДЕКОРАЦИИ", "лампы, стены, потолок, пол — в настоящем мире"],
]

var wins: Dictionary = {}        ## ключ → Window
var game: Node3D = null          ## настоящий мир; строится при первой надобности
## МИР ЖИВЁТ В ОТДЕЛЬНОЙ ОБЛАСТИ, А НЕ В ГЛАВНОМ ОКНЕ. Сперва я подвесил его
## прямо под пульт, и пульт начал рисовать лабиринт у себя за кнопками: сквозь
## него просвечивала палочка в световом пятне. Так и родилось ощущение, что
## открылось «две лаборатории, которые работают отдельно». Теперь мир висит в
## невидимой области с выключенной отрисовкой, а окна берут у неё только World3D
## — то есть рисуют его сами, своими камерами, а пульт не рисует вовсе.
var game_ready: bool = false
var note: Label
var btns: Dictionary = {}        ## ключ → кнопка пульта, чтобы писать на ней состояние
var building: bool = false       ## лабиринт уже строится: второй раз не надо
var holder: SubViewport = null   ## та самая невидимая область
var lines: Dictionary = {}       ## группа → линия; общая на все окна
var lines_on: Dictionary = {}    ## какие группы показаны

## КАРТА ЛИНИЯМИ. Летать сквозь стены с одной клавиатуры неудобно, да и врёт:
## в игре сквозь стены не ходят. Поэтому по лабиринту ХОДЯТ, а чтобы не
## заблудиться — от игрока к каждой важной точке тянется линия ПО КОРИДОРАМ,
## а не напрямую. Тем же способом, каким игра рисует линию к монстру.
const GROUPS := [
	["полотна", Color(0.35, 0.85, 0.45)],
	["гнёзда (скримеры)", Color(0.95, 0.35, 0.3)],
	["столы с записками", Color(0.85, 0.75, 0.35)],
	["убежища", Color(0.4, 0.7, 1.0)],
	["капель", Color(0.55, 0.8, 0.85)],
	["выход", Color(1.0, 1.0, 1.0)],
	["пролом и насыпь", Color(0.95, 0.6, 0.25)],
	["монстр", Color(0.9, 0.25, 0.55)],
]
## ЗАМОК ОДНОГО ЭКЗЕМПЛЯРА. Держим его открытым всё время жизни приложения:
## пока он жив, порт занят, и второй экземпляр это увидит.
var lock_srv: TCPServer
## Необычный порт, чтобы случайно не столкнуться с чем-то настоящим.
const LOCK_PORT := 47231


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Окна должны быть НАСТОЯЩИМИ окнами системы, а не картинками внутри одного:
	# смысл лаборатории в том, чтобы разложить их по экрану рядом.
	get_tree().root.gui_embed_subwindows = false
	# ПУЛЬТ, А НЕ ВТОРОЕ ТАКОЕ ЖЕ ОКНО. Ступица открывалась во весь экран, и
	# рядом с окном звуков читалась как ещё одна лаборатория, работающая сама
	# по себе. Так и было сказано: «открывается сразу 2 окна, которые работают
	# отдельно». Окон и правда два — пульт и окно, — но выглядеть они должны
	# по-разному, иначе непонятно, какое из них главное.
	#
	# Масштабирование содержимого отключаем: у проекта база 1920×1080 с
	# растяжением, и в маленьком окне весь текст пульта уехал бы в нечитаемую
	# мелочь.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().title = "Лаборатория — пульт"
	get_window().size = Vector2i(660, 430)
	# В УГОЛ, И НЕ ПОД БОЛЬШИЕ ОКНА. Большие открываются плиткой от левого
	# верхнего угла, поэтому пульту место в правом нижнем: он маленький и
	# всегда всплывает, когда по нему щёлкнешь.
	var usable: Rect2i = DisplayServer.screen_get_usable_rect()
	get_window().position = usable.position + usable.size - Vector2i(690, 470)
	_build_hub()
	# ДВА ОКНА ЛАБОРАТОРИИ — ЭТО ДВА РАЗНЫХ МИРА. Каждое строит себе свой
	# лабиринт, свой монстр и свои настройки, и работают они независимо: то,
	# что нажато в одном, во втором не происходит. Само по себе это не ломается,
	# но перепутать их легко, а понять, что их два, — трудно.
	#
	# Определяем занятым портом, а не файлом с номером процесса: OS проверяет
	# живость только своих дочерних процессов, и для чужого экземпляра такая
	# проверка бесполезна (она честно ругается в консоль и возвращает ложь).
	#
	# ОТКАЗЫВАТЬ В ЗАПУСКЕ НЕ СТАНЕМ: порт мог занять кто-то посторонний, и
	# тогда лаборатория просто не открылась бы без объяснений. Лучше сказать.
	lock_srv = TCPServer.new()
	if lock_srv.listen(LOCK_PORT, "127.0.0.1") != OK:
		_warn_twice()
	# САМОПРОВЕРКА. «Окно открылось и ничего не напечатало» — это не проверка:
	# половина здешних вызовов лезет во внутренности мира, и опечатка в имени
	# поля молча вернёт null. Поэтому есть режим, который открывает все окна,
	# жмёт в каждом все кнопки и говорит, что из этого упало.
	if OS.get_cmdline_user_args().has("проверка"):
		await _self_test()
	# Открыть всё сразу — и оставить открытым. Так задумано пользоваться:
	# четыре окна рядом, и в каждом своя сторона игры.
	elif OS.get_cmdline_user_args().has("всё"):
		for row in WINDOWS:
			await _open(String(row[0]))
	else:
		# Открыть ровно одно окно по имени: «-- одно=звуки». Нужно, чтобы
		# ловить беду в одном окне, не открывая остальные.
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("одно="):
				await _open(String(a).substr(5))


func _build_hub() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.055, 0.06, 0.058)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 48.0
	col.offset_top = 40.0
	col.offset_right = -48.0
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var title := Label.new()
	title.text = "ЛАБОРАТОРИЯ — ПУЛЬТ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.72, 0.78, 0.72))
	col.add_child(title)

	var sub := Label.new()
	sub.text = "это маленькое окно — пульт. кнопки открывают и закрывают\nбольшие окна: их можно держать открытыми все сразу."
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.52, 0.56, 0.52))
	col.add_child(sub)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 18)
	col.add_child(pad)

	for row in WINDOWS:
		var key: String = row[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		col.add_child(line)
		var b := Button.new()
		b.text = String(row[1])
		b.custom_minimum_size = Vector2(196, 38)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_toggle.bind(key))
		line.add_child(b)
		btns[key] = b
		var why := Label.new()
		why.text = String(row[2])
		why.add_theme_font_size_override("font_size", 15)
		why.add_theme_color_override("font_color", Color(0.5, 0.54, 0.5))
		why.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(why)

	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(0, 16)
	col.add_child(pad2)

	note = Label.new()
	note.text = ""
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.6))
	col.add_child(note)


func _warn_twice() -> void:
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 0.0
	box.offset_bottom = 64.0
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.42, 0.14, 0.12)
	box.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.text = "ЛАБОРАТОРИЯ, ПОХОЖЕ, УЖЕ ОТКРЫТА. Это второе окно, и у него СВОЙ" \
		+ " лабиринт: нажатое здесь в том окне не произойдёт. Закрой лишнее."
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.84))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	add_child(box)
	get_window().title = "Лаборатория — ВТОРОЕ ОКНО"


## Нажал на открытое — закрылось. Иначе пульт выглядит так, будто кнопка не
## работает: окно-то уже открыто, просто спряталось за другими.
func _toggle(key: String) -> void:
	if wins.has(key) and is_instance_valid(wins[key]):
		_close(key)
		return
	await _open(key)


func _mark() -> void:
	for k in btns.keys():
		var open_now: bool = wins.has(k) and is_instance_valid(wins[k])
		var b: Button = btns[k]
		var base: String = ""
		for row in WINDOWS:
			if String(row[0]) == String(k):
				base = String(row[1])
		b.text = ("● " if open_now else "") + base


func _say(text: String) -> void:
	if note != null:
		note.text = text


## Мир строим ОДИН РАЗ и только когда он впервые понадобился: окно монстра
## обходится без него, и грузить лабиринт ради него значит ждать на пустом месте.
func _ensure_game() -> bool:
	if game_ready:
		return true
	# ЖДЁМ, А НЕ СТРОИМ ВТОРОЙ. Постройка идёт через кадр, и два быстрых
	# щелчка по разным кнопкам успевали войти сюда оба: получалось два
	# лабиринта, два игрока и два монстра в одном приложении.
	if building:
		while building:
			await get_tree().process_frame
		return game_ready
	building = true
	holder = SubViewport.new()
	# МИР ЗАДАЁМ ЯВНО, А НЕ ФЛАЖКОМ own_world_3d. С флажком движок создаёт мир
	# сам, а поле world_3d остаётся ПУСТЫМ — и окнам я передавал пустоту.
	# Самопроверка это и поймала: «мир ДРУГОЙ» в каждом окне. Ровно та порода
	# ошибки, ради которой проверка и написана: ни одного сообщения об ошибке,
	# просто окна показывают не то.
	holder.world_3d = World3D.new()
	holder.render_target_update_mode = SubViewport.UPDATE_DISABLED
	holder.size = Vector2i(4, 4)
	add_child(holder)
	game = WorldScene.instantiate()
	holder.add_child(game)
	# Игровой интерфейс в лаборатории лишний: он нарисовался бы поверх ступицы
	# и поверх каждого окна, которое смотрит в этот мир.
	await get_tree().process_frame
	_hide_game_ui()
	_make_lines()
	game_ready = true
	building = false
	return true


## Линии заводим один раз и в том же мире, что лабиринт: они общие на все окна,
## как и лампа осмотра, — по той же причине, что мир один.
func _make_lines() -> void:
	for row in GROUPS:
		var nm: String = row[0]
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = row[1]
		mat.emission_enabled = true
		mat.emission = row[1]
		mat.emission_energy_multiplier = 2.4
		# Сквозь камень их видно нарочно: иначе линия к точке за углом
		# обрывается ровно там, где она и нужна.
		mat.no_depth_test = true
		mi.material_override = mat
		mi.visible = false
		holder.add_child(mi)
		lines[nm] = mi
		lines_on[nm] = false


func line_toggle(group: String) -> bool:
	if not lines.has(group):
		return false
	lines_on[group] = not bool(lines_on[group])
	return bool(lines_on[group])


## ЦЕЛЬ ДОЛЖНА БЫТЬ ПОЛОМ. Гнёзда висят НА СТЕНЕ, и клетка, в которой они
## стоят, — это камень: пути к ней нет, и линия не рисуется. Замер показал
## ровно это: «целей 10, полос 9». Переводим такую цель на соседнюю клетку
## пола — по камню всё равно не ходят, а подойти надо к стене с гнездом.
func _walkable(cell: Vector2i) -> Vector2i:
	if not game.maze.is_wall(cell.x, cell.y):
		return cell
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var n: Vector2i = cell + d
		if not game.maze.is_wall(n.x, n.y):
			return n
	return cell


func _targets(group: String) -> Array:
	var out: Array = []
	if game == null:
		return out
	match group:
		"полотна":
			for c in game.canv_cells:
				out.append(c)
		"гнёзда (скримеры)":
			for n in game.nests:
				out.append(game.world_to_cell(n["pos"]))
		"столы с записками":
			for t in game.tables:
				out.append(game.world_to_cell(t["pos"]))
		"убежища":
			for c in game.safe_cells:
				out.append(c)
		"капель":
			for d in game.drips:
				out.append(d["cell"])
		"выход":
			out.append(game.exit_cell)
		"пролом и насыпь":
			for h in game.holes:
				out.append(h)
			if game.climb_cell.x >= 0:
				out.append(game.climb_cell)
		"монстр":
			if game.monster != null:
				out.append(game.world_to_cell(game.monster.global_position))
	return out


func _update_lines() -> void:
	if game == null or game.player_node == null:
		return
	var from: Vector2i = game.world_to_cell(game.player_node.global_position)
	if game.maze.is_wall(from.x, from.y):
		return
	for nm in lines.keys():
		var mi: MeshInstance3D = lines[nm]
		if not bool(lines_on[nm]):
			mi.visible = false
			continue
		var mesh: ImmediateMesh = mi.mesh
		mesh.clear_surfaces()
		var drew: bool = false
		for cell0 in _targets(String(nm)):
			var cell: Vector2i = _walkable(cell0)
			var path: Array = game.maze.path_weighted(from, cell, 1, 1)
			mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			if path.size() < 2:
				# ТЫ СТОИШЬ НА НЕЙ. Путь длиной в одну клетку рисовать нечем, и
				# раньше такая цель просто исчезала: замер давал «целей 8,
				# полос 7», и понять, потерялась линия или я на ней стою, было
				# нельзя. Теперь вместо линии — короткая метка вверх.
				mesh.surface_add_vertex(game.cell_to_world(cell, 0.12))
				mesh.surface_add_vertex(game.cell_to_world(cell, 1.1))
			else:
				mesh.surface_add_vertex(game.cell_to_world(from, 0.12))
				for c2 in path:
					mesh.surface_add_vertex(game.cell_to_world(c2, 0.12))
			mesh.surface_end()
			drew = true
		mi.visible = drew


func _process(_delta: float) -> void:
	if game_ready:
		_update_lines()


func _hide_game_ui() -> void:
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false


func _open(key: String) -> void:
	if wins.has(key) and is_instance_valid(wins[key]):
		var w: Window = wins[key]
		w.visible = true
		w.grab_focus()
		return
	var win := Window.new()
	win.title = "%s — лаборатория" % String(key).capitalize()
	# ПЛИТКОЙ ПО ЭКРАНУ, А НЕ ЛЕСЕНКОЙ. Сдвиг на несколько десятков пикселей
	# складывал четыре окна почти друг на друга, и «разложить рядом» — то,
	# ради чего лаборатория и делается, — не получалось. Считаем от настоящего
	# размера экрана: четверть на окно, с полями.
	var scr: Vector2i = DisplayServer.screen_get_usable_rect().size
	var n: int = wins.size()
	var cw: int = maxi(720, scr.x / 2 - 24)
	var ch: int = maxi(520, scr.y / 2 - 40)
	win.size = Vector2i(cw, ch)
	win.position = Vector2i(12 + (n % 2) * (cw + 12),
		34 + (n / 2) * (ch + 34))
	win.close_requested.connect(_close.bind(key))
	add_child(win)
	wins[key] = win
	match key:
		"монстр":
			_fill_monster(win)
		_:
			# Остальные окна смотрят в настоящий мир — его и ждём.
			_say("строю лабиринт…")
			await _ensure_game()
			_say("")
			_fill_world_window(key, win)
	_mark()


func _close(key: String) -> void:
	if not wins.has(key) or not is_instance_valid(wins[key]):
		return
	var w: Window = wins[key]
	wins.erase(key)
	w.queue_free()
	_mark()


## ОКНО МОНСТРА. Смотровая уже умеет всё, что он просил: тело, походка, приёмы,
## внешность в игровом свете и в белой комнате. Здесь она просто живёт в окне.
func _fill_monster(win: Window) -> void:
	var v := ViewerScene.instantiate()
	v.in_lab = true
	v.want_close.connect(_close.bind("монстр"))
	win.add_child(v)


## ОКНА, СМОТРЯЩИЕ В МИР. Один и тот же World3D отдаётся нескольким окнам —
## каждое рисует его своей камерой. Так лампа в окне декораций это та самая
## лампа, которая стоит в игре, а не её двойник.
func _fill_world_window(key: String, win: Window) -> void:
	win.world_3d = holder.world_3d
	var fly := LabFly.new()
	fly.game = game
	fly.kind = key
	fly.lab = self
	win.add_child(fly)


## ПРОГОН ЛАБОРАТОРИИ. Открыть каждое окно, нажать в нём каждую кнопку и
## посмотреть, осталось ли оно живым. Ошибки GDScript печатаются сами — здесь
## важно лишь дойти до конца и не встать на первой же кнопке.
func _self_test() -> void:
	var bad: int = 0
	for row in WINDOWS:
		var key: String = row[0]
		print("[лаб] окно «%s»" % key)
		await _open(key)
		await get_tree().process_frame
		await get_tree().process_frame
		if not wins.has(key) or not is_instance_valid(wins[key]):
			print("[лаб] !!! окно «%s» не открылось" % key)
			bad += 1
			continue
		var win: Window = wins[key]
		var pressed: int = 0
		var total: int = 0
		# КНОПКУ ВЫХОДА НЕ ЖМЁМ. На первом прогоне прогон нажал её в окне
		# монстра, окно закрылось, и дальше цикл ждал кадр от узла, которого
		# уже нет в дереве: ожидание не возвращалось никогда, и проверка
		# вставала намертво. Хорошая ловушка, но не то, что мы проверяем.
		for n in _all_buttons(win):
			if not is_instance_valid(n) or not is_instance_valid(win):
				break
			var b: Button = n
			total += 1
			# Точное совпадение, а не «содержит». По «содержит» фильтр съел
			# «выход из стены (рядом)» и «выход из стены (поодаль)» — то есть
			# ровно те кнопки, которые важнее всех прочих проверить.
			if String(b.text).to_lower() == "выход (esc)":
				continue
			b.emit_signal("pressed")
			pressed += 1
			await get_tree().process_frame
		if not is_instance_valid(win):
			print("[лаб] !!! окно «%s» закрылось само посреди прогона" % key)
			bad += 1
			continue
		print("[лаб] окно «%s»: кнопок %d, нажато %d, узлов внутри %d"
			% [key, total, pressed, _count(win)])
		for n2 in win.get_children():
			if n2 is Node3D and n2.has_method("report"):
				print("[лаб] %s" % n2.report())
		if pressed == 0:
			print("[лаб] !!! в окне «%s» не нашлось ни одной кнопки" % key)
			bad += 1
	# И САМ МИР. Кнопки могли нажаться и в пустоте: если лабиринт не собрался,
	# всё, что окна показывают, — это чёрный экран без единой ошибки.
	if game_ready:
		print("[лаб] мир: узлов %d, игрок %s, монстр %s, полотен %d, столов %d, убежищ %d"
			% [_count(game), "есть" if game.player_node != null else "НЕТ",
				"есть" if game.monster != null else "НЕТ",
				game.canv_cells.size(), game.tables.size(), game.safe_cells.size()])
		if game.player_node == null or game.monster == null or game.canv_cells.is_empty():
			print("[лаб] !!! мир собрался неполным")
			bad += 1
	else:
		print("[лаб] !!! мир так и не собрался")
		bad += 1
	# ЛИНИИ. «Кнопка нажалась» не значит «линия нарисовалась»: список целей
	# может оказаться пустым, а путь по коридорам — не найтись. Проверяем по
	# числу построенных полос в самой сетке.
	if game_ready:
		# СТАВИМ ИГРОКА НА СТАРТ. Прогон перед этим жал кнопки прыжков и мог
		# оставить его прямо в той клетке, к которой мерим линию: путь тогда
		# длиной в одну клетку, и полоса честно не рисуется. Замер не должен
		# зависеть от порядка нажатий — иначе он мерит прогон, а не игру.
		if game.player_node != null:
			game.player_node.global_position = game.cell_to_world(game.start_cell, 0.85)
		for row in GROUPS:
			var nm: String = row[0]
			lines_on[nm] = true
		_update_lines()
		for row in GROUPS:
			var nm2: String = row[0]
			var mi: MeshInstance3D = lines[nm2]
			var strips: int = (mi.mesh as ImmediateMesh).get_surface_count()
			print("[лаб] линии «%s»: целей %d, полос %d%s" % [
				nm2, _targets(nm2).size(), strips,
				"" if strips > 0 else "   !!! НИ ОДНОЙ"])
			if strips == 0:
				bad += 1
			lines_on[nm2] = false
	print("[лаб] ИТОГ: %s" % ("всё открылось" if bad == 0 else "беда в %d окнах" % bad))
	get_tree().quit()


func _all_buttons(n: Node) -> Array:
	var out: Array = []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_buttons(c))
	return out


func _count(n: Node) -> int:
	var k: int = 1
	for c in n.get_children():
		k += _count(c)
	return k
