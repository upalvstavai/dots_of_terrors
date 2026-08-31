extends Node3D
## ТОЧКИ УЖАСА — сборка мира.
##
## Вешается на пустой Node3D, внутрь кладётся Player — и F5. Пол, стены с физикой,
## освещение и расстановка игрока делаются здесь.
##
## Стены НЕ ставятся по одной клетке. Тайлов камня выходит около 950, и столько
## отдельных объектов — зря потраченный кадр. Соседние клетки склеиваются
## в прямоугольники: замер на 50 картах — 950 тайлов превращаются в 75 коробок,
## в 12.7 раза меньше. Покрытие точное, ни одна коробка не залезает на пол.

## Грузим генератор ПО ПУТИ, а не через class_name. Имя класса появляется только
## после того, как Godot проиндексировал файл; пока этого не случилось, скрипт
## не парсится, а сцена с непарсящимся скриптом выдаёт «ошибка при загрузке файла».
const MazeGenScript := preload("res://MazeGen.gd")
const BoardScript := preload("res://Board.gd")
const Shapes := preload("res://Shapes.gd")
const Notes := preload("res://Notes.gd")
const NoteUIScript := preload("res://NoteUI.gd")
const MonsterScript := preload("res://Monster.gd")
const SfxScript := preload("res://Sfx.gd")
const WALL_SHADER := preload("res://wall.gdshader")
const GrabScript := preload("res://Grab.gd")
const ScareScript := preload("res://Scare.gd")

## СКРИМЕРЫ. Скример — событие, а не реакция на поимку: если бить каждый раз,
## к третьему это раздражение, а не страх. Право копится и тратится редко.
const SCARE_CHANCE := {"monster": 0.6, "lash": 0.2}
const SCARE_MIN_GAP := 25.0    ## жёсткий пол между ЛЮБЫМИ двумя скримерами
const MON_COOL := 45.0         ## «монстр пугает всегда» верно ровно один раз
const DEATH_LIMIT := 3

## ЩУПАЛЬЦА ИЗ ЛЮБОЙ СТЕНЫ. Пугает не сила удара, а неожиданность, а к частому
## неожиданности не бывает: игрок привыкал к ним за один забег.
const LASH_FIRST := [30.0, 50.0]
const LASH_REPEAT := [110.0, 180.0]
const LASH_MISS := 0.5
const TELL := 0.85             ## сколько стена «дышит» перед ударом
const TELL_LOOK := 0.35        ## косинус: ±70°. Спасает ВЗГЛЯД, а не бегство

## ПОДСКАЗКИ СОЗДАТЕЛЯ. Выключены по умолчанию и переключаются клавишами прямо
## в игре: если держать их константой в коде, однажды отдашь сборку с включённой
## линией к выходу — и человек пройдёт лабиринт по ней, то есть не сыграет вовсе.
##   G — нить к текущей цели (полотно, а после шести — выход)
##   M — линия к монстру (появится, когда монстр будет перенесён)

@export var cell_size: float = 2.4        ## метров в клетке — та же, что у игрока
@export var wall_height: float = 2.9      ## в прототипе стена 58 при клетке 48
@export var regenerate_seed: bool = true  ## новый лабиринт на каждый запуск
@export var fixed_seed: int = 20260825    ## если regenerate_seed выключен

@export_group("Освещение")
## Игра задумана в полной темноте: свет даёт только палочка. Но собирать мир вслепую
## невозможно, поэтому пока оставлен слабый общий свет. Ставь 0.0, когда дойдёшь
## до фонарика.
@export var ambient: float = 0.6
## Временный фонарь на игроке. Ставь 0.0, когда сделаешь палочку.
@export var player_light: float = 1.4

var maze
var start_cell: Vector2i
var exit_cell: Vector2i
var canv_cells: Array[Vector2i] = []
var canv_marks: Array[MeshInstance3D] = []
var exit_mark: MeshInstance3D
var room_cells: Array[Vector2i] = []
var shapes: Array = []

var done: int = 0          ## сдано полотен
var fear: float = 1.0      ## множитель дрожи на следующем полотне
var errors: int = 0        ## ошибок за забег — из них растёт безумие
var player_node: Node3D
var board
var note_ui
var hud: Label
var mad_hud: Label
var tables: Array = []          ## {pos: Vector3, text: String, read: bool}
var journal: Array = []
var has_wand: bool = false
var canvas_arm: bool = true     ## пока не отошёл от полотна, следующее не откроется
var finale: bool = false        ## идёт финальная дверь
var won: bool = false
var monster
var phase: int = 1              ## 1 — он в камне, 2 — глухота, 3 — он снаружи
var anger: int = 0              ## растёт после потолка ошибок, разгоняет монстра
var captures: int = 0
var sfx
var grab_ui
var scare_ui
var lash_t: float = 0.0
var tell_t: float = -1.0        ## идёт предупреждение
var tell_pos: Vector3
var tell_miss: bool = false
var streak: int = 0             ## поимок подряд
var mon_kills: int = 0          ## поимок именно монстром — они не прощаются
var _last_loud: float = -999.0
var _mon_scare_t: float = -999.0
var _clock: float = 0.0
var dead: bool = false
var nests: Array = []           ## {pos, used}
var nests_hit: int = 0
var safe_cells: Array[Vector2i] = []
var safe_sit: float = 0.0       ## сколько сидишь в убежище
var ambush_done: bool = false
var ambush_t: float = -1.0
var burst_t: float = 0.0
var ring_t: float = 0.0
var visited := {}               ## клетки, где ты уже был — палочка их метит
var eyes: Array = []            ## красные глаза по краям экрана от безумия
var eyes_layer: Control
var dev: bool = false           ## подсказки создателя
var mad_said := {}              ## какие пороги безумия уже объявлены
var wall_mat: ShaderMaterial
var env_ref: Environment
var _skit_t: float = 0.0
var _heart_t: float = 0.0
var _breath_t: float = 0.0
var mon_on: bool = false        ## линия к монстру [M]
var mon_line: MeshInstance3D
var thread_on: bool = false
var thread_line: MeshInstance3D
var _thread_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Строим по шагам с ловлей: если упадёт расстановка, мир всё равно соберётся,
	# игрок сможет ходить и, главное, отпустить курсор и прочитать ошибку.
	maze = MazeGenScript.new()
	var s := randi() if regenerate_seed else fixed_seed
	maze.generate(s)
	var guard := 0
	while not maze.is_good(_first_floor()) and guard < 60:
		guard += 1
		s = randi()
		maze.generate(s)
	print("Лабиринт собран, сид ", s, ", размер ", maze.size)

	start_cell = _first_floor()
	_rng.seed = s
	shapes = Shapes.pick(_rng)
	_build_environment()
	_build_floor()
	_build_walls()
	_place_features()
	_place_tables()
	_place_decor()
	_place_safe()
	_build_ui()
	_place_player()
	sfx = SfxScript.new()
	add_child(sfx)
	_spawn_monster()
	_set_cursor(false)
	set_process(true)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.62)
	env.ambient_light_energy = 1.0
	env.fog_enabled = false                    # туман съедает дальние коридоры
	env.fog_light_color = Color(0.02, 0.02, 0.03)
	env.fog_density = 0.06
	env_ref = env
	we.environment = env
	add_child(we)


