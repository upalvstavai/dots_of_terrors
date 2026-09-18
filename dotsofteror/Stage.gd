extends Node3D
## СЪЁМОЧНАЯ ПЛОЩАДКА — РОЛИК ОДНОЙ ЛЕНТОЙ.
##
## Четыре акта подряд: детская с проломом, полёт по коридорам со сменой фаз,
## встреча с обеими формами и по одной атаке от каждой. Камера летает там, где
## в игре летать нельзя, — но всё, что она снимает, собрано из тех же шейдеров,
## того же монстра и той же комнаты, что стоят в билде. Ничего нарисованного
## отдельно «для красоты» здесь нет: показанное можно потребовать вживую.
##
## Сборщики пролома с жижей и насыпи с солнцем оставлены ниже: они проверены и
## пригодятся, если в ленту понадобится ещё пара кадров.
##
## Управление: A — прогнать всё подряд, ПРОБЕЛ — следующий акт, R — повторить,
## H — убрать подписи (для чистой записи), F11 — во весь экран, ESC — выход.

const MonsterScript := preload("res://Monster.gd")
const SfxScript := preload("res://Sfx.gd")
const RoomScene := preload("res://room.tscn")
const WALL_SHADER := preload("res://wall.gdshader")
const FLOOR_SHADER := preload("res://floor.gdshader")
const POUR_SHADER := preload("res://pour.gdshader")
const GOO_SHADER := preload("res://goo.gdshader")
const Lang := preload("res://Lang.gd")
const Settings := preload("res://Settings.gd")
const BoardScript := preload("res://Board.gd")
const Grab3DScript := preload("res://Grab3D.gd")
const Shapes := preload("res://Shapes.gd")

## РАЗМЕРЫ БЕРУТСЯ ИЗ ИГРЫ, А НЕ СВОИ.
##
## Здесь стояло 2.8 и 4.3 — размеры лабиринта ДО того, как его расширили под
## нормальный человеческий рост. Ролик с тех пор снимал другой мир: коридор на
## сорок процентов уже игрового, и, что хуже, тварь заводилась той же строкой
## `monster.setup(null, CELL, ...)` — значит и посадка ног, и дистанция удара,
## и стойка считались от чужого числа. На плёнке было существо не из этой игры.
##
## Сверять надо с world.gd: cell_size 4.0, wall_height 6.0.
const CELL := 4.0
const WALL_H := 6.0

var cam: Camera3D
var flash: SpotLight3D
var fill: OmniLight3D           ## съёмочная подсветка, в игре её нет
var fill_r: OmniLight3D         ## и вторая, справа: иначе одна сторона в тени
var mon_beam: SpotLight3D
var monster
var sfx
var set_root: Node3D            ## всё, что построено под текущий акт
var wall_mat: ShaderMaterial    ## их и крутим, когда меняется фаза
var ceil_mat: ShaderMaterial
var env_ref: Environment
var nursery                     ## сцена детской, когда она в кадре
var goo: ColorRect
var fade: ColorRect
var caption: Label
var voice: Label
var thanks: Label
var board                       ## полотно: то, чем игрок вообще действует
var board_vp: SubViewport       ## его кадр: он натягивается на лист в мире
var board_face: MeshInstance3D  ## сам лист на мольберте
var grab3d                      ## щупальца и нож в пространстве
var _slash_from: Vector2 = Vector2.ZERO
var _slash_to: Vector2 = Vector2.ZERO
var _slash_k: float = 1.0       ## 0..1 — где сейчас взмах
var _slash_gap: float = 0.0     ## пауза до следующего взмаха
var _dot_t: float = 0.0
var _board_hit_done: bool = false
## Что уже выстрелило в текущем акте. Чистится при каждом _start.
var _fired: Dictionary = {}
var fat_tents: Array = []
var hint: Label
var shot: int = 0
var t: float = 0.0
var playing: bool = false
var auto_all: bool = true
var beat: int = -1              ## какая доля акта сейчас идёт
var shots: Array = []


