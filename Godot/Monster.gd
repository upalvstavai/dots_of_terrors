extends Node3D
## ТОЧКИ УЖАСА — монстр. Перенос из HTML (updInWall / updMonster / updHaunt).
##
## Главное решение автора, которое надо сохранить любой ценой: в первых двух фазах
## монстра НЕ СУЩЕСТВУЕТ КАК ТЕЛА. Он внутри камня, не рисуется вообще и только
## слышен — с направлением. Пока он не вылез, вся угроза идёт через слух.
##
## Скорости заданы ДОЛЯМИ от скорости игрока, а не метрами. В прототипе они
## настраивались замерами при игроке 160 px/с; если переносить абсолютные числа,
## всё ломается от одной правки скорости игрока.

signal emerged                 ## вылез из стены — началась третья фаза
signal caught                  ## дотянулся до игрока
signal noticed                 ## заметил и пошёл на сближение
signal gave_up                 ## погоня выдохлась, он ушёл обратно в камень
signal surfacing               ## треск: он вот-вот вылезет
signal wall_scare              ## подошёл к его стене в первой фазе — глаза и уполз
signal wall_hit(pos: Vector3, on_wall: bool)  ## поставил щупальце: в стену или на пол

## ХОД В КАМНЕ задаётся в КЛЕТКАХ в секунду, а не долей от игрока — и это важно.
## Тут вопрос не «догонит или нет», а «через сколько дойдёт», то есть длина арки
## первых двух фаз. Доля от игрока сломалась при переносе: в браузере игрок шёл
## 3.33 клетки/с, в Godot — 1.33, и та же одна пятая дала монстру 0.27 клетки/с
## вместо 0.67. Замер: при 0.27 он НЕ ДОХОДИЛ за 400 секунд ни на одной из десяти карт.
const INWALL_CELLS := 0.667    ## клеток в секунду вблизи игрока
## Издалека он идёт БЫСТРЕЕ. Замер: против неподвижного игрока он выходил за
## 125–148 с, а против ходящего — от 28 до 391, потому что «ближайшая к игроку
## стена» скачет по карте быстрее, чем он ползёт. Плюс на каждом полотне он
## замирал. За восьмиминутный забег мог не дойти ни разу — так и вышло.
## Вблизи скорость прежняя: угроза должна нарастать медленно.
const INWALL_FAR := 1.7        ## во сколько раз быстрее, когда далеко
const INWALL_CAP := 200.0      ## через столько секунд выходит в любом случае
const INWALL_WANDER_F := 0.25  ## доля пересчётов «куда попало»: подход не прямой линией

## Доли от скорости ИГРОКА — тут наоборот, вопрос именно в том, убежишь ли.
const K_HUNT := 0.74
const K_CHASE := 0.91
const K_MAX := 1.50            ## потолок при максимальной ярости. Быстрее нельзя:
                               ## от такого не убежать в принципе, и лабиринт
                               ## превращается в коридор смерти
## Пятнадцать, а не тридцать. Играющий сносно проходит полотна почти без ошибок,
## и до тридцати он бы не дожил никогда — верхняя половина шкалы просто не
## существовала бы в игре.
const ANGER_MAX := 15

const PH3_MEET_CELLS := 2.2    ## на каком расстоянии сквозь стену он решает вылезти
const CUT_FAR_CELLS := 12      ## обход по коридорам, после которого он режет напрямую
## Расстояние захвата считается ТОЛЬКО по горизонтали. Монстр стоит на полу
## (y = 0), а камера игрока — на 0.85 м выше, и объёмное расстояние между ними
## никогда не падало ниже этих 0.85. При пороге 0.9 ему надо было подойти
## на 29 сантиметров по горизонтали — а он и не может, он останавливается
## в центре клетки. Отсюда «подошёл вплотную и не нападает».
## Он НЕ ПОДХОДИТ ВПЛОТНУЮ. У массы со щупальцами нет причин подбираться вплотную:
## она выстреливает щупальцем с расстояния, цепляет и подтягивает к себе.
## Прежние 1.3 м означали, что он честно доходит и утыкается в тебя носом.
const CATCH_DIST := 3.4        ## метров по горизонтали: на столько он дотягивается
## Ближе этого он НЕ ПОДХОДИТ. Дотягиваться щупальцем и при этом утыкаться носом
## — противоречие: если он всё равно доходит вплотную, щупальца незачем.
const STANDOFF := 2.9
const REPATH := 0.45           ## как часто пересчитывать путь, сек
## ТРАВЛЯ, А НЕ ПОГОНЯ. После выхода он вставал в режим погони и не выходил
## из него никогда: бесконечные догонялки, где рывок успевает перезарядиться,
## и это перестаёт быть страшно — становится беговой дорожкой.
## Правильный ритм: короткий рывок за тобой, потом он отступает и выжидает.
## Пауза нужна не тебе, а страху: пока он рядом и молчит, ты его ждёшь.
const CHASE_LEN := [5.0, 9.0]      ## сколько длится короткая погоня
const CHASE_PAUSE := [9.0, 18.0]   ## сколько выжидает после неё
## ВЫХОД ИЗ СТЕНЫ — событие, а не появление. Сначала треск, и только через
## SURFACE_DELAY он вылезает. Полторы секунды нужны не ему, а тебе: за них
## успеваешь понять, что сейчас будет, и не успеваешь ничего сделать.
const SURFACE_DELAY := 1.5
## Выдохшись, он НЕ остаётся стоять рядом, а уходит обратно в камень и вылезает
## снова в случайный момент. Так он перестаёт быть объектом на карте, за которым
## можно следить, и снова становится тем, что может оказаться где угодно.
const RESURFACE := [14.0, 30.0]
const SURFACE_NEAR := 2.0          ## клеток: вылез вплотную
const SURFACE_FAR := [8.0, 13.0]   ## клеток: вылез поодаль, видно как идёт
## ОТОРВАЛСЯ — значит потерял. Погоня и так конечна по времени, но если ты сумел
## разорвать дистанцию, она должна кончаться СРАЗУ: иначе бегство не читается
## как успех, ты просто ждёшь, пока у него выйдет таймер.
const LOSE_CELLS := 13.0

var maze
var cell_size: float = 2.4
var player_speed: float = 3.2
var mode: String = "inwall"
var stun: float = 0.0
var path: Array = []
var _path_t: float = 0.0
var _see_t: float = 0.0
var chase_t: float = 0.0
var pause_t: float = 0.0
var roam_cell: Vector2i = Vector2i(-1, -1)
var surface_t: float = 0.0
var surface_pos: Vector3
var resurface_t: float = 0.0
var first_out: bool = true
var last_phase: bool = false      ## третья фаза: он быстрее игрока
var allow_emerge: bool = false    ## можно ли вылезать: до третьей фазы нельзя
var scare_cool: float = 0.0       ## чтобы глаза в стене не повторялись подряд
var cutting: bool = false
var parked: bool = false        ## игрок рисует — монстр стоит и ждёт
var finale_mode: bool = false   ## идёт к двери: он и есть таймер
var finale_near: float = 0.0    ## 0 — далеко, 1 — дошёл
var _fin_start: int = 1
var _fin_speed: float = 0.27
var trail: Array = []
var _trail_t: float = 0.0
var _shiv: float = 0.0
var inwall_time: float = 0.0
## ФОРМА. Обычно он бесформенный — рой осколков вокруг пустоты. В момент атаки
## осколки на секунду складываются в фигуру: человека, зверя или чего-то ещё, —
## и снова рассыпаются.
##
## Модель тут была бы ошибкой: статичный меш не умеет НЕ держать форму, а именно
## это про него главное. Осколки умеют и то и другое.
var form_pose: Array = []      ## куда складываться, по осколку на запись
var form_t: float = 0.0        ## 0 — рой, 1 — фигура
var form_hold: float = 0.0     ## сколько ещё держать фигуру
var form_warp: float = 0.0     ## насколько фигура искажена
## ФОРМЫ. Пока одна разобрана честно — искажённый гуманоид: у него есть пасть,
## и ловит он щупальцами ИЗ НЕЁ, а не руками. Остальные две пока просто раскладки.
const FORM_NONE := 0
const FORM_HUMAN := 1
const FORM_BEAST := 2
const FORM_OTHER := 3
const ARM_MOUTH := 5            ## сколько щупалец лезет изо рта
var form_kind: int = FORM_NONE
var mouth_dir: Vector3 = Vector3.UP
var mouth_size: float = 0.15
var mouth_open: float = 0.0
## ВТОРОЕ ТЕЛО. Не «осьминог, натянутый на человека», а отдельная фигура из той
## же жижи. Восемь точек притяжения умеют выдавить бугры, но не конечность —
## руки и ноги здесь настоящие, из тех же цепочек звеньев, что и щупальца.
## Между телами он ПЕРЕТЕКАЕТ: одно оседает лужей, второе поднимается из неё.
var human: Node3D
var human_mat: ShaderMaterial
var human_skel
var hb: Dictionary = {}        ## имя кости -> индекс
var hrest: Dictionary = {}     ## имя кости -> поворот покоя
var twitch_t: float = 0.0      ## до следующего рывка
var twitch: float = 0.0        ## сила текущего рывка
var crawl_k: float = 0.0       ## 0 — идёт в рост, 1 — ползёт на коленях
var arm_stretch: Dictionary = {}   ## во сколько раз вытянуты кости рук
## РУКИ С ПОТОЛКА. Две цепочки, живущие в мировых координатах: они спускаются
## над игроком, где бы он ни был. Смысл атаки в том, что убежать нельзя — руки
## приходят не от монстра, а сверху.
var ceil_arms: Array = []
var ceil_at: Vector3 = Vector3.ZERO
var ceil_k: float = 0.0        ## 0 — их нет, 1 — сомкнулись
## РУКИ ВВЕРХ. Жест, с которого начинается атака: он замирает и тянется вверх,
## и уже оттуда, с потолка, приходят руки. Без жеста связи между ним и потолком
## не видно вовсе — просто «что-то схватило».
var arms_up: float = 0.0
var shell_mat: ShaderMaterial  ## материал тела: ему сообщается собранность
var blob: MeshInstance3D       ## само тело — одна поверхность
var core_mesh: MeshInstance3D  ## светящееся ядро внутри кома
var tendrils: Array = []       ## щупальца на теле
var tend_mat: ShaderMaterial
var arm_mat: ShaderMaterial
var arms: Array = []           ## восемь рук, каждая — цепочка звеньев
var aim_at: Vector3 = Vector3.ZERO     ## где игрок: к нему тянутся руки
var cramped: bool = false              ## зажат между стенами
var side_dir: Vector3 = Vector3.ZERO   ## поперёк коридора, к стенам
var wall_a: Vector3 = Vector3.ZERO     ## точка на одной стене
var wall_b: Vector3 = Vector3.ZERO     ## и на другой
var cell_mid: Vector3 = Vector3.ZERO   ## середина клетки, то есть ось прохода
var _space_t: float = 0.0
var _hit_cool: float = 0.0             ## чтобы удары не слились в дробь
var _step_cool: float = 0.0            ## то же для шагов по полу
var _gait_prev: float = 0.0
var eye_glow: float = 0.25
var gait_move: float = 0.0             ## 0 — стоит, 1 — идёт в полную силу
## Клетки убежищ. Он в них НЕ ЗАХОДИТ и не видит того, кто там стоит. До сих
## пор список ему не передавали вовсе: «безопасная комната» отличалась от
## обычной только тем, что там нельзя было долго сидеть.
var safe_cells: Dictionary = {}
var manual_space: bool = false         ## теснота задана снаружи, не замером
var reach: MeshInstance3D      ## щупальце, которым он достаёт до игрока
var reach_mat: ShaderMaterial
var reach_t: float = 0.0       ## сколько ещё держит
## Шаг: по нему опорные щупальца отталкиваются в такт движению.
var gait: float = 0.0
var grasp_at: Vector3 = Vector3.ZERO   ## куда тянутся щупальца, в мировых
## ДЕРЖИТ НАД ГОЛОВОЙ. Пока не ноль — четыре руки обвивают эту точку, а не
## тянутся к ней: кончики уходят ЗА неё и завиваются, то есть смыкаются вокруг.
var hold_at: Vector3 = Vector3.ZERO
var hold_t: float = 0.0
var hold_tight: float = 0.0            ## 0 — только обхватили, 1 — сжали
const HOLD_ARMS := 6   ## четырёх мало: между ними оставались просветы
## ВЫДАВЛИВАЕТСЯ ИЗ КАМНЯ. Точка на стене и нормаль наружу. Пока это не ноль,
## четыре руки лупят в стену позади него и отжимаются от неё. Раньше он просто
## ехал сквозь камень — со стороны это было скольжение, а не выход.
var push_at: Vector3 = Vector3.ZERO
var push_n: Vector3 = Vector3.ZERO
## Слой видимости только для него. По нему бьёт отдельная лампа с палочки,
## которая не трогает больше ничего: коридор остаётся тёмным, проявляется он.
const MON_LAYER := 5
const LIT_FROM := 11.0                 ## с какого расстояния начинает проявляться
## Сколько щупалец тянется к игроку прямо сейчас.
const GRASP := 4
## Сколько щупалец всего и сколько из них опорных.
const TENDRILS := 14           ## мелкие нити жижи по телу
const ARMS := 8                ## восемь рук — это и есть осьминог
const ARM_SEGS := 14           ## звеньев в руке: на семи дуга ломалась в колено
# ДЛИННЫЕ. На 2.6 м руки были короче мантии, и спереди он читался шаром с
# выступами: щупальца попросту терялись в его же объёме. У осьминога рука
# в несколько раз длиннее тела — с 4.4 м она выходит за силуэт и работает
# на него, а не пропадает внутри.
const ARM_LEN := 4.40          ## длина руки: у осьминога руки — большая часть тела
# ТОЛЩЕ. На кадре с двух метров руки читались нитками: мантия под три метра,
# а рука в обхвате с палец. Осьминог узнаётся по толстым щупальцам, и это
# единственное число, которым это чинится без новой модели.
const ARM_R := 0.47            ## радиус у основания: у основания рука толстая
const ARM_DUTY := 0.74         ## какую долю цикла рука стоит на опоре
## Насколько резок перенос. Единица — равномерно, больше — рука долго висит
## на опоре и потом ХЛЁСТКО перебрасывается. При равномерном переносе движение
## читается как плавное помахивание, а не как отталкивание.
const ARM_SNAP := 2.4
## МЕСТА НОГ В ЗАЛЕ: [сторона, вынос вдоль тела]. Правая половина задана явно,
## левая — её точное зеркало. Никакой случайности: сколько ног видно с одной
## стороны, столько же видно с другой.
const LEG_SIDE := 2.75        ## насколько вбок от оси тела стоит нога в зале
const ARM_STRIDE := 1.05       ## на сколько метров вперёд ставится новая опора
const ARM_LIFT := 0.85         ## насколько рука поднимается в переносе
## Роли рук. В тесноте они разные: одни упираются в стены, другие переступают,
## две тянутся к игроку, лишние прижаты к телу — в коридоре их некуда девать.
const ROLE_FLOOR := 0
const ROLE_WALL := 1
const ROLE_REACH := 2
const ROLE_TUCK := 3
const ROLE_HOLD := 4
const ROLE_MOUTH := 5
const SPACE_T := 0.30          ## как часто перещупывать пространство вокруг
## ПРОФИЛЬ МАНТИИ. Пары «высота от -1 до 1, радиус». Это и есть «реальная форма
## осьминога»: острая макушка, широкий мешок, ПЕРЕХВАТ шеи и надбровный валик,
## из-под которого смотрят глаза. Шар этого не даёт никаким шейдером — форма
## должна быть в самой сетке, а кипение уже искажает готовый силуэт.
const MANTLE := [
	[1.00, 0.04], [0.94, 0.31], [0.84, 0.56], [0.70, 0.77],
	[0.52, 0.89], [0.32, 0.93], [0.12, 0.87], [-0.04, 0.75],
	[-0.16, 0.61], [-0.28, 0.71], [-0.44, 0.67], [-0.62, 0.55],
	[-0.80, 0.39], [-0.92, 0.25], [-1.00, 0.11],
]
const MANTLE_H := 1.85         ## полувысота мантии в единицах BLOB_R
## Опорных щупалец шесть, а не четыре: он отталкивается ими от пола и стен, и
## на четырёх это читается как паук, а не как осьминог.
const LEGS := 6                ## осталось от прежнего тела; рук теперь ARMS
## Радиус кома. Он должен быть БОЛЬШИМ: маленький ком читается как валун,
## а не как масса, которая сейчас на тебя перельётся.
const BLOB_R := 0.78
## Восемь притягивателей: столько поддерживает шейдер. Больше и не нужно —
## голова, две руки, две ноги и пара опорных точек.
const ATTR := 8
## РОСТ. Первая версия была ростом с куст: осколки по метру, глаза на 1.42 —
## ниже глаз игрока (1.62). Снизу вверх смотреть должен ты, а не оно.
## Теперь он выше человека и почти достаёт до верха коридора (стены 2.9),
## а в ширину остаётся уже прохода (коридор 2.4), чтобы по нему проходить.
const HEIGHT := 2.7            ## метров до глаз
const WIDTH := 0.62            ## радиус разброса осколков