func _build_floor() -> void:
	var fw = maze.size.x * cell_size
	var fh = maze.size.y * cell_size
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(fw, 0.4, fh)
	mi.mesh = m
	mi.material_override = _material(Color(0.28, 0.28, 0.30))
	mi.position = Vector3(fw * 0.5, -0.2, fh * 0.5)
	add_child(mi)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = m.size
	cs.shape = shape
	body.position = mi.position
	body.add_child(cs)
	add_child(body)


func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	# Коробке нужна сетка, иначе смещать в шейдере нечего: у BoxMesh по умолчанию
	# восемь вершин, и рельеф просто не на чем построить.
	var mat := ShaderMaterial.new()
	mat.shader = WALL_SHADER
	wall_mat = mat

	for box in _merge_walls():
		var br: int = box.x
		var bc: int = box.y
		var bh: int = box.z          # сколько клеток вниз
		var bw: int = box.w          # сколько клеток вправо
		var centre := Vector3((bc + bw * 0.5) * cell_size, wall_height * 0.5, (br + bh * 0.5) * cell_size)

		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(bw * cell_size, wall_height, bh * cell_size)
		m.subdivide_width = clampi(int(bw * 3), 1, 24)
		m.subdivide_depth = clampi(int(bh * 3), 1, 24)
		m.subdivide_height = 6
		mi.mesh = m
		mi.material_override = mat
		mi.position = centre
		body.add_child(mi)

		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = m.size
		cs.shape = shape
		cs.position = centre
		body.add_child(cs)


## Жадная склейка: тянем прямоугольник вправо, потом вниз, пока строки совпадают.
## Vector4i(строка, столбец, высота_в_клетках, ширина_в_клетках).
func _merge_walls() -> Array[Vector4i]:
	var out: Array[Vector4i] = []
	var seen := {}
	for r in maze.size.y:
		for c in maze.size.x:
			if maze.grid[r][c] != 1 or seen.has(Vector2i(r, c)):
				continue
			var w := 0
			while c + w < maze.size.x and maze.grid[r][c + w] == 1 and not seen.has(Vector2i(r, c + w)):
				w += 1
			var h := 1
			while r + h < maze.size.y:
				var fits := true
				for k in w:
					if maze.grid[r + h][c + k] != 1 or seen.has(Vector2i(r + h, c + k)):
						fits = false
						break
				if not fits:
					break
				h += 1
			for a in h:
				for b in w:
					seen[Vector2i(r + a, c + b)] = true
			out.append(Vector4i(r, c, h, w))
	return out


func _place_player() -> void:
	var p := find_child("Player", true, false) as Node3D
	if p == null:
		push_warning("Player в сцене не найден — добавь его дочерним узлом к World")
		return
	player_node = p
	if p.has_signal("wall_touched"):
		p.wall_touched.connect(_on_wall_touched)
	if p.has_signal("stepped"):
		p.stepped.connect(func(): if sfx != null: sfx.play("step", -12.0))
	p.global_position = cell_to_world(start_cell, 0.85)
	if player_light > 0.0 and p.has_node("Head"):
		var lamp := OmniLight3D.new()
		lamp.light_energy = player_light
		lamp.light_color = Color(0.85, 0.88, 0.95)
		lamp.omni_range = 14.0
		p.get_node("Head").add_child(lamp)
	print("Игрок поставлен в клетку ", start_cell, " -> ", p.global_position)


## Клетка лабиринта -> точка в мире. Пригодится для полотен, столов и монстра.
func cell_to_world(cell: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3((cell.y + 0.5) * cell_size, y, (cell.x + 0.5) * cell_size)


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.z / cell_size), int(pos.x / cell_size))


func _first_floor() -> Vector2i:
	for r in maze.size.y:
		for c in maze.size.x:
			if maze.grid[r][c] == 0:
				return Vector2i(r, c)
	return Vector2i(1, 1)


func _material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.metallic = 0.0
	return m


# ─────────────────────────── полотна и выход ───────────────────────────

## Шесть полотен равномерно по ГЛУБИНЕ лабиринта от старта, выход — самая дальняя точка.
## Не по прямой: в лабиринте прямая ничего не значит, важно, сколько идти.
func _place_features() -> void:
	var dist: Dictionary = maze.distances(start_cell)
	var deepest := 0
	for v in dist.values():
		deepest = maxi(deepest, int(v))

	# Залы сортируем ПО ГЛУБИНЕ и раздаём под полотна. Раньше полотна стояли
	# по глубине где попало, а залы с записками — отдельно и случайно; игрок
	# видел «столы в коридорах». Теперь полотно и записка живут в одной комнате:
	# мимо полотна не пройдёшь, значит и записку увидишь.
	room_cells.clear()
	var by_depth := []
	for room in maze.rooms:
		var cell := _room_cell(room)
		if maze.is_wall(cell.x, cell.y) or not dist.has(cell):
			continue
		by_depth.append({"cell": cell, "d": int(dist[cell])})
	by_depth.sort_custom(func(a, b): return a["d"] < b["d"])
	for r in by_depth:
		room_cells.append(r["cell"])

	canv_cells.clear()
	var n_rooms := room_cells.size()
	var taken: Array[Vector2i] = []
	for k in Shapes.N_CANV:
		var cell: Vector2i
		if n_rooms >= Shapes.N_CANV:
			# берём залы равномерно по списку глубин: от ближнего к дальнему
			var idx: int = int(round(float(k) * (n_rooms - 1) / float(Shapes.N_CANV - 1)))
			cell = room_cells[idx]
		else:
			cell = _cell_at_depth(dist, deepest, [0.18, 0.32, 0.46, 0.60, 0.74, 0.88][k], taken)
		# Мало не совпадать — надо ещё и не стоять впритык: два полотна в соседних
		# залах читаются как одно место, и половина лабиринта остаётся не пройденной.
		var too_close := false
		for u in taken:
			if absi(u.x - cell.x) + absi(u.y - cell.y) < 8:
				too_close = true
				break
		if too_close or taken.has(cell):
			cell = _cell_at_depth(dist, deepest, float(k + 1) / float(Shapes.N_CANV + 1), taken)
		taken.append(cell)
		canv_cells.append(cell)
		canv_marks.append(_marker(cell, Color(0.22, 1.0, 0.62), 1.2))

	var bd2 := -1
	for cell in dist:
		if int(dist[cell]) > bd2 and not canv_cells.has(cell):
			bd2 = int(dist[cell])
			exit_cell = cell
	exit_mark = _marker(exit_cell, Color(1.0, 0.85, 0.35), 2.2)
	_refresh_marks()


## Центр зала в клетках сетки. Rect2i зала — (столбец, строка, ширина, высота)
## в координатах УЗЛОВ, а тайл узла = wall + узел * шаг. Только целыми.
func _room_cell(room) -> Vector2i:
	var step: int = int(maze.corridor) + int(maze.wall)
	var ni: int = int(room.position.y) + int(room.size.y) / 2
	var nj: int = int(room.position.x) + int(room.size.x) / 2
	return Vector2i(int(maze.wall) + ni * step, int(maze.wall) + nj * step)