func _ready() -> void:
	_build_env()
	cam = Camera3D.new()
	cam.fov = 62.0   # акты с атаками ставят себе шире
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	# ШИРЕ И ДАЛЬШЕ ИГРОВОГО. В игре узкий конус на девятнадцать метров — это
	# правило: смотреть по сторонам приходится головой. Но камера в ролике летит
	# по коридору, и с игровым лучом в кадре была одна темнота: стен не видно
	# вовсе. Здесь это съёмочный свет, а не механика.
	flash = SpotLight3D.new()
	flash.light_energy = 34.0
	flash.light_color = Color(0.86, 0.89, 0.96)
	flash.spot_range = 30.0
	flash.spot_angle = 55.0
	flash.spot_angle_attenuation = 0.9
	flash.spot_attenuation = 0.7
	flash.shadow_enabled = true
	flash.light_volumetric_fog_energy = 0.0
	cam.add_child(flash)
	mon_beam = SpotLight3D.new()
	mon_beam.light_color = Color(0.86, 0.95, 1.0)
	mon_beam.light_energy = 0.0
	mon_beam.spot_range = 26.0
	mon_beam.spot_angle = 46.0
	mon_beam.spot_angle_attenuation = 0.6
	mon_beam.light_cull_mask = 1 << 4
	mon_beam.shadow_enabled = false
	cam.add_child(mon_beam)
	# Заполняющий свет вокруг камеры: без него ближние стены и пол уходят в
	# сплошную черноту, и коридор читается пустотой, а не коридором.
	fill = OmniLight3D.new()
	fill.light_energy = 4.2
	fill.light_color = Color(0.72, 0.78, 0.86)
	fill.omni_range = 21.0
	fill.omni_attenuation = 1.4
	fill.shadow_enabled = false
	# СБОКУ И СВЕРХУ, а не из объектива. Лампа ровно на оси камеры давала на
	# гладкой туше круглый блик точно в середине кадра — он ехал за камерой и
	# читался пятном на теле, а не светом. Сдвинутая лампа лепит форму.
	fill.position = Vector3(-1.25, 0.85, 0.35)
	cam.add_child(fill)
	# И ВТОРАЯ, СПРАВА, слабее. Замер показал, что упоры в правую стену на
	# месте — их тени просто некому было подсветить: единственная лампа стояла
	# слева, и вся правая половина туши с руками уходила в чёрное.
	fill_r = OmniLight3D.new()
	fill_r.light_color = Color(0.66, 0.72, 0.82)
	fill_r.light_energy = 2.1
	fill_r.omni_range = 19.0
	fill_r.omni_attenuation = 1.4
	fill_r.shadow_enabled = false
	fill_r.position = Vector3(1.35, 0.55, 0.35)
	cam.add_child(fill_r)
	monster = MonsterScript.new()
	add_child(monster)
	monster.setup(null, CELL, 3.2, 12345)
	monster.manual_space = true
	monster.visible = false
	sfx = SfxScript.new()
	add_child(sfx)
	_build_ui()
	# ПОЛНАЯ ЛЕНТА НА ДВУХ ЯЗЫКАХ. Раньше английской была только магазинная — с
	# другим монтажом и вдвое короче. Показать иностранцу полную ленту было
	# нечем. Подписи берутся через _cap, реплики твари — из общего словаря, и
	# обе стороны переключает один флаг.
	if OS.get_cmdline_user_args().has("англ"):
		Settings.lang = "en"
	shots = [
		{"name": "детская", "len": 19.2, "cap": _cap("это не твоя комната",
			"this is not your room")},
		# СРАЗУ ПОСЛЕ КОМНАТЫ. В детской он видит блокнот с точками, а здесь
		# уже соединяет их в лабиринте — механика объясняется без единого слова.
		# И это главное, чем игра не похожа на другой тёмный коридор: без этого
		# куска лента показывала мир и тварь, но не саму игру.
		{"name": "полотно", "len": 8.0, "cap": _cap("рисовать — единственное, что ты умеешь",
			"drawing is the only thing you can do")},
		# СРАЗУ ПОСЛЕ ПОЛОТНА — ЧЕМ ОТБИВАЮТСЯ. Порядок тут смысловой: вот
		# единственное, что ты умеешь (рисовать), вот чем за это платят
		# (щупальца в лицо), и вот чем от этого отбиваются (палочка-лезвие).
		{"name": "нож", "len": 11.0, "cap": _cap("палочка — единственное лезвие",
			"the wand is your only blade")},
		{"name": "фазы", "len": 11.0, "cap": ""},
		{"name": "формы", "len": 20.0, "cap": ""},
		{"name": "атаки", "len": 19.0, "cap": ""},
		{"name": "зрители", "len": 8.0, "cap": _cap("оно знает, что ты не один",
			"it knows you are not alone")},
		{"name": "добивание", "len": 10.0, "cap": _cap("вторая смерть — последняя",
			"the second death is the last")},
		{"name": "титр", "len": 6.0, "cap": _cap("ТОЧКИ УЖАСА", "DOTS OF TERROR")},
	]
	# ВЕРСИЯ ДЛЯ МАГАЗИНА. Другая лента из тех же актов: пятьдесят секунд,
	# сильное впереди, подписи по-английски. В ленте Steam человек уходит за
	# первые десять секунд, поэтому начинаем не с атмосферы, а с твари,
	# и берём из каждого акта только его лучший кусок — поле «от».
	# ТИЗЕР. Короткая лента, чтобы позвать зрителя, — БЕЗ добивания и без фразы
	# про зрителей. Самое сильное держим до страницы в Steam: показать козырь
	# некуда ведущим роликом — значит потратить его впустую.
	if OS.get_cmdline_user_args().has("тизер"):
		shots = [
			{"name": "детская", "от": 1.0, "len": 6.5, "cap": "это не твоя комната"},
			{"name": "полотно", "от": 0.0, "len": 7.0, "cap": "рисовать — единственное, что ты умеешь"},
			{"name": "нож", "от": 1.6, "len": 6.5, "cap": "палочка — единственное лезвие"},
			{"name": "фазы", "от": 1.5, "len": 7.0, "cap": "лабиринт портится вместе с тобой"},
			{"name": "тварь", "от": 1.2, "len": 5.0, "cap": "оно ходит сквозь камень"},
			{"name": "титр", "от": 0.0, "len": 4.5, "cap": "ТОЧКИ УЖАСА"},
		]
	elif OS.get_cmdline_user_args().has("магазин"):
		# Реплики твари берутся из общего словаря, а он смотрит на язык
		# настроек. В магазинной ленте подписи английские — значит и голос
		# должен быть английским, иначе в одном кадре два языка.
		Settings.lang = "en"
		shots = [
			{"name": "тварь", "от": 0.8, "len": 4.6, "cap": "IT WALKS THROUGH STONE"},
			{"name": "атаки", "от": 3.2, "len": 5.0, "cap": "AND STRIKES FROM THE WALLS"},
			# ПОСЛЕ УГРОЗЫ — ТО, ЧЕМ ЕЙ ОТВЕЧАЮТ. Сначала показали, что оно ходит
			# сквозь камень и бьёт из стен, и тут же — что у тебя есть только
			# точки и таймер. Контраст и продаёт: без этого куска страница в
			# Steam обещает ещё один хоррор про монстра в подвале.
			# Берём с 1.5 с: к этому времени часть линий уже проведена, и доска
			# читается сразу, а не начинается с пустоты.
			{"name": "полотно", "от": 1.5, "len": 5.5, "cap": "YOUR ONLY WEAPON IS DRAWING"},
			{"name": "нож", "от": 1.6, "len": 5.6, "cap": "AND YOUR ONLY BLADE"},
			{"name": "детская", "от": 0.6, "len": 6.0, "cap": "THIS IS NOT YOUR ROOM"},
			{"name": "фазы", "от": 2.2, "len": 6.0, "cap": "THE MAZE ROTS WITH YOU"},
			{"name": "формы", "от": 11.0, "len": 6.0, "cap": "IT IS NOT ALWAYS ITSELF"},
			{"name": "зрители", "от": 1.4, "len": 6.2, "cap": "AND IT KNOWS YOU ARE WATCHING"},
			{"name": "добивание", "от": 0.6, "len": 7.4, "cap": "THE SECOND DEATH IS THE LAST"},
			{"name": "титр", "от": 0.0, "len": 5.0, "cap": "DOTS OF TERROR"},
		]
	# Снимать можно один акт: «-- снимки только=детская». Гонять ради одной
	# комнаты все пять актов с монстром — минута ожидания на каждую правку.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("только="):
			var want: String = a.substr(len("только="))
			var keep: Array = []
			for sh in shots:
				if str(sh["name"]) == want:
					keep.append(sh)
			if not keep.is_empty():
				shots = keep
	_start(0)
	if OS.get_cmdline_user_args().has("снимки"):
		_shots_pass()
	# ЗАПИСЬ. Годо умеет писать видео сам (--write-movie), но выйти из игры по
	# концу ленты он не догадается — а лишние секунды чёрного в конце файла
	# никому не нужны. Этот режим гасит СЛУЖЕБНУЮ строку и закрывает игру, когда
	# титр досмотрен.
	#
	# ПОДПИСИ ОСТАЮТСЯ. Раньше гасились и они — вместе со служебной строкой, — и
	# все ленты выходили немыми: ни «это не твоя комната», ни продающих строк
	# магазинного трейлера в файлах не было вовсе. Проверено кадром: в нижней
	# полосе самый светлый пиксель 84 из 255, то есть текста нет. А половина
	# зрителей в Steam смотрит без звука, и для них немой трейлер не говорит
	# о игре ничего.
	elif OS.get_cmdline_user_args().has("запись"):
		hint.visible = false
		auto_all = true


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.07)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.04, 0.045)
	env.fog_density = 0.045
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.014
	env.volumetric_fog_emission = Color(0.02, 0.03, 0.03)
	we.environment = env
	env_ref = env
	add_child(we)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	goo = ColorRect.new()
	goo.set_anchors_preset(Control.PRESET_FULL_RECT)
	goo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = GOO_SHADER
	goo.material = gm
	goo.visible = false
	layer.add_child(goo)
	# Чёрная штора: ею гасим переходы между актами, иначе склейка читается
	# рывком камеры, а не сменой места.
	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	caption = Label.new()
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.offset_top = -92.0
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color(0.88, 0.87, 0.84))
	layer.add_child(caption)
	# СПАСИБО ЗА ПРОСМОТР. Только на титре и только по-английски: лента уходит
	# к стримерам и в Steam, а там это обычная вежливость в конце. Приходит
	# ПОЗЖЕ названия — сперва пусть прочтут, как игра называется.
	thanks = Label.new()
	thanks.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thanks.offset_top = -56.0
	thanks.add_theme_font_size_override("font_size", 15)
	thanks.add_theme_color_override("font_color", Color(0.52, 0.51, 0.49))
	thanks.text = "THANK YOU FOR WATCHING"
	thanks.modulate.a = 0.0
	layer.add_child(thanks)
	# ГОЛОС ТВАРИ. В игре это отдельный слой посреди экрана, и в ролике он
	# должен выглядеть так же, а не подписью внизу.
	voice = Label.new()
	voice.set_anchors_preset(Control.PRESET_FULL_RECT)
	voice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	voice.add_theme_font_size_override("font_size", 34)
	voice.add_theme_color_override("font_color", Color(0.88, 0.86, 0.84))
	voice.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	voice.add_theme_constant_override("shadow_offset_x", 2)
	voice.add_theme_constant_override("shadow_offset_y", 2)
	voice.modulate.a = 0.0
	layer.add_child(voice)
	# ПОЛОТНО. Единственное, чем игрок вообще действует, — и в ленте его до сих
	# пор не было вовсе: ролик показывал мир и тварь, но не игру.
	#
	# И ТЕПЕРЬ ОНО В МИРЕ, А НЕ ПОВЕРХ ЭКРАНА. В игре полотно давно висит
	# листом на мольберте: камера смотрит на настоящий предмет в коридоре, по
	# нему течёт краска, и на сдаче он прожигает темноту. Лента же показывала
	# прежнее плоское окно во весь кадр — то есть другую игру. Кадр собираем
	# тем же способом, что и мир: полотно рисуется в отдельный SubViewport,
	# а тот натягивается на лист.
	board_vp = SubViewport.new()
	board_vp.size = Vector2i(1000, 800)
	board_vp.transparent_bg = false
	board_vp.canvas_item_default_texture_filter = \
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	board_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board_vp.disable_3d = true
	add_child(board_vp)
	board = BoardScript.new()
	# Растянут по кадру viewport-а: размер ему задаёт сам кадр, руками его
	# трогать нельзя — Godot всё равно перезапишет после _ready и предупредит.
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.visible = false
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_vp.add_child(board)
	hint = Label.new()
	hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hint.position = Vector2(18, 14)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.45, 0.46, 0.44))
	layer.add_child(hint)


## ─────────────────────────── декорации ───────────────────────────

func _clear_set() -> void:
	if set_root != null:
		set_root.queue_free()
	set_root = Node3D.new()
	add_child(set_root)
	nursery = null
	wall_mat = null
	ceil_mat = null
	# Лист жил в set_root: он ушёл вместе с декорацией, и ссылку надо погасить,
	# иначе следующий акт трогает освобождённый узел.
	board_face = null
	if grab3d != null:
		grab3d.finish()
	monster.visible = false
	monster.form_hold = 0.0
	monster.form_t = 0.0
	monster.arms_up = 0.0
	monster.ceiling_release()
	monster.end_push()
	goo.visible = false
	goo.material.set_shader_parameter("wipe", 0.0)
	mon_beam.light_energy = 0.0
	_phase_look(0)


## Вид мира по фазе: чем дальше, тем гуще прожилки в камне и плотнее туман.
## Те же величины, что крутит сама игра при росте безумия.
func _phase_look(stage_n: int) -> void:
	var k: float = [0.07, 0.45, 1.0][clampi(stage_n, 0, 2)]
	if wall_mat != null:
		wall_mat.set_shader_parameter("madness", k)
	if ceil_mat != null:
		ceil_mat.set_shader_parameter("madness", k)
	if env_ref != null:
		# Туман вдвое жиже игрового: в игре он прячет конец коридора и это
		# правильно, а в ролике из-за него коридор кончался чёрной стеной в трёх
		# метрах от камеры.
		env_ref.fog_density = 0.011 * (1.0 + k)
		# Общий свет держим низким, а форму даёт не он, а лампы: на высоком
		# ambient камень становился ровно-серым, будто в тумане, и переставал
		# читаться камнем.
		env_ref.ambient_light_energy = 1.05 * (1.0 - k * 0.28)


## ДЕТСКАЯ — настоящая, из игры. Забираем сцену пролога целиком, выбрасываем из
## неё игрока с его интерфейсом и открываем пролом: снимать надо комнату, а не
## проходить её.
func _nursery() -> void:
	nursery = RoomScene.instantiate()
	set_root.add_child(nursery)
	nursery.set_process(false)
	nursery.set_process_unhandled_input(false)
	if nursery.player != null:
		nursery.player.queue_free()
		nursery.player = null
	for ch in nursery.get_children():
		if ch is CanvasLayer:
			(ch as CanvasLayer).visible = false
	nursery.stage = 3
	nursery.lamp_on = true
	nursery.lamp.light_energy = 2.2
	var bm: StandardMaterial3D = nursery.lamp_bulb.material_override
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.88, 0.66)
	bm.emission_energy_multiplier = 1.4
	nursery.hole.visible = true
	nursery.floor_whole.visible = false
	nursery.floor_cut.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## РАЗНЫЕ КОРИДОРЫ, А НЕ ОДИН. Все акты строили одну и ту же трубу с одним и тем
