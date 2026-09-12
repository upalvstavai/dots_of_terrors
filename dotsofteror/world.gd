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
const Lang := preload("res://Lang.gd")
const Notes := preload("res://Notes.gd")
const NoteUIScript := preload("res://NoteUI.gd")
const MonsterScript := preload("res://Monster.gd")
const SfxScript := preload("res://Sfx.gd")
const WALL_SHADER := preload("res://wall.gdshader")
const POUR_SHADER := preload("res://pour.gdshader")
const EYES_SHADER := preload("res://eyes.gdshader")
const TENT_SHADER := preload("res://tentacle.gdshader")
const SPLASH_SHADER := preload("res://splash.gdshader")
const FLOOR_SHADER := preload("res://floor.gdshader")
const GOO_SHADER := preload("res://goo.gdshader")
const THREAD_SHADER := preload("res://thread.gdshader")
const GrabScript := preload("res://Grab.gd")
const RoomScript := preload("res://Room.gd")
const ScareScript := preload("res://Scare.gd")
const StartScript := preload("res://StartUI.gd")
const VoiceScript := preload("res://VoiceUI.gd")
const SaysScript := preload("res://Says.gd")
const CreditsScript := preload("res://CreditsUI.gd")
const DeathScript := preload("res://DeathUI.gd")
const PauseScript := preload("res://PauseUI.gd")
const Settings := preload("res://Settings.gd")

## СКРИМЕРЫ. Скример — событие, а не реакция на поимку: если бить каждый раз,
## к третьему это раздражение, а не страх. Право копится и тратится редко.
const SCARE_CHANCE := {"monster": 0.6, "lash": 0.2}
const SCARE_MIN_GAP := 25.0    ## жёсткий пол между ЛЮБЫМИ двумя скримерами
const MON_COOL := 45.0         ## «монстр пугает всегда» верно ровно один раз
## ДВЕ, А НЕ ТРИ. Три поимки — это две бесплатные: первая ничего не стоит, и
## угроза успевает стать привычкой раньше, чем станет страшно. С двумя первая же
## поимка означает «следующая последняя», и монстр перестаёт быть помехой.
const DEATH_LIMIT := 2
const PHASE_BAR_H := 9.0        ## высота полоски фаз

## ЩУПАЛЬЦА ИЗ ЛЮБОЙ СТЕНЫ. Пугает не сила удара, а неожиданность, а к частому
## неожиданности не бывает: игрок привыкал к ним за один забег.
const LASH_FIRST := [30.0, 50.0]
const LASH_REPEAT := [150.0, 260.0]
const LASH_MISS := 0.5
const TELL := 0.85             ## сколько стена «дышит» перед ударом
const TELL_LOOK := 0.35        ## косинус: ±70°. Спасает ВЗГЛЯД, а не бегство

## ПОДСКАЗКИ СОЗДАТЕЛЯ. Выключены по умолчанию и переключаются клавишами прямо
## в игре: если держать их константой в коде, однажды отдашь сборку с включённой
## линией к выходу — и человек пройдёт лабиринт по ней, то есть не сыграет вовсе.
##   G — нить к текущей цели (полотно, а после шести — выход)
##   M — линия к монстру (появится, когда монстр будет перенесён)

## 2.8, а не 2.4. Стол в полтора метра оставлял в клетке 12 см запаса — в такой
## коридор он влезал только чудом. Больше поднимать нельзя: площадь пола и
## потолка растёт квадратом, а с ней и число треугольников.
@export var cell_size: float = 2.8
## Потолок должен быть НАД головой, а не на ней. При 2.9 он приходился в метре
## с небольшим от глаз, и коридор читался как щель без верха.
@export var wall_height: float = 4.3
## Сколько дыр в потолке: сквозь них бьёт солнце и льётся та же масса.
@export var holes_want: int = 3
# СРЕЗ ИДЁТ НА ОДНОЙ КАРТЕ. Генерация никуда не делась — она включается одним
# флагом, — но показывать и обкатывать надо то, что у всех одинаковое: иначе
# один человек проходит удобный лабиринт, другой получает шестьдесят клеток
# пустого коридора между полотнами, и сравнивать их впечатления нельзя.
@export var regenerate_seed: bool = false  ## true — новый лабиринт на каждый запуск
# Сид выбран перебором: у него ровный путь (157 клеток на восемь перегонов,
# самый длинный 34), первое полотно в пяти клетках от старта, обвал лежит
# ровно на дороге между четвёртым и пятым полотном, три убежища и три пролома.
@export var fixed_seed: int = 909         ## если regenerate_seed выключен

@export_group("Освещение")
## Игра задумана в полной темноте: свет даёт только палочка. Но собирать мир вслепую
## невозможно, поэтому пока оставлен слабый общий свет. Ставь 0.0, когда дойдёшь
## до фонарика.
## Лабиринт ТЁМНЫЙ. Общий свет — минимум, только чтобы стены угадывались
## силуэтом. Всё остальное даёт палочка, и пока ты её не взял, идёшь на ощупь.
@export var ambient: float = 0.14
@export var fog: float = 0.055
## Свет палочки. Поднят с 1.4: стены стали чёрной массой, их отражение упало
## с 0.36 до 0.055 — почти в семь раз. Прежней яркости хватало на серый камень,
## а на чёрном она не показывала ничего, и казалось, что фонарь сломан.
@export var player_light: float = 25.0

var maze
var start_cell: Vector2i
var exit_cell: Vector2i
var canv_cells: Array[Vector2i] = []
var canv_marks: Array[MeshInstance3D] = []
var canv_fails: Array[int] = []   ## сколько раз провалено каждое полотно
const CANV_FLEE := 2              ## после стольких провалов полотно уходит
var exit_mark: MeshInstance3D
var room_cells: Array[Vector2i] = []
var room_rects: Array = []      ## прямоугольники тех же залов, для расстановки столов
var shapes: Array = []

var done: int = 0          ## сдано полотен
## ЧТО ПЕРЕЖИВАЕТ СМЕРТЬ. Статическое: сцена грузится заново, скрипт остаётся.
##
## Переживает только СИД — то есть карта после смерти складывается другая.
## Полотна не переживают, и это решение автора: соединять точки просто, к этому
## быстро приноравливаются, и сохранённый прогресс в такой механике ничего не
## бережёт, зато убирает у смерти цену. А цена ей нужна: без неё поимка —
## помеха, а не угроза.
static var carry_seed: int = 0   ## сид следующего захода; 0 — обычный
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
var _from_room: bool = false    ## пришли из пролога, заставку уже видели
var dead: bool = false
var scare_only: bool = false   ## скример без поимки: просто испугать
var start_ui
var voice_ui                    ## слой, которым говорит тварь
var says                        ## распорядитель фраз: он решает, можно ли сейчас
var _away_days: int = 0         ## сколько дней не запускали, считано до отметки
var _pauses: int = 0            ## сколько раз снимали паузу
var _says_t: float = 0.0        ## опрос поводов идёт не каждый кадр
var _box_t: float = 200.0       ## до следующего обрывка шкатулки
## ОТДЕЛЬНЫЙ ГЕНЕРАТОР ДЛЯ УКРАШЕНИЙ. Голос, шкатулка и выбор реплики добивания
## не имеют права брать числа из общего _rng: из него берётся ВСЁ остальное —
## куда пойдёт монстр, будет ли скример, промахнётся ли щупальце. Опрос фраз
## идёт дважды в секунду, и за забег он вычерпывал оттуда сотни значений,
## сдвигая каждый следующий случайный выбор в игре. Замер: с голосом бот
## проходил за 349 с и не доходил до двух полотен, без него — за 254 с и до
## всех. Карта у нас одна на всех нарочно, и поток случайностей обязан зависеть
## от сида, а не от того, сколько раз успел сработать опрос.
var _srng := RandomNumberGenerator.new()
## ДОБИВАНИЕ. Стадии: 1 хватает, 2 поднимает, 3 держит над собой, 4 разрыв.
var fat_stage: int = 0
var fat_t: float = 0.0
var fat_from: Vector3 = Vector3.ZERO
var fat_to: Vector3 = Vector3.ZERO
var fat_roll: float = 0.0
var credits_ui
var death_ui
var pause_ui
var started: bool = false   ## нажата ли клавиша на стартовом экране
## Окно потеряло фокус — игра встаёт. Выключается только для стенда и съёмки.
var _autopause: bool = true
var nests: Array = []           ## {pos, used}
var nests_hit: int = 0
var safe_cells: Array[Vector2i] = []
var safe_sit: float = 0.0       ## сколько сидишь в убежище
var drop_t: float = 0.0         ## сколько ещё падать после выброса
var still_t: float = 0.0        ## окно «замри» перед захватом щупалец
var still_text: String = ""
var still_src: String = ""
var esc_by_flash: bool = false  ## вырвался вспышкой — палочку не отбирают
## Щупальца иногда ЩУПАЮТ ВОЗДУХ прежде чем схватить. Замер — и они проходят
## мимо. Внутри захвата такого нет и не будет: из монстра надо выдираться.
const STILL_CHANCE := 0.22
const STILL_TIME := 1.9
const DROP_H := 3.4             ## с какой высоты
const DROP_T := 1.15            ## сколько длится падение
var ambush_done: bool = false
var ambush_t: float = -1.0
var burst_t: float = 0.0
var nest_gap_t: float = 0.0
var visited := {}               ## клетки, где ты уже был — палочка их метит
var eyes: Array = []            ## красные глаза по краям экрана от безумия
var eyes_layer: Control
var sprint_bar: Control
var wand_lamp: SpotLight3D
var wand_view: Node3D
var wand_mesh: MeshInstance3D   ## сама палочка: в захвате она меняет форму
var wand_worms: Array = []      ## нити, ползущие по палочке к кончику
var wand_bead: MeshInstance3D   ## светящаяся точка на конце
var mon_lamp: SpotLight3D       ## луч с палочки, который бьёт ТОЛЬКО по монстру
var lid_top: ColorRect          ## веки: моргание
var lid_bot: ColorRect
var blink_t: float = 3.0        ## до следующего моргания
var blink_p: float = 0.0        ## 0 — открыто, 1 — закрыто
var blink_dir: float = 0.0      ## -1 закрывается, 1 открывается
var blink_hold: float = 0.0     ## сколько держать глаза закрытыми
var breath_t: float = 0.0       ## сколько ещё отдыхиваться
var breath_gap: float = 0.0
const BLINK_GAP := [3.4, 8.0]   ## пауза между морганиями
var lift_on: bool = false       ## монстр поднял игрока над полом
var lift_y: float = 0.0         ## насколько поднял
var lift_to: Vector3 = Vector3.ZERO  ## куда именно держит — точка между его рук
var strain_t: float = 0.0       ## до следующего крика в хвате
const LIFT_H := 1.45            ## на сколько метров
## УДАР О СТЕНУ — третья фаза. Он не подходит и не хватает, а швыряет тебя
## щупальцем в стену. Ты падаешь, палочка вылетает, и пока ты её ищешь, он
## медленно вылезает. Успел найти и ударить вспышкой — уходит обратно в камень.
## Не успел или вспышка потрачена — берёт, и бежать бесполезно.
var slam_stage: int = 0         ## 0 нет, 1 летишь, 2 лежишь, 3 встал, 4 тянет, 5 вдавливает
var slam_t: float = 0.0         ## сколько осталось в текущей стадии
var slam_left: float = 0.0      ## сколько всего до неминуемой поимки
var slam_cool: float = 0.0
var traps_left: int = TRAP_TIMES  ## сколько засад из стены осталось на проход
var forms_left: int = FORM_TIMES  ## сколько раз он ещё выйдет фигурой
var form_cool: float = 0.0
var form_want: float = -1.0    ## сколько ждём удобного момента; -1 — не взведено
var slam_to: Vector3 = Vector3.ZERO
var slam_from: Vector3 = Vector3.ZERO   ## откуда он вылезает
var slam_out: float = 0.0               ## насколько уже выдавился
const SLAM_FLY := 0.30
const SLAM_DOWN := 1.5
const SLAM_WINDOW := 8.5
const SLAM_COOL := 75.0
## ДВА РАЗА ЗА ИГРУ, и ни разом больше. Ловушка из стены — событие, а не приём:
## третий раз она уже не пугает, а раздражает, потому что ты её знаешь. Откат
## нужен только чтобы два срабатывания не легли подряд.
const TRAP_TIMES := 2
## ФИГУРА В ЛАБИРИНТЕ. До сих пор вторая форма жила только внутри скримера при
## поимке: полторы секунды, один облик из трёх наугад, и всё это под экраном
## испуга. То есть человека, которого мы собрали целиком — со своей походкой,
## руками с потолка и языком из пасти, — игрок за проход не видел НИ РАЗУ.
## Теперь он ВЫХОДИТ фигурой: дважды за игру, на полминуты, и только когда его
## видно, иначе превращение случится за спиной в соседнем коридоре.
const FORM_TIMES := 2
const FORM_LEN := 28.0
const FORM_COOL := 120.0
## Сколько ждать удобного момента, прежде чем сделать его самим.
const FORM_WAIT := 45.0
## АТАКИ ФИГУРЫ. Первая: он замирает, тянет руки вверх — и тебя ловят руки
## С ПОТОЛКА, где бы ты ни был. Пока висишь, он бежит к тебе втрое быстрее и
## берёт ртом из живота. Вторая: выстрел языком из пасти и рывок к себе.
var hf_stage: int = 0           ## 0 нет, 1 руки с потолка, 2 он бежит, 3 взял
var hf_t: float = 0.0
var hf_cool: float = 0.0
var hf_step: float = 0.0        ## до следующего его шага на бегу
const HF_HANG := 2.6            ## сколько висишь, пока он бежит
const HF_COOL := 65.0
const HF_RUSH := 2.5            ## во сколько раз быстрее обычного он бежит
var _click_t: float = 0.0
var phase_bar: Control
var next_fear_mul: float = 1.0   ## во сколько раз сильнее трясёт следующее полотно
var dev: bool = false           ## подсказки создателя
var mad_said := {}              ## какие пороги безумия уже объявлены
var wall_mat: ShaderMaterial
var ceil_mat: ShaderMaterial
var floor_mat: ShaderMaterial
# ── ОБВАЛ. Одно место на весь лабиринт, в середине пути: под проломом навалило
# камня, и по нему можно подняться и высунуть голову наружу. Наверху солнце,
# небо и полсекунды на то, чтобы поверить, что отсюда есть выход.
var climb_cell: Vector2i = Vector2i(-1, -1)
var climb: Node3D               ## насыпь целиком, вместе с коллизией
var climb_a: Vector3            ## низ ската
var climb_b: Vector3            ## верх ската, у самого пролома
var climb_state: int = 0        ## 0 стоит, 1 наверху, 2 тянет вниз, 3 уходит под землю
var climb_t: float = 0.0
var climb_shapes: Array = []    ## коллизии скатов: отключаем в момент обвала
const MOUND_H := 0.55           ## высота насыпи: через неё переходят, а не лезут
var climb_ready: bool = false   ## стоит на насыпи, может полезть наверх
var climb_tent: Node3D          ## то, что за ним поднимется
var climb_segs: Array = []
var climb_grab: Vector3
var goo_rect: ColorRect
var goo_wipe: float = 0.0        ## идёт протирание: 0..1, дальше сбрасывается
var goo_hold: float = 0.0        ## сколько секунд после протирания не заливать
var goo_wiped_in: bool = false   ## вытер, когда вошёл под пролом
var goo_wiped_out: bool = false  ## и второй раз, когда выходил
var goo_amt: float = 0.0
var dropped_wand: MeshInstance3D    ## палочка, выбитая из руки
var reel_t: float = 0.0             ## сколько ещё тянет к себе
var reel_to: Vector3 = Vector3.ZERO  ## куда тянет
var grab_src: String = ""            ## кто держит: от этого зависит, может ли он дойти
var reel_wait: float = 0.0           ## сколько ещё ждём, пока доиграет чужое окно
var board_torn: bool = false   ## холст сорвал ОН, а не таймер
var holes: Array[Vector2i] = []
var drips: Array = []            ## места капели: клетка и время до следующей капли
var drops: Array = []            ## пул падающих капель, чтобы не плодить узлы
var eyes_quad: MeshInstance3D    ## глаза, открывающиеся в стене
var eyes_mat: ShaderMaterial
var eyes_t: float = 0.0          ## сколько им ещё висеть
var eyes_wait: float = 0.0       ## сколько до следующей попытки
var tents: Array = []            ## щупальца из стен: пул узлов
var tent_gap: float = 0.0        ## пауза до следующего появления
var tent_cap: int = TENT_MAX     ## потолок числа щупалец, зависит от качества
var splashes: Array = []         ## пул колец-брызг
var hole_splash_t: float = 0.0   ## до следующей брызги под дырой
var env_ref: Environment
var _skit_t: float = 0.0
var _heart_t: float = 0.0
var _breath_t: float = 0.0
var mon_on: bool = false        ## линия к монстру [M]
var mon_line: MeshInstance3D
var thread_on: bool = false
var thread_line: MeshInstance3D
var thread_mark: MeshInstance3D  ## огонёк в конце нити: видно, КУДА она ведёт
var _thread_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# ПЕРВОЙ строкой: ползунки громкости создаются в _build_ui и читают Settings
	# при создании. Загрузи позже — и они покажут не сохранённое, а значение
	# по умолчанию, а первый же сдвиг запишет его поверх настроек игрока.
	Settings.load_all()
	# АВТОПАУЗА НЕ ДЛЯ СТЕНДА И НЕ ДЛЯ СЪЁМКИ. Там окно фокус не держит вовсе:
	# бот гоняется в фоне, съёмка кадров идёт со свёрнутым окном, — и пауза
	# остановила бы и прогон, и запись на первой же секунде.
	for a in OS.get_cmdline_args():
		if a.begins_with("--write-movie"):
			_autopause = false
	var uargs: PackedStringArray = OS.get_cmdline_user_args()
	if uargs.size() > 0 and uargs[0] == "бот":
		_autopause = false
	# ПАМЯТЬ О ПРОШЛОМ РАЗЕ снимается ДО отметки нового запуска — иначе разрыв
	# всегда выйдет нулевым. Тварь потом назовёт это вслух.
	_away_days = Settings.days_away()
	Settings.note_run()
	# Свой сид, но производный от общего: украшения тоже повторимы от запуска
	# к запуску, просто берут числа из своего потока.
	_srng.seed = 20260908
	# Строим по шагам с ловлей: если упадёт расстановка, мир всё равно соберётся,
	# игрок сможет ходить и, главное, отпустить курсор и прочитать ошибку.
	maze = MazeGenScript.new()
	# СИД. На срезе карта одна и та же: и ты, и тот, кому ты её показываешь,
	# должны получать один и тот же лабиринт, а не «как повезёт». Из командной
	# строки сид можно подменить — этим я и перебирал карты, выбирая эту.
	var s := randi() if regenerate_seed else fixed_seed
	# ПОСЛЕ СМЕРТИ — ДРУГАЯ КАРТА. Стоит ДО разбора командной строки: «сид=» —
	# инструмент отладки и стенда, и он обязан перебивать всё, иначе прогон
	# бота перестаёт быть повторимым, стоит боту один раз умереть.
	if carry_seed != 0:
		s = carry_seed
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("сид="):
			s = int(arg.substr(4))
	# ОБЩИЙ ГЕНЕРАТОР СЕЕМ ДО СБОРКИ ЛАБИРИНТА, а не после: на нём висит и
	# перемешивание массивов, и вся мелочь расстановки.
	seed(s)
	maze.generate(s)
	var guard := 0
	while not maze.is_good(_first_floor()) and guard < 60:
		guard += 1
		s = randi()
		maze.generate(s)
		print("сид не подошёл, взял другой: ", s)
	print("Лабиринт собран, сид ", s, ", размер ", maze.size)

	start_cell = _first_floor()
	_rng.seed = s
	shapes = Shapes.pick(_rng)
	_build_environment()
	_build_floor()
	_build_walls()
	# ПОЛОТНА ПЕРВЫМИ. Проломы в потолке должны знать, где пойдёт игрок: один из
	# них ставится ровно на дорогу между четвёртым и пятым полотном, и ни один —
	# на само полотно. Пока потолок строился раньше, приходилось ГАДАТЬ, где
	# встанут полотна, и на трети сидов пролом промахивался мимо дороги на
	# девять клеток, а на другой трети попадал прямо на полотно.
	_place_features()
	_build_ceiling()
	_build_drips()
	_build_eyes()
	_build_tents()
	_build_climb()
	_place_tables()
	_place_decor()
	_place_safe()
	_place_doors()
	_dress_rooms()
	_build_ui()
	# Слой яркости. Ставится ПОСЛЕ интерфейса и живёт на отрицательном слое:
	# правится мир, а надписи, шкалы и меню остаются как нарисованы.
	Settings.attach_gamma(self)
	_place_player()
	# СВОИ КЛАВИШИ — В САМОМ КОНЦЕ. apply_binds снимает с действия клавиатурное
	# событие и ставит своё, а действия ходьбы заводит ИГРОК при рождении. Пока
	# он не создан, снимать нечего: назначенные игроком W/S/A/D молча терялись.
	Settings.remember_defaults()
	Settings.apply_binds()
	sfx = SfxScript.new()
	add_child(sfx)
	_build_pour_sound()
	_spawn_monster()
	# Игра стоит, пока не нажали клавишу: иначе монстр начинает подбираться,
	# пока человек читает управление.
	# Заморожен ПОЛНОСТЬЮ и курсор свободен: под заставкой не должно работать
	# ничего — ни камера, ни клавиши, ни подбор палочки.
	if _from_room:
		# Провалился сюда из детской: заставки нет, игра идёт сразу.
		_on_start()
	if started:
		_set_cursor(false)
	else:
		_freeze_player(true)
		_set_cursor(true)
	# Вид мира ставится ЗДЕСЬ, а не при первой ошибке. Свет, туман и цвет камня
	# должны с первого кадра соответствовать нулевому безумию, а не ждать, пока
	# что-нибудь их случайно применит.
	apply_quality()
	_apply_madness()
	set_process(true)
	# СТЕНД. Запускается только по слову в командной строке, игры не касается:
	#   Godot --path . -- бот фаза3 погоня формы атаки
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "бот":
		var bot = load("res://Bot.gd").new()
		add_child(bot)
		bot.setup(self)
		bot.run(Array(args.slice(1)))
	set_process_unhandled_input(true)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.62)
	# ambient, а не 1.0. Разошедшиеся числа: мир строился с яркостью 1.0, а
	# _apply_madness ставит ambient (0.07) — в четырнадцать раз темнее. Пока
	# полотно ошибочно проваливало себя на второй секунде, оно вызывало
	# _apply_madness сразу, и расхождения не было видно. Убрал фантом — и мир
	# остался ярким до первой настоящей ошибки, а она роняла свет посреди игры.
	env.ambient_light_energy = ambient
	# Объёмный туман — ради столбов света из дыр. Без него луч не видно в воздухе,
	# видно только пятно на полу, и дыра читается как лампочка, а не как небо.
	# Объёмный туман — второе по цене после наклона нормали у пола. На низком
	# качестве он выключается целиком: столбы света из проломов станут плоскими
	# пятнами на полу, но игра будет идти.
	env.volumetric_fog_enabled = Settings.quality >= 2
	# 0.055 забеливало весь коридор. Туман нужен РЕДКИЙ, а видимость луча берётся
	# не из него, а из light_volumetric_fog_energy у самого солнца.
	env.volumetric_fog_density = 0.017
	env.volumetric_fog_albedo = Color(0.86, 0.88, 0.92)
	env.volumetric_fog_length = 44.0
	env.volumetric_fog_gi_inject = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.02, 0.03)
	env.fog_density = fog
	env_ref = env
	we.environment = env
	add_child(we)


