extends Node3D
## ПРОЛОГ. Детская комната, из которой игрок проваливается в лабиринт.
##
## Зачем она: игра начиналась сразу внутри кошмара, и первые три минуты
## выглядели как «ещё один тёмный коридор». Ужас живёт на переходе от обычного
## к неправильному, а перехода не было — не с чем сравнивать. Здесь же лежит и
## завязка: книжка с точками, карандаши, рисунки. Их не объясняют, их видно.
##
## Комната ОДНА и маленькая. Дом делать нельзя: домашнюю обстановку из коробок
## видно насквозь, все знают, как выглядит кухня. Одну комнату можно обставить
## честно, дом — нет.

const PlayerScript := preload("res://Player.gd")
const PlayerScene := preload("res://player.tscn")
const Lang := preload("res://Lang.gd")
const BoardScript := preload("res://Board.gd")
const Shapes := preload("res://Shapes.gd")
const Settings := preload("res://Settings.gd")
const SfxScript := preload("res://Sfx.gd")
## НАСТОЯЩИЕ МОДЕЛИ, А НЕ КОРОБКИ. Кровать, тумбочка, подушка и утка —
## сканы с polyhaven.com, лицензия CC0. Из коробок можно собрать стол и стул,
## их никто не разглядывает; кровать с силуэтом ребёнка разглядывают тридцать
## секунд подряд, и коробка там читается сразу. Источник записан в
## models/ИСТОЧНИК.txt.
const BedScene := preload("res://models/old_bed_frame/old_bed_frame_1k.gltf")
const StandScene := preload(
	"res://models/painted_wooden_nightstand/painted_wooden_nightstand_1k.gltf")
const PillowScene := preload("res://models/throw_pillows_01/throw_pillows_01_1k.gltf")

## Верх матраса. От него считается всё, что лежит на кровати.
const BED_TOP := 0.66

## Мир читает это и не показывает стартовый экран второй раз.
static var done: bool = false

const W := 5.2          ## комната: ширина
const D := 4.4          ## глубина
## 2.8 — обычная комната. Ниже человек ростом 1.63 чувствует себя великаном,
## выше она читается залом. Всё, что свисает, висит не ниже 2.15: пройти под
## лампой надо не пригибаясь.
## ПОТОЛОК ПОД ВЗРОСЛОГО. При 2.8 и глазе на 1.70 над головой оставалось метр
## с небольшим — комната читалась низкой, и первый же человек со стороны сказал,
## что персонаж в ней огромен. Три метра — обычная высота жилой комнаты, и
## разница в двадцать сантиметров здесь решает: потолок перестаёт давить.
const H := 3.0          ## высота

var player: CharacterBody3D
var hud: Label
var book: MeshInstance3D
var lamp_on: bool = false
var lamp: OmniLight3D
var lamp_bulb: MeshInstance3D
var read_t: float = 0.0     ## сколько уже читает книжку
var fall_t: float = 0.0     ## провал
var dark: ColorRect
var hole: Node3D
var floor_whole: MeshInstance3D
var floor_cut: Node3D
var hole_armed: bool = false
var hum_on: bool = false
var stage: int = 0   ## 0 входишь, 1 ходишь, 2 читаешь, 3 пролом открыт, 4 падаешь
var board                   ## блокнот с детскими рисунками
var vines: Array = []       ## лианы, тянущиеся к пролому
var enter_t: float = 2.2    ## сколько длится вход
var girl: Node3D
var sfx                     ## тот же звук, что в лабиринте
var _t: float = 0.0


