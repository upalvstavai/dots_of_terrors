extends Node3D

## ОКНО, СМОТРЯЩЕЕ В НАСТОЯЩИЙ МИР. Своя камера, свободный полёт и панель
## кнопок. Вид у окна свой, а мир — тот самый, что запускается в игре.
##
## ПРАВИЛО ЭТОГО ФАЙЛА: кнопки НЕ ВОСПРОИЗВОДЯТ анимации и звуки «по памяти».
## Каждая зовёт ту же функцию мира, которую зовёт игра. Иначе лаборатория
## начнёт показывать не игру, а моё представление о ней, — а это уже было:
## смотровая открывалась с коридором 4.6 м при игровых 2.8, и походка в ней
## выглядела правильной, пока в игре половина ноги стояла в камне.

## Settings и Lang в этом проекте не глобальные классы, а подгружаемые файлы:
## без этих двух строк «Settings.quality» и «Lang.t» упали бы в игре, а не у
## проверялки — она таких имён не ловит.
const PlayerScript := preload("res://Player.gd")
const Settings := preload("res://Settings.gd")
const Lang := preload("res://Lang.gd")
const LabHub := preload("res://Lab.gd")

const SPEED := 5.4
const FAST := 3.2
const EYE: float = PlayerScript.EYE_Y   ## высота глаз игрока: с неё и надо смотреть коридор
const HINT := "ходьба: WASD — идти · СТРЕЛКИ — повернуться · ПРОБЕЛ — рывок    ||    полёт: WASD, Q/E, мышь с зажатой кнопкой"

var game: Node3D            ## настоящий мир
var lab                     ## пульт: у него живут общие линии-маршруты
var kind: String = "декорации"
## ХОДЬБА, А НЕ ПОЛЁТ. Свободный полёт удобен мышью и неудобен с одной
## клавиатуры, а главное — врёт: сквозь стены в игре не ходят, и оценивать
## декорации, пролетая их насквозь, значит смотреть не на то, что увидит
## игрок. Поэтому по умолчанию мы ВЕДЁМ ИГРОКА его же управлением, а камера
## сидит у него в голове. Полёт остался кнопкой — он нужен, чтобы посмотреть
## лабиринт сверху.
var walk: bool = true
var run_always: bool = true ## бесконечное ускорение: бег не кончается

var cam: Camera3D
var yaw: float = 0.0
var pitch: float = -0.05
var drag: bool = false
var rows: VBoxContainer
var info: Label
var log_box: Label
var look_lamp: OmniLight3D
var _log: Array = []
var _watching: float = 0.0  ## сколько ещё собирать журнал звуков
## Уровни музыки и бита держит сам Sfx (forced_mus / forced_beat): держать их
## отсюда, пересиливая мир каждый кадр, было борьбой, а не решением.


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 74.0
	cam.far = 120.0
	add_child(cam)
	cam.make_current()
	# ЛАМПА ОСМОТРА. Честная игровая темнота хороша в игре и бесполезна, когда
	# надо разглядеть, из чего сделана капель. Лампа висит на камере и её можно
	# погасить — тогда остаётся ровно игровой свет.
	#
	# ЯРКОСТЬ ВЗЯТА ОТ ИГРОВОЙ, А НЕ НА ГЛАЗ. Сперва я поставил конус в 3.2 —
	# и замер показал, что он не меняет ничего: окно давало среднюю яркость
	# 5.8 при игровых 10.1, то есть лампы в кадре не было видно вовсе. Фонарь
	# палочки в игре светит на 25, и слабее него смотровая лампа бессмысленна.
	# Всенаправленная, а не конус: разглядывать надо и потолок, и пол, и стену
	# за спиной, а не то, куда смотрит нос.
	look_lamp = OmniLight3D.new()
	look_lamp.light_energy = 20.0
	look_lamp.light_color = Color(0.88, 0.92, 0.96)
	look_lamp.omni_range = 34.0
	look_lamp.omni_attenuation = 0.6
	look_lamp.visible = kind == "декорации"
	cam.add_child(look_lamp)
	_build_panel()
	_start_world()
	_home()