func _build_floor() -> void:
	var fw = maze.size.x * cell_size
	var fh = maze.size.y * cell_size
	# Видимый пол строится ТОЛЬКО под проходимыми клетками. Под камнем его никто
	# не увидит, а сетка нужна густая: пузыри поднимаются вершинами.
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = FLOOR_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sub: int = [2, 3, 4][Settings.quality]
	var q: float = cell_size / float(sub)
	for r in maze.size.y:
		for c in maze.size.x:
			if maze.grid[r][c] != 0:
				continue
			for i in sub:
				for j in sub:
					_floor_quad(st, c * cell_size + i * q, r * cell_size + j * q, q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = floor_mat
	add_child(mi)
	# Плита под всем — она держит столкновения и закрывает щели по краям.
	var slab := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(fw, 0.4, fh)
	slab.mesh = m
	slab.material_override = _material(Color(0.02, 0.02, 0.025))
	slab.position = Vector3(fw * 0.5, -0.21, fh * 0.5)
	add_child(slab)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = m.size
	cs.shape = shape
	# ПЛИТА СТОЛКНОВЕНИЙ ЛЕЖИТ ТАМ ЖЕ, ГДЕ ВИДИМАЯ. Здесь стояло mi.position —
	# то есть начало координат, — а лабиринт занимает четверть от него вправо и
	# вниз. Значит пол под ногами был только над той четвертью, что попала под
	# коробку, а на остальных трёх столкновений не было вовсе. Не замечалось это
	# потому, что тяжести в игре нет: проваливаться было нечем.
	#
	# Зато там, где коробка всё-таки была, её верх приходился на 0.2 м вместо
	# нуля, и капсула стояла в плите. Движок раз в несколько шагов выталкивал её
	# наружу на двенадцать сантиметров и отпускал обратно — стоя на месте это
	# читалось как дёргающаяся камера.
	#
	# Верх коробки ровно на нуле: игрок встаёт на 0.85, а именно это число
	# записано во всех местах, где его куда-то ставят.
	body.position = Vector3(fw * 0.5, -m.size.y * 0.5, fh * 0.5)
	body.add_child(cs)
	add_child(body)


## Дыры в потолке. Далеко от старта и друг от друга: три солнечных столба в
## одном закутке — это не находка, а освещение.
func _pick_holes() -> void:
	var free: Array[Vector2i] = []
	for r in maze.size.y:
		for c in maze.size.x:
			if maze.grid[r][c] == 0:
				free.append(Vector2i(r, c))
	free.shuffle()
	# ПЕРВЫЙ пролом — на середине пути. Полотна расставляются позже, но порядок
	# у них один: по удалению от старта, — а значит середину пути можно взять
	# прямо из расстояний, ещё до того, как полотна встанут. Под этим проломом
	# и будет обвал, по которому можно подняться наружу.
	var dist: Dictionary = maze.distances(start_cell)
	var deepest: int = 0
	for cell in dist:
		deepest = maxi(deepest, int(dist[cell]))
	var midc: Vector2i = _mid_path_cell(dist, deepest)
	if midc.x >= 0:
		holes.append(midc)
		climb_cell = midc
	for cell in free:
		if holes.size() >= holes_want:
			break
		if Vector2(cell - start_cell).length() < 10.0:
			continue
		var ok := true
		for h in holes:
			if Vector2(cell - h).length() < 12.0:
				ok = false
				break
		# И НЕ НА ПОЛОТНО. Под проломом льёт масса и заливает экран — полотно
		# там не нарисовать, а таймер идёт. Выход — туда же: последняя дверь под
		# заливающим экраном это не сложность, а издевательство.
		for cc in canv_cells:
			if Vector2(cell - cc).length() < 2.5:
				ok = false
				break
		if ok and Vector2(cell - exit_cell).length() < 2.5:
			ok = false
		if ok:
			holes.append(cell)
	print("Дыр в потолке: ", holes.size(), " ", holes)


## СЕРЕДИНА ПУТИ — не середина лабиринта. Путь игрока — это цепочка полотен, и
## «середина игры» это дорога от четвёртого к пятому. Полотна встают позже, но
## встают они в залы по глубине, а залы известны уже сейчас, — значит дорогу
## можно предсказать и поставить пролом ровно на неё, а не «где-то в середине».
func _mid_path_cell(dist: Dictionary, deepest: int) -> Vector2i:
	if canv_cells.size() >= 3:
		var m: int = int(canv_cells.size() / 2)
		var path: Array[Vector2i] = _path_cells(canv_cells[m - 1], canv_cells[m])
		if path.size() > 4:
			# Идём от середины дороги наружу. Сначала ищем клетку и не в зале, и
			# не у полотна; если такой на дороге нет — соглашаемся на любую не у
			# полотна. ДОРОГА ВАЖНЕЕ: с прежним порядком на трёх сидах из восьми
			# обвал уезжал в сторону на 11–30 клеток, то есть переставал быть
			# «на пути игрока» — ровно тем, ради чего он и делался.
			var half: int = int(path.size() / 2)
			for strict in [true, false]:
				for off in range(0, half):
					for sgn in [1, -1]:
						var i: int = half + off * sgn
						if i < 1 or i >= path.size() - 1:
							continue
						if not _far_from_canv(path[i]):
							continue
						if strict and not _far_from_rooms(path[i]):
							continue
						return path[i]
	# Запасной вариант: просто половина глубины.
	var want: int = int(0.5 * float(deepest))
	var best := Vector2i(-1, -1)
	var bd: int = 1 << 30
	for cell in dist:
		var c2: Vector2i = cell
		if maze.grid[c2.x][c2.y] != 0 or not _far_from_rooms(c2) or not _far_from_canv(c2):
			continue
		var dd: int = absi(int(dist[cell]) - want)
		if dd < bd:
			bd = dd
			best = c2
	return best


## Не на полотне и не впритык к нему: под проломом льёт масса, рисовать под ней
## нельзя. Запасная ветка выбора середины эту проверку пропускала, и на каждом
## четвёртом сиде обвал вставал ровно на полотно.
func _far_from_canv(cell: Vector2i) -> bool:
	for c in canv_cells:
		if Vector2(c - cell).length() < 2.5:
			return false
	return Vector2(exit_cell - cell).length() >= 2.5


func _far_from_rooms(cell: Vector2i) -> bool:
	for room in maze.rooms:
		if Vector2(_room_cell(room) - cell).length() < 4.0:
			return false
	return true


## Дорога из клетки в клетку: спускаемся по расстояниям от «а» — так же, как
## по ним ищут выход.
func _path_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var da: Dictionary = maze.distances(a)
	var out: Array[Vector2i] = []
	if not da.has(b):
		return out
	var cur: Vector2i = b
	var guard: int = 0
	while cur != a and guard < 4000:
		guard += 1
		out.append(cur)
		var best: Vector2i = cur
		var bd: int = int(da[cur])
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if da.has(nb) and int(da[nb]) < bd:
				bd = int(da[nb])
				best = nb
		if best == cur:
			break
		cur = best
	out.append(a)
	out.reverse()
	return out


## Течение у проломов. Звучит ПОСТОЯННО и из точки: дыру слышно из коридора
## раньше, чем видно, и это единственный ориентир в лабиринте, который не врёт.
## Раньше там были только редкие шлепки — масса лилась беззвучно.
func _build_pour_sound() -> void:
	if sfx == null or holes.is_empty():
		return
	# Тип явно: sfx нетипизирован, и вывести тип возврата Godot не может.
	var st: AudioStreamWAV = sfx.pour_stream()
	if st == null:
		return
	for h in holes:
		var p := cell_to_world(h, 0.9)
		var pl := AudioStreamPlayer3D.new()
		pl.stream = st
		# Петля теперь собрана из слизи, а не из воды, поэтому по высоте её надо
		# ронять меньше — иначе получается гул, а не хлюпанье.
		pl.pitch_scale = 0.92
		pl.volume_db = -12.0
		pl.unit_size = 9.0
		pl.max_distance = 26.0
		pl.position = p
		add_child(pl)
		pl.play()
	print("Течение озвучено у ", holes.size(), " проломов")


func _build_ceiling() -> void:
	_pick_holes()
	ceil_mat = ShaderMaterial.new()
	ceil_mat.shader = WALL_SHADER
	# Потолок серее стен и шевелится крупнее: он висит, а не стоит.
	ceil_mat.set_shader_parameter("base_color", Color(0.105, 0.105, 0.112))
	ceil_mat.set_shader_parameter("spark_color", Color(0.28, 0.40, 0.34))
	ceil_mat.set_shader_parameter("mad_spark", Color(0.24, 0.11, 0.40))
	ceil_mat.set_shader_parameter("mad_color", Color(0.075, 0.05, 0.11))
	ceil_mat.set_shader_parameter("bulge", 0.42)
	ceil_mat.set_shader_parameter("buzz", 0.75)
	# Потолок висит в 2.7 м над глазами — на самой границе, где мелочь гаснет.
	# Со стенным near_dist он читался пустым: мимо носа проходит только вблизи.
	ceil_mat.set_shader_parameter("near_dist", 6.5)
	ceil_mat.set_shader_parameter("relief", 1.8)
	ceil_mat.set_shader_parameter("madness", 0.07)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Пять на клетку вместо трёх: вершинам нужно на чём выпирать, иначе густая
	# масса получается плоской заливкой с рисунком.
	var sub: int = [2, 3, 5][Settings.quality]
	var q: float = cell_size / float(sub)
	for r in maze.size.y:
		for c in maze.size.x:
			if holes.has(Vector2i(r, c)):
				continue
			for i in sub:
				for j in sub:
					_ceil_quad(st, c * cell_size + i * q, r * cell_size + j * q, q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = ceil_mat
	add_child(mi)

	for h in holes:
		_build_hole(h)


func _ceil_quad(st: SurfaceTool, x: float, z: float, q: float) -> void:
	var y: float = wall_height
	var a := Vector3(x, y, z)
	var b := Vector3(x + q, y, z)
	var c := Vector3(x + q, y, z + q)
	var d := Vector3(x, y, z + q)
	for v in [a, c, b, a, d, c]:
		st.set_normal(Vector3.DOWN)
		st.add_vertex(v)


## Дыра: небо сверху, столб света вниз и та же масса, которая льётся внутрь.
func _build_hole(cell: Vector2i) -> void:
	# У пролома с обвалом всё своё: и небо, и солнце, и отсутствие занавеса.
	# Белая заглушка в трёх метрах над потолком с вершины насыпи закрывала
	# полнеба — ровно то, ради чего туда и лезут.
	if cell == climb_cell:
		return
	var p := cell_to_world(cell, 0.0)

	var sky := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(cell_size * 0.96, 0.1, cell_size * 0.96)
	sky.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.97, 0.88)
	smat.disable_fog = true
	sky.mesh.surface_set_material(0, smat)
	sky.position = Vector3(p.x, wall_height + 3.0, p.z)
	add_child(sky)

	_hole_sun(p)

	# ЗАНАВЕС ПО ОБОДУ. Масса течёт с КРАЁВ пролома — из середины ей течь неоткуда,
	# там дыра. Нижний край вытянут языками разной длины: кусок мира тает.
	_hole_curtain(p)


## Столб света из пролома. Тот же и над обвалом: без него в клетке темно, и
## снизу непонятно, что там наверху вообще что-то есть.
func _hole_sun(p: Vector3) -> void:
	var sun := SpotLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.82)
	# 11 выжигало пол в белое пятно. Солнце должно ОСВЕЩАТЬ закуток, а не
	# светить в глаза.
	sun.light_energy = 4.5
	# Вот это и рисует луч в воздухе: обычная яркость на объёмный туман не влияет.
	sun.light_volumetric_fog_energy = 18.0
	sun.spot_range = wall_height + 6.0
	sun.spot_angle = 21.0
	sun.spot_angle_attenuation = 0.9
	sun.spot_attenuation = 0.6
	sun.shadow_enabled = true
	sun.position = Vector3(p.x, wall_height + 2.6, p.z)
	sun.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(sun)


func _hole_curtain(p: Vector3) -> void:
	var rim_mat := ShaderMaterial.new()
	rim_mat.shader = POUR_SHADER
	var curtain_h: float = 1.5
	rim_mat.set_shader_parameter("melt", 1.0)
	rim_mat.set_shader_parameter("half_h", curtain_h * 0.5)
	var curtain := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	# Радиус БОЛЬШЕ половины клетки, а верх утоплен в потолок. Занавес был уже
	# пролома и кончался ровно на уровне потолка — по краю оставалась щель, и
	# сквозь неё было видно, что масса висит в воздухе. Потолок вдобавок
	# шевелится вершинами, так что перекрытие нужно с запасом.
	cm.top_radius = cell_size * 0.56
	cm.bottom_radius = cell_size * 0.50
	cm.height = curtain_h
	cm.radial_segments = 40
	cm.rings = 14
	cm.cap_top = false
	cm.cap_bottom = false
	curtain.mesh = cm
	curtain.material_override = rim_mat
	curtain.position = Vector3(p.x, wall_height - curtain_h * 0.5 + 0.45, p.z)
	add_child(curtain)

	# Несколько нитей, дотянувшихся до пола. Не по кругу, а вразнобой: ровный
	# частокол выглядел бы решёткой.
	var thin := ShaderMaterial.new()
	thin.shader = POUR_SHADER
	for i in 4:
		var a: float = _rng.randf() * TAU
		var rad: float = cell_size * 0.45
		var t := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.055
		tm.bottom_radius = 0.03
		tm.height = wall_height - 0.1
		tm.radial_segments = 8
		tm.rings = 4
		t.mesh = tm
		t.material_override = thin
		t.position = Vector3(p.x + cos(a) * rad, (wall_height - 0.1) * 0.5, p.z + sin(a) * rad)
		add_child(t)

	# Лужа кольцом под ободом, а не блином посередине: натекло оттуда, откуда лилось.
	var pool := MeshInstance3D.new()
	var pm := TorusMesh.new()
	pm.inner_radius = cell_size * 0.30
	pm.outer_radius = cell_size * 0.62
	pm.rings = 24
	pm.ring_segments = 8
	pool.mesh = pm
	pool.material_override = thin
	pool.scale = Vector3(1.0, 0.10, 1.0)
	pool.position = Vector3(p.x, 0.04, p.z)
	add_child(pool)


## Капель. Сорок мест на весь лабиринт: реже — и её не замечаешь, чаще — и она
## превращается в фон, который перестаёшь слышать.
func _build_drips() -> void:
	var free: Array[Vector2i] = []
	for r in maze.size.y:
		for c in maze.size.x:
			if maze.grid[r][c] == 0 and not holes.has(Vector2i(r, c)):
				free.append(Vector2i(r, c))
	free.shuffle()
	for i in mini(DRIP_POINTS, free.size()):
		drips.append({"cell": free[i], "t": _rng.randf_range(1.0, 14.0)})
	var dmat := ShaderMaterial.new()
	dmat.shader = POUR_SHADER
	for i in 8:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.045
		sm.height = 0.16
		sm.radial_segments = 6
		sm.rings = 4
		mi.mesh = sm
		mi.material_override = dmat
		mi.visible = false
		add_child(mi)
		drops.append({"node": mi, "t": 0.0, "from": Vector3.ZERO})
	for i in 10:
		var sp := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		# Плашмя на полу: кольцо расходится по полу, а не висит стенкой.
		q.orientation = PlaneMesh.FACE_Y
		sp.mesh = q
		var sm := ShaderMaterial.new()
		sm.shader = SPLASH_SHADER
		sp.material_override = sm
		sp.visible = false
		add_child(sp)
		splashes.append({"node": sp, "mat": sm, "t": 0.0})


func _build_eyes() -> void:
	eyes_mat = ShaderMaterial.new()
	eyes_mat.shader = EYES_SHADER
	eyes_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.26)
	eyes_quad.mesh = q
	eyes_quad.material_override = eyes_mat
	eyes_quad.visible = false
	add_child(eyes_quad)
	eyes_wait = _rng.randf_range(25.0, 55.0)


## Щупальца из стен. Почти все — ОТВЛЕКАЮЩИЕ: они вьются, но не трогают.
## Смысл в том, что среди двух десятков безобидных не отличить то одно, которое
## сейчас ударит, — и приходится бояться каждого.
func _build_tents() -> void:
	for i in TENT_MAX:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.028
		cm.bottom_radius = 0.10
		cm.height = 1.0
		cm.radial_segments = 8
		cm.rings = 14
		cm.cap_top = true
		mi.mesh = cm
		var m := ShaderMaterial.new()
		m.shader = TENT_SHADER
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		tents.append({"node": mi, "mat": m, "t": 0.0})


## Одно щупальце в стене возле точки. Возвращает false, если стены рядом нет.
func _spawn_tent(from: Vector3, dir: Vector3, life: float, big: bool) -> bool:
	var slot: Dictionary = {}
	for t in tents:
		if t["t"] <= 0.0:
			slot = t
			break
	if slot.is_empty():
		return false
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * cell_size * 3.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.4:
		return false
	var ln: float = _rng.randf_range(1.5, 2.6) if big else _rng.randf_range(0.6, 1.7)
	slot["big"] = big
	var node: MeshInstance3D = slot["node"]
	node.global_position = hit["position"] + n * (ln * 0.5)
	node.look_at(node.global_position + n, Vector3.UP)
	# +Y меша должен смотреть ИЗ стены, а look_at наводит -Z. Отсюда доворот.
	node.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	node.scale = Vector3(1.0, ln, 1.0)
	slot["mat"].set_shader_parameter("phase", _rng.randf() * TAU)
	slot["mat"].set_shader_parameter("wave", 0.42 if big else _rng.randf_range(0.14, 0.30))
	slot["mat"].set_shader_parameter("speed", 4.2 if big else _rng.randf_range(1.2, 2.4))
	if big:
		# Бьющее всегда красное — единственный цвет, которого больше нигде нет.
		slot["mat"].set_shader_parameter("rim_tint", Color(0.62, 0.20, 0.16))
	else:
		# Отвлекающие идут за стенами: зелёные, пока держишься, фиолетовые к концу.
		var k: float = clampf(float(errors) / float(MAD_MAX), 0.0, 1.0)
		slot["mat"].set_shader_parameter("rim_tint",
			Color(0.20, 0.44, 0.28).lerp(Color(0.30, 0.14, 0.48), k))
	slot["t"] = life
	node.visible = true
	return true


func _update_tents(delta: float) -> void:
	for t in tents:
		if t["t"] <= 0.0:
			continue
		t["t"] -= delta
		if t["t"] <= 0.0:
			t["node"].visible = false
	if player_node == null or _ui_blocking() or dead or won:
		return
	# Сколько их сейчас — целиком от безумия. На нуле почти никого, на потолке
	# стены шевелятся со всех сторон.
	var k: float = clampf(float(errors) / float(MAD_MAX), 0.0, 1.0)
	var want: int = int(round(k * float(tent_cap - 2)))
	var live := 0
	for t in tents:
		if t["t"] > 0.0:
			live += 1
	tent_gap -= delta
	if live >= want or tent_gap > 0.0:
		return
	tent_gap = _rng.randf_range(0.25, 1.1)
	var head: Node3D = player_node.get_node_or_null("Head")
	if head == null:
		return
	var a: float = _rng.randf() * TAU
	var dir := Vector3(cos(a), 0.0, sin(a))
	_spawn_tent(head.global_position, dir, _rng.randf_range(5.0, 13.0), false)


func _floor_quad(st: SurfaceTool, x: float, z: float, q: float) -> void:
	var a := Vector3(x, 0.0, z)
	var b := Vector3(x + q, 0.0, z)
	var c := Vector3(x + q, 0.0, z + q)
	var d := Vector3(x, 0.0, z + q)
	for v in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


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
		# Шаг примерно полметра — как у потолка. Было три деления на клетку с
		# потолком в 24: на длинной стене это метр с лишним, и выпирать вершинам
		# негде. Рельеф был, но только в шейдере нормалей, а силуэт оставался
		# прямой линейкой.
		# Шаг сетки зависит от качества. Это САМАЯ дорогая часть: смещение вершин
		# считает шум с искажением области, то есть три с лишним десятка хэшей на
		# каждую вершину, а их сотни тысяч. Настройки пикселей дают проценты,
		# плотность сетки — разы.
		var step: float = [1.2, 0.75, 0.5][Settings.quality]
		m.subdivide_width = clampi(int(bw * cell_size / step), 1, 48)
		m.subdivide_depth = clampi(int(bh * cell_size / step), 1, 48)
		m.subdivide_height = clampi(int(wall_height / step), 1, 16)
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
		p.stepped.connect(_on_step)
		p.sprint_ended.connect(_on_sprint_ended)
	p.global_position = cell_to_world(start_cell, 0.85)
	if "mouse_sens" in p:
		# Базовое значение умножаем на настройку игрока, а не заменяем: так
		# «единица» всегда означает то, под что игра настраивалась.
		p.mouse_sens = 0.0022 * Settings.mouse
	if player_light > 0.0 and p.has_node("Head"):
		# Не лампа вокруг игрока, а КОНУС ВПЕРЁД. Лампа освещала и то, что сзади,
		# и лабиринт переставал быть тёмным: смотреть по сторонам было незачем.
		var lamp := SpotLight3D.new()
		lamp.light_energy = player_light
		lamp.light_color = Color(0.86, 0.89, 0.96)
		# Дальность и спад важнее самой яркости: «вперёд не светит» — это не про
		# мощность лампы, а про то, что луч гаснет через десяток метров.
		lamp.spot_range = 19.0
		lamp.spot_angle = 32.0          # узкий: край луча всегда рядом с темнотой
		lamp.spot_angle_attenuation = 1.4
		lamp.spot_attenuation = 0.85
		lamp.shadow_enabled = true
		# Палочка НЕ светит в объёмный туман. Он включён ради солнечных столбов
		# из проломов, но лампа в упор рассеивалась в нём и давала дымку вместо
		# луча — казалось, что фонарь сел.
		lamp.light_volumetric_fog_energy = 0.0
		lamp.position = Vector3(0, -0.1, 0)
		p.get_node("Head").add_child(lamp)
		lamp.visible = has_wand         # свет появляется только с палочкой в руке
		wand_lamp = lamp
		_build_viewmodel(p.get_node("Head"))
	print("Игрок поставлен в клетку ", start_cell, " -> ", p.global_position)


## Клетка лабиринта -> точка в мире. Пригодится для полотен, столов и монстра.
## Палочка и кусок руки в кадре. Без них игрок — бестелесная камера: свет
## берётся ниоткуда, и нечему пачкаться, ломаться и дрожать.
##
## Всё висит на голове, поэтому двигается вместе со взглядом. Держим близко и
## мелко: отдельной камеры под оружие тут нет, и длинная палка втыкалась бы в
## стены.
func _build_viewmodel(head: Node3D) -> void:
	var view := Node3D.new()
	view.name = "View"
	head.add_child(view)
	wand_view = view

	# КУЛАК, А НЕ ПЛАСТИНА. Одна светлая коробка ловила весь конус фонаря и
	# читалась как серый клин в углу экрана — на снятом кадре она была вторым по
	# яркости пятном после самого огонька. Тон темнее кожи в тени, блик убран, и
	# сверху лежит большой палец: без него кисть не читается кистью.
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.17, 0.14, 0.13)
	hmat.roughness = 1.0
	hmat.metallic_specular = 0.0
	var hand := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.082, 0.072, 0.155)
	hand.mesh = hm
	hand.material_override = hmat
	hand.position = Vector3(0.252, -0.205, -0.395)
	hand.rotation_degrees = Vector3(-16.0, 0.0, -8.0)
	view.add_child(hand)
	var thumb := MeshInstance3D.new()
	var tm2 := BoxMesh.new()
	tm2.size = Vector3(0.030, 0.030, 0.085)
	thumb.mesh = tm2
	thumb.material_override = hmat
	thumb.position = Vector3(0.222, -0.176, -0.418)
	thumb.rotation_degrees = Vector3(-32.0, 6.0, -10.0)
	view.add_child(thumb)

	var wand := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.018
	wm.bottom_radius = 0.026
	wm.height = 0.46
	wm.radial_segments = 8
	wand.mesh = wm
	wand.material_override = _tex_material("wood", 3.0, Color(0.30, 0.25, 0.21))
	wand.position = Vector3(0.235, -0.13, -0.5)
	wand.rotation_degrees = Vector3(-72.0, 0.0, -6.0)
	view.add_child(wand)
	wand_mesh = wand

	# СВЕТИТ КОНЧИК. Свет шёл от головы, и связь «светит палочка» держалась
	# только на том, что игрок сам догадается. Точка на конце эту связь и делает.
	var bead := MeshInstance3D.new()
	var bm2 := SphereMesh.new()
	bm2.radius = 0.026
	bm2.height = 0.052
	bm2.radial_segments = 12
	bm2.rings = 8
	bead.mesh = bm2
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.92, 0.97, 1.0)
	bmat.emission_enabled = true
	bmat.emission = Color(0.80, 0.92, 1.0)
	bmat.emission_energy_multiplier = 6.0
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bead.material_override = bmat
	# Кончик — это +Y меша: цилиндр центрирован, высота 0.46.
	# 0.265, а не 0.248: полувысота древка 0.23 плюс радиус шарика 0.026 — на
	# меньшем выносе торец палочки срезает точку, и на кадре она полумесяц.
	bead.position = Vector3(0.0, 0.265, 0.0)
	wand.add_child(bead)
	wand_bead = bead
	# ОТДЕЛЬНЫЙ ЛУЧ ПО МОНСТРУ. Обычный фонарь осветить его не может: у него
	# альбедо 0.03, и сколько ни добавляй яркости, отражать нечему — зато
	# коридор вокруг выбелится. Этот луч светит только по его слою: стены,
	# пол и мебель его не видят вовсе.
	var ml := SpotLight3D.new()
	ml.light_color = Color(0.86, 0.95, 1.0)
	ml.light_energy = 0.0
	ml.spot_range = 26.0
	ml.spot_angle = 46.0
	ml.spot_angle_attenuation = 0.6
	ml.light_cull_mask = 1 << 4     # тот же пятый слой, что помечен в Monster
	ml.shadow_enabled = false
	head.add_child(ml)
	mon_lamp = ml
	var tip := OmniLight3D.new()
	tip.light_color = Color(0.78, 0.90, 1.0)
	tip.light_energy = 0.55
	tip.omni_range = 0.9
	bead.add_child(tip)

	# НИТИ НА ДРЕВКЕ. Деревянная палка не объясняет, как она становится ножом.
	# Тонкие щупальца, ползущие по ней вверх, объясняют: дерево тут ни при чём,
	# внутри та же масса, что и в стенах.
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://tentacle.gdshader")
	wmat.set_shader_parameter("tint", Color(0.030, 0.035, 0.033))
	wmat.set_shader_parameter("rim_tint", Color(0.16, 0.44, 0.27))
	wmat.set_shader_parameter("wave", 0.018)
	wmat.set_shader_parameter("speed", 2.6)
	wmat.set_shader_parameter("pinch", 0.55)
	for i in 7:
		var w := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.0025
		cm2.bottom_radius = 0.007
		cm2.height = 1.0
		cm2.radial_segments = 6
		cm2.rings = 10
		cm2.cap_top = false
		w.mesh = cm2
		w.material_override = wmat
		var ln2: float = 0.055 + float(i % 3) * 0.022
		w.scale = Vector3(1, ln2, 1)
		wand.add_child(w)
		# Своя фаза по кругу и своя скорость: одинаковые ползли бы строем.
		wand_worms.append({"n": w, "a": TAU * float(i) / 7.0,
			"t": float(i) / 7.0, "v": 0.20 + 0.10 * float(i % 3), "len": ln2})
	view.visible = has_wand


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


## Материал из карт ambientCG (всё CC0). Карты лежат в tex/, уменьшены до 512:
## в темноте, где полкадра чёрное, от 1024 их не отличить, а вес вчетверо ниже.
##
## tint — не украшение, а необходимость. Фотографии сняты при дневном свете, и
## в упор к палочке доска светилась бы как в музее. Приглушаем.
func _tex_material(prefix: String, uv: float, tint: Color, rough: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var col = load("res://tex/%s_color.jpg" % prefix)
	if col == null:
		# Текстур нет — игра всё равно должна запускаться, как и со звуком.
		return _material(tint)
	m.albedo_texture = col
	m.albedo_color = tint
	var nrm = load("res://tex/%s_normalgl.jpg" % prefix)
	if nrm != null:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = 1.0
	var rgh = load("res://tex/%s_roughness.jpg" % prefix)
	if rgh != null:
		m.roughness_texture = rgh
	m.roughness = rough
	m.metallic = 0.0
	m.uv1_scale = Vector3(uv, uv, uv)
	return m


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
	room_rects.clear()
	var by_depth := []
	for room in maze.rooms:
		var cell := _room_cell(room)
		if maze.is_wall(cell.x, cell.y) or not dist.has(cell):
			continue
		by_depth.append({"cell": cell, "d": int(dist[cell]), "rect": room})
	by_depth.sort_custom(func(a, b): return a["d"] < b["d"])
	for r in by_depth:
		room_cells.append(r["cell"])
		room_rects.append(r["rect"])

	canv_cells.clear()
	var n_rooms := room_cells.size()
	var taken: Array[Vector2i] = []
	for k in Shapes.N_CANV:
		var cell: Vector2i
		if k == 0:
			# ОБУЧАЮЩЕЕ полотно ставим близко к старту, а не по общей схеме.
			# Крючок игры должен попасться в первую минуту: пока его не увидели,
			# это просто тёмный коридор, каких сотни.
			cell = _cell_at_depth(dist, deepest, 0.06, taken)
		elif n_rooms >= Shapes.N_CANV:
			# берём залы равномерно по списку глубин: от ближнего к дальнему
			var idx: int = int(round(float(k) * (n_rooms - 1) / float(Shapes.N_CANV - 1)))
			cell = room_cells[idx]
		else:
			cell = _cell_at_depth(dist, deepest, [0.06, 0.20, 0.34, 0.48, 0.62, 0.76, 0.90][k], taken)
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
		canv_marks.append(_easel(cell))
		canv_fails.append(0)

	# ПО ГЛУБИНЕ. Полотна открываются строго по очереди, а расстановка иногда
	# ставила третье ближе второго — игрок проходил мимо запертого мольберта,
	# шёл дальше и возвращался. Порядок сложности фигур при этом сохраняется:
	# они и так отсортированы от простой к сложной, а теперь совпадают с путём.
	var order_idx: Array = []
	for k in canv_cells.size():
		order_idx.append(k)
	order_idx.sort_custom(func(a, b): return int(dist.get(canv_cells[a], 0)) < int(dist.get(canv_cells[b], 0)))
	var cells_sorted: Array[Vector2i] = []
	var marks_sorted: Array[MeshInstance3D] = []
	for k in order_idx:
		cells_sorted.append(canv_cells[k])
		marks_sorted.append(canv_marks[k])
	canv_cells = cells_sorted
	canv_marks = marks_sorted

	var bd2 := -1
	for cell in dist:
		if int(dist[cell]) > bd2 and not canv_cells.has(cell):
			bd2 = int(dist[cell])
			exit_cell = cell
	exit_mark = _doorway(exit_cell)
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


## ПРЕДМЕТЫ вместо меток. Раньше и полотно, и убежище, и выход были одинаковыми
## светящимися коробками разного цвета. Текстура их не спасала: в тёмной комнате
## любой ящик читается как ящик, чем его ни покрой. Форма важнеематериала.
##
## Каждый предмет ГОВОРИТ, что он такое: мольберт — тут рисуют, лежанка — тут
## приходят в себя, проём — отсюда выходят.
func _wood(uv: float, tint: Color) -> StandardMaterial3D:
	return _tex_material("wood", uv, tint)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


## Мольберт: три ноги, перекладина и холст. Возвращается САМ ХОЛСТ — это его
## материал перекрашивает _refresh_marks, когда полотно сдано или следующее.
func _easel(cell: Vector2i) -> MeshInstance3D:
	var root := Node3D.new()
	root.position = cell_to_world(cell, 0.0)
	root.rotation_degrees = Vector3(0, randf_range(-30.0, 30.0), 0)
	add_child(root)
	var wood := _wood(2.2, Color(0.34, 0.28, 0.23))
	_part(root, Vector3(0.06, 1.55, 0.06), Vector3(-0.34, 0.78, 0.10), wood, Vector3(6, 0, 8))
	_part(root, Vector3(0.06, 1.55, 0.06), Vector3(0.34, 0.78, 0.10), wood, Vector3(6, 0, -8))
	_part(root, Vector3(0.06, 1.5, 0.06), Vector3(0.0, 0.75, -0.32), wood, Vector3(-14, 0, 0))
	_part(root, Vector3(0.86, 0.07, 0.07), Vector3(0.0, 0.64, 0.08), wood)
	var canvas := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.78, 0.62, 0.04)
	canvas.mesh = cm
	var mat := _tex_material("paper", 1.0, Color(0.42, 0.90, 0.62), 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.22, 1.0, 0.62)
	mat.emission_texture = mat.albedo_texture
	mat.emission_energy_multiplier = 0.55
	canvas.material_override = mat
	canvas.position = Vector3(0.0, 1.02, 0.06)
	canvas.rotation_degrees = Vector3(-8, 0, 0)
	root.add_child(canvas)
	return canvas


