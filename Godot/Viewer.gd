extends Node3D
## СМОТРОВАЯ. Белая комната, монстр посередине и кнопки, которыми им управляют.
##
## Зачем: увидеть третью фазу в игре стоит десятка ошибок, побега по коридорам и
## удачи — а посмотреть на неё надо десять раз подряд. Здесь он стоит манекеном,
## пока не нажмёшь, и любую позу, походку или атаку можно включить сразу.
##
## Это НЕ часть игры и не влияет на неё: отдельная сцена, свой свет, свой
## монстр. Лабиринта здесь нет вовсе — стены коридора подделываются двумя
## плоскостями, чтобы было видно, как он от них отталкивается.

const MonsterScript := preload("res://Monster.gd")
const SfxScript := preload("res://Sfx.gd")
const GrabScript := preload("res://Grab.gd")
const WALL_SHADER := preload("res://wall.gdshader")
const FLOOR_SHADER := preload("res://floor.gdshader")
const Lang := preload("res://Lang.gd")

## Ширина поддельного коридора — та же, что в игре.
## В ИГРЕ коридор 2.8 м, и он в нём еле помещается — руки и часть туши уходят
## в камень. Смотреть на это бессмысленно, поэтому здесь проход по умолчанию
## ШИРЕ; кнопка возвращает настоящую ширину, когда надо проверить именно её.
const CELL_GAME := 2.8
const CELL_WIDE := 4.6
## ОТКРЫВАЕТСЯ НА ИГРОВОЙ ШИРИНЕ, а не на широкой. Смотровая по умолчанию
## показывала проход 4.6 м — на 64% шире настоящего. Именно поэтому коридорная
## походка тут всегда выглядела нормально, а в игре половина ноги оказывалась в
## камне: инструмент показывал не то, что у игрока. Кнопка «шире» осталась —
## ею удобно разглядывать анатомию, — но начинаем с правды.
var cell_gap: float = CELL_GAME

var monster
var cam: Camera3D
var yaw: float = 0.0
var pitch: float = -0.12
var dist: float = 9.0
var target_y: float = 2.0   ## он под четыре метра ростом, целимся в середину
var walking: bool = false
var wall_l: MeshInstance3D
var wall_r: MeshInstance3D
var info: Label
var _drag: bool = false
var _t: float = 0.0
var _auto_reach: bool = false
var _lash_t: float = 0.0
var _bright: bool = false
var _slam_t: float = 0.0
var _slam_out: float = 0.0
var _corr: bool = false   ## показан ли поддельный коридор
var hf_demo: int = 0      ## 0 нет, 1 руки с потолка, 2 язык
var hf_t: float = 0.0
var hf_at: Vector3 = Vector3.ZERO   ## где «игрок» в этой сцене
var hf_step: float = 0.0
var hf_home: Vector3 = Vector3.ZERO
var _pull_t: float = 0.0  ## притягивание и вдавливание в стену
var _hold_to: Vector3 = Vector3.ZERO
var slab: MeshInstance3D
var white_room: Array = []      ## белая комната и её лампы
var game_room: Node3D           ## коридор с игровыми шейдерами и светом
var flash: SpotLight3D          ## фонарь палочки на камере
var mon_beam: SpotLight3D       ## луч, который бьёт только по монстру
var game_look: bool = false
var dark: ColorRect
var sfx
var grab_ui
var speed: float = 2.6            ## как в погоне: 3.2 * 0.91
var fast: bool = true
## В ЛАБОРАТОРИИ СМОТРОВАЯ — ОДНО ИЗ ОКОН, а не отдельная сцена. Выход и Escape
## там обязаны закрывать ОКНО, а не подменять сцену: подмена выбросила бы всю
## лабораторию вместе с остальными окнами.
var in_lab: bool = false
signal want_close