func _ready() -> void:
	# Звук тот же, что дальше. Тихий пролог, а потом лабиринт с гулом — это
	# слышно как «включили игру», и вход перестаёт быть частью игры.
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.amb_level(0.12)
	# ШКАТУЛКА. В комнате играет её мотив — тихо, будто крутится где-то рядом.
	# Всё, что дальше случится с этой мелодией, случится в лабиринте.
	sfx.box_level(0.55)
	# Яркость игрока — с первого кадра, а не со второй сцены: детская и есть
	# первое, что он видит, и если у него тут темно, дальше он не пойдёт.
	Settings.attach_gamma(self)
	_build_room()
	_build_stuff()
	player = PlayerScene.instantiate()
	add_child(player)
	# ВХОДИТ. Не «оказывается в комнате», а входит: стоит в дверях, дверь за
	# спиной, и первые две секунды идёт сам. Разница в одном — становится
	# понятно, что комната ЧУЖАЯ и он сюда зашёл.
	player.global_position = Vector3(0, PlayerScript.STAND_Y, D * 0.5 - 0.35)
	# И rotation, и yaw: поворот игрока считается ОТ yaw, и без второй строки
	# камера разворачивалась на сто восемьдесят градусов в тот момент, когда
	# прологу возвращают управление.
	player.rotation.y = PI
	player.yaw = PI
	player.set_physics_process(false)
	_build_ui()
	# Действия в проекте нигде не записаны — их заводит из кода world.gd, а
	# пролог до него ещё не дошёл. Без этой строки E в детской не работает.
	if not InputMap.has_action("fullscreen"):
		InputMap.add_action("fullscreen")
		var fev := InputEventKey.new()
		fev.physical_keycode = KEY_F11
		InputMap.action_add_event("fullscreen", fev)
	if not InputMap.has_action("read"):
		InputMap.add_action("read")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event("read", ev)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _box(size: Vector3, pos: Vector3, mat: Material, solid: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.position = pos
		add_child(body)
	return mi


## Кусок мебели внутри узла-родителя. То же, что _box, но без столкновений и
## с привязкой: силуэт под одеялом должен двигаться как одно целое.
func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(c: Color, rough: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _tex(prefix: String, uv: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var col = load("res://tex/%s_color.jpg" % prefix)
	if col == null:
		return _mat(tint)
	m.albedo_texture = col
	m.albedo_color = tint
	# ТРИПЛАНАР, А НЕ UV КОРОБКИ. Раньше каждая грань растягивала картинку на
	# себя целиком: половая доска шириной три метра, штукатурка размером со
	# стену — от этого комната и читалась собранной из деталей лего. Здесь uv —
	# это ПОВТОРОВ НА МЕТР, и доска остаётся доской на полу, на столе и на
	# обломке у пролома, какого бы размера кусок ни был.
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	m.roughness = 1.0
	# РЕЛЬЕФ И БЛЕСК — ОТДЕЛЬНЫМИ КАРТАМИ. Одна картинка цвета оставляет
	# поверхность гладкой пластмассой: свет по ней ложится ровно, и никакой
	# ткани или доски не читается. Нормаль даёт нити и волокна, шероховатость —
	# разницу между матовым одеялом и залакированным полом.
	var nrm = load("res://tex/%s_normalgl.jpg" % prefix)
	if nrm != null:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = 1.0
	var rgh = load("res://tex/%s_roughness.jpg" % prefix)
	if rgh != null:
		m.roughness_texture = rgh
	m.metallic = 0.0
	return m


## ДЕТСКИЙ РИСУНОК КАРТИНКОЙ. Точки и линия между ними — ровно то, что игрок
## делает на полотнах. Рисуем в памяти: класть в проект три картинки ради трёх
## листов на стене нечестно, а фигуры всё равно берутся из общего списка.
func _draw_tex(idx: int) -> ImageTexture:
	var w: int = 220
	var h: int = 290
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + idx
	for y in h:
		for x in w:
			var t: float = 0.92 + rng.randf() * 0.06
			img.set_pixel(x, y, Color(0.93 * t, 0.90 * t, 0.82 * t))
	var pts: Array = Shapes.TUTOR[idx % Shapes.TUTOR.size()]["pts"]
	var col: Color = [Color(0.22, 0.30, 0.55), Color(0.58, 0.24, 0.22),
		Color(0.24, 0.44, 0.26)][idx % 3]
	var scr: Array[Vector2] = []
	for p in pts:
		var v: Vector2 = p
		scr.append(Vector2(v.x * float(w) + rng.randf_range(-3.0, 3.0),
			v.y * float(h) + rng.randf_range(-3.0, 3.0)))
	for i in scr.size() - 1:
		var a: Vector2 = scr[i]
		var b: Vector2 = scr[i + 1]
		var n: int = int(a.distance_to(b)) + 1
		for k in n + 1:
			var q: Vector2 = a.lerp(b, float(k) / float(n))
			# Рука у ребёнка дрожит, линейки у него нет.
			q += Vector2(sin(float(k) * 0.42 + float(i)) * 1.4,
				cos(float(k) * 0.36 + float(i)) * 1.4)
			_blot(img, q, 1.7, col)
	for p2 in scr:
		_blot(img, p2, 3.1, col.darkened(0.35))
	return ImageTexture.create_from_image(img)


## Мягкая клякса карандаша.
func _blot(img: Image, at: Vector2, r: float, col: Color) -> void:
	var ri: int = int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x: int = int(at.x) + dx
			var y: int = int(at.y) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var f: float = 1.0 - clampf(Vector2(dx, dy).length() / r, 0.0, 1.0)
			if f <= 0.0:
				continue
			img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, f * 0.85))


func _build_room() -> void:
	# Пол — половая доска, стены — штукатурка. Обе карты CC0, источник записан
	# в tex/ИСТОЧНИК.txt.
	var floor_mat := _tex("floorwood", 0.55, Color(0.62, 0.52, 0.42))
	var wall_mat := _tex("plaster", 0.42, Color(0.74, 0.72, 0.68))
	floor_whole = _box(Vector3(W, 0.3, D), Vector3(0, -0.15, 0), floor_mat)
	# Тот же пол, но с вырезанным квадратом. Пока лежит невидимым поверх целого:
	# когда пол провалится, мы просто меняем один на другой — и в дыру ВИДНО,
	# а не просто чёрный квадрат нарисован на досках.
	floor_cut = Node3D.new()
	floor_cut.visible = false
	add_child(floor_cut)
	var hx: float = 0.0
	var hz: float = 0.4
	var hr: float = 0.85
	for piece in [
			[Vector3(W * 0.5 - hr, 0.3, D),
				Vector3((-W * 0.5 + hx - hr) * 0.5, -0.15, 0.0)],
			[Vector3(W * 0.5 - hr, 0.3, D), Vector3((W * 0.5 + hr) * 0.5, -0.15, 0.0)],
			[Vector3(hr * 2.0, 0.3, D * 0.5 - (hz + hr)),
				Vector3(hx, -0.15, (hz + hr + D * 0.5) * 0.5)],
			[Vector3(hr * 2.0, 0.3, (hz - hr) + D * 0.5),
				Vector3(hx, -0.15, ((hz - hr) - D * 0.5) * 0.5)]]:
		var pc := _part(floor_cut, piece[0], piece[1], floor_mat)
		pc.scale = Vector3.ONE
	# Стенки колодца: без них край дыры просвечивает и глубины не видно.
	var pit_mat := _mat(Color(0.06, 0.05, 0.05))
	for w in [[Vector3(hr * 2.0, 2.4, 0.06), Vector3(hx, -1.2, hz - hr)],
			[Vector3(hr * 2.0, 2.4, 0.06), Vector3(hx, -1.2, hz + hr)],
			[Vector3(0.06, 2.4, hr * 2.0), Vector3(hx - hr, -1.2, hz)],
			[Vector3(0.06, 2.4, hr * 2.0), Vector3(hx + hr, -1.2, hz)]]:
		_part(floor_cut, w[0], w[1], pit_mat)
	_part(floor_cut, Vector3(hr * 2.2, 0.1, hr * 2.2), Vector3(hx, -2.5, hz),
		_mat(Color(0.01, 0.01, 0.012)))
	_box(Vector3(W, 0.3, D), Vector3(0, H + 0.15, 0), _mat(Color(0.70, 0.69, 0.66)))
	_box(Vector3(0.3, H, D), Vector3(-W * 0.5 - 0.15, H * 0.5, 0), wall_mat)
	_box(Vector3(0.3, H, D), Vector3(W * 0.5 + 0.15, H * 0.5, 0), wall_mat)
	_box(Vector3(W, H, 0.3), Vector3(0, H * 0.5, -D * 0.5 - 0.15), wall_mat)
	_box(Vector3(W, H, 0.3), Vector3(0, H * 0.5, D * 0.5 + 0.15), wall_mat)
	# ПЛИНТУС. Мелочь, но именно её отсутствие делает комнату коробкой: без него
	# стена втыкается в пол прямым швом, а такого шва в жилой комнате нет.
	var base_mat := _tex("furniture", 1.4, Color(0.66, 0.60, 0.54))
	for b in [[Vector3(W, 0.12, 0.04), Vector3(0, 0.06, -D * 0.5 + 0.02)],
			[Vector3(W, 0.12, 0.04), Vector3(0, 0.06, D * 0.5 - 0.02)],
			[Vector3(0.04, 0.12, D), Vector3(-W * 0.5 + 0.02, 0.06, 0)],
			[Vector3(0.04, 0.12, D), Vector3(W * 0.5 - 0.02, 0.06, 0)]]:
		_box(b[0], b[1], base_mat, false)
	# ОКНО. Не украшение: серый дневной свет из него — единственное, с чем
	# игрок потом сравнит темноту лабиринта.
	var glass := _box(Vector3(1.5, 1.1, 0.06), Vector3(-W * 0.5 + 0.2, 1.55, -0.4),
		_mat(Color(0.78, 0.83, 0.88)), false)
	var gm := glass.material_override as StandardMaterial3D
	gm.emission_enabled = true
	gm.emission = Color(0.62, 0.70, 0.80)
	# 0.8, а не 1.5: окно выбивалось в чистый белый прямоугольник и съедало
	# полстены. Свет из него всё равно даёт отдельная лампа.
	gm.emission_energy_multiplier = 0.8
	var day := OmniLight3D.new()
	day.light_color = Color(0.72, 0.80, 0.92)
	day.light_energy = 2.2
	day.omni_range = 8.0
	day.position = Vector3(-W * 0.5 + 0.6, 1.6, -0.4)
	add_child(day)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.70, 0.74, 0.82)
	fill.light_energy = 0.8
	fill.omni_range = 9.0
	fill.position = Vector3(0, H - 0.4, 0)
	add_child(fill)