## Лежанка: рама из досок и светлая простыня. Здесь приходят в себя после
## поимки, и это должно быть видно с порога.
## ОБСТАНОВКА. Залы отличались друг от друга только числом столов, и лабиринт
## читался одинаковым от начала до конца. Три вида хлама, по одному-двум на зал:
## этого хватает, чтобы комнаты запоминались и по ним можно было ориентироваться.
func _dress_rooms() -> void:
	for k in room_rects.size():
		var tiles: Array[Vector2i] = _room_tiles(room_rects[k])
		tiles.shuffle()
		var put: int = 0
		for t in tiles:
			if put >= 2:
				break
			if canv_cells.has(t) or safe_cells.has(t) or room_cells[k] == t:
				continue
			put += 1
			# Хлам ставим в ПРОТИВОПОЛОЖНУЮ от стола сторону клетки: стол жмётся
			# к стене, и без этого они влезали друг в друга.
			var at: Vector3 = cell_to_world(t) - _table_offset(t)
			match (k + put) % 3:
				0:
					_stool(at)
				1:
					_crates(at)
				_:
					_leaning(at, _table_offset(t))


func _stool(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = Vector3(0, randf() * 360.0, 0)
	add_child(root)
	var wood := _wood(1.6, Color(0.34, 0.28, 0.23))
	_part(root, Vector3(0.46, 0.07, 0.46), Vector3(0.0, 0.52, 0.0), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part(root, Vector3(0.07, 0.52, 0.07), Vector3(sx * 0.17, 0.26, sz * 0.17), wood)


func _crates(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var wood := _wood(1.4, Color(0.30, 0.25, 0.20))
	var h: float = 0.0
	for i in 2 + (randi() % 2):
		var sz: float = randf_range(0.52, 0.72)
		var box := _part(root, Vector3(sz, sz, sz), Vector3(randf_range(-0.12, 0.12),
			h + sz * 0.5, randf_range(-0.12, 0.12)), wood)
		box.rotation_degrees = Vector3(0, randf_range(-22.0, 22.0), 0)
		h += sz


## Подрамники у стены. Лицом к стене, как ставят то, на что смотреть не хотят.
func _leaning(pos: Vector3, to_wall: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	if to_wall.length() > 0.01:
		root.rotation_degrees = Vector3(0, rad_to_deg(atan2(to_wall.x, to_wall.z)), 0)
	add_child(root)
	var wood := _wood(1.8, Color(0.33, 0.27, 0.22))
	for i in 3:
		var w: float = randf_range(0.55, 0.85)
		var hh: float = randf_range(0.75, 1.15)
		var f := _part(root, Vector3(w, hh, 0.05),
			Vector3(randf_range(-0.20, 0.20), hh * 0.5, -0.10 - float(i) * 0.07), wood)
		f.rotation_degrees = Vector3(randf_range(9.0, 16.0), randf_range(-8.0, 8.0), 0)


## ДВЕРИ. Выходя из зала, ты сейчас просто проваливаешься в очередной проём —
## и зал, и коридор выглядят одинаково. Косяк на границе делает переход
## СОБЫТИЕМ: видно, что ты откуда-то вышел, а не что коридор стал уже.
func _place_doors() -> void:
	var done_pairs := {}
	for k in room_rects.size():
		var tiles: Array[Vector2i] = _room_tiles(room_rects[k])
		var inside := {}
		for t in tiles:
			inside[t] = true
		for t in tiles:
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var n: Vector2i = t + d
				if maze.is_wall(n.x, n.y) or inside.has(n):
					continue
				# Ключ по паре клеток: два соседних тайла зала выходят в один и
				# тот же проход, и без этого косяки вставали друг в друга.
				var key: String = "%d_%d_%d_%d" % [t.x, t.y, n.x, n.y]
				if done_pairs.has(key):
					continue
				done_pairs[key] = true
				_door_frame(t, d)


## Косяк поперёк прохода: два столба, перемычка и приоткрытая створка.
## Створка БЕЗ столкновений — она не должна мешать бежать, она должна
## показывать, что здесь была дверь.
func _door_frame(cell: Vector2i, d: Vector2i) -> void:
	var root := Node3D.new()
	# На саму границу клеток, а не в центр: дверь стоит В ПРОЁМЕ.
	root.position = cell_to_world(cell, 0.0) \
		+ Vector3(float(d.y), 0.0, float(d.x)) * cell_size * 0.5
	# Проход вдоль Z — косяк как есть; вдоль X — развернуть.
	root.rotation_degrees = Vector3(0, 90.0 if d.y != 0 else 0.0, 0)
	add_child(root)
	var wood := _wood(2.4, Color(0.26, 0.21, 0.17))
	var half: float = cell_size * 0.5 - 0.06
	var h: float = 2.95
	_part(root, Vector3(0.20, h, 0.24), Vector3(-half, h * 0.5, 0.0), wood)
	_part(root, Vector3(0.20, h, 0.24), Vector3(half, h * 0.5, 0.0), wood)
	_part(root, Vector3(half * 2.0 + 0.2, 0.26, 0.24), Vector3(0.0, h + 0.13, 0.0), wood)
	# Створка висит на одном столбе и приоткрыта: с закрытой пришлось бы
	# заводить столкновения и открывание, а это другая игра.
	var leaf := Node3D.new()
	leaf.position = Vector3(-half + 0.10, 0.0, 0.0)
	leaf.rotation_degrees = Vector3(0, randf_range(48.0, 74.0) * (1.0 if randf() < 0.5 else -1.0), 0)
	root.add_child(leaf)
	_part(leaf, Vector3(1.05, 2.55, 0.09), Vector3(0.52, 1.30, 0.0),
		_wood(2.0, Color(0.22, 0.18, 0.15)))


func _pallet(cell: Vector2i) -> MeshInstance3D:
	var root := Node3D.new()
	root.position = cell_to_world(cell, 0.0)
	root.rotation_degrees = Vector3(0, randf_range(-25.0, 25.0), 0)
	add_child(root)
	var wood := _wood(2.0, Color(0.30, 0.25, 0.21))
	_part(root, Vector3(1.7, 0.12, 0.10), Vector3(0.0, 0.20, 0.44), wood)
	_part(root, Vector3(1.7, 0.12, 0.10), Vector3(0.0, 0.20, -0.44), wood)
	_part(root, Vector3(0.12, 0.26, 0.98), Vector3(-0.80, 0.13, 0.0), wood)
	_part(root, Vector3(0.12, 0.26, 0.98), Vector3(0.80, 0.13, 0.0), wood)
	var sheet := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.62, 0.10, 0.88)
	sheet.mesh = sm
	var mat := _tex_material("paper", 1.6, Color(0.52, 0.66, 0.86), 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.62, 1.0)
	mat.emission_texture = mat.albedo_texture
	mat.emission_energy_multiplier = 0.30
	sheet.material_override = mat
	sheet.position = Vector3(0.0, 0.30, 0.0)
	root.add_child(sheet)
	return sheet


## Проём: две стойки и перекладина. Не «столб на выходе», а дверь, которой пока
## нет, — её и предстоит нарисовать.
func _doorway(cell: Vector2i) -> MeshInstance3D:
	var root := Node3D.new()
	root.position = cell_to_world(cell, 0.0)
	add_child(root)
	var wood := _wood(2.6, Color(0.32, 0.26, 0.22))
	_part(root, Vector3(0.16, 2.4, 0.16), Vector3(-0.62, 1.2, 0.0), wood)
	_part(root, Vector3(0.16, 2.4, 0.16), Vector3(0.62, 1.2, 0.0), wood)
	_part(root, Vector3(1.5, 0.18, 0.16), Vector3(0.0, 2.34, 0.0), wood)
	var glow := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(1.16, 2.3, 0.03)
	glow.mesh = gm
	var mat := _tex_material("paper", 1.2, Color(0.80, 0.70, 0.40), 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.35)
	mat.emission_texture = mat.albedo_texture
	mat.emission_energy_multiplier = 0.12
	glow.material_override = mat
	glow.position = Vector3(0.0, 1.18, 0.0)
	root.add_child(glow)
	return glow


func _marker(cell: Vector2i, col: Color, h: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.9, h, 0.9)
	mi.mesh = m
	# Не светящийся куб, а холст: бумажная фактура, а цвет уходит в свечение.
	# Куб был виден за сто метров как маяк из другой игры.
	var mat := _tex_material("paper", 1.4, col * 0.85, 0.9)
	mat.emission_enabled = true
	mat.emission = col
	# Свечение идёт ЧЕРЕЗ ТЕКСТУРУ. Сплошная эмиссия не зависит от света и просто
	# заливает поверхность ровным цветом — фактура под ней есть, но её не видно
	# ни с какого расстояния. С картой свечение повторяет волокна бумаги.
	mat.emission_texture = mat.albedo_texture
	mat.emission_energy_multiplier = 0.34
	mi.material_override = mat
	mi.position = cell_to_world(cell, h * 0.5)
	add_child(mi)
	return mi


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# ГОЛОС. Отдельным слоем поверх всего: пока оно говорит, остальной
	# интерфейс гаснет, иначе выходит не «с тобой заговорили», а «выскочило окно».
	voice_ui = VoiceScript.new()
	add_child(voice_ui)
	voice_ui.sfx = sfx
	voice_ui.speaking.connect(_on_speaking)
	says = SaysScript.new()
	add_child(says)
	says.voice = voice_ui
	board = BoardScript.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.visible = false
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.solved.connect(_on_solved)
	board.failed.connect(_on_failed)
	board.mistake.connect(_on_mistake)
	board.abandoned.connect(_on_abandoned)
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
	_ensure_action("read", KEY_E, JOY_BUTTON_Y)
	_ensure_action("journal", KEY_J, JOY_BUTTON_BACK)
	eyes_layer = Control.new()
	eyes_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	eyes_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eyes_layer.draw.connect(_draw_eyes)
	layer.add_child(eyes_layer)
	sprint_bar = Control.new()
	sprint_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	sprint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprint_bar.draw.connect(_draw_sprint)
	layer.add_child(sprint_bar)
	# ВЕКИ. Два чёрных поля сверху и снизу, которые сходятся. Это дешевле любого
	# шейдера и читается именно как глаз, а не как затемнение экрана.
	lid_top = ColorRect.new()
	lid_top.color = Color(0, 0, 0, 1)
	lid_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lid_top.anchor_right = 1.0
	layer.add_child(lid_top)
	lid_bot = ColorRect.new()
	lid_bot.color = Color(0, 0, 0, 1)
	lid_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lid_bot.anchor_right = 1.0
	lid_bot.anchor_top = 1.0
	lid_bot.anchor_bottom = 1.0
	layer.add_child(lid_bot)
	phase_bar = Control.new()
	phase_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	phase_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_bar.draw.connect(_draw_phases)
	layer.add_child(phase_bar)
	# Свой слой с большим номером. В общем layer стартовый экран оказывался ПОД
	# индикаторами и шкалами — их добавляют ниже по коду, а значит рисуют поверх.
	var top := CanvasLayer.new()
	top.layer = 100
	add_child(top)
	pause_ui = PauseScript.new()
	pause_ui.resumed.connect(_on_resume)
	pause_ui.restarted.connect(_restart)
	pause_ui.wiped.connect(_wipe_journal)
	pause_ui.quit_game.connect(_quit)
	pause_ui.quality_changed.connect(apply_quality)
	top.add_child(pause_ui)
	death_ui = DeathScript.new()
	death_ui.restarted.connect(_restart_after_death)
	top.add_child(death_ui)
	credits_ui = CreditsScript.new()
	credits_ui.closed.connect(func() -> void: start_ui.visible = true)
	top.add_child(credits_ui)
	# Жижа на экране поверх всего игрового, но ПОД меню: заляпанный стартовый
	# экран читался бы как сломанная игра.
	goo_rect = ColorRect.new()
	goo_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	goo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = GOO_SHADER
	goo_rect.material = gm
	goo_rect.visible = false
	layer.add_child(goo_rect)

	start_ui = StartScript.new()
	start_ui.started.connect(func() -> void:
		# «Проснуться» ведёт СНАЧАЛА В КОМНАТУ. Оттуда игрок проваливается сюда,
		# и лабиринт начинается уже как продолжение падения, а не с заставки.
		if not RoomScript.done:
			get_tree().change_scene_to_file("res://room.tscn")
		else:
			_on_start())
	# Пришли из комнаты — заставку не показываем второй раз: она уже была. Но
	# ЗАПУСКАЕМ ИГРУ НЕ ЗДЕСЬ. _on_start дёргает _update_hud, а сам hud рождается
	# на сорок строк ниже: при переходе из пролога это падало на первом же кадре
	# — «нельзя присвоить text у Nil». В обычном запуске ошибки не было, потому
	# что там игру запускает кнопка, когда всё уже собрано.
	# «изкомнаты» в командной строке — тот же путь без прохождения пролога:
	# именно на нём и вылезала эта ошибка, а поймать её из стенда было нельзя.
	if RoomScript.done or OS.get_cmdline_user_args().has("изкомнаты"):
		start_ui.skip()
		_from_room = true
	start_ui.viewer.connect(func() -> void:
		get_tree().change_scene_to_file("res://viewer.tscn"))
	# Стартовый экран прячем, пока читают титры: два полноэкранных окна друг
	# на друге спорят за мышь, и кнопки перестают нажиматься.
	start_ui.credits.connect(func() -> void:
		start_ui.visible = false
		credits_ui.open())
	top.add_child(start_ui)
	# Правила читают один раз. После смерти сцена грузится заново, а прочитанное
	# помнит сам экран — он и решает, покаазываться ли.
	if StartScript.seen:
		start_ui.skip()
		started = true
	_load_dev()
	_ensure_action("fullscreen", KEY_F11)
	_ensure_action("thread", KEY_G, JOY_BUTTON_DPAD_UP)
	_pad_menu_keys()
	_ensure_action("devmode", KEY_QUOTELEFT)
	_ensure_action("restart", KEY_R)
	_ensure_action("monline", KEY_M)
	_make_thread_line()
	# ОГОНЁК В КОНЦЕ. Нить показывала дорогу, но не цель: если в конце пусто
	# (полотно далеко и не светится, палочка лежит в темноте), путь читается
	# как «ведёт непонятно куда».
	thread_mark = MeshInstance3D.new()
	var tmm := SphereMesh.new()
	tmm.radius = 0.16
	tmm.height = 0.32
	thread_mark.mesh = tmm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.30, 0.95, 0.62)
	tmat.emission_enabled = true
	tmat.emission = Color(0.22, 1.0, 0.62)
	tmat.emission_energy_multiplier = 2.2
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	thread_mark.material_override = tmat
	thread_mark.visible = false
	add_child(thread_mark)
	hud = Label.new()
	hud.position = Vector2(16, 14)
	hud.add_theme_color_override("font_color", Color(0.48, 0.66, 0.56))
	layer.add_child(hud)
	mad_hud = Label.new()
	mad_hud.position = Vector2(16, 36)
	layer.add_child(mad_hud)
	_update_hud()


## ДОБИВАНИЕ. Единственное на всю игру, и построено на том, что делают с
## КАМЕРОЙ, а не на том, что показывают.
##
## Крови здесь нет и не будет. Подробное потрошение работает всплеском — шок,
## облегчение, а следом любопытство «покажи остальные»; тварь превращается в
## артиста, а артиста не боятся. Плюс вид от первого лица: своего тела игрок не
## видит вовсе, показывать нечего, зато камера И ЕСТЬ жертва. Ужас берётся из
## беспомощности и высоты, остальное достраивает звук.
##
## Заодно это единственный за всю игру взгляд на лабиринт сверху.
func _start_fatality() -> void:
	if player_node == null or monster == null:
		return
	_freeze_player(true)
	fat_stage = 1
	fat_t = 0.55
	fat_roll = 1.0 if _srng.randf() < 0.5 else -1.0
	fat_from = player_node.global_position
	# ОН ПОД ТОБОЙ. Куда бы ни утащило, добивает ком, и он должен быть внизу:
	# иначе игрока поднимает в пустоту.
	var here: Vector2i = world_to_cell(player_node.global_position)
	monster.global_position = cell_to_world(here)
	monster.path.clear()
	monster.mode = "chase"
	monster.stun = 0.0
	monster.visible = true
	monster._grow_out()
	fat_to = monster.global_position + Vector3(0.0, 3.35, 0.0)
	monster.strike_at(player_node.global_position + Vector3(0, 0.9, 0), 9.0)
	if sfx != null:
		# Весь фон уходит на всё добивание: там должно быть слышно только его.
		sfx.amb_duck(4.2)
		sfx.play_at("whip", monster.global_position, 8.0)
		sfx.play("strain", 5.0)
	player_node.shake(3.2, fat_roll)


func _update_fatality(delta: float) -> void:
	if fat_stage == 0 or player_node == null:
		return
	fat_t -= delta
	var head: Node3D = player_node.get_node_or_null("Head")
	if fat_stage == 1:
		# Схватило. Держит внизу, тянет — камера кренится к нему.
		var k: float = 1.0 - clampf(fat_t / 0.55, 0.0, 1.0)
		if head != null:
			head.rotation.z = k * 0.5 * fat_roll
		monster._aim_reach(player_node.global_position + Vector3(0, 1.0, 0))
		if fat_t <= 0.0:
			fat_stage = 2
			fat_t = 1.5
			if sfx != null:
				sfx.play("hit_low", 5.0)
				sfx.play("scream", 5.0)
		return
	if fat_stage == 2:
		# ПОДНИМАЕТ НАД СОБОЙ. Медленно: это и есть весь кадр.
		var k2: float = 1.0 - clampf(fat_t / 1.5, 0.0, 1.0)
		var e2: float = k2 * k2 * (3.0 - 2.0 * k2)
		player_node.global_position = fat_from.lerp(fat_to, e2)
		if head != null:
			# Смотрит вниз, на то, что его держит.
			head.rotation.x = -e2 * 0.85
			head.rotation.z = lerpf(0.5 * fat_roll, 0.12 * fat_roll, e2)
		monster._aim_reach(player_node.global_position)
		if fat_t <= 0.0:
			fat_stage = 3
			fat_t = 1.15
			monster.grab_hold(1.4)
		return
	if fat_stage == 3:
		# ДЕРЖИТ. Щупальца сходятся, кадр медленно поворачивается.
		var k3: float = 1.0 - clampf(fat_t / 1.15, 0.0, 1.0)
		player_node.global_position = fat_to + Vector3(0.0, sin(k3 * PI) * 0.18, 0.0)
		if head != null:
			head.rotation.x = -0.85 + sin(k3 * PI) * 0.10
			head.rotation.z = 0.12 * fat_roll + k3 * 0.30 * fat_roll
		monster._aim_reach(player_node.global_position)
		if fat_t <= 0.0:
			fat_stage = 4
			fat_t = 0.42
			if sfx != null:
				sfx.play("hit_low", 6.0)
				sfx.play("hit_mid", 6.0)
				sfx.play("strain", 6.0)
			player_node.shake(4.0, -fat_roll)
		return
	# РАЗРЫВ. Показывать нечего — кадр рвётся сам: два коротких рывка в разные
	# стороны и обрыв в темноту НА СЕРЕДИНЕ движения. То, чего не показали,
	# зритель достроит сам, и достроит хуже, чем нарисовал бы я.
	var k4: float = 1.0 - clampf(fat_t / 0.42, 0.0, 1.0)
	if head != null:
		head.rotation.z = 0.42 * fat_roll + sin(k4 * PI * 3.0) * 0.55
		head.rotation.x = -0.85 + k4 * 0.7
	if k4 > 0.45:
		_blink_shut(0.9)
	if fat_t <= 0.0:
		fat_stage = 0
		if head != null:
			head.rotation = Vector3.ZERO
		if monster != null:
			monster.drop_hold()
		# И только теперь — скример и экран смерти.
		scare_ui.begin(true, true, _rng.randi())


## КОГДА ЕЙ ЗАГОВОРИТЬ. Здесь только ПОВОДЫ; можно ли сейчас — решает says,
## и он чаще отвечает «нет». Порядок важен: сверху то, что держится на правде о
## самом игроке, — это самые сильные фразы, и им нужно доставаться бюджету
## первыми. Условия и частота расписаны в ЧЕТВЁРТАЯ_СТЕНА.md.
func _update_says() -> void:
	if says == null or player_node == null or dead or won:
		return
	# ДВА РАЗА В СЕКУНДУ, А НЕ КАЖДЫЙ КАДР. Здесь опрашивается системное время и
	# перебирается десяток условий; на кадр это мелочь, но кадр в этой игре мы
	# считали по миллисекундам, и тратить его на то, что меняется раз в минуту,
	# незачем.
	_says_t += get_process_delta_time()
	if _says_t < 0.5:
		return
	_says_t = 0.0
	if _busy() or _attack_busy() or still_t > 0.0:
		return
	if Settings.runs > 1:
		if _away_days >= 1 \
				and says.try_say("v_days", true, [_away_days, Lang.days(_away_days)]):
			return
		if says.try_say("v_waited", true):
			return
		if says.try_say("v_again", true):
			return
	if Settings.deaths == 1 and says.try_say("v_count1"):
		return
	if Settings.deaths >= 2 and says.try_say("v_count2"):
		return
	var hh: int = int(Time.get_datetime_dict_from_system()["hour"])
	if hh >= 2 and hh < 5 and says.try_say("v_night"):
		return
	if _clock > 2400.0 and says.try_say("v_long"):
		return
	# ЗРИТЕЛИ. Один раз за забег и только на ходу: фраза про тех, кто смотрит,
	# должна прилететь посреди обычного коридора, а не в тишине у полотна.
	if _clock > 600.0 and monster != null and monster.mode != "chase" \
			and says.try_say("v_watch"):
		_watch_strike()
		return
	# В ТИШИНЕ. Он далеко, ничего не происходит, игрок просто идёт — тогда
	# фраза останавливает шаг.
	if monster == null or monster.mode == "chase":
		return
	if player_node.global_position.distance_to(monster.global_position) < cell_size * 8.0:
		return
	var quiet: Array = ["v_breath", "v_stop", "v_chase", "v_door", "v_wrong", "v_dark"]
	says.try_say(str(quiet[_srng.randi() % quiet.size()]))


## ОБРЫВОК ШКАТУЛКИ. Тот же мотив, что играл в детской, — но ниже, медленнее и
## только три ноты. Ничего не объясняем: игрок либо узнает его, либо нет.
## Редко нарочно: узнаваемая мелодия, повторённая часто, перестаёт быть находкой.
## ШКАТУЛКА ВОЗВРАЩАЕТСЯ, КОГДА ОН СНАРУЖИ.
##
## В лабиринте не было НИ ОДНОГО тонального слоя: дрон, тритон безумия и удары —
## это фактура, а не музыка, и между ударами ухо слышит тишину. Замер по ролику
## показал это наглядно: во второй половине даже ГРОМЧЕ, чем в начале (−12 дБ
## против −15), а на слух — пусто. Не хватало не громкости, а мелодии.
##
## Берём ту, что уже знакома, — мотив из детской, — и портим её. И включаем
## только пока тварь СНАРУЖИ и близко: тогда мелодия сама становится сообщением,
## а тишина после неё значит «его рядом нет». Играла бы она всё время — стала бы
## обоями, которых через минуту не слышно.
const BOX_LOW := 0.62      ## во сколько раз ниже и медленнее, чем в детской
const BOX_OUT := 0.40      ## громкость, пока он снаружи
const BOX_NEAR := 11.0     ## в клетках: дальше мелодия не идёт


func _update_box(delta: float) -> void:
	if sfx == null or player_node == null or monster == null:
		return
	var out: bool = monster.visible and monster.mode != "inwall" \
		and monster.mode != "surfacing" and monster.mode != "gone"
	var near: bool = player_node.global_position.distance_to(monster.global_position) \
		< cell_size * BOX_NEAR
	sfx.box_pitch(BOX_LOW)
	sfx.box_level(BOX_OUT if (out and near and not dead and not won) else 0.0)
	if dead or won:
		return
	_box_t -= delta
	if _box_t > 0.0 or phase < 2 or _busy() or _attack_busy():
		return
	var d: float = player_node.global_position.distance_to(monster.global_position)
	if d > cell_size * 7.0 or monster.mode == "gone":
		return
	_box_t = _srng.randf_range(180.0, 300.0)
	sfx.box_shard()


## УДАР В КАМЕРУ, А НЕ АТАКА. Ни хвата, ни поимки, ни окна вырывания: оно бьёт
## в объектив и уходит. Спутать это с атакой нельзя — иначе игрок решит, что
## пропустил удар, и пойдёт искать полоску здоровья, которой нет.
func _watch_strike() -> void:
	if player_node == null:
		return
	var at: Vector3 = player_node.global_position
	var fwd: Vector3 = -player_node.global_transform.basis.z
	var side: Vector3 = player_node.global_transform.basis.x
	# Пробуем стены вокруг: щупальце должно вырасти из настоящего камня.
	for d in [side, -side, fwd, -fwd]:
		if _spawn_tent(at, d, 1.4, true):
			break
	player_node.shake(2.8, 0.0)
	_blink_shut(0.30)
	if sfx != null:
		sfx.play("whip", 7.0)
		sfx.play("hit_mid", 3.0)


## Пока тварь говорит, интерфейса нет.
func _on_speaking(on: bool) -> void:
	if hud != null:
		hud.visible = not on
	if mad_hud != null:
		mad_hud.visible = not on


func _update_hud() -> void:
	if done < Shapes.N_CANV:
		hud.text = Lang.t("h_canvas") % [done + 1, Shapes.N_CANV]
	else:
		hud.text = Lang.t("h_findexit")
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

	if pause_ui != null and pause_ui.visible:
		return
	if not started:
		return
	if paused():
		hud.text = Lang.t("h_paused")
		if player_node != null:
			player_node.set_physics_process(false)
		return
	_update_says()
	_update_fatality(delta)
	_update_box(delta)
	# reel_t в условии обязателен: пока тебя тянут, окон не открыто, и эта
	# строка каждый кадр возвращала управление — игрок шёл своими ногами,
	# пока его волокут.
	if player_node != null and not _ui_blocking() and not dead and reel_t <= 0.0 \
			and drop_t <= 0.0 and slam_stage != 1 and slam_stage != 2 and slam_stage < 4:
		_freeze_player(false)
	_update_thread(delta)
	_update_mon_line(delta)
	_update_phase()
	_update_sound(delta)
	_clock += delta
	_update_lash(delta)
	_update_nests(delta)
	_update_safe(delta)
	_update_burst(delta)
	_update_mad_hud()
	_update_marks()
	_update_eyes(delta)
	_update_board_sound(delta)
	if sprint_bar != null:
		sprint_bar.queue_redraw()
	# Полоска фаз НЕ перерисовывалась ни разу за игру: обработчик draw был
	# подключён, а звать его никто не звал. Она рисовалась один раз на нулевом
	# кадре, при нуле ошибок, и так и стояла пустой — сколько бы ты ни ошибался.
	if phase_bar != null:
		phase_bar.queue_redraw()
	_update_ambient()
	_update_drips(delta)
	_update_wall_eyes(delta)
	_update_tents(delta)
	_update_splashes(delta)
	_update_goo(delta)
	_update_climb(delta)
	_update_dropped(delta)
	_update_drop(delta)
	_update_worms(delta)
	_update_mon_lamp()
	_update_blink(delta)
	_update_breath(delta)
	_update_lift(delta)
	_update_slam(delta)
	_update_trap(delta)
	_update_form(delta)
	_update_human_attack(delta)
	_update_still(delta)
	_update_reel(delta)
	# Пока идёт борьба, щупальце по-прежнему держит: иначе оно исчезает ровно
	# тогда, когда должно быть заметнее всего.
	if monster != null and grab_ui != null and grab_ui.visible and grab_src == "monster":
		monster._aim_reach(player_node.global_position + Vector3(0, 0.9, 0))
	if monster != null and player_node != null and not won:
		# Пока игрок рисует, монстр НЕ стоит — он продолжает идти. Но и схватить
		# не может: захват проверяется только когда игрок в коридоре.
		monster.tick(delta, player_node.global_position, anger, done >= Shapes.N_CANV)
		if finale and board.visible:
			board.near = monster.finale_near
			if monster.finale_near >= 1.0:
				board.force_fail()
		elif board.visible:
			_monster_at_canvas(delta)
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
	board.open(shapes[done], done, fear * next_fear_mul, _madness_stage(), _rng.randi())
	next_fear_mul = 1.0
	board.visible = true
	if sfx != null:
		sfx.hum_start()
	_click_t = randf_range(4.0, 9.0)
	if monster != null and player_node != null:
		monster.park(world_to_cell(player_node.global_position), 5)
	_pause_player(true)


## ОН ДОХОДИТ ДО ХОЛСТА. Раньше весь такт обрывался, пока полотно открыто, —
## значит во время рисования игрок был неуязвим, и самое безопасное место в игре
## оказывалось тем, где по замыслу страшнее всего.
##
## Механика уже была написана для финальной двери. Здесь она просто перестаёт
## быть исключением.
func _monster_at_canvas(delta: float) -> void:
	# Пока он в камне — полоски нет. Иначе давление идёт с первой секунды игры
	# и перестаёт что-либо значить.
	var out: bool = monster.mode == "hunt" or monster.mode == "chase" or monster.mode == "roam"
	board.show_near = out
	if not out:
		board.near = 0.0
		return
	var d: float = Vector2(player_node.global_position.x - monster.global_position.x,
		player_node.global_position.z - monster.global_position.z).length()
	board.near = 1.0 - clampf(d / (cell_size * 7.0), 0.0, 1.0)
	if d > MonsterScript.CATCH_DIST:
		return
	# Только что вырвался — не трогает. Та же неуязвимость, что и везде: без неё
	# можно было вырваться из хвата, шагнуть к полотну и тут же быть схваченным
	# снова, уже без единого шанса.
	if player_node.invuln > 0.0:
		return
	# Дошёл. Рисунок срывает — и хватает. Не убивает: раньше это была сразу
	# поимка, без борьбы и без шанса, и три полотна подряд заканчивались смертью
	# просто потому, что рисовать надо стоя на месте. Цена и так высокая:
	# полотно сорвано, страх вырос, и дальше надо ВЫРЫВАТЬСЯ.
	board_torn = true
	board.force_fail()


func _close_board() -> void:
	board.visible = false
	if sfx != null:
		sfx.hum_stop()
	if monster != null:
		monster.unpark()
	_pause_player(false)


func _on_solved() -> void:
	if finale:
		_win()
		return
	done += 1
	fear = 1.0            # полотно сдано — страх отпускает
	# ЕДИНСТВЕННОЕ ОРУЖИЕ ИГРОКА — ПОД СОМНЕНИЕ. Четвёртое полотно — уже
	# привычка, шестое — уверенность; туда и бьём.
	if says != null:
		if board != null and board.time_max > 0.0 \
				and board.time_left > board.time_max * 0.5:
			says.try_say("v_pretty")
		elif done == 4:
			says.try_say("v_doors")
		elif done == 6:
			says.try_say("v_who")
	# Взводим сразу, если следующее полотно и так далеко. Ждать шага в сторону надо
	# только когда цель рядом — иначе игрок мог застрять со снятым взводом.
	canvas_arm = done >= Shapes.N_CANV or not _near(canv_cells[done])
	_close_board()
	_update_hud()
	_refresh_marks()
	if done >= Shapes.N_CANV:
		hud.text = Lang.t("h_noexit")


## Провалил по времени — рисунок осыпался, страх копится и трясёт следующую попытку.
func _on_failed() -> void:
	if says != null and done < canv_fails.size() and int(canv_fails[done]) >= 1:
		says.try_say("v_shake")
	fear = minf(fear + Shapes.FEAR_STEP, Shapes.FEAR_MAX)
	_add_madness(Lang.t("m_torn"))
	if board_torn:
		board_torn = false
		board.visible = false
		_pause_player(false)
		if sfx != null:
			sfx.play_at("roar", monster.global_position, 5.0)
		_grab_now(Lang.t("g_mash"), "monster")
		return
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
	# ПОЛОТНО УХОДИТ. Два провала подряд — и оно перебирается в другое место.
	# Механика была в браузерном прототипе и потерялась при переносе: игрок
	# помнил её, а в Godot полотно просто оставалось стоять.
	if done < canv_fails.size():
		canv_fails[done] += 1
		if canv_fails[done] >= CANV_FLEE:
			canv_fails[done] = 0
			_flee_canvas()
	_close_board()


## Перенести текущее полотно подальше от игрока. И мольберт, и клетка в списке —
## иначе нить продолжит вести на старое место, а полотна там уже нет.
func _flee_canvas() -> void:
	var here := world_to_cell(player_node.global_position)
	var dist: Dictionary = maze.distances(here)
	# Ищем по ВСЕЙ карте, а не по залам. Залов семь, и все они уже заняты
	# полотнами и убежищами — по залам не находилось ни одной клетки, и
	# полотно оставалось стоять, будто механики нет.
	var rooms_free: Array[Vector2i] = []
	var any_free: Array[Vector2i] = []
	for r in maze.size.y:
		for c in maze.size.x:
			if maze.is_wall(r, c):
				continue
			var cell := Vector2i(r, c)
			if canv_cells.has(cell) or safe_cells.has(cell):
				continue
			# Не на другой конец карты: искать полчаса — это не страх, а скука.
			var d: int = int(dist.get(cell, -1))
			if d < 6 or d > 22:
				continue
			# И не вплотную к другому полотну: два мольберта рядом читаются
			# как одно место, и половина поиска пропадает.
			var near_other := false
			for u in canv_cells:
				if absi(u.x - cell.x) + absi(u.y - cell.y) < 5:
					near_other = true
			if near_other:
				continue
			any_free.append(cell)
			if room_cells.has(cell):
				rooms_free.append(cell)
	var pool: Array[Vector2i] = rooms_free if not rooms_free.is_empty() else any_free
	if pool.is_empty():
		return
	var best: Vector2i = pool[_rng.randi() % pool.size()]
	var mark: MeshInstance3D = canv_marks[done]
	var root: Node3D = mark.get_parent()
	root.global_position = cell_to_world(best, 0.0)
	root.rotation_degrees = Vector3(0, randf_range(-30.0, 30.0), 0)
	canv_cells[done] = best
	# Нить пересчитываем немедленно: иначе до трети секунды она ещё показывает
	# дорогу туда, где уже пусто. Ровно это и выглядело как поломка.
	_thread_t = 0.0
	hud.text = Lang.t("h_canv_fled")
	if sfx != null:
		sfx.play("scrape", 2.0)


## Бросил сам — потери нет, кроме начатого рисунка. Это законная тактика, а не
## трусость: за неё не наказывают, иначе выбор перестаёт быть выбором.
func _on_abandoned() -> void:
	_close_board()
	hud.text = Lang.t("h_left")


func _on_mistake() -> void:
	# Щупальце закрывает ту самую точку, на которой промахнулся: последствие,
	# а не запись в счётчике.
	if board != null:
		board.punish()
	_add_madness(Lang.t("m_miss"))


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
	for k in room_cells.size():
		# Столов в зале несколько, но НЕ в соседних клетках: иначе они сливаются
		# в один длинный прилавок. Между занятыми держим хотя бы две клетки.
		var tiles: Array[Vector2i] = _room_tiles(room_rects[k]) if k < room_rects.size() else []
		tiles.shuffle()
		# ГЛАВНЫЙ СТОЛ ЗАЛА — у стены. Середина зала часто открыта со всех
		# сторон, и стол с запиской вставал ровно в проходе. Если середина
		# такая, берём ближайшую клетку, где есть к чему прислониться.
		var main_cell: Vector2i = room_cells[k]
		if not _ok_for_table(main_cell):
			main_cell = Vector2i(-1, -1)
			for t in tiles:
				if _ok_for_table(t):
					main_cell = t
					break
		var placed: Array[Vector2i] = []
		if main_cell.x >= 0:
			placed.append(main_cell)
			# Сдвиг СЧИТАЕТСЯ, а не на глаз: полклетки минус половина стола.
			_add_table(cell_to_world(main_cell) + _table_offset(main_cell),
				order[i % order.size()], false)
			i += 1
		for t in tiles:
			if placed.size() >= TABLES_PER_ROOM:
				break
			var ok := true
			for p in placed:
				# Было 2 клетки — столы всё равно вставали в ряд и читались
				# одним прилавком. Четыре клетки: между ними надо пройти.
				if absi(p.x - t.x) + absi(p.y - t.y) < 4:
					ok = false
					break
			if not ok or not _ok_for_table(t):
				continue
			placed.append(t)
			# Соседние столы в зале — пустые. Записка одна на комнату.
			_add_table(cell_to_world(t) + _table_offset(t), "", false)
	_add_table(cell_to_world(start_cell) + Vector3(0, 0, 0.7), Notes.START_NOTE, true)


## Куда сдвинуть стол внутри клетки. К стене, если стена рядом есть, и всегда
## так, чтобы столешница целиком осталась внутри клетки.
## ЕСТЬ ЛИ КУДА ПРИСЛОНИТЬСЯ. Стол прижимается к стене, и пока стена рядом
## есть, он не мешает: проход остаётся вдоль неё. А в клетке, где открыты все
## стороны, прислониться некуда — стол встаёт посреди прохода.
##
## На перекрёстке это не мелочь. Туда влетают на бегу, когда за спиной тварь, и
## зацепиться там за мебель значит умереть из-за расстановки, а не из-за твари.
## Замер: бот дважды подряд застревал в клетке (14, 9) — перекрёсток со столом.
func _has_wall_side(cell: Vector2i) -> bool:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = cell + d
		if n.x < 0 or n.y < 0 or n.x >= maze.size.y or n.y >= maze.size.x:
			continue
		if maze.grid[n.x][n.y] == 1:
			return true
	return false


## Годится ли клетка под стол. Два запрета, и оба про то, чтобы мебель не
## оказалась там, где её будут задевать: у стола должна быть стена, к которой он
## прижмётся, и он не встаёт на полотно — иначе мольберт и стол в одной точке.
func _ok_for_table(cell: Vector2i) -> bool:
	return _has_wall_side(cell) and not canv_cells.has(cell)


func _table_offset(cell: Vector2i) -> Vector3:
	# полклетки минус половина длинной стороны стола и запас
	var lim: float = cell_size * 0.5 - 0.75 - 0.12
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = cell + d
		if n.x < 0 or n.y < 0 or n.x >= maze.size.y or n.y >= maze.size.x:
			continue
		if maze.grid[n.x][n.y] == 1:
			return Vector3(float(d.y) * lim, 0.0, float(d.x) * lim)
	# Кругом пусто — просто отходим от центра, чтобы не стоять на полотне.
	return Vector3(lim * 0.7, 0.0, lim * 0.7)


## Свободные клетки зала. Нужны, чтобы поставить в комнату НЕСКОЛЬКО столов:
## одна записка на зал читалась как случайность, три — как чьё-то рабочее место.
func _room_tiles(room) -> Array[Vector2i]:
	var step: int = int(maze.corridor) + int(maze.wall)
	var r0: int = int(maze.wall) + int(room.position.y) * step
	var c0: int = int(maze.wall) + int(room.position.x) * step
	var r1: int = int(maze.wall) + (int(room.position.y) + int(room.size.y) - 1) * step
	var c1: int = int(maze.wall) + (int(room.position.x) + int(room.size.x) - 1) * step
	var out: Array[Vector2i] = []
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if r < 0 or c < 0 or r >= maze.size.y or c >= maze.size.x:
				continue
			if maze.grid[r][c] == 0:
				out.append(Vector2i(r, c))
	return out


## Пустой text — стол БЕЗ книжки: мебель, а не находка. Записок всего восемь, а
## столов два десятка; если раздать текст всем, одну и ту же записку прочитаешь
## трижды, и лор перестанет быть лором. Пусть в зале стоит рабочее место, а
## бумага лежит на одном столе из трёх.
func _add_table(pos: Vector3, text: String, wand: bool) -> void:
	if text != "":
		tables.append({"pos": pos, "text": text, "read": false, "wand": wand})
	var top := MeshInstance3D.new()
	var m := BoxMesh.new()
	# Было 0.9 x 0.55 — письменный столик. При глазе на 1.63 он и правда мелкий.
	# Стало 1.6 x 0.9 и ВЫШЕ: столешница на 0.95 вместо 0.78. Разница в
	# семнадцать сантиметров решает всё — стол перестаёт быть подставкой под
	# ногами и попадает в поле зрения, когда идёшь мимо.
	m.size = Vector3(1.6, 0.12, 0.9)
	top.mesh = m
	# Столешница 0.9 x 0.55 м, доски крупные — берём один отрезок текстуры,
	# иначе получится паркет из спичек.
	top.material_override = _tex_material("wood", 1.6, Color(0.42, 0.36, 0.30))
	top.position = pos + Vector3(0, 0.95, 0)
	add_child(top)

	# Стол теперь ТВЁРДЫЙ. Сквозь мебель проходят призраки, а игрок должен её
	# обходить: иначе стол не препятствие, а картинка на полу.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.02, 0.9)
	cs.shape = box
	cs.position = Vector3(0, 0.51, 0)
	body.add_child(cs)
	body.position = pos
	add_child(body)

	# ЧЕТЫРЕ НОГИ И ЦАРГИ, а не один брус посередине. Стол на единственной
	# подпорке читается как тумба: под ним не видно просвета, и вся мебель
	# кажется мелкой независимо от размеров.
	var frame := Node3D.new()
	frame.position = pos
	add_child(frame)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part(frame, Vector3(0.13, 0.89, 0.13),
				Vector3(sx * 0.66, 0.445, sz * 0.33), top.material_override)
	for sz2 in [-1.0, 1.0]:
		_part(frame, Vector3(1.24, 0.09, 0.09), Vector3(0.0, 0.30, sz2 * 0.33),
			top.material_override)

	# Книжка слегка светится: столы стоят в стороне от дороги, и без этого игрок
	# проходит мимо комнаты, ни разу не заглянув внутрь.
	if text == "":
		return
	# КОНТОРКА. Раньше письмо было плоской светящейся коробочкой на столе, и
	# отличить стол с письмом от пустого можно было, только подойдя вплотную.
	# Наклонный пюпитр с листом виден силуэтом через всю комнату и говорит сам:
	# сюда что-то положили, чтобы читали.
	var wood := top.material_override
	var desk := Node3D.new()
	desk.position = pos + Vector3(0, 1.01, 0)
	add_child(desk)
	_part(desk, Vector3(0.62, 0.05, 0.46), Vector3(0.0, 0.13, 0.0), wood,
		Vector3(-26.0, 0.0, 0.0))
	# Бортик снизу ската — иначе лист «лежит» на наклонной плоскости и падает
	# на глаз в никуда.
	_part(desk, Vector3(0.62, 0.06, 0.05), Vector3(0.0, 0.04, 0.20), wood)
	for sx2 in [-1.0, 1.0]:
		_part(desk, Vector3(0.05, 0.22, 0.44), Vector3(sx2 * 0.285, 0.10, 0.0), wood,
			Vector3(-26.0, 0.0, 0.0))
	var mat := _tex_material("paper", 2.0, Color(0.88, 0.85, 0.76), 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.86, 0.7)
	mat.emission_energy_multiplier = 0.5
	var sheet := _part(desk, Vector3(0.40, 0.012, 0.30), Vector3(0.0, 0.17, -0.01),
		mat, Vector3(-26.0, 0.0, 0.0))
	sheet.name = "Sheet"


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
		if wand_lamp != null:
			wand_lamp.visible = true
		if wand_view != null:
			wand_view.visible = true
		if player_node != null:
			player_node.has_wand = true
	if not journal.has(t["text"]):
		journal.append(t["text"])
		Notes.save_journal(journal)
	note_ui.show_note(Notes.say(str(t["text"])))
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


## Заморозить игрока целиком: ни шага, ни поворота, ни рывка, ни вспышки.
## set_physics_process мало — разворот по Q, рывок и вспышка живут в обработчике
## ввода и продолжали срабатывать во время захвата.
func _freeze_player(on: bool) -> void:
	if player_node == null:
		return
	# МЁРТВОГО НЕ РАЗМОРАЖИВАЕМ. Смерть замораживала игрока, но любой путь,
	# зовущий _freeze_player(false) — выход из паузы, закрытие полотна, конец
	# захвата, — возвращал управление. Игрок ходил дальше, а монстр при этом
	# уже не нападал: _on_caught выходит сразу, если dead. Со стороны это
	# читалось как «монстр сломался», хотя сломана была смерть.
	if not on and dead:
		return
	player_node.set_physics_process(not on)
	player_node.set_process_unhandled_input(not on)


## КУРСОР ОСВОБОЖДАЮТ ТОЛЬКО ОКНА, ГДЕ НАДО ЩЁЛКАТЬ, — полотно и записка.
## Захват и скример его не трогают: жмёшь пробел, кликать нечего. Раньше они
## тоже отпускали мышь, состояния накладывались, и курсор жил своей жизнью.
func _pause_player(on: bool) -> void:
	_freeze_player(on)
	_set_cursor(on)


func _unhandled_input(event: InputEvent) -> void:
	# ESC ПЕРВЫМ и без единой зависимости. Если ниже что-то упадёт — не важно что,
	# необработанный null или сломанный узел, — обработчик умрёт целиком, и курсор
	# останется захваченным навсегда. Тогда нельзя ни закрыть окно, ни скопировать
	# текст ошибки, то есть нельзя даже узнать, что сломалось.
	# Esc ТОЛЬКО отпускает и никогда не забирает обратно: возврат к управлению
	# камерой — по щелчку мышью внутри игры. Так эти два действия не спорят.
	# ПОЛНЫЙ ЭКРАН — ПЕРВЫМ и без единого условия: он должен работать и на
	# заставке, и в паузе, и под скримером, и даже когда всё остальное занято.
	if event.is_action_pressed("fullscreen") \
			or (event is InputEventKey and (event as InputEventKey).pressed \
				and (event as InputEventKey).keycode == KEY_ENTER \
				and (event as InputEventKey).alt_pressed):
		Settings.toggle_fullscreen()
		return
	if grab_ui != null and grab_ui.visible:
		if event.is_action_pressed("sprint"):
			grab_ui.press()
		# ВСПЫШКА ВНУТРИ ЗАХВАТА. Она и раньше была на F, но здесь обработчик
		# выходил сразу после пробела — то есть единственный момент, ради
		# которого её и берегут, был единственным, где она не работала.
		elif event.is_action_pressed("flash"):
			_flash_out()
		return
	if start_ui != null and start_ui.visible:
		return
	if event.is_action_pressed("restart"):
		# Экран смерти сам пишет «R — обратно в лабиринт», и клавиша обязана
		# делать ровно то же, что его кнопка. В живой игре R остаётся полным
		# сбросом — это отладочная клавиша, ей так и надо.
		if dead:
			_restart_after_death()
		else:
			_restart()
		return
	if event.is_action_pressed("ui_cancel"):
		# Курсор отпускаем ПЕРВЫМ и без условий — это аварийный выход, он обязан
		# сработать, даже если ниже что-то упадёт.
		_set_cursor(true)
		if note_ui != null and note_ui.visible:
			note_ui.close()
		elif board == null or not board.visible:
			# Поверх полотна пауза не лезет: там ESC — это «отдай мышь», а не «выйди».
			_open_pause()
		return
	# Щелчок по игре снимает паузу. Условие именно paused(), а не «курсор свободен»:
	# при открытом полотне курсор тоже свободен, и клик по точке не должен
	# возвращать захват мыши посреди рисования.
	if event is InputEventMouseButton and event.pressed and paused():
		_set_cursor(false)
	if board != null and board.visible:
		# Бросить холст и бежать. Единственное, что делает приход монстра честным.
		if event.is_action_pressed("read"):
			board.abandon()
		return
	if note_ui == null:
		return
	if event.is_action_pressed("read"):
		if note_ui.visible:
			note_ui.close()
		elif climb_ready and climb_state == 0 and not _busy():
			_start_climb_up()
		elif not _pick_wand():
			_read_table()
	elif event.is_action_pressed("devmode") and Settings.creator_tools():
		# В собранной игре эта клавиша не делает НИЧЕГО. Она стоит на «ё», рядом
		# с Esc и Tab, — по ней попадают случайно, а за ней нить и монстр
		# сквозь стены.
		_toggle_dev()
	elif event.is_action_pressed("thread"):
		thread_on = not thread_on
		_thread_t = 0.0
		hud.text = Lang.t("h_thread_on") if thread_on else Lang.t("h_thread_off")
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
			# Переводим ПРИ ПОКАЗЕ: в самом дневнике лежат русские строки-ключи,
			# и они там и должны лежать — иначе сохранение прошлых забегов
			# перестанет узнаваться после смены языка.
			var shown: Array = []
			for jn in journal:
				shown.append(Notes.say(str(jn)))
			note_ui.show_journal(shown)
			_pause_player(true)
	elif event.is_action_pressed("ui_cancel"):
		if note_ui.visible:
			note_ui.close()
		else:
			_set_cursor(true)


func _on_note_closed() -> void:
	_pause_player(false)


func _ensure_action(action: String, key: int, pad: int = -1) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)
	if pad >= 0:
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad
		InputMap.action_add_event(action, jb)


## ПАУЗА НА ГЕЙМПАДЕ. Отдельно, потому что ui_cancel заводит сам движок, и
## has_action на нём всегда true — обычный путь до него не доходит.
## Не трогаем «B»: он у движка уже значит «отмена», и если повесить на него ещё
## и дневник, меню будет открываться от попытки закрыть записку.
func _pad_menu_keys() -> void:
	for pair in [["ui_cancel", JOY_BUTTON_START]]:
		var a: String = str(pair[0])
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == int(pair[1]):
				return
		var jb := InputEventJoypadButton.new()
		jb.button_index = int(pair[1])
		InputMap.action_add_event(a, jb)


# ─────────────────────────── нить создателя ───────────────────────────

func _make_thread_line() -> void:
	# Не линия, а ЛЕНТА: линию в один пиксель на тёмном полу почти не видно, и
	# по ней не понять, в какую сторону идти.
	thread_line = MeshInstance3D.new()
	thread_line.mesh = ImmediateMesh.new()
	var tm := ShaderMaterial.new()
	tm.shader = THREAD_SHADER
	thread_line.material_override = tm
	thread_line.visible = false
	add_child(thread_line)


## Пересчитываем не каждый кадр: путь по коридорам меняется медленно, а поиск
## по всей карте на каждом кадре — пустая трата.
func _update_thread(delta: float) -> void:
	if not thread_on or player_node == null:
		thread_line.visible = false
		if thread_mark != null:
			thread_mark.visible = false
		return
	_thread_t -= delta
	if _thread_t > 0.0:
		return
	_thread_t = 0.35
	var from := world_to_cell(player_node.global_position)
	if maze.is_wall(from.x, from.y):
		thread_line.visible = false
		return
	# Пока палочка на полу, нить ведёт К НЕЙ. Без фонаря искать её по тёмному
	# лабиринту — это не напряжение, а блуждание: цель всё равно одна.
	var target: Vector2i
	if dropped_wand != null:
		target = world_to_cell(dropped_wand.global_position)
	elif done >= Shapes.N_CANV:
		target = exit_cell
	else:
		target = canv_cells[done]
	var path := _path(from, target)
	if thread_mark != null:
		thread_mark.global_position = cell_to_world(target, 0.9 + sin(_clock * 2.2) * 0.12)
		thread_mark.visible = true
	var mesh: ImmediateMesh = thread_line.mesh
	mesh.clear_surfaces()
	if path.size() < 2:
		thread_line.visible = false
		return
	# Лента строится из четырёхугольников вдоль пути. UV.x — пройденные метры,
	# по ним шейдер гонит метки и гасит нить вдали.
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var run := 0.0
	for i in path.size():
		var here: Vector3 = cell_to_world(path[i], 0.05)
		var nxt: Vector3 = cell_to_world(path[mini(i + 1, path.size() - 1)], 0.05)
		var prv: Vector3 = cell_to_world(path[maxi(i - 1, 0)], 0.05)
		var dir: Vector3 = (nxt - prv)
		dir.y = 0.0
		if dir.length() < 0.001:
			dir = Vector3(0, 0, 1)
		dir = dir.normalized()
		var side: Vector3 = dir.cross(Vector3.UP) * 0.16
		if i > 0:
			run += here.distance_to(prv)
		mesh.surface_set_uv(Vector2(run, 0.0))
		mesh.surface_add_vertex(here - side)
		mesh.surface_set_uv(Vector2(run, 1.0))
		mesh.surface_add_vertex(here + side)
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
	hud.text = Lang.t("h_drawdoor")


## Дорисовал — впервые за всю игру появляется свет. Он бьёт из двери, которую
## игрок только что нарисовал.
func _win() -> void:
	won = true
	if sfx != null:
		sfx.play("win", 4.0, 0.04)
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
	lbl.text = Lang.t("win_text")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.1, 0.09, 0.08))
	lbl.add_theme_font_size_override("font_size", 22)
	flash.add_child(lbl)