func _cell_at_depth(dist: Dictionary, deepest: int, frac: float, used: Array[Vector2i] = []) -> Vector2i:
	var want := int(frac * deepest)
	var best: Vector2i = start_cell
	var bd := 1 << 30
	for cell in dist:
		var far := true
		for u in used:
			if absi(u.x - cell.x) + absi(u.y - cell.y) < 5:
				far = false
				break
		if not far:
			continue
		var d: int = absi(int(dist[cell]) - want)
		if d < bd:
			bd = d
			best = cell
	return best


func _marker(cell: Vector2i, col: Color, h: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.9, h, 0.9)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	mi.material_override = mat
	mi.position = cell_to_world(cell, h * 0.5)
	add_child(mi)
	return mi


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	board = BoardScript.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.visible = false
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.solved.connect(_on_solved)
	board.failed.connect(_on_failed)
	board.mistake.connect(_on_mistake)
	layer.add_child(board)
	note_ui = NoteUIScript.new()
	note_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	note_ui.visible = false
	note_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_ui.closed.connect(_on_note_closed)
	layer.add_child(note_ui)
	grab_ui = GrabScript.new()
	grab_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	grab_ui.visible = false
	grab_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grab_ui.escaped.connect(_on_escaped)
	grab_ui.failed.connect(_on_grab_failed)
	layer.add_child(grab_ui)
	scare_ui = ScareScript.new()
	scare_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	scare_ui.visible = false
	scare_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scare_ui.done.connect(_on_scare_done)
	layer.add_child(scare_ui)
	lash_t = randf_range(LASH_FIRST[0], LASH_FIRST[1])
	_ensure_action("read", KEY_E)
	_ensure_action("journal", KEY_J)
	eyes_layer = Control.new()
	eyes_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	eyes_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eyes_layer.draw.connect(_draw_eyes)
	layer.add_child(eyes_layer)
	_load_dev()
	_ensure_action("thread", KEY_G)
	_ensure_action("devmode", KEY_QUOTELEFT)
	_ensure_action("restart", KEY_R)
	_ensure_action("monline", KEY_M)
	_make_thread_line()
	hud = Label.new()
	hud.position = Vector2(16, 14)
	hud.add_theme_color_override("font_color", Color(0.48, 0.66, 0.56))
	layer.add_child(hud)
	mad_hud = Label.new()
	mad_hud.position = Vector2(16, 36)
	layer.add_child(mad_hud)
	_update_hud()


func _update_hud() -> void:
	if done < Shapes.N_CANV:
		hud.text = "ПОЛОТНО %d/%d" % [done + 1, Shapes.N_CANV]
	else:
		hud.text = "НАЙДИ ВЫХОД"
	_update_mad_hud()


func _update_mad_hud() -> void:
	if mad_hud == null:
		return
	mad_hud.text = _madness_bar()
	var st := _madness_stage()
	mad_hud.add_theme_color_override("font_color",
		[Color(0.48, 0.66, 0.56), Color(0.75, 0.7, 0.35), Color(0.85, 0.5, 0.25), Color(0.88, 0.31, 0.24)][st])
	if streak > 0:
		mad_hud.text += "   ПОИМКИ ПОДРЯД %d/%d" % [streak, DEATH_LIMIT]
	if mon_kills > 0:
		mad_hud.text += "   ОНО ДОСТАЛО %d/%d" % [mon_kills, DEATH_LIMIT]


func _process(delta: float) -> void:
	if paused():
		hud.text = "ПАУЗА — щёлкни по игре, чтобы продолжить"
		if player_node != null:
			player_node.set_physics_process(false)
		return
	if player_node != null and not _ui_blocking() and not dead:
		player_node.set_physics_process(true)
	_update_thread(delta)
	_update_mon_line(delta)
	_update_phase()
	_update_sound(delta)
	_clock += delta
	_update_lash(delta)
	_update_nests()
	_update_safe(delta)
	_update_burst(delta)
	_update_ring(delta)
	_update_mad_hud()
	_update_marks()
	_update_eyes(delta)
	if monster != null and player_node != null and not won:
		# Пока игрок рисует, монстр НЕ стоит — он продолжает идти. Но и схватить
		# не может: захват проверяется только когда игрок в коридоре.
		monster.tick(delta, player_node.global_position, anger, done >= Shapes.N_CANV)
		if finale and board.visible:
			board.near = monster.finale_near
			if monster.finale_near >= 1.0:
				board.force_fail()
	if board.visible or player_node == null or note_ui.visible:
		return
	if won:
		return
	if done < Shapes.N_CANV:
		if _near(canv_cells[done]):
			if canvas_arm:
				_open_board()
		else:
			canvas_arm = true
	elif _near(exit_cell) and not finale:
		_open_finale()


func _near(cell: Vector2i) -> bool:
	return player_node.global_position.distance_to(cell_to_world(cell, player_node.global_position.y)) < cell_size * 0.9


func _open_board() -> void:
	board.open(shapes[done], done, fear, _madness_stage(), _rng.randi())
	board.visible = true
	if monster != null and player_node != null:
		monster.park(world_to_cell(player_node.global_position), 5)
	_pause_player(true)


func _close_board() -> void:
	board.visible = false
	if monster != null:
		monster.unpark()
	_pause_player(false)


func _on_solved() -> void:
	if finale:
		_win()
		return
	done += 1
	fear = 1.0            # полотно сдано — страх отпускает
	# Взводим сразу, если следующее полотно и так далеко. Ждать шага в сторону надо
	# только когда цель рядом — иначе игрок мог застрять со снятым взводом.
	canvas_arm = done >= Shapes.N_CANV or not _near(canv_cells[done])
	_close_board()
	_update_hud()
	_refresh_marks()
	if done >= Shapes.N_CANV:
		hud.text = "ВЫХОДА НЕТ. ИДИ К ЖЁЛТОМУ СТОЛБУ."


## Провалил по времени — рисунок осыпался, страх копится и трясёт следующую попытку.
func _on_failed() -> void:
	fear = minf(fear + Shapes.FEAR_STEP, Shapes.FEAR_MAX)
	_add_madness("Рисунок осыпался.")
	if finale:
		# Сорвал дверь — это ОН до тебя дошёл. Значит и последствия те же, что
		# у поимки: очнёшься в убежище и пойдёшь к двери заново. Оставлять игрока
		# стоять у двери бессмысленно — он бы просто открыл её снова на месте.
		finale = false
		board.final = false
		if monster != null:
			monster.finale_mode = false
		board.visible = false
		_capture("monster")
		return
	_close_board()


func _on_mistake() -> void:
	_add_madness("Неверная точка.")


## Стадия безумия: чем больше ошибок, тем хуже ведёт себя лабиринт.
func _madness_stage() -> int:
	var st := 0
	for th in MAD_STAGE:
		if errors >= int(th):
			st += 1
	return st


# ─────────────────────────── столы с записками ───────────────────────────