func _build_stuff() -> void:
	var wood := _tex("furniture", 1.4, Color(0.62, 0.55, 0.48))
	_build_bed(W * 0.5 - 0.75)
	# Стол у окна и стул.
	_box(Vector3(1.5, 0.08, 0.75), Vector3(-W * 0.5 + 1.1, 0.74, -0.9), wood)
	for sx in [-0.6, 0.6]:
		for sz in [-0.3, 0.3]:
			_box(Vector3(0.08, 0.74, 0.08),
				Vector3(-W * 0.5 + 1.1 + sx, 0.37, -0.9 + sz), wood, false)
	# Табурет С НОЖКАМИ: сиденье само по себе висело в воздухе доской.
	_box(Vector3(0.42, 0.06, 0.42), Vector3(-W * 0.5 + 1.1, 0.45, -0.1), wood)
	for tx in [-0.16, 0.16]:
		for tz in [-0.16, 0.16]:
			_box(Vector3(0.05, 0.42, 0.05),
				Vector3(-W * 0.5 + 1.1 + tx, 0.21, -0.1 + tz), wood, false)
	# На столе — раскрытая тетрадь и карандаши: тут работали, а блокнот с
	# точками лежит на кровати, у неё под рукой.
	_box(Vector3(0.40, 0.02, 0.30), Vector3(-W * 0.5 + 1.05, 0.79, -0.9),
		_tex("paper", 2.6, Color(0.88, 0.86, 0.80)), false)
	# Карандаши рядом — россыпью, а не в стакане: тут работали, а не позировали.
	for i in 5:
		var p := _box(Vector3(0.02, 0.02, 0.17),
			Vector3(-W * 0.5 + 1.45 + float(i) * 0.05, 0.79, -0.78),
			_mat([Color(0.52, 0.24, 0.20), Color(0.24, 0.34, 0.48),
				Color(0.28, 0.44, 0.29), Color(0.56, 0.50, 0.24),
				Color(0.34, 0.27, 0.40)][i], 0.85), false)
		p.rotation_degrees = Vector3(0, randf_range(-25.0, 25.0), 0)
	# Лампа на столе — её и включают.
	_box(Vector3(0.06, 0.34, 0.06), Vector3(-W * 0.5 + 0.55, 0.95, -0.9), wood, false)
	lamp_bulb = _box(Vector3(0.20, 0.14, 0.20), Vector3(-W * 0.5 + 0.55, 1.16, -0.9),
		_mat(Color(0.85, 0.80, 0.70)), false)
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.62)
	lamp.light_energy = 0.0
	lamp.omni_range = 5.0
	lamp.position = Vector3(-W * 0.5 + 0.55, 1.16, -0.9)
	add_child(lamp)
	# Рисунки на стене — ТЕ ЖЕ ФИГУРЫ, что игрок будет соединять весь дальнейший
	# час: домик, рыбка, кораблик. Раньше здесь висели пустые белые листы, и
	# завязка «она рисовала точками» держалась на честном слове.
	for i in 3:
		var dm := StandardMaterial3D.new()
		dm.albedo_texture = _draw_tex(i)
		dm.roughness = 1.0
		var d := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.34, 0.44)
		d.mesh = qm
		d.material_override = dm
		d.position = Vector3(-0.6 + float(i) * 0.7, 1.65, -D * 0.5 + 0.02)
		d.rotation_degrees = Vector3(0, 0, randf_range(-4.0, 4.0))
		add_child(d)
	# ПРОЛОМ. Собран заранее, но невидим: пока пол цел, лианы просто сходятся
	# в одно место на полу, и это ничего не объясняет — до поры.
	hole = Node3D.new()
	hole.position = Vector3(0, 0, 0.4)
	hole.visible = false
	add_child(hole)
	# Рваный край. Пол не ломается по линейке: доски торчат в разные стороны и
	# на разной длине, иначе дыра читается люком.
	var brk := _tex("floorwood", 0.55, Color(0.40, 0.31, 0.23))
	for i in 14:
		var a2: float = TAU * float(i) / 14.0 + randf_range(-0.10, 0.10)
		var r: float = 0.78 + randf() * 0.22
		var shard := _part(hole, Vector3(0.18 + randf() * 0.20, 0.05,
			0.24 + randf() * 0.34),
			Vector3(cos(a2) * r, 0.02, sin(a2) * r), brk)
		shard.rotation = Vector3(randf_range(-0.35, 0.35), -a2,
			randf_range(-0.30, 0.30))
	# Пара досок, отлетевших от края. Пол не проваливается аккуратно.
	for i in 4:
		var a3: float = randf() * TAU
		var r3: float = 1.15 + randf() * 0.5
		var pl := _part(hole, Vector3(0.16, 0.04, 0.62 + randf() * 0.3),
			Vector3(cos(a3) * r3, 0.02, sin(a3) * r3), brk)
		pl.rotation = Vector3(0, randf() * TAU, 0)
	_build_vines(Vector3(0, 0.02, 0.4))