## Мир надо ЗАПУСТИТЬ: пока не нажата клавиша на стартовом экране, в нём не
## тикает ничего — ни монстр, ни щупальца, ни свет палочки. Но собственную волю
## тут же отбираем (lab), а игрока замораживаем: мышь в лаборатории нужна для
## кнопок, а не для того, чтобы её забрал захват курсора.
func _start_world() -> void:
	if game == null:
		return
	game.lab = true
	if game.start_ui != null:
		game.start_ui.skip()
	if not game.started:
		game._on_start()
	# Игрока НЕ морозим: им и ходят. Мышь при этом свободна — она нужна кнопкам,
	# а поворачиваться в игре можно стрелками (это её штатное управление).
	game._freeze_player(not walk)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# ПАЛОЧКУ В РУКУ. В игре свет один — фонарь на палочке, и палочку игрок
	# сперва ищет: has_wand на старте false, её дают за прочитанную записку.
	# Первый снимок лаборатории вышел почти чёрным именно поэтому: мир был
	# правильный, света в нём не было вовсе. Выдаём напрямую — это то же
	# состояние, в котором игрок проводит всю игру после первой минуты.
	if game.dropped_wand != null:
		# Своей же функцией: она и лежащую палочку убирает, и флаги ставит.
		# Без этого палочка оказывалась сразу в руке И на полу — на кадре
		# лаборатории она так и лежала посреди коридора.
		game._take_wand()
	else:
		game.has_wand = true
		if game.player_node != null:
			game.player_node.has_wand = true
		if game.wand_lamp != null:
			game.wand_lamp.visible = true
		if game.wand_view != null:
			game.wand_view.visible = true


## Что окно на самом деле видит. Тот же вопрос, что и всегда: показывает ли
## стенд игру. Мир у окна должен быть ТОТ ЖЕ объект, что у мира, иначе камера
## смотрит в пустоту, а лампа светит в другой вселенной.
func report() -> String:
	var same: bool = game != null and get_world_3d() == game.get_world_3d()
	return "%s: мир %s, камера %s, игрок %s, палочка %s, лампа %s" % [
		kind, "тот же" if same else "ДРУГОЙ",
		str(cam.global_position.round()),
		str(game.player_node.global_position.round()) if game.player_node != null else "нет",
		"есть" if game != null and game.has_wand else "НЕТ",
		"горит" if look_lamp != null and look_lamp.visible else "погашена"]


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var pane := PanelContainer.new()
	pane.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pane.offset_left = 12.0
	pane.offset_top = 12.0
	pane.custom_minimum_size = Vector2(306, 0)
	layer.add_child(pane)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(306, 700)
	pane.add_child(scroll)

	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.custom_minimum_size = Vector2(288, 0)
	scroll.add_child(rows)

	info = Label.new()
	info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info.offset_left = 16.0
	info.offset_top = -58.0
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color(0.68, 0.76, 0.68))
	info.text = HINT
	layer.add_child(info)

	log_box = Label.new()
	log_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_box.offset_left = -560.0
	log_box.offset_top = 12.0
	log_box.offset_right = -12.0
	log_box.add_theme_font_size_override("font_size", 14)
	log_box.add_theme_color_override("font_color", Color(0.6, 0.72, 0.6))
	log_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(log_box)

	match kind:
		"декорации":
			_panel_decor()
		"анимации":
			_panel_anim()
		"звуки":
			_panel_sound()


func _head(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.78, 0.82, 0.7))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 8)
	rows.add_child(pad)
	rows.add_child(l)


func _btn(text: String, what: String, arg: Variant = null) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(284, 30)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(_on_press.bind(what, arg))
	rows.add_child(b)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.5, 0.54, 0.5))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(284, 0)
	rows.add_child(l)


# ─────────────────────────── панель декораций ───────────────────────────

func _panel_walk() -> void:
	_head("КАК ХОДИТЬ")
	_btn("ходьба / полёт", "mode")
	_btn("бег: бесконечный / как в игре", "run")
	_note("Ходьба: WASD — идти, СТРЕЛКИ влево-вправо — поворачиваться,"
		+ " ПРОБЕЛ — рывок. Всё с клавиатуры, мышь только для кнопок."
		+ " Полёт нужен, чтобы глянуть лабиринт сверху.")
	_head("КАРТА: ЛИНИИ К ТОЧКАМ")
	for row in LabHub.GROUPS:
		_btn(String(row[0]), "line", String(row[0]))
	_note("Линии идут ПО КОРИДОРАМ от тебя к каждой точке, а не напрямую"
		+ " через камень: по ним можно дойти. Видно их и сквозь стены."
		+ " Они общие на все окна, как и лампа.")