func _ready() -> void:
	_build_room()
	monster = MonsterScript.new()
	add_child(monster)
	# maze = null: смотровая не знает про лабиринт, и монстру он здесь не нужен —
	# всё, что мы зовём, работает от тела, а не от карты.
	monster.setup(null, CELL_GAME, 3.2, 12345)
	monster.visible = true
	monster.manual_space = true
	monster.position = Vector3.ZERO
	_set_phase(3)
	cam = Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	cam.current = true
	sfx = SfxScript.new()
	add_child(sfx)
	# Звуки он шлёт сам, теми же сигналами, что и в игре: смотровая ничего не
	# подделывает, иначе смотреть на неё было бы незачем.
	monster.wall_hit.connect(_on_limb)
	# ФОНАРЬ ПАЛОЧКИ. Числа взяты из мира дословно: важна не яркость, а то, что
	# луч узкий и гаснет через десяток метров.
	flash = SpotLight3D.new()
	flash.light_energy = 25.0
	flash.light_color = Color(0.86, 0.89, 0.96)
	flash.spot_range = 19.0
	flash.spot_angle = 32.0
	flash.spot_angle_attenuation = 1.4
	flash.spot_attenuation = 0.85
	flash.shadow_enabled = true
	flash.light_volumetric_fog_energy = 0.0
	flash.visible = false
	cam.add_child(flash)
	# И отдельный луч по нему одному — тот же слой, что в игре.
	mon_beam = SpotLight3D.new()
	mon_beam.light_color = Color(0.86, 0.95, 1.0)
	mon_beam.light_energy = 0.0
	mon_beam.spot_range = 26.0
	mon_beam.spot_angle = 46.0
	mon_beam.spot_angle_attenuation = 0.6
	mon_beam.light_cull_mask = 1 << 4
	mon_beam.shadow_enabled = false
	mon_beam.visible = false
	cam.add_child(mon_beam)
	_build_ui()
	grab_ui = GrabScript.new()
	grab_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	grab_ui.visible = false
	grab_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grab_ui.escaped.connect(func() -> void: _say("вырвался"))
	grab_ui.failed.connect(func() -> void: _say("не успел — в игре это была бы поимка"))
	var gl := CanvasLayer.new()
	add_child(gl)
	gl.add_child(grab_ui)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_room() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.86, 0.87, 0.88)
	white.roughness = 1.0
	for spec in [[Vector3(26, 0.4, 26), Vector3(0, -0.2, 0)],
			[Vector3(26, 12, 0.4), Vector3(0, 6, -9.0)],
			[Vector3(0.4, 12, 26), Vector3(-9.0, 6, 0)],
			[Vector3(0.4, 12, 26), Vector3(9.0, 6, 0)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.material_override = white
		mi.position = spec[1]
		add_child(mi)
		white_room.append(mi)
	# Три источника с разных сторон: с одним половина тела уходит в чёрное,
	# а смотровая нужна ровно затем, чтобы видеть форму.
	for p in [Vector3(5, 7, 6), Vector3(-6, 6, 4), Vector3(0, 5, -6)]:
		var l := OmniLight3D.new()
		l.light_energy = 7.0
		l.omni_range = 30.0
		l.position = p
		add_child(l)
		white_room.append(l)
	# Поддельные стены коридора: включаются вместе с коридорной походкой.
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.57, 0.60)
	grey.roughness = 1.0
	wall_l = _slab(grey, Vector3(-cell_gap * 0.5, 2.15, 0))
	wall_r = _slab(grey, Vector3(cell_gap * 0.5, 2.15, 0))
	wall_l.visible = false
	wall_r.visible = false
	# Стена, из которой он вылезает в сцене удара. Видна только там.
	slab = MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(9.0, 4.3, 0.4)
	slab.mesh = sb
	# Материал КАМНЯ, а не серая коробка: под фонарём она горела белым
	# прямоугольником, и на кадре позади монстра был яркий просвет.
	var sm2 := ShaderMaterial.new()
	sm2.shader = WALL_SHADER
	sm2.set_shader_parameter("detail", 1.0)
	sm2.set_shader_parameter("near_dist", 3.2)
	sm2.set_shader_parameter("madness", 0.07)
	sb.subdivide_width = 18
	sb.subdivide_height = 8
	slab.material_override = sm2
	slab.position = Vector3(0, 2.15, -4.6)
	add_child(slab)
	slab.visible = false


## ВИД КАК В ИГРЕ. Не «похожий»: те же шейдеры, те же три параметра, которые им
## задаёт мир, тот же фонарь с теми же дальностью и спадом и тот же отдельный луч
## по монстру. Иначе смотреть на это бессмысленно — я бы оценивал не игру.
func _set_game_look(on: bool) -> void:
	for n in white_room:
		(n as Node3D).visible = not on
	if game_room == null:
		_build_game_room()
	game_room.visible = on
	flash.visible = on
	mon_beam.visible = on
	# В темноте отзывчивость поверхности считает сам мир по расстоянию; здесь
	# делаем то же самое, иначе он будет либо чёрным, либо всегда ярким.
	if not on:
		monster.set_lit(2.0 if _bright else 1.0)


func _build_game_room() -> void:
	game_room = Node3D.new()
	add_child(game_room)
	var wm := ShaderMaterial.new()
	wm.shader = WALL_SHADER
	# Ровно те три, что задаёт мир на высоком качестве, и нижний порог безумия.
	wm.set_shader_parameter("detail", 1.0)
	wm.set_shader_parameter("near_dist", 3.2)
	wm.set_shader_parameter("madness", 0.07)
	var half: float = CELL_GAME * 0.5
	for sx in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 4.3, 20.0)
		# Сетка обязательна: шейдер двигает вершины, а у коробки их восемь.
		bm.subdivide_width = 2
		bm.subdivide_height = 8
		bm.subdivide_depth = 40
		w.mesh = bm
		w.material_override = wm
		w.position = Vector3(sx * (half + 0.3), 2.15, 0)
		game_room.add_child(w)
	var fm := ShaderMaterial.new()
	fm.shader = FLOOR_SHADER
	fm.set_shader_parameter("relief", 1.0)
	var fl := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(CELL_GAME, 0.3, 20.0)
	fb.subdivide_width = 6
	fb.subdivide_depth = 48
	fl.mesh = fb
	fl.material_override = fm
	fl.position = Vector3(0, -0.15, 0)
	game_room.add_child(fl)
	var cm := ShaderMaterial.new()
	cm.shader = WALL_SHADER
	cm.set_shader_parameter("base_color", Color(0.105, 0.105, 0.112))
	cm.set_shader_parameter("bulge", 0.42)
	cm.set_shader_parameter("near_dist", 6.5)
	cm.set_shader_parameter("relief", 1.8)
	cm.set_shader_parameter("madness", 0.07)
	var ce := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(CELL_GAME, 0.3, 20.0)
	cb.subdivide_width = 6
	cb.subdivide_depth = 48
	ce.mesh = cb
	ce.material_override = cm
	ce.position = Vector3(0, 4.3, 0)
	game_room.add_child(ce)
	# Темнота и туман — как в мире.
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.68, 0.60)
	env.ambient_light_energy = 0.14 * (1.0 - 0.07 * 0.35)
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.02, 0.03)
	env.fog_density = 0.055 * 1.07
	we.environment = env
	game_room.add_child(we)
	game_room.visible = false