var body: MeshInstance3D
var eye_dirs: Array = []      ## куда смотрят глаза, в системе тела
var eye_open: Array = []      ## насколько открыт каждый
var _rng := RandomNumberGenerator.new()


func setup(maze_ref, cell: float, pspeed: float, seed_value: int) -> void:
	maze = maze_ref
	cell_size = cell
	player_speed = pspeed
	_rng.seed = seed_value
	_build_body()
	visible = false


func _build_body() -> void:
	# НЕ КАПСУЛА. Гладкое цельное тело читается как тупой предмет — в браузере
	# он был роем нитей, и силуэт говорил главное: эта штука НЕ ДЕРЖИТ ФОРМУ.
	# Здесь то же самое собирается из тонких осколков вокруг пустого центра.
	# Такое устройство и пригодится дальше: «принять любую форму» — это просто
	# другая раскладка осколков, тело переписывать не придётся.
	body = MeshInstance3D.new()
	add_child(body)
	# ОДИН ШАР. Две попытки до этого собирали тело из множества мешей — сначала
	# коробок, потом сфер, — и обе провалились одинаково: у каждого меша свой
	# силуэт, и глаз читает связку палок или гусеницу из шариков. Комком это не
	# станет никогда.
	#
	# Здесь вся форма — смещение вершин ОДНОЙ поверхности, поэтому силуэт всегда
	# сплошной. Сегментов много: на редкой сетке кипение превращается в грани.
	var shell := ShaderMaterial.new()
	shell.shader = load("res://blob.gdshader")
	shell_mat = shell
	blob = MeshInstance3D.new()
	blob.mesh = _mantle_mesh()
	blob.material_override = shell
	# ВЫТЯНУТ ВВЕРХ. Шар радиусом 0.78 читался как валун: полтора метра в ширину
	# при полутора в высоту — это картошка, а не то, что над тобой нависает.
	# Верх тела должен приходиться ВЫШЕ головы игрока (1.63): смотреть снизу
	# вверх должен ты, а не наоборот.
	# Вытяжку теперь несёт сам профиль, а не масштаб узла: масштабом шар
	# превращался в яйцо, а перехвата шеи и надбровья из него не получить.
	blob.scale = Vector3.ONE
	blob.position = Vector3(0, HEIGHT * 0.60, 0)
	body.add_child(blob)
	# Ядро — то, что внутри камня. Маленькое и зелёное, просвечивает сквозь осколки.
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.17
	cm.height = 0.34
	core.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.06, 0.20, 0.10)
	cmat.emission_enabled = true
	cmat.emission = Color(0.14, 0.75, 0.35)
	cmat.emission_energy_multiplier = 0.25
	core.material_override = cmat
	core.position = Vector3(0, HEIGHT * 0.55, 0)
	body.add_child(core)
	core_mesh = core
	_build_tendrils()
	_build_arms()
	_build_human()
	_build_ceiling_arms()
	_build_reach()
	# Глаза рисует сам шейдер тела — направления задаём здесь, раз и навсегда.
	# Два передних и четыре по бокам и сзади: смотрит отовсюду.
	eye_dirs = [
		Vector3(-0.42, 0.10, 0.90).normalized(),
		Vector3(0.42, 0.10, 0.90).normalized(),
		Vector3(-0.95, -0.10, 0.20).normalized(),
		Vector3(0.95, -0.10, 0.20).normalized(),
		Vector3(-0.55, 0.35, -0.75).normalized(),
		Vector3(0.60, -0.30, -0.72).normalized(),
	]
	for i in eye_dirs.size():
		eye_open.append(1.0 if i < 2 else 0.0)
	# Слой ставим ПОСЛЕ того, как всё тело собрано: иначе руки и нити, которые
	# создаются позже, останутся на общем слое и лампа их не тронет.
	_mark_layer(self)


## Хвост сороконожки: сегменты идут по СЛЕДУ головы с равным шагом.
## Пропадал с тех пор, как тело собрали из осколков, — старый цикл жил внутри
## прежнего _build_body и исчез вместе с ним.
## Хвоста из сегментов БОЛЬШЕ НЕТ. Двенадцать шаров, нанизанных на след, — это
## буквально гусеница, и именно её было видно, когда тело уже стало комом.
## У жидкой массы не бывает отдельных сегментов: она вся одна.


## Щупальца на теле. Много и разной длины — по ним и читается, что масса не
## просто ком: у кома нет намерения, а у щупалец есть.
##
## Четыре самых длинных и толстых — ОПОРНЫЕ: тело приподнято, и оно на них
## переступает. Полноценной походки тут нет и не нужно: достаточно, чтобы они
## гнулись в такт движению, а силуэт держался высоко.
## Две руки, которые спускаются с потолка. Строятся из того же кирпича, что и
## щупальца, но живут сами по себе: их корни в мировых координатах, потому что
## тянутся они не от тела, а оттуда, где игрок.
func _build_ceiling_arms() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tentacle.gdshader")
	mat.set_shader_parameter("tint", Color(0.035, 0.040, 0.037))
	mat.set_shader_parameter("rim_tint", Color(0.16, 0.44, 0.28))
	mat.set_shader_parameter("wave", 0.0)
	mat.set_shader_parameter("pinch", 0.0)
	for i in 2:
		var root := Node3D.new()
		root.top_level = true
		root.visible = false
		add_child(root)
		var joints: Array = _chain(root, 10, 4.2, 0.15, mat)
		ceil_arms.append({"root": root, "joints": joints, "len": 4.2,
			"ph": float(i) * PI, "scl": 1.0})
	return


## Показать руки с потолка над точкой и начать смыкание.
func ceiling_grab(at: Vector3, ceiling_y: float) -> void:
	ceil_at = Vector3(at.x, ceiling_y, at.z)
	ceil_k = 0.0
	for a in ceil_arms:
		(a["root"] as Node3D).visible = true


func ceiling_release() -> void:
	ceil_k = 0.0
	ceil_at = Vector3.ZERO
	for a in ceil_arms:
		(a["root"] as Node3D).visible = false


## Спускаются и обхватывают. Считается прямо в мировых координатах: корни у
## этих рук top_level, тело монстра на них не влияет.
func _pose_ceiling(delta: float, target: Vector3) -> void:
	if ceil_at == Vector3.ZERO:
		return
	ceil_k = minf(1.0, ceil_k + delta * 0.9)
	for i in ceil_arms.size():
		var a: Dictionary = ceil_arms[i]
		var root: Node3D = a["root"]
		root.global_position = ceil_at + Vector3(cos(float(i) * PI) * 0.5, 0.0,
			sin(float(i) * PI) * 0.5)
		# Цель уезжает вниз к игроку по мере смыкания, а кисти обходят его
		# с двух сторон — иначе обе руки лезут в одну точку.
		var side: Vector3 = Vector3(cos(_shiv * 0.8 + float(i) * PI), 0.0,
			sin(_shiv * 0.8 + float(i) * PI)) * lerpf(1.1, 0.35, ceil_k)
		var goal: Vector3 = target.lerp(target, 1.0) + side
		_pose_world_arm(a, goal, Vector3.UP, 0.45)
	return


## Тот же решатель дуги, но в МИРОВЫХ координатах: у этих рук нет тела-родителя.
func _pose_world_arm(arm: Dictionary, target: Vector3, bow: Vector3, tip: float) -> void:
	var root: Node3D = arm["root"]
	var joints: Array = arm["joints"]
	var n: int = joints.size() - 2
	var seg: float = float(arm["len"]) / float(joints.size())
	var d: Vector3 = target - root.global_position
	var dist: float = d.length()
	var dir: Vector3 = d / dist if dist > 0.001 else Vector3.DOWN
	var c: float = _arc_curl(dist, seg, n)
	var bn: Vector3 = dir.cross(bow)
	if bn.length() < 0.01:
		bn = dir.cross(Vector3.RIGHT)
	bn = bn.normalized()
	var half: float = c * float(n - 1) * 0.5
	var tangent: Vector3 = dir.rotated(bn, half)
	var yv: Vector3 = -tangent
	var xv: Vector3 = bn
	var zv: Vector3 = xv.cross(yv).normalized()
	var tr: Transform3D = root.global_transform
	tr.basis = Basis(xv, yv, zv)
	root.global_transform = tr
	for k in joints.size():
		var a2: float = 0.0
		if k > 0 and k <= n - 1:
			a2 = -c
		elif k > n - 1:
			a2 = tip
		(joints[k] as Node3D).rotation = Vector3(a2, 0.0, 0.0)


## ЧЕЛОВЕЧЕСКАЯ ФИГУРА — ГОТОВАЯ МОДЕЛЬ, А НЕ САМОДЕЛКА.
##
## Я сначала собрал её из тех же кирпичей, что и осьминога: торс телом вращения,
## цепочки-конечности, изломы в суставах. Вышла сосиска с выступами — человек
## не читался. Причина простая: узнаваемость человека держится на пропорциях и
## на десятке мелочей (ключицы, колени, кисти), и подбирать их вручную дольше,
## чем взять готовый скелет.
##
## Поэтому здесь CC0-модель с костями. Своё в ней — ТОЛЬКО искажение: руки
## вытянуты вдвое, шея вытянута, голова свёрнута набок, ноги разной длины. И
## шейдер жижи поверх, тот же, что у кома: это по-прежнему та же масса, просто
## принявшая чужую форму.
## Во сколько раз сжата фигура, чтобы помещаться в коридор. Число не на глаз:
## 5.71 м роста при потолке 4.3 — см. замер в _build_human.
const HUMAN_FIT := 0.69


func _build_human() -> void:
	human = Node3D.new()
	human.visible = false
	body.add_child(human)
	var packed = load("res://models/human.glb")
	if packed == null:
		# Модели нет — форма просто не появится, игра не падает.
		push_warning("models/human.glb не найдена, форма гуманоида отключена")
		human = null
		return
	var inst: Node3D = packed.instantiate()
	human.add_child(inst)
	# РОСТ ПОД КАРТУ. Замер по костям: макушка стояла на 4.96 м при потолке
	# 4.3, а ступни — на −0.75, то есть фигура одновременно торчала сквозь
	# потолок и была закопана в пол. От ступней до макушки выходило 5.71 м в
	# коридоре высотой 4.3 — она физически не помещалась в место, по которому
	# ходит.
	#
	# Сжимаем ЦЕЛИКОМ, а не по частям: длинные руки и вытянутая шея — это её
	# силуэт, и резать их по отдельности значит сделать обычного человека.
	# 0.69 даёт макушку на 3.94 — голова почти касается потолка, и это ровно то
	# ощущение, ради которого она и задумана.
	inst.scale = Vector3(HUMAN_FIT, HUMAN_FIT, HUMAN_FIT)
	# И ПОДНЯТЬ НА ПОЛ. Начало координат модели лежит выше ступней, поэтому без
	# сдвига она уходит в камень по щиколотку.
	inst.position.y = 0.75 * HUMAN_FIT
	# ОТДЕЛЬНЫЙ ШЕЙДЕР ДЛЯ СКИНЕННОГО МЕША. Тот, что у кома, двигает вершины —
	# и на костях это рвёт сетку в клочья: проверено, фигуру разнесло на
	# треугольники по всей комнате. Здесь только поверхность.
	human_mat = ShaderMaterial.new()
	human_mat.shader = load("res://goo_skin.gdshader")
	_skin(inst)
	_distort(inst)
	# ЧУЖУЮ АНИМАЦИЮ ОСТАНАВЛИВАЕМ. Она перезаписывает позы костей каждый кадр,
	# и любая своя поза до экрана не доживает. Ходьбу, хромоту и дёрганье
	# считаем сами — заодно они получаются кривыми, а не человеческими.
	var ap := inst.find_child("AnimationPlayer", true, false)
	if ap != null and ap is AnimationPlayer:
		(ap as AnimationPlayer).stop()
		(ap as AnimationPlayer).active = false
	return


## Натянуть жижу на всё, что нашлось: у модели пять материалов (рубашка, кожа,
## волосы), и оставить хоть один — значит показать, что это чужая модель.
func _skin(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for i in mi.get_surface_override_material_count():
			mi.set_surface_override_material(i, human_mat)
		mi.material_override = human_mat
	for c in n.get_children():
		_skin(c)


## ИСКАЖЕНИЕ ПО КОСТЯМ. Модель обычная — страшной её делает вот это.
func _distort(n: Node) -> void:
	var sk = n.find_child("Skeleton3D", true, false)
	if sk == null:
		return
	human_skel = sk
	# Вытяжка задаётся по имени кости: у этой модели они человеческие.
	var stretch := {
		"UpperArm.L": Vector3(0.85, 2.10, 0.85),
		"UpperArm.R": Vector3(0.85, 1.85, 0.85),
		"LowerArm.L": Vector3(0.80, 2.30, 0.80),
		"LowerArm.R": Vector3(0.80, 2.05, 0.80),
		# 1.25. И 2.6, и 1.7 уводили голову на стебель отдельно от плеч: у этой
		# модели шея и так длинная, множитель ложится поверх.
		"Neck": Vector3(0.80, 1.25, 0.80),
		"Head": Vector3(0.88, 1.25, 0.92),
		"UpperLeg.L": Vector3(0.90, 1.30, 0.90),
		"UpperLeg.R": Vector3(0.90, 1.14, 0.90),
		"Torso": Vector3(0.92, 1.10, 0.86),
	}
	# Индексы и позы покоя запоминаем один раз: искать кость по имени каждый
	# кадр — это перебор всего скелета на каждую из полутора десятков костей.
	for bone in ["Hips", "Abdomen", "Torso", "Neck", "Head",
			"Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R",
			"LowerArm.L", "LowerArm.R", "UpperLeg.L", "UpperLeg.R",
			"LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R"]:
		var bidx: int = sk.find_bone(bone)
		if bidx >= 0:
			hb[bone] = bidx
			hrest[bone] = sk.get_bone_rest(bidx).basis.get_rotation_quaternion()
	for nm2 in ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]:
		arm_stretch[nm2] = stretch[nm2]
	for bone in stretch.keys():
		var idx: int = sk.find_bone(bone)
		if idx >= 0:
			sk.set_bone_pose_scale(idx, stretch[bone])
	# Голова свёрнута набок — мелочь, а без неё это просто длиннорукий человек.
	var hi: int = sk.find_bone("Head")
	if hi >= 0:
		sk.set_bone_pose_rotation(hi, Quaternion(Vector3(0.20, 0.35, 0.55).normalized(), 0.45))
	return