func _panel_decor() -> void:
	_panel_walk()
	_head("ГДЕ СМОТРЕТЬ")
	_btn("коридор с высоты глаз", "eye")
	_btn("сверху, вид на лабиринт", "top")
	_btn("выход из лабиринта", "cell", "exit")
	_btn("пролом: оттуда идёт свет", "cell", "hole")
	_btn("насыпь, по которой лезут", "cell", "climb")
	_head("ПОЛОТНА (их семь)")
	for i in 7:
		_btn("полотно %d" % (i + 1), "canv", i)
	_head("ОСТАЛЬНОЕ")
	_btn("ближайший стол с запиской", "near", "table")
	_btn("ближайшее убежище (круг мелом)", "near", "safe")
	_btn("ближайшее гнездо", "near", "nest")
	_btn("ближайшая капель", "near", "drip")
	_head("ЧЕМ КРУТИТЬ ВИД")
	_btn("безумие: 0 (чистый камень)", "mad", 0)
	_btn("безумие: 5 (стены шевелятся)", "mad", 5)
	_btn("безумие: 10", "mad", 10)
	_btn("безумие: 15 (потолок)", "mad", 15)
	_btn("качество: низкое", "qual", 0)
	_btn("качество: среднее", "qual", 1)
	_btn("качество: высокое", "qual", 2)
	_btn("фонарь палочки: вкл/выкл", "wand")
	_btn("лампа осмотра (общая): вкл/выкл", "lamp")
	_note("Безумие — это не цифра в углу: оно зеленит камень, гасит свет и"
		+ " густит туман. Качество меняет плотность сетки стен, то есть сам"
		+ " силуэт камня, а не только резкость.")
	_note("Лампа осмотра ОБЩАЯ для всех окон: мир один и тот же, а свет в"
		+ " Godot принадлежит миру, а не камере. Это цена того, что ты видишь"
		+ " настоящую игру, а не её копию. Погаси её — и останется ровно"
		+ " игровая темнота: с лампой средняя яркость кадра 64 из 255,"
		+ " без неё 6, у самой игры 10.")


# ─────────────────────────── панель анимаций ───────────────────────────

func _panel_anim() -> void:
	_panel_walk()
	_head("СЦЕНЫ ФАЗ")
	_btn("катсцена с лицом (первая фаза)", "face")
	_btn("глаза из камня (скример)", "eyes")
	_btn("третья фаза началась", "ph3")
	_note("Катсцена сама ведёт голову: игрок всматривается в ближайшую стену,"
		+ " камень дышит, и оттуда выходит лицо. Щупальце в ней НЕ хватает —"
		+ " первое появление способности должно её объявить, а не наказать.")
	_head("ДВА ЕГО ТЕЛА")
	_btn("стать фигурой (гуманоид)", "form")
	_btn("вернуть осьминога", "unform")
	_btn("поставить его в зал (на четвереньки)", "toroom")
	_btn("поставить его в коридор (в рост)", "tocorr")
	_note("В зале он зверь на четырёх опорах, щупальца из спины; в коридоре"
		+ " встаёт в рост, щупальца на груди, руками упирается в стены."
		+ " Переключается сам, по месту — поставь его туда и посмотри.")
	_head("ЕГО ПРИЁМЫ")
	_btn("выход из стены (рядом)", "emerge", true)
	_btn("выход из стены (поодаль)", "emerge", false)
	_btn("удар щупальцем из камня", "lash")
	_btn("руки с потолка", "hands")
	_btn("язык из пасти", "tongue")
	_btn("удар о стену", "slam")
	_btn("хват щупальцами из стен", "grab_wall")
	_btn("хват им самим", "grab_mon")
	_head("ЗАСАДЫ")
	_btn("1. поставить засаду за углом", "amb_corner")
	_btn("2. прыжок из засады", "amb_spring")
	_btn("1. притвориться стеной (плита)", "amb_wall")
	_note("Плиту надо СНАЧАЛА поставить, потом нажать прыжок: смысл приёма в"
		+ " том, что ты стоишь рядом с камнем, которого здесь не было.")
	_head("ПРОЧЕЕ")
	_btn("выброс в коридор", "drop")
	_btn("подъём по насыпи", "climbup")
	_btn("фаталити", "fatality")
	_head("КАМЕРА")
	_btn("смотреть на монстра", "watch_mon")
	_btn("смотреть на игрока", "watch_pl")
	_btn("вид от глаз игрока", "eye")
	_btn("лампа осмотра (общая): вкл/выкл", "lamp")
	_note("Анимации проигрываются НА ИГРОКЕ, который стоит в лабиринте"
		+ " замороженным. Смотреть удобнее со стороны — «смотреть на игрока».")
	_note("Свет здесь по умолчанию ИГРОВОЙ — то есть почти никакой. Так приёмы"
		+ " и видно в игре. Лампа осмотра общая на все окна, и включив её тут,"
		+ " ты осветишь и окно декораций.")