## СИЛУЭТ ПОД ОДЕЯЛОМ, ЗАДАННЫЙ ЧИСЛАМИ, А НЕ ШАРАМИ. Раньше под одеялом лежали
## три эллипсоида: гладкие, одинаковые, с натянутой на каждый тканью — и это
## читалось гусеницей, а не ребёнком. Здесь одеяло — одна сплошная поверхность,
## а тело задаёт её высоту: [x, z, полуширина, полудлина, высота].
const BODY := [
	[0.00, -0.44, 0.22, 0.26, 0.150],   ## плечи
	[-0.01, -0.07, 0.19, 0.28, 0.112],  ## спина
	[0.02, 0.21, 0.19, 0.20, 0.126],    ## бёдра
	[0.07, 0.47, 0.13, 0.16, 0.132],    ## подтянутые колени
	[0.06, 0.68, 0.11, 0.14, 0.072],    ## голени
	[0.05, 0.83, 0.09, 0.10, 0.050],    ## ступни
]


## Высота ткани над матрасом в точке кровати. Тело — сумма плавных бугров,
## поверх — складки: без них любая ткань выглядит натянутой плёнкой.
func _drape_h(x: float, z: float) -> float:
	var h: float = 0.022
	for b in BODY:
		var dx: float = (x - float(b[0])) / float(b[2])
		var dz: float = (z - float(b[1])) / float(b[3])
		var q: float = 1.0 - dx * dx - dz * dz
		if q > 0.0:
			h += float(b[4]) * pow(q, 1.35)
	var w: float = 0.011 * sin(x * 18.0 + z * 5.5)
	w += 0.008 * sin(z * 12.5 - x * 8.0)
	w += 0.005 * sin((x + z) * 26.0 + 1.7)
	# Складки крупнее там, где ткань лежит свободно, и почти пропадают на
	# натянутых местах — на плече и на колене.
	return h + w * clampf(1.5 - h * 4.5, 0.20, 1.0)


## ОДЕЯЛО ОДНОЙ ПОВЕРХНОСТЬЮ. Сетка по кровати: середина лежит на теле, края
## свисают с матраса, у плеч — отворот. Нормали считаются по соседям, поэтому
## свет ложится по складкам, а не ровным пятном.
func _drape_mesh() -> ArrayMesh:
	var skirt: int = 5
	var drop: float = 0.235
	var xs: Array[float] = []
	var xd: Array[float] = []
	for i in skirt:
		xs.append(-0.445)
		xd.append(drop * float(skirt - i) / float(skirt))
	var cols: int = 46
	for i in cols:
		xs.append(lerpf(-0.445, 0.445, float(i) / float(cols - 1)))
		xd.append(0.0)
	for i in skirt:
		xs.append(0.445)
		xd.append(drop * float(i + 1) / float(skirt))
	var zs: Array[float] = []
	var zd: Array[float] = []
	var lip: int = 4
	for i in lip:
		zs.append(-0.56 - 0.024 * float(lip - i))
		zd.append(-0.032 * float(lip - i) / float(lip))
	var rows: int = 78
	for i in rows:
		zs.append(lerpf(-0.56, 0.93, float(i) / float(rows - 1)))
		zd.append(0.0)
	for i in skirt:
		zs.append(0.93)
		zd.append(drop * float(i + 1) / float(skirt))
	var nc: int = xs.size()
	var nr: int = zs.size()
	var g: Array = []
	for r in nr:
		var row: Array = []
		for c in nc:
			var x: float = xs[c]
			if xd[c] > 0.0:
				# Свисающий край не доска: он гуляет вдоль кровати.
				x += signf(x) * (0.006 + 0.006 * sin(zs[r] * 7.3)) * (xd[c] / drop)
			var y: float = BED_TOP + _drape_h(xs[c], zs[r]) - xd[c] - zd[r]
			row.append(Vector3(x, y, zs[r]))
		g.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uw: float = 1.36 * 2.0
	var ul: float = 1.86 * 2.0
	for r in nr - 1:
		for c in nc - 1:
			for q in [[r, c], [r, c + 1], [r + 1, c], [r + 1, c], [r, c + 1],
					[r + 1, c + 1]]:
				var rr: int = int(q[0])
				var cc: int = int(q[1])
				st.set_normal(_grid_n(g, rr, cc, nr, nc))
				st.set_uv(Vector2(float(cc) / float(nc - 1) * uw,
					float(rr) / float(nr - 1) * ul))
				st.add_vertex(g[rr][cc])
	st.generate_tangents()
	return st.commit()