## же камнем. Подряд это читается как ковёр под моделью: тварь идёт, а место не
## меняется, и через полминуты зритель перестаёт верить, что там лабиринт.
##
## Разводим ТРЕМЯ признаками сразу, потому что одного мало: два коридора с разной
## порчей камня, но одинаковыми лампами через шесть метров и глухими стенами всё
## равно узнаются как один и тот же.
##   КАМЕНЬ — насколько он испорчен (тот же параметр, что растёт от безумия);
##   НИШИ   — разрывы в боковой стене: видно, что коридор часть чего-то;
##   СВЕТ   — цвет и частота ламп.
const NICHE_W := 2.6        ## ширина разрыва в стене


func _corridor(length: float, gap_z: float = INF, look: int = 0) -> void:
	var mad: float = [0.07, 0.42, 0.80, 1.0][look % 4]
	var lamp_col: Color = [
		Color(0.70, 0.78, 0.88), Color(0.78, 0.74, 0.66),
		Color(0.62, 0.80, 0.72), Color(0.80, 0.66, 0.62)][look % 4]
	var lamp_step: float = [6.0, 7.5, 5.0, 9.0][look % 4]
	var lamp_e: float = [4.6, 3.6, 4.0, 2.8][look % 4]
	# Ниши по сторонам. Слева их нет у вида 1: в акте атак из левой стены лезет
	# сам монстр, и дыра рядом с ним читалась бы как его нора.
	var cuts_l: Array = [[], [], [-length * 0.30], []][look % 4]
	var cuts_r: Array = [[], [length * 0.16], [length * 0.10], [-length * 0.05, length * 0.34]][look % 4]
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = WALL_SHADER
	wall_mat.set_shader_parameter("detail", 1.0)
	wall_mat.set_shader_parameter("near_dist", 3.2)
	wall_mat.set_shader_parameter("madness", mad)
	for sx in [-1.0, 1.0]:
		for seg in _wall_parts(length, cuts_l if sx < 0.0 else cuts_r):
			var w := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, WALL_H, float(seg[0]))
			bm.subdivide_width = 2
			bm.subdivide_height = 8
			bm.subdivide_depth = maxi(2, int(float(seg[0]) * 2.0))
			w.mesh = bm
			w.material_override = wall_mat
			w.position = Vector3(sx * (CELL * 0.5 + 0.3), WALL_H * 0.5, float(seg[1]))
			set_root.add_child(w)
		# За нишей — глухой торец, иначе в дыру видно пустоту сцены.
		for cz in (cuts_l if sx < 0.0 else cuts_r):
			var b := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.6, WALL_H, NICHE_W)
			b.mesh = bb
			b.material_override = wall_mat
			b.position = Vector3(sx * (CELL * 0.5 + 2.4), WALL_H * 0.5, float(cz))
			set_root.add_child(b)
	var fm := ShaderMaterial.new()
	fm.shader = FLOOR_SHADER
	fm.set_shader_parameter("relief", 1.0)
	var fl := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(CELL, 0.3, length)
	fb.subdivide_width = 6
	fb.subdivide_depth = int(length * 2.4)
	fl.mesh = fb
	fl.material_override = fm
	fl.position = Vector3(0, -0.15, 0)
	set_root.add_child(fl)
	ceil_mat = ShaderMaterial.new()
	ceil_mat.shader = WALL_SHADER
	ceil_mat.set_shader_parameter("base_color", Color(0.105, 0.105, 0.112))
	ceil_mat.set_shader_parameter("bulge", 0.42)
	ceil_mat.set_shader_parameter("near_dist", 6.5)
	ceil_mat.set_shader_parameter("relief", 1.8)
	ceil_mat.set_shader_parameter("madness", mad)
	# Потолок кусками с разрывом, если просят дыру: сплошная плита закрывает и
	# солнце, и столб света, а камера, поднимаясь, проходит сквозь неё.
	var parts: Array = []
	if is_inf(gap_z):
		parts.append([length, 0.0])
	else:
		var back: float = (gap_z - CELL * 0.5) - (-length * 0.5)
		var front: float = (length * 0.5) - (gap_z + CELL * 0.5)
		if back > 0.2:
			parts.append([back, -length * 0.5 + back * 0.5])
		if front > 0.2:
			parts.append([front, length * 0.5 - front * 0.5])
	# ФОНАРИ ВДОЛЬ КОРИДОРА. Только для съёмки: в игре их нет и быть не должно.
	# Без них замер средней яркости кадра давал 22 из 255 — то есть коридор
	# честно чёрный, стен по бокам почти не разобрать, а впереди пусто. Пятна
	# света через каждые шесть метров дают и глубину, и направление.
	var lamps: int = int(length / lamp_step)
	for i in lamps:
		var l := OmniLight3D.new()
		l.light_color = lamp_col
		l.light_energy = lamp_e
		l.omni_range = 8.5
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		l.position = Vector3(0, WALL_H - 0.9,
			-length * 0.5 + 3.0 + float(i) * lamp_step)
		set_root.add_child(l)
	for pr in parts:
		var ce := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(CELL, 0.3, float(pr[0]))
		cb.subdivide_width = 6
		cb.subdivide_depth = maxi(2, int(float(pr[0]) * 2.4))
		ce.mesh = cb
		ce.material_override = ceil_mat
		ce.position = Vector3(0, WALL_H, float(pr[1]))
		set_root.add_child(ce)


## ЩУПАЛЬЦА ИЗ СТЕН НА ПОДЪЁМЕ. В добивании не было видно, ЧЕМ игрока поднимает:
## кадр уезжал вверх сам собой, и со стороны это читалось как телекинез. Держат
## его вот эти — из обеих стен, разом, ровно в тот момент, когда начинается
## подъём, и тянутся туда же, куда едет камера.
const TENT_SHADER := preload("res://tentacle.gdshader")
const FAT_TENTS := 14


func _build_fat_tents(at: Vector3) -> void:
	for n in fat_tents:
		(n["node"] as Node3D).queue_free()
	fat_tents.clear()
	for i in FAT_TENTS:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var row: int = i / 2
		# Вдоль прохода и по высоте вразнобой: ряд одинаковых — это забор,
		# а не щупальца.
		var z: float = at.z - 2.2 + float(row) * 0.72
		var y: float = 0.85 + float((i * 7) % 5) * 0.52
		var ln: float = 1.5 + float((i * 3) % 4) * 0.42
		# Из стены внутрь и ВВЕРХ: они тянутся туда же, куда поднимают.
		var dir: Vector3 = (Vector3(-side, 0.0, 0.0) + Vector3.UP * 0.62).normalized()
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.14
		cm.height = 1.0
		cm.radial_segments = 8
		cm.rings = 14
		cm.cap_top = true
		mi.mesh = cm
		var m := ShaderMaterial.new()
		m.shader = TENT_SHADER
		m.set_shader_parameter("phase", float(i) * 0.83)
		m.set_shader_parameter("wave", 0.26 + float(i % 3) * 0.09)
		m.set_shader_parameter("speed", 2.0 + float(i % 4) * 0.55)
		mi.material_override = m
		mi.visible = false
		set_root.add_child(mi)
		fat_tents.append({"node": mi, "root": Vector3(side * (CELL * 0.5), y, z),
			"dir": dir, "len": ln})


## Насколько щупальца вылезли: 0 — в стене, 1 — во всю длину.
func _fat_tents_grow(k: float) -> void:
	for tt in fat_tents:
		var mi: MeshInstance3D = tt["node"]
		if k <= 0.001:
			mi.visible = false
			continue
		mi.visible = true
		var ln: float = float(tt["len"]) * k
		var dir: Vector3 = tt["dir"]
		mi.global_position = Vector3(tt["root"]) + dir * (ln * 0.5)
		mi.look_at(mi.global_position + dir, Vector3.UP)
		# +Y меша смотрит ИЗ стены, а look_at наводит -Z. Отсюда доворот.
		mi.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		mi.scale = Vector3(1.0, ln, 1.0)


## Стена кусками: целая полоса минус разрывы. Возвращает [длина, середина].
func _wall_parts(length: float, cuts: Array) -> Array:
	var edges: Array = []
	for cz in cuts:
		edges.append([float(cz) - NICHE_W * 0.5, float(cz) + NICHE_W * 0.5])
	edges.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	var from: float = -length * 0.5
	for e in edges:
		var a: float = maxf(from, float(e[0]))
		if a - from > 0.2:
			out.append([a - from, (from + a) * 0.5])
		from = maxf(from, float(e[1]))
	if length * 0.5 - from > 0.2:
		out.append([length * 0.5 - from, (from + length * 0.5) * 0.5])
	return out