## «Заново» из паузы — это НАЧАТЬ СНАЧАЛА: и карта прежняя, и полотна в ноль.
## У смерти путь другой, он ниже.
func _restart() -> void:
	carry_seed = 0
	get_tree().reload_current_scene()


## ПОСЛЕ СМЕРТИ. Новая карта и всё заново.
##
## Сид мешаем со временем, а не берём из _rng: тот к этому моменту прокручен
## забегом, и следующая карта зависела бы от того, сколько раз тебя ловили.
## Незаметно, но это уже не случай, а эхо прошлой попытки.
func _restart_after_death() -> void:
	carry_seed = int(Time.get_unix_time_from_system()) ^ (randi() | 1)
	if carry_seed == 0:
		carry_seed = 1
	get_tree().reload_current_scene()


## Все шесть столбов стояли одинаково зелёными с первой секунды, и понять, какой
## сейчас живой, было нельзя: игрок проходил сквозь дальний и решал, что тот сломан.
## Живой горит ярко, пройденные гаснут, будущие едва тлеют.
func _refresh_marks() -> void:
	for i in canv_marks.size():
		var mat: StandardMaterial3D = canv_marks[i].material_override
		# Сила свечения ЗДЕСЬ перебивала ту, что задана при создании метки, и
		# фактура снова тонула в ровной заливке. Держим её низкой: метку и так
		# видно издалека, а вблизи должно быть понятно, что это вещь.
		if i < done:
			mat.albedo_color = Color(0.20, 0.26, 0.22)
			mat.emission = Color(0.10, 0.16, 0.13)
			mat.emission_energy_multiplier = 0.10
		elif i == done:
			mat.albedo_color = Color(0.42, 0.90, 0.62)
			mat.emission = Color(0.22, 1.0, 0.62)
			mat.emission_energy_multiplier = 0.55
		else:
			mat.albedo_color = Color(0.28, 0.48, 0.36)
			mat.emission = Color(0.16, 0.40, 0.28)
			mat.emission_energy_multiplier = 0.20
	if exit_mark != null:
		var em: StandardMaterial3D = exit_mark.material_override
		var live := done >= Shapes.N_CANV
		em.emission_energy_multiplier = 0.75 if live else 0.12