## В каждой комнате — свой стол. Комнат семь, фраз тоже семь: игрок обходит их
## не подряд, а как попало, и обрывки складываются в голове сами.
## Плюс стартовый стол за спиной игрока — на нём палочка и первая записка.
func _place_tables() -> void:
	journal = Notes.load_journal()
	tables.clear()
	var order: Array = Notes.order(_rng)
	var i := 0
	for cell in room_cells:
		# сдвигаем стол от центра, чтобы он не стоял ровно на полотне
		_add_table(cell_to_world(cell) + Vector3(1.1, 0, 1.1), order[i % order.size()], false)
		i += 1
	_add_table(cell_to_world(start_cell) + Vector3(0, 0, 0.7), Notes.START_NOTE, true)


func _add_table(pos: Vector3, text: String, wand: bool) -> void:
	tables.append({"pos": pos, "text": text, "read": false, "wand": wand})
	var top := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.9, 0.08, 0.55)
	top.mesh = m
	top.material_override = _material(Color(0.22, 0.19, 0.16))
	top.position = pos + Vector3(0, 0.75, 0)
	add_child(top)

	var leg := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.12, 0.75, 0.12)
	leg.mesh = lm
	leg.material_override = top.material_override
	leg.position = pos + Vector3(0, 0.375, 0)
	add_child(leg)

	# Книжка слегка светится: столы стоят в стороне от дороги, и без этого игрок
	# проходит мимо комнаты, ни разу не заглянув внутрь.
	var book := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.05, 0.2)
	book.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.83, 0.74)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.86, 0.7)
	mat.emission_energy_multiplier = 0.5
	book.material_override = mat
	book.position = pos + Vector3(0, 0.82, 0)
	add_child(book)


## Ближайший стол в руке. Луч от ИГРОКА, а не от камеры: камера обновляется позже,
## и до первого кадра книжка «не видна», хотя стоишь вплотную.
func _table_at_hand():
	if player_node == null:
		return null
	var best = null
	var bd := 1.7 * 1.7
	for t in tables:
		var d: float = player_node.global_position.distance_squared_to(t["pos"])
		if d < bd:
			bd = d
			best = t
	return best


func _read_table() -> void:
	var t = _table_at_hand()
	if t == null:
		return
	t["read"] = true
	if t["wand"]:
		has_wand = true
		if player_node != null:
			player_node.has_wand = true
	if not journal.has(t["text"]):
		journal.append(t["text"])
		Notes.save_journal(journal)
	note_ui.show_note(t["text"])
	_pause_player(true)


## ЕДИНСТВЕННЫЙ хозяин курсора — этот скрипт. Раньше режим мыши писали и игрок,
## и мир: игрок по Esc отпускал курсор, а мир через мгновение забирал обратно —
## отсюда «стрелка появляется и через секунду пропадает». Два владельца одного
## глобального состояния всегда кончаются такой дракой.
var _ui_open: bool = false

## Esc теперь ставит игру НА ПАУЗУ, а не просто отпускает курсор.
## Из-за этого и «возвращалась стрелка»: пока ты смотрел на ошибки со свободным
## курсором, мир продолжал жить — тикали щупальца, подходил монстр. Он хватал,
## открывался QTE, и на выходе из него курсор честно забирался обратно.
## Дело было не в курсоре: игра просто не останавливалась.
## Открыто ли какое-нибудь окно поверх игры.
func _ui_blocking() -> bool:
	return board.visible or note_ui.visible or grab_ui.visible or scare_ui.visible


func paused() -> bool:
	return _ui_open and not _ui_blocking()


func _set_cursor(free: bool) -> void:
	if (board != null and board.visible) or (note_ui != null and note_ui.visible):
		free = true                        # пока открыто окно, курсор нужен всегда
	_ui_open = free
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


func _pause_player(on: bool) -> void:
	if player_node != null:
		player_node.set_physics_process(not on)
	_set_cursor(on)


func _unhandled_input(event: InputEvent) -> void:
	# ESC ПЕРВЫМ и без единой зависимости. Если ниже что-то упадёт — не важно что,
	# необработанный null или сломанный узел, — обработчик умрёт целиком, и курсор
	# останется захваченным навсегда. Тогда нельзя ни закрыть окно, ни скопировать
	# текст ошибки, то есть нельзя даже узнать, что сломалось.
	# Esc ТОЛЬКО отпускает и никогда не забирает обратно: возврат к управлению
	# камерой — по щелчку мышью внутри игры. Так эти два действия не спорят.
	if grab_ui != null and grab_ui.visible:
		if event.is_action_pressed("sprint"):
			grab_ui.press()
		return
	if event.is_action_pressed("restart"):
		_restart()
		return
	if event.is_action_pressed("ui_cancel"):
		if note_ui != null and note_ui.visible:
			note_ui.close()
		_set_cursor(true)
		return
	# Щелчок по игре снимает паузу. Условие именно paused(), а не «курсор свободен»:
	# при открытом полотне курсор тоже свободен, и клик по точке не должен
	# возвращать захват мыши посреди рисования.
	if event is InputEventMouseButton and event.pressed and paused():
		_set_cursor(false)
	if board != null and board.visible:
		return
	if note_ui == null:
		return
	if event.is_action_pressed("read"):
		if note_ui.visible:
			note_ui.close()
		else:
			_read_table()
	elif event.is_action_pressed("devmode"):
		_toggle_dev()
	elif event.is_action_pressed("thread") and dev:
		thread_on = not thread_on
		_thread_t = 0.0
		hud.text = "НИТЬ: ВКЛ" if thread_on else "НИТЬ: ВЫКЛ"
		await get_tree().create_timer(1.2).timeout
		_update_hud()
	elif event.is_action_pressed("flash"):
		_do_flash()
	elif event.is_action_pressed("monline") and dev:
		mon_on = not mon_on
		if monster != null:
			monster.set_xray(mon_on)     # видно его самого сквозь камень, а не только путь
	elif event.is_action_pressed("journal"):
		if note_ui.visible:
			note_ui.close()
		else:
			note_ui.show_journal(journal)
			_pause_player(true)
	elif event.is_action_pressed("ui_cancel"):
		if note_ui.visible:
			note_ui.close()
		else:
			_set_cursor(true)


func _on_note_closed() -> void:
	_pause_player(false)