## Тело вращения по ЛЮБОМУ профилю. Раньше эта возня жила внутри мантии; теперь
## по ней строится и торс фигуры, поэтому вынесено отдельно.
func _lathe(prof: Array, rad: float, half: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: int = 36
	for r in prof.size() - 1:
		var y0: float = float(prof[r][0]) * half
		var r0: float = float(prof[r][1]) * rad
		var y1: float = float(prof[r + 1][0]) * half
		var r1: float = float(prof[r + 1][1]) * rad
		for c in cols:
			var a0: float = TAU * float(c) / float(cols)
			var a1: float = TAU * float(c + 1) / float(cols)
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.set_uv(Vector2(float(c) / float(cols), float(r) / float(prof.size())))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Тело вращения по профилю MANTLE. Обычная «бочка»: кольцо вершин на каждой
## высоте, соседние кольца сшиты полосой треугольников.
##
## Начало координат — в середине мантии, потому что blob.gdshader смещает
## вершины вдоль normalize(VERTEX): форму он раздувает ОТ ЦЕНТРА, и центр обязан
## быть внутри тела, иначе кипение выворачивает силуэт наизнанку.
func _mantle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: int = 44
	var rows: int = MANTLE.size()
	for r in rows - 1:
		var y0: float = float(MANTLE[r][0]) * BLOB_R * MANTLE_H
		var r0: float = float(MANTLE[r][1]) * BLOB_R
		var y1: float = float(MANTLE[r + 1][0]) * BLOB_R * MANTLE_H
		var r1: float = float(MANTLE[r + 1][1]) * BLOB_R
		for c in cols:
			var a0: float = TAU * float(c) / float(cols)
			var a1: float = TAU * float(c + 1) / float(cols)
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.set_uv(Vector2(float(c) / float(cols), float(r) / float(rows)))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _build_tendrils() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tentacle.gdshader")
	mat.set_shader_parameter("tint", Color(0.035, 0.040, 0.037))
	mat.set_shader_parameter("rim_tint", Color(0.14, 0.38, 0.23))
	mat.set_shader_parameter("wave", 0.85)
	mat.set_shader_parameter("speed", 1.4)
	tend_mat = mat
	# Только НИТИ. Опорные и хватающие отсюда ушли в _build_arms: у осьминога
	# конечности одного рода — восемь рук, — а связка разнокалиберных отростков
	# читается как ёж. Эти нити остались как стекающая жижа, и их немного.
	for i in TENDRILS:
		var t := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006 + _rng.randf() * 0.010
		cm.bottom_radius = 0.045 + _rng.randf() * 0.035
		cm.height = 1.0
		cm.radial_segments = 8
		cm.rings = 22
		cm.cap_top = false
		t.mesh = cm
		t.material_override = mat
		# Спираль по золотому углу: случайные направления сбивались в пучок.
		var a: float = float(i) * 2.39996
		var up: float = asin(clampf(-0.35 + 1.2 * float(i) / float(TENDRILS - 1), -1.0, 1.0))
		var dir := Vector3(cos(a) * cos(up), sin(up), sin(a) * cos(up)).normalized()
		var ln: float = HEIGHT * (0.16 + _rng.randf() * 0.30)
		var centre := Vector3(0, HEIGHT * 0.60, 0)
		# Корень НА поверхности мантии: у неё переменный радиус, поэтому берём
		# его из профиля, а не из BLOB_R, — иначе нити висят в воздухе у шеи.
		var rr: float = _mantle_radius(dir.y)
		var root: Vector3 = centre + Vector3(dir.x * rr, dir.y * BLOB_R * MANTLE_H, dir.z * rr)
		# Цилиндр центрирован: без выноса наружу половина сидит внутри тела.
		t.position = root + dir * ln * 0.5
		t.rotation = Vector3(acos(clampf(dir.y, -1.0, 1.0)), atan2(dir.x, dir.z), 0.0)
		t.scale = Vector3(1, ln, 1)
		body.add_child(t)
		tendrils.append({"n": t, "ph": _rng.randf() * TAU, "len": ln, "rot": t.rotation})
	return


## ── ДВЕ ПОХОДКИ ───────────────────────────────────────────────────────────
##
## В КОРИДОРЕ ему тесно, и он этим пользуется: по одной руке упирается в левую
## и правую стену и отталкивается от них, две задние переступают по полу, две
## передние всё время тянутся к игроку, а лишние поджаты к телу — развести их
## в коридоре просто некуда.
##
## В ЗАЛЕ разводить есть куда: там он ползёт на всех восьми, руки переставляются
## волной по кругу.
##
## Общее у обеих походок одно: рука, ПОСТАВЛЕННАЯ на опору, стоит в мировой
## точке и не двигается, пока тело идёт вперёд. Только так и видно, что он
## отталкивается, а не машет конечностями в воздухе.


## Что вокруг: коридор или зал. Коридор — это когда по одной оси обе соседние
## клетки камень, а по другой есть проход.
func _probe_space() -> void:
	# СМОТРОВАЯ задаёт тесноту руками: лабиринта там нет, а коридорную походку
	# показать надо. Без этого флага замер каждые 0.3 с сбрасывал бы её обратно.
	if manual_space:
		return
	if maze == null:
		cramped = false
		return
	var me := _to_cell(global_position)
	# Клетка задаётся как (строка из z, столбец из x), поэтому сосед по X — это
	# сдвиг столбца, а по Z — сдвиг строки. Перепутать здесь легко, и тогда он
	# упирается руками в пустоту.
	var wx: bool = maze.is_wall(me.x, me.y - 1) and maze.is_wall(me.x, me.y + 1)
	var wz: bool = maze.is_wall(me.x - 1, me.y) and maze.is_wall(me.x + 1, me.y)
	var ox: bool = not maze.is_wall(me.x, me.y - 1) or not maze.is_wall(me.x, me.y + 1)
	var oz: bool = not maze.is_wall(me.x - 1, me.y) or not maze.is_wall(me.x + 1, me.y)
	var centre: Vector3 = _to_world(me)
	if wx and oz:
		cramped = true
		side_dir = Vector3.RIGHT
	elif wz and ox:
		cramped = true
		side_dir = Vector3.FORWARD
	else:
		cramped = false
		return
	# Точки на стенах берём от ЦЕНТРА КЛЕТКИ, а не от себя: сам он может стоять
	# у самой стены, и тогда «половина клетки в сторону» промахивается мимо.
	var half: float = cell_size * 0.5 - 0.10
	cell_mid = centre
	wall_a = centre + side_dir * half
	wall_b = centre - side_dir * half


## Кому что делать. Роли раздаются по МИРОВОМУ направлению руки, а не по номеру:
## тело всё время разворачивается к игроку, и закреплённые номера то и дело
## оказывались бы не с той стороны.
func _assign_roles() -> void:
	var fwd: Vector3 = global_transform.basis.z    # look_at целит игрока по +Z
	var to_p: Vector3 = aim_at - global_position
	to_p.y = 0.0
	if to_p.length() > 0.01:
		to_p = to_p.normalized()
	else:
		to_p = fwd
	# ДЕРЖИТ — значит держит: четыре руки уходят на обхват независимо от того,
	# в коридоре он или в зале.
	# ИЗО РТА. Пока держится фигура гуманоида, часть рук растёт не от венчика,
	# а из пасти: ловит он именно ими. Корень руки — обычный узел, его можно
	# переставить, и решатель сам посчитает позу от нового места.
	if form_kind == FORM_HUMAN and form_t > 0.55:
		var m: Vector3 = _mouth_local()
		for ai6 in arms.size():
			var a6: Dictionary = arms[ai6]
			if ai6 < ARM_MOUTH:
				# ОБХВАТЫВАЕТ ИМИ ЖЕ. Когда он держит, эти пять переходят с
				# «тянуться» на «смыкаться» — но растут по-прежнему изо рта.
				a6["role"] = ROLE_HOLD if hold_at != Vector3.ZERO else ROLE_MOUTH
				var r6: Node3D = a6["root"]
				r6.position = m
				# МЕЛЬЧЕ. Это щупальца осьминога: 2.6 м длиной и 27 см в
				# обхвате у основания. На груди фигуры шириной в полметра они
				# выглядели пятью брёвнами, из-за которых саму фигуру не видно.
				a6["scl"] = 0.38
			else:
				a6["role"] = ROLE_FLOOR
				a6["cyc"] = fmod(float(ai6 % 4) * 0.25
					+ (0.05 if ai6 >= 4 else 0.0), 1.0)
				a6["scl"] = 1.0
				(a6["root"] as Node3D).position = Vector3(a6["home"])
		return
	# Фигура кончилась — руки вернулись на место.
	for ai7 in arms.size():
		arms[ai7]["scl"] = 1.0
		(arms[ai7]["root"] as Node3D).position = Vector3(arms[ai7]["home"])
	# Отжимается от стены — это важнее всего прочего.
	if push_at != Vector3.ZERO:
		for ai4 in arms.size():
			arms[ai4]["role"] = ROLE_WALL if ai4 < 4 else ROLE_TUCK
			arms[ai4]["push"] = ai4 < 4
			arms[ai4]["cyc"] = [0.0, 0.5, 0.25, 0.75][ai4] if ai4 < 4 else 0.0
		return
	for ai5 in arms.size():
		arms[ai5]["push"] = false
	if hold_at != Vector3.ZERO:
		for ai3 in arms.size():
			arms[ai3]["role"] = ROLE_HOLD if ai3 < HOLD_ARMS else ROLE_FLOOR
			arms[ai3]["cyc"] = fmod(float(ai3) * 0.5625, 1.0)
		return
	if not cramped:
		# ЗЕРКАЛЬНО, А НЕ «КУДА ПРИРОСЛА». Раньше место опоры считали от того,
		# где рука приросла к мантии, и стороны выходили какие получатся: одна
		# половина туши могла остаться голой, и это было видно сразу. Теперь
		# места заданы таблицей и повторены на обе стороны точь-в-точь: сколько
		# ног справа, столько же и слева, на тех же расстояниях.
		# КАЖДАЯ РУКА РАБОТАЕТ НА СВОЮ СТОРОНУ. Подбирать «кому какое место»
		# перебором нельзя: последним рукам доставалось место на другой стороне
		# туши, они упирались в предел вытянутой руки и складывались под брюхом.
		# Руки растут по кругу через 45 градусов, поэтому сторона у каждой уже
		# известна: 1, 2, 3 — правая половина, 7, 6, 5 — левая. Спереди (0) и
		# сзади (4) ног нет, эти две поднимаются к телу.
		#
		# Раскладка зеркальная по построению: сколько ног справа, столько слева,
		# на тех же выносах. Пара напротив шагает вместе, поэтому в воздухе
		# всегда две ноги через тушу и ни одна сторона не пустеет.
		for aio in arms.size():
			arms[aio]["role"] = ROLE_TUCK
		var pairs := [[1, 7, 1.55, 0.0], [2, 6, 0.30, 0.25], [3, 5, -1.30, 0.5]]
		for pr in pairs:
			for half in 2:
				var idx: int = int(pr[half])
				arms[idx]["role"] = ROLE_FLOOR
				arms[idx]["side"] = 1.0 if half == 0 else -1.0
				arms[idx]["along"] = float(pr[2])
				arms[idx]["cyc"] = float(pr[3])
		return
	if false:
		for ai2 in arms.size():
			arms[ai2]["role"] = ROLE_FLOOR
			# ШАГАЮТ ПАРАМИ НАПРОТИВ. Прежняя раскладка (0.5625 на руку)
			# разводила фазы ровно по кругу — и это выглядело правильным, пока
			# я не посчитал, КТО именно оказывается в воздухе. Стоит доля
			# цикла ARM_DUTY = 0.74, значит поднято всегда две руки; при
			# сквозной раскладке эти две попадали в соседние фазы и оказывались
			# в одной четверти. Замер по смотровой: подняты были руки на 225° и
			# 315°, то есть вся задняя левая сторона пустела разом. Поднятая
			# рука прижата к телу и не читается — и сторона выглядела голой.
			#
			# Теперь фазу делят руки НАПРОТИВ друг друга (0 и 4, 1 и 5, ...):
			# в воздухе всегда пара через тушу, и с каждой стороны в любой
			# момент стоит поровну. Малый сдвиг у дальней половины — чтобы пара
			# не выглядела метрономом.
			arms[ai2]["cyc"] = fmod(float(ai2 % 4) * 0.25
				+ (0.05 if ai2 >= 4 else 0.0), 1.0)
		return
	var free: Array = []
	for ai in arms.size():
		arms[ai]["role"] = ROLE_TUCK
		free.append(ai)
	# ПО ОДНОМУ УПОРУ НА СТЕНУ, А НЕ ПО ДВА. Восемь рук делятся на три работы, и
	# раньше дележ был такой: четыре в стены, две тянутся к игроку, ДВЕ по полу.
	# То есть по полу он переступал всего двумя щупальцами из восьми — спереди
	# это читалось шаром на двух ногах. Ног должно быть видно больше, чем всего
	# остального: именно они превращают ком в идущее существо. Поэтому упор
	# теперь по одному на сторону — с обеих сторон он всё равно виден, а это и
	# было главным, — а освободившиеся две руки ушли в ноги.
	for pair in [[1.0, 0], [-1.0, 1]]:
		var sgn: float = float(pair[0])
		var best: int = -1
		var bd: float = -2.0
		for ai in free:
			var w: Vector3 = _arm_world_dir(arms[ai])
			var dt: float = w.dot(side_dir) * sgn
			if dt > bd:
				bd = dt
				best = ai
		if best >= 0:
			arms[best]["role"] = ROLE_WALL
			arms[best]["side"] = sgn
			arms[best]["slot"] = int(pair[1])
			arms[best]["cyc"] = [0.0, 0.5, 0.25, 0.75][int(pair[1])]
			free.erase(best)
	# Две передние тянутся к игроку — остальные заняты ходьбой.
	for _n in 2:
		var best2: int = -1
		var bd2: float = -2.0
		for ai in free:
			var dt2: float = _arm_world_dir(arms[ai]).dot(to_p)
			if dt2 > bd2:
				bd2 = dt2
				best2 = ai
		if best2 >= 0:
			arms[best2]["role"] = ROLE_REACH
			# НОМЕР В РЯДУ. Раньше сторону, в которую уходит рука, задавала её
			# собственная фаза — и на замере все три тянущиеся руки оказались
			# в левой половине экрана: справа не было ни одной. Теперь место в
			# ряду назначаем сами: слева, посередине, справа.
			arms[best2]["slot"] = _n
			arms[best2]["slots"] = 2
			free.erase(best2)
	# ЧЕТЫРЕ НОГИ, ПО ДВЕ С КАЖДОЙ СТОРОНЫ. Раньше их выбирали по одному
	# признаку — «самые задние», — и обе легко оказывались с одной стороны туши.
	# Сторону теперь назначаем сами, как у упоров: иначе симметрии нет и видно,
	# что он опирается на что попало.
	for pair2 in [[1.0, 0], [-1.0, 1], [1.0, 2], [-1.0, 3]]:
		var sgn2: float = float(pair2[0])
		var best3: int = -1
		var bd3: float = -2.0
		for ai in free:
			var w3: Vector3 = _arm_world_dir(arms[ai])
			# Вбок И назад: нога, ушедшая вперёд, спорит с тянущимися руками.
			var dt3: float = w3.dot(side_dir) * sgn2 - w3.dot(to_p) * 0.35
			if dt3 > bd3:
				bd3 = dt3
				best3 = ai
		if best3 >= 0:
			arms[best3]["role"] = ROLE_FLOOR
			arms[best3]["side"] = sgn2
			# Вразнобой: одновременный шаг четырьмя читается как прыжок.
			arms[best3]["cyc"] = [0.0, 0.5, 0.25, 0.75][int(pair2[1])]
			free.erase(best3)


## Мировое НАПРАВЛЕНИЕ в систему body: через to_local точки так не перевести,
## там прибавится сдвиг начала координат.
func _local_dir(v: Vector3) -> Vector3:
	return (body.global_transform.basis.inverse() * v).normalized()


## Схватить и поднять НАД СОБОЙ. Точка возвращается наружу — по ней мир
## поднимает игрока, чтобы он висел ровно там, где смыкаются руки.
func grab_hold(seconds: float) -> Vector3:
	hold_t = seconds
	hold_tight = 0.0
	# ПЕРЕД СОБОЙ И ВЫШЕ, а не прямо над макушкой. Мантия доходит до 4 м, и
	# точка ровно над центром оказывалась ВНУТРИ туши: игрока затягивало в тело,
	# и он видел его изнутри — сквозь невидимую с изнанки поверхность торчали
	# щупальца и просвечивал мир. Вынос вперёд убирает это и заодно оставляет
	# рукам запас: от венчика до точки 2.0 м при рабочей длине 2.1.
	# ДАЛЬШЕ ОТ ТЕЛА. 1.5 м вперёд было мало: мантия шириной под метр, а её
	# поверхность ещё и кипит наружу — игрок оказывался в полутора десятках
	# сантиметров от оболочки и то и дело проваливался внутрь. Два метра вперёд
	# и ниже по высоте: от венчика рук до точки 1.9 м при рабочей длине 2.1.
	# У ФИГУРЫ — ОТ ГРУДИ. Высота «0.80 от роста кома» — это 2.16 м, и для
	# пятиметровой фигуры она приходится на колени: после атаки камера уезжала
	# ей в ноги. Держит он перед пастью, значит и точка от пасти.
	if form_kind == FORM_HUMAN and human != null and human.visible:
		var chest: Vector3 = body.global_transform * _mouth_local()
		hold_at = chest + global_transform.basis.z * 1.6
	else:
		hold_at = global_position + global_transform.basis.z * 2.0 \
			+ Vector3(0, HEIGHT * 0.80, 0)
	# Щупальце-язык на время хвата убираем: одна красная кишка, тыкающая в
	# камеру, читалась как «облизал», а не «схватил».
	if reach != null:
		reach.visible = false
	reach_t = 0.0
	return hold_at


func drop_hold() -> void:
	hold_at = Vector3.ZERO
	hold_t = 0.0
	hold_tight = 0.0
	replant()


## Кончил отжиматься от стены — руки обратно на пол.
func end_push() -> void:
	push_at = Vector3.ZERO
	push_n = Vector3.ZERO
	replant()


## ПЕРЕСТАВИТЬ ВСЕ РУКИ ЗАНОВО. Опора живёт до конца своего такта, а такт
## крутится от пройденного пути — значит, когда он стоит, опора не меняется
## НИКОГДА. После сцены руки так и оставались вытянутыми туда, где была стена,
## и на землю не вставали. Сбрасываем признак «стоит», и следующий же кадр
## посчитает опору заново — уже по полу.
func replant() -> void:
	for arm in arms:
		arm["down"] = false
		arm["push"] = false


## Куда рука смотрит в покое, в мировых координатах.
func _arm_world_dir(arm: Dictionary) -> Vector3:
	var y: float = float(arm["yaw"])
	return (global_transform.basis * Vector3(sin(y), 0.0, cos(y))).normalized()


func _walk_arms(delta: float) -> void:
	if arms.is_empty() or not visible:
		return
	_space_t -= delta
	if hold_t > 0.0:
		hold_t -= delta
		# Сжимает толчками, а не ровно: ровное стягивание читается как
		# механизм, толчками — как то, что дышит.
		hold_tight = clampf(0.35 + 0.65 * absf(sin(_shiv * 1.9)), 0.0, 1.0)
		if hold_t <= 0.0:
			drop_hold()
	_hit_cool = maxf(0.0, _hit_cool - delta)
	_step_cool = maxf(0.0, _step_cool - delta)
	# НАСКОЛЬКО ОН СЕЙЧАС ИДЁТ. Считаем по приросту шага за кадр: gait крутится
	# от пройденного пути, значит его скорость — это и есть скорость хода.
	# Нужно, чтобы туша не оставалась накрененной, когда он встал.
	var dg: float = fmod(gait - _gait_prev + 1.0, 1.0)
	_gait_prev = gait
	gait_move = lerpf(gait_move, clampf(dg / maxf(delta, 0.001) * 1.7, 0.0, 1.0),
		minf(1.0, delta * 7.0))
	if _space_t <= 0.0:
		_space_t = SPACE_T
		_probe_space()
		_assign_roles()
	var fwd: Vector3 = global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var foot_y: float = global_position.y + 0.06
	# ТЕЛО ТОЛКАЕТСЯ ВМЕСТЕ С РУКАМИ. Раньше оно висело неподвижным комом, а
	# щупальца шевелились сами по себе — со стороны это читалось как «картошка,
	# вокруг которой что-то машет». Теперь на каждый упор туша проседает и
	# кренится в сторону толчка, а между упорами подбрасывается вперёд.
	#
	# Руки при этом не едут: их опоры заданы в МИРОВЫХ координатах, и решатель
	# сам довернёт цепочку под качнувшееся тело. Именно от этого и появляется
	# ощущение, что толкается он, а не его анимация.
	var ph: float = gait * TAU
	var mv: float = gait_move
	body.position.y = HEIGHT * (0.020 * sin(ph * 2.0) - 0.012) * mv
	body.rotation.z = sin(ph) * 0.085 * mv
	body.rotation.x = (-0.05 + cos(ph * 2.0) * 0.055) * mv
	for ai in arms.size():
		var arm: Dictionary = arms[ai]
		var role: int = int(arm.get("role", ROLE_FLOOR))
		match role:
			ROLE_REACH:
				_pose_reach(arm, ai)
			ROLE_MOUTH:
				_pose_mouth(arm, ai)
			ROLE_HOLD:
				_pose_hold(arm, ai)
			ROLE_TUCK:
				_pose_tuck(arm)
			ROLE_WALL:
				_pose_step(arm, ai, fwd, true, foot_y)
			_:
				_pose_step(arm, ai, fwd, false, foot_y)


## Фигура покачивается и переминается. Ничего сложного: она стоит и смотрит,
## а щупальца изо рта делают всю работу.
## ДВЕ ПОХОДКИ ФИГУРЫ.
##
## В ЗАЛЕ она идёт согнувшись, приволакивая одну ногу и время от времени
## дёргаясь. В КОРИДОРЕ ей не встать в рост: она ползёт на коленях, а длинные
## руки тянет вперёд, к игроку, и подтягивается ими.
##
## Всё считается по костям: чужая анимация модели остановлена, иначе она
## перезаписывала бы позы каждый кадр. Заодно так выходит криво — а нам и надо
## криво, человеческая походка тут была бы хуже всего.
func _sway_human(delta: float, k: float) -> void:
	if human == null or k <= 0.01:
		return
	# БЕЗ РАСКАЧКИ ВБОК. Наклон всего тела туда-сюда читался не как походка, а
	# как кукла, которую качают за макушку: ноги при этом не двигались вовсе.
	# Вместо крена — лёгкое покачивание по высоте на каждый шаг, как у идущего
	# человека, и оно считается ниже, вместе с походкой.
	human.rotation.z = 0.0
	if human_skel == null or hb.is_empty():
		return
	# РЫВКИ. Редкие и короткие: то, что дёргается ровно, читается как механизм.
	twitch_t -= delta
	if twitch_t <= 0.0:
		twitch_t = randf_range(1.4, 3.4)
		twitch = 1.0
	twitch = maxf(0.0, twitch - delta * 3.5)
	var jerk: float = twitch * twitch * (0.7 + 0.3 * sin(_shiv * 41.0))
	# НА КОЛЕНЯХ — ЗНАЧИТ НИЖЕ. Согнуть кости мало: фигура складывала ноги, но
	# оставалась на прежней высоте и стояла на коленях В ВОЗДУХЕ. Опускаем её
	# целиком, плавно, чтобы переход между походками не был скачком.
	crawl_k = move_toward(crawl_k, 1.0 if cramped else 0.0, delta * 2.2)
	human.position.y = -0.62 * crawl_k
	var ph: float = gait * TAU
	if arms_up > 0.01:
		_pose_human_reach_up(jerk)
		return
	if cramped:
		_pose_human_crawl(ph, jerk)
	else:
		_pose_human_walk(ph, jerk)
	return


## ТЯНЕТСЯ ВВЕРХ. Замер, голова запрокинута, обе руки уходят над головой —
## и в этот момент над игроком опускаются другие руки.
func _pose_human_reach_up(jerk: float) -> void:
	var sk3: Skeleton3D = human_skel
	for nm in ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]:
		if hb.has(nm):
			sk3.set_bone_pose_scale(int(hb[nm]), arm_stretch[nm])
	var k: float = arms_up
	# ЗНАК ПОЗВОНОЧНИКА. Разобрал позу по одной кости и записал высоту кисти:
	#   всё в покое            -2.69
	#   только плечо Z=1.45     5.17   <- подъём работает
	#   + локоть                5.24
	#   + таз  -0.10            4.63
	#   + живот -0.18           3.53
	#   + торс -0.16            2.60
	# То есть подъём я делал правильно, а потом сам же ронял руку на два с
	# половиной метра тремя костями корпуса: у этого скелета отрицательный
	# угол по X наклоняет спину ВПЕРЁД, а не назад, и утягивает плечи вниз.
	# ПОЗВОНОЧНИК НЕ ТРОГАЕМ ВОВСЕ. Поворот по X у этих трёх костей роняет
	# поднятую руку В ЛЮБУЮ СТОРОНУ: с -0.10/-0.18/-0.16 кисть падала с 5.24
	# до 2.60, с плюсами — до 2.42. Он не наклоняется, он просто тянется.
	# ЗАМЕР: при чистом Z локти уходили на z −7.7 при плече −6.5, то есть руки
	# задирались ВВЕРХ И НАЗАД, за спину, и спереди их не было видно вовсе.
	# Небольшой наклон корпуса вперёд возвращает их над головой — это не
	# «сгибание позвоночника», которое роняло руку, а компенсация заброса.
	_bone("Hips", 0.16 * k, 0.0, 0.0)
	_bone("Abdomen", 0.30 * k, 0.0, 0.0)
	_bone("Torso", 0.22 * k, 0.0, 0.0)
	# Голова запрокинута: он смотрит туда же, куда тянет.
	_bone("Neck", 0.0, 0.0, 0.0)
	_bone("Head", 0.0, jerk * 0.25, 0.15)
	# ПЛЕЧО НЕ ТРОГАЕМ. Его доворот складывался с доворотом руки и разворачивал
	# её обратно вниз: на замере кисть уезжала с 2.25 на 0.4, то есть к полу.
	_bone("Shoulder.L", 0.0, 0.0, 0.0)
	_bone("Shoulder.R", 0.0, 0.0, 0.0)
	# ЧИСТАЯ ОСЬ, без примеси. Замер по шагам: поворот плеча по Z на 1.5 поднимает
	# кисть с 2.25 до 6.87. Но мешать его с малым X нельзя — Godot складывает
	# углы в порядке YXZ, и примесь съедала почти весь подъём.
	# ЗЕРКАЛЬНЫЙ СКЕЛЕТ — ЗЕРКАЛЬНЫЙ ЗНАК. У обеих рук стоял плюс, и правая
	# уходила не вверх, а вперёд: получался не замах в потолок, а поза с
	# известной картины. У правой стороны та же ось поворачивает в другую
	# сторону, поэтому здесь минус.
	_bone("UpperArm.L", 0.0, 0.0, 1.85 * k)
	_bone("UpperArm.R", 0.0, 0.0, -1.85 * k)
	# Локти почти прямые: он ВОНЗАЕТ руки в потолок, а не держит их над собой.
	_bone("LowerArm.L", 0.12, 0.0, 0.0)
	_bone("LowerArm.R", 0.12, 0.0, 0.0)
	_bone("UpperLeg.L", 0.0, 0.0, 0.05)
	_bone("UpperLeg.R", 0.0, 0.0, -0.05)
	_bone("LowerLeg.L", 0.05, 0.0, 0.0)
	_bone("LowerLeg.R", 0.05, 0.0, 0.0)