## Пролом с занавесом жижи — в ленту сейчас не входит, но проверен и готов.
func _pour(at: Vector3) -> void:
	var sun := SpotLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.82)
	sun.light_energy = 4.5
	sun.light_volumetric_fog_energy = 18.0
	sun.spot_range = WALL_H + 6.0
	sun.spot_angle = 21.0
	sun.spot_angle_attenuation = 0.9
	sun.spot_attenuation = 0.6
	sun.shadow_enabled = true
	sun.position = at + Vector3(0, WALL_H + 2.6, 0)
	sun.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	set_root.add_child(sun)
	var sky := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(CELL * 0.96, 0.1, CELL * 0.96)
	sky.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.97, 0.88)
	smat.disable_fog = true
	sky.mesh.surface_set_material(0, smat)
	sky.position = at + Vector3(0, WALL_H + 3.0, 0)
	set_root.add_child(sky)
	var rim := ShaderMaterial.new()
	rim.shader = POUR_SHADER
	rim.set_shader_parameter("melt", 1.0)
	rim.set_shader_parameter("half_h", 0.75)
	var curtain := MeshInstance3D.new()
	var cm2 := CylinderMesh.new()
	cm2.top_radius = CELL * 0.56
	cm2.bottom_radius = CELL * 0.50
	cm2.height = 1.5
	cm2.radial_segments = 40
	cm2.rings = 14
	cm2.cap_top = false
	cm2.cap_bottom = false
	curtain.mesh = cm2
	curtain.material_override = rim
	curtain.position = at + Vector3(0, WALL_H - 0.3, 0)
	set_root.add_child(curtain)
	var thin := ShaderMaterial.new()
	thin.shader = POUR_SHADER
	for i in 4:
		var a: float = randf() * TAU
		var th := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.055
		tm.bottom_radius = 0.03
		tm.height = WALL_H - 0.1
		tm.radial_segments = 8
		th.mesh = tm
		th.material_override = thin
		th.position = at + Vector3(cos(a) * CELL * 0.45, (WALL_H - 0.1) * 0.5,
			sin(a) * CELL * 0.45)
		set_root.add_child(th)
	var pool := MeshInstance3D.new()
	var pm := TorusMesh.new()
	pm.inner_radius = CELL * 0.30
	pm.outer_radius = CELL * 0.62
	pool.mesh = pm
	pool.material_override = thin
	pool.scale = Vector3(1.0, 0.10, 1.0)
	pool.position = at + Vector3(0, 0.04, 0)
	set_root.add_child(pool)


## Насыпь обвала с небом над ней — тоже готова и тоже пока не в ленте.
func _mound(at: Vector3) -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.10, 0.10, 0.11)
	stone.roughness = 1.0
	var half: float = CELL * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array = [Vector3(-half, 0, -half), Vector3(half, 0, -half),
		Vector3(half, 0, half), Vector3(-half, 0, half)]
	var peak := Vector3(0, 0.55, 0)
	for i in 4:
		var c1: Vector3 = corners[i]
		var c2: Vector3 = corners[(i + 1) % 4]
		st.set_normal((c2 - c1).cross(peak - c1).normalized())
		st.add_vertex(c1)
		st.add_vertex(c2)
		st.add_vertex(peak)
	var mound := MeshInstance3D.new()
	mound.mesh = st.commit()
	mound.material_override = stone
	mound.position = at
	set_root.add_child(mound)
	var skmat := StandardMaterial3D.new()
	skmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skmat.albedo_color = Color(0.62, 0.74, 0.88)
	skmat.disable_fog = true
	var sky := MeshInstance3D.new()
	var skm := BoxMesh.new()
	skm.size = Vector3(CELL * 34.0, 0.1, CELL * 34.0)
	sky.mesh = skm
	sky.mesh.surface_set_material(0, skmat)
	sky.position = at + Vector3(0, WALL_H + 7.0, 0)
	set_root.add_child(sky)
	var sunmat := StandardMaterial3D.new()
	sunmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sunmat.albedo_color = Color(1.0, 0.98, 0.90)
	sunmat.disable_fog = true
	var sun := MeshInstance3D.new()
	var sm3 := SphereMesh.new()
	sm3.radius = 1.25
	sm3.height = 2.5
	sun.mesh = sm3
	sun.material_override = sunmat
	sun.position = at + Vector3(1.35, WALL_H + 3.9, -3.5)
	set_root.add_child(sun)
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.albedo_color = Color(0.07, 0.08, 0.06)
	edge.disable_fog = true
	for i in 26:
		var a4: float = TAU * float(i) / 26.0
		var r4: float = CELL * randf_range(0.40, 0.52)
		var blade := MeshInstance3D.new()
		var bm4 := CylinderMesh.new()
		bm4.top_radius = 0.005
		bm4.bottom_radius = 0.035
		bm4.height = randf_range(0.25, 0.75)
		bm4.radial_segments = 5
		blade.mesh = bm4
		blade.material_override = edge
		blade.position = at + Vector3(cos(a4) * r4, WALL_H + bm4.height * 0.45,
			sin(a4) * r4)
		blade.rotation = Vector3(randf_range(-0.5, 0.5), a4, randf_range(-0.5, 0.5))
		set_root.add_child(blade)
	for i in 9:
		var a5: float = randf_range(-1.1, 1.1)
		var far: float = randf_range(26.0, 44.0)
		var tr := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(randf_range(0.9, 2.2), randf_range(3.0, 7.5),
			randf_range(0.9, 2.2))
		tr.mesh = tb
		tr.material_override = edge
		tr.position = at + Vector3(sin(a5) * far, WALL_H + tb.size.y * 0.45,
			-cos(a5) * far)
		set_root.add_child(tr)


## КЛЮЧЕВОЙ СВЕТ. Для ролика это законно: декорация и монстр те же, просто
## поставлен свет под камеру. В игре тут светила бы палочка игрока — но её
## конус смотрит туда же, куда камера, и атаку сбоку он не вытягивает.
## МОЛЬБЕРТ С ЛИСТОМ. Три ноги, перекладина и лист, на который натянут кадр
## полотна. Всё то же, что стоит в игре, — просто собранное здесь вручную:
## сборщики мира живут в world.gd и площадке недоступны.
func _easel(at: Vector3) -> void:
	var wood := StandardMaterial3D.new()
	var wt: Texture2D = load("res://tex/wood_color.jpg")
	if wt != null:
		wood.albedo_texture = wt
		wood.uv1_scale = Vector3(2.2, 2.2, 1.0)
	wood.albedo_color = Color(0.34, 0.28, 0.23)
	wood.roughness = 0.92
	var ноги: Array = [
		[Vector3(-0.34, 0.78, 0.10), Vector3(0.06, 1.55, 0.06), 8.0],
		[Vector3(0.34, 0.78, 0.10), Vector3(0.06, 1.55, 0.06), -8.0],
		[Vector3(0.0, 0.75, -0.32), Vector3(0.06, 1.5, 0.06), 0.0],
		[Vector3(0.0, 0.64, 0.08), Vector3(0.86, 0.07, 0.07), 0.0],
	]
	for нога in ноги:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = нога[1]
		mi.mesh = bm
		mi.material_override = wood
		mi.position = at + нога[0]
		mi.rotation_degrees = Vector3(0.0, 0.0, float(нога[2]))
		set_root.add_child(mi)
	# ЛИСТ. Тот же размер и тот же материал, что в игре: кадр в sRGB, свечение
	# по той же картинке, без освещения и с обеих сторон.
	board_face = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.90, 0.72)
	board_face.mesh = q
	set_root.add_child(board_face)
	var tex: Texture2D = board_vp.get_texture()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	# Кадр хранится в sRGB, а мир берёт альбедо как линейное: без этого чёрный
	# холст выходит светло-серым. На это я уже наступал в мире.
	m.albedo_texture_force_srgb = true
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	board_face.material_override = m
	# На уровне глаз камеры и лицом к ней: рисуют в упор и прямо.
	board_face.position = at + Vector3(0.0, 1.62, 0.04)
	board_face.rotation = Vector3.ZERO


func _key_light(at: Vector3, from: Vector3, energy: float) -> void:
	var l := SpotLight3D.new()
	l.light_color = Color(0.92, 0.94, 1.0)
	l.light_energy = energy
	l.spot_range = 22.0
	l.spot_angle = 40.0
	l.spot_angle_attenuation = 0.8
	l.spot_attenuation = 0.7
	l.shadow_enabled = true
	l.light_volumetric_fog_energy = 0.6
	l.position = from
	set_root.add_child(l)
	l.look_at(at, Vector3.UP)


## ─────────────────────────── акты ───────────────────────────