func _ensure_action(action: String, key: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


# ─────────────────────────── нить создателя ───────────────────────────

func _make_thread_line() -> void:
	thread_line = _make_line(Color(0.60, 0.48, 0.85))


## Пересчитываем не каждый кадр: путь по коридорам меняется медленно, а поиск
## по всей карте на каждом кадре — пустая трата.
func _update_thread(delta: float) -> void:
	if not thread_on or player_node == null:
		thread_line.visible = false
		return
	_thread_t -= delta
	if _thread_t > 0.0:
		return
	_thread_t = 0.35
	var from := world_to_cell(player_node.global_position)
	if maze.is_wall(from.x, from.y):
		thread_line.visible = false
		return
	var target: Vector2i = exit_cell if done >= Shapes.N_CANV else canv_cells[done]
	var path := _path(from, target)
	var mesh: ImmediateMesh = thread_line.mesh
	mesh.clear_surfaces()
	if path.size() < 2:
		thread_line.visible = false
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for cell in path:
		mesh.surface_add_vertex(cell_to_world(cell, 0.08))
	mesh.surface_end()
	thread_line.visible = true


## Путь по полу от клетки к клетке. Волна и обратный ход по родителям.
func _path(from: Vector2i, to: Vector2i) -> Array:
	var prev := {from: from}
	var q: Array[Vector2i] = [from]
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		if cur == to:
			break
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = cur + d
			if not maze.is_wall(n.x, n.y) and not prev.has(n):
				prev[n] = cur
				q.append(n)
	if not prev.has(to):
		return []
	var out: Array[Vector2i] = []
	var cur2: Vector2i = to
	while cur2 != from:
		out.append(cur2)
		cur2 = prev[cur2]
	out.append(from)
	out.reverse()
	return out


# ─────────────────────────── финал ───────────────────────────

## Выхода нет. Есть стена, и дверь надо НАРИСОВАТЬ — тем самым действием, которым
## игрок занимался всю игру. Раньше добежал до выхода — и просто менялась надпись
## в углу; последние тридцать секунд, то есть ровно то, что человек потом
## пересказывает, были пустыми.
## Вместо таймера — он сам. Встаёт в четырнадцати клетках и идёт по коридору;
## полоска над доской не убывает, а НАПОЛНЯЕТСЯ по мере его приближения.
## Идёт медленно и только коридорами: у игрока должно быть ровно столько времени,
## сколько монстру идти, — не больше и не меньше.
const FINAL_DIST := 14
const FINAL_SPEED := 0.27      ## клеток в секунду

func _open_finale() -> void:
	finale = true
	board.final = true
	if monster != null and player_node != null:
		monster.to_finale(world_to_cell(player_node.global_position), FINAL_DIST, FINAL_SPEED)
	board.open(Shapes.DOOR, 0, fear, _madness_stage(), _rng.randi())
	board.visible = true
	_pause_player(true)
	hud.text = "НАРИСУЙ ДВЕРЬ"


## Дорисовал — впервые за всю игру появляется свет. Он бьёт из двери, которую
## игрок только что нарисовал.
func _win() -> void:
	won = true
	finale = false
	if monster != null:
		monster.mode = "gone"
	board.visible = false
	_pause_player(true)
	hud.text = ""
	var flash := ColorRect.new()
	flash.color = Color(1, 0.98, 0.93, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.get_parent().add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 1.0, 2.2)
	tw.tween_callback(_show_win_text.bind(flash))


func _show_win_text(flash: ColorRect) -> void:
	var lbl := Label.new()
	lbl.text = "ТЫ ВЫБРАЛСЯ\n\nДверь ты нарисовал сам. Как и всё остальное здесь.\n\nR — ещё раз"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.1, 0.09, 0.08))
	lbl.add_theme_font_size_override("font_size", 22)
	flash.add_child(lbl)


func _restart() -> void:
	get_tree().reload_current_scene()


## Все шесть столбов стояли одинаково зелёными с первой секунды, и понять, какой
## сейчас живой, было нельзя: игрок проходил сквозь дальний и решал, что тот сломан.
## Живой горит ярко, пройденные гаснут, будущие едва тлеют.
func _refresh_marks() -> void:
	for i in canv_marks.size():
		var mat: StandardMaterial3D = canv_marks[i].material_override
		if i < done:
			mat.albedo_color = Color(0.14, 0.20, 0.16)
			mat.emission = Color(0.10, 0.16, 0.13)
			mat.emission_energy_multiplier = 0.15
		elif i == done:
			mat.albedo_color = Color(0.22, 1.0, 0.62)
			mat.emission = Color(0.22, 1.0, 0.62)
			mat.emission_energy_multiplier = 2.2
		else:
			mat.albedo_color = Color(0.18, 0.42, 0.30)
			mat.emission = Color(0.16, 0.40, 0.28)
			mat.emission_energy_multiplier = 0.35
	if exit_mark != null:
		var em: StandardMaterial3D = exit_mark.material_override
		var live := done >= Shapes.N_CANV
		em.emission_energy_multiplier = 2.6 if live else 0.3


# ─────────────────────────── монстр ───────────────────────────

func _spawn_monster() -> void:
	monster = MonsterScript.new()
	add_child(monster)
	monster.setup(maze, cell_size, 3.2, _rng.randi())
	monster.place_far_from(start_cell, maze.wall_skin())
	monster.emerged.connect(_on_emerged)
	monster.caught.connect(_on_caught)
	mon_line = _make_line(Color(0.88, 0.35, 0.27))


func _on_emerged() -> void:
	phase = 3
	hud.text = "СТЕНА ЛОПНУЛА. ОНО ВЫШЛО."


## Пока QTE не перенесён — поимка просто отбрасывает игрока на старт и злит лабиринт.
## Сама механика вырывания придёт следующим слоем.
func _far_cell_from(cell: Vector2i) -> Vector2i:
	var dist: Dictionary = maze.distances(cell)
	var best := cell
	var bd := -1
	for c in dist:
		if int(dist[c]) > bd:
			bd = int(dist[c])
			best = c
	return best


## Фазы. Первая — он в камне и только слышен. Вторая — шум игрока отбирает слух.
## Третья наступает не по таймеру, а когда он подобрался сквозь камень вплотную.
func _update_phase() -> void:
	pass


func _update_mon_line(delta: float) -> void:
	if not mon_on or monster == null or player_node == null:
		mon_line.visible = false
		return
	var from: Vector2i = world_to_cell(player_node.global_position)
	var to: Vector2i = world_to_cell(monster.global_position)
	if maze.is_wall(from.x, from.y):
		mon_line.visible = false
		return
	var path: Array = maze.path_weighted(from, to, 1, 1)
	var mesh: ImmediateMesh = mon_line.mesh
	mesh.clear_surfaces()
	if path.size() < 2:
		mon_line.visible = false
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	mesh.surface_add_vertex(cell_to_world(from, 0.12))
	for cell in path:
		mesh.surface_add_vertex(cell_to_world(cell, 0.12))
	mesh.surface_end()
	mon_line.visible = true