# ─────────────────────────── панель звуков ───────────────────────────

func _panel_sound() -> void:
	_panel_walk()
	_head("СИТУАЦИИ")
	_btn("выход из стены", "s_emerge")
	_btn("удар щупальцем из камня", "s_lash")
	_btn("руки с потолка", "s_hands")
	_btn("хват: щупальца из стен", "s_grab_wall")
	_btn("хват: он сам", "s_grab_mon")
	_btn("прыжок из засады", "s_amb")
	_btn("катсцена с лицом", "s_face")
	_btn("третья фаза началась", "s_ph3")
	_btn("полотно сдано", "s_solved")
	_btn("ошибка на полотне", "s_err")
	_head("МУЗЫКА И УДАРЫ")
	_btn("музыка: он далеко", "mus", 0.0)
	_btn("музыка: он в середине", "mus", 0.5)
	_btn("музыка: он вплотную", "mus", 1.0)
	_btn("удар: лицо из камня", "sting", "лицо")
	_btn("удар: вышел из-за угла", "sting", "угол")
	_btn("удар: началась погоня", "sting", "погоня")
	_btn("бит погони: вкл (он далеко)", "beat", 0.25)
	_btn("бит погони: вкл (он вплотную)", "beat", 1.0)
	_btn("бит погони: выкл", "beat", 0.0)
	_btn("вернуть музыку и бит игре", "release")
	_note("Музыка — два слоя в одной тональности. Нижний звучит всегда и ни о"
		+ " чём не предупреждает; верхний — малая секунда и тритон — проступает"
		+ " тем сильнее, чем он ближе, и ползёт вверх по тону. Спокойный слой"
		+ " при этом приглушается: музыка уступает, а не соревнуется.")
	_head("ПОГОНЯ: ГРОМЧЕ ВБЛИЗИ")
	_btn("он в 10 клетках", "s_near", 10.0)
	_btn("он в 6 клетках", "s_near", 6.0)
	_btn("он в 4 клетках", "s_near", 4.0)
	_btn("он в 2 клетках", "s_near", 2.0)
	_btn("он в 1 клетке", "s_near", 1.0)
	_btn("он в камне, в 2 клетках", "s_far", 2.0)
	_note("Справа — что игра попросила сыграть: имя записи, громкость добавки"
		+ " в децибелах и откуда шёл звук. Затухание по расстоянию добавляет"
		+ " сверху сам движок, поэтому «из точки» тише, чем цифра.")
	_head("ОТДЕЛЬНЫЕ ЗАПИСИ")
	for nm in ["scrape", "skitter", "whip", "roar", "scream", "hit_low",
			"hit_mid", "step_wet", "strain", "err", "door", "drip", "win"]:
		_btn(nm, "s_one", nm)


# ─────────────────────────── камера ───────────────────────────

func _home() -> void:
	if game == null:
		return
	_on_press("eye", null)


## Прыжок к точке. В ХОДЬБЕ прыгает сам игрок, а не камера: камера сидит у
## него в голове и через кадр вернулась бы обратно — кнопки выглядели бы
## сломанными. В полёте прыгает камера, как раньше.
func _go_to(p: Vector3, back: float) -> void:
	if walk and _pl() != null:
		var pl: Node3D = _pl()
		var to: Vector3 = p - pl.global_position
		to.y = 0.0
		if to.length() > 0.2:
			# Встаём НЕ В точку, а в шаге от неё и лицом к ней.
			var stand: Vector3 = p - to.normalized() * minf(back, 2.6)
			stand.y = pl.global_position.y
			pl.global_position = stand
			var look: Vector3 = p - stand
			pl.rotation.y = atan2(-look.x, -look.z)
			if "yaw" in pl:
				pl.yaw = pl.rotation.y
		return
	_look_at_point(p, back)


func _look_at_point(p: Vector3, back: float) -> void:
	var dir := Vector3(sin(yaw), -0.25, cos(yaw)).normalized()
	cam.global_position = p - dir * back + Vector3.UP * 1.1
	var to: Vector3 = p - cam.global_position
	yaw = atan2(-to.x, -to.z)
	pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.35, 1.2)
	_apply_cam()