## Нормаль узла сетки по соседям. Считать её по граням нельзя: на свисающем
## крае грани почти вертикальные, и шов между верхом и краем становится виден.
func _grid_n(g: Array, r: int, c: int, nr: int, nc: int) -> Vector3:
	var a: Vector3 = g[r][maxi(c - 1, 0)]
	var b: Vector3 = g[r][mini(c + 1, nc - 1)]
	var d: Vector3 = g[maxi(r - 1, 0)][c]
	var e: Vector3 = g[mini(r + 1, nr - 1)][c]
	var n: Vector3 = (e - d).cross(b - a)
	if n.length() < 0.000001:
		return Vector3.UP
	return n.normalized()


## ГОЛОВА. Не шар: у шара нет затылка, челюсти и подбородка, а именно по ним
## голову и узнают краем глаза. Лица не будет — она отвёрнута к стене, — но
## затылок и скула должны быть настоящими, иначе из-под одеяла торчит мяч.
func _head_p(n: Vector3, th: float, phi: float, hair: bool) -> Vector3:
	var p := Vector3(n.x * 0.074, n.y * 0.087, n.z * 0.091)
	# Затылок — не полусфера, он выступает назад и вниз.
	p.z -= 0.013 * pow(maxf(0.0, -n.z), 2.0)
	# Ниже глаз череп сужается к челюсти.
	var low: float = smoothstep(-0.08, -0.85, n.y)
	p.x *= 1.0 - 0.30 * low
	p.z *= 1.0 - 0.09 * low
	# Подбородок и нос — маленькие, детские.
	var chin: float = maxf(0.0, n.z * 0.55 - n.y * 0.83)
	p += Vector3(0.0, -0.005, 0.011) * pow(chin, 6.0)
	var nose: float = maxf(0.0, n.z * 0.985 + n.y * 0.17)
	p.z += 0.013 * pow(nose, 20.0)
	# Лоб чуть плоский, макушка чуть примята подушкой.
	p.z -= 0.005 * pow(maxf(0.0, n.z * 0.5 + n.y * 0.86), 4.0)
	p.y *= 1.0 - 0.06 * pow(maxf(0.0, n.y), 3.0)
	# Уши.
	var ear: float = maxf(0.0, absf(n.x) * 0.99 + n.y * 0.05 - absf(n.z) * 0.12)
	p.x += signf(n.x) * 0.009 * pow(ear, 13.0)
	if not hair:
		return p
	# ВОЛОСЫ — ОТДЕЛЬНАЯ ОБОЛОЧКА поверх черепа, но только там, где они растут.
	# Где их нет, оболочка уходит ВНУТРЬ головы: если положить её вплотную,
	# две поверхности начинают спорить за один пиксель и картинка дрожит.
	var d: float = n.z * 0.85 - n.y * 0.62 + absf(n.x) * 0.16
	var m: float = clampf((0.26 - d) / 0.30, 0.0, 1.0)
	var strand: float = 0.0040 * sin(th * 33.0) + 0.0026 * sin(phi * 22.0 + th * 4.0)
	return p + p.normalized() * (-0.005 + m * (0.013 + strand))


func _head_mesh(hair: bool) -> ArrayMesh:
	var nu: int = 46
	var nv: int = 32
	var g: Array = []
	for j in nv + 1:
		var row: Array = []
		var phi: float = PI * float(j) / float(nv)
		for i in nu + 1:
			var th: float = TAU * float(i) / float(nu)
			var n := Vector3(sin(phi) * sin(th), cos(phi), sin(phi) * cos(th))
			row.append(_head_p(n, th, phi, hair))
		g.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nv:
		for i in nu:
			for q in [[j, i], [j, i + 1], [j + 1, i], [j + 1, i], [j, i + 1],
					[j + 1, i + 1]]:
				var jj: int = int(q[0])
				var ii: int = int(q[1])
				var v: Vector3 = g[jj][ii]
				st.set_normal(_grid_n(g, jj, ii, nv + 1, nu + 1))
				st.set_uv(Vector2(float(ii) / float(nu) * 3.0,
					float(jj) / float(nv) * 2.0))
				st.add_vertex(v)
	st.generate_tangents()
	return st.commit()


## Мелкий рельеф из шума. Кожа и штукатурка без него — залитый цвет: свет
## ложится ровным пятном, и любая поверхность становится пластмассой.
func _noise_normal(freq: float, bump: float) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = bump
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn.frequency = freq
	nt.noise = fn
	return nt