func _make_line(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	return mi


# ─────────────────────────── слух ───────────────────────────

## Единственный сенсор игрока в первых двух фазах. Монстра не видно вообще —
## он в камне, — и понять, где он и насколько близко, можно только на слух.
## Шум самого игрока этот слух отбирает: чем громче идёшь, тем глуше скрежет.
## Отсюда и вся вторая фаза: лучшая тишина в игре — твоя собственная.
func _update_sound(delta: float) -> void:
	if sfx == null or monster == null or player_node == null or won:
		return
	var d: float = player_node.global_position.distance_to(monster.global_position)
	var hearing: float = player_node.hearing()

	_skit_t -= delta
	if _skit_t <= 0.0:
		var near: float = clampf(1.0 - d / (cell_size * 10.0), 0.0, 1.0)
		if near > 0.02:
			# Звук идёт ИЗ ТОЧКИ, где монстр: направление слышно, и по нему
			# игрок понимает, с какой стороны скребёт.
			var vol: float = linear_to_db(clampf(near * hearing, 0.02, 1.0))
			sfx.play_at("scrape" if phase >= 3 else "skitter", monster.global_position, vol)
		_skit_t = 0.5 + randf() * 1.2 - anger * 0.01

	_heart_t -= delta
	if _heart_t <= 0.0 and d < cell_size * 5.0:
		var k: float = clampf(1.0 - d / (cell_size * 5.0), 0.0, 1.0)
		sfx.play("heart", linear_to_db(clampf(k * 0.6, 0.05, 1.0)))
		_heart_t = clampf(d / (cell_size * 5.0), 0.3, 1.0) * 1.1

	_breath_t -= delta
	if _breath_t <= 0.0:
		var scare: float = clampf(1.0 - d / (cell_size * 8.0), 0.0, 1.0) * 0.7 + _madness_stage() * 0.15
		if scare > 0.15:
			sfx.play("breath", linear_to_db(clampf(scare * 0.5, 0.05, 1.0)))
		_breath_t = clampf(3.4 - scare * 2.4, 0.9, 4.0)


# ─────────────────────────── захват ───────────────────────────

func _busy() -> bool:
	return _ui_blocking() or dead or paused()


## Щупальца из стены. Первый раз через 30–50 с, дальше каждые 110–180.
## Половина ударов ПРОМАХИВАЕТСЯ: частота испугов сохранена, а число схваток вдвое
## меньше — утомление убивает страх так же надёжно, как скука.
func _update_lash(delta: float) -> void:
	if tell_t >= 0.0:
		tell_t -= delta
		if tell_t <= 0.0:
			tell_t = -1.0
			_lash_strike()
		return
	if _busy() or player_node == null:
		return
	lash_t -= delta
	if lash_t > 0.0:
		return
	lash_t = randf_range(LASH_REPEAT[0], LASH_REPEAT[1]) * (1.0 - _madness_stage() * 0.08)
	# бьёт СЗАДИ: место выбирается за спиной игрока
	var back := -player_node.global_transform.basis.z
	tell_pos = player_node.global_position + back * cell_size * 2.0
	tell_miss = randf() < LASH_MISS
	tell_t = TELL
	# Никакого текста. Треск идёт ИЗ ТОЧКИ за спиной, и оттуда же толкает камеру:
	# игрок оборачивается рефлекторно, а не потому что прочитал подсказку в углу.
	if sfx != null:
		sfx.play_at("scrape", tell_pos, 4.0)
		sfx.play_at("whip", tell_pos, -2.0)
	if player_node != null:
		var to := tell_pos - player_node.global_position
		var right := player_node.global_transform.basis.x
		player_node.shake(1.0, signf(right.dot(to)))


## Спасает ВЗГЛЯД, а не бегство. Отойти в лабиринте почти невозможно — удар
## назначается за спину, и за секунду разрыв растёт на треть клетки. Зато
## обернуться можно всегда, и это ровно то поведение, которому игра учит
## с первой строки: слушай, с какой стороны скребёт.
func _lash_strike() -> void:
	if player_node == null:
		return
	var to := tell_pos - player_node.global_position
	to.y = 0.0
	var fwd := -player_node.global_transform.basis.z
	fwd.y = 0.0
	var seen: bool = to.length() < 0.01 or fwd.normalized().dot(to.normalized()) > TELL_LOOK
	if seen or tell_miss:
		if sfx != null:
			sfx.play("err", -6.0)
		player_node.shake(0.7, 0.0)
		return
	_start_grab("ЩУПАЛЬЦА ИЗ СТЕНЫ! ЖМИ ПРОБЕЛ!", "lash")


func _start_grab(text: String, src: String) -> void:
	if _busy():
		return
	var loud := _roll_scare(src)
	_pause_player(true)
	grab_ui.begin(text, loud, _rng.randi(), _madness_stage())
	if sfx != null:
		sfx.play("err", 0.0 if loud else -8.0)


func _on_escaped() -> void:
	streak = 0
	if monster != null:
		monster.stun = 4.5          # вырвался — значит получил фору
	if player_node != null:
		player_node.invuln = 3.2
	_pause_player(false)
	_update_hud()


func _on_grab_failed() -> void:
	_capture("lash")


## Два счёта, и это намеренно. streak — поимки подряд чем угодно, сдал полотно и
## прощено. mon_kills — поимки ИМЕННО монстром, и они не прощаются ничем: он
## главная угроза игры, значит он и должен убивать, а не только пугать.
func _capture(src: String) -> void:
	captures += 1
	streak += 1
	_add_madness("Оно тебя достало.")
	if src == "monster":
		mon_kills += 1
	anger = mini(MonsterScript.ANGER_MAX, anger + 1)
	var fatal: bool = streak >= DEATH_LIMIT or mon_kills >= DEATH_LIMIT
	var loud: bool = fatal or _roll_scare(src)
	scare_ui.begin(loud, fatal, _rng.randi())
	dead = fatal
	_pause_player(true)


func _on_scare_done() -> void:
	if dead:
		hud.text = "ОНО ДОСТАЛО ТЕБЯ. R — ЕЩЁ РАЗ."
		return
	if player_node != null:
		player_node.global_position = cell_to_world(_nearest_safe(), 0.85)
		player_node.invuln = 3.0
		safe_sit = 0.0
		if not ambush_done:
			ambush_t = 5.0
	if monster != null:
		monster.global_position = cell_to_world(_far_cell_from(start_cell))
		monster.stun = 2.5
	_pause_player(false)
	_update_hud()


## Право на скример копится: два подряд запрещены, между любыми двумя не меньше
## SCARE_MIN_GAP секунд. Монстр — исключение, но и у него кулдаун: «пугает всегда»
## верно ровно один раз, иначе затяжная погоня превращается в очередь криков.
func _roll_scare(src: String) -> bool:
	if _clock - _last_loud < SCARE_MIN_GAP:
		return false
	var ok := false
	if src == "monster" and _clock - _mon_scare_t >= MON_COOL:
		_mon_scare_t = _clock
		ok = true
	else:
		ok = randf() < float(SCARE_CHANCE.get(src, 0.25))
	if ok:
		_last_loud = _clock
	return ok


func _on_caught() -> void:
	if won or dead or player_node == null or _busy():
		return
	if player_node.invuln > 0.0:
		return
	_start_grab("ЖМИ ПРОБЕЛ! ВЫРЫВАЙСЯ!", "monster")
	monster.stun = 3.0


# ─────────────────────────── украшения и гнёзда ───────────────────────────

## Стены не пустые: на них чужие созвездия, спирали и засечки. Смотреть на них
## становится привычкой — и ИМЕННО эта привычка делает первую фазу: среди них
## спрятаны гнёзда щупалец. Заметить гнездо можно, только если присматриваться.
const DECOR_COUNT := 90
const NEST_COUNT := 10
const NEST_REACH := 2.1        ## клеток: дальше первого гнезда бьёт при проходе мимо

func _place_decor() -> void:
	nests.clear()
	nests_hit = 0
	var skin: Array = maze.wall_skin()
	skin.shuffle()
	var made := 0
	var made_nests := 0
	var dist: Dictionary = maze.distances(start_cell)
	for cell in skin:
		if made >= DECOR_COUNT:
			break
		var face := _wall_face(cell)
		if face.is_empty():
			continue
		var floor_cell: Vector2i = face["cell"]
		# гнёзда не ставим у самого старта: игрок должен сперва привыкнуть к украшениям
		var deep: bool = int(dist.get(floor_cell, 0)) > 8
		var is_nest: bool = made_nests < NEST_COUNT and deep and randf() < 0.25
		_decor_quad(face["pos"], face["normal"], is_nest)
		if is_nest:
			made_nests += 1
			nests.append({"pos": face["pos"], "used": false})
		made += 1


## Грань стены, смотрящая в коридор: там и висит украшение.
func _wall_face(cell: Vector2i) -> Dictionary:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = cell + d
		if not maze.is_wall(n.x, n.y):
			var normal := Vector3(float(d.y), 0.0, float(d.x))
			return {"cell": n, "normal": normal,
				"pos": cell_to_world(cell, 1.35) + normal * (cell_size * 0.5 + 0.02)}
	return {}


func _decor_quad(pos: Vector3, normal: Vector3, is_nest: bool) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5) if is_nest else Vector2(0.35, 0.35)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if is_nest:
		# тёмно-багровое и еле пульсирует: заметно, если присматриваться,
		# но чужеродно среди бледных чужих рисунков
		mat.albedo_color = Color(0.35, 0.06, 0.08, 0.55)
	else:
		mat.albedo_color = Color(0.72, 0.70, 0.64, 0.16)
	mi.material_override = mat
	mi.position = pos
	mi.look_at_from_position(pos, pos - normal, Vector3.UP)
	add_child(mi)
	if is_nest:
		mi.set_meta("nest", true)