func _slab(mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# Восемь метров, а не четырнадцать: длинные плиты закрывали обзор при
	# обходе кругом, а нужны они только чтобы было видно, ВО ЧТО он упирается.
	bm.size = Vector3(0.25, 4.3, 8.0)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(18, 18)
	box.add_theme_constant_override("separation", 4)
	layer.add_child(box)
	var rows := [
		["— ВИД —", ""],
		["в камне (2 фаза)", "phase2"],
		["снаружи (3 фаза)", "phase3"],
		["— ПОХОДКА —", ""],
		["стоит", "idle"],
		["ползёт по залу", "walk_open"],
		["ползёт в коридоре", "walk_corr"],
		["— АТАКИ —", ""],
		["тянется щупальцами", "reach"],
		["бросок щупальца", "strike"],
		["фигура: гуманоид с пастью", "form_human"],
		["фигура: наугад", "form"],
		["— ХВАТ (пробел — выйти) —", ""],
		["схватил и держит", "grab"],
		["швырнул в стену", "slam"],
		["— ПРОЧЕЕ —", ""],
		["шагом / бегом", "speed"],
		["ширина: игровая / шире", "gap"],
		["как в игре / светло", "game"],
		["обойти кругом", "orbit"],
		["подсветить сильнее", "bright"],
		["выход (ESC)", "exit"],
	]
	for r in rows:
		if str(r[1]) == "":
			var lbl := Label.new()
			lbl.text = str(r[0])
			lbl.add_theme_color_override("font_color", Color(0.20, 0.22, 0.24))
			lbl.add_theme_font_size_override("font_size", 12)
			box.add_child(lbl)
			continue
		var b := Button.new()
		b.text = str(r[0])
		b.custom_minimum_size = Vector2(210, 26)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_button.bind(str(r[1])))
		box.add_child(b)
	# ВТОРОЙ СТОЛБЕЦ, СПРАВА. Атаки фигуры живут в игровой логике, и посмотреть
	# на них иначе можно было только доиграв до третьей фазы. Здесь они
	# проигрываются как сцены: камера играет игрока, монстр — сам себя.
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-236, 18)
	right.add_theme_constant_override("separation", 4)
	layer.add_child(right)
	for r2 in [["— АТАКИ ФИГУРЫ —", ""], ["руки с потолка", "hf_hands"],
			["язык из пасти", "hf_tongue"], ["отмена", "hf_stop"]]:
		if str(r2[1]) == "":
			var l2 := Label.new()
			l2.text = str(r2[0])
			l2.add_theme_color_override("font_color", Color(0.20, 0.22, 0.24))
			l2.add_theme_font_size_override("font_size", 12)
			right.add_child(l2)
			continue
		var b2 := Button.new()
		b2.text = str(r2[0])
		b2.custom_minimum_size = Vector2(210, 26)
		b2.add_theme_font_size_override("font_size", 13)
		b2.pressed.connect(_on_button.bind(str(r2[1])))
		right.add_child(b2)
	info = Label.new()
	info.position = Vector2(18, 18)
	info.anchor_left = 0.0
	info.add_theme_color_override("font_color", Color(0.12, 0.13, 0.14))
	info.add_theme_font_size_override("font_size", 13)
	layer.add_child(info)
	info.position = Vector2(250, 20)
	# Затемнение на сцену удара: экран гаснет, пока ты лежишь.
	dark = ColorRect.new()
	dark.color = Color(0, 0, 0, 0)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dark)
	_say("тащи мышью — обойти, колесо — ближе и дальше")