# ─────────────────────────── монстр ───────────────────────────

func _spawn_monster() -> void:
	monster = MonsterScript.new()
	add_child(monster)
	monster.setup(maze, cell_size, 3.2, _rng.randi())
	monster.place_far_from(start_cell, maze.wall_skin())
	monster.emerged.connect(_on_emerged)
	monster.gave_up.connect(_on_gave_up)
	monster.surfacing.connect(_on_surfacing)
	monster.wall_scare.connect(_on_wall_scare)
	monster.caught.connect(_on_caught)
	monster.wall_hit.connect(_on_wall_hit)
	# Убежища расставляются раньше монстра, поэтому список отдаём и здесь.
	var set3 := {}
	for c3 in safe_cells:
		set3[c3] = true
	monster.safe_cells = set3
	mon_line = _make_line(Color(0.88, 0.35, 0.27))


func _on_emerged() -> void:
	phase = 3
	if monster != null:
		monster.last_phase = true
		monster.allow_emerge = true
	hud.text = Lang.t("h_burst")
	if monster != null:
		_phase_shock(monster.global_position)


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
			# Пока он в камне — это шорох на пределе слышимости, а не скрежет
			# в микрофон. Громким он становится, только когда выходит.
			var quiet: float = 1.0 if phase >= 3 else 0.22
			var vol: float = linear_to_db(clampf(near * hearing * quiet, 0.01, 1.0))
			sfx.play_at("scrape" if phase >= 3 else "skitter", monster.global_position, vol)
		_skit_t = 0.5 + randf() * 1.2 - anger * 0.01

	_heart_t -= delta
	if _heart_t <= 0.0 and d < cell_size * 5.0:
		var k: float = clampf(1.0 - d / (cell_size * 5.0), 0.0, 1.0)
		sfx.play("heart", linear_to_db(clampf(k * 0.55, 0.04, 1.0)), 0.06)
		# Не короче самой записи: «лаб-даб» длится 0.62 с, и при интервале 0.3 с
		# следующий удар обрывал предыдущий на середине — получалась дробь.
		_heart_t = 0.70 + clampf(d / (cell_size * 5.0), 0.0, 1.0) * 0.85

	_breath_t -= delta
	if _breath_t <= 0.0:
		var scare: float = clampf(1.0 - d / (cell_size * 8.0), 0.0, 1.0) * 0.7 + _madness_stage() * 0.15
		if scare > 0.15:
			sfx.play("breath", linear_to_db(clampf(scare * 0.5, 0.05, 1.0)), 0.10)
		_breath_t = clampf(3.4 - scare * 2.4, 0.9, 4.0)


# ─────────────────────────── захват ───────────────────────────

## ОДНА АТАКА ЗА РАЗ. Приёмы у него разные и запускаются из разных мест — удар
## о стену, руки с потолка, язык, подтягивание, хват, — и до сих пор ничто не
## мешало второму начаться поверх первого. Получалась каша: тебя тянут
## щупальцем, и в этот же миг он швыряет тебя в стену.
func _attack_busy() -> bool:
	return slam_stage > 0 or hf_stage > 0 or lift_on or reel_t > 0.0 \
		or still_t > 0.0 or climb_state > 0 \
		or (grab_ui != null and grab_ui.visible)


func _busy() -> bool:
	# Полёт и лежание — занято; а вот когда встал и ищешь палочку, игра идёт
	# как обычно: в этом всё окно и состоит.
	return _ui_blocking() or dead or paused() or still_t > 0.0 \
		or slam_stage == 1 or slam_stage == 2 or slam_stage >= 4 or hf_stage > 0


## Щупальца из стены. Первый раз через 30–50 с, дальше каждые 110–180.
## Половина ударов ПРОМАХИВАЕТСЯ: частота испугов сохранена, а число схваток вдвое
## меньше — утомление убивает страх так же надёжно, как скука.
func _update_lash(delta: float) -> void:
	if _clock < GRACE:
		return
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
	if sfx != null:
		sfx.amb_duck(0.9)
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
	if _attack_busy():
		return
	if seen or tell_miss:
		if sfx != null:
			sfx.play("err", -6.0)
		player_node.shake(0.7, 0.0)
		return
	# Бьющее щупальце ВИДНО, и оно другого цвета. Иначе удар прилетает из ниоткуда
	# при том, что вокруг вьётся два десятка совершенно безобидных.
	if player_node != null:
		var d: Vector3 = tell_pos - player_node.global_position
		d.y = 0.0
		_spawn_tent(player_node.global_position, d, 3.0, true)
	_start_grab(Lang.t("g_wallburst"), "lash")


## Палочка — та же масса, просто в этой форме. Значит и в лезвие она может.
##
## Это не украшение, а ответ на дыру в логике: человек не сильнее твари, которая
## держит его щупальцами, и вырываться голыми руками ему нечем. А ножом — есть.
## Нити ползут по древку снизу вверх и на кончике исчезают, начиная снова
## с рукояти. Ползут ВСЕГДА, не только в захвате: именно поэтому палочка и
## перестаёт выглядеть деревяшкой.
func _update_worms(delta: float) -> void:
	if wand_worms.is_empty() or wand_view == null or not wand_view.visible:
		return
	for wd in wand_worms:
		wd["t"] = fmod(float(wd["t"]) + delta * float(wd["v"]), 1.0)
		var t2: float = float(wd["t"])
		var n: MeshInstance3D = wd["n"]
		# Древко центрировано: от -0.23 у рукояти до +0.23 у кончика.
		var y: float = -0.21 + t2 * 0.42
		# Виток по кругу заодно: нить не просто едет вверх, а обвивает.
		var a: float = float(wd["a"]) + t2 * 3.4
		var r: float = 0.021
		n.position = Vector3(cos(a) * r, y, sin(a) * r)
		# Наружу от оси, с наклоном к кончику — так они «тянутся» вперёд.
		n.rotation = Vector3(deg_to_rad(62.0), a + PI * 0.5, 0.0)
		# У самого кончика втягивается: иначе нити исчезают рывком.
		var fade: float = minf(t2 * 6.0, (1.0 - t2) * 6.0)
		n.scale = Vector3(1, float(wd["len"]) * clampf(fade, 0.05, 1.0), 1)


## Луч по монстру тем сильнее, чем он ближе. Гаснет вместе с палочкой: без неё
## света нет вообще, и он снова только силуэт.
func _update_mon_lamp() -> void:
	# Фонарь палочки тоже. Он светит вперёд узким конусом, и в упор бьёт ровно
	# туда же, куда и подсветка монстра.
	if wand_lamp != null and wand_lamp.visible and monster != null and player_node != null:
		var dm: float = player_node.global_position.distance_to(monster.global_position)
		var near_k: float = 1.0
		if monster.visible and dm < 2.0:
			near_k = clampf((dm - 0.6) / 1.4, 0.30, 1.0)
		# И ВО ВРЕМЯ ХВАТА. Мерить расстояние до самого монстра тут мало: он
		# может стоять в трёх метрах, а его щупальце или язык — упираться в
		# камеру, и фонарь в упор выжигает их в два белых пятна во весь экран.
		# Пока тебя держат, разглядывать всё равно нечего.
		if (grab_ui != null and grab_ui.visible) or reel_t > 0.0 or lift_on:
			near_k = minf(near_k, 0.28)
		wand_lamp.light_energy = player_light * near_k
	if mon_lamp == null or monster == null:
		return
	if not has_wand or not monster.visible:
		mon_lamp.light_energy = 0.0
		return
	var d: float = player_node.global_position.distance_to(monster.global_position) \
		if player_node != null else 99.0
	var k: float = clampf(1.0 - d / monster.LIT_FROM, 0.0, 1.0)
	# Квадрат: далеко — пятно, последние метры — проявляется резко.
	# 20 было посчитано БЕЗ включённого фонаря палочки: я мерил яркость в зонде,
	# где света у игрока не было вовсе. В игре горят оба, и вблизи он выбеливался
	# в бледное пятно вместо чёрной туши.
	var e: float = 1.0 + 9.0 * k * k
	# В УПОР — ГАСИМ. Когда он вплотную (хват, добивание), туша занимает весь
	# экран, и оба луча упираются в неё с полуметра: на снятом кадре вместо
	# монстра было белое пятно во весь экран. Свет там уже не нужен — он и так
	# закрывает собой всё.
	if d < 2.2:
		e *= clampf((d - 0.7) / 1.5, 0.12, 1.0)
	if (grab_ui != null and grab_ui.visible) or reel_t > 0.0 or lift_on:
		e *= 0.25
	mon_lamp.light_energy = e


## АТАКА ФИГУРЫ: РУКИ С ПОТОЛКА. Убежать нельзя — в этом весь смысл: руки
## приходят не от него, а сверху, там, где ты стоишь. Он в это время бежит.
func _start_human_attack() -> void:
	if _attack_busy():
		return
	var mc0: Vector2i = world_to_cell(monster.global_position)
	if maze.is_wall(mc0.x, mc0.y):
		return
	hf_cool = HF_COOL
	hf_stage = 1
	hf_t = HF_HANG
	# СНАЧАЛА ЖЕСТ. Он замирает и тянет руки вверх — и уже оттуда приходят руки
	# с потолка. Без жеста связи между ним и потолком не видно.
	monster.arms_up = 1.0
	monster.ceiling_grab(player_node.global_position, wall_height - 0.2)
	# Замер и рывок вверх: тебя выдёргивают из-под ног.
	lift_on = true
	lift_to = player_node.global_position + Vector3(0, 1.9, 0)
	_freeze_player(true)
	player_node.shake(2.6, 1.0)
	if sfx != null:
		# ПОРЯДОК ВАЖЕН. Сначала РЫК — он идёт из монстра, с той стороны, где
		# он замер: это и есть предупреждение. Потом хлыст сверху и твой крик:
		# руки уже на тебе. Если сложить всё в один момент, слышно кашу.
		sfx.play_at("roar", monster.global_position, 5.0)
		sfx.play("whip", 3.0)
		sfx.play("scream", 4.0)
	hf_step = 0.0
	hud.text = Lang.t("h_hands")


func _update_human_attack(delta: float) -> void:
	hf_cool = maxf(0.0, hf_cool - delta)
	if hf_stage == 0 or player_node == null or monster == null:
		return
	hf_t -= delta
	monster.aim_at = player_node.global_position + Vector3(0, 0.9, 0)
	if hf_stage == 1:
		# ОН БЕЖИТ. Втрое быстрее обычного и по прямой: это не погоня, а
		# развязка — ты уже висишь.
		var to: Vector3 = player_node.global_position
		to.y = monster.global_position.y
		# Скорость берём у самого игрока: «в два с половиной раза быстрее» —
		# это относительно ЕГО хода, иначе число ничего не значит.
		var step: float = player_node.speed * HF_RUSH * delta
		monster.global_position = monster.global_position.move_toward(to, step)
		monster.visible = true
		monster.path.clear()
		monster.gait = fmod(monster.gait + step * 0.55, 1.0)
		# ШАГИ НА БЕГУ. Он бежит по мокрому полу, и по звуку слышно, как быстро
		# он приближается — это единственное, что тебе доступно, пока висишь.
		hf_step -= delta
		if hf_step <= 0.0:
			hf_step = 0.26
			if sfx != null:
				sfx.play_at("step_wet", monster.global_position, -1.0)
		# И дыхание: висящий человек не молчит.
		if sfx != null and randf() < delta * 1.2:
			sfx.play("breath", -5.0)
		var look: Vector3 = monster.global_position - (to - monster.global_position)
		if (to - monster.global_position).length() > 0.15:
			monster.look_at(look, Vector3.UP)
		# Добежал или время вышло — берёт ртом.
		# ЖЕСТ ДЕРЖИТСЯ ПЕРВЫЕ ПОЛСЕКУНДЫ. Я гасил его с первого же кадра, и
		# к моменту, когда на него можно было посмотреть, руки уже опускались:
		# на замере вместо подъёма выходила половина. Сначала тянется — потом
		# бежит, а не одновременно.
		if hf_t < HF_HANG - 0.55:
			monster.arms_up = maxf(0.0, monster.arms_up - delta * 1.6)
		if monster.global_position.distance_to(to) < 1.9 or hf_t <= 0.0:
			hf_stage = 0
			monster.arms_up = 0.0
			monster.ceiling_release()
			# Руки с потолка отпускают — дальше держат ЕГО щупальца изо рта.
			lift_on = false
			if sfx != null:
				# Добежал: тяжёлый удар массы и второй рык уже В УПОР.
				sfx.play("hit_low", 5.0)
				sfx.play_at("roar", monster.global_position, 7.0)
			_start_grab(Lang.t("g_mash"), "monster")
	return


## АТАКА ФИГУРЫ: ЯЗЫК ИЗ ПАСТИ. Выстрел и рывок к себе — коротко и без окна на
## подумать, в отличие от рук с потолка.
func _human_tongue() -> void:
	# ИЗ КАМНЯ НЕ АТАКУЕТ. Он умеет ходить сквозь стены, и если запустить рывок
	# оттуда, игрока тянет В СТЕНУ. Стенд поймал это четыре раза подряд:
	# «игрок ВНУТРИ камня» с координатами всё дальше и дальше.
	var mc: Vector2i = world_to_cell(monster.global_position)
	if maze.is_wall(mc.x, mc.y) or _attack_busy():
		return
	hf_cool = HF_COOL * 0.45
	monster.strike_at(player_node.global_position + Vector3(0, 0.9, 0), 3.0)
	reel_to = monster.global_position
	reel_t = 0.7
	reel_wait = 3.0
	_freeze_player(true)
	if sfx != null:
		# Короткий рык на выдохе, хлыст и крик: у этой атаки нет паузы, значит
		# и звук у неё один слитный удар, а не последовательность.
		sfx.play_at("roar", monster.global_position, 2.0)
		sfx.play_at("whip", monster.global_position, 6.0)
		sfx.play("scream", 3.0)
	hud.text = Lang.t("h_tongue")


## ПРЕВРАЩЕНИЕ. Условия те же, что у засады: редко, на виду и не поверх другой
## сцены. Разница в том, что засада — это событие на секунду, а фигура остаётся
## и ходит: у неё своя походка и свои приёмы, и полминуты — это как раз столько,
## чтобы успеть от неё убежать и понять, что бежал уже не от того, от кого начал.
func _update_form(delta: float) -> void:
	form_cool = maxf(0.0, form_cool - delta)
	if monster == null or player_node == null or phase < 2:
		return
	if forms_left <= 0 or form_cool > 0.0 or dead or won:
		form_want = -1.0
		return
	# ВЗВЕДЕНО — И ДАЛЬШЕ ИГРА ДОБИВАЕТСЯ ВЫХОДА САМА.
	#
	# Раньше здесь стоял список совпадений: он в погоне, ближе пяти клеток, и
	# ты именно на него смотришь. Замер по полному проходу: за весь забег
	# набирался ОДИН СЕКУНДНЫЙ кусок, где сходилось всё, кроме взгляда, — а
	# смотреть на него в этот момент неоткуда, ты от него убегаешь. Оба игрока,
	# которым я давал играть, не увидели вторую форму ни разу.
	#
	# Теперь выход не лотерея, а расписание: игра ждёт удобного момента, а если
	# не дождалась за FORM_WAIT — ставит его перед тобой сама, как это делает
	# засада с ударом о стену. Условие «только в лицо» остаётся: превращение —
	# зрелище, за спиной оно пропадает впустую.
	if form_want < 0.0:
		form_want = 0.0
	form_want += delta
	if _busy() or _attack_busy():
		return
	if monster.form_t > 0.01 or monster.form_hold > 0.0:
		return
	# 1. УДОБНЫЙ МОМЕНТ. Он уже на виду — превращаем на месте.
	var to: Vector3 = monster.global_position - player_node.global_position
	to.y = 0.0
	var fwd: Vector3 = -player_node.global_transform.basis.z
	fwd.y = 0.0
	var mc: Vector2i = world_to_cell(monster.global_position)
	if to.length() <= cell_size * 7.0 and not maze.is_wall(mc.x, mc.y) \
			and to.length() > 0.1 \
			and fwd.normalized().dot(to.normalized()) >= 0.25:
		_take_human_form()
		return
	# 2. НЕ ДОЖДАЛИСЬ. Ставим его в клетку, которую видно, и выводим наружу.
	if form_want < FORM_WAIT:
		return
	var c: Vector2i = _cell_in_view(3.0, 6.0)
	if c.x < 0:
		return
	monster.global_position = cell_to_world(c)
	monster.path.clear()
	monster.mode = "chase"
	monster.chase_t = maxf(monster.chase_t, FORM_LEN)
	monster.visible = true
	monster._grow_out()
	_take_human_form()


func _take_human_form() -> void:
	forms_left -= 1
	form_cool = FORM_COOL
	form_want = -1.0
	monster.take_form(FORM_LEN, monster.FORM_HUMAN)
	if sfx != null:
		sfx.play_at("roar", monster.global_position, 5.0)
	hud.text = Lang.t("h_form")


## Свободная клетка ПЕРЕД ИГРОКОМ, до которой есть прямая видимость. Нужна,
## чтобы поставить тварь туда, где её увидят, а не за угол и не в спину.
## Возвращает (-1, -1), если такой клетки нет — например, игрок уткнулся в тупик.
func _cell_in_view(near_c: float, far_c: float) -> Vector2i:
	var head: Node3D = player_node.get_node_or_null("Head")
	var from: Vector3 = player_node.global_position
	if head != null:
		from = head.global_position
	var fwd: Vector3 = -player_node.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var pc: Vector2i = world_to_cell(player_node.global_position)
	var rad: int = int(ceil(far_c))
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = 100000.0
	for dr in range(-rad, rad + 1):
		for dc in range(-rad, rad + 1):
			var c := Vector2i(pc.x + dr, pc.y + dc)
			if maze.is_wall(c.x, c.y):
				continue
			var wp: Vector3 = cell_to_world(c)
			var to2: Vector3 = wp - player_node.global_position
			to2.y = 0.0
			var d: float = to2.length()
			if d < near_c * cell_size or d > far_c * cell_size or d >= best_d:
				continue
			# Не сбоку и не за спиной: 0.55 — это примерно сорок градусов от
			# направления взгляда, то есть заведомо в кадре.
			if fwd.dot(to2.normalized()) < 0.55:
				continue
			var q := PhysicsRayQueryParameters3D.create(from, wp + Vector3(0.0, 1.0, 0.0))
			if not space.intersect_ray(q).is_empty():
				continue
			best_d = d
			best = c
	return best


## ЗАСАДА. Он в камне вплотную к тебе, ты идёшь мимо — и стена бьёт. Условия
## жёсткие нарочно: только третья фаза, только когда он действительно сидит в
## соседней клетке камня, только на ходу и только если больше ничего не идёт.
## Редкая ловушка запоминается; частая превращается в помеху.
func _update_trap(_delta: float) -> void:
	if monster == null or player_node == null or phase < 3:
		return
	if traps_left <= 0 or slam_cool > 0.0 or _busy() or _attack_busy() or dead or won:
		return
	if monster.mode != "inwall":
		return
	var pc: Vector2i = world_to_cell(player_node.global_position)
	var mc: Vector2i = world_to_cell(monster.global_position)
	# МЕРИМ ТЕМ ЖЕ, ЧЕМ И ОН. Он решает вылезти, когда до игрока остаётся 2.2
	# клетки ПО ПРЯМОЙ, а я считал шагами по сетке: по диагонали это три шага
	# при тех же 2.2 клетки — то есть он выходил из камня раньше, чем условие
	# засады выполнялось, и она не срабатывала ни разу за проход. Теперь порог
	# чуть больше его собственного, и ловушка успевает первой.
	if not maze.is_wall(mc.x, mc.y):
		return
	var fd: float = Vector2(player_node.global_position.x - monster.global_position.x,
		player_node.global_position.z - monster.global_position.z).length()
	if fd > cell_size * 2.6:
		return
	# НА ХОДУ. Стоящего врасплох не застанешь — это уже не засада.
	if player_node.velocity.length() < 1.2:
		return
	_start_slam(mc)


## ЗАСАДА ИЗ КАМНЯ. Он сидит в стене, мимо которой ты идёшь, и бьёт оттуда —
## поперёк коридора, в противоположную стену. Раньше это был приём погони: он
## бежал за тобой и вдруг посреди бега разыгрывал швырок; сцена та же, а
## читалась как сбой.
func _start_slam(from_cell: Vector2i) -> void:
	traps_left -= 1
	slam_cool = SLAM_COOL
	slam_stage = 1
	slam_t = SLAM_FLY
	slam_left = SLAM_WINDOW
	var here := world_to_cell(player_node.global_position)
	# Бьёт ОТ СЕБЯ: из своей стены в противоположную. Так удар читается как
	# «оттуда вылетело и швырнуло меня туда», а не как «меня куда-то дёрнуло».
	var d: Vector2i = here - from_cell
	var to := Vector3(float(d.y), 0.0, float(d.x)).normalized()
	if to == Vector3.ZERO:
		to = (player_node.global_position - monster.global_position).normalized()
		to.y = 0.0
	slam_to = cell_to_world(here, 0.85) + to * (cell_size * 0.5 - 0.45)
	# И ВЫХОДИТ ОН ИЗ ТОЙ САМОЙ СТЕНЫ, а не подбегает откуда-то сбоку.
	slam_from = cell_to_world(from_cell, 0.0)
	monster.global_position = slam_from
	monster.push_n = to
	_freeze_player(true)
	# ТИШИНА ПЕРЕД УДАРОМ. Фон уходит на полторы секунды: пустота бьёт сильнее
	# любого грохота, потому что игрок не понимает, почему подобрался.
	if sfx != null:
		sfx.amb_duck(1.5)
	monster.strike_at(player_node.global_position + Vector3(0, 0.9, 0), 6.0)
	if sfx != null:
		sfx.play_at("whip", monster.global_position, 8.0)
	player_node.shake(3.0, 1.0 if _rng.randf() < 0.5 else -1.0)
	hud.text = Lang.t("h_slam")


func _update_slam(delta: float) -> void:
	slam_cool = maxf(0.0, slam_cool - delta)
	if slam_stage == 0 or player_node == null:
		return
	slam_t -= delta
	slam_left -= delta
	if slam_stage >= 4:
		_slam_finish(delta)
		return
	if slam_stage == 1:
		# Летишь в стену. Быстро, с закруткой.
		var k: float = clampf(1.0 - slam_t / SLAM_FLY, 0.0, 1.0)
		player_node.global_position = player_node.global_position.lerp(slam_to, k * 0.5)
		player_node.head.rotation.z = k * 1.1
		if slam_t <= 0.0:
			slam_stage = 2
			slam_t = SLAM_DOWN
			# Удар. Глаза закрываются, палочка вылетает.
			# Темнеет ДОЛЬШЕ: пока темно, он и вылезает из камня. Мгновенное
			# моргание не давало этой паузы, и он просто оказывался рядом.
			_blink_shut(1.1)
			player_node.shake(3.5, 0.0)
			player_node.shake_long(2.2)
			player_node.down = 1.0
			breath_t = 9.0
			breath_gap = 0.1
			if sfx != null:
				sfx.play("hit_low", 6.0)
				sfx.play("hit_mid", 4.0)
				sfx.play("scream", 6.0)
			_drop_wand()
			# Он не бросается добивать — он ИДЁТ. В этом весь смысл окна.
			monster.stun = 1.4
			monster.mode = "chase"
			monster.chase_t = SLAM_WINDOW + 4.0
			# ВЫЛЕЗАЕТ ИЗ СТЕНЫ. Ставим его в камень за спиной у игрока и
			# ведём наружу сами: пока ты лежишь, из стены выходит туша, и
			# видно, СКОЛЬКО у тебя времени.
			# ИЗ НАСТОЯЩЕЙ СТЕНЫ. Раньше он появлялся просто дальше по коридору
			# и «отжимался» от пустоты: стены за ним не было вовсе. Ищем клетку
			# камня рядом с полом неподалёку и сажаем его внутрь неё.
			slam_from = Vector3.ZERO
			var pc0 := world_to_cell(player_node.global_position)
			for rad in [1, 2, 3]:
				if slam_from != Vector3.ZERO:
					break
				for dr in range(-rad, rad + 1):
					for dc in range(-rad, rad + 1):
						var f := Vector2i(pc0.x + dr, pc0.y + dc)
						if maze.is_wall(f.x, f.y) or absi(dr) + absi(dc) != rad:
							continue
						for d2 in [Vector2i(0, 1), Vector2i(0, -1),
								Vector2i(1, 0), Vector2i(-1, 0)]:
							# Тип ЯВНО: переменная цикла по литералу массива —
							# это Variant, и вывести тип из f + d2 нельзя.
							var w: Vector2i = f + (d2 as Vector2i)
							if not maze.is_wall(w.x, w.y) or slam_from != Vector3.ZERO:
								continue
							slam_from = cell_to_world(w)
							# Наружу из камня — в сторону той самой клетки пола.
							monster.push_n = (cell_to_world(f) - slam_from).normalized()
			if slam_from == Vector3.ZERO:
				var away: Vector3 = player_node.global_position - slam_to
				away.y = 0.0
				slam_from = player_node.global_position \
					+ (away.normalized() if away.length() > 0.1 else Vector3.FORWARD) \
					* cell_size * 1.9
				monster.push_n = (player_node.global_position - slam_from).normalized()
			monster.global_position = slam_from
			monster.visible = true
			# Стена у него за спиной: в неё он и лупит щупальцами, отжимаясь.
			monster.push_at = slam_from - monster.push_n * 0.6
			slam_out = 0.0
		return
	if slam_stage == 2:
		# Лежишь. Управление возвращаем ДО того, как он подойдёт: искать палочку
		# надо самому, иначе это не окно, а ролик.
		player_node.head.rotation.z = lerpf(player_node.head.rotation.z, 0.35, delta * 3.0)
		# Замороженному игроку голову никто не двигает — опускаем сами, иначе
		# «лежит на полу» видно только после того, как встанешь.
		player_node.head.position.y = 0.42
		if slam_t <= 0.0:
			slam_stage = 3
			player_node.head.rotation.z = 0.0
			_freeze_player(false)
			# Встаёт не сразу и хромает: удар должен идти за тобой дальше.
			player_node.limp = 1.0
			hud.text = Lang.t("h_slam_up")
		return
	# Встал. Поднимаемся на ноги и ждём развязки.
	player_node.down = maxf(0.0, player_node.down - delta * 0.7)
	# Он всё это время ВЫХОДИТ: медленно, по прямой, и смотрит на тебя. Его
	# обычная логика тут отключена — иначе он уходит бродить по коридорам, и
	# сцена превращается в паузу.
	if monster != null and slam_left > 0.0:
		var to_p: Vector3 = player_node.global_position
		to_p.y = 0.0
		var from2: Vector3 = Vector3(slam_from.x, 0.0, slam_from.z)
		# РЫВКАМИ, А НЕ РОВНО. Каждый упор — толчок: первые пятую часть цикла
		# он выдавливается, остальное перехватывается. Ровное движение читалось
		# как «проехал сквозь стену».
		var g: float = fmod(monster.gait, 0.5)
		var burst: float = 2.6 if g < 0.11 else 0.18
		# ТОЛЬКО ПОЛОВИНА ТУШИ. Коридор в одну клетку: выйти во весь рост он
		# может, лишь перекрыв его собой, — тогда не видно ни его, ни дороги.
		# Он остаётся торчать из камня, и этого хватает.
		slam_out = clampf(slam_out + delta * 0.16 * burst, 0.0, 0.35)
		monster.global_position = from2.lerp(to_p, slam_out)
		monster.visible = true
		monster.path.clear()
		monster.gait = fmod(monster.gait + delta * 0.55, 1.0)
		# Стена остаётся там, где была: он отходит от неё, а не тащит её с собой.
		# Стену он не отпускает: он из неё и не выходит до конца.
		var look: Vector3 = monster.global_position - (to_p - monster.global_position)
		if (to_p - monster.global_position).length() > 0.1:
			monster.look_at(look, Vector3.UP)
	if slam_left <= 0.0:
		# ВРЕМЯ ВЫШЛО. Он не идёт к тебе — он ТЯНЕТ ТЕБЯ К СЕБЕ щупальцем: сам
		# он торчит из камня и целиком оттуда не выходит. Дальше вдавит в стену.
		slam_stage = 4
		slam_t = 0.9
		_freeze_player(true)
		monster.strike_at(player_node.global_position + Vector3(0, 0.9, 0), 3.0)
		if sfx != null:
			sfx.play_at("whip", monster.global_position, 6.0)
			sfx.play("scream", 4.0)
		player_node.shake(2.2, 1.0)
		hud.text = Lang.t("h_slam_pull")