## Первое гнездо требует подойти вплотную, дальше бьёт при проходе мимо —
## без предупреждения. Длинную катсцену игрок запоминает и перестаёт бояться.
func _update_nests() -> void:
	if _busy() or player_node == null or player_node.invuln > 0.0:
		return
	var reach: float = cell_size * (1.15 if nests_hit == 0 else NEST_REACH)
	for nst in nests:
		if nst["used"]:
			continue
		if player_node.global_position.distance_to(nst["pos"]) > reach:
			continue
		nst["used"] = true
		nests_hit += 1
		_add_madness("Гнездо.")
		if sfx != null:
			sfx.play_at("scrape", nst["pos"], 0.0)
		_start_grab("ЩУПАЛЬЦА! ЖМИ ПРОБЕЛ!", "nest")
		return


# ─────────────────────────── вспышка ───────────────────────────

## Вспышка не убивает и не оглушает надолго — она ПОКУПАЕТ время и стоит шума.
## Потратил рано — минуту идёшь без неё, а он всё это время подходит.
func _do_flash() -> void:
	if player_node == null or monster == null or not has_wand:
		hud.text = "НЕЧЕМ. ПАЛОЧКА ОСТАЛАСЬ НА СТОЛЕ."
		return
	if not player_node.flash_charged:
		return
	var d: float = player_node.global_position.distance_to(monster.global_position)
	if d > cell_size * 6.0 or monster.mode == "gone":
		hud.text = "РЯДОМ НИКОГО... ВСПЫШКУ ЛУЧШЕ БЕРЕЧЬ."
		return
	player_node.try_flash()
	monster.stun = 3.5
	monster.global_position = cell_to_world(_far_cell_from(world_to_cell(player_node.global_position)))
	monster.path.clear()
	if monster.mode == "hunt":
		monster.mode = "roam"
	if sfx != null:
		sfx.play("door", 4.0)
	_flash_blink()
	hud.text = "ВСПЫШКА. ОНО ОТСТУПИЛО."


func _flash_blink() -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 0.96, 0.85)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.get_parent().add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.5)
	tw.tween_callback(r.queue_free)


# ─────────────────────────── убежища ───────────────────────────

const SAFE_LIMIT := 7.0        ## сек в убежище, после которых стена трескается
const BURST := [13.0, 24.0]    ## пауза между выпрыгиваниями из стен в фазе 3

## Убежище — единственное место, где после поимки можно выдохнуть. И оно же
## перестаёт быть убежищем: пересидеть больше SAFE_LIMIT нельзя. Иначе игрок
## находит угол и просто пережидает всю игру.
func _place_safe() -> void:
	safe_cells.clear()
	safe_cells.append(start_cell)
	# Убежищ должно быть НЕСКОЛЬКО и их должно быть видно: игрок за два забега
	# не заметил ни одного, потому что оно было ровно одно и помечено кубиком
	# в полметра высотой.
	for cell in room_cells:
		if safe_cells.size() >= 3:
			break
		if not canv_cells.has(cell):
			safe_cells.append(cell)
			_marker(cell, Color(0.35, 0.62, 1.0), 2.6)
	if safe_cells.size() < 2:
		safe_cells.append(_cell_at_depth(maze.distances(start_cell), 0, 0.5, canv_cells))


func _nearest_safe() -> Vector2i:
	if player_node == null or safe_cells.is_empty():
		return start_cell
	var best := safe_cells[0]
	var bd := INF
	for c in safe_cells:
		var d: float = player_node.global_position.distance_to(cell_to_world(c))
		if d < bd:
			bd = d
			best = c
	return best


func _update_safe(delta: float) -> void:
	if _busy() or player_node == null:
		return
	var inside := false
	for c in safe_cells:
		if player_node.global_position.distance_to(cell_to_world(c)) < cell_size * 0.9:
			inside = true
			break
	safe_sit = safe_sit + delta if inside else 0.0
	if safe_sit >= SAFE_LIMIT and player_node.invuln <= 0.0:
		safe_sit = 0.0
		_start_grab("СТЕНА УБЕЖИЩА ТРЕСНУЛА! ЖМИ ПРОБЕЛ!", "lash")
	# «Безопасные» комнаты безопасны не полностью — один раз за забег.
	if ambush_t > 0.0:
		ambush_t -= delta
		if ambush_t <= 0.0 and not ambush_done:
			ambush_done = true
			_start_grab("СТЕНА ТРЕСНУЛА! ЖМИ ПРОБЕЛ!", "lash")


# ─────────────────────────── стены в третьей фазе ───────────────────────────

## Выпрыгивания намеренно БЕЗВРЕДНЫ: показалось, хлестнуло воздух и ушло.
## Постоянные QTE превратили бы травлю в рутину, а так стены просто перестают
## быть стенами.
func _update_burst(delta: float) -> void:
	if phase < 3 or _busy() or player_node == null:
		return
	burst_t -= delta
	if burst_t > 0.0:
		return
	burst_t = randf_range(BURST[0], BURST[1])
	var here := world_to_cell(player_node.global_position)
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = here + d
		if not maze.is_wall(n.x, n.y):
			continue
		var pos := cell_to_world(n, 1.3)
		if sfx != null:
			sfx.play_at("whip", pos, 2.0)
		_burst_quad(pos, Vector3(float(-d.y), 0.0, float(-d.x)))
		return