## Повернуть кость относительно её позы покоя. Именно относительно: поза в
## Godot — это ПОЛНЫЙ локальный поворот, и записать туда голый угол значит
## сложить скелет в кучу.
func _bone(name: String, x: float, y: float, z: float) -> void:
	if not hb.has(name):
		return
	var q: Quaternion = Quaternion.from_euler(Vector3(x, y, z))
	(human_skel as Skeleton3D).set_bone_pose_rotation(int(hb[name]), hrest[name] * q)


## ЗАЛ: идёт согнувшись и хромает. Хромота — это не «одна нога короче», а
## РАЗНЫЙ РАЗМАХ: здоровая нога делает полный шаг, больная еле переставляется,
## и на каждый её шаг тело проваливается вниз.
func _pose_human_walk(ph: float, jerk: float) -> void:
	# ХОДЬБА, А НЕ КАЧАНИЕ. Раньше здесь была хромота: левая нога махала, правая
	# почти стояла, а тело кренилось вбок. Со стороны это читалось как
	# пластиковая кукла, которую шатают, — ног при этом было не разобрать.
	# Теперь обе ноги ходят в противофазе, и главное — КОЛЕНО СГИБАЕТСЯ у той
	# ноги, что идёт вперёд по воздуху. Кривизна остаётся, но она в другом:
	# шаги разной длины и корпус завален вперёд.
	var swing: float = sin(ph)
	var back: float = sin(ph + PI)
	# Колено гнётся, когда голень уходит назад-вверх, и распрямляется к опоре.
	var knee_l: float = maxf(0.0, -swing) * 1.05
	var knee_r: float = maxf(0.0, -back) * 1.05
	# Тело чуть подпрыгивает на каждый шаг: два подъёма за полный цикл.
	human.position.y = -0.62 * crawl_k + absf(sin(ph)) * 0.045
	_bone("Hips", -0.08, sin(ph) * 0.12, 0.0)
	# Согнут вперёд всегда: выпрямленная фигура читается человеком.
	_bone("Abdomen", 0.26, 0.0, 0.0)
	_bone("Torso", 0.20, sin(ph) * -0.10, jerk * 0.10)
	_bone("Neck", -0.30 + jerk * 0.22, sin(ph * 0.5) * 0.10, jerk * 0.16)
	_bone("Head", -0.12, jerk * 0.30, 0.18)
	# Ноги: шаг у левой шире — он всё-таки не человек.
	_bone("UpperLeg.L", swing * 0.66, 0.0, 0.04)
	_bone("LowerLeg.L", knee_l, 0.0, 0.0)
	_bone("UpperLeg.R", back * 0.52, 0.0, -0.04)
	_bone("LowerLeg.R", knee_r, 0.0, 0.0)
	# Руки висят и раскачиваются в противофазу ногам, левая длиннее — она и
	# болтается сильнее.
	# ОСИ ПРОВЕРЕНЫ ЗАМЕРОМ, а не на глаз. Я поворачивал каждую кость по каждой
	# оси на 0.6 радиана и смотрел, куда уехала кисть:
	#   плечо, X — мах ВБОК: 3.2 м вбок против 1.8 вперёд;
	#   плечо, Y — почти ноль, это скрутка вдоль кости;
	#   плечо, Z — вверх и назад;
	#   ЛОКОТЬ, X — единственное, что реально УКОРАЧИВАЕТ руку: с 7.80 до 6.90.
	# Отсюда и «руки не гнутся, а болтаются вбок»: локоть я гнул на 0.25, то
	# есть на четырнадцать градусов, а махал плечом как раз по боковой оси.
	# В рост — руки во всю длину, как и задумано.
	var sk1: Skeleton3D = human_skel
	for nm in ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]:
		if hb.has(nm):
			sk1.set_bone_pose_scale(int(hb[nm]), arm_stretch[nm])
	# Руки идут в противофазе ногам: левая нога вперёд — правая рука вперёд.
	_bone("Shoulder.L", 0.0, 0.0, 0.10 + jerk * 0.2)
	_bone("Shoulder.R", 0.0, 0.0, -0.08)
	_bone("UpperArm.L", back * 0.30, 0.0, 0.0)
	_bone("UpperArm.R", swing * 0.30, 0.0, 0.0)
	_bone("LowerArm.L", 0.18 + maxf(0.0, back) * 0.30, 0.0, 0.0)
	_bone("LowerArm.R", 0.16 + maxf(0.0, swing) * 0.30, 0.0, 0.0)
	_bone("UpperArm.L", 0.10 + swing * 0.10, 0.0, -0.30)
	_bone("UpperArm.R", 0.12 - swing * 0.08, 0.0, -0.26)
	# Локти согнуты ВСЕГДА и подрабатывают в такт шагу: висящие плети выглядят
	# смешно, согнутые — как «приготовился хватать».
	_bone("LowerArm.L", 1.35 + swing * 0.22 + jerk * 0.30, 0.0, 0.0)
	_bone("LowerArm.R", 1.20 - swing * 0.18, 0.0, 0.0)


## КОРИДОР: в рост не встать. Ползёт на коленях, руки тянет вперёд и
## подтягивается ими — левая и правая по очереди.
func _pose_human_crawl(ph: float, jerk: float) -> void:
	var pull_l: float = sin(ph)
	var pull_r: float = sin(ph + PI)
	# Таз опущен и завален вперёд: колени под ним.
	# НАКЛОН СКЛАДЫВАЕТСЯ. Было 0.55 + 0.42 + 0.30 — это 75 градусов, и фигура
	# ныряла лицом в пол. Три кости вместе должны давать наклон, а не кувырок.
	_bone("Hips", 0.22, sin(ph) * 0.14, 0.0)
	_bone("Abdomen", 0.20, 0.0, sin(ph) * 0.08)
	_bone("Torso", 0.16, sin(ph) * -0.16, jerk * 0.12)
	# Голова задрана: смотрит на тебя снизу.
	_bone("Neck", -0.45 + jerk * 0.25, 0.0, 0.0)
	_bone("Head", -0.30, jerk * 0.35, 0.18)
	# Колени подобраны под себя, голени сложены.
	_bone("UpperLeg.L", 1.25 + pull_l * 0.22, 0.0, 0.10)
	_bone("UpperLeg.R", 1.25 + pull_r * 0.18, 0.0, -0.10)
	_bone("LowerLeg.L", -1.55, 0.0, 0.0)
	_bone("LowerLeg.R", -1.55, 0.0, 0.0)
	# РУКИ ВПЕРЁД. Поднимаются над головой и опускаются: подтягивает ими себя.
	# ВДВОЕ КОРОЧЕ. В рост длинные руки читаются как уродство, а на четвереньках
	# они просто волочатся впереди на два метра и мешают смотреть на саму тварь.
	var sk2: Skeleton3D = human_skel
	for nm in ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]:
		if hb.has(nm):
			var full: Vector3 = arm_stretch[nm]
			# Натуральная длина: множитель вытяжки на четвереньках снимается
			# целиком. Замер — 3.85 м в рост против 1.9 ползком.
			sk2.set_bone_pose_scale(int(hb[nm]), Vector3(full.x, 1.0, full.z))
	_bone("Shoulder.L", 0.0, 0.0, 0.22)
	_bone("Shoulder.R", 0.0, 0.0, -0.22)
	# Доворот по Y сводит руки ВПЕРЁД. Без него они уходили в стороны: у этого
	# скелета поворот вокруг X машет рукой вбок, а не вдоль тела.
	# Ползёт — руки идут вперёд и врозь, как у ящерицы, и подтягивают по
	# очереди. Мах по X у этого скелета как раз даёт «вперёд и в сторону»,
	# а локоть по X складывает предплечье внутрь.
	_bone("UpperArm.L", 0.55 + pull_l * 0.30, 0.0, 0.20)
	_bone("UpperArm.R", 0.52 + pull_r * 0.30, 0.0, 0.18)
	_bone("LowerArm.L", 0.95 - maxf(0.0, pull_l) * 0.45, 0.0, 0.0)
	_bone("LowerArm.R", 0.95 - maxf(0.0, pull_r) * 0.45, 0.0, 0.0)