## Звук постановки щупальца — тот же путь, что в игре.
## Завести сцену атаки. Игрока здесь нет — его роль играет точка перед
## монстром, к ней же привязана камера.
func _hf_start(kind: int) -> void:
	hf_demo = kind
	hf_t = 0.0
	# ОТ НАЧАЛА КООРДИНАТ, А НЕ ОТ СЕБЯ. Точка считалась от текущего места
	# монстра, а он в конце атаки оставался там, куда добежал: каждый повтор
	# отодвигал сцену ещё на пять метров, и через три захода мы были за стеной.
	monster.position = Vector3.ZERO
	monster.rotation = Vector3.ZERO
	hf_home = Vector3.ZERO
	hf_at = Vector3(0, 1.63, 5.0)
	monster.aim_at = hf_at
	walking = false
	if kind == 1:
		monster.arms_up = 1.0
		monster.ceiling_grab(hf_at, 4.1)
		hf_step = 0.0
		if sfx != null:
			sfx.play_at("roar", monster.global_position, 5.0)
			sfx.play("whip", 3.0)
			sfx.play("scream", 4.0)
	else:
		monster.strike_at(hf_at, 4.0)
		if sfx != null:
			sfx.play_at("roar", monster.global_position, 2.0)
			sfx.play("whip", 5.0)
			sfx.play("scream", 3.0)


func _hf_end() -> void:
	hf_demo = 0
	monster.ceiling_release()
	monster.arms_up = 0.0
	monster.reach_t = 0.0
	monster.position = hf_home
	dist = 9.0
	target_y = 2.0


func _on_limb(pos: Vector3, on_wall: bool) -> void:
	if sfx == null:
		return
	if on_wall:
		sfx.slap(pos, 1.0)
	else:
		sfx.play_at("step_wet", pos, -7.0)


func _say(text: String) -> void:
	if info != null:
		info.text = text


func _set_phase(n: int) -> void:
	if n == 2:
		# До третьей фазы его тела снаружи не бывает: он внутри камня и виден
		# только глазами из стены. Показываем ту же массу, но неразвёрнутой.
		monster.body.scale = Vector3.ONE
		monster.set_lit(0.35)
		_say("вторая фаза: он в камне, наружу выходит только это")
	else:
		monster._grow_out()
		monster.set_lit(1.0)
		_say("третья фаза: вышел целиком, тело крупнее")