func _apply_cam() -> void:
	cam.rotation = Vector3(pitch, yaw, 0.0)


func _process(delta: float) -> void:
	if _watching > 0.0:
		_watching -= delta
		_drain_sound_log()
		if _watching <= 0.0 and game != null and game.sfx != null:
			game.sfx.watch = false
	# ПАЛОЧКУ ПОДБИРАЕМ САМИ, И В ЛЮБОМ РЕЖИМЕ. Удар о стену и хват выбивают её
	# из руки — так в игре и задумано, — но в лаборатории это значит, что после
	# проверки одной атаки гаснет весь свет и смотреть больше нечего. Прогон
	# это и показал: «палочка НЕТ» после того, как нажали все кнопки приёмов.
	# Сперва я поставил подбор только в ходьбу, и в полёте он не работал.
	if game != null and not game.has_wand and game.dropped_wand != null:
		game._take_wand()
	if walk:
		_walk_tick()
		return
	var sp: float = SPEED * (FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var f := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		f -= cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		f += cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		f -= cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		f += cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		f += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		f -= Vector3.UP
	if f != Vector3.ZERO:
		cam.global_position += f.normalized() * sp * delta


## ВЗГЛЯД СО СТОРОНЫ — ЭТО ПОЛЁТ. В ходьбе камера сидит в голове и через кадр
## возвращается туда же, так что «смотреть на игрока» выглядело бы сломанной
## кнопкой. Переключаем режим сами, а не просим догадаться.
func _to_fly() -> void:
	if not walk:
		return
	walk = false
	if game != null:
		game._freeze_player(true)


## КАМЕРА СИДИТ В ГОЛОВЕ ИГРОКА. Не «рядом» и не «сзади»: смотреть надо ровно
## тем глазом, которым смотрит игрок, иначе высота и угол поедут, а вместе с
## ними и всё, что о декорациях подумаешь.
func _walk_tick() -> void:
	var p: Node3D = _pl()
	if p == null:
		return
	if p.has_node("Head"):
		cam.global_transform = (p.get_node("Head") as Node3D).global_transform
	else:
		cam.global_position = p.global_position + Vector3.UP * EYE
		cam.global_rotation = Vector3(0.0, p.rotation.y, 0.0)
	# БЕСКОНЕЧНОЕ УСКОРЕНИЕ. В игре рывок длится десять секунд и потом двадцать
	# секунд перезаряжается — в лаборатории это только мешает ходить.
	if run_always:
		p.sprint_left = 9999.0
		p.sprint_cool = 0.0
		p.sprint_drain = 0.0



func _unhandled_input(event: InputEvent) -> void:
	# В ХОДЬБЕ МЫШЬ ТОЖЕ ВЕРТИТ — только не камеру, а ИГРОКА. Раньше я движение
	# мыши здесь просто выбрасывал: поворот задуман стрелками, чтобы хватало
	# одной клавиатуры. На тачпаде это читается как поломка — жмёшь, ведёшь,
	# и ничего. Стрелки остаются, перетаскивание добавляется.
	if walk and event is InputEventMouseMotion and drag:
		var pl: Node3D = _pl()
		if pl != null:
			var mm2 := event as InputEventMouseMotion
			pl.yaw -= mm2.relative.x * 0.005
			pl.rotation.y = pl.yaw
			pl.pitch = clampf(pl.pitch - mm2.relative.y * 0.004, -1.2, 1.2)
		return
	if walk and not (event is InputEventMouseButton):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			drag = mb.pressed
	elif event is InputEventMouseMotion and drag:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		pitch = clampf(pitch - mm.relative.y * 0.005, -1.4, 1.3)
		_apply_cam()


# ─────────────────────────── кнопки ───────────────────────────

func _pl() -> Node3D:
	return game.player_node if game != null else null


func _cellv(cell: Vector2i, y: float) -> Vector3:
	return game.cell_to_world(cell, y)


func _on_press(what: String, arg: Variant) -> void:
	if game == null:
		return
	match what:
		"eye":
			var p: Node3D = _pl()
			if p != null:
				cam.global_position = p.global_position + Vector3.UP * EYE
				yaw = p.rotation.y
				pitch = 0.0
				_apply_cam()
			_say("вид с высоты глаз игрока, %.2f м — та же, что в игре" % EYE)
		"top":
			# Сверху — это полёт по определению: ходьба держит камеру в голове.
			_to_fly()
			var mid: Vector3 = _cellv(game.start_cell, 0.0)
			cam.global_position = Vector3(mid.x, 34.0, mid.z)
			pitch = -1.35
			_apply_cam()
			_say("сверху. лабиринт целиком — так видно, сколько его")
		"cell":
			var c: Vector2i = game.start_cell
			match String(arg):
				"exit":
					c = game.exit_cell
				"hole":
					c = game.holes[0] if not game.holes.is_empty() else game.start_cell
				"climb":
					c = game.climb_cell if game.climb_cell.x >= 0 else game.start_cell
			_go_to(_cellv(c, 1.2), 6.0)
			_say("клетка %s" % str(c))
		"canv":
			var i: int = int(arg)
			if i < game.canv_cells.size():
				_go_to(_cellv(game.canv_cells[i], 1.3), 4.2)
				_say("полотно %d, клетка %s" % [i + 1, str(game.canv_cells[i])])
			else:
				_say("полотен столько не расставлено")
		"near":
			_jump_near(String(arg))
		"mad":
			game.errors = int(arg)
			game._apply_madness()
			_say("безумие %d — камень, туман и свет пересчитаны" % int(arg))
		"qual":
			Settings.quality = int(arg)
			game.apply_quality()
			_say("качество %d. стены перестраиваются, это заметно на силуэте" % int(arg))
		"mode":
			walk = not walk
			if game != null:
				game._freeze_player(not walk)
			if not walk and _pl() != null:
				# В полёт уходим из того места, где стояли: иначе камера
				# прыгает в последнюю точку, где её оставили.
				cam.global_position = _pl().global_position + Vector3.UP * EYE
				yaw = _pl().rotation.y
				pitch = 0.0
				_apply_cam()
			_say("%s" % ("ходьба: WASD и стрелки, ПРОБЕЛ — рывок" if walk
				else "полёт: WASD, Q/E, мышь с зажатой кнопкой"))
		"run":
			run_always = not run_always
			if not run_always and _pl() != null:
				_pl().sprint_drain = 1.0
				_pl().sprint_left = 0.0
			_say("бег: %s" % ("бесконечный" if run_always else "как в игре — 10 с и перезарядка"))
		"line":
			if lab != null:
				var on: bool = lab.line_toggle(String(arg))
				_say("линии «%s»: %s" % [str(arg), "показаны" if on else "убраны"])
		"lamp":
			if look_lamp != null:
				look_lamp.visible = not look_lamp.visible
				_say("лампа осмотра: %s. погасишь — останется ровно игровой свет"
					% ("горит" if look_lamp.visible else "погашена"))
		"wand":
			if game.wand_lamp != null:
				game.wand_lamp.visible = not game.wand_lamp.visible
				_say("фонарь палочки: %s" % ("горит" if game.wand_lamp.visible else "погашен"))
		_:
			_on_press_act(what, arg)


func _jump_near(kind2: String) -> void:
	var from: Vector3 = cam.global_position
	var best: Vector3 = Vector3.ZERO
	var bd: float = 1e9
	var list: Array = []
	match kind2:
		"table":
			for t in game.tables:
				list.append(t["pos"])
		"safe":
			for c in game.safe_cells:
				list.append(_cellv(c, 0.2))
		"nest":
			for n in game.nests:
				list.append(n["pos"])
		"drip":
			for d in game.drips:
				list.append(_cellv(d["cell"], 2.0))
	for p in list:
		var d2: float = from.distance_to(p)
		if d2 < bd:
			bd = d2
			best = p
	if bd > 1e8:
		_say("такого в этом лабиринте не расставлено")
		return
	_go_to(best, 3.4)
	_say("%s: ближайший в %.0f м, всего их %d" % [kind2, bd, list.size()])


## АНИМАЦИИ И ЗВУКИ — ОДНИ И ТЕ ЖЕ ВЫЗОВЫ. Разница только в том, что окно
## звуков включает журнал и показывает, что именно прозвучало.
func _on_press_act(what: String, arg: Variant) -> void:
	var p: Node3D = _pl()
	var m = game.monster
	if p == null or m == null:
		_say("мир ещё не готов")
		return
	# ОДИН ЗВУК ЗА РАЗ. Он заметил верно: кнопки ложились друг на друга, и
	# разобрать, что именно звучит, было нельзя.
	if game.sfx != null:
		game.sfx.hush()
	var sound: bool = String(what).begins_with("s_")
	var act: String = String(what).substr(2) if sound else String(what)
	if sound:
		_watch_start()
	match act:
		"emerge":
			m.allow_emerge = true
			m.visible = false
			m.mode = "inwall"
			m._begin_surface(p.global_position, arg == null or bool(arg))
			_say("выход из стены: он появится %s" % ("вплотную" if arg == null or bool(arg) else "поодаль"))
		"lash":
			game.tell_pos = p.global_position - p.global_transform.basis.z * -game.cell_size * 2.0
			game.tell_miss = false
			game._lash_strike()
			_say("удар щупальцем из камня, сзади. в игре спасает ВЗГЛЯД")
		"hands":
			game._start_human_attack()
			_say("руки с потолка: держат, он бежит, потом хват")
		"tongue":
			game._human_tongue()
			_say("язык из пасти: рывок без окна на подумать")
		"slam":
			game._start_slam(game.world_to_cell(p.global_position))
			_say("удар о стену")
		"grab_wall":
			game._start_grab(Lang.t("g_wallburst"), "lash")
			_say("хват щупальцами из стен: петли рисуются, потому что это не он")
		"grab_mon":
			game._grab_now(Lang.t("g_mash"), "monster")
			_say("хват им самим: руками, без петель")
		"amb_corner":
			game.phase = maxi(game.phase, 2)
			game._ambush_arm()
			if game.amb_on:
				_look_at_point(_cellv(game.amb_cell, 1.2), 5.0)
				_say("засада за углом: поворот %s, он за ним в %s"
					% [str(game.amb_cell), str(game.amb_hide)])
			else:
				_say("поворота на маршруте не нашлось — пройди игроком дальше")
		"amb_wall":
			game.phase = 3
			game._wall_arm()
			if game.amb_on:
				_look_at_point(_cellv(game.amb_cell, 1.4), 5.2)
				_say("плита стоит в клетке %s. это настоящий шейдер стен"
					% str(game.amb_cell))
			else:
				_say("подходящей стены на маршруте не нашлось")
		"amb_spring":
			if game.amb_on:
				game._ambush_spring()
				_say("прыжок: плита сошла, дальше обычный хват и погоня")
			else:
				_say("сначала поставь засаду")
		"drop":
			game._respawn_drop()
			_say("выброс в коридор: щупальца бросают и уходят")
		"climbup":
			game._start_climb_up()
			_say("подъём по насыпи")
		"fatality":
			game._start_fatality()
			_say("фаталити")
		"face":
			# Сцена ставится только на свободный кадр и требует стены рядом:
			# в зале её ставить некуда. Поэтому фазу сбрасываем и говорим, если
			# сцена не пошла, — иначе кнопка выглядит сломанной.
			game.phase = 0
			game.face_stage = 0
			game._face_begin()
			_say("катсцена первой фазы пошла" if game.face_stage > 0
				else "рядом нет стены — отойди в коридор и нажми снова")
		"eyes":
			game.phase = maxi(game.phase, 1)
			m.scare_cool = 0.0
			game._on_wall_scare()
			_say("глаза из камня: экранный скример и он уползает в другую стену")
		"ph3":
			game._phase3_begin()
			_say("третья фаза: он перестал искать")
		"solved":
			if game.sfx != null:
				game.sfx.play("ok", 0.0)
			_say("полотно сдано")
		"err":
			if game.sfx != null:
				game.sfx.play("err", 0.0)
			_say("ошибка")
		"near":
			_chase_sound(float(arg), true)
		"far":
			_chase_sound(float(arg), false)
		"mus":
			# НАСИЛЬНО И НАСОВСЕМ. Обычный вызов мир затирал в том же кадре:
			# музыка и бит — это уровни, которые он задаёт каждый кадр по
			# расстоянию до монстра, а не разовые звуки.
			game.sfx.music_force(float(arg))
			_say("музыка на %.0f%%: слой напряжения %.0f дБ, тон %.2f (мир не мешает)"
				% [float(arg) * 100.0, game.sfx._mus_tense.volume_db,
				game.sfx._mus_tense.pitch_scale])
		"beat":
			game.sfx.beat_force(float(arg))
			_say("бит: %s" % ("выключен" if float(arg) <= 0.0
				else "%.0f%% близости, %.0f дБ, темп ×%.2f" % [float(arg) * 100.0,
					game.sfx._beat_player.volume_db,
					game.sfx._beat_player.pitch_scale]))
		"release":
			game.sfx.music_force(-1.0)
			game.sfx.beat_force(-1.0)
			_say("музыка и бит снова у игры: теперь ими правит расстояние")
		"sting":
			game.sfx.sting(String(arg), 0.0)
			_say("удар «%s»" % str(arg))
		"one":
			if game.sfx != null:
				game.sfx.play_at(String(arg), p.global_position, 0.0)
			_say("запись «%s» из точки игрока" % str(arg))
		"form":
			game.phase = maxi(game.phase, 2)
			game.form_cool = 0.0
			game.forms_left = maxi(game.forms_left, 1)
			m.visible = true
			m._grow_out()
			game._take_human_form()
			_say("фигура собирается: ком оседает, из лужи встаёт она")
		"unform":
			m.form_hold = 0.0
			_say("форма распускается обратно в ком")
		"toroom":
			var rr = game.room_rects
			if rr.is_empty():
				_say("залов на этой карте нет")
			else:
				var r0 = rr[0]
				var midc := Vector2i(int(r0.position.x + r0.size.x * 0.5),
					int(r0.position.y + r0.size.y * 0.5))
				if _pl() != null:
					_pl().global_position = game.cell_to_world(midc, PlayerScript.STAND_Y)
				m.global_position = game.cell_to_world(midc, 0.0) \
					+ Vector3(0, 0, game.cell_size * 2.5)
				m.visible = true
				m.mode = "chase"
				m.chase_t = 60.0
				_say("зал: он должен опуститься на четвереньки, щупальца — из спины")
		"tocorr":
			var pc2: Vector2i = game.world_to_cell(_pl().global_position)
			var found: bool = false
			# Коридор — это клетка пола со стенами с ДВУХ сторон: именно её
			# игра и считает теснотой, от неё же зависит, встанет ли он в рост.
			# Ищем ближайшую такую в восьми клетках от игрока.
			for i2 in range(2, 9):
				for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var c4: Vector2i = pc2 + d2 * i2
					if game.maze.is_wall(c4.x, c4.y):
						continue
					var wx: bool = game.maze.is_wall(c4.x, c4.y - 1) \
						and game.maze.is_wall(c4.x, c4.y + 1)
					var wz: bool = game.maze.is_wall(c4.x - 1, c4.y) \
						and game.maze.is_wall(c4.x + 1, c4.y)
					if wx or wz:
						m.global_position = game.cell_to_world(c4, 0.0)
						m.visible = true
						m.mode = "chase"
						m.chase_t = 60.0
						found = true
						break
				if found:
					break
			_say("коридор: он должен встать в рост и упереться руками в стены"
				if found else "прямого коридора рядом не нашлось")
		"watch_mon":
			_to_fly()
			_look_at_point(m.global_position + Vector3.UP * 1.6, 5.4)
			_say("смотрю на монстра со стороны (режим полёта)")
		"watch_pl":
			_to_fly()
			_look_at_point(p.global_position + Vector3.UP * 1.0, 4.6)
			_say("смотрю на игрока со стороны (режим полёта)")


## ПОГОНЯ НА ЗАКАЗ. Ставим его на нужное расстояние и даём миру сыграть свой
## кадр звука: это тот же _update_sound, что работает в игре, а не мой пересказ.
func _chase_sound(cells: float, out_now: bool) -> void:
	var p: Node3D = _pl()
	var m = game.monster
	m.global_position = p.global_position \
		+ p.global_transform.basis.z * game.cell_size * cells
	m.visible = out_now
	m.mode = "chase" if out_now else "inwall"
	game._skit_t = 0.0
	game._update_sound(0.016)
	_say("он %s, в %.0f клетках" % ["в коридоре" if out_now else "в камне", cells])


func _watch_start() -> void:
	if game.sfx == null:
		return
	game.sfx.heard.clear()
	game.sfx.watch = true
	_log.clear()
	_watching = 3.0


func _drain_sound_log() -> void:
	if game == null or game.sfx == null:
		return
	for e in game.sfx.heard:
		var where: String = "из точки" if bool(e["из точки"]) else "в голове"
		_log.append("%s   %+.1f дБ   %s" % [String(e["имя"]), float(e["дб"]), where])
	game.sfx.heard.clear()
	while _log.size() > 26:
		_log.pop_front()
	if log_box != null:
		log_box.text = "ЧТО ПРОЗВУЧАЛО\n" + "\n".join(_log)


func _say(text: String) -> void:
	if info != null:
		info.text = text + "\n" + HINT