## Где пасть в системе body: направление от центра кома, умноженное на радиус.
func _mouth_local() -> Vector3:
	# Пока стоит фигура — рот у неё на груди; ком в это время лужей на полу.
	if form_kind == FORM_HUMAN and human != null and human.visible:
		# Точку берём от КОСТИ ГРУДИ, а не на глаз: модель вытянута костями, и
		# любое число, посчитанное от пола, уезжает вместе с ними. На кадре
		# щупальца лезли из паха.
		if human_skel != null:
			var sk: Skeleton3D = human_skel
			# МЕЖДУ ТОРСОМ И ШЕЕЙ. Кость «Torso» у этого скелета сидит внизу
			# спины, почти на тазу, и пасть с щупальцами оказывалась у фигуры
			# между ног. Берём точку ближе к шее — это и есть грудь.
			var bi: int = sk.find_bone("Torso")
			var ni: int = sk.find_bone("Neck")
			if bi >= 0 and ni >= 0:
				var wt: Vector3 = sk.global_transform * sk.get_bone_global_pose(bi).origin
				var wn: Vector3 = sk.global_transform * sk.get_bone_global_pose(ni).origin
				return body.to_local(wt.lerp(wn, 0.72)) + mouth_dir * 0.34
		return Vector3(0, 2.15, 0) + mouth_dir * 0.42
	var c := Vector3(0, HEIGHT * 0.60, 0)
	return c + mouth_dir * BLOB_R * 0.92


## ЩУПАЛЬЦЕ ИЗО РТА. Лезет наружу вдоль взгляда пасти и тянется к игроку,
## каждое своей дугой. Пока игрока рядом нет — шарит перед собой.
func _pose_mouth(arm: Dictionary, ai: int) -> void:
	var root: Node3D = arm["root"]
	var out: Vector3 = _local_dir(global_transform.basis * mouth_dir)
	var goal: Vector3 = root.position + out * float(arm.get("len", ARM_LEN)) * 1.05
	if aim_at != Vector3.ZERO:
		var l: Vector3 = body.to_local(aim_at)
		var d: Vector3 = l - root.position
		if d.length() > 0.05:
			goal = root.position + d.normalized() \
				* minf(d.length() * 0.95, float(arm.get("len", ARM_LEN)) * 1.05)
	# Каждое своей стороной: пятеро, целящихся в одну точку, слипаются в жгут.
	# ВЕЕРОМ, а не пучком в одну точку. Пять щупалец, нацеленных прямо в игрока,
	# видны с его места как пять коротких шипов: вся длина уходит в ракурс.
	# Разброс берём от длины самой руки, иначе на дистанции он теряется.
	var ang: float = TAU * float(ai) / float(ARM_MOUTH) + _shiv * 0.9
	var side: Vector3 = Vector3(cos(ang), sin(ang) * 0.7, 0.0)
	_pose_arm(arm, goal + side * float(arm.get("len", ARM_LEN)) * 0.62, side, 0.40)


## ОБВИВАЕТ. Рука целится не в точку, а ЗА неё — на четверть длины дальше и в
## сторону, — поэтому дуга проходит мимо и смыкается кольцом. Чем плотнее
## сжатие, тем ближе кольца к телу и тем сильнее подвёрнут кончик.
func _pose_hold(arm: Dictionary, ai: int) -> void:
	var root: Node3D = arm["root"]
	var local: Vector3 = body.to_local(hold_at)
	var ang: float = TAU * float(ai) / float(HOLD_ARMS) + _shiv * 0.6
	var side: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
	# Кольцо сжимается: 0.62 в обхвате, 0.24 в сжатии.
	# ТЕСНЕЕ. Кольцо в 0.62-0.24 проходило далеко от лица, и руки оставались
	# где-то по краям. Держат вплотную — значит и петли идут вплотную.
	var r: float = lerpf(0.40, 0.14, hold_tight)
	var aim: Vector3 = local + side * r + Vector3(0.0, sin(ang * 2.0) * 0.18, 0.0)
	# Выгиб — наружу от кольца, тогда рука обходит игрока по дуге, а не
	# протыкает его насквозь.
	_pose_arm(arm, aim, side, 0.55 + hold_tight * 0.45)


## Шаг: рука стоит на опоре большую часть цикла, потом отрывается и заносится
## вперёд. Опора хранится в МИРОВЫХ координатах, поэтому пока тело едет вперёд,
## рука сама уходит назад относительно тела — это и есть отталкивание.
func _pose_step(arm: Dictionary, ai: int, fwd: Vector3, on_wall: bool, foot_y: float) -> void:
	var c: float = fmod(gait + float(arm.get("cyc", 0.0)), 1.0)
	var plant: Vector3 = arm.get("plant", Vector3.ZERO)
	var stance: bool = c < ARM_DUTY
	if stance:
		if not bool(arm.get("down", false)):
			arm["plant"] = _next_plant(arm, ai, fwd, on_wall, foot_y)
			arm["down"] = true
			plant = arm["plant"]
			# УДАР О СТЕНУ — ровно в момент постановки, а не по таймеру: так
			# звук совпадает с тем, что видно. Выдержка нужна потому, что на
			# полном ходу цикл прокручивается по три раза в секунду, и без неё
			# упоры сливаются в дробь.
			# Звук ставится в момент упора, а не по таймеру: только так он
			# совпадает с тем, что видно.
			# УПОР — НЕ ШАГ. Пока он выдавливается из стены, четыре руки стоят
			# ВРАСПОР, а не переступают: настоящий упор не шлёпает по камню
			# пять раз в секунду. А выдержка стояла одна на всех, и на выходе
			# из стены удары сливались в сплошную мокрую кашу — её и слышно
			# как нарастающий шум ровно в тот момент, когда он лезет наружу.
			# Замер по файлам: step_wet и hit_mid почти целиком высокочастотные,
			# поэтому слитые в поток они звучат не ударами, а шипением.
			var push_now: bool = bool(arm.get("push", false))
			if on_wall and _hit_cool <= 0.0:
				_hit_cool = 0.62 if push_now else 0.22
				wall_hit.emit(plant, true)
			elif not on_wall and _step_cool <= 0.0:
				_step_cool = 0.20
				wall_hit.emit(plant, false)
	else:
		arm["down"] = false
		# Перенос: от старой опоры к новой по дуге через верх.
		var k0: float = (c - ARM_DUTY) / (1.0 - ARM_DUTY)
		# Хлыст: первую половину переноса рука почти стоит, вторую — летит.
		var k: float = pow(k0, ARM_SNAP)
		var nxt: Vector3 = _next_plant(arm, ai, fwd, on_wall, foot_y)
		plant = plant.lerp(nxt, k)
		# Отрыв: настенная отходит ОТ стены, половая поднимается вверх.
		# Без отрыва рука едет по опоре юзом, и весь шаг пропадает.
		var sgn2: float = signf(float(arm.get("side", 1.0)))
		var off_dir: Vector3 = Vector3.UP
		if bool(arm.get("push", false)):
			off_dir = push_n
		elif on_wall:
			off_dir = -side_dir * sgn2
		plant += off_dir * sin(k0 * PI) * ARM_LIFT
	# ЩИКОЛОТКА ВЫШЕ СТОПЫ. Дуга приходит точно в цель, но ПОСЛЕ неё идут ещё
	# два звена — они всегда уходят дальше. У настенной руки это незаметно, а у
	# ноги цель лежит на полу, и лишнее втыкается в землю. Замер по смотровой:
	# концы трёх ног из четырёх были на 14-40 см НИЖЕ пола, наружу торчали
	# огрызки — оттого ног и было видно две вместо четырёх. Целимся выше опоры,
	# и последние звенья доводят стопу ровно до пола.
	var aim_p: Vector3 = plant
	if not on_wall:
		aim_p += Vector3.UP * 0.42
	var local: Vector3 = body.to_local(aim_p)
	# Опора не дальше вытянутой руки. Замер по кадрам: точки, которые ложились
	# за 2.17 (это вся рабочая длина), рука недобирала на 0.6 м, и шаг вместо
	# упора превращался в тычок в воздух.
	var root2: Node3D = arm["root"]
	var nseg: int = arm["joints"].size()
	var reach_max: float = float(arm.get("len", ARM_LEN)) * float(nseg - 2) \
		/ float(nseg) * 0.97
	var away: Vector3 = local - root2.position
	if away.length() > reach_max:
		local = root2.position + away.normalized() * reach_max
	# Выгиб — куда рука горбится по дороге к опоре: без него она идёт по прямой
	# и выглядит палкой, а не щупальцем.
	var bow: Vector3 = Vector3.UP
	if bool(arm.get("push", false)):
		bow = _local_dir(-push_n)
	# ВВЕРХ, А НЕ В СТЕНУ. Настенная рука горбилась НАРУЖУ — то есть ровно в ту
	# породу, к которой тянулась. Кисть при этом стояла правильно, на грани, а
	# середина руки уходила в камень: замер — 40% звеньев внутри. Со стороны это
	# не «упёрся в стену», а «рука наполовину утонула». Горб вверх оставляет её
	# в проходе целиком, а кисть по-прежнему приходит на камень.
	# Кончик подворачивается заметно: на 0.30 рука кончалась прямой палкой,
	# и вся связка читалась ногами, а не щупальцами.
	_pose_arm(arm, local, bow, 0.58)


## НОГИ ЧУТЬ ШИРЕ ПРОХОДА — И ВСЁ.
##
## Разводились они на глаз: «шире, а то он читается катящимся шаром». В зале это
## верно, а в коридоре шириной 2.8 м нога уходила на 2.32 м от оси — почти на
## метр в породу. Замер по прямому участку в 25 м: 36% звеньев опорных ног
## стояли в камне, у семи ног из десяти в стене была больше трети длины. Снаружи
## от такой ноги торчит обрубок — отсюда и «щупальца только с одной стороны»,
## хотя они есть со всех.
##
## Считать надо ОТ ОСИ ПРОХОДА, а не от самого монстра: он редко идёт ровно по
## середине, и симметричный развод от его собственного места одну ногу оставляет
## в проходе, а другую загоняет в стену.
##
## 1.45 при стенах на 1.40: стопа заходит в камень на пять сантиметров. Ровно
## настолько, чтобы она выглядела упёртой в стену, а не висящей перед ней.
const LEG_HALF := 1.45


func _corridor_clamp(p: Vector3) -> Vector3:
	if not cramped:
		return p
	var lat: float = (p - cell_mid).dot(side_dir)
	var over: float = absf(lat) - LEG_HALF
	if over <= 0.0:
		return p
	return p - side_dir * signf(lat) * over


## Куда ставить руку в следующий раз: вперёд по ходу и в свою сторону.
func _next_plant(arm: Dictionary, ai: int, fwd: Vector3, on_wall: bool, foot_y: float) -> Vector3:
	if bool(arm.get("push", false)):
		# Упор В СТЕНУ ПОЗАДИ. Четыре точки врозь и на разной высоте, чтобы
		# это выглядело как «выдавливается», а не как четыре одинаковых поршня.
		var side: Vector3 = push_n.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		var lat: float = [-0.95, 0.95, -0.45, 0.45][ai % 4]
		var hgt: float = [1.05, 1.35, 2.05, 1.75][ai % 4]
		# Чуть ВНУТРЬ камня: рука должна упереться в него, а не зависнуть перед.
		return push_at + side * lat + Vector3(0.0, hgt, 0.0) - push_n * 0.12
	if on_wall:
		var sgn: float = signf(float(arm.get("side", 1.0)))
		var w: Vector3 = wall_a if sgn > 0.0 else wall_b
		# ВРАЗНОБОЙ. Четыре упора на одной высоте и в одной точке вдоль коридора
		# сливаются в две палки; разводим их по высоте и вперёд-назад, тогда
		# видно распор.
		var slot: int = int(arm.get("slot", 0))
		var hgt: float = [0.30, 0.58, 0.72, 0.44][slot % 4]
		var along: float = [1.05, 0.35, -0.45, 1.35][slot % 4]
		return Vector3(w.x, global_position.y + HEIGHT * hgt, w.z) \
			+ fwd * (ARM_STRIDE + along)
	var d: Vector3 = _arm_world_dir(arm)
	# В МЕТРАХ, а не в долях клетки: размер тела от размера клетки не зависит.
	# 1.29 м от центра — это всего на четверть метра дальше края мантии, и на
	# кадре руки оказывались спрятаны прямо под телом. В зале разводим широко.
	# 2.45, а не 2.15: мантия сама 1.9 м в ширину, и при малом выносе наружу
	# торчал только метр руки — восемь коротких обрубков вокруг яйца. Лишнее
	# всё равно подрежет ограничение по вытянутой руке.
	# В КОРИДОРЕ ТОЖЕ ШИРОКО. На 1.25 м опоры оказывались ровно под мантией —
	# ног не видно, и он читался катящимся шаром. Вбок мешают стены, поэтому
	# выносим в основном ВПЕРЁД и НАЗАД, вдоль прохода.
	var spread: float = 1.95 if cramped else 3.40
	# Свой вынос у каждой руки: по идеальной окружности опоры читаются как
	# циркуль, а не как то, чем он цепляется за пол.
	spread *= 0.86 + 0.28 * fmod(float(ai) * 0.37, 1.0)
	# В ЗАЛЕ — ПО ТАБЛИЦЕ. Место ноги задано стороной и выносом вдоль тела,
	# поэтому правая и левая половины получаются одинаковыми по построению.
	if not cramped and not on_wall and arm.has("along"):
		var sgn_t: float = signf(float(arm.get("side", 1.0)))
		var along_t: float = float(arm["along"])
		var rightv: Vector3 = global_transform.basis.x
		var pt: Vector3 = global_position + rightv * sgn_t * LEG_SIDE \
			+ fwd * (along_t + ARM_STRIDE * 0.45)
		pt.y = foot_y
		return _corridor_clamp(pt)
	var lateral: float = 1.05 if cramped else 1.0
	var dd: Vector3 = Vector3(d.x * lateral, 0.0, d.z * lateral).normalized() if cramped else d
	# НОГА СТАВИТСЯ В СВОЮ СТОРОНУ. Сторону ей назначают при раздаче ролей, но
	# сюда это не доходило: точку опоры считали от того, где рука ПРИРОСЛА к
	# мантии, а вперёд её тянет ещё и шаг. Замер по смотровой: четыре ноги
	# вставали как +1.38, -1.58, -1.51 и -0.03 — то есть две слева, одна справа
	# и одна под самым брюхом. Теперь поперёк прохода ногу разводит назначенная
	# сторона, а вдоль — её собственный вынос вперёд или назад.
	if cramped and not on_wall:
		var sgn: float = signf(float(arm.get("side", 1.0)))
		dd = (side_dir * sgn * 0.95 + fwd * clampf(d.dot(fwd), -0.8, 0.8)).normalized()
	var p: Vector3 = global_position + dd * spread \
		+ fwd * (ARM_STRIDE * (0.5 + 0.5 * d.dot(fwd)) + (0.9 if cramped else 0.0) * d.dot(fwd))
	p.y = foot_y
	return _corridor_clamp(p)