func _on_button(what: String) -> void:
	# ОБОРОТ ОСТАНАВЛИВАЕМ НА ЛЮБОЙ КНОПКЕ. Он крутил камеру дальше, и все
	# следующие сцены игрались из случайного угла — стена оказывалась за
	# спиной, а показывать надо было именно её.
	if what != "orbit":
		_lash_t = 0.0
	match what:
		"phase2":
			_set_phase(2)
		"phase3":
			_set_phase(3)
		"idle":
			walking = false
			monster.manual_space = true
			monster.cramped = false
			_corr = false
			wall_l.visible = false
			wall_r.visible = false
			_say("стоит: видно только кипение массы")
		"walk_open":
			walking = true
			monster.manual_space = true
			monster.cramped = false
			monster._assign_roles()
			_corr = false
			wall_l.visible = false
			wall_r.visible = false
			_say("зал: переступает всеми восемью, волной по кругу")
		"walk_corr":
			yaw = 0.55
			walking = true
			# Лабиринта нет, поэтому теснота задаётся руками: направление
			# поперёк прохода и две точки на стенах.
			monster.manual_space = true
			monster.cramped = true
			monster.side_dir = Vector3.RIGHT
			monster.wall_a = Vector3(cell_gap * 0.5 - 0.10, 0, 0)
			monster.wall_b = Vector3(-cell_gap * 0.5 + 0.10, 0, 0)
			monster._assign_roles()
			_corr = true
			wall_l.visible = true
			wall_r.visible = true
			_say("коридор: по упору в каждую стену, две тянутся, четыре ноги")
		"reach":
			_auto_reach = not _auto_reach
			if _auto_reach:
				# Тянущиеся руки есть только в тесноте: в зале все восемь заняты
				# ходьбой. Поэтому включаем коридорную раскладку ролей.
				monster.manual_space = true
				monster.cramped = true
				monster.side_dir = Vector3.RIGHT
				monster.wall_a = Vector3(cell_gap * 0.5 - 0.10, 0, 0)
				monster.wall_b = Vector3(-cell_gap * 0.5 + 0.10, 0, 0)
				monster._assign_roles()
				_corr = true
				wall_l.visible = true
				wall_r.visible = true
				_say("две руки тянутся к камере, две упираются в стены")
			else:
				_say("перестал тянуться")
		"strike":
			monster.strike_at(cam.global_position, 2.5)
			_say("бросок: щупальце достаёт до камеры")
		"form_human":
			monster.take_form(30.0, monster.FORM_HUMAN)
			walking = false
			_auto_reach = true
			_say("искажённый гуманоид: пасть открылась, щупальца лезут изо рта")
		"form":
			monster.take_form(3.0)
			_say("собирается в фигуру и расползается обратно")
		"bright":
			_bright = not _bright
			monster.set_lit(2.0 if _bright else 1.0)
			_say("подсветка: %s" % ("сильная — видно форму" if _bright
				else "как в игре"))
		"hf_hands":
			# Фигура должна стоять — атака её.
			if monster.form_kind != monster.FORM_HUMAN:
				_on_button("form_human")
			_hf_start(1)
			_say("руки с потолка: тебя подняли, он бежит к тебе втрое быстрее")
		"hf_tongue":
			if monster.form_kind != monster.FORM_HUMAN:
				_on_button("form_human")
			_hf_start(2)
			_say("язык из пасти: выстрел и рывок к себе")
		"hf_stop":
			_hf_end()
			_say("атака отменена")
		"grab":
			yaw = 0.0
			pitch = -0.04
			# Камера ЗДЕСЬ и есть игрок: поднимаем её туда, где смыкаются руки.
			_hold_to = monster.grab_hold(30.0)
			walking = false
			grab_ui.coils = false
			grab_ui.begin("ЖМИ ПРОБЕЛ! ВЫРЫВАЙСЯ!", true, randi(), 0)
			grab_ui.need = 1
			if sfx != null:
				sfx.hit(6.0)
				sfx.play("scream", 3.0)
			_say("поднял над собой и обвивает. пробел — выйти")
		"slam":
			# Сцене нужен вид спереди: он выходит из стены, которая стоит по -Z.
			yaw = 0.0
			pitch = -0.10
			dist = 7.0
			# Вся сцена целиком: удар, падение, темнота, и он выходит из камня.
			_slam_t = 7.0
			walking = false
			slab.visible = true
			# Считано, а не на глаз: туша около 1.9 м в глубину, лицевая сторона
			# стены на -4.4. Чтобы наружу торчала треть, центр должен встать
			# на -4.12; начинаем с -4.9, то есть почти целиком внутри.
			# Пересчитано по замеру: при конце на -4.12 наружу выходило 54%, а
			# не треть. Треть от 1.9 м глубины — это 0.67 м за лицевой стороной
			# стены (-4.4), значит центр должен встать на -4.68.
			monster.position = Vector3(0, 0, -5.3)
			monster.drop_hold()
			_hold_to = Vector3.ZERO
			# Стена позади него: в неё он и будет лупить щупальцами.
			monster.push_n = Vector3(0, 0, 1)
			monster.push_at = Vector3(0, 0, -4.6)
			_slam_out = 0.0
			if sfx != null:
				sfx.play("hit_low", 6.0)
				sfx.play("hit_mid", 4.0)
				sfx.play("scream", 6.0)
			_say("удар о стену: падаешь, темнеет, он выходит из камня")
		"game":
			game_look = not game_look
			_set_game_look(game_look)
			_say("вид: %s" % ("как в игре — тьма, фонарь, живой камень"
				if game_look else "смотровая — белая комната"))
		"gap":
			cell_gap = CELL_GAME if cell_gap > CELL_GAME else CELL_WIDE
			wall_l.position.x = -cell_gap * 0.5
			wall_r.position.x = cell_gap * 0.5
			_say("ширина прохода: %s" % ("как в игре, 2.8 м" if cell_gap == CELL_GAME
				else "шире игровой, 4.6 м — чтобы всё было видно"))
		"speed":
			fast = not fast
			speed = 2.6 if fast else 1.4
			_say("скорость: %s" % ("бегом, как в погоне" if fast else "шагом"))
		"orbit":
			_drag = false
			_say("кручу сам")
			_lash_t = 6.0
		"exit":
			if in_lab:
				want_close.emit()
			else:
				get_tree().change_scene_to_file("res://world.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE \
			and grab_ui != null and grab_ui.visible:
		grab_ui.press()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if in_lab:
			want_close.emit()
		else:
			get_tree().change_scene_to_file("res://world.tscn")
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(2.2, dist - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(16.0, dist + 0.5)
	elif event is InputEventMouseMotion and _drag:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch - event.relative.y * 0.004, -1.2, 0.9)


func _process(delta: float) -> void:
	_t += delta
	if _lash_t > 0.0:
		_lash_t -= delta
		yaw += delta * 0.5
	# Шаг крутится от «пройденного пути», хотя стоим на месте: тело здесь не
	# едет, иначе он ушёл бы из кадра, а походку смотреть надо.
	if walking:
		# ЕСТЬ КОГО ХВАТАТЬ. В смотровой игрока нет, и aim_at оставался нулём —
		# значит две руки, которые в игре тянутся к тебе, здесь тянулись в
		# никуда, «вперёд по умолчанию». Со стороны это читалось как «спереди
		# щупалец нет вовсе». Целью назначаем камеру: смотрящий и есть игрок.
		monster.aim_at = cam.global_position
		# ОН ДЕЙСТВИТЕЛЬНО ИДЁТ. Пока туша стояла на месте, а щупальца махали,
		# отталкивания не было видно в принципе: опора неподвижна в мире, и
		# смысл её появляется только когда мимо неё едет тело.
		var step: float = speed * delta
		monster.position.z += step
		# Шаг крутится от ПУТИ, ровно как в игре, — отсюда и совпадение с
		# движением, которого не хватало.
		monster.gait = fmod(monster.gait + step * 0.55, 1.0)
		if monster.cramped:
			# Стены «едут» вместе с ним: в игре точки упора берутся от его
			# клетки, здесь — от него самого.
			monster.wall_a = Vector3(cell_gap * 0.5 - 0.10, 0, monster.position.z)
			monster.wall_b = Vector3(-cell_gap * 0.5 + 0.10, 0, monster.position.z)
		if monster.position.z > 5.0:
			# Возврат в начало вместе с опорами: без сдвига опор руки остались
			# бы позади и вытянулись на всю комнату.
			monster.position.z -= 10.0
			for arm in monster.arms:
				arm["plant"] = Vector3(arm["plant"]) - Vector3(0, 0, 10.0)
	if hf_demo > 0:
		hf_t += delta
		monster.aim_at = hf_at
		if hf_demo == 1:
			# Тебя подняли на два метра, он бежит по прямой втрое быстрее.
			# ТОЛЬКО ВВЕРХ, НА МЕСТЕ. Камера — это игрок: его поднимают там, где
			# он стоял, а не тащат куда-то вбок. Раньше я вёл её со смещением,
			# и выходило, будто монстр таскает обзор за собой.
			target_y = lerpf(target_y, hf_at.y + 1.9, minf(1.0, delta * 2.2))
			cam.global_position = Vector3(hf_at.x, target_y, hf_at.z)
			# СМОТРИМ ЕМУ В ГРУДЬ, а не в ноги. Точка «плюс 1.6 м от основания»
			# годилась для кома, а у фигуры это голени: висящий игрок всю атаку
			# пялился вниз, и выглядело так, будто его тянет к ступням.
			var look_at_p: Vector3 = monster.body.global_transform \
				* monster._mouth_local()
			cam.look_at(look_at_p, Vector3.UP)
			var to: Vector3 = Vector3(hf_at.x, monster.position.y, hf_at.z)
			var step: float = 3.2 * 2.5 * delta
			monster.position = monster.position.move_toward(to, step)
			monster.gait = fmod(monster.gait + step * 0.55, 1.0)
			monster.look_at(monster.global_position
				- (to - monster.global_position), Vector3.UP)
			# Первые полсекунды жест держится: гасить его с первого кадра —
			# значит не показать вовсе.
			if hf_t > 0.55:
				monster.arms_up = maxf(0.0, monster.arms_up - delta * 1.6)
			hf_step -= delta
			if hf_step <= 0.0:
				hf_step = 0.26
				if sfx != null:
					sfx.play_at("step_wet", monster.global_position, -1.0)
			if monster.position.distance_to(to) < 1.9:
				monster.arms_up = 0.0
				monster.ceiling_release()
				if sfx != null:
					sfx.play("hit_low", 5.0)
					sfx.play_at("roar", monster.global_position, 7.0)
				_hold_to = monster.grab_hold(30.0)
				grab_ui.coils = false
				grab_ui.begin("ЖМИ ПРОБЕЛ! ВЫРЫВАЙСЯ!", true, randi(), 0)
				grab_ui.need = 1
				if sfx != null:
					sfx.hit(6.0)
				hf_demo = 0
				_say("дошёл и взял ртом. пробел — выйти")
		else:
			# Язык тянет тебя к пасти.
			monster._aim_reach(cam.global_position)
			var mouth: Vector3 = monster.body.global_transform * monster._mouth_local()
			cam.global_position = cam.global_position.lerp(
				mouth + Vector3(0, 0, 1.9), minf(1.0, delta * 1.3))
			if hf_t > 2.6:
				hf_demo = 0
				_say("дотянул к пасти")
		# БЕЗ return. Он стоял здесь и выходил из _process ДО вызова _shiver —
		# а значит на время всей атаки монстр вообще не оживал: ни жеста руками
		# вверх, ни кипения. Камеру и так не трогает отдельная проверка ниже.
	if _slam_t > 0.0:
		_slam_t -= delta
		var k: float = 7.0 - _slam_t
		if k < 0.5:
			# Летишь и падаешь: глаз валится к полу.
			target_y = lerpf(1.63, 0.42, k / 0.5)
			dark.color.a = k / 0.5
		elif k < 1.6:
			# Темно. Ровно в эти секунды он и трогается из камня.
			target_y = 0.42
			dark.color.a = 1.0 - (k - 0.5) / 1.1
		else:
			# Лежишь и смотришь, как он выходит.
			dark.color.a = 0.0
			target_y = lerpf(0.42, 1.63, clampf((k - 4.5) / 2.0, 0.0, 1.0))
		# ВЫДАВЛИВАЕТСЯ РЫВКАМИ. Гонится тот же шаг, что и при ходьбе, и на
		# каждый упор в стену он выходит толчком — а не едет сквозь камень.
		if k > 0.6:
			monster.gait = fmod(monster.gait + delta * 0.55, 1.0)
			var g: float = fmod(monster.gait, 0.5)
			_slam_out = clampf(_slam_out + delta * (0.62 if g < 0.11 else 0.04), 0.0, 1.0)
		# Выходит НАПОЛОВИНУ: в коридоре ему просто некуда выйти целиком.
		monster.position = Vector3(0, 0, lerpf(-5.3, -4.68, _slam_out))
		monster.set_lit(clampf(_slam_out * 1.6, 0.2, 1.6))
		if _slam_out > 0.9 and monster.push_at != Vector3.ZERO:
			monster.end_push()
		if _slam_t <= 0.0:
			slab.visible = false
			monster.end_push()
			# Он торчит из камня и целиком не выходит — значит тянет ТЕБЯ.
			# Дальше вдавит в стену: отсюда и берётся выброс вниз головой.
			_pull_t = 1.8
			monster.strike_at(cam.global_position, 3.0)
			if sfx != null:
				sfx.play("whip", 5.0)
				sfx.play("scream", 4.0)
			_say("тянет к себе щупальцем, потом вдавит в камень")
			target_y = 2.0
			dark.color.a = 0.0
			monster.set_lit(2.0 if _bright else 1.0)
	elif _pull_t > 0.0:
		_pull_t -= delta
		var q: float = 1.8 - _pull_t
		if q < 1.1:
			# Тянет: камера едет к нему и заваливается.
			# 3.4, а не 2.2: вплотную кадр занимала одна зелёная масса.
			dist = lerpf(dist, 3.4, minf(1.0, delta * 2.6))
			target_y = lerpf(target_y, 1.9, minf(1.0, delta * 2.0))
			monster._aim_reach(cam.global_position + cam.global_transform.basis.x * 0.5)
			dark.color.a = 0.0
		else:
			# Вдавливает в камень позади: экран гаснет.
			dark.color.a = clampf((q - 1.1) / 0.7, 0.0, 1.0)
		if _pull_t <= 0.0:
			dark.color.a = 0.0
			dist = 9.0
			target_y = 2.0
			slab.visible = false
			monster.end_push()
			_say("в игре здесь тебя продавливает сквозь камень — и выбрасывает "
				+ "вниз головой уже в другом месте")
	elif _hold_to != Vector3.ZERO:
		# В хвате камера — это игрок: висит там, где сомкнулись руки.
		# ГЛАЗАМИ ИГРОКА. Смотреть на хват со стороны бессмысленно: судить надо
		# то, что видит человек, — а он висит ровно в точке, где смыкаются руки.
		# Отъехать колесом можно всегда.
		target_y = lerpf(target_y, _hold_to.y, minf(1.0, delta * 1.4))
		dist = lerpf(dist, 0.45, minf(1.0, delta * 1.4))
		if not grab_ui.visible:
			_hold_to = Vector3.ZERO
			monster.drop_hold()
			target_y = 2.0
			dist = 9.0
	# Пока идут руки с потолка — цель задана снаружи, и перебивать её камерой
	# нельзя: иначе они тянутся к наблюдателю, а не к тому, кого ловят.
	if monster.ceil_at == Vector3.ZERO:
		monster.aim_at = cam.global_position if _auto_reach else Vector3.ZERO
	monster.grasp_at = monster.aim_at
	monster._shiver(delta, true)
	if game_look:
		# Ровно та же формула, что в мире: квадрат от близости.
		var dm: float = cam.global_position.distance_to(monster.global_position)
		var kk: float = clampf(1.0 - dm / monster.LIT_FROM, 0.0, 1.0)
		mon_beam.light_energy = 1.0 + 9.0 * kk * kk
		monster.set_lit(kk * kk)
	# СТЕНЫ НЕ ЗАКРЫВАЮТ ОБЗОР. Обходя кругом, камера уходила за плиту, и полкадра
	# занимал серый прямоугольник. Прячем ту, что стоит между камерой и ним.
	if wall_l.visible or wall_r.visible or slab.visible:
		wall_l.visible = _corr and cam.global_position.x > wall_l.position.x
		wall_r.visible = _corr and cam.global_position.x < wall_r.position.x
		slab.visible = _slam_t > 0.0 and cam.global_position.z > slab.position.z
	# В ХВАТЕ вращаемся вокруг ТОЧКИ ДЕРЖАНИЯ, а не вокруг монстра. Центр был
	# на нём, и камера при малом радиусе оказывалась ВНУТРИ туши — та самая
	# прозрачность, которую видно было в смотровой.
	# ОБЕ атаки, а не только первая. Убрав из ветки атак выход из _process, я
	# оставил здесь проверку лишь на первую — и общий облёт камеры каждый кадр
	# затирал притягивание к пасти. Со стороны это выглядело как «тянет к ногам»
	# и «щупальце перестало тянуть вовсе».
	if hf_demo > 0:
		return
	var o: Vector3 = Vector3(0, target_y, monster.position.z)
	if _hold_to != Vector3.ZERO:
		o = Vector3(_hold_to.x, target_y, _hold_to.z)
	cam.position = o + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(o, Vector3.UP)