func _start(i: int) -> void:
	shot = clampi(i, 0, shots.size() - 1)
	t = float(shots[shot].get("от", 0.0))
	beat = -1
	playing = true
	_clear_set()
	cam.fov = 62.0
	caption.text = str(shots[shot]["cap"])
	_fired.clear()
	if thanks != null:
		thanks.modulate.a = 0.0
	hint.text = "%d/%d  %s   A — всё подряд, ПРОБЕЛ — дальше, R — повтор, H — без подписей" % [
		shot + 1, shots.size(), str(shots[shot]["name"])]
	flash.light_energy = 34.0
	fill.light_energy = 4.2
	fill_r.light_energy = 2.1
	# ЗВУК ПОД КАЖДЫЙ АКТ. Раньше на площадке звучали только отдельные удары —
	# фонового слоя не было вовсе, и ролик выходил тишиной с редкими шлепками.
	# Здесь тот же пласт, что в игре: дрон, тритон по безумию, воздух и
	# шкатулка. Ролик должен звучать так же, как игра, а не отдельно от неё.
	if board != null:
		board.visible = false
	if sfx != null:
		sfx.box_level(0.0)
		sfx.box_pitch(1.0)
		sfx.amb_madness(0.0)
		sfx.amb_level(0.45)
	match str(shots[shot]["name"]):
		"детская":
			_nursery()
			if sfx != null:
				# В детской ещё всё в порядке: тихий фон и мотив шкатулки.
				sfx.amb_level(0.12)
				sfx.box_level(0.55)
			flash.visible = false
			fill.visible = false
			fill_r.visible = false
		"фазы":
			_corridor(60.0, INF, 0)
			if sfx != null:
				sfx.amb_level(0.30)
			flash.visible = true
			fill.visible = true
			fill_r.visible = true
		"формы", "тварь":
			_corridor(34.0, INF, 2)
			if sfx != null:
				sfx.amb_level(0.55)
				sfx.amb_madness(0.6)
				# Мотив из детской, но ниже и медленнее: он пришёл оттуда.
				sfx.box_pitch(0.62)
				sfx.box_level(0.38)
			flash.visible = true
			fill.visible = true
			fill_r.visible = true
			monster.visible = true
			# В КОРИДОРЕ У НЕГО ДРУГАЯ ПОХОДКА. Площадка не знает про лабиринт,
			# и он по умолчанию считал, что вокруг зал: тогда все восемь рук
			# переступают по полу, ниже кадра, и в кадре остаётся голый шар.
			# Говорим прямо: тесно. Тогда две руки упираются в стены, три
			# тянутся вперёд — то, что игрок и видит в игре.
			monster.cramped = true
			monster.position = Vector3(0, 0, -11.0)
			monster.rotation.y = 0.0
		"атаки":
			# Вид 1: ниша ТОЛЬКО справа. Слева из стены лезет он сам, и дыра
			# рядом читалась бы как его нора — а он выходит из целого камня.
			_corridor(34.0, INF, 1)
			if sfx != null:
				sfx.amb_level(0.6)
				sfx.amb_madness(0.85)
				sfx.box_pitch(0.58)
				sfx.box_level(0.45)
			flash.visible = true
			fill.visible = true
			fill_r.visible = true
			monster.visible = true
			monster.cramped = true
			# Два источника: один на стену, из которой он лезет, второй на место,
			# куда придёт удар. Без них обе атаки — зелёные палки в темноте.
			_key_light(Vector3(-1.0, 1.6, -4.0), Vector3(2.6, 3.2, -1.0), 7.0)
			_key_light(Vector3(0.0, 1.4, -4.2), Vector3(-2.2, 3.4, -7.5), 5.0)
		"полотно":
			_corridor(20.0, INF, 1)
			flash.visible = true
			fill.visible = true
			fill_r.visible = true
			monster.visible = false
			# Мольберт с листом в 0.75 м перед камерой: столько и остаётся между
			# лицом и холстом, когда рисуешь.
			_easel(Vector3(0.0, 0.0, 2.25))
			board.visible = true
			# Настоящее полотно, не обучающее: с таймером и с дрожью. Тизер
			# должен показать не «как это устроено», а как это давит.
			# НОМЕР ПОЛОТНА — ВТОРОЙ, А НЕ ТРЕТИЙ. У третьего теперь помеха
			# «порядок скрыт»: лента показывает только следующий цвет, и в
			# кадре она выходит рядом тёмных квадратов. В игре это правильно,
			# а в ленте лента порядка — единственное, по чему зритель понимает
			# правило, и прятать её от него незачем.
			board.open(Shapes.POOL[3], 2, 0.35, 1, 4242)
			# ТЕМП КЛИКОВ СЧИТАЕМ ОТ ЧИСЛА ТОЧЕК, а не задаём числом. Раньше
			# стояло 0.42 с на точку при тринадцати точках — это пять с
			# половиной секунд, ровно до удара, и прожиг сдачи в кадр не
			# попадал ни разу. А это лучший кадр полотна: линия вспыхивает
			# насквозь и на секунду освещает коридор.
			_dot_t = 0.8
			_board_hit_done = false
			_step_t = 1.1
			_step_a = 0.0
			if sfx != null:
				sfx.amb_level(0.45)
				sfx.amb_madness(0.35)
				sfx.box_pitch(0.70)
				sfx.box_level(0.24)
		"нож":
			# Узкий коридор и никакого мольберта: тебя держат, и всё, что есть
			# в кадре, — это щупальца, лезвие и жижа.
			_corridor(16.0, INF, 1)
			flash.visible = true
			fill.visible = true
			fill_r.visible = true
			monster.visible = false
			if grab3d == null:
				grab3d = Grab3DScript.new()
				add_child(grab3d)
				grab3d.touched.connect(_on_stage_touched)
			# Пять щупалец: столько даёт злой хват в игре. Голова — сама камера.
			grab3d.build(cam, 5, 9731)
			grab3d.begin()
			grab3d.aim = Vector2.ZERO
			_slash_k = 1.0
			_slash_gap = 0.5
			if sfx != null:
				sfx.amb_level(0.55)
				sfx.amb_madness(0.7)
				sfx.box_pitch(0.60)
				sfx.box_level(0.30)
		"зрители", "добивание":
			# ВИД 1, А НЕ 3. Третий — самый тёмный набор ламп: 2.8 энергии через
			# девять метров вместо 4.6 через шесть. Тварь идёт к камере с девяти
			# метров, и в такой темноте её не видно, пока не подойдёт вплотную:
			# полторы секунды ленты — чёрный кадр с одной подписью, и зритель
			# читает это как зависшее видео. Проверено покадрово: с 33.25 по
			# 34.75 кадры побайтово одинаковые.
			_corridor(34.0, INF, 1)
			# И ЛУЧ НА ПОДХОД. Лампы стоят вдоль потолка и дальний конец не
			# достают; этот светит туда, откуда она приходит.
			_key_light(Vector3(0.0, 1.7, -7.0), Vector3(1.8, 3.4, -2.0), 6.0)
			flash.visible = true
			fill.visible = true
			fill_r.visible = true
			monster.visible = true
			# В добивании он НЕ зажат: руки должны развестись, это его кадр.
			monster.cramped = str(shots[shot]["name"]) == "зрители"
			monster.position = Vector3(0, 0, -7.5 if monster.cramped else -3.2)
			monster.rotation.y = 0.0
			monster.drop_hold()
			if str(shots[shot]["name"]) == "добивание":
				_build_fat_tents(monster.position)
			if sfx != null:
				sfx.amb_level(0.6)
				sfx.amb_madness(1.0)
				# Ниже всего: к добиванию от мотива остаётся почти поступь.
				sfx.box_pitch(0.52)
				sfx.box_level(0.50)
			voice.text = ""
			voice.modulate.a = 0.0
		"титр":
			if sfx != null:
				# Титр в тишине: после добивания это единственное, что нужно.
				sfx.amb_level(0.0)
				sfx.amb_madness(0.0)
			flash.visible = false
			fill.visible = false
			fill_r.visible = false


func _process(delta: float) -> void:
	if not playing:
		return
	t += delta
	var from_s: float = float(shots[shot].get("от", 0.0))
	var end_s: float = from_s + float(shots[shot]["len"])
	match str(shots[shot]["name"]):
		"детская":
			_act_nursery()
			# ПЕРЕХОД ГОТОВИТСЯ ЗАРАНЕЕ. На стыке актов комната обрывалась
			# разом: мотив вырубался на полуноте, а гул коридора начинался с
			# нуля. Теперь за последнюю пятую часть акта шкатулка уходит, а
			# фон лабиринта уже поднимается — звук следующей сцены приходит
			# раньше картинки, и склейки не слышно.
			if sfx != null:
				var kn: float = (t - from_s) / maxf(0.1, float(shots[shot]["len"]))
				var tail: float = clampf((kn - 0.78) / 0.22, 0.0, 1.0)
				sfx.box_level(0.55 * (1.0 - tail))
				sfx.amb_level(0.12 + tail * 0.20)
				sfx.amb_madness(tail * 0.25)
		"фазы":
			_act_phases()
			# Акт ПРО ТО, как портится мир, — пусть портится и звук: тритон
			# приходит вместе с камнем и туманом.
			if sfx != null:
				var kp: float = clampf((t - from_s) / float(shots[shot]["len"]), 0.0, 1.0)
				sfx.amb_madness(kp)
				sfx.amb_level(0.30 + kp * 0.35)
		"формы", "тварь":
			_act_forms(delta)
			if sfx != null and t - from_s > 2.0 and _once("shard"):
				# Обрывок мотива из детской. Ничего не объясняем.
				sfx.box_shard()
		"атаки":
			_act_attacks(delta)
		"полотно":
			_act_board(delta)
		"нож":
			_act_knife(delta)
		"зрители":
			_act_watch(delta)
		"добивание":
			_act_fatality(delta)
		"титр":
			cam.position = Vector3(0, 1.62, 0)
			cam.rotation = Vector3.ZERO
			# Наливается за секунду, начиная со второй: название уже прочли.
			thanks.modulate.a = clampf((t - from_s - 1.8) / 1.0, 0.0, 1.0)
	# Плавные концы: чёрное на первые полсекунды куска и последние.
	var a_in: float = clampf(1.0 - (t - from_s) / 0.5, 0.0, 1.0)
	var a_out: float = clampf((t - (end_s - 0.6)) / 0.6, 0.0, 1.0)
	fade.color.a = maxf(fade.color.a * 0.5, maxf(a_in, a_out))
	if t >= end_s:
		playing = false
		if auto_all:
			if shot < shots.size() - 1:
				_start(shot + 1)
			else:
				auto_all = false
				if OS.get_cmdline_user_args().has("запись"):
					get_tree().quit()


## АКТ 1. Взгляд в дверь на зимнюю улицу, круг по детской — и вниз, в пролом.
##
## УЛИЦА ДОБАВЛЕНА, И ЭТО НЕ УКРАШЕНИЕ. Акт строит НАСТОЯЩУЮ детскую из игры, а
## у неё за дверью теперь коридор с часами и картинами, а дальше зимняя улица со
## снегом, фонарями и домами. Всё это уже было в кадре — просто камера туда не
## смотрела: круг начинался сразу с кровати.
##
## Четыре секунды в начале: пятимся от двери вглубь комнаты, глядя наружу.
## Зритель успевает увидеть, ОТКУДА пришёл человек, и только потом — куда попал.
func _act_nursery() -> void:
	var door: float = 4.2
	if t < door:
		var k0: float = t / door
		var e0: float = k0 * k0 * (3.0 - 2.0 * k0)
		cam.position = Vector3(0.0, 1.62, lerpf(2.0, -0.2, e0))
		cam.look_at(Vector3(0.0, 1.5, 9.5), Vector3.UP)
		return
	var orbit: float = 10.5 + door
	if t < orbit:
		# Медленный оборот вокруг середины комнаты: кровать с силуэтом, стол,
		# окно, лианы по стенам проходят через кадр сами.
		var tt: float = t - door
		var a: float = -1.9 + tt * 0.52
		var r: float = 2.35 - tt * 0.055
		cam.position = Vector3(sin(a) * r, 1.62 - tt * 0.02, 0.35 + cos(a) * r)
		var look := Vector3(1.05, 0.72, -0.55)      # кровать с девочкой
		if tt > 5.2:
			# Ко второй половине круга переводим взгляд на пролом.
			var s2: float = clampf((tt - 5.2) / 3.6, 0.0, 1.0)
			look = look.lerp(Vector3(0.0, 0.05, 0.4), s2 * s2 * (3.0 - 2.0 * s2))
		cam.look_at(look, Vector3.UP)
	else:
		# И вниз: разгон, крен, темнота.
		var k: float = clampf((t - orbit) / 3.8, 0.0, 1.0)
		var e: float = k * k
		cam.position = Vector3(0, lerpf(1.62, -6.0, e), 0.4)
		cam.rotation = Vector3(lerpf(-0.35, -1.35, k), k * 0.6, k * 0.35)