## Тянется к игроку. Целится МИМО, каждая со своей стороны: рука, направленная
## точно в камеру, видна как обрубок — вся длина уходит в ракурс.
func _pose_reach(arm: Dictionary, ai: int) -> void:
	var goal: Vector3 = aim_at if aim_at != Vector3.ZERO else global_position + global_transform.basis.z * 3.0
	var d: Vector3 = goal - global_position
	var dir: Vector3 = d.normalized() if d.length() > 0.01 else global_transform.basis.z
	var side: Vector3 = dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var upv: Vector3 = side.cross(dir).normalized()
	# РАЗВОДИМ ПО ЧИСЛУ РУК, а не по жёсткой сетке. Сетка была рассчитана на
	# три: слева, посередине, справа. Когда тянущихся стало две, им достались
	# «слева» и «посередине» — и справа не оказывалось ни одной, отчего все
	# щупальца в кадре были с одной стороны.
	var slot: float = float(arm.get("slot", 0))
	var total: float = maxf(1.0, float(arm.get("slots", 2)))
	# РАЗВОД ИДЁТ ВБОК. Раньше сторону задавал косинус, а он у +82 и -82
	# градусов ОДИНАКОВЫЙ — то есть вбок обе руки уходили совершенно одинаково,
	# а различались только высотой: одна вверх, другая вниз. Замер по смотровой:
	# обе тянущиеся оказывались слева (x = -1.29 и -1.05). Теперь сторону задаёт
	# синус, и слоты расходятся честно влево и вправо.
	var span: float = PI * 0.9
	var ang: float = -span * 0.5 + (slot + 0.5) * (span / total) \
		+ sin(_shiv * 0.7 + float(arm["ph"])) * 0.22
	# ШИРЕ РАЗВОДИМ. С 0.75 руки шли почти прямо на игрока, а рука, направленная
	# в камеру, видна как обрубок: вся её длина уходит в глубину кадра. Отсюда и
	# «щупалец не видно» — они были, но смотрели точно на зрителя.
	# РАЗВОДИМ ВБОК, А НЕ ПО КРУГУ. Угол крутится в плоскости «вбок + вверх», и
	# при двух руках он даёт -82 и +82 градуса: то есть одна рука уходила почти
	# строго ВНИЗ. Замер по смотровой: её конец оказывался на 1.63 м НИЖЕ пола —
	# рука была закопана в землю и в кадре её не было вовсе. Вертикальную долю
	# придавливаем: развод остаётся, ныряния в пол нет.
	var off: Vector3 = (side * sin(ang) + upv * 0.30) * 2.1
	# Не до самого игрока: рука тянется и чуть не достаёт, пока он не в захвате.
	var far: float = minf(d.length() * 0.88, ARM_LEN * 0.92)
	var goal_w: Vector3 = global_position + (dir + off).normalized() * far \
		+ Vector3(0.0, 0.7, 0.0)
	# И НИЖЕ ПОЛА НЕ ТЯНЕМСЯ НИКОГДА: под ногами у него камень.
	goal_w.y = maxf(goal_w.y, global_position.y + 0.25)
	# И СКВОЗЬ СТЕНУ НЕ ТЯНЕМСЯ ТОЖЕ. Развод в 81 градус придуман для зала; в
	# проходе шириной 2.8 м он уводит руку прямо в породу — замер показал, что
	# половина её звеньев стояла в камне. Правило то же, что у опор.
	goal_w = _corridor_clamp(goal_w)
	var local: Vector3 = body.to_local(goal_w)
	# И ВЫГИБАЕМ ВБОК, а не вверх: тогда рука идёт к игроку дугой мимо туши, и
	# в кадре видно её целиком, а не кончик.
	var bow: Vector3 = (side * signf(cos(ang)) + Vector3.UP * 0.55).normalized()
	_pose_arm(arm, local, bow, -0.22)


## Поджата к телу: в коридоре развести все восемь просто некуда.
func _pose_tuck(arm: Dictionary) -> void:
	# НЕ ПРИЖАТЫ, А ШЕВЕЛЯТСЯ. Раньше эти руки лежали на самой мантии — с
	# полуметра они сливались с тушей, и осьминог читался шаром с парой
	# отростков. Теперь они держатся поодаль и гуляют вверх-вниз: силуэт
	# получается рваный, и щупальца видно даже спереди.
	var y: float = float(arm["yaw"])
	var r: Vector3 = Vector3(sin(y), 0.0, cos(y))
	var wob: float = sin(_shiv * 1.7 + float(arm["ph"])) * 0.26
	var lift: float = sin(_shiv * 1.15 + float(arm["ph"]) * 1.7) * 0.55
	# ВВЕРХ, ЧЕРЕЗ МАНТИЮ. Держать их сбоку на уровне туши бесполезно: спереди
	# мантия закрывает всё, и осьминог читается шаром. Эти руки поднимаются
	# ВЫШЕ головы и качаются там — силуэт получается рваный сверху, а щупальца
	# видно на фоне коридора, а не на фоне его же тела.
	var local: Vector3 = Vector3(0.0, HEIGHT * 1.02 + lift, 0.0) \
		+ r * (BLOB_R * 0.95 + wob)
	_pose_arm(arm, local, Vector3.UP, 0.75)


## ── ПОСТАНОВКА РУКИ В ТОЧКУ ───────────────────────────────────────────────
##
## Всё, что ниже, держится на одном решателе: рука — цепочка равных звеньев,
## и если каждый сустав повернуть на ОДИН И ТОТ ЖЕ угол, цепочка ложится на
## дугу окружности. Длина хорды такой дуги считается формулой, а значит по
## расстоянию до цели можно найти нужный угол — и рука дотянется ровно куда
## надо, без подбора углов на глаз.
##
## Это принципиально другой подход, чем был: раньше углы задавались числами, и
## любое движение приходилось подгонять заново. Теперь я задаю ТОЧКУ, а поза
## считается сама, — на этом и построены обе походки.


## Угол на сустав, при котором дуга из n звеньев длиной seg даёт хорду dist.
## Хорда монотонно убывает с ростом угла, поэтому берём делением пополам:
## аналитического решения у этого уравнения нет.
## Больше этого суммарного поворота рука не сворачивается: дальше начинается
## спираль, которая читается смешно, а не страшно. 1.35π — это дуга, загнутая
## чуть больше полукруга: ещё щупальце, уже не пружина.
const CURL_MAX := 4.24


func _arc_curl(dist: float, seg: float, n: int) -> float:
	var full: float = seg * float(n)
	if dist >= full * 0.995:
		return 0.0                      # дальше вытянутой руки не достать
	var lo: float = 0.0
	# ВЕРХНЯЯ ГРАНИЦА — ПОЛНЫЙ ОБОРОТ, а не половина. При PI/n самая короткая
	# достижимая хорда равна 1.39 из 2.17 длины руки: всё, что ближе, решатель
	# просто не мог свернуть, и рука не доставала до опоры на 0.4-0.6 м. Замерил
	# промах по кадрам — он рос ровно по мере приближения цели.
	# ...но НЕ БОЛЬШЕ ПОЛУТОРА ОБОРОТОВ НА ЗВЕНО В СУММЕ. Полный оборот решатель
	# честно использовал, когда цель совсем близко, — и рука сворачивалась в
	# спираль. В атаке, где монстр стоит вплотную, это происходило каждый раз.
	# Ближе предела руку не гнём, а УКОРАЧИВАЕМ — этим занимается _pose_arm.
	var hi: float = CURL_MAX / float(n)
	for _i in 16:
		var c: float = (lo + hi) * 0.5
		var chord: float = seg * sin(float(n) * c * 0.5) / sin(c * 0.5)
		if chord > dist:
			lo = c
		else:
			hi = c
	return (lo + hi) * 0.5


## Ставит руку так, чтобы её рабочий конец пришёл в target (в системе body).
## bow — куда рука выгибается: с ним она заносится над опорой, а не волочится
## по прямой. Последние два звена в расчёт не входят: это подворачивающийся
## кончик, он и должен уходить за точку опоры.
func _pose_arm(arm: Dictionary, target: Vector3, bow: Vector3, tip: float) -> void:
	var root: Node3D = arm["root"]
	var joints: Array = arm["joints"]
	var n: int = joints.size() - 2
	var seg: float = float(arm.get("len", ARM_LEN)) / float(joints.size())
	var d: Vector3 = target - root.position
	var dist: float = d.length()
	var dir: Vector3 = d / dist if dist > 0.001 else Vector3.DOWN
	# КОРОТКАЯ ЦЕЛЬ — КОРОТКАЯ РУКА. Самая короткая хорда, которую даёт дуга при
	# предельном загибе; всё, что ближе, раньше добиралось спиралью. Теперь на
	# столько же уменьшаем длину звеньев: рука подбирается к себе, как настоящая,
	# а не завивается кольцами.
	var cmax: float = CURL_MAX / float(n)
	var min_chord: float = seg * sin(float(n) * cmax * 0.5) / sin(cmax * 0.5)
	var shrink: float = 1.0
	if dist < min_chord and min_chord > 0.01:
		shrink = clampf(dist / min_chord, 0.35, 1.0)
		seg *= shrink
	var c: float = _arc_curl(dist, seg, n)
	# Ось изгиба — поперёк плоскости «направление + выгиб».
	var bn: Vector3 = dir.cross(bow)
	if bn.length() < 0.01:
		bn = dir.cross(Vector3.UP)
	if bn.length() < 0.01:
		bn = Vector3.RIGHT
	bn = bn.normalized()
	# Начальная касательная отклонена от хорды на половину суммарного поворота:
	# тогда дуга выходит симметричной и её конец попадает точно в цель.
	var half: float = c * float(n - 1) * 0.5
	var tangent: Vector3 = dir.rotated(bn, half)
	# Базис корня: локальный -Y вдоль касательной, локальный X — ось изгиба.
	# Через углы Эйлера это не выразить без переворотов, поэтому собираем руками.
	var yv: Vector3 = -tangent
	var xv: Vector3 = bn
	var zv: Vector3 = xv.cross(yv).normalized()
	var tr: Transform3D = root.transform
	# МАСШТАБ СОХРАНЯЕМ. Basis из трёх осей — чистый поворот, и он затирал
	# уменьшение корня: щупальца на груди фигуры так и оставались брёвнами
	# в человеческий рост, сколько я ни ставил root.scale.
	var sc: float = float(arm.get("scl", 1.0)) * shrink
	tr.basis = Basis(xv, yv, zv).scaled(Vector3(sc, sc, sc))
	root.transform = tr
	for k in joints.size():
		var a: float = 0.0
		if k > 0 and k <= n - 1:
			a = -c
		elif k > n - 1:
			a = tip
		var j: Node3D = joints[k]
		j.rotation = Vector3(a, 0.0, 0.0)


## Радиус мантии на заданной относительной высоте (-1 низ, 1 макушка).
func _mantle_radius(h: float) -> float:
	for k in MANTLE.size() - 1:
		var a: float = float(MANTLE[k][0])
		var b: float = float(MANTLE[k + 1][0])
		if h <= a and h >= b:
			var f: float = 0.0 if is_equal_approx(a, b) else (a - h) / (a - b)
			return lerpf(float(MANTLE[k][1]), float(MANTLE[k + 1][1]), f) * BLOB_R
	return BLOB_R * 0.1


## ЦЕПОЧКА ЗВЕНЬЕВ. Общий кирпич: из него сделаны и щупальца осьминога, и руки
## с ногами человеческой фигуры. Звено висит на предыдущем, поэтому поворот у
## основания уносит всю конечность, а повороты дальше накапливаются в изгиб.
func _chain(root: Node3D, segs: int, total: float, r0: float, mat: Material) -> Array:
	var seg: float = total / float(segs)
	var joints: Array = []
	var parent: Node3D = root
	for i in segs:
		var j := Node3D.new()
		# Первое звено сидит в корне, каждое следующее — на конце прошлого.
		j.position = Vector3.ZERO if i == 0 else Vector3(0.0, -seg, 0.0)
		parent.add_child(j)
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		# Показатель 0.85: конус прямее, соседние радиусы ближе, и стык между
		# звеньями меньше видно. На 0.75 руку было видно кольцами.
		cm.top_radius = maxf(r0 * pow(1.0 - float(i) / float(segs), 0.85), 0.012)
		cm.bottom_radius = maxf(r0 * pow(1.0 - float(i + 1) / float(segs), 0.85), 0.010)
		# Перекрытие 6%: при большом нахлёсте толстая часть следующего звена
		# вылезает сквозь тонкую предыдущего.
		cm.height = seg * 1.06
		cm.radial_segments = 14
		cm.rings = 2
		cm.cap_top = false
		cm.cap_bottom = false
		m.mesh = cm
		m.material_override = mat
		m.position = Vector3(0.0, -seg * 0.5, 0.0)
		j.add_child(m)
		joints.append(j)
		parent = j
	return joints


## ВОСЕМЬ РУК. Каждая — цепочка звеньев: звено i висит на звене i-1, поэтому
## поворот у основания уносит всю руку, а повороты дальше накапливаются в
## завиток. Так гнётся настоящее щупальце; одним цилиндром с волной в шейдере
## этого не получить — там изгиб живёт внутри меша и не двигает кончик.
func _build_arms() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tentacle.gdshader")
	mat.set_shader_parameter("tint", Color(0.035, 0.040, 0.037))
	mat.set_shader_parameter("rim_tint", Color(0.14, 0.38, 0.23))
	# Волны в шейдере НЕТ: она сдвигает вершины внутри каждого звена, и на стыках
	# соседних звеньев появляется ступенька. Гнём суставами.
	mat.set_shader_parameter("wave", 0.0)
	mat.set_shader_parameter("speed", 1.0)
	# Сужение внутри звена выключено: иначе каждое звено пережимается само в
	# себе и рука выглядит нанизанными бусинами.
	mat.set_shader_parameter("pinch", 0.0)
	arm_mat = mat
	# Руки РАЗНОЙ ДЛИНЫ. Восемь одинаковых читались бахромой из ног; у живого
	# осьминога они заметно разные, и именно этим связка перестаёт быть узором.
	# Разброс детерминированный: он часть облика, а не случайность кадра.
	var lens := [1.0, 0.88, 1.12, 0.94, 1.06, 0.90, 1.10, 0.97]
	# Руки растут из-под мантии, от венчика вокруг рта.
	var mouth := Vector3(0, HEIGHT * 0.60 - BLOB_R * MANTLE_H * 0.52, 0)
	for a in ARMS:
		var alen: float = ARM_LEN * float(lens[a % lens.size()])
		var seg: float = alen / float(ARM_SEGS)
		var yaw: float = TAU * float(a) / float(ARMS)
		var root := Node3D.new()
		root.position = mouth + Vector3(sin(yaw), 0.0, cos(yaw)) * BLOB_R * 0.30
		root.rotation = Vector3(0.0, yaw, 0.0)
		body.add_child(root)
		var joints: Array = _chain(root, ARM_SEGS, alen, alen * ARM_R / ARM_LEN, mat)
		arms.append({"root": root, "joints": joints, "yaw": yaw, "ph": _rng.randf() * TAU,
			"role": ROLE_FLOOR, "plant": Vector3.ZERO, "down": false, "side": 1.0,
			"push": false, "len": alen, "home": root.position})
	return


## ЩУПАЛЬЦЕ ДОСТАВАНИЯ. Отдельное от прочих: длинное, толстое, и оно
## единственное соединяет его с игроком.
##
## Без него вся механика оставалась невидимой: игрока тянуло к монстру, а
## причины на экране не было — со стороны это читалось как «он сам подошёл».
func _build_reach() -> void:
	reach = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055
	cm.bottom_radius = 0.15
	cm.height = 1.0
	cm.radial_segments = 8
	cm.rings = 14
	cm.cap_top = false
	reach.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = load("res://tentacle.gdshader")
	m.set_shader_parameter("tint", Color(0.045, 0.050, 0.047))
	# ЗЕЛЁНАЯ КРОМКА, как у остальных щупалец. Красная делала из него язык:
	# на кадре в упор это читалось «он тебя облизывает», а не «он тебя держит».
	m.set_shader_parameter("rim_tint", Color(0.20, 0.52, 0.32))
	m.set_shader_parameter("wave", 0.20)
	m.set_shader_parameter("speed", 5.0)
	reach.material_override = m
	reach_mat = m
	# Живёт в мире, а не на теле: один конец у него, другой у игрока, и
	# поворачиваться вместе с телом он не должен.
	reach.top_level = true
	reach.visible = false
	add_child(reach)


## Дотянуться до точки. Зовётся в момент броска и держится, пока тянут и давят.
func strike_at(target: Vector3, seconds: float) -> void:
	if reach == null:
		return
	reach_t = seconds
	reach.visible = true
	_aim_reach(target)