func _skin_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.55, 0.50)
	m.roughness = 0.62
	m.metallic = 0.0
	m.normal_enabled = true
	m.normal_texture = _noise_normal(0.22, 1.4)
	m.normal_scale = 0.55
	m.uv1_scale = Vector3(4.0, 4.0, 4.0)
	# Кожа просвечивает. Без этого голова — крашеный гипс.
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.42
	m.subsurf_scatter_skin_mode = true
	return m


func _hair_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.115, 0.093, 0.088)
	m.roughness = 0.66
	m.metallic = 0.0
	m.normal_enabled = true
	m.normal_texture = _noise_normal(0.55, 3.0)
	m.normal_scale = 1.0
	m.uv1_scale = Vector3(6.0, 1.0, 1.0)
	# Блик на волосах вытянут вдоль пряди, а не круглый.
	m.anisotropy_enabled = true
	m.anisotropy = 0.55
	return m


## Модель со сканера: поставить, повернуть, задать размер.
func _model(scene: PackedScene, pos: Vector3, yaw: float,
		scl: float = 1.0) -> Node3D:
	var n: Node3D = scene.instantiate()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3(scl, scl, scl)
	add_child(n)
	return n


## КРОВАТЬ И ТА, КТО В НЕЙ. Первые тридцать секунд игры человек смотрит сюда,
## и всё остальное в комнате он оценит по этому месту.
func _build_bed(bx: float) -> void:
	var bz: float = -0.6
	# Рама — скан старой железной кровати (CC0). Изголовье у неё со стороны
	# −Z, то есть у дальней стены: девочка лежит головой туда.
	_model(BedScene, Vector3(bx, 0.0, bz), 0.0)
	# Столкновения отдельно: у скана их нет, а сквозь кровать ходить нельзя.
	var body := StaticBody3D.new()
	body.position = Vector3(bx, 0.0, bz)
	add_child(body)
	for c in [[Vector3(0.96, 0.72, 2.04), Vector3(0.0, 0.36, 0.0)],
			[Vector3(0.96, 1.22, 0.08), Vector3(0.0, 0.61, -1.0)]]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = c[0]
		cs.shape = sh
		cs.position = c[1]
		body.add_child(cs)
	girl = Node3D.new()
	girl.position = Vector3(bx, 0.0, bz)
	add_child(girl)
	# Матрас. Верх на 0.66 — ровно на сетке рамы.
	var mat_mesh := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.845, 0.17, 1.88)
	mat_mesh.mesh = mb
	mat_mesh.material_override = _tex("linen", 1.9, Color(0.80, 0.75, 0.66))
	mat_mesh.position = Vector3(0.0, BED_TOP - 0.085, 0.0)
	girl.add_child(mat_mesh)
	# Одеяло.
	var blanket := MeshInstance3D.new()
	blanket.mesh = _drape_mesh()
	var cloth := _tex("blanket", 1.3, Color(0.66, 0.63, 0.62))
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	blanket.material_override = cloth
	girl.add_child(blanket)
	# Подушка — тоже скан; цвет приглушён множителем, иначе она кричит на всю
	# комнату узором.
	var pil: Node3D = PillowScene.instantiate()
	pil.position = Vector3(0.02, BED_TOP + 0.088, -0.76)
	pil.rotation = Vector3(0.0, 0.09, 0.0)
	pil.scale = Vector3(1.20, 0.80, 1.06)
	girl.add_child(pil)
	# У скана свой узор — красно-оранжевые треугольники. В детской он кричит на
	# всю комнату, поэтому форму берём от скана, а ткань свою.
	_face(pil, "throw_pillows_01_pillow01", false)
	_reskin(pil, _tex("linen", 2.4, Color(0.88, 0.86, 0.82)))
	# ГОЛОВА. Лицом к стене: лица нет и не будет, а затылок ребёнка на подушке
	# говорит ровно то, что нужно — с ней ничего нельзя сделать.
	var head := Node3D.new()
	head.position = Vector3(0.02, BED_TOP + 0.215, -0.66)
	head.rotation = Vector3(0.12, PI * 0.40, -0.30)
	head.scale = Vector3(1.14, 1.14, 1.14)
	girl.add_child(head)
	var skull := MeshInstance3D.new()
	skull.mesh = _head_mesh(false)
	skull.material_override = _skin_mat()
	head.add_child(skull)
	var hair := MeshInstance3D.new()
	hair.mesh = _head_mesh(true)
	hair.material_override = _hair_mat()
	head.add_child(hair)
	# Пряди по подушке: без них голова кончается ровной шапкой.
	var hm: StandardMaterial3D = _hair_mat()
	for i in 7:
		var a: float = -0.9 + float(i) * 0.30
		# Пряди уходят НАЗАД, на подушку. Раньше они торчали вбок и вперёд —
		# из головы получался чёрный ёж.
		_lock(girl, Vector3(0.02 + sin(a) * 0.04, BED_TOP + 0.23, -0.72),
			Vector3(0.02 + sin(a) * 0.13, BED_TOP + 0.135,
				-0.80 - absf(cos(a)) * 0.10), hm)
	# БЛОКНОТ на одеяле: обучение живёт здесь, а не в подсказках. Лежит криво —
	# его положили, а не поставили.
	var bh: float = BED_TOP + _drape_h(-0.24, 0.36) + 0.012
	book = _box(Vector3(0.27, 0.028, 0.20), Vector3(bx - 0.24, bh, bz + 0.36),
		_tex("paper", 2.6, Color(0.46, 0.34, 0.24)), false)
	book.rotation = Vector3(0.0, 0.28, 0.0)
	# Бумага отдельным листом поверх обложки: одна белая плита читалась куском
	# пенопласта, а не тетрадью.
	var pg := _box(Vector3(0.245, 0.020, 0.178), Vector3(bx - 0.24, bh + 0.012,
		bz + 0.365), _tex("paper", 3.4, Color(0.80, 0.77, 0.70)), false)
	pg.rotation = Vector3(0.0, 0.28, 0.0)
	# Тумбочка у изголовья и утка на полу: комната обжитая, а не выставочная.
	_model(StandScene, Vector3(bx - 0.82, 0.04, bz - 0.72), -PI * 0.5)