## АКТ 2. Полёт по коридору: каждые пять секунд мир портится на ступень.
func _act_phases() -> void:
	cam.position = Vector3(sin(t * 1.3) * 0.05, 1.62 + sin(t * 2.6) * 0.02,
		26.0 - t * 3.4)
	cam.rotation = Vector3(0, 0, sin(t * 1.3) * 0.012)
	# БЫСТРЕЕ. По пять секунд на ступень — это половина ролика на один проезд;
	# смена фаз должна успевать три раза, пока зритель ещё смотрит.
	var want: int = 0
	if t > 6.6:
		want = 2
	elif t > 3.3:
		want = 1
	if want != beat:
		# ПЕРВАЯ ФАЗА — НЕ СМЕНА, А ИСХОДНОЕ СОСТОЯНИЕ. beat стартует с -1,
		# и на первом же кадре акта срабатывал скрежет — ровно на склейке с
		# детской. Из-за него переход и звучал обрывом: комната кончалась, и
		# тут же бил удар. Звук теперь только на настоящих сменах.
		var was: int = beat
		beat = want
		_phase_look(beat)
		var ph_ru: Array = ["первая фаза: его нет, он только слышен",
			"вторая: он уже в камне рядом", "третья: он снаружи"]
		var ph_en: Array = ["phase one: there is no body, only sound",
			"phase two: it is in the stone beside you", "phase three: it is outside"]
		_act_cap(str(ph_ru[beat]), str(ph_en[beat]))
		if sfx != null and was >= 0:
			sfx.play("scrape", -4.0 + float(beat) * 2.0)


## АКТ: ПОЛОТНО. Ведём его сами — соединяем точки по порядку, как это делал бы
## игрок, только без промахов. Камера при этом стоит в коридоре: видно, что
## рисуют не в меню, а посреди лабиринта, пока сзади что-то происходит.
## АКТ: ПОЛОТНО. Главная механика игры, и в ленте она шла НЕМОЙ: точки
## соединялись сами, беззвучно, камера стояла как штатив. Со стороны — экранная
## заставка, а не то, чем в игре занимаются под таймером с тварью за спиной.
##
## Три добавки, и все взяты из игры, а не придуманы для ролика:
##   ЗВУК ТОЧКИ — каждое соединение щёлкает, как под пальцем игрока;
##   ДЫХАНИЕ    — кадр не стоит, а мелко дышит: полотно рисуют руками;
##   УДАР       — на исходе полотна фон замолкает, и приходит атака. Коротко:
##                полсекунды тишины, удар, крик, темнота — и акт кончается на
##                этом. Длиннее нельзя, иначе это уже сцена, а не механика.
const BOARD_HIT := 5.6      ## когда бьёт, от начала акта


## Шаги вокруг рисующего: та же поступь, что в игре, и тот же толчок в руку.
var _step_t: float = 0.0
var _step_a: float = 0.0


func _act_board(delta: float) -> void:
	var k: float = t
	# ОН ХОДИТ ВОКРУГ, ПОКА ТЫ РИСУЕШЬ. Это и есть то, ради чего в игре у
	# полотна вообще появился слух: тварь не замирает, она кружит в семи метрах,
	# и слышно, с какой стороны. В кадре её не видно — её и не должно быть
	# видно, — но шаг идёт из точки, панорама его разводит, а близкий шаг
	# дёргает руку и портит линию. Точка ходит по кругу вокруг камеры.
	_step_t -= delta
	if _step_t <= 0.0 and k < BOARD_HIT:
		_step_t = 0.92
		_step_a += 0.9
		var at: Vector3 = cam.global_position + Vector3(
			sin(_step_a) * 6.5, -1.4, cos(_step_a) * 6.5)
		if sfx != null:
			sfx.stomp(at, 0.0)
		# Ближе всего он проходит за спиной: там и дёргает.
		var близко: float = clampf(cos(_step_a) * 0.5 + 0.5, 0.0, 1.0)
		if board != null:
			board.step_jolt(близко * 0.7)
	# ДЫШИТ. Полотно держат в руках, а не прибивают к стене.
	# 0.88 м до листа, а не 0.75: в упор лист вылезал за края кадра, и рамка
	# полотна обрезалась. Столько и стоят у мольберта, когда на него смотрят.
	cam.position = Vector3(sin(k * 1.7) * 0.012, 1.62 + sin(k * 2.3) * 0.010, 3.13)
	cam.rotation = Vector3(0.0, 0.0, sin(k * 1.1) * 0.006)
	if board == null or not board.visible:
		return
	if k > BOARD_HIT:
		_board_hit(k - BOARD_HIT)
		return
	if k > BOARD_HIT - 0.55 and sfx != null and _once("duck"):
		# Тишина за полсекунды до удара — тот же приём, что в акте зрителей.
		sfx.amb_duck(1.4)
	_dot_t -= delta
	if _dot_t > 0.0:
		return
	# Всё полотно надо успеть за время ДО удара, минус секунда на прожиг.
	_dot_t = maxf(0.16, (BOARD_HIT - 1.5) / float(maxi(1, board.n)))
	for d in board.dots:
		if not bool(d["done"]) and int(d["idx"]) == board.next_idx:
			board._click(board._dot_pos(d))
			# Щелчок точки. В игре его даёт мир по сигналу полотна, а на
			# площадке мира нет — зовём тот же банк напрямую.
			if sfx != null:
				sfx.play("ok", 1.2)
			return


## Удар по рисующему. Всё внутри секунды: кадр вздрагивает, чернеет и акт
## заканчивается — как обрыв, а не как сцена.
func _board_hit(d: float) -> void:
	if not _board_hit_done:
		_board_hit_done = true
		if sfx != null:
			# Те же уровни, что в акте зрителей: whip и hit_mid широкополосные,
			# на +8 и +5 они били помехами, а не ударом.
			sfx.play("whip", 1.0)
			sfx.play("hit_mid", 0.0)
			sfx.play("scream", 4.0)
	cam.rotation.z = sin(d * 38.0) * 0.20 * maxf(0.0, 1.0 - d * 1.8)
	cam.rotation.x = sin(d * 29.0) * 0.13 * maxf(0.0, 1.0 - d * 1.8)
	if d < 0.34:
		fade.color.a = maxf(fade.color.a, 1.0 - d / 0.34)


## АКТ: НОЖ. Самое залипательное, что у игры есть, и в ленте его не было вовсе.
##
## Щупальца обвивают лицо, палочка становится лезвием, и каждое надо перепилить
## в три взмаха; из срезов бьёт жижа, капли садятся на объектив. Всё это —
## тот же Grab3D, что работает в игре: ни одного отдельного «киношного»
## щупальца здесь нет, и потребовать показанное вживую можно.
##
## Взмахи ведём САМИ, а не через bot_slash: тот ставит нож в две позы за один
## кадр и режет — для стенда это верно (мерится попадание), а для ленты это
## значит, что взмаха не видно. Здесь нож едет поперёк щупальца за четверть
## секунды, и попадание случается само, той же проверкой, что у игрока.
func _act_knife(delta: float) -> void:
	if grab3d == null:
		return
	# Камера дышит и слегка ведёт: тебя держат, ты не на штативе.
	cam.position = Vector3(sin(t * 2.1) * 0.02, 1.62 + sin(t * 2.7) * 0.016, 0.0)
	cam.rotation = Vector3(sin(t * 1.3) * 0.012, sin(t * 0.9) * 0.02,
		sin(t * 1.7) * 0.016)
	# Хватка крепнет: свет от лезвия разгорается, щупальца тянут ближе.
	var grip: float = clampf(0.45 + t * 0.075, 0.0, 1.0)
	grab3d.tick(delta, grip)
	if _slash_k < 1.0:
		_slash_k = minf(1.0, _slash_k + delta / 0.24)
		# Замедление к концу: рука доводит взмах, а не обрывает его.
		var e: float = 1.0 - pow(1.0 - _slash_k, 2.2)
		grab3d.aim = _slash_from.lerp(_slash_to, e)
		grab3d.try_cut(delta)
		return
	_slash_gap -= delta
	if _slash_gap > 0.0:
		return
	if not _aim_slash():
		return
	_slash_gap = 0.34


## Навести следующий взмах поперёк ближайшего целого щупальца. Возвращает false,
## если резать больше нечего.
func _aim_slash() -> bool:
	for a in grab3d.arms:
		if bool(a["cut"]) or not a.has("pts") or not a.has("mark_seg"):
			continue
		var pts: Array = a["pts"]
		var k: int = int(a["mark_seg"])
		var mid: Vector3 = (pts[k] + pts[k + 1]) * 0.5
		var goal: Vector2 = grab3d._aim_for(mid)
		var along: Vector2 = grab3d._aim_for(pts[k + 1]) - grab3d._aim_for(pts[k])
		var cross := Vector2(-along.y, along.x)
		if cross.length() < 0.001:
			cross = Vector2(1.0, 0.0)
		cross = cross.normalized() * 0.5
		_slash_from = (goal - cross).clamp(Vector2(-1, -1), Vector2(1, 1))
		_slash_to = (goal + cross).clamp(Vector2(-1, -1), Vector2(1, 1))
		grab3d.aim = _slash_from
		_slash_k = 0.0
		return true
	return false