func _aim_reach(target: Vector3) -> void:
	if reach == null or not reach.visible:
		return
	# Из ПАСТИ, если сейчас фигура: язык из живота — это её приём, и вылетать
	# он должен оттуда, а не из середины несуществующего кома.
	var from: Vector3 = global_position + Vector3(0, HEIGHT * 0.45, 0)
	if form_kind == FORM_HUMAN and human != null and human.visible:
		from = body.global_transform * _mouth_local()
	var to: Vector3 = target
	var d: Vector3 = to - from
	var l: float = maxf(d.length(), 0.05)
	reach.global_position = from + d * 0.5
	var dir: Vector3 = d / l
	reach.rotation = Vector3(acos(clampf(dir.y, -1.0, 1.0)), atan2(dir.x, dir.z), 0.0)
	reach.scale = Vector3(1, l, 1)


## Ставим как можно дальше от игрока, ВНУТРИ камня.
func place_far_from(from_cell: Vector2i, skin: Array) -> void:
	var best: Vector2i = from_cell
	var bd := -1
	for c in skin:
		var d: int = absi(c.x - from_cell.x) + absi(c.y - from_cell.y)
		if d > bd:
			bd = d
			best = c
	global_position = _to_world(best)
	mode = "inwall"
	visible = false
	path.clear()


func tick(delta: float, player_pos: Vector3, anger: int, in_finale: bool) -> void:
	if mode == "gone":
		return
	if stun > 0.0:
		stun -= delta
		return
	# Пока игрок рисует, монстр НЕ движется: он замер там, где его застало полотно.
	# Иначе он подходил вплотную и хватал сразу на выходе — доделать рисунок
	# означало попасться, и полотно превращалось в ловушку.
	if finale_mode:
		_tick_finale(delta, player_pos)
		return
	if parked:
		return
	if mode == "surfacing":
		surface_t -= delta
		if surface_t <= 0.0:
			_pop_out()
		return
	if mode == "inwall":
		_tick_inwall(delta, player_pos)
	else:
		_tick_out(delta, player_pos, anger, in_finale)


## Скорость от ярости: линейно от базовой до потолка, и упирается ровно на ANGER_MAX.
func _speed(base_k: float, anger: int) -> float:
	var k: float = clampf(float(anger) / float(ANGER_MAX), 0.0, 1.0)
	return player_speed * (base_k + (K_MAX - base_k) * k)


# ─────────────────────────── фазы 1–2: он в камне ───────────────────────────

func _tick_inwall(delta: float, player_pos: Vector3) -> void:
	# Страховка: третья фаза — центральное событие игры, и она не должна
	# зависеть от того, повезло ли ему найти дорогу.
	# Уже показывался — значит просто пережидает в камне до следующего раза.
	if not first_out:
		resurface_t -= delta
		if resurface_t <= 0.0:
			# Вплотную или поодаль — поровну. Первое не даёт привыкнуть,
			# второе даёт увидеть, как он идёт, и это разные страхи.
			_begin_surface(player_pos, _rng.randf() < 0.5)
		return
	inwall_time += delta
	if inwall_time > INWALL_CAP:
		allow_emerge = true          # страховка по времени: выйти он обязан
		_emerge(player_pos)
		return
	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = 0.6
		var me := _to_cell(global_position)
		var target: Vector2i
		var skin: Array = maze.wall_skin()
		if _rng.randf() < INWALL_WANDER_F and not skin.is_empty():
			# иногда просто бродит по камню: подход не должен быть прямой линией
			target = skin[_rng.randi() % skin.size()]
		else:
			# Цель выбираем ТОЛЬКО по близости к игроку. Если подмешать стоимость
			# пути, побеждает собственная клетка монстра — она стоит ноль,
			# и он стоит на месте.
			var pc := _to_cell(player_pos)
			var bd := 1 << 30
			target = me
			for c in skin:
				var d: int = absi(c.x - pc.x) + absi(c.y - pc.y)
				if d < bd:
					bd = d
					target = c
		path = maze.path_weighted(me, target, 1, 9)
	var far: float = _flat_dist(player_pos) / (cell_size * 18.0)
	var sp: float = INWALL_CELLS * lerpf(1.0, INWALL_FAR, clampf(far, 0.0, 1.0))
	_follow(sp * cell_size * delta)
	# вылез?
	scare_cool = maxf(0.0, scare_cool - delta)
	if _flat_dist(player_pos) < PH3_MEET_CELLS * cell_size:
		if allow_emerge:
			_emerge(player_pos)
		elif scare_cool <= 0.0:
			# ДО ТРЕТЬЕЙ ФАЗЫ ОН НЕ ВЫХОДИТ. Подошёл вплотную к его стене —
			# получаешь глаза из камня, и он уползает в другую стену.
			# Так первая фаза остаётся тем, чем задумана: его нет как тела,
			# он только слышен, и подойти к нему нельзя — можно лишь спугнуть.
			scare_cool = 25.0
			wall_scare.emit()
			var skin: Array = maze.wall_skin()
			var best := _to_cell(global_position)
			var bd := -1
			var pc := _to_cell(player_pos)
			for c in skin:
				var d: int = absi(c.x - pc.x) + absi(c.y - pc.y)
				if d > bd:
					bd = d
					best = c
			global_position = _to_world(best)
			path.clear()
			_path_t = 0.0


## Треск сейчас, тело через полторы секунды. Первый раз вылезает ЦЕЛЕНАПРАВЛЕННО
## рядом с игроком: знакомство должно быть в упор. Дальше — как повезёт.
func _begin_surface(player_pos: Vector3, close: bool) -> void:
	mode = "surfacing"
	visible = false
	surface_t = SURFACE_DELAY
	var pc := _to_cell(player_pos)
	var want: float = SURFACE_NEAR if close else _rng.randf_range(SURFACE_FAR[0], SURFACE_FAR[1])
	var dist: Dictionary = maze.distances(pc)
	var best := pc
	var bd := 1 << 30
	for c in dist:
		var d: int = absi(int(dist[c]) - int(want))
		if d < bd:
			bd = d
			best = c
	surface_pos = _to_world(best)
	surfacing.emit()


## Снаружи он БОЛЬШЕ, чем в камне. Пока он в стене, размер не важен — его не
## видно; а выйдя, он должен не помещаться в коридор.
func _grow_out() -> void:
	if body != null:
		body.scale = Vector3(1.32, 1.32, 1.32)


func _emerge(player_pos: Vector3) -> void:
	_grow_out()
	_begin_surface(player_pos, first_out)


func _pop_out() -> void:
	global_position = surface_pos
	mode = "chase"
	visible = true
	chase_t = _rng.randf_range(CHASE_LEN[0], CHASE_LEN[1])
	pause_t = 0.0
	path.clear()
	_path_t = 0.0
	trail.clear()
	if first_out:
		first_out = false
		emerged.emit()


# ─────────────────────────── фаза 3: он снаружи ───────────────────────────

## Осколки всё время шевелятся — форма не держится. Это и есть его силуэт.
func _shiver(delta: float, seen: bool) -> void:
	_shiv += delta
	# Щупальце доставания живёт своим сроком и всё это время держится за игрока.
	if reach_t > 0.0:
		reach_t -= delta
		if reach_t <= 0.0:
			reach.visible = false
	# Собирается быстро, рассыпается медленно: фигура должна успеть броситься в
	# глаза, а расползание — тянуться, чтобы осталось сомнение, видел ли.
	if form_hold > 0.0:
		form_hold -= delta
		form_t = minf(1.0, form_t + delta * 3.2)
	else:
		form_t = maxf(0.0, form_t - delta * 0.9)
	var e: float = form_t * form_t * (3.0 - 2.0 * form_t)
	# Пасть раскрывается вместе с фигурой и закрывается вместе с ней.
	mouth_open = e if form_kind != FORM_NONE else 0.0
	if form_t <= 0.001:
		form_kind = FORM_NONE
	shell_mat.set_shader_parameter("mouth",
		Vector4(mouth_dir.x, mouth_dir.y, mouth_dir.z, mouth_size))
	shell_mat.set_shader_parameter("mouth_open", mouth_open)
	# ПЕРЕТЕКАНИЕ. Ком не превращается в человека — он ОСЕДАЕТ, а из лужи
	# поднимается вторая фигура. Пока идёт переход, оба тела ужаты по высоте:
	# в середине на полу остаётся только растёкшаяся масса, и именно этот
	# провал делает превращение переходом, а не подменой.
	var hk: float = e if form_kind == FORM_HUMAN else 0.0
	if human != null:
		human.visible = hk > 0.01
		# Ком опадает первым, фигура встаёт следом: сдвиг по времени.
		var fall: float = clampf(hk * 1.7, 0.0, 1.0)
		var rise: float = clampf(hk * 1.7 - 0.7, 0.0, 1.0)
		# ЛУЖА, А НЕ БЛИН. Разлёт 0.55 давал диск шире, чем был сам ком: масса
		# не может занять больше места, чем её есть. И толщину оставляем
		# заметной — то, что растеклось, всё равно лежит горкой.
		blob.scale.y = 1.0 - 0.80 * fall
		blob.scale.x = 1.0 + 0.28 * fall
		blob.scale.z = 1.0 + 0.28 * fall
		# ЛУЖА ЛОЖИТСЯ НА ПОЛ. Ком сплющивался, но оставался висеть на высоте
		# своего центра — в полутора метрах над полом, здоровенным блином
		# в воздухе. Опускаем вместе со сплющиванием.
		blob.position.y = lerpf(HEIGHT * 0.60, 0.20, fall)
		# Когда фигура встала, комa уже нет: масса вся в ней. Оставлять его
		# лужей под ногами — значит показывать, что её вдвое больше, чем было.
		blob.visible = rise < 0.92
		# ЯДРО УХОДИТ ВМЕСТЕ С КОМОМ. Оно принадлежит ему, а не фигуре: когда
		# ком спрятался, шарик остался висеть у фигуры между ног — и к нему же
		# тянуло камеру, потому что рядом сидела и точка пасти.
		if core_mesh != null:
			core_mesh.visible = rise < 0.92
		# Щупальца осьминога уходят вместе с комом: они и есть тот же материал.
		# КРОМЕ ТЕХ, ЧТО ЛЕЗУТ ИЗО РТА. Я спрятал все восемь разом — и вместе
		# с комом исчезли те пять, ради которых форма и затевалась.
		for ai8 in arms.size():
			var keep_arm: bool = ai8 < ARM_MOUTH
			# Щупальца ИЗО РТА появляются только когда рот уже есть. Пока
			# фигура лежит в луже, они били фонтаном из пола: корень у них
			# на груди, а грудь в этот момент на земле.
			# ФОРМЫ НЕТ — ВИДНЫ ВСЕ ВОСЕМЬ. Эта развилка стоит внутри
			# «if human != null», а модель гуманоида загружена ВСЕГДА, значит
			# блок работает и в обычном виде осьминога. Без формы rise = 0, и
			# условие «видна, если rise > 0.60» гасило первые пять рук
			# НАСОВСЕМ: осьминог всё это время ходил на трёх щупальцах из
			# восьми, причём на трёх соседних — 225, 270 и 315 градусов. Отсюда
			# и «с одной стороны три ноги, с другой пусто».
			if hk <= 0.001:
				(arms[ai8]["root"] as Node3D).visible = true
			else:
				(arms[ai8]["root"] as Node3D).visible = \
					(rise > 0.60) if keep_arm else (rise < 0.55)
			# ЩУПАЛЬЦА ТОНУТ ВМЕСТЕ С МАССОЙ. Они оставались торчать из лужи
			# в полный рост, как ноги у опрокинутого паука: тело уже стекло,
			# а руки те же. Убираем их вместе с оседанием.
			if not keep_arm:
				arms[ai8]["scl"] = maxf(0.05, 1.0 - 0.92 * fall)
		for td2 in tendrils:
			(td2["n"] as MeshInstance3D).visible = rise < 0.55
		human.scale = Vector3(0.86 + 0.14 * rise, rise, 0.86 + 0.14 * rise)
		human_mat.set_shader_parameter("lit", shell_mat.get_shader_parameter("lit"))
		# Пока фигура поднимается — она ещё «сырая», кромка светится сильнее.
		human_mat.set_shader_parameter("wet", 1.0 + (1.0 - rise) * 1.4)
	elif blob != null:
		# Формы нет — ком на месте, целиком.
		if core_mesh != null:
			core_mesh.visible = true
		blob.visible = true
		blob.scale = Vector3.ONE
		blob.position.y = HEIGHT * 0.60
	_sway_human(delta, hk)
	if shell_mat == null:
		return
	shell_mat.set_shader_parameter("form", e)
	# Кипит всегда. Когда он тебя видит — сильнее: масса подбирается.
	# Сильнее, чем было (0.26): при слабом кипении шар остаётся шаром, а нам
	# нужен ком, у которого силуэт всё время другой.
	shell_mat.set_shader_parameter("wobble", (0.30 + (0.12 if seen else 0.0)) * (1.0 + e * 0.5))
	# Пила, а не синус: растекается медленно, подбирается рывком. Синус дал бы
	# ровное дыхание, а нам нужно, чтобы масса ТЕРЯЛА форму и спохватывалась.
	# fmod, а не fract: fract есть в шейдерах, в GDScript его нет.
	var ph: float = fmod(_shiv * 0.16, 1.0)
	var sp: float = ph / 0.78 if ph < 0.78 else (1.0 - (ph - 0.78) / 0.22)
	# В фигуре не растекается: она держится через силу, на это и уходят силы.
	shell_mat.set_shader_parameter("spread", sp * (1.0 - e) * 0.45)
	# Щупальца живут отдельно от кома: мелкие шарят по сторонам, опорные
	# переступают в такт ходьбе. Фаза у каждого своя, иначе они машут строем.
	# Нити живут сами по себе: мелко шарят по сторонам. Фаза у каждой своя,
	# иначе они машут строем.
	for td in tendrils:
		var n: MeshInstance3D = td["n"]
		var p2: float = float(td["ph"])
		var base: Vector3 = Vector3(td["rot"])
		n.rotation = base + Vector3(sin(_shiv * 2.6 + p2 * 1.3) * 0.35, 0.0,
			sin(_shiv * 3.4 + p2) * 0.55)
	_walk_arms(delta)
	if ceil_at != Vector3.ZERO:
		_pose_ceiling(delta, aim_at if aim_at != Vector3.ZERO else ceil_at)
	for i in ATTR:
		# В покое притягиватели медленно бродят у центра со слабой силой: ком
		# перекатывается сам в себе, но конечностей не отращивает.
		var a: float = TAU * float(i) / float(ATTR)
		var idle := Vector4(
			cos(a + _shiv * 0.31) * BLOB_R * 0.85,
			sin(_shiv * 0.44 + float(i)) * BLOB_R * 0.8,
			sin(a + _shiv * 0.27) * BLOB_R * 0.85,
			0.26 + 0.14 * sin(_shiv * 0.7 + float(i) * 1.3))
		var target := idle
		if i < form_pose.size():
			var pose: Dictionary = form_pose[i]
			var p: Vector3 = Vector3(pose["pos"])
			# Искажение: фигура должна быть узнаваемой и при этом НЕПРАВИЛЬНОЙ.
			p += Vector3(sin(_shiv * 3.7 + float(i)), sin(_shiv * 2.9 + float(i) * 2.1),
				cos(_shiv * 3.3 + float(i))) * form_warp
			target = Vector4(p.x, p.y, p.z, float(pose["w"]))
		var cur: Vector4 = idle.lerp(target, e)
		shell_mat.set_shader_parameter("attr%d" % i, cur)
	# Глаза — самое яркое, что есть, и загораются, только когда он тебя ВИДИТ.
	# Пока не видит, силуэт остаётся безглазым куском камня.
	# 1.6, А НЕ 4.5. Вот где на самом деле задаётся яркость глаз: эта строка
	# каждый кадр перезаписывает то, что выставлено при создании, — и все мои
	# правки констант в _eye не значили ничего. На 4.5 все три канала уходили
	# за единицу, и красный глаз выгорал в белый диск; на 0.35 его не было
	# видно вовсе. 1.6 — красный клипует, зелёный остаётся 0.48: оранжево-красный.
	# Глаза — самое яркое, что есть, и разгораются, только когда он тебя ВИДИТ.
	# 1.6, а не 4.5: на 4.5 все три канала уходят за единицу, и красный глаз
	# выгорает в белый диск.
	var want: float = 1.6 if seen else 0.25
	eye_glow = lerpf(eye_glow, want, minf(1.0, delta * 6.0))
	shell_mat.set_shader_parameter("eye_glow", eye_glow)
	for i in eye_dirs.size():
		# Открываются и закрываются вразнобой: считать их не выходит, и каждый
		# раз кажется, что глаз стало больше.
		var o: float = 0.5 + 0.5 * sin(_shiv * (0.7 + 0.31 * float(i)) + float(i) * 2.1)
		o = smoothstep(0.35, 0.75, o)
		# Передняя пара смотрит почти всегда: по ней он и опознаётся.
		if i < 2:
			o = maxf(o, 0.75)
		eye_open[i] = o
		var d: Vector3 = eye_dirs[i]
		shell_mat.set_shader_parameter("eye%d" % i, Vector4(d.x, d.y, d.z, o))