## Прядь волос: короткая цепочка сужающихся звеньев с провисанием.
func _lock(parent: Node3D, from: Vector3, to: Vector3,
		mat: Material) -> void:
	var segs: int = 5
	var prev: Vector3 = from
	for k in range(1, segs + 1):
		var t: float = float(k) / float(segs)
		var p: Vector3 = from.lerp(to, t)
		p.y -= sin(t * PI) * 0.012
		var d: Vector3 = p - prev
		var l: float = maxf(d.length(), 0.001)
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008 * (1.0 - t * 0.7)
		cm.bottom_radius = 0.008 * (1.0 - (t - 1.0 / float(segs)) * 0.7)
		cm.height = l
		cm.radial_segments = 6
		seg.mesh = cm
		seg.material_override = mat
		seg.position = (prev + p) * 0.5
		seg.look_at_from_position(seg.position, p, Vector3.UP)
		seg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		parent.add_child(seg)
		prev = p


## Заменить ткань готовой модели своей. Прежняя версия множила цвет на месте
## и не срабатывала: у сканов нет переопределённых материалов, и счётчик
## переопределений всегда ноль — цикл ни разу не выполнялся.
func _reskin(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		mi.material_override = mat
	for ch in n.get_children():
		_reskin(ch, mat)


## Показать или спрятать часть модели по имени узла.
func _face(n: Node, part: String, on: bool) -> void:
	if n.name == part and n is Node3D:
		var v: Node3D = n
		v.visible = on
	for ch in n.get_children():
		_face(ch, part, on)


## ЛИАНЫ. Тонкие чёрные жилы тянутся ОТ ВСЕХ СТЕН к одной точке пола. Они не
## угрожают и ничего не делают — они показывают направление. Игрок не читает
## подсказок, но взгляд сам идёт вдоль линии и упирается туда, куда надо.
##
## И это первое, что в комнате неправильно: обои, кровать, лампа — всё обычное,
## а по стенам расползлось вот это.
func _build_vines(to: Vector3) -> void:
	var mat := _mat(Color(0.05, 0.05, 0.06))
	var starts: Array = []
	# ПО ПЯТЬ С КАЖДОЙ СТЕНЫ, а не по три: двенадцать жил на всю комнату
	# терялись — стены казались просто пустыми, и «всё тянется к пролому» не
	# читалось. Двадцать штук уже похожи на то, что комнату оплело.
	for i in 5:
		var h: float = 0.35 + float(i) * 0.52
		var t2: float = float(i) / 4.0
		starts.append(Vector3(-W * 0.5 + 0.02, h, -1.6 + t2 * 3.2))
		starts.append(Vector3(W * 0.5 - 0.02, h, 1.6 - t2 * 3.2))
		starts.append(Vector3(-1.8 + t2 * 3.6, h, -D * 0.5 + 0.02))
		starts.append(Vector3(1.8 - t2 * 3.6, h, D * 0.5 - 0.02))
	for st in starts:
		var v := Node3D.new()
		add_child(v)
		# Жила — цепочка коротких звеньев: она должна ИЗГИБАТЬСЯ по стене и полу,
		# а не идти по прямой сквозь комнату.
		var segs: int = 9
		var prev: Vector3 = st
		for k in range(1, segs + 1):
			var t: float = float(k) / float(segs)
			# Сначала сползает по стене вниз, потом тянется по полу к пролому.
			var down: Vector3 = Vector3(st.x, lerpf(st.y, 0.03, minf(1.0, t * 1.8)), st.z)
			# Цель — не центр, а точка на краю пролома со стороны своей стены:
			# двенадцать жил, сходящихся в одну точку, читались звездой, а не
			# тем, что доползло до дыры и обхватило её.
			var away: Vector3 = Vector3(st.x - to.x, 0.0, st.z - to.z).normalized()
			var rim: Vector3 = Vector3(to.x, 0.03, to.z) + away * 0.82
			var p: Vector3 = down.lerp(rim, maxf(0.0, t * 1.6 - 0.6))
			# Лёгкий изгиб вбок, чтобы не было прямых линеек.
			p.x += sin(t * 3.4 + st.z) * 0.16 * (1.0 - t)
			p.z += cos(t * 3.1 + st.x) * 0.16 * (1.0 - t)
			var d: Vector3 = p - prev
			var l: float = maxf(d.length(), 0.001)
			var seg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			# Толщина у каждой своя: одинаковые жилы читаются проводами.
			var thick: float = float(v.get_index() % 3) * 0.006 + 0.010
			cm.top_radius = thick * (1.0 - t * 0.5)
			cm.bottom_radius = (thick + 0.005) * (1.0 - t * 0.5)
			cm.height = l
			cm.radial_segments = 6
			seg.mesh = cm
			seg.material_override = mat
			seg.position = prev + d * 0.5
			seg.rotation = Vector3(acos(clampf(d.y / l, -1.0, 1.0)),
				atan2(d.x, d.z), 0.0)
			v.add_child(seg)
			prev = p
		vines.append(v)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.offset_top = -70.0
	hud.z_index = 4        # подсказка поверх полотна, а не под его палитрой
	hud.add_theme_color_override("font_color", Color(0.86, 0.85, 0.82))
	hud.add_theme_font_size_override("font_size", 17)
	hud.text = Lang.t("p_look")
	layer.add_child(hud)
	# Блокнот открывается настоящим полотном — тем же, что в лабиринте. Так
	# обучение не «объясняет правила», а даёт их сделать.
	board = BoardScript.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.visible = false
	board.solved.connect(_on_book_done)
	board.failed.connect(_on_book_done)
	board.abandoned.connect(_on_book_done)
	layer.add_child(board)
	dark = ColorRect.new()
	dark.color = Color(0, 0, 0, 0)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dark)