## Притянул и вдавливает. Отсюда и берётся то, что случается потом: тебя
## продавливают СКВОЗЬ камень, а выбрасывает уже в другом месте — вниз головой.
func _slam_finish(delta: float) -> void:
	var full: float = 0.9 if slam_stage == 4 else 0.8
	var k: float = 1.0 - clampf(slam_t / full, 0.0, 1.0)
	if slam_stage == 4:
		var to: Vector3 = monster.global_position
		to.y = 0.85
		player_node.global_position = player_node.global_position.lerp(to, delta * 5.0)
		# Целим МИМО головы: щупальце, направленное точно в камеру, видно как
		# обрубок в лицо — ровно то, что читалось «облизал».
		var beside: Vector3 = player_node.global_transform.basis.x * 0.5
		monster._aim_reach(player_node.global_position + Vector3(0, 1.0, 0) + beside)
		player_node.head.rotation.z = sin(k * PI) * 0.22
		if slam_t <= 0.0:
			slam_stage = 5
			slam_t = 0.8
			if sfx != null:
				sfx.play("hit_low", 6.0)
				sfx.play("strain", 5.0)
		return
	# Вдавливает в камень: летишь спиной вперёд, темнеет.
	player_node.global_position = player_node.global_position.lerp(slam_to, delta * 7.0)
	player_node.head.rotation.z = k * 0.9
	if k > 0.45:
		_blink_shut(0.6)
	if slam_t <= 0.0:
		_end_slam()
		player_node.head.rotation.z = 0.0
		if sfx != null:
			sfx.play("hit_mid", 6.0)
			sfx.play("scream", 6.0)
		_capture("monster")


## Кончить сцену: и по вспышке, и по времени.
func _end_slam() -> void:
	slam_stage = 0
	if monster != null:
		monster.end_push()
		# УХОДИТ В КАМЕНЬ ПОСЛЕ УДАРА. Из стены он выходит только наполовину, и
		# когда сцена кончалась, эта половина оставалась ТОРЧАТЬ из породы —
		# видимая туша внутри камня, пока что-нибудь другое случайно не уберёт
		# её оттуда. Стенд ловил это каждым проходом третьей фазы.
		var mc4: Vector2i = world_to_cell(monster.global_position)
		if maze.is_wall(mc4.x, mc4.y):
			monster.retreat_to_wall(5.0, 11.0)
	slam_t = 0.0
	slam_left = 0.0
	if player_node != null:
		player_node.down = 0.0
		player_node.head.rotation.z = 0.0


## ПОДНИМАЕТ И СЖИМАЕТ. Раньше захват был щупальцами поверх экрана — картинка,
## из которой не следует, что с тобой делают. Теперь он ОТРЫВАЕТ ТЕБЯ ОТ ПОЛА:
## земля уходит вниз, тебя качает, и щупальца сходятся тем плотнее, чем дольше
## ты в хвате. Отсюда и крик — понятно, отчего кричать.
func _update_lift(delta: float) -> void:
	if player_node == null:
		return
	# Ушёл в камень — значит отпустил. Держать, сидя в стене, он не может:
	# рук снаружи нет.
	if lift_on and monster != null:
		var mc3: Vector2i = world_to_cell(monster.global_position)
		if maze.is_wall(mc3.x, mc3.y):
			lift_on = false
			monster.drop_hold()
	# Высота хвата — от точки, в которой смыкаются руки, а не от числа: он
	# держит тебя у себя над головой, а не «на полтора метра выше пола».
	var want: float = LIFT_H
	if lift_on and lift_to != Vector3.ZERO:
		want = maxf(0.6, lift_to.y - 0.9 - 0.85)
	if not lift_on:
		want = 0.0
	# Вверх МЕДЛЕННО, вниз рывком: подъём — это то, что с тобой делают, а
	# падение случается само.
	var v: float = 0.85 if lift_on else 5.5
	var was_up: bool = lift_y > 0.0
	lift_y = move_toward(lift_y, want, delta * v)
	if lift_y <= 0.0 and not lift_on:
		# Доводим ровно на пол один раз. Без этого последняя запись высоты
		# оставалась на полпути, гравитации у игрока нет, и он так и оставался
		# висеть на двадцать сантиметров выше — навсегда.
		if was_up:
			player_node.global_position.y = 0.85
			player_node.head.rotation.z = 0.0
			player_node.head.rotation.x = 0.0
		return
	# Пока висишь, физика игрока выключена захватом, поэтому высоту ставим сами.
	player_node.global_position.y = 0.85 + lift_y
	# И по горизонтали затягивает к себе: висеть в стороне от колец нельзя.
	if lift_on and lift_to != Vector3.ZERO:
		# И ЗДЕСЬ НЕ В КАМЕНЬ. Подъём тянет игрока к точке держания по
		# горизонтали, а точка эта — на монстре; он же ходит сквозь стены.
		# Стенд поймал: игрок в клетке (15,21), монстр в (30,42), и та клетка
		# камень. Тащило прямо в породу, без единой проверки.
		var flat: Vector3 = Vector3(lift_to.x, player_node.global_position.y, lift_to.z)
		var nxt2: Vector3 = player_node.global_position.lerp(flat, delta * 1.6)
		var nc2: Vector2i = world_to_cell(nxt2)
		if not maze.is_wall(nc2.x, nc2.y):
			player_node.global_position = nxt2
	# Пока сжимает — кричит снова и снова. Реже, чем бьётся сердце, иначе это
	# превращается в вой без пауз.
	if lift_on:
		strain_t -= delta
		if strain_t <= 0.0:
			strain_t = randf_range(2.1, 3.0)
			if sfx != null:
				sfx.play("strain", 2.0)
	var k: float = lift_y / LIFT_H
	# Качает и заваливает: висящего человека не держат ровно.
	player_node.head.rotation.z = sin(_clock * 1.7) * 0.13 * k
	player_node.head.rotation.x = -0.30 * k + sin(_clock * 2.3) * 0.05 * k


## МОРГАНИЕ. Веки сходятся и расходятся за пятую долю секунды. Чем выше безумие,
## тем чаще: дыхание учащается, и моргание вместе с ним.
func _update_blink(delta: float) -> void:
	if lid_top == null:
		return
	if blink_dir == 0.0:
		blink_t -= delta * (1.0 + float(_madness_stage()) * 0.45)
		if blink_t <= 0.0:
			blink_dir = -1.0
	else:
		if blink_hold > 0.0 and blink_p >= 1.0:
			blink_hold -= delta
			return
		# Закрывается быстрее, чем открывается: так моргают на самом деле.
		# Знак берётся ПРЯМО из направления: домножение на -blink_dir делало обе
		# фазы положительными, и веки, раз закрывшись, больше не открывались —
		# на замере 400 кадров подряд глаза были закрыты.
		blink_p += delta * (7.0 if blink_dir < 0.0 else -4.6)
		if blink_p >= 1.0:
			blink_p = 1.0
			blink_dir = 1.0
		elif blink_p <= 0.0:
			blink_p = 0.0
			blink_dir = 0.0
			blink_t = randf_range(BLINK_GAP[0], BLINK_GAP[1])
	var h: float = get_viewport().get_visible_rect().size.y * 0.5 * blink_p
	lid_top.offset_bottom = h
	lid_bot.offset_top = -h


## Закрыть глаза принудительно — на удар о стену и на смерть.
func _blink_shut(hold: float) -> void:
	blink_p = 1.0
	blink_dir = 1.0
	blink_hold = hold


## ОТДЫШКА. После рывка человек не может просто побежать дальше. Звук идёт
## реже и тише с каждым разом — усталость отпускает, а не выключается.
func _update_breath(delta: float) -> void:
	if breath_t <= 0.0:
		return
	breath_t -= delta
	breath_gap -= delta
	if breath_gap <= 0.0:
		breath_gap = 1.05
		if sfx != null:
			sfx.play("breath", -6.0 - (5.0 - minf(breath_t, 5.0)))


func _on_sprint_ended() -> void:
	breath_t = 5.2
	breath_gap = 0.25


func _wand_blade(on: bool) -> void:
	if wand_mesh == null:
		return
	if on:
		# Вытягивается и сплющивается: та же масса, перелитая в лезвие.
		wand_mesh.scale = Vector3(0.42, 1.55, 1.25)
		wand_mesh.rotation_degrees = Vector3(-96.0, 0.0, -3.0)
		if wand_bead != null:
			# Лезвие тянет массу к острию — точка разгорается.
			wand_bead.scale = Vector3(1.6, 1.6, 1.6)
	else:
		wand_mesh.scale = Vector3.ONE
		wand_mesh.rotation_degrees = Vector3(-72.0, 0.0, -6.0)
		if wand_bead != null:
			wand_bead.scale = Vector3.ONE


## Развилка. От МОНСТРА вырываются всегда — он держит тебя сам, и пережидать
## тут нечего. Щупальца же сначала шарят: если стоять неподвижно, они проходят
## мимо. Срабатывает редко, иначе это перестаёт быть неожиданностью.
func _start_grab(text: String, src: String) -> void:
	if _busy():
		return
	# НЕУЯЗВИМОСТЬ ДЕЙСТВУЕТ НА ВСЁ. Вырвался — и 3.2 с тебя не трогают: это
	# окно, чтобы отбежать, найти палочку, вообще понять, что произошло. Но
	# проверяли её лишь три вызова из восьми: щупальца из стены, добивание
	# монстра и рывок языком хватали прямо сквозь неё. На третьей фазе, где он
	# ходит снаружи постоянно, из этого получалась цепочка хватов без единого
	# промежутка — стенд насчитал их семьсот за проход.
	if player_node != null and player_node.invuln > 0.0:
		return
	if src != "monster" and _clock > GRACE and _rng.randf() < STILL_CHANCE:
		still_t = STILL_TIME
		still_text = text
		still_src = src
		hud.text = Lang.t("h_still")
		if sfx != null:
			sfx.play("scrape", -2.0)
		if player_node != null:
			player_node.shake(0.7, 0.0)
		return
	_grab_now(text, src)


## Окно «замри». Игрока НЕ замораживаем: весь смысл в том, что двинуться можно,
## и именно это тебя и выдаёт.
func _update_still(delta: float) -> void:
	if still_t <= 0.0 or player_node == null:
		return
	still_t -= delta
	var moved: bool = Input.get_vector("left", "right", "forward", "back").length_squared() > 0.0
	if moved:
		var t2: String = still_text
		var s2: String = still_src
		still_t = 0.0
		_grab_now(t2, s2)
		return
	if still_t <= 0.0:
		still_t = 0.0
		hud.text = Lang.t("h_still_ok")
		if sfx != null:
			sfx.play("breath", -4.0)


func _grab_now(text: String, src: String) -> void:
	if _busy():
		return
	grab_src = src
	var loud := _roll_scare(src)
	_freeze_player(true)
	# ВСЕГДА ВЫРЫВАТЬСЯ. Был режим «не шевелись», в котором любое нажатие
	# считалось провалом. Он ломал главное чувство момента: из щупалец надо
	# ВЫДИРАТЬСЯ, а не пережидать, пока отпустят.
	# Петли рисуем только для щупалец из стен: монстр обвивает настоящими руками.
	grab_ui.coils = src != "monster"
	grab_ui.begin(text, loud, _rng.randi(), _madness_stage())
	# В захвате рука с палочкой ОСТАЁТСЯ видна, и палочка становится лезвием:
	# иначе непонятно, чем игрок вообще отбивается.
	if wand_view != null and has_wand:
		wand_view.visible = true
		_wand_blade(true)
	if sfx != null:
		sfx.hit(8.0 if loud else 3.0)
		# Голос. Он и объясняет, что происходит: без крика захват — это узор
		# на экране, с криком — то, что делают с человеком.
		sfx.play("scream", 3.0)
	strain_t = 1.6
	if player_node != null:
		# РЫВОК КАМЕРЫ в момент захвата, а не ровное затемнение: тебя дёрнули.
		player_node.shake(2.4, 1.0 if _rng.randf() < 0.5 else -1.0)
		player_node.shake_long(1.2)
	# Отрывает от пола только МОНСТР. Щупальца из стен коротки — они держат
	# на месте, и поднимать тебя им нечем.
	lift_on = src == "monster"
	if lift_on and monster != null:
		# Он поднимает тебя НАД СОБОЙ и смыкает вокруг четыре руки. Точку
		# держания задаёт он сам — туда и подтягиваем игрока.
		lift_to = monster.grab_hold(9.0)


## Вырвался — он не стоит рядом столбом, а с резким звуком уходит в камень.
## И вылезет снова не сразу: пауза каждый раз своя, чтобы нельзя было отсчитать
## секунды до следующего появления.
## Палочка выбита. Свет гаснет, и её надо найти на полу — последствие, которое
## идёт за тобой из момента, а не кончается вместе с ним. Раньше вырвался и
## пошёл дальше, будто ничего не было.
func _drop_wand() -> void:
	if not has_wand or player_node == null or dropped_wand != null:
		return
	has_wand = false
	player_node.has_wand = false
	if wand_lamp != null:
		wand_lamp.visible = false
	if wand_view != null:
		wand_view.visible = false
	# КУДА УПАЛА. Раньше бралось случайное направление на 1.2-2.6 м без единой
	# проверки — а коридор шириной в одну клетку, и палочка регулярно улетала
	# ВНУТРЬ КАМНЯ. Достать её оттуда нельзя ничем: игра молча превращалась в
	# тупик без фонаря. Перебираем направления и оставляем только те, где под
	# ногами пол.
	var here: Vector3 = player_node.global_position
	var good: Array = []
	for i in 16:
		var a2: float = TAU * float(i) / 16.0
		for dd in [1.1, 1.7, 2.3]:
			var q: Vector3 = here + Vector3(cos(a2), 0, sin(a2)) * dd
			var qc: Vector2i = world_to_cell(q)
			if not maze.is_wall(qc.x, qc.y):
				good.append(q)
	var p: Vector3 = good[_rng.randi() % good.size()] if not good.is_empty() \
		else cell_to_world(world_to_cell(here), 0.0)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.045
	cm.height = 0.5
	cm.radial_segments = 8
	mi.mesh = cm
	var mat := _tex_material("wood", 3.0, Color(0.40, 0.34, 0.28))
	# Слабо светится: иначе в полной темноте её не найти вообще, и наказание
	# превращается в тупик.
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.62, 0.72)
	mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	mi.position = Vector3(p.x, 0.10, p.z)
	mi.rotation_degrees = Vector3(90, _rng.randf() * 360.0, 0)
	add_child(mi)
	# Слабый огонёк на самой палочке: без фонаря коридор — чёрный, и лежащий
	# на полу цилиндр не видно с двух метров. Радиус маленький, светит только
	# пятно под собой — это подсказка, а не замена фонарю.
	var gl := OmniLight3D.new()
	gl.light_energy = 0.9
	gl.omni_range = 3.2
	gl.light_color = Color(0.62, 0.72, 0.86)
	gl.position = Vector3(0, 0, 0.18)
	mi.add_child(gl)
	dropped_wand = mi
	hud.text = Lang.t("h_dropped")


## Тянет к себе. Пока тянет — управление отобрано, и это правильно: тебя волокут.
func _update_reel(delta: float) -> void:
	if reel_t <= 0.0 or player_node == null:
		return
	reel_t -= delta
	var to: Vector3 = reel_to - player_node.global_position
	to.y = 0.0
	var d: float = to.length()
	if d > 1.15:
		# СКВОЗЬ КАМЕНЬ НЕ ТЯНЕМ. Игрок в это время заморожен, значит его
		# столкновения не работают вовсе, и позиция ставится напрямую — а
		# монстр вполне может оказаться за стеной. Стенд поймал это трижды
		# подряд: «игрок ВНУТРИ камня» во время рывка языком.
		var step2: Vector3 = to / maxf(d, 0.01) * minf(delta * 6.0, d - 1.15)
		var nxt: Vector3 = player_node.global_position + step2
		var nc: Vector2i = world_to_cell(nxt)
		if maze.is_wall(nc.x, nc.y):
			# Упёрлись в стену — дальше не тянет, хватает там, где достал.
			reel_t = minf(reel_t, 0.05)
		else:
			player_node.global_position = nxt
	# Щупальце всё время держится за тебя, а не висит там, где ты был.
	if monster != null:
		monster._aim_reach(player_node.global_position + Vector3(0, 0.9, 0))
	if reel_t <= 0.0:
		# Дотянул — теперь давит. Но если в этот момент играет скример или
		# открыто полотно, _start_grab молча отказывает, и хват теряется: тебя
		# подтянули и отпустили ни с чем. Ждём, пока чужое окно доиграет.
		if _busy():
			reel_wait -= delta
			if reel_wait > 0.0:
				reel_t = 0.02
				return
			return
		_start_grab(Lang.t("g_mash"), "monster")


## Подобрать палочку по E. Само по себе оно поднимается, когда подойдёшь
## вплотную, но человек, у которого её выбили, первым делом жмёт E — и до сих
## пор ничего не происходило. Радиус здесь больше: раз уж нажал, тянуться не
## заставляем.
func _pick_wand() -> bool:
	if dropped_wand == null or player_node == null:
		return false
	var fl: Vector3 = player_node.global_position - dropped_wand.global_position
	fl.y = 0.0
	if fl.length() > 2.2:
		return false
	_take_wand()
	return true


func _update_dropped(_delta: float) -> void:
	if dropped_wand == null or player_node == null:
		return
	# ПО ГОРИЗОНТАЛИ. Начало координат игрока — середина капсулы, это 0.85 м над
	# полом, а палочка лежит на 0.10. В объёмном замере три четверти метра
	# уходило на разницу высот, и подобрать её можно было, только встав почти
	# ровно сверху.
	var fl: Vector3 = player_node.global_position - dropped_wand.global_position
	fl.y = 0.0
	if fl.length() > 1.0:
		return
	_take_wand()


func _take_wand() -> void:
	dropped_wand.queue_free()
	dropped_wand = null
	has_wand = true
	player_node.has_wand = true
	if wand_lamp != null:
		wand_lamp.visible = true
	if wand_view != null:
		wand_view.visible = true
	if sfx != null:
		sfx.play("ok", -4.0)
	hud.text = Lang.t("h_picked")


func _on_escaped() -> void:
	streak = 0
	lift_on = false
	if monster != null:
		monster.drop_hold()
	if player_node != null:
		player_node.head.rotation.z = 0.0
		player_node.head.rotation.x = 0.0
	_wand_blade(false)
	if monster != null:
		monster.reach_t = 0.25
	# Каждый четвёртый раз вырвался — но без палочки. Уйти из момента совсем
	# без следа нельзя, иначе захват так и остаётся эпизодом, который не жаль.
	if _rng.randf() < 0.25 and not esc_by_flash:
		_drop_wand()
	esc_by_flash = false
	if monster != null:
		if sfx != null:
			sfx.play_at("whip", monster.global_position, 6.0)
			sfx.play("hit_low", 2.0)
		monster.retreat_to_wall(10.0, 26.0)
	if player_node != null:
		player_node.invuln = 3.2
		player_node.shake_long(4.0)
	_freeze_player(false)
	hud.text = Lang.t("h_free")
	_update_hud()


func _on_grab_failed() -> void:
	_wand_blade(false)
	lift_on = false
	if monster != null:
		monster.drop_hold()
	if player_node != null:
		player_node.head.rotation.z = 0.0
		player_node.head.rotation.x = 0.0
	if monster != null:
		monster.reach_t = 0.25
	_capture("lash")


## Два счёта, и это намеренно. streak — поимки подряд чем угодно, сдал полотно и
## прощено. mon_kills — поимки ИМЕННО монстром, и они не прощаются ничем: он
## главная угроза игры, значит он и должен убивать, а не только пугать.
func _capture(src: String) -> void:
	# Форму он принимает В МОМЕНТ БРОСКА. Если делать это после захвата, экран
	# уже перекрыт, и всю работу никто не увидит.
	# Форму НЕ принимает, если это последняя поимка: добивать будет ком, а не
	# фигура, и превращение посреди сцены её же и сломает.
	var last_one: bool = streak + 1 >= DEATH_LIMIT or (src == "monster" and mon_kills + 1 >= DEATH_LIMIT)
	if monster != null and src == "monster" and not last_one:
		monster.take_form(1.3)
	captures += 1
	streak += 1
	_add_madness(Lang.t("m_caught"))
	if src == "monster":
		mon_kills += 1
	anger = mini(MonsterScript.ANGER_MAX, anger + 1)
	var fatal: bool = streak >= DEATH_LIMIT or mon_kills >= DEATH_LIMIT
	var loud: bool = fatal or _roll_scare(src)
	dead = fatal
	if fatal:
		# ДОБИВАНИЕ ВМЕСТО МГНОВЕННОГО ЭКРАНА. Скример подождёт: сначала сцена,
		# и уже из неё — темнота и экран смерти.
		_start_fatality()
	else:
		scare_ui.begin(loud, fatal, _rng.randi())
	if fatal:
		# СЧЁТ ВЕДЁТСЯ МЕЖДУ ЗАПУСКАМИ. Из этого числа потом берётся «два раза,
		# я считаю» — фраза работает только потому, что это правда.
		Settings.note_death()
		# И последнее слово за ней. Вне бюджета и вне пауз: это последнее, что
		# игрок слышит за забег, молчать здесь нельзя из-за счётчика фраз.
		if says != null:
			var last: Array = ["v_f1", "v_f2", "v_f3", "v_f4", "v_f5", "v_f6"]
			says.say_now(str(last[_srng.randi() % last.size()]))
	_freeze_player(true)


func _on_scare_done() -> void:
	if scare_only:
		scare_only = false
		_freeze_player(false)
		_update_hud()
		return
	if dead:
		hud.text = Lang.t("h_dead")
		# Экран, а не строчка в углу. Без него смерть неотличима от поломки.
		if death_ui != null:
			death_ui.open()
		_set_cursor(true)
		return
	if player_node != null:
		# ТЕБЯ ВЫБРОСИЛИ. Раньше после неудачи игрок просто оказывался в
		# ближайшем убежище — то есть прямо в мебели, среди столов, и это
		# читалось как «игра меня телепортировала». Теперь щупальца бросают
		# тебя в коридоре вниз головой и уходят.
		_respawn_drop()
		player_node.invuln = 3.0
		safe_sit = 0.0
		if not ambush_done:
			ambush_t = 5.0
	if monster != null:
		monster.global_position = cell_to_world(_far_cell_from(start_cell))
		monster.stun = 2.5
	_freeze_player(false)
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
	if won or dead or player_node == null:
		return
	# Монстр шлёт сигнал КАЖДЫЙ КАДР, пока ты в его досягаемости. Без этой
	# строки таймер подтягивания взводился заново на каждом кадре и никогда не
	# доходил до нуля: тебя тянуло вечно, а хват так и не начинался.
	if reel_t > 0.0:
		return
	if player_node.invuln > 0.0:
		return
	# ПОДТЯГИВАНИЕ. Щупальце уже на тебе — дальше тебя ТЯНУТ к нему, и только
	# потом начинается борьба. Без этого «дотянулся с трёх метров» читалось бы
	# как «схватил по воздуху».
	# ВО ВРЕМЯ ЗАХВАТА ОН ДОХОДИТ. Раньше здесь стоял _busy(), и пока щупальца
	# держат, монстр не мог тебя тронуть — то есть захват был безопасной паузой,
	# а не опасностью. Отсюда и ощущение обязанности потыкать кнопку.
	# Правило «дошёл во время захвата» относится только к ЧУЖОМУ захвату — когда
	# тебя держат щупальца из стены или гнездо, а он подходит отдельно. Если
	# держит он сам, это правило срабатывало бы в тот же кадр, в который он тебя
	# и схватил: хват мгновенно превращался в поимку, и борьбы не было вообще.
	if grab_ui != null and grab_ui.visible and grab_src != "monster":
		# ПЕРЕХВАТ, А НЕ КАЗНЬ. Здесь стояла немедленная поимка: тебя держат
		# щупальца, он подходит — и всё, экран смерти без единого нажатия. В
		# третьей фазе, где он ходит постоянно, это выглядело как «вышел и
		# сразу убил». Теперь он ОТБИРАЕТ хват себе: прогресс борьбы сгорает,
		# держит уже он, и вырываться надо заново — но вырываться можно.
		grab_ui.visible = false
		grab_ui.set_process(false)
		grab_src = ""
		if player_node != null:
			player_node.shake(2.6, 1.0 if _rng.randf() < 0.5 else -1.0)
		_grab_now(Lang.t("g_mash"), "monster")
		return
	if board.visible or note_ui.visible or scare_ui.visible:
		return
	# ФИГУРА ДЕРЖИТСЯ — у неё свои приёмы.
	if monster.form_kind == monster.FORM_HUMAN and monster.form_t > 0.6 \
			and hf_stage == 0 and hf_cool <= 0.0:
		if _rng.randf() < 0.5:
			_start_human_attack()
		else:
			_human_tongue()
		return
	# УДАРА О СТЕНУ ЗДЕСЬ БОЛЬШЕ НЕТ. Он был приёмом погони: тварь бежала за
	# тобой и вдруг посреди бега разыгрывала целую сцену со швырком. Теперь это
	# ЗАСАДА (см. _update_trap): он ждёт в камне, и стена бьёт, когда идёшь мимо.
	if monster != null and player_node.global_position.distance_to(monster.global_position) > 1.6:
		reel_to = monster.global_position
		# Дольше и ближе, чем было. 0.55 с до 1.4 м проходило почти незаметно —
		# игрок видел, что сдвинулся, но не чувствовал, что его ВОЛОКУТ.
		reel_t = 0.85
		reel_wait = 3.0
		# И главное: щупальце, которое видно. Оно держится весь захват.
		monster.strike_at(player_node.global_position + Vector3(0, 0.9, 0), 7.0)
		if sfx != null:
			sfx.play_at("whip", monster.global_position, 4.0)
		_freeze_player(true)
		return
	_start_grab(Lang.t("g_mash"), "monster")
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
		# Не ближе шестнадцати клеток от старта: игрок должен сперва привыкнуть
		# к украшениям на стенах, а потом уже узнать, что среди них есть живые.
		var deep: bool = int(dist.get(floor_cell, 0)) > 16
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
			# Высота от СТЕНЫ, а не число. Раньше стояло 1.35 — половина стены
			# в 2.9 м. Когда я поднял стены до 4.3, украшения остались внизу и
			# выстроились в ровную линию у колена: розетки в подъезде.
			var y: float = wall_height * 0.46 + randf_range(-0.4, 0.4)
			return {"cell": n, "normal": normal,
				"pos": cell_to_world(cell, y) + normal * (cell_size * 0.5 + 0.02)}
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
func _update_nests(delta: float) -> void:
	nest_gap_t = maxf(0.0, nest_gap_t - delta)
	if _clock < GRACE or nest_gap_t > 0.0:
		return
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
		nest_gap_t = NEST_GAP
		_add_madness(Lang.t("m_nest"))
		if sfx != null:
			sfx.play_at("scrape", nst["pos"], 0.0)
		_start_grab(Lang.t("g_nest"), "nest")
		return