func _update_trail(delta: float) -> void:
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	_trail_t = 0.05
	trail.push_front(global_position)
	if trail.size() > 60:
		trail.resize(60)
	pass   # хвост убран: он читался как гусеница из шаров


func _tick_out(delta: float, player_pos: Vector3, anger: int, in_finale: bool) -> void:
	_update_trail(delta)
	_shiver(delta, _see_t > 0.0)
	var me := _to_cell(global_position)
	var pc := _to_cell(player_pos)
	# В убежище он тебя не видит и не достаёт. Границу держит круг мелом на полу.
	var hidden: bool = safe_cells.has(pc)
	var sees: bool = maze.los(me, pc) and not hidden
	# Погоня всегда КОНЕЧНА. Выдохлась — отступает и выжидает.
	if mode == "chase":
		chase_t -= delta
		if chase_t <= 0.0:
			# В КАМЕНЬ ОН УХОДИТ ТОЛЬКО ПОСЛЕ ТОГО, КАК ТЫ ВЫРВАЛСЯ ИЗ ХВАТА.
			# Раньше погоня просто кончалась по таймеру, и он растворялся прямо
			# на глазах: достаточно было пятиться, глядя на него, и через
			# пять-девять секунд он пропадал. Выдохшаяся погоня теперь переводит
			# его в обход — он остаётся здесь, отстаёт и ищет заново.
			mode = "roam"
			path.clear()
			roam_cell = Vector2i(-1, -1)
			pause_t = _rng.randf_range(CHASE_PAUSE[0], CHASE_PAUSE[1])
	else:
		pause_t = maxf(0.0, pause_t - delta)

	if sees:
		_see_t = 2.5                      # заметил — держит направление ещё пару секунд
		if mode == "roam":
			mode = "hunt"
			noticed.emit()
		# В погоню срывается, только когда отдышался: иначе травля превращается
		# в один непрерывный спринт.
		if mode == "hunt" and pause_t <= 0.0:
			mode = "chase"
			chase_t = _rng.randf_range(CHASE_LEN[0], CHASE_LEN[1])
	else:
		_see_t = maxf(0.0, _see_t - delta)
		if mode == "hunt" and _see_t <= 0.0:
			mode = "roam"

	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = REPATH
		# Сквозь стены он ходит НЕ всегда. Мера «далеко» — длина ОБХОДА ПО КОРИДОРАМ,
		# а не прямая: в лабиринте прямая почти всегда мала, и порог по ней не срабатывал.
		var cut: bool = maze.is_wall(me.x, me.y)   # уже в камне — выбираться всё равно сквозь
		if not cut and in_finale:
			var corridor_path: Array = maze.path_weighted(me, pc, 1 << 20, 1)
			cut = corridor_path.is_empty() or corridor_path.size() > CUT_FAR_CELLS
		cutting = cut
		var goal: Vector2i = pc
		if mode == "roam":
			# Бродит, а не крадётся к тебе. Иначе «отступил» на деле означает
			# «идёт тем же курсом, только медленнее».
			if roam_cell.x < 0 or me == roam_cell:
				var fl: Array = maze.dead_ends()
				if fl.is_empty():
					fl = [pc]
				roam_cell = fl[_rng.randi() % fl.size()]
			goal = roam_cell
		path = maze.path_weighted(me, goal, 7 if cut else (1 << 20), 1)

	# В ПОСЛЕДНЕЙ ФАЗЕ погоня быстрее игрока в полтора раза. Убежать можно только
	# рывком (он даёт 1.9) — то есть бегство перестаёт быть бесплатным.
	# Оторвался достаточно далеко — он теряет тебя и уходит в камень.
	if _flat_dist(player_pos) > LOSE_CELLS * cell_size:
		retreat_to_wall(RESURFACE[0], RESURFACE[1])
		gave_up.emit()
		return

	var chase_k: float = K_MAX if last_phase else K_CHASE
	var k: float = chase_k if mode == "chase" else (K_HUNT if mode == "hunt" else K_HUNT * 0.8)
	var step: float = _speed(k, anger) * delta
	# ДЕРЖИТ ДИСТАНЦИЮ. Ближе STANDOFF он не идёт совсем: у твари, которая
	# дотягивается щупальцем с трёх метров, нет причин подходить вплотную, а
	# раньше она честно доходила и утыкалась носом — щупальца становились
	# украшением.
	if _flat_dist(player_pos) <= STANDOFF:
		step = 0.0
	_follow(step)
	# Шаг крутится от пройденного пути: опорные щупальца отталкиваются в такт
	# движению, а не сами по себе.
	gait = fmod(gait + step * 0.55, 1.0)
	# Тянемся к игроку, когда он в пределах досягаемости с запасом.
	# Куда смотрит игрок, знаем ВСЕГДА: тянущиеся руки в коридоре целят в него
	# и издалека. grasp_at — это уже про близко, про попытку схватить.
	aim_at = player_pos + Vector3(0, 0.9, 0)
	# ЧЕМ БЛИЖЕ — ТЕМ ВИДНЕЕ. Квадрат, а не прямая: далеко он должен оставаться
	# пятном, а последние метры — проявляться резко.
	var kl: float = clampf(1.0 - _flat_dist(player_pos) / LIT_FROM, 0.0, 1.0)
	set_lit(kl * kl)
	grasp_at = aim_at if _flat_dist(player_pos) < CATCH_DIST * 2.0 else Vector3.ZERO
	# Путь ведёт по КЛЕТКАМ и кончается в центре той, где стоит игрок, — то есть
	# в полутора метрах от него. Последний шаг надо делать прямо на игрока,
	# иначе монстр честно доходит и останавливается рядом.
	if path.is_empty() and step > 0.0:
		var to := player_pos - global_position
		to.y = 0.0
		var l := to.length()
		# Останавливаемся на STANDOFF, а не на игроке.
		if l > STANDOFF:
			global_position += to / l * minf(step, l - STANDOFF)

	if not hidden and _flat_dist(player_pos) < CATCH_DIST:
		caught.emit()

	# смотрим на игрока
	var to_p := player_pos - global_position
	to_p.y = 0.0
	if to_p.length_squared() > 0.01:
		look_at(global_position - to_p, Vector3.UP)


# ─────────────────────────── движение по пути ───────────────────────────

func _follow(step: float) -> void:
	while step > 0.0 and not path.is_empty():
		# В клетку убежища не шагаем — упираемся у порога и ждём там.
		if safe_cells.has(path[0]):
			path.clear()
			return
		var target: Vector3 = _to_world(path[0])
		var d: Vector3 = target - global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.05:
			path.remove_at(0)
			continue
		var m: float = minf(step, l)
		global_position += d / l * m
		step -= m


func _to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.y + 0.5) * cell_size, 0.0, (cell.x + 0.5) * cell_size)


func _to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.z / cell_size), int(pos.x / cell_size))


## Отойти и замереть, пока игрок рисует. Не телепорт через полкарты: отступает
## на несколько клеток по коридору, чтобы это читалось как «отошёл и ждёт».
func park(player_cell: Vector2i, back_cells: int) -> void:
	# Пока он в камне, замирать незачем: схватить он всё равно не может,
	# а заморозка на каждом полотне съедала минуты его подхода.
	if mode == "inwall":
		return
	parked = true
	path.clear()
	_path_t = 0.0
	var me := _to_cell(global_position)
	if maze.is_wall(me.x, me.y):
		return                      # он в камне — там и остаётся
	# Из клеток в паре шагов от себя выбираем ту, что ДАЛЬШЕ всего от игрока.
	var near: Dictionary = maze.distances(me)
	var from_player: Dictionary = maze.distances(player_cell)
	var best := me
	var bd := -1
	for c in near:
		if int(near[c]) > back_cells:
			continue
		var d: int = int(from_player.get(c, -1))
		if d > bd:
			bd = d
			best = c
	global_position = _to_world(best)


func unpark() -> void:
	parked = false
	_path_t = 0.0


## Финал: он выходит на FINAL_DIST клеток и идёт по КОРИДОРАМ, не срезая.
## Срезать тут нельзя — иначе обещанный игроку запас времени превращается
## во вдвое меньший, и дверь срывается не по его вине.
func to_finale(player_cell: Vector2i, cells_away: int, speed_cells: float) -> void:
	finale_mode = true
	parked = false
	visible = true
	mode = "chase"
	stun = 0.0
	_fin_speed = speed_cells
	_fin_start = maxi(1, cells_away)
	finale_near = 0.0
	var dist: Dictionary = maze.distances(player_cell)
	var best := player_cell
	var bd := 1 << 30
	for c in dist:
		var d: int = absi(int(dist[c]) - cells_away)
		if d < bd:
			bd = d
			best = c
	global_position = _to_world(best)
	path.clear()
	_path_t = 0.0


func _tick_finale(delta: float, player_pos: Vector3) -> void:
	var me := _to_cell(global_position)
	var pc := _to_cell(player_pos)
	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = 0.4
		var b: Array = maze.path_weighted(me, pc, 1 << 20, 1)
		if b.is_empty():
			b = maze.path_weighted(me, pc, 7, 1)   # коридором не дойти — только тогда сквозь камень
		path = b
	_follow(_fin_speed * cell_size * delta)
	var left: Array = maze.path_weighted(_to_cell(global_position), pc, 1 << 20, 1)
	finale_near = clampf(1.0 - float(left.size()) / float(_fin_start), 0.0, 1.0)
	var to_p := player_pos - global_position
	to_p.y = 0.0
	if to_p.length_squared() > 0.01:
		look_at(global_position - to_p, Vector3.UP)


## По горизонтали: высота камеры игрока не должна мешать расчётам расстояния.
func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## ── ФИГУРЫ ──────────────────────────────────────────────────────────────
##
## Не раскладка частей, а ВОСЕМЬ ТОЧЕК, к которым тянется одна поверхность.
## Координаты — относительно центра кома, то есть уровня груди. Сила w говорит,
## насколько сильно поверхность туда вытянется.
##
## Точку ставим ДАЛЬШЕ, чем нужен кончик: масса не дотягивается до неё целиком,
## а наплывает в её сторону — так и получается конечность, а не шишка.
## ИСКАЖЁННЫЙ ГУМАНОИД. Не человек: пропорции нарочно неверные — голова
## вытянута вверх и вперёд, плечи разной высоты, одна рука длиннее другой,
## таз узкий до нелепого. Узнаётся как человек ровно настолько, чтобы стало
## понятно, что это НЕ он.
func _pose_human() -> Array:
	return [
		{"pos": Vector3(0.03, 0.86, 0.16), "w": 0.46},   # голова: выше и вперёд
		{"pos": Vector3(-0.70, 0.22, 0.10), "w": 0.40},  # плечо выше
		{"pos": Vector3(0.62, -0.04, -0.08), "w": 0.36}, # и ниже
		{"pos": Vector3(-0.26, -0.92, 0.06), "w": 0.36}, # ноги
		{"pos": Vector3(0.20, -0.96, -0.06), "w": 0.36},
		{"pos": Vector3(0.0, 0.26, 0.0), "w": 0.24},     # грудь
		{"pos": Vector3(0.02, -0.40, 0.0), "w": 0.13},   # таз узкий
		{"pos": Vector3(0.0, 0.56, -0.06), "w": 0.10},   # шея тонкая
	]


## Зверь: низкий, длинный, голова опущена и вынесена вперёд.
func _pose_beast() -> Array:
	return [
		{"pos": Vector3(0.0, -0.10, 0.95), "w": 0.42},   # голова
		{"pos": Vector3(0.0, 0.06, 0.42), "w": 0.24},    # шея
		{"pos": Vector3(0.0, 0.10, -0.30), "w": 0.24},   # хребет
		{"pos": Vector3(-0.34, -0.78, 0.44), "w": 0.34}, # четыре ноги
		{"pos": Vector3(0.34, -0.78, 0.40), "w": 0.34},
		{"pos": Vector3(-0.36, -0.80, -0.44), "w": 0.34},
		{"pos": Vector3(0.36, -0.80, -0.40), "w": 0.34},
		{"pos": Vector3(0.0, 0.02, -0.86), "w": 0.26},   # хвост
	]


## И что-то третье: лучи из одной точки. Ни человек, ни зверь — форма, которой
## не с чем свериться, и потому худшая из трёх.
func _pose_other() -> Array:
	var o: Array = []
	for i in ATTR:
		var a: float = TAU * float(i) / float(ATTR) + 0.4
		var up: float = -0.7 + float(i % 3) * 0.7
		o.append({"pos": Vector3(cos(a) * 0.78, up, sin(a) * 0.78), "w": 0.30})
	return o


## Принять форму. Зовётся в момент атаки: он бросается — и на секунду становится
## чем-то, что ты почти узнал.
func take_form(seconds: float = 1.1, kind: int = -1) -> void:
	var which: int = kind if kind > 0 else 1 + _rng.randi() % 3
	form_kind = which
	if which == FORM_HUMAN:
		form_pose = _pose_human()
		# Пасть на морде, чуть вперёд: щупальца полезут отсюда.
		# ВПЕРЁД, а не вверх: при (0, 0.62, 0.52) пасть оказывалась на темени,
		# и щупальца лезли из макушки.
		# У ФИГУРЫ пасть на груди: голова маленькая, и рот на ней потерялся бы,
		# а грудная пасть — это ровно то, чего у человека быть не может.
		mouth_dir = Vector3(0.0, 0.10, 0.99).normalized()
	elif which == FORM_BEAST:
		form_pose = _pose_beast()
		mouth_dir = Vector3(0.0, 0.05, 0.98).normalized()
	else:
		form_pose = _pose_other()
		mouth_dir = Vector3(0.0, 1.0, 0.0)
	# МАСШТАБ ПОД НЫНЕШНЕЕ ТЕЛО. Раскладки писались, когда телом был шар
	# радиусом 0.78; мантия теперь 1.44 в полувысоту, и точки притяжения
	# оказались ВНУТРИ неё — фигура не проступала вовсе, оставалось яйцо.
	for i in form_pose.size():
		var d: Dictionary = form_pose[i]
		d["pos"] = Vector3(d["pos"]) * 1.55
		d["w"] = float(d["w"]) * 2.4
	form_warp = 0.05 + _rng.randf() * 0.05
	form_hold = seconds


## Показать монстра СКВОЗЬ стены. Только для режима создателя: в игре видеть его
## через камень нельзя, на этом держится вся первая фаза.
func set_xray(on: bool) -> void:
	# У тела теперь шейдерный материал, а свойства no_depth_test у него нет:
	# отключение глубины в шейдере задаётся при компиляции. Для просвечивания
	# хватает порядка сортировки, а падать режим создателя не должен.
	if blob != null:
		blob.sorting_offset = 100.0 if on else 0.0
	if not visible and on:
		visible = true          # в камне его иначе просто нет на экране


## Уйти в камень немедленно — после того, как игрок вырвался, или когда оторвался.
## Стоящий столбом монстр выглядит как зависший, и весь страх от него пропадает.
## Насколько он сейчас проявлен. Разослать надо во ВСЕ его материалы: тело,
## руки и нити — разные шейдеры, и забытый останется чёрным пятном на светлом.
func set_lit(v: float) -> void:
	if shell_mat != null:
		shell_mat.set_shader_parameter("lit", v)
	if tend_mat != null:
		tend_mat.set_shader_parameter("lit", v)
	if arm_mat != null:
		arm_mat.set_shader_parameter("lit", v)
	if reach_mat != null:
		reach_mat.set_shader_parameter("lit", v)


## Пометить всё его тело своим слоем видимости — рекурсивно, потому что руки
## это цепочки узлов, и меши висят на разной глубине.
func _mark_layer(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1 | (1 << (MON_LAYER - 1))
	for c in n.get_children():
		_mark_layer(c)


func retreat_to_wall(delay_min: float, delay_max: float) -> void:
	# Сигнал теперь ЗДЕСЬ, а не на конце погони: «он ушёл» — это про уход в
	# камень, и уход в камень бывает только отсюда.
	if visible:
		gave_up.emit()
	mode = "inwall"
	visible = false
	path.clear()
	roam_cell = Vector2i(-1, -1)
	chase_t = 0.0
	stun = 0.0
	resurface_t = _rng.randf_range(delay_min, delay_max)