func _burst_quad(pos: Vector3, normal: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.8)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.06, 0.07, 0.08, 0.9)
	mi.material_override = mat
	mi.position = pos + normal * 0.05
	mi.look_at_from_position(mi.position, mi.position - normal, Vector3.UP)
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.55)
	tw.tween_callback(mi.queue_free)


## Звон в ушах — слышимая ПРИЧИНА, почему монстра перестало быть слышно.
## Без него глухота читается как поломка звука.
func _update_ring(delta: float) -> void:
	if phase < 2 or player_node == null or sfx == null:
		return
	if player_node.noise <= 0.45:
		return
	ring_t -= delta
	if ring_t > 0.0:
		return
	ring_t = 0.5
	sfx.play("ring", linear_to_db(clampf(player_node.noise * 0.12, 0.02, 1.0)))


## Прижался к камню — он оживает. Только со второй стадии безумия: до неё стены
## ещё притворяются стенами.
func _on_wall_touched(seconds: float) -> void:
	if seconds < 1.6 or _madness_stage() < 2 or _busy():
		return
	if player_node == null or player_node.invuln > 0.0:
		return
	player_node.wall_touch = 0.0
	_start_grab("СТЕНА ЖИВАЯ! ЖМИ ПРОБЕЛ!", "lash")


# ─────────────────────────── палочка метит пол ───────────────────────────

## Палочка оставляет метку там, где ты уже был. Лабиринт одинаковый со всех
## сторон, и без этого игрок ходит кругами, не понимая, что вернулся.
## Метка появляется ТОЛЬКО когда палочка взята — до неё ты слеп во всех смыслах.
func _update_marks() -> void:
	if not has_wand or player_node == null:
		return
	var c := world_to_cell(player_node.global_position)
	if visited.has(c) or maze.is_wall(c.x, c.y):
		return
	visited[c] = true
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.72, 0.62, 0.20)
	mi.material_override = mat
	mi.position = cell_to_world(c, 0.03)
	mi.rotation_degrees = Vector3(-90, 0, 0)
	add_child(mi)


# ─────────────────────────── глаза безумия ───────────────────────────

## Красные глаза по краям экрана со второй стадии. Они НИЧЕГО не делают —
## и в этом весь смысл: игрок не может отличить галлюцинацию от угрозы,
## а голубые глаза скримера при этом означают, что тебя действительно держат.
func _update_eyes(delta: float) -> void:
	if eyes_layer == null:
		return
	var stage := _madness_stage()
	if stage < 2 or _busy():
		eyes.clear()
		eyes_layer.queue_redraw()
		return
	if eyes.size() < 4 and randf() < 0.01:
		var vp := eyes_layer.size
		var x: float = randf_range(20.0, 80.0) if randf() < 0.5 else vp.x - randf_range(20.0, 80.0)
		eyes.append({"p": Vector2(x, randf_range(60.0, vp.y - 60.0)), "life": 3.0 + randf() * 3.0})
	for e in eyes:
		e["life"] -= delta
	eyes = eyes.filter(func(e): return float(e["life"]) > 0.0)
	eyes_layer.queue_redraw()


func _draw_eyes() -> void:
	for e in eyes:
		var p: Vector2 = e["p"]
		var a: float = clampf(float(e["life"]) / 1.5, 0.0, 1.0) * 0.75
		eyes_layer.draw_circle(p, 2.2, Color(0.78, 0.16, 0.16, a))
		eyes_layer.draw_circle(p + Vector2(8, 1), 2.2, Color(0.78, 0.16, 0.16, a))


# ─────────────────────────── подсказки создателя ───────────────────────────

## Выключены по умолчанию и переключаются клавишей прямо в игре. Держать их
## константой в коде нельзя: однажды отдашь сборку с включённой линией к выходу,
## и человек пройдёт лабиринт по ней, то есть не сыграет вовсе.
const DEV_SAVE := "user://dev.txt"

func _load_dev() -> void:
	if FileAccess.file_exists(DEV_SAVE):
		var f := FileAccess.open(DEV_SAVE, FileAccess.READ)
		if f != null:
			dev = f.get_as_text().strip_edges() == "1"
			f.close()


func _toggle_dev() -> void:
	dev = not dev
	var f := FileAccess.open(DEV_SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string("1" if dev else "0")
		f.close()
	if not dev:
		thread_on = false
		mon_on = false
	hud.text = "РЕЖИМ СОЗДАТЕЛЯ: ВКЛ (G — нить, M — монстр)" if dev else "РЕЖИМ СОЗДАТЕЛЯ: ВЫКЛ"


# ─────────────────────────── БЕЗУМИЕ ───────────────────────────

## Две НЕЗАВИСИМЫЕ шкалы, и это решение автора:
##   БЕЗУМИЕ — качество лабиринта. Копится от ошибок, доходит до потолка и там
##             стоит. Оно меняет МИР: стены шевелятся, кто-то смотрит из темноты,
##             щупальца бьют чаще, камень оживает от прикосновения.
##   ЯРОСТЬ  — личная злость монстра. Начинает расти ТОЛЬКО после того, как
##             безумие упёрлось в потолок. Она меняет ЕГО: скорость до полутора
##             твоих и не выше.
## Смысл разделения: сначала портится место, и лишь потом — тварь. Если бы росло
## одно число, игрок не различал бы «стало страшнее» и «стало быстрее».
const MAD_MAX := 9
const MAD_STAGE := [2, 4, 7]
const MAD_SAY := {
	2: "Стены начали шевелиться.",
	4: "В темноте кто-то смотрит.",
	7: "Стены больше не притворяются стенами.",
}

func _add_madness(reason: String) -> void:
	errors += 1
	if errors > MAD_MAX:
		anger = mini(MonsterScript.ANGER_MAX, errors - MAD_MAX)
		if anger == 1 and not mad_said.has("anger"):
			mad_said["anger"] = true
			hud.text = "ТЫ ЕГО РАЗОЗЛИЛ."
	elif MAD_SAY.has(errors) and not mad_said.has(errors):
		mad_said[errors] = true
		hud.text = str(MAD_SAY[errors])
	else:
		hud.text = reason + " ЛАБИРИНТ ЭТО ЗАПОМНИЛ."
	# Вторая фаза — глухота. Наступает от ошибок: чем хуже лабиринт, тем меньше
	# ты слышишь, а слух — единственное, чем ты его находишь.
	if phase == 1 and errors >= 2:
		phase = 2
	_apply_madness()


## Безумие видно НЕ только в цифре. Мир темнеет, туман густеет, камень зеленеет —
## иначе шкала остаётся счётчиком в углу, а не ощущением.
func _apply_madness() -> void:
	var k: float = clampf(float(errors) / float(MAD_MAX), 0.0, 1.0)
	if wall_mat != null:
		wall_mat.set_shader_parameter("madness", k)
	if env_ref != null:
		env_ref.fog_density = 0.015 + k * 0.03
		env_ref.ambient_light_energy = ambient * (1.0 - k * 0.35)


func _madness_bar() -> String:
	var st := _madness_stage()
	var bar := ""
	for i in 3:
		bar += "▮" if i < st else "▯"
	var out := "БЕЗУМИЕ " + bar
	if anger > 0:
		out += "  ЯРОСТЬ +" + str(anger)
	return out