func _unhandled_input(event: InputEvent) -> void:
	# Полный экран работает и здесь: пролог — первое, что видит игрок, и жать
	# F11 он будет именно тут.
	if event.is_action_pressed("fullscreen"):
		Settings.toggle_fullscreen()
		return
	if stage == 0 or stage >= 4:
		return
	if not event.is_action_pressed("read"):
		return
	var p: Vector3 = player.global_position
	# Лампа: свет включают руками, и это первое, что делает человек в комнате.
	if not lamp_on and p.distance_to(lamp.position) < 1.6:
		lamp_on = true
		lamp.light_energy = 2.6
		sfx.play("click", -2.0)
		var bm := lamp_bulb.material_override as StandardMaterial3D
		bm.emission_enabled = true
		bm.emission = Color(1.0, 0.88, 0.66)
		bm.emission_energy_multiplier = 1.4
		hud.text = Lang.t("p_book")
		return
	if board.visible:
		return
	if stage == 1 and p.distance_to(book.global_position) < 1.6:
		# Открываем блокнот: обычный детский рисунок, без таймера на нервах.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var sh: Dictionary = Shapes.TUTOR[rng.randi() % Shapes.TUTOR.size()]
		# Подсказку — наверх: внизу её закрывает палитра порядка цветов.
		hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
		hud.offset_top = 22.0
		board.tutor = true
		sfx.play("scrape", -8.0)
		board.open(sh, 0, 0.0, 0, rng.randi())
		board.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.set_physics_process(false)
		hud.text = Lang.t("p_draw")


## Блокнот закрыт — как бы он ни закрылся. Провалить его нельзя: это не
## испытание, а первое знакомство с тем, чем ты будешь занят всю игру.
func _on_book_done() -> void:
	board.visible = false
	hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hud.offset_top = -70.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_physics_process(true)
	stage = 2
	read_t = 2.4
	hud.text = Lang.t("p_read")


## Сколько по полу до пролома. Высота не в счёт: он ходит по полу.
func _hole_dist() -> float:
	return Vector2(player.global_position.x - hole.position.x,
		player.global_position.z - hole.position.z).length()


func _process(delta: float) -> void:
	_t += delta
	# ВХОД. Первые секунды он идёт в комнату сам, управления нет.
	if stage == 0:
		enter_t -= delta
		player.global_position.z -= delta * 0.9
		if enter_t <= 0.0:
			stage = 1
			player.set_physics_process(true)
			hud.text = Lang.t("p_look")
		return
	if stage == 2:
		read_t -= delta
		if not hum_on:
			hum_on = true
			sfx.hum_start()
		# Пока «читает», комната начинает портиться: свет садится, а из-под пола
		# слышно. Ничего не объясняем — просто становится хуже.
		lamp.light_energy = maxf(0.0, lamp.light_energy - delta * 0.9)
		# Пока он смотрит в блокнот, комната садится: свет уходит, а снизу
		# поднимается гул. Ничего не объясняем — просто становится хуже.
		var k2: float = 1.0 - clampf(read_t / 2.4, 0.0, 1.0)
		sfx.amb_level(0.12 + k2 * 0.5)
		sfx.hum_level(k2 * 0.55)
		# И ШКАТУЛКА ЗАМОЛКАЕТ. Пока он читает, комната садится: свет уходит,
		# гул поднимается, а мелодия кончается — будто завод вышел.
		sfx.box_level(0.55 * (1.0 - k2))
		if read_t <= 0.0:
			stage = 3
			sfx.box_level(0.0)
			hole.visible = true
			floor_whole.visible = false
			floor_cut.visible = true
			# Взводим сразу, если он стоит не над проломом. Ждать, пока он
			# отойдёт на полтора метра, было лишним: после блокнота он у
			# кровати, до дыры чуть меньше метра — и шаг вниз не срабатывал.
			hole_armed = _hole_dist() > 0.8
			sfx.hit(6.0)
			sfx.play("scrape", 2.0)
			hud.text = Lang.t("p_hole")
		return
	# ПРЫГАЕТ САМ. Пол не забирает его — он подходит и шагает вниз. Лианы весь
	# пролог показывали куда, и это единственное, что он тут решает сам.
	if stage == 3:
		var d: float = _hole_dist()
		# Если пол провалился прямо под ним, ждём, пока он выйдет: иначе
		# «прыжок» — не его решение, а случайность.
		if d > 0.8:
			hole_armed = true
		if hole_armed and d < 0.7:
			stage = 4
			fall_t = 2.6
			sfx.play("breath", -2.0)
			sfx.hum_level(1.0)
			hud.text = Lang.t("p_fall")
			player.set_physics_process(false)
		return
	if stage == 4:
		fall_t -= delta
		var k: float = 1.0 - clampf(fall_t / 2.6, 0.0, 1.0)
		# Пол уходит вниз, экран гаснет. Дальше — лабиринт.
		player.global_position.y = 0.85 - 7.0 * k * k
		player.head.rotation.z = k * 0.8
		dark.color.a = clampf(k * 1.7 - 0.3, 0.0, 1.0)
		if fall_t <= 0.0:
			done = true
			get_tree().change_scene_to_file("res://world.tscn")