## Звук порезов на площадке. В игре его даёт мир по сигналу — здесь мира нет.
func _on_stage_touched(_arm: int, killed: bool) -> void:
	if sfx == null:
		return
	if killed:
		sfx.play("sever", -1.0, 0.10)
		sfx.play("whip", -8.0, 0.16)
	else:
		sfx.play("slice", -5.0, 0.18)


## АКТ: ЗРИТЕЛИ. Самая наглая фраза набора и удар щупальцем прямо в объектив.
## Удар нарочно НЕ атака: он ничего не отнимает, оно просто бьёт в камеру и
## уходит. Для ленты это лучший кадр, какой у игры есть.
func _act_watch(delta: float) -> void:
	_walls_here()
	var k: float = t - float(shots[shot].get("от", 0.0))
	monster.gait = fmod(monster.gait + delta * 0.55, 1.0)
	monster.aim_at = cam.global_position
	monster._shiver(delta, true)
	# Идём вперёд, он идёт навстречу.
	cam.position = Vector3(0, 1.62, 2.0 - k * 0.55)
	cam.rotation = Vector3.ZERO
	monster.position.z = -7.5 + k * 0.75
	if k > 2.2:
		voice.text = Lang.t("v_watch")
		voice.modulate.a = clampf((k - 2.2) / 0.8, 0.0, 1.0)
	if k > 3.9 and sfx != null and _once("duck"):
		# ТИШИНА ПЕРЕД УДАРОМ, как в игре: фон уходит за секунду до.
		sfx.amb_duck(1.6)
	if k > 4.6 and _once("strike"):
		monster.strike_at(cam.global_position, 3.0)
		if sfx != null:
			# УДАР, А НЕ ПОМЕХИ. Оба этих звука широкополосные по построению:
			# whip — вспышка белого шума, hit_mid — запись с верхом ярче крика.
			# На +8 и +4 они вместе давали в акте −33 дБ в самом верху, громче
			# всех остальных актов, и слышались как включённый ливень.
			sfx.play("whip", 1.0)
			sfx.play("hit_mid", 0.0)
			# ГОЛОС. В игре он есть на каждой поимке, а в ленте его не было ни
			# разу: било молча, и удар читался как помеха в записи, а не как
			# «попало по мне».
			sfx.play("scream", 5.0)
	if k > 4.7:
		# УДАР. Кадр вздрагивает и на треть секунды уходит в чёрное — ровно так
		# это выглядит в игре.
		var d: float = k - 4.7
		cam.rotation.z = sin(d * 34.0) * 0.16 * maxf(0.0, 1.0 - d * 1.6)
		cam.rotation.x = sin(d * 27.0) * 0.10 * maxf(0.0, 1.0 - d * 1.6)
		if d < 0.30:
			fade.color.a = maxf(fade.color.a, 1.0 - d / 0.30)
		voice.modulate.a = maxf(0.0, voice.modulate.a - delta * 2.0)
	if k > 6.6:
		voice.modulate.a = maxf(0.0, voice.modulate.a - delta * 2.0)


## АКТ: ДОБИВАНИЕ. Те же четыре стадии, что в игре, и снятые оттуда же —
## глазами того, кого поднимают. Крови нет: рвётся сам кадр.
func _act_fatality(delta: float) -> void:
	_walls_here()
	var k: float = t - float(shots[shot].get("от", 0.0))
	monster.gait = fmod(monster.gait + delta * 0.35, 1.0)
	monster.aim_at = cam.global_position
	monster._shiver(delta, true)
	# ВЫШЕ ЕГО МАКУШКИ И ЧУТЬ ВПЕРЁД. Ком под четыре метра ростом: на 3.35 м
	# камера оказывалась ВНУТРИ его головы, и кадр превращался в зелёную стену.
	# Потолок здесь 4.3 — выше не поднять, поэтому смотрим на него сверху сбоку.
	var top: Vector3 = monster.global_position + Vector3(0.0, 3.95, 1.35)
	if k > 0.05 and sfx != null and _once("duck"):
		# Всё добивание идёт в тишине: там должно быть слышно только его.
		sfx.amb_duck(6.6)
		sfx.play("hit_low", 3.0)
	# КРИК — НА ПОДЪЁМЕ, А НЕ НА СКЛЕЙКЕ. Я ставил его на первые кадры акта, но
	# акт начинается с того, что игрока УЖЕ держат: сам захват случился до
	# склейки, и зритель его не видел. Крик выходил раньше причины. Теперь он
	# ровно там, где щупальца лезут из стен и тянут вверх, — на видимом поводе.
	if k > 1.25 and sfx != null and _once("scream"):
		sfx.play("scream", 7.0)
	if k < 1.2:
		# Схватило: держит внизу, кадр кренится к нему.
		var a: float = k / 1.2
		cam.position = Vector3(0.0, 1.62, 0.9)
		cam.rotation = Vector3(-a * 0.25, 0.0, a * 0.5)
	elif k < 3.4:
		# ПОДНИМАЮТ ЩУПАЛЬЦА, а не воздух. Вылезают из обеих стен за полсекунды
		# до того, как кадр пойдёт вверх, и держатся, пока он наверху.
		_fat_tents_grow(clampf((k - 1.2) / 0.7, 0.0, 1.0))
		# Поднимает над собой.
		# СНАЧАЛА ВВЕРХ, ПОТОМ НАД НЕЙ. Прямая между «перед ней» и «над ней»
		# проходит СКВОЗЬ тушу: на записи в этот момент кадр превращался в
		# мутное пятно — камера ехала внутри мантии. Высота набирается быстрее,
		# заход поверху с задержкой.
		var b: float = (k - 1.2) / 2.2
		var e: float = b * b * (3.0 - 2.0 * b)
		var bz: float = clampf((b - 0.38) / 0.62, 0.0, 1.0)
		var ez: float = bz * bz * (3.0 - 2.0 * bz)
		cam.position = Vector3(0.0, lerpf(1.62, top.y, e), lerpf(0.9, top.z, ez))
		cam.rotation = Vector3(lerpf(-0.25, -0.95, e), 0.0, lerpf(0.5, 0.12, e))
	elif k < 6.2:
		_fat_tents_grow(1.0)
		# Держит. Щупальца сходятся, кадр медленно поворачивается, оно говорит.
		var c: float = (k - 3.4) / 2.8
		cam.position = top + Vector3(0.0, sin(c * PI) * 0.16, 0.0)
		cam.rotation = Vector3(-0.95 + sin(c * PI) * 0.10, 0.0, 0.12 + c * 0.32)
		if k > 3.9:
			voice.text = Lang.t("v_f5")
			voice.modulate.a = clampf((k - 3.9) / 0.7, 0.0, 1.0)
		if k > 5.8 and _once("hold"):
			monster.grab_hold(1.2)
	else:
		# РАЗРЫВ. Два коротких рывка и обрыв в темноту НА СЕРЕДИНЕ движения.
		var d2: float = k - 6.2
		# На разрыве они уходят обратно в камень: держать больше нечего.
		_fat_tents_grow(maxf(0.0, 1.0 - d2 * 1.6))
		cam.position = top
		cam.rotation.z = 0.44 + sin(d2 * 26.0) * 0.55
		cam.rotation.x = -0.95 + d2 * 0.8
		voice.modulate.a = maxf(0.0, voice.modulate.a - delta * 3.0)
		if d2 > 0.22:
			fade.color.a = 1.0
		# РАЗРЫВ — ОДИН. Окно в десятую долю секунды пропускало шесть кадров, и
		# на разрыве шло шесть ударов и шесть человеческих хрипов подряд.
		if k > 6.3 and sfx != null and _once("tear"):
			sfx.play("hit_low", 7.0)
			sfx.play("strain", 6.0)


## АКТ 3. Обе формы по очереди, каждая идёт на камеру.
## Стены для коридорной походки. В игре монстр берёт их из лабиринта, а на
## площадке лабиринта нет — и с manual_space он их вовсе не считает: точки
## упора оставались нулевыми, руки «упирались» в начало координат где-то в
## другом конце сцены. Именно поэтому на всех кадрах он был шаром без ног:
## коридорная походка тут просто не работала.
## Ближе этого монстр к камере не подходит НИ В ОДНОМ акте: за этой чертой
## объектив входит внутрь туши и срезает её изнутри.
const NEAR_KEEP := 2.3
## Ниша, из-за которой он выходит фигурой. Совпадает с левым разрывом стены у
## коридора вида 2: -34.0 * 0.30.
const CORNER_X := 2.2
const CORNER_Z := -10.2


## Подпись на языке ленты. Держим парой прямо в коде, а не в общем словаре:
## это текст ролика, он живёт и меняется вместе с монтажом, а не с игрой.
## СОБЫТИЕ ОДИН РАЗ ЗА АКТ. Условия вида «k больше 4.6 и меньше 4.7» выглядят
## как момент, а на деле это ОКНО: при 60 кадрах в секунду внутрь него попадает
## шесть кадров, и всё, что там стоит, срабатывает шестью подряд. В логе это
## видно прямо: шесть whip, шесть hit_mid, шесть scream на один удар щупальцем.
## На слух — очередь человеческих вскриков там, где задуман один.
func _once(key: String) -> bool:
	if _fired.has(key):
		return false
	_fired[key] = true
	return true


func _cap(ru: String, en: String) -> String:
	return en if Settings.lang == "en" else ru