# ─────────────────────────── вспышка ───────────────────────────

## Вспышка не убивает и не оглушает надолго — она ПОКУПАЕТ время и стоит шума.
## Потратил рано — минуту идёшь без неё, а он всё это время подходит.
## БЛИЖАЙШАЯ УГРОЗА, А НЕ ТУША. Проверка «есть ли кого пугать» смотрела только
## на монстра — а бьют тебя часто не им. Щупальце из стены живёт само, и во
## время замаха тело может быть в другом конце лабиринта. Из-за этого на F
## приходило «рядом никого» ровно в тот момент, когда рядом кто-то был и уже
## замахнулся.
##
## Фоновая мелочь, которая вьётся по стенам на третьей фазе, угрозой НЕ считается:
## она ничего не делает, и если считать её, вспышка станет срабатывать всегда.
func _threat_dist() -> float:
	if player_node == null:
		return 1000.0
	var here: Vector3 = player_node.global_position
	var best: float = 1000.0
	if monster != null and monster.mode != "gone":
		best = here.distance_to(monster.global_position)
	if tell_t >= 0.0:
		best = minf(best, here.distance_to(tell_pos))
	for t in tents:
		if float(t["t"]) > 0.0 and bool(t.get("big", false)):
			var n: Node3D = t["node"]
			best = minf(best, here.distance_to(n.global_position))
	return best


## Погасить то, что уже замахнулось. Без этого вспышка срабатывает, а через
## полсекунды тебя всё равно хватает ровно то, что она должна была отогнать.
func _flash_clears_lash() -> void:
	tell_t = -1.0
	for t in tents:
		if float(t["t"]) > 0.0 and bool(t.get("big", false)):
			t["t"] = 0.0
			var n: Node3D = t["node"]
			n.visible = false


func _do_flash() -> void:
	if player_node == null or monster == null or not has_wand:
		# РАЗНИЦА МЕЖДУ «НЕТ» И «ВЫБИЛИ». Здесь всегда говорилось «палочка
		# осталась на столе» — в том числе сразу после удара о стену, когда она
		# лежит в двух метрах и светится. Игроку сообщали, что оружия нет
		# вообще, ровно в тот момент, когда его надо поднять и ударить в упор.
		hud.text = Lang.t("h_dropped") if dropped_wand != null else Lang.t("h_nowand")
		return
	# МОЛЧА ОТКАЗЫВАТЬ НЕЛЬЗЯ. Откат — минута, индикатора заряда нигде нет, и
	# раньше нажатие на пустую вспышку не давало ни звука, ни надписи: для
	# игрока это неотличимо от сломанной клавиши. Ровно так этот баг и был
	# найден — «вспышка не работает».
	if not player_node.flash_charged:
		hud.text = Lang.t("h_charging") % int(ceil(player_node.flash_cd))
		return
	if _threat_dist() > cell_size * 6.0:
		hud.text = Lang.t("h_noone")
		return
	if not player_node.try_flash():
		return
	_flash_clears_lash()
	# Если это была развязка удара о стену — она и есть спасение.
	if slam_stage > 0:
		_end_slam()
		monster.retreat_to_wall(18.0, 34.0)
		_flash_blink()
		if sfx != null:
			sfx.play("door", 5.0)
		hud.text = Lang.t("h_slam_win")
		return
	monster.stun = 3.5
	monster.global_position = cell_to_world(_far_cell_from(world_to_cell(player_node.global_position)))
	monster.path.clear()
	if monster.mode == "hunt":
		monster.mode = "roam"
	if sfx != null:
		sfx.play("door", 4.0)
	_flash_blink()
	hud.text = Lang.t("h_flash")


## Вспышка изнутри захвата: оно отпускает и уходит. Один раз на длинный откат —
## это тот самый козырь, который держат до последнего.
func _flash_out() -> void:
	if player_node == null or not has_wand:
		hud.text = Lang.t("h_dropped") if dropped_wand != null else Lang.t("h_nowand")
		return
	if not player_node.flash_charged:
		hud.text = Lang.t("h_charging") % int(ceil(player_node.flash_cd))
		return
	if not player_node.try_flash():
		return
	_flash_clears_lash()
	_flash_blink()
	if sfx != null:
		sfx.play("door", 4.0)
	if monster != null and grab_src == "monster":
		monster.stun = 4.5
		monster.global_position = cell_to_world(
			_far_cell_from(world_to_cell(player_node.global_position)))
		monster.path.clear()
		if monster.mode == "hunt" or monster.mode == "chase":
			monster.mode = "roam"
	hud.text = Lang.t("h_flash")
	# Палочку при этом НЕ выбивают: иначе размен выходит грабительский —
	# потратил единственный козырь и остался без света.
	esc_by_flash = true
	# Считается за побег: захват кончается тем же путём, что и вырывание, —
	# иначе пришлось бы дублировать всё, что делает _on_escaped.
	if grab_ui != null:
		grab_ui._end(true)


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

## ПЕРВЫЕ СЕКУНДЫ НЕПРИКОСНОВЕННЫ. Игрок стартует ВНУТРИ убежища, а в нём нельзя
## сидеть дольше SAFE_LIMIT — стена трескается и хватает. Получалось, что первый
## удар прилетал через семь секунд после старта, пока ты ещё читаешь записку
## и берёшь палочку. Гнёзда добивали: они стояли всего в восьми клетках.
## До GRACE не бьёт ничего — ни стены, ни гнёзда, ни убежище.
const GRACE := 45.0
const NEST_GAP := 30.0         ## пауза между гнёздами: три подряд — это не страшно
## Точек капели и пауза между каплями в каждой. Реже, но ГРОМЧЕ: редкий звук
## слышно как событие, частый — как помеху, и он забивал хлюпанье пузырей.
const DRIP_POINTS := 22
## Столов в одном зале. Одна записка читалась как случайность, три — как
## чьё-то рабочее место, которое бросили.
const TABLES_PER_ROOM := 2   ## было 3: три стола в зале стоят стеной
const DRIP_GAP := [45.0, 130.0]
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
			_pallet(cell)
			_shelter(cell)
	if safe_cells.size() < 2:
		safe_cells.append(_cell_at_depth(maze.distances(start_cell), 0, 0.5, canv_cells))
	# Отдаём монстру: убежище, в которое он всё равно заходит, — это не убежище,
	# а лежанка. До сих пор он туда ходил, и игрок честно не понимал, где они.
	if monster != null:
		var set2 := {}
		for c2 in safe_cells:
			set2[c2] = true
		monster.safe_cells = set2


## ТЁПЛЫЙ СВЕТ. Вся игра холодная — зелень, чернота, синие полотна. Одно тёплое
## пятно на весь лабиринт читается мгновенно и без единой надписи: сюда можно.
## Раньше убежище было помечено поддоном на полу, и его не замечали вовсе.
func _shelter(cell: Vector2i) -> void:
	var root := Node3D.new()
	root.position = cell_to_world(cell, 0.0)
	add_child(root)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.74, 0.46)
	lamp.light_energy = 2.6
	lamp.omni_range = 7.5
	lamp.position = Vector3(0.0, 2.35, 0.0)
	root.add_child(lamp)
	var wood := _wood(2.0, Color(0.28, 0.23, 0.19))
	# Сам фонарь: без него свет висит из ниоткуда.
	_part(root, Vector3(0.06, 0.75, 0.06), Vector3(0.0, 2.75, 0.0), wood)
	var glass := MeshInstance3D.new()
	var gm2 := BoxMesh.new()
	gm2.size = Vector3(0.28, 0.34, 0.28)
	glass.mesh = gm2
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.95, 0.78, 0.48)
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.78, 0.45)
	gmat.emission_energy_multiplier = 2.4
	glass.material_override = gmat
	glass.position = Vector3(0.0, 2.28, 0.0)
	root.add_child(glass)
	# Круг мелом на полу: граница, внутри которой он не достанет. Её видно и
	# тогда, когда фонарь загорожен телом.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = cell_size * 0.36
	tm.outer_radius = cell_size * 0.40
	tm.rings = 32
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.86, 0.84, 0.78)
	rmat.emission_enabled = true
	rmat.emission = Color(0.9, 0.85, 0.72)
	rmat.emission_energy_multiplier = 0.6
	ring.material_override = rmat
	ring.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(ring)


## Куда бросают. КОРИДОР, а не зал: в зале ты падаешь на столы, и вся сцена
## превращается в недоразумение. И не вплотную к монстру — но и не на другом
## конце карты: он должен прийти, а не искать тебя полчаса.
func _drop_cell() -> Vector2i:
	var from: Vector2i = world_to_cell(monster.global_position) if monster != null \
		else start_cell
	var dist: Dictionary = maze.distances(from)
	var pick: Array[Vector2i] = []
	for r in maze.size.y:
		for c in maze.size.x:
			if maze.is_wall(r, c):
				continue
			var cell := Vector2i(r, c)
			# Коридор — это когда с двух сторон по одной оси камень.
			var corr: bool = (maze.is_wall(r, c - 1) and maze.is_wall(r, c + 1)) \
				or (maze.is_wall(r - 1, c) and maze.is_wall(r + 1, c))
			if not corr or canv_cells.has(cell) or safe_cells.has(cell):
				continue
			var d: int = int(dist.get(cell, -1))
			if d >= 9 and d <= 20:
				pick.append(cell)
	if pick.is_empty():
		return _far_cell_from(start_cell)
	return pick[_rng.randi() % pick.size()]


## Выброс: повис вниз головой, упал, поднялся. Управление на это время отобрано —
## тебя принесли и бросили, участвовать в этом ты не мог.
func _respawn_drop() -> void:
	var cell: Vector2i = _drop_cell()
	player_node.global_position = cell_to_world(cell, 0.85 + DROP_H)
	drop_t = DROP_T
	_freeze_player(true)
	# Крен ставим ПРЯМО голове: пока игрок заморожен, его _move не работает и
	# сам поворот головы не обновляет — а значит и не затрёт наш.
	player_node.head.rotation.z = PI
	hud.text = Lang.t("h_dumped")
	if sfx != null:
		sfx.play("whip", 2.0)


func _update_drop(delta: float) -> void:
	if drop_t <= 0.0 or player_node == null:
		return
	drop_t -= delta
	var k: float = clampf(1.0 - drop_t / DROP_T, 0.0, 1.0)
	# Падение с ускорением: равномерное читается как спуск на лифте.
	player_node.global_position.y = 0.85 + DROP_H * (1.0 - k * k)
	# Переворот отпускает во второй половине — пока летишь, мир ещё вверх ногами.
	player_node.head.rotation.z = PI * clampf((0.62 - k) / 0.62, 0.0, 1.0)
	if drop_t > 0.0:
		return
	drop_t = 0.0
	player_node.global_position.y = 0.85
	player_node.head.rotation.z = 0.0
	player_node.shake(1.7, 0.0)
	if sfx != null:
		sfx.play("hit_low", 3.0)
		sfx.play("step_wet", -1.0)
	_freeze_player(false)


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
	if _clock < GRACE or _busy() or player_node == null:
		return
	var inside := false
	for c in safe_cells:
		if player_node.global_position.distance_to(cell_to_world(c)) < cell_size * 0.9:
			inside = true
			break
	# Вошёл — скажем об этом. Без строки игрок не связывает тёплый свет с тем,
	# что монстр перестал идти.
	if inside and safe_sit <= 0.0:
		hud.text = Lang.t("h_safe")
	safe_sit = safe_sit + delta if inside else 0.0
	if safe_sit >= SAFE_LIMIT and player_node.invuln <= 0.0:
		safe_sit = 0.0
		_start_grab(Lang.t("g_shelter"), "lash")
	# «Безопасные» комнаты безопасны не полностью — один раз за забег.
	if ambush_t > 0.0:
		ambush_t -= delta
		if ambush_t <= 0.0 and not ambush_done:
			ambush_done = true
			_start_grab(Lang.t("g_wall"), "lash")


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

## Звона в ушах БОЛЬШЕ НЕТ. Синусоида на 3100 Гц каждые полсекунды задумывалась
## как последствие глухоты, а звучала как писк прибора: чистый высокий тон ухо
## читает не как ощущение, а как сигнал. Ходьба шумит постоянно, так что пищало
## почти непрерывно со второй фазы.




## Звона в ушах БОЛЬШЕ НЕТ. Синусоида на 3100 Гц каждые полсекунды задумывалась
## как последствие глухоты, а звучала как писк прибора: чистый высокий тон ухо
## читает не как ощущение, а как сигнал. Ходьба шумит постоянно, поэтому со
## второй фазы пищало почти непрерывно.

## Прижался к камню — он оживает. Только со второй стадии безумия: до неё стены
## ещё притворяются стенами.
func _on_wall_touched(seconds: float) -> void:
	if seconds < 1.6 or _madness_stage() < 2 or _busy():
		return
	if player_node == null or player_node.invuln > 0.0:
		return
	player_node.wall_touch = 0.0
	_start_grab(Lang.t("g_alive"), "lash")


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
	# В собранной игре — выключен всегда, чем бы ни был файл рядом.
	if not Settings.creator_tools():
		dev = false
		return
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
## Фазы — КАЖДЫЕ ПЯТЬ ОШИБОК, и полоска наверху заполняется внутри каждой.
## Прежние пороги 2/4/7 срабатывали слишком рано: игрок, который просто
## аккуратно рисует, проваливался во вторую фазу почти сразу.
const PHASE_STEP := 5
const MAD_MAX := 15
## Нижняя граница вида камня: на сколько лабиринт «зелен» при нулевом безумии.
const MAD_FLOOR := 0.07            ## дальше копится не безумие, а ярость
const MAD_STAGE := [5, 10, 15]
## Сколько щупалец может виться одновременно на потолке безумия.
const TENT_MAX := 22
const MAD_SAY := {
	5: "Стены начали шевелиться. Ты перестал его слышать.",
	10: "Стены больше не притворяются стенами.",
	15: "Оно больше не отпускает.",
}

func _add_madness(reason: String) -> void:
	errors += 1
	# Ярость начинает копиться с третьей фазы, а не после потолка безумия:
	# иначе до неё дожили бы единицы.
	if errors > PHASE_STEP * 2:
		anger = mini(MonsterScript.ANGER_MAX, errors - PHASE_STEP * 2)
		if anger == 1 and not mad_said.has("anger"):
			mad_said["anger"] = true
			hud.text = Lang.t("h_angry")
	elif MAD_SAY.has(errors) and not mad_said.has(errors):
		mad_said[errors] = true
		hud.text = str(MAD_SAY[errors])
	else:
		hud.text = reason + " ЛАБИРИНТ ЭТО ЗАПОМНИЛ."
	# Вторая фаза — глухота. Наступает от ошибок: чем хуже лабиринт, тем меньше
	# ты слышишь, а слух — единственное, чем ты его находишь.
	if phase == 1 and errors >= PHASE_STEP:
		phase = 2
		if player_node != null:
			_phase_shock(player_node.global_position - player_node.global_transform.basis.z * -3.0)
	# Третья фаза наступает и по ошибкам тоже: монстр выходит через пару ошибок
	# после второй, не дожидаясь, пока доползёт сквозь камень.
	if phase == 2 and errors >= PHASE_STEP * 2 and monster != null and monster.mode == "inwall":
		monster.allow_emerge = true
		monster.inwall_time = MonsterScript.INWALL_CAP + 1.0
	_apply_madness()


## Безумие видно НЕ только в цифре. Мир темнеет, туман густеет, камень зеленеет —
## иначе шкала остаётся счётчиком в углу, а не ощущением.
## Качество. Применяется НА ЛЕТУ, без перезапуска: игрок должен видеть разницу
## сразу, иначе он не поймёт, что настройка работает, и вернёт как было.
##
## Сетки мешей тут не трогаются — они строятся один раз, и менять их пришлось бы
## пересборкой мира. Гасим то, что считается каждый кадр на каждый пиксель.
## Плотность сеток тут НЕ трогается: меши строятся один раз при запуске мира,
## и поменять их можно только пересборкой. Всё, что ниже, считается каждый кадр
## и применяется сразу.
func apply_quality() -> void:
	var q: int = Settings.quality
	if wall_mat != null:
		wall_mat.set_shader_parameter("detail", [0.0, 0.55, 1.0][q])
		wall_mat.set_shader_parameter("near_dist", [2.0, 2.6, 3.2][q])
	if ceil_mat != null:
		ceil_mat.set_shader_parameter("detail", [0.0, 0.55, 1.0][q])
		ceil_mat.set_shader_parameter("near_dist", [3.0, 4.5, 6.5][q])
	if floor_mat != null:
		floor_mat.set_shader_parameter("relief", [0.0, 0.6, 1.0][q])
	if env_ref != null:
		env_ref.volumetric_fog_enabled = q >= 2
	# Тени. По отдельности каждая мелочь даёт проценты, но на слабой машине
	# складываются именно они: теней нет, тумана нет, мелочи нет, сетка вчетверо
	# реже — вместе это разы, а не проценты.
	if wand_lamp != null:
		wand_lamp.shadow_enabled = q >= 1
	for c in get_children():
		if c is SpotLight3D and c != wand_lamp:
			c.shadow_enabled = q >= 2
	# Щупалец на потолке ярости тоже меньше: каждое — свой меш со своим шейдером.
	tent_cap = [8, 14, TENT_MAX][q]
	# РАЗРЕШЕНИЕ 3D. Самая крупная экономия из всех, и на ретине почти незаметная.
	# Окно во весь экран на такой матрице — это 2560×1600, вчетверо больше
	# пикселей, чем на обычном мониторе тех же размеров, и КАЖДЫЙ из них
	# проходит через шейдер камня. Считать сцену в три четверти и растянуть
	# дешевле любой отдельной правки: цена кадра падает почти линейно по числу
	# пикселей. Интерфейс при этом рисуется в полном разрешении и не мылится.
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = [0.60, 0.78, 1.0][q]


func _apply_madness() -> void:
	# Снизу не ноль, а MAD_FLOOR. При чистом нуле камень мёртвый: прожилки идут
	# через EMISSION * madness, и на нуле их нет вообще — стена просто серая.
	# Ровно это значение (одна ошибка из пятнадцати) держалось всё время из-за
	# фантомного провала полотна, и именно таким лабиринт знаком на вид. Он
	# должен быть живым с первого кадра — а безумие пусть считается от живого.
	var k: float = MAD_FLOOR + (1.0 - MAD_FLOOR) * clampf(float(errors) / float(MAD_MAX), 0.0, 1.0)
	if wall_mat != null:
		wall_mat.set_shader_parameter("madness", k)
	if env_ref != null:
		env_ref.fog_density = fog * (1.0 + k)
		env_ref.ambient_light_energy = ambient * (1.0 - k * 0.35)
	# И ЗВУК ТОЖЕ. Камень, туман и фон едут по одному счётчику: мир портится
	# целиком, а не картинкой отдельно от слуха.
	if sfx != null:
		sfx.amb_madness(k)


func _madness_bar() -> String:
	var st := _madness_stage()
	var bar := ""
	for i in 3:
		bar += "▮" if i < st else "▯"
	var out := "БЕЗУМИЕ " + bar
	if anger > 0:
		out += "  ЯРОСТЬ +" + str(anger)
	return out


# ─────────────────────────── полоска рывка ───────────────────────────

## Рывок — решение, а не рефлекс: потратил рано, и двадцать секунд идёшь пешком,
## пока оно подходит. Но решать можно, только если ВИДНО, сколько осталось.
## Полоска стоит внизу по центру: туда игрок и так смотрит, когда бежит.
func _draw_sprint() -> void:
	if player_node == null or _ui_blocking() or dead:
		return
	var w := 170.0
	var h := 7.0
	var x := (sprint_bar.size.x - w) * 0.5
	var y := sprint_bar.size.y - 58.0
	var f := ThemeDB.fallback_font
	var left: float = player_node.sprint_left
	var cool: float = player_node.sprint_cool
	var frac: float
	var col: Color
	var label: String
	if left > 0.0:
		frac = left / player_node.sprint_time
		col = Color(0.35, 0.95, 0.75)
		label = "РЫВОК  %.1f" % left
	elif cool > 0.0:
		# копится обратно — видно, сколько ещё идти пешком
		frac = 1.0 - cool / player_node.sprint_cd
		col = Color(0.62, 0.30, 0.26)
		label = "ПЕРЕЗАРЯДКА  %.0f" % ceil(cool)
	else:
		frac = 1.0
		col = Color(0.42, 0.58, 0.52)
		label = "РЫВОК ГОТОВ  [ПРОБЕЛ]"
	sprint_bar.draw_rect(Rect2(x, y, w, h), Color(0.06, 0.06, 0.08, 0.75))
	sprint_bar.draw_rect(Rect2(x, y, w * clampf(frac, 0.0, 1.0), h), col)
	sprint_bar.draw_rect(Rect2(x, y, w, h), Color(col, 0.5), false, 1.0)
	sprint_bar.draw_string(f, Vector2(0, y - 6.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, sprint_bar.size.x, 11, Color(col, 0.85))


# ─────────────────────────── полоска фаз ───────────────────────────

## Три куска наверху: сколько прошло каждой фазы. Заливается ЧЁРНЫМ — не растёт
## что-то хорошее, а гаснет что-то, пока ты жив. Перегородки — щупальца:
## разделители между фазами не линия, а то, что тебя ждёт на границе.
## Каждый кусок — своя пятёрка ошибок. Заполнился до конца — фаза сменилась.
## Фон мира. Две причины, по которым он звучит, и обе должны быть слышны:
## третья фаза — постоянное давление, охота — острое. Отстал — уходит, и это
## единственный способ УСЛЫШАТЬ, что тебя больше не ведут.
func _update_ambient() -> void:
	if sfx == null:
		return
	if dead or won:
		sfx.amb_level(0.0)
		return
	var goal: float = 0.0
	if phase >= 3:
		goal = 0.34
	if monster != null:
		match monster.mode:
			"chase":
				goal = 1.0
			"hunt":
				goal = maxf(goal, 0.78)
			"surfacing":
				goal = maxf(goal, 0.55)
	# Пока рисуешь, главный звук — гул полотна. Фон уходит вниз, чтобы два
	# низких гула не смешались в кашу, но не пропадает: он и там про угрозу.
	if board != null and board.visible:
		goal *= 0.35
	sfx.amb_level(goal)


## Экран заливает, когда идёшь ПОД проломом. Натекает быстро, сползает долго:
## стряхнуть такое с лица — дело не одной секунды, и в эти секунды ты слеп.
func _update_goo(delta: float) -> void:
	if goo_rect == null or player_node == null:
		return
	var want := 0.0
	var near: float = 99.0       # до ближайшего пролома, в метрах
	if not (_ui_blocking() or dead or won):
		var p: Vector3 = player_node.global_position
		for h in holes:
			if h == climb_cell:
				continue          # там не льёт, там обвал
			var hp: Vector3 = cell_to_world(h, 0.0)
			var d: float = Vector2(p.x - hp.x, p.z - hp.z).length()
			near = minf(near, d)
			# ЛЬЁТСЯ С ОБОДА, а не из середины: в середине над головой открытое
			# небо, а масса течёт по краям пролома. Поэтому заливает СРАЗУ, как
			# подходишь, а в самой середине её нет — но с глаз она сама не
			# денется, её надо стереть.
			var rim: float = cell_size * 0.52
			want = maxf(want, 1.0 - clampf(absf(d - rim) / (cell_size * 0.48), 0.0, 1.0))
	# Отошёл от пролома — проход засчитан, в следующий раз всё сначала.
	if near > cell_size * 1.3:
		goo_wiped_in = false
		goo_wiped_out = false
	# ПРОТИРАЕТ ГЛАЗА. Два раза за проход: в середине, когда можно поднять
	# голову и увидеть небо, и на выходе, когда с обода заливает снова.
	if goo_wipe <= 0.0 and goo_hold <= 0.0 and goo_amt > 0.45 and not _ui_blocking():
		if not goo_wiped_in and near < cell_size * 0.30:
			goo_wiped_in = true
			_start_wipe()
		elif goo_wiped_in and not goo_wiped_out and near > cell_size * 0.62:
			goo_wiped_out = true
			_start_wipe()
	# Пауза после протирания — только пока он СТОИТ в середине и смотрит вверх.
	# Шагнул к краю — там льёт с обода, и никакая пауза не спасает.
	if near > cell_size * 0.42:
		goo_hold = 0.0
	goo_hold = maxf(0.0, goo_hold - delta)
	if goo_wipe > 0.0:
		goo_wipe = minf(1.0, goo_wipe + delta * 1.55)
		# Пока рука идёт, жижа уходит вместе с ней.
		goo_amt = maxf(0.0, goo_amt - delta * 2.2)
		if goo_wipe >= 1.0:
			goo_wipe = 0.0
			goo_hold = 1.4        # секунду с небольшим видно, потом натечёт снова
		goo_rect.visible = true
		goo_rect.size = get_viewport().get_visible_rect().size
		goo_rect.material.set_shader_parameter("amount", goo_amt)
		goo_rect.material.set_shader_parameter("wipe", goo_wipe)
		return
	goo_rect.material.set_shader_parameter("wipe", 0.0)
	if goo_hold > 0.0:
		want = 0.0
	# Заливает БЫСТРО, сходит долго: стряхнуть такое с лица — дело не секунды.
	var speed: float = 6.0 if want > goo_amt else 0.55
	goo_amt = move_toward(goo_amt, want, delta * speed)
	if goo_amt <= 0.002:
		goo_rect.visible = false
		return
	goo_rect.visible = true
	# Размер задаём явно. Контрол в CanvasLayer не всегда получает его от якорей,
	# и прямоугольник нулевого размера рисует ровно ничего — при том, что все
	# числа выглядят правильными.
	goo_rect.size = get_viewport().get_visible_rect().size
	goo_rect.material.set_shader_parameter("amount", goo_amt)


## Провёл рукой по глазам. Полсекунды не видно ничего, кроме собственной ладони,
## потом видно сквозь разводы. Само по себе это не спасение: с обода льёт дальше.
func _start_wipe() -> void:
	goo_wipe = 0.001
	if sfx != null:
		sfx.play("scrape", -4.0)
		sfx.play("breath", -6.0)
	if player_node != null:
		player_node.shake_amt = maxf(player_node.shake_amt, 0.35)
		player_node.shake_dir = -0.5


## НАСЫПЬ ПОД ПРОЛОМОМ. Ставим у того пролома, который ближе всего к середине
## пути по полотнам: место должно попасться, когда он уже понял правила и ещё не
## идёт к финалу. Одно на игру — второй раз это уже не находка, а декорация.
func _build_climb() -> void:
	if holes.is_empty() or canv_cells.size() < 3:
		return
	# Тот пролом, что лежит на дороге от полотна N/2-1 к N/2 — то есть ровно на
	# том куске пути, который игрок пройдёт в середине игры.
	if climb_cell.x < 0 or not holes.has(climb_cell):
		return
	# КУРГАН, А НЕ ПАНДУС. Длинные скаты (подъём 2.75 м под тридцать градусов)
	# вылезали из клетки на две-три в стороны и вставали поперёк коридора
	# двухметровым бортом: идёшь вдоль ската — поднимаешься, подходишь сбоку —
	# упираешься в стену, которой в темноте не видно. Игрок так и застрял по
	# дороге к пятому полотну.
	#
	# Теперь насыпь целиком внутри своей клетки: четырёхскатный курган в полметра
	# высотой, у краёв сходящий на нет. Через него можно просто перейти с любой
	# стороны, а НАВЕРХ поднимает уже сцена, а не ходьба по пандусу.
	var top: Vector3 = cell_to_world(climb_cell, 0.0)
	climb_b = Vector3(top.x, wall_height - 1.62 - 0.85 + 0.90, top.z)
	climb = Node3D.new()
	climb.position = top
	add_child(climb)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.10, 0.10, 0.11)
	stone.roughness = 1.0
	var half: float = cell_size * 0.5
	var apex: float = MOUND_H
	# Меш: четыре треугольных ската от углов клетки к вершине.
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array = [Vector3(-half, 0.0, -half), Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half), Vector3(-half, 0.0, half)]
	var peak := Vector3(0.0, apex, 0.0)
	for i in 4:
		var c1: Vector3 = corners[i]
		var c2: Vector3 = corners[(i + 1) % 4]
		st2.set_normal((c2 - c1).cross(peak - c1).normalized())
		st2.add_vertex(c1)
		st2.add_vertex(c2)
		st2.add_vertex(peak)
	var mound := MeshInstance3D.new()
	mound.mesh = st2.commit()
	mound.material_override = stone
	climb.add_child(mound)
	# Коллизия — тот же курган выпуклой формой. Ровно по мешу и без единой
	# ступеньки: с любой стороны въезжаешь на него с уровня пола.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var conv := ConvexPolygonShape3D.new()
	conv.points = PackedVector3Array([corners[0], corners[1], corners[2], corners[3],
		peak, Vector3(-half, -0.25, -half), Vector3(half, -0.25, -half),
		Vector3(half, -0.25, half), Vector3(-half, -0.25, half)])
	cs.shape = conv
	body.add_child(cs)
	climb.add_child(body)
	climb_shapes.append(cs)
	# Обломки поверх. Гладкий курган читается насыпью песка, а не обвалом.
	for i in 20:
		var chunk := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = Vector3(_rng.randf_range(0.2, 0.6), _rng.randf_range(0.15, 0.4),
			_rng.randf_range(0.2, 0.6))
		chunk.mesh = cbm
		chunk.material_override = stone
		var rr: float = _rng.randf() * half * 0.92
		var aa: float = _rng.randf() * TAU
		chunk.position = Vector3(cos(aa) * rr, apex * (1.0 - rr / half) - 0.05,
			sin(aa) * rr)
		chunk.rotation = Vector3(_rng.randf() * 0.6, _rng.randf() * TAU, _rng.randf() * 0.6)
		climb.add_child(chunk)
	climb_a = Vector3(top.x, 0.0, top.z)
	# НЕБО НАД ЭТИМ ПРОЛОМОМ — настоящее: далёкое, с солнцем сбоку. Над
	# остальными хватает белого пятна, сюда он полезет смотреть.
	var sky := MeshInstance3D.new()
	var skm := BoxMesh.new()
	skm.size = Vector3(cell_size * 9.0, 0.1, cell_size * 9.0)
	sky.mesh = skm
	var skmat := StandardMaterial3D.new()
	skmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skmat.albedo_color = Color(0.62, 0.74, 0.88)
	# БЕЗ ТУМАНА. Небо в девяти метрах над потолком туман съедал в чёрное: на
	# кадре с вершины насыпи не было видно вообще ничего, при том что голова
	# честно торчала наружу.
	skmat.disable_fog = true
	sky.mesh.surface_set_material(0, skmat)
	sky.position = Vector3(top.x, wall_height + 7.0, top.z)
	add_child(sky)
	var sun := MeshInstance3D.new()
	var sunm := SphereMesh.new()
	sunm.radius = 1.25
	sunm.height = 2.5
	sun.mesh = sunm
	var sunmat := StandardMaterial3D.new()
	sunmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sunmat.albedo_color = Color(1.0, 0.98, 0.90)
	sunmat.disable_fog = true
	sun.material_override = sunmat
	sun.position = Vector3(top.x + 1.9, wall_height + 6.4, top.z - 1.4)
	add_child(sun)
	_hole_sun(top)
	# Трава и корни по краю снаружи. Чистое голубое поле читается заливкой; с
	# парой тёмных силуэтов по ободу сразу видно, что это ЗЕМЛЯ и он смотрит
	# из-под неё.
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.albedo_color = Color(0.07, 0.08, 0.06)
	edge.disable_fog = true
	for i in 26:
		var a4: float = TAU * float(i) / 26.0 + _rng.randf_range(-0.08, 0.08)
		var r4: float = cell_size * _rng.randf_range(0.40, 0.52)
		var blade := MeshInstance3D.new()
		var bm4 := CylinderMesh.new()
		bm4.top_radius = 0.005
		bm4.bottom_radius = 0.035
		bm4.height = _rng.randf_range(0.25, 0.75)
		bm4.radial_segments = 5
		blade.mesh = bm4
		blade.material_override = edge
		blade.position = Vector3(top.x + cos(a4) * r4,
			wall_height + bm4.height * 0.45, top.z + sin(a4) * r4)
		blade.rotation = Vector3(_rng.randf_range(-0.5, 0.5), a4,
			_rng.randf_range(-0.5, 0.5))
		add_child(blade)
	# Щупальце, которое поднимется следом. Собираем сразу и прячем.
	climb_tent = Node3D.new()
	climb_tent.visible = false
	add_child(climb_tent)
	for i in 9:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.10 + 0.16 * (1.0 - float(i) / 9.0)
		cm.bottom_radius = 0.14 + 0.20 * (1.0 - float(i) / 9.0)
		cm.height = 1.0
		cm.radial_segments = 10
		cm.rings = 6
		seg.mesh = cm
		var m := ShaderMaterial.new()
		m.shader = TENT_SHADER
		m.set_shader_parameter("phase", float(i) * 0.7)
		seg.material_override = m
		climb_tent.add_child(seg)
		climb_segs.append(seg)
	print("Обвал у пролома ", climb_cell)