## Подпись, заданную АКТОМ. Ставится только если у куска нет своей: в полной
## ленте у «форм» и «атак» подпись пустая, и её пишет акт, а в магазинной у них
## есть своя — и раньше акт её перетирал. В кадре это выглядело как разнобой:
## часть строк прописными от ленты, часть строчными от актов.
func _act_cap(ru: String, en: String) -> void:
	if str(shots[shot].get("cap", "")) != "":
		return
	caption.text = _cap(ru, en)


func _walls_here() -> void:
	monster.side_dir = Vector3.RIGHT
	var z: float = monster.global_position.z
	var half: float = CELL * 0.5 - 0.10
	monster.wall_a = Vector3(half, 0.0, z)
	monster.wall_b = Vector3(-half, 0.0, z)


func _act_forms(delta: float) -> void:
	_walls_here()
	monster.gait = fmod(monster.gait + delta * 0.5, 1.0)
	monster.aim_at = cam.global_position
	monster._shiver(delta, true)
	# ВБЛИЗИ ПРИТУШИВАЕМ. Оба луча упираются в тушу, и на снятом кадре середина
	# его тела выгорала в белое пятно — та же беда, что была в игре при хвате.
	var dm: float = cam.global_position.distance_to(monster.global_position)
	var near_k: float = clampf((dm - 1.6) / 3.2, 0.22, 1.0)
	flash.light_energy = 34.0 * near_k
	mon_beam.light_energy = 7.0 * near_k
	fill.light_energy = 4.2 * clampf(near_k * 1.2, 0.18, 1.0)
	fill_r.light_energy = 2.1 * clampf(near_k * 1.2, 0.18, 1.0)
	# И САМА ТУША. У неё свой шейдер с параметром «освещённость», и по
	# умолчанию он выкручен: белое пятно в середине тела шло не от ламп, а
	# отсюда — гасили свет втроём, а пятно оставалось.
	monster.set_lit(lerpf(0.35, 1.0, near_k))
	if t < 9.5:
		# Осьминог: идёт по коридору, упираясь в стены, камера пятится медленнее.
		if beat != 0:
			beat = 0
			_act_cap("оно ходит сквозь камень", "it walks through stone")
		# НЕ ДАЁМ ЕМУ ВОЙТИ В ОБЪЕКТИВ. Он шёл быстрее, чем камера пятилась, и к
		# концу подхода между ними оставалось 1.3 м — меньше половины его туши.
		# Камера оказывалась ВНУТРИ меша, ближняя плоскость срезала его изнутри,
		# и вместо твари в кадре был полупрозрачный обломок. Держим полтора
		# корпуса: он подходит вплотную, но остаётся телом.
		cam.position = Vector3(0, 1.62, -4.5 + t * 0.8)
		monster.position.z = minf(-11.0 + t * 1.35, cam.position.z - NEAR_KEEP)
		cam.look_at(monster.global_position + Vector3(0, 1.5, 0), Vector3.UP)
	elif t < 10.6:
		# Чёрная пауза между формами: это склейка, а не превращение на глазах.
		fade.color.a = maxf(fade.color.a, clampf(1.0 - absf(t - 10.05) / 0.55, 0.0, 1.0))
		if beat != 1:
			beat = 1
			monster.take_form(90.0, monster.FORM_HUMAN)
			# ЗА УГОЛ. Он уходит в боковую нишу и выйдет ОТТУДА уже другим.
			# Раньше склейка просто подменяла тварь на фигуру в том же месте, и
			# смене формы неоткуда было взяться: моргнули — стало другое. Теперь
			# у неё есть причина: он был вне кадра, за поворотом.
			monster.position = Vector3(-CORNER_X, 0, CORNER_Z)
			monster.rotation.y = -PI * 0.5
	else:
		# Фигура: выходит из-за угла и только потом идёт на камеру.
		if beat != 2:
			beat = 2
			_act_cap("и не всегда остаётся собой", "and it is not always itself")
		var t2: float = t - 10.6
		var s2: float = clampf(t2 / 1.9, 0.0, 1.0)
		var e2: float = s2 * s2 * (3.0 - 2.0 * s2)
		# Сначала вбок в проход, доворачиваясь к камере, и лишь потом вперёд.
		monster.position.x = lerpf(-CORNER_X, 0.0, e2)
		monster.position.z = CORNER_Z + maxf(0.0, t2 - 1.9) * 0.95
		monster.rotation.y = lerpf(-PI * 0.5, 0.0, e2)
		cam.position = Vector3(0, 1.62, CORNER_Z + 7.2 + maxf(0.0, t2 - 1.9) * 0.5)
		cam.look_at(monster.global_position + Vector3(0, 1.85, 0), Vector3.UP)


## АКТ 4. По одной атаке от каждой формы. Камера стоит СБОКУ и видит удар
## целиком: спиной к атаке ролик не снимают — иначе «что-то мелькнуло».
func _act_attacks(delta: float) -> void:
	_walls_here()
	monster.aim_at = cam.global_position
	mon_beam.light_energy = 12.0
	var mark := Vector3(0, 0, -4.0)          # место, где «стоит игрок»
	if t < 9.0:
		# ЗАСАДА ИЗ СТЕНЫ. Он выходит из левой стены наполовину и бьёт щупальцем
		# поперёк коридора. Камера с другого конца и чуть правее: в кадре и
		# стена, из которой он лезет, и то место, куда прилетает.
		if beat != 0:
			beat = 0
			_act_cap("из стены", "from the wall")
			monster.form_hold = 0.0
			monster.form_t = 0.0
			monster.position = Vector3(-(CELL * 0.5 + 0.75), 0, -4.0)
		var out: float = clampf((t - 1.6) / 2.0, 0.0, 1.0)
		monster.position.x = lerpf(-(CELL * 0.5 + 0.75), -(CELL * 0.5 - 0.30),
			out * out * (3.0 - 2.0 * out))
		# ЛИЦОМ ПОПЕРЁК КОРИДОРА. Глаза — самое читаемое, что у него есть, и
		# камера должна видеть их, а не затылок: разворачиваем его туда же, куда
		# он бьёт.
		monster.look_at(Vector3(2.0, monster.global_position.y, -4.0), Vector3.UP)
		monster.push_at = monster.global_position - Vector3(0.7, 0, 0)
		monster.push_n = Vector3(1, 0, 0)
		monster.gait = fmod(monster.gait + delta * 0.5, 1.0)
		monster._shiver(delta, true)
		if beat == 0 and t > 3.8 and monster.reach_t <= 0.0:
			monster.strike_at(mark + Vector3(0.2, 1.5, 0), 5.0)
			if sfx != null:
				sfx.play_at("whip", monster.global_position, -1.0)
				sfx.play("hit_low", 2.0)
		if t > 3.8:
			# Щупальце идёт через коридор в стену напротив — то самое движение,
			# которым в игре тебя и впечатывает.
			var s: float = clampf((t - 3.8) / 1.3, 0.0, 1.0)
			monster._aim_reach(mark + Vector3(lerpf(0.1, 1.30, s), 1.5, 0))
		# Отходим: туша под три метра, вблизи она занимает весь кадр и удара не
		# видно вовсе. Пять метров и угол пошире — в кадре и он, и стена, и
		# щупальце, которое идёт поперёк.
		cam.fov = 72.0
		cam.position = Vector3(1.62, 1.95, 0.75)
		cam.look_at(Vector3(-0.55, 1.55, -4.0), Vector3.UP)
	else:
		# РУКИ С ПОТОЛКА. Фигура тянет руки вверх, и с потолка над меткой
		# опускаются такие же. Камера сбоку и снизу: видно и её жест, и то, что
		# приходит сверху.
		if beat != 1:
			beat = 1
			_act_cap("и сверху", "and from above")
			monster.reach_t = 0.0
			monster.take_form(90.0, monster.FORM_HUMAN)
			monster.position = Vector3(0, 0, -8.2)
			monster.rotation.y = 0.0
			monster.ceiling_grab(mark, WALL_H)
		var t2: float = t - 9.0
		monster.arms_up = clampf((t2 - 1.6) * 1.3, 0.0, 1.0)
		# ПОДОШЁЛ — ВСТАЛ — ПОТЯНУЛСЯ. Раньше он тянул руки на ходу, и жест
		# терялся в шаге: замах должен быть остановкой, иначе это не замах.
		monster.position.z = -8.2 + minf(t2, 1.6) * 0.75
		if monster.arms_up <= 0.02:
			monster.gait = fmod(monster.gait + delta * 0.4, 1.0)
		monster._shiver(delta, true)
		cam.fov = 68.0
		cam.position = Vector3(1.35, 1.05, -0.9)
		cam.look_at(mark + Vector3(0, 2.2, 0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var k: int = (event as InputEventKey).keycode
	if k == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://world.tscn")
	elif k == KEY_SPACE:
		auto_all = false
		_start(shot + 1 if shot < shots.size() - 1 else 0)
	elif k == KEY_R:
		_start(shot)
	elif k == KEY_A:
		auto_all = true
		_start(0)
	elif k == KEY_H:
		caption.visible = not caption.visible
		hint.visible = caption.visible
	elif k == KEY_F11:
		var m: int = DisplayServer.window_get_mode()
		if m == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Снять по несколько кадров из каждого акта и выйти — так я смотрю композицию,
## не записывая видео.
func _shots_pass() -> void:
	caption.visible = false
	hint.visible = false
	for i in shots.size():
		_start(i)
		var from_s: float = float(shots[i].get("от", 0.0))
		var len_s: float = float(shots[i]["len"])
		for frac in [0.15, 0.35, 0.55, 0.75, 0.95]:
			var want: float = from_s + len_s * frac
			while t < want:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://кадр_%d_%s_%d.png" % [i + 1, str(shots[i]["name"]),
				int(frac * 100.0)])
	print("[площадка] снято ", shots.size() * 5, " кадров")
	get_tree().quit()