## Полез наружу. Полторы секунды подъёма — и голова над землёй.
func _start_climb_up() -> void:
	if climb == null or player_node == null:
		return
	climb_state = 5
	climb_t = 1.5
	climb_grab = player_node.global_position
	_freeze_player(true)
	if sfx != null:
		sfx.play("breath", -2.0)
		sfx.play("scrape", -1.0)


## Кладём щупальце по дуге от пола до точки хвата.
func _pose_climb_tent(from: Vector3, to: Vector3, bow: float) -> void:
	var n: int = climb_segs.size()
	var side: Vector3 = Vector3(to.z - from.z, 0.0, from.x - to.x).normalized()
	var prev: Vector3 = from
	for i in n:
		var t: float = float(i + 1) / float(n)
		var p: Vector3 = from.lerp(to, t) + side * sin(t * PI) * bow
		var d: Vector3 = p - prev
		var l: float = maxf(d.length(), 0.001)
		var seg := climb_segs[i] as MeshInstance3D
		(seg.mesh as CylinderMesh).height = l
		seg.position = prev + d * 0.5
		seg.rotation = Vector3(acos(clampf(d.y / l, -1.0, 1.0)), atan2(d.x, d.z), 0.0)
		prev = p


## ОБВАЛ ЦЕЛИКОМ. Поднялся — увидел небо — и его сдёрнули вниз, а насыпь ушла
## под землю. Выхода не было; была секунда, когда казалось, что он есть.
func _update_climb(delta: float) -> void:
	if climb == null or player_node == null:
		return
	if climb_state == 0:
		# Пока игроком распоряжается что-то другое — захват, выброс, удар о
		# стену, руки с потолка, — не лезем: иначе моя «гравитация» спорит с
		# чужой анимацией и тянет его вниз посреди чужой сцены.
		if dead or won or _ui_blocking() or drop_t > 0.0 or lift_on \
				or slam_stage > 0 or hf_stage > 0 or reel_t > 0.0:
			return
		# Сошёл с насыпи в сторону — падает на пол. Гравитации у игрока нет, и
		# без этого он остаётся висеть в воздухе на высоте, с которой шагнул.
		var p: Vector3 = player_node.global_position
		if p.y > 0.86 and not _on_climb(p):
			player_node.global_position.y = maxf(0.85, p.y - delta * 6.0)
			return
		# И НЕ НИЖЕ ПОЛА. Пока насыпь уходит вниз, физика успевает вытолкнуть
		# стоящего на ней игрока в другую сторону — сквозь пол. Стенд ловил его
		# на высоте −1.4, то есть под лабиринтом.
		if p.y < 0.84:
			player_node.global_position.y = 0.85
		# ВСТАЛ НА НАСЫПЬ — МОЖЕТ ПОЛЕЗТЬ. Пандуса больше нет: наверх поднимает
		# сцена, и начинает её сам игрок по E. Само собой это срабатывать не
		# должно — через клетку можно просто идти дальше, и решать, лезть ли
		# наружу, он будет сам.
		climb_ready = world_to_cell(p) == climb_cell \
			and Vector2(p.x - climb_a.x, p.z - climb_a.z).length() < 1.0
		if climb_ready and not _ui_blocking():
			hud.text = Lang.t("h_climb")
		return
	# ПОДЪЁМ. Тянется вверх руками по камню: качает, и в конце голова оказывается
	# над потолком.
	if climb_state == 5:
		climb_t -= delta
		var k5: float = 1.0 - clampf(climb_t / 1.5, 0.0, 1.0)
		var e5: float = k5 * k5 * (3.0 - 2.0 * k5)
		player_node.global_position = Vector3(
			lerpf(climb_grab.x, climb_a.x, e5),
			lerpf(climb_grab.y, climb_b.y, e5),
			lerpf(climb_grab.z, climb_a.z, e5))
		player_node.head.rotation.z = sin(_clock * 6.0) * 0.05 * (1.0 - e5)
		if climb_t <= 0.0:
			climb_state = 1
			climb_t = 1.9
			player_node.head.rotation.z = 0.0
		return
	# Умер или победил посреди сцены — сцену сворачиваем и возвращаем всё как
	# было. Иначе управление остаётся отобранным у мёртвого.
	if (dead or won) and climb_state > 0 and climb_state < 3:
		climb_state = 3
		climb_t = 1.8
		climb_tent.visible = false
		for cs3 in climb_shapes:
			(cs3 as CollisionShape3D).disabled = true
		_freeze_player(false)
		return
	if climb_state == 1:
		# Смотрит сам: камеру не трогаем, это единственные секунды в игре, когда
		# наверху есть что разглядывать. Высоту держим мы: физика у него
		# выключена, и без этой строки он тихо съезжает вниз.
		player_node.global_position.y = climb_b.y
		climb_t -= delta
		if climb_t <= 0.0:
			climb_state = 2
			climb_t = 1.4
			climb_grab = player_node.global_position
			_freeze_player(true)
			climb_tent.visible = true
			if sfx != null:
				sfx.play("roar", 5.0)
				sfx.hit(4.0)
			player_node.shake_amt = 1.0
			player_node.shake_dir = 0.7
			player_node.shake_hold = 1.1
		return
	if climb_state == 2:
		climb_t -= delta
		var k: float = 1.0 - clampf(climb_t / 1.4, 0.0, 1.0)
		var y: float = lerpf(climb_grab.y, 0.85, k * k * (3.0 - 2.0 * k))
		player_node.global_position.y = y
		# Голову заваливает вниз — туда, куда тянут.
		player_node.head.rotation.x = -1.15 * sin(clampf(k, 0.0, 1.0) * PI * 0.75)
		player_node.head.rotation.z = sin(_clock * 9.0) * 0.12 * (1.0 - k)
		var base: Vector3 = Vector3(climb_b.x, 0.05, climb_b.z)
		_pose_climb_tent(base, Vector3(climb_grab.x, y + 0.35, climb_grab.z), 0.55)
		if climb_t <= 0.0:
			climb_state = 3
			climb_t = 1.8
			# Коллизию снимаем СРАЗУ. Иначе уходящая вниз плита уносит игрока с
			# собой: он стоял на ней, и на замере оказывался на высоте -4.5.
			for cs2 in climb_shapes:
				(cs2 as CollisionShape3D).disabled = true
			_freeze_player(false)
			player_node.global_position.y = 0.85
			player_node.head.rotation.x = 0.0
			player_node.head.rotation.z = 0.0
			player_node.limp = 1.0
			climb_tent.visible = false
			anger = mini(anger + 1, 3)
			if sfx != null:
				sfx.hit(6.0)
				sfx.play("scrape", 4.0)
		return
	if climb_state == 3:
		# Уходит под землю: второй раз наверх не подняться.
		climb_t -= delta
		climb.position.y -= delta * 3.0
		player_node.global_position.y = 0.85
		if climb_t <= 0.0:
			climb_state = 4
			climb.queue_free()
			climb = null


## Стоит ли он на насыпи. Считаем по её же прямоугольнику: на скате высоту
## держит физика, а вот за его краем держать её нечему.
func _on_climb(p: Vector3) -> bool:
	if climb == null:
		return false
	return Vector2(p.x - climb_a.x, p.z - climb_a.z).length() < cell_size * 0.72


## Кольцо брызг в точке удара. Живёт полсекунды и гаснет.
func _splash_at(pos: Vector3, size: float, life: float) -> void:
	for sp in splashes:
		if sp["t"] > 0.0:
			continue
		sp["t"] = life
		sp["node"].global_position = Vector3(pos.x, 0.045, pos.z)
		sp["node"].scale = Vector3(size, 1.0, size)
		sp["mat"].set_shader_parameter("t0", float(Time.get_ticks_msec()) / 1000.0)
		sp["mat"].set_shader_parameter("life", life)
		sp["node"].visible = true
		return


func _update_splashes(delta: float) -> void:
	for sp in splashes:
		if sp["t"] <= 0.0:
			continue
		sp["t"] -= delta
		if sp["t"] <= 0.0:
			sp["node"].visible = false
	# Под дырами масса льётся непрерывно, значит и бьёт непрерывно. Но только
	# когда игрок рядом: считать брызги на другом конце лабиринта незачем.
	if player_node == null or holes.is_empty():
		return
	hole_splash_t -= delta
	if hole_splash_t > 0.0:
		return
	hole_splash_t = _rng.randf_range(0.22, 0.75)
	for h in holes:
		var p: Vector3 = cell_to_world(h, 0.0)
		if player_node.global_position.distance_to(p) > cell_size * 6.0:
			continue
		var a: float = _rng.randf() * TAU
		var rad: float = cell_size * _rng.randf_range(0.28, 0.52)
		var hit := Vector3(p.x + cos(a) * rad, 0.0, p.z + sin(a) * rad)
		_splash_at(hit, _rng.randf_range(0.5, 1.0), _rng.randf_range(0.4, 0.7))
		if sfx != null and _rng.randf() < 0.55:
			sfx.play_at("splat", hit, -20.0)
		return


## Капля падает молча, а слышно её удар о пол. Звук идёт из точки, а не из
## головы: в первых двух фазах слух — единственный сенсор, и он должен работать
## честно, иначе игрок перестаёт ему верить.
func _update_drips(delta: float) -> void:
	if player_node == null or sfx == null:
		return
	var pp: Vector3 = player_node.global_position
	for d in drips:
		d["t"] -= delta
		if d["t"] > 0.0:
			continue
		# Реже. Сорок точек с интервалом 6-22 с давали в коридоре каплю каждые
		# две-три секунды — очередь, а не редкий звук.
		d["t"] = _rng.randf_range(DRIP_GAP[0], DRIP_GAP[1])
		var p: Vector3 = cell_to_world(d["cell"], 0.0)
		if pp.distance_to(p) > cell_size * 7.0:
			continue
		for dr in drops:
			if dr["t"] <= 0.0:
				dr["t"] = 0.62
				dr["from"] = Vector3(p.x + _rng.randf_range(-0.5, 0.5), wall_height - 0.15,
					p.z + _rng.randf_range(-0.5, 0.5))
				dr["node"].position = dr["from"]
				dr["node"].visible = true
				break
	for dr in drops:
		if dr["t"] <= 0.0:
			continue
		dr["t"] -= delta
		var k: float = clampf(1.0 - dr["t"] / 0.62, 0.0, 1.0)
		# Свободное падение, а не равномерное: капля должна разгоняться.
		dr["node"].position = dr["from"] + Vector3.DOWN * (wall_height - 0.15) * k * k
		if dr["t"] <= 0.0:
			dr["node"].visible = false
			var floor_pos := Vector3(dr["from"].x, 0.05, dr["from"].z)
			sfx.play_at("drip", floor_pos, -4.0)
			_splash_at(floor_pos, 0.45, 0.5)


## Глаза открываются в стене, на которую ты СМОТРИШЬ, и держатся несколько
## секунд. Не в спину: в спину их никто не увидит, а весь смысл в том, что ты
## заметил их сам.
func _update_wall_eyes(delta: float) -> void:
	if player_node == null or eyes_quad == null:
		return
	if eyes_t > 0.0:
		eyes_t -= delta
		if eyes_t <= 0.0:
			eyes_quad.visible = false
		return
	eyes_wait -= delta
	if eyes_wait > 0.0:
		return
	eyes_wait = _rng.randf_range(22.0, 60.0)
	if _ui_blocking() or dead or won or not has_wand:
		return
	# Треть раз — потолок. Он тоже живая масса, и открывать глаза должен тоже,
	# а поднять голову страшнее, чем повернуться: наверх не смотришь на ходу.
	if _rng.randf() < 0.34 and _ceiling_eyes():
		return
	var head: Node3D = player_node.get_node_or_null("Head")
	if head == null:
		return
	var from: Vector3 = head.global_position
	var dir: Vector3 = -head.global_transform.basis.z.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	dir.y = 0.0
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * cell_size * 4.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.4:
		return                      # пол и потолок не годятся: глаза смотрят В УПОР
	eyes_quad.global_position = hit["position"] + n * 0.03
	eyes_quad.look_at(hit["position"] + n * 1.0, Vector3.UP)
	eyes_quad.rotate_object_local(Vector3.UP, PI)
	eyes_mat.set_shader_parameter("t0", float(Time.get_ticks_msec()) / 1000.0)
	eyes_t = _rng.randf_range(2.6, 4.2)
	eyes_mat.set_shader_parameter("life", eyes_t)
	eyes_quad.visible = true


## Глаза на потолке. Луча туда нет — у потолка нет столкновений, — поэтому
## место выбирается по сетке лабиринта: клетка перед игроком, если она свободна.
func _ceiling_eyes() -> bool:
	var head: Node3D = player_node.get_node_or_null("Head")
	if head == null:
		return false
	var fwd: Vector3 = -head.global_transform.basis.z
	fwd.y = 0.0
	var target: Vector3 = head.global_position + fwd.normalized() * cell_size * 1.6
	var cell := world_to_cell(target)
	if cell.x < 0 or cell.y < 0 or cell.x >= maze.size.y or cell.y >= maze.size.x:
		return false
	if maze.grid[cell.x][cell.y] != 0 or holes.has(cell):
		return false
	eyes_quad.global_position = Vector3(target.x, wall_height - 0.06, target.z)
	eyes_quad.look_at(head.global_position, Vector3.UP)
	eyes_mat.set_shader_parameter("t0", float(Time.get_ticks_msec()) / 1000.0)
	eyes_t = _rng.randf_range(2.6, 4.2)
	eyes_mat.set_shader_parameter("life", eyes_t)
	eyes_quad.visible = true
	return true


## Рык и дальняя капель УБРАНЫ. Оба были низкими тональными звуками — 38 Гц пила
## и 320 Гц синусоида, — и вместе читались как короткая отрыжка, а не как
## далёкий зверь и капля. Низкий чистый тон в этой игре звучит телесно, и
## лечится это не громкостью, а отсутствием.
##
## Из низких тональных остаётся только сердце, 52 Гц, и оно бьётся, лишь когда
## монстр в пяти клетках.




## Шаг по мокрому. Изредка вместо хлюпа под ногой лопается пузырь — с хрустом
## и расходящимся кольцом. Раз в десять шагов: чаще это стало бы ритмом, к
## которому привыкают, а привыкание — ровно то, чего здесь быть не должно.
func _on_step() -> void:
	if sfx == null:
		return
	if _rng.randf() < 0.10:
		sfx.play("pop", -16.0, 0.14)
		if player_node != null:
			_splash_at(player_node.global_position, 0.7, 0.6)
	else:
		# -30, а не -25: записи после выравнивания стали вдвое громче исходных.
		sfx.play("step_wet", -30.0, 0.09)


func _phase_fill(i: int) -> float:
	var lo := i * PHASE_STEP
	return clampf(float(errors - lo) / float(PHASE_STEP), 0.0, 1.0)


func _draw_phases() -> void:
	if _ui_blocking() or dead or won:
		return
	var w := 250.0
	var h := PHASE_BAR_H
	var seg := w / 3.0
	var x := (phase_bar.size.x - w) * 0.5
	var y := 16.0
	for i in 3:
		var sx := x + seg * i
		phase_bar.draw_rect(Rect2(sx, y, seg - 3.0, h), Color(0.62, 0.60, 0.55, 0.22))
		var f: float = _phase_fill(i)
		if f > 0.0:
			phase_bar.draw_rect(Rect2(sx, y, (seg - 3.0) * f, h), Color(0.02, 0.02, 0.03, 0.92))
		phase_bar.draw_rect(Rect2(sx, y, seg - 3.0, h), Color(0.62, 0.60, 0.55, 0.45), false, 1.0)
		if i < 2:
			_draw_tentacle_divider(sx + seg - 1.5, y + h * 0.5)


## Перегородка-щупальце: три коротких извива, живущих во времени.
func _draw_tentacle_divider(cx: float, cy: float) -> void:
	for k in 3:
		var pts := PackedVector2Array()
		for j in 7:
			var t: float = float(j) / 6.0
			var a: float = _clock * 1.7 + float(k) * 2.1
			pts.append(Vector2(cx + sin(a + t * 3.4) * 3.5 * t,
				cy + (t - 0.5) * (PHASE_BAR_H + 6.0) + cos(a + t * 2.6) * 2.0 * t))
		phase_bar.draw_polyline(pts, Color(0.10, 0.11, 0.10, 0.85), 1.6)



# ─────────────────────────── реакция на фазы и на отбой ───────────────────────────

## 7. Он отстал — и вот теперь тебя колотит. Страх приходит не в погоне,
## в погоне работает тело. Он приходит через минуту после, когда уже можно.
## И следующее полотно ты рисуешь этими же руками.
## Он упёрся щупальцем в стену коридора. Звук идёт ИЗ ТОЧКИ УПОРА, а не из
## монстра: в узком проходе по нему слышно, с какой стороны он отталкивается.
func _on_wall_hit(pos: Vector3, on_wall: bool) -> void:
	if sfx == null or player_node == null:
		return
	var d: float = player_node.global_position.distance_to(pos)
	if d > 22.0:
		return
	if on_wall:
		sfx.slap(pos, 1.0)
		return
	# Опора на пол — не удар, а хлюп: он ползёт по той же мокрой мерзости, по
	# которой ходишь ты. Тише и только вблизи, иначе восемь рук превращаются
	# в кашу.
	if d < 12.0:
		sfx.play_at("step_wet", pos, -7.0)


func _on_gave_up() -> void:
	if player_node != null:
		player_node.shake_long(6.0)
	next_fear_mul = 2.5
	hud.text = Lang.t("h_gone")


## 6. Каждая новая фаза — громкий удар и щупальце в лицо. Фаза не должна
## наступать молча: игрок обязан почувствовать, что мир только что стал хуже.
func _phase_shock(where: Vector3) -> void:
	if sfx != null:
		sfx.play("scrape", 6.0)
		sfx.play_at("whip", where, 6.0)
	if player_node != null:
		player_node.shake(1.2, 0.0)
	tell_pos = where
	tell_miss = false
	tell_t = TELL                # обычный тель: обернуться всё ещё можно


## Гул растёт, пока рисуешь, и изредка лопается щелчком. Щелчок ничего не делает —
## он просто заставляет дёрнуться в тот момент, когда рука ведёт линию.
func _update_board_sound(delta: float) -> void:
	if sfx == null or not board.visible:
		return
	var lvl: float = 1.0 - clampf(board.time_left / maxf(1.0, board.time_max), 0.0, 1.0)
	if board.final:
		lvl = board.near
	# Гул ПРОВАЛИВАЕТСЯ, когда он рядом. Раньше он только нарастал и глушил шаги,
	# то есть игра прятала единственный сигнал об опасности. Тишина предупреждает
	# сильнее любого звука.
	var duck: float = clampf(board.near, 0.0, 1.0) if board.show_near else 0.0
	sfx.hum_level(lvl, duck)
	_click_t -= delta
	if _click_t <= 0.0:
		_click_t = randf_range(5.0, 11.0)
		if randf() < 0.35:
			sfx.play("click", 4.0)


## Треск камня за полторы секунды до того, как он вылезет. Успеваешь понять,
## что сейчас будет, и не успеваешь ничего сделать — в этом и смысл.
func _on_surfacing() -> void:
	if sfx != null and monster != null:
		sfx.play_at("scrape", monster.surface_pos, 6.0)
		sfx.play("err", 2.0)
	if player_node != null and monster != null:
		var to: Vector3 = monster.surface_pos - player_node.global_position
		var right := player_node.global_transform.basis.x
		player_node.shake(1.0, signf(right.dot(to)))
	hud.text = Lang.t("h_crack")


## Подошёл вплотную к стене, в которой он сидит. Он НЕ выходит — до третьей фазы
## его как тела не существует. Из камня смотрят глаза, и он уползает в другую стену.
## Иначе первая фаза ломалась об одну простую вещь: любопытный игрок находил его
## по звуку, подходил и вытаскивал наружу раньше срока.
func _on_wall_scare() -> void:
	if _busy() or won:
		return
	scare_only = true
	scare_ui.begin(false, false, _rng.randi())
	_freeze_player(true)
	if sfx != null and monster != null:
		sfx.play_at("scrape", monster.global_position, 4.0)
		sfx.play("err", 0.0)
	if player_node != null:
		player_node.shake(1.0, 0.0)
	hud.text = Lang.t("h_eyes")


## Клавиша нажата — мир оживает. До этого не тикает ничего: ни щупальца,
## ни подход монстра, ни отсчёт неприкосновенных секунд.
## ОТВЛЁКСЯ? Godot сообщает, когда окно теряет и возвращает себе внимание.
## Это правда о самом игроке, а правда здесь работает лучше выдумки.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and started and says != null:
		says.try_say("v_focus")
	# ОКНО ПОТЕРЯЛО ФОКУС — ИГРА ВСТАЁТ. Раньше человек отвлекался на сообщение
	# и возвращался мёртвым: монстр всё это время подбирался к пустому креслу.
	# Это не удобство, а честность — умирать надо от того, что видел.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _autopause \
			and started and not dead and pause_ui != null and not pause_ui.visible:
		_open_pause()


func _open_pause() -> void:
	if pause_ui == null or dead:
		return
	# ПАУЗА НЕ РАБОТАЕТ. Считаем именно СНЯТИЯ паузы: фраза должна догнать
	# игрока в тот момент, когда он думает, что вернулся к управлению.
	if pause_ui.visible:
		_pauses += 1
		if _pauses >= 2 and says != null:
			says.try_say("v_pause")
	pause_ui.toggle()
	# Курсор отпускает САМО меню, а не тот, кто его позвал. По ESC он и так уже
	# свободен, но меню из четырёх кнопок, которое можно открыть с захваченной
	# мышью, — это меню, из которого нельзя выйти.
	if pause_ui.visible:
		_freeze_player(true)
		_set_cursor(true)


func _on_resume() -> void:
	_freeze_player(false)
	_set_cursor(false)


func _wipe_journal() -> void:
	journal = []
	Notes.save_journal(journal)


func _quit() -> void:
	get_tree().quit()


func _on_start() -> void:
	started = true
	_freeze_player(false)
	_set_cursor(false)
	_update_hud()
