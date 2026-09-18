extends Node3D
## ХВАТ В ТРЁХ ИЗМЕРЕНИЯХ.
##
## До этого хват был плоской спиралью поверх мира: нарисованные кольца, по
## которым водили нарисованным ножом. Игра трёхмерная, и играющий сказал прямо —
## «щупальца, нож, рука были 3D, их было видно, и выглядело сочно, а сейчас это
## просто 2D спираль». Он прав, и старый комментарий в Grab.gd говорил ровно то
## же самое с другой стороны: плоская спираль поверх настоящих рук монстра
## читалась плохо.
##
## Здесь всё настоящее: щупальца — те же цепочки звеньев на том же шейдере, что
## и руки твари; нож — предмет в руке; попадание считается в пространстве, по
## отрезку, который прошло остриё. Разрезанное щупальце укорачивается, обрубок
## отлетает, из культи льёт.
##
## ОДНА УСЛОВНОСТЬ ОСТАЁТСЯ, И ОНА НАРОЧНАЯ: все щупальца лежат в оболочке на
## одном расстоянии от лица. Иначе в виде от первого лица игрок не чувствует
## глубину и машет мимо — целиться становится лотереей. Так целятся фактически
## плоско, а выглядит объёмно.

## ОДИННАДЦАТЬ ЗВЕНЬЕВ, А НЕ СЕМЬ. На семи виток шёл углами: на крутых
## поворотах соседние звенья расходились, и по телу были видны ступеньки.
const SEGS := 11                 ## звеньев в щупальце
const SHELL := 1.15              ## на каком расстоянии от лица лежит оболочка
const ARM_LEN := 1.9             ## длина щупальца
## ТОЛЩЕ. Щупальце в семь сантиметров с метра читается верёвкой; резать надо
## то, у чего есть тело.
const ARM_R := 0.105             ## толщина у основания
## НАСКОЛЬКО БЛИЗКО КОНЧИК ПОДХОДИТ К ЛИЦУ. Было 0.42, и виток проходил в
## сантиметрах от объектива: в кадре стояли бледные плиты во весь экран, а не
## щупальца. Шестьдесят сантиметров — это ещё «в упор», но уже видно, ЧТО это.
const TIP_NEAR := 0.62
const HIT_R := 0.16              ## на таком расстоянии лезвие достаёт до тела
## СКОЛЬКО ВЗМАХОВ ДЕРЖИТ ОДНО ЩУПАЛЬЦЕ. Было два, и играющий сказал прямо:
## «пара взмахов ножом и готово, не страшно и не опасно, я бы резал их хоть
## час». Значит работы должно быть БОЛЬШЕ, а не сложнее попадать: три взмаха —
## надруб, разруб, обрубание.
const ARM_HP := 3
## И НАДРУБ ЗАРАСТАЕТ. Само число взмахов опасности не даёт: можно возить ножом
## вразвалку и всё равно успеть. Щупальце, которое не добили за REGROW секунд,
## затягивает рану обратно — значит начатое надо КОНЧАТЬ, и пауза стоит дорого.
const REGROW := 2.6
const SWING_MIN := 0.55          ## метров в секунду: медленнее — не взмах

signal healed                    ## надруб зарос: щупальце снова целое
signal touched(arm: int, killed: bool)   ## задел щупальце: срезал или надрубил
signal hurt_at(pos: Vector3, killed: bool)  ## где именно: туда полетят брызги

var arms: Array = []             ## живые щупальца
var pieces: Array = []           ## отрубленные куски, они падают сами
var rig: Node3D                  ## всё висит на голове игрока
var knife: Node3D
var knife_tip: Node3D
## ПРЕВРАЩЕНИЕ ПАЛОЧКИ В ЛЕЗВИЕ.
##
## Раньше нож просто ПОЯВЛЯЛСЯ готовым: рука была с палочкой, кадр спустя — с
## ножом. Самое интересное в этой механике — то, что оружие у игрока одно и то
## же, и в бою оно меняет облик; а этого никто не видел, потому что перехода
## не было вовсе. Теперь из древка прорастает сталь: полсекунды, за которые
## бусина разгорается, лезвие вытягивается из рукояти и нож доворачивается
## плашмя к лицу.
var knife_blade: MeshInstance3D   ## сама сталь: она и растёт
var knife_bead: MeshInstance3D    ## бусина с палочки: она разгорается
var blade_t: float = 0.0          ## 0..1 — насколько лезвие выросло
const BLADE_GROW := 0.46          ## за столько секунд оно вырастает
var _blade_y: float = 0.0         ## куда лезвие встаёт, когда выросло
var _bead_glow: float = 2.2
var lamp: OmniLight3D
var blade_prev: Vector3 = Vector3.ZERO
var aim: Vector2 = Vector2.ZERO  ## куда игрок отвёл нож, в долях экрана
var tip_aim: Vector3 = Vector3(0.0, 0.0, -0.7)  ## куда тянется остриё
var t: float = 0.0
var live: bool = false
## Пауза между резами. Она была в плоском слое, но резать стало пространство —
## и без неё один взмах засчитывался дважды: сперва сам мах, потом возврат
## ножа к руке, который тоже быстрый.
var cut_lock: float = 0.0
const CUT_LOCK := 0.16
var _rng := RandomNumberGenerator.new()
var _head: Node3D


## Собираем один раз и прячем: щупальца из восьми звеньев каждое — это
## несколько десятков узлов, и строить их в момент хвата значит подарить
## игроку рывок кадра ровно тогда, когда ему страшнее всего.
func build(head: Node3D, n: int, seed_value: int) -> void:
	_head = head
	_rng.seed = seed_value
	if rig == null:
		rig = Node3D.new()
		head.add_child(rig)
		_make_knife()
		lamp = OmniLight3D.new()
		# СВЕТ НА ВРЕМЯ ХВАТА. Щупальце в метре от лица без света — чёрный
		# силуэт, и вся возня с жижей пропадает впустую. Свет холодный и
		# слабый: это отсвет от лезвия, а не прожектор.
		# ТЁПЛЫЙ, А НЕ ЗЕЛЁНЫЙ. Альбедо у плоти почти чёрное, и в кадре видно не
		# её цвет, а цвет света. Холодный делал из щупалец камень; тёплый —
		# мясо. Это единственная тёплая лампа в лабиринте, и горит она ровно
		# те секунды, пока тебя держат.
		lamp.light_color = Color(0.96, 0.52, 0.42)
		lamp.light_energy = 0.0
		lamp.omni_range = 4.2
		lamp.shadow_enabled = false
		lamp.position = Vector3(0.16, -0.16, -0.30)
		rig.add_child(lamp)
	for a in arms:
		_free_arm(a)
	arms.clear()
	for i in n:
		arms.append(_make_arm(i, n))


func _mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://tentacle.gdshader")
	# Тон и кромка — как у рук твари: это её руки и есть.
	# ТЁПЛЕЕ И ТЕМНЕЕ, ЧЕМ У РУК ТВАРИ. Серо-зелёное вблизи читается камнем;
	# плоть уходит в тёмно-оливковое с бурым, и на ней блик виден как мокрота,
	# а не как иней.
	m.set_shader_parameter("tint", Color(0.105, 0.062, 0.055))
	m.set_shader_parameter("rim_tint", Color(0.34, 0.62, 0.36))
	# Зерно мельче: вблизи крупное превращает тело в трубу с коркой.
	m.set_shader_parameter("bump_k", 2.4)
	# КРОМКА ГОРИТ. Играющий дважды сказал, что не видно, ЧТО резать: тело
	# тёмное, свет один, а вокруг чернота. Очерк решает это без выбеливания —
	# щупальце читается краями, как и всё живое в темноте.
	m.set_shader_parameter("rim_k", 3.4)
	m.set_shader_parameter("wave", 0.10)
	m.set_shader_parameter("speed", 3.0)
	m.set_shader_parameter("pinch", 0.0)
	# МОКРОЕ. Это главное отличие хвата от всех прочих щупалец в игре: его
	# режут в упор, и оно должно блестеть.
	m.set_shader_parameter("wet", 0.9)
	# lit НЕ ТРОГАЕМ. Он умножает альбедо втрое и поднимает кромку: щупальца
	# выбеливались до серых труб. В хвате их лепит свет лампы, а не подсветка.
	m.set_shader_parameter("lit", 0.0)
	# И БЕЗ ДАЛЬНЕЙ КРОМКИ. В коридоре кромка тем ярче, чем тварь дальше, — там
	# это и даёт очертание вместо пятна. Здесь щупальце в метре от лица и своя
	# тёплая лампа: та же прибавка при lit = 0 превратила бы мясо в неоновый
	# контур, ровно то, от чего мы ушли, когда делали хват сочным.
	m.set_shader_parameter("rim_far", 0.0)
	m.set_shader_parameter("phase", _rng.randf() * TAU)
	return m


func _make_arm(i: int, n: int) -> Dictionary:
	var root := Node3D.new()
	rig.add_child(root)
	var mat := _mat()
	var joints: Array = []
	var segl: float = ARM_LEN / float(SEGS)
	var parent: Node3D = root
	for k in SEGS:
		var j := Node3D.new()
		j.position = Vector3.ZERO if k == 0 else Vector3(0.0, -segl, 0.0)
		parent.add_child(j)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		# Сужается к кончику: ровная труба читается шлангом.
		cm.top_radius = maxf(ARM_R * pow(1.0 - float(k) / float(SEGS), 0.8), 0.014)
		cm.bottom_radius = maxf(ARM_R * pow(1.0 - float(k + 1) / float(SEGS), 0.8), 0.012)
		# НАХЛЁСТ ПОБОЛЬШЕ: на витке звенья сходятся под углом, и при малом
		# перекрытии между ними видны зазубрины.
		cm.height = segl * 1.22
		cm.radial_segments = 12
		cm.rings = 2
		cm.cap_top = false
		cm.cap_bottom = false
		mi.mesh = cm
		mi.material_override = mat
		mi.position = Vector3(0.0, -segl * 0.5, 0.0)
		j.add_child(mi)
		joints.append({"node": j, "mesh": mi})
		parent = j
	# Угол, под которым щупальце входит в кадр. Разбрасываем по кругу неровно:
	# ровный веер читается узором, а не хваткой.
	var ang: float = TAU * (float(i) + _rng.randf_range(-0.18, 0.18)) / float(n)
	# КОЛЬЦО-МЕТКА. Играющий сказал прямо: «не видно, что именно надо резать».
	# Значит это надо ПОКАЗАТЬ, а не подразумевать. На каждом щупальце светится
	# перетяжка — набухшее место, по которому и бьют. Целое кольцо зелёное,
	# надрубленное краснеет и начинает биться чаще.
	# НЕ КОЛЬЦО ВОКРУГ, А ПЕРЕТЯЖКА НА ТЕЛЕ.
	#
	# Кольцом был тор, и он подвёл: виток проходит через середину кадра, камера
	# оказывалась ВНУТРИ тора и видела его изнанку — в кадре висели плоские
	# зелёные клинья непонятно чего. Утолщение на самом щупальце внутрь не
	# пускает по построению: это его же тело, только набухшее и светящееся.
	# НЕ ТРУБКА, А НАБУХШИЙ УЗЕЛ. Цилиндр с открытыми торцами показывал свою
	# изнанку и читался рваным листом зелёной бумаги. Шар, сплющенный вдоль
	# тела, — это утолщение, и ни с чем другим его не спутать.
	var mark := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = ARM_R * 1.30
	tm.height = ARM_R * 2.60
	tm.radial_segments = 14
	tm.rings = 8
	mark.mesh = tm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.12, 0.22, 0.14)
	mm.emission_enabled = true
	mm.emission = Color(0.40, 1.0, 0.58)
	mm.emission_energy_multiplier = 1.5
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mark.material_override = mm
	rig.add_child(mark)
	# Куда заворачивает виток и насколько круто. Половина щупалец вьётся в одну
	# сторону, половина в другую: одинаковый завиток читается узором.
	var curl: float = (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(1.5, 2.6)
	return {"root": root, "joints": joints, "ang": ang, "curl": curl,
		"hp": ARM_HP, "since": 0.0,
		"mark": mark, "mark_mat": mm,
		"alive": SEGS, "cut": false, "ph": _rng.randf() * TAU,
		"wobble": _rng.randf_range(0.8, 1.4), "hurt": 0.0, "pull": 0.0}


## КОЛЬЦО СИДИТ НА СЕРЕДИНЕ ЖИВОЙ ЧАСТИ. Отрезали половину — метка переезжает
## на то, что осталось: резать надо то, что ещё держит.
func _pose_mark(a: Dictionary, delta: float) -> void:
	var mark: MeshInstance3D = a["mark"]
	if mark == null:
		return
	if bool(a["cut"]) or not a.has("pts"):
		mark.visible = false
		return
	mark.visible = true
	var pts: Array = a["pts"]
	var alive: int = int(a["alive"])
	# СЕГМЕНТ ВЫБИРАЕМ НЕ ПО СЕРЕДИНЕ, А ПО ВИДИМОСТИ: тот, что дальше сорока
	# сантиметров от лица, иначе метка оказывается вплотную к объективу и
	# читается пятном на весь экран.
	# СЕГМЕНТ ДОЛЖЕН БЫТЬ ВИДЕН.
	#
	# Сначала я брал первый, что дальше сорока сантиметров, — и метка садилась
	# на КОРЕНЬ, который лежит ЗА головой (z положительный). Светилось оно
	# честно, только за спиной у игрока. Теперь отбираем звенья перед лицом и
	# берём среднее из них: там щупальце и пересекает кадр.
	# БЛИЖЕ К СЕРЕДИНЕ ЭКРАНА, А НЕ К СЕРЕДИНЕ ЩУПАЛЬЦА.
	#
	# Сначала я брал среднее из видимых звеньев — и узлы оказывались по краям
	# кадра, где их не ищут. Глаз смотрит в центр, там же ходит нож; туда и
	# сажаем цель. Меряем по углу от направления взгляда: −Z и есть взгляд.
	var k: int = clampi(alive / 2, 0, pts.size() - 2)
	var best: float = -2.0
	for probe in range(alive):
		var mid_p: Vector3 = (pts[probe] + pts[probe + 1]) * 0.5
		if mid_p.z > -0.30 or mid_p.length() < 0.45:
			continue
		var cosa: float = mid_p.normalized().dot(Vector3.FORWARD)
		if cosa > best:
			best = cosa
			k = probe
	a["mark_seg"] = k
	var p0: Vector3 = pts[k]
	var p1: Vector3 = pts[k + 1]
	mark.position = (p0 + p1) * 0.5
	var dir: Vector3 = (p1 - p0).normalized()
	# Ось цилиндра — Y. Кладём её вдоль тела щупальца.
	mark.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), mark.position)
	var mm: StandardMaterial3D = a["mark_mat"]
	# ТРИ СОСТОЯНИЯ, ПО ЧИСЛУ ВЗМАХОВ. Целое — зелёное и дышит ровно; надрублено
	# — янтарное и чаще; почти перебито — красное и колотится. По одному взгляду
	# видно, сколько ещё пилить именно это щупальце.
	var hp: int = int(a["hp"])
	var beat: float = 0.5 + 0.5 * sin(t * (5.0 if hp >= ARM_HP else (8.0 if hp >= 2 else 12.0)))
	if hp >= ARM_HP:
		mm.emission = Color(0.35, 1.0, 0.55)
		mm.emission_energy_multiplier = 1.3 + 1.1 * beat
	elif hp >= 2:
		mm.emission = Color(1.0, 0.72, 0.20)
		mm.emission_energy_multiplier = 1.8 + 1.6 * beat
	else:
		# Почти перебито: метка краснеет и колотится — добей.
		mm.emission = Color(1.0, 0.24, 0.18)
		mm.emission_energy_multiplier = 2.4 + 2.2 * beat
	# ТОЛЩИНА — ПО МЕСТУ, А НЕ ПО КОРНЮ.
	#
	# Метка строилась в радиусе основания, а садилась на седьмое звено, где
	# щупальце вдвое тоньше: вокруг тонкого тела висел обод втрое шире него —
	# на кадре это читалось зелёными лепёшками в воздухе, а не перетяжкой.
	var r_here: float = maxf(ARM_R * pow(1.0 - float(k) / float(SEGS), 0.8), 0.014)
	var want_r: float = r_here * 1.55
	var base_r: float = ARM_R * 1.30
	# Дышит: набухает и опадает. Неподвижное пятно читается наклейкой.
	# Вдоль тела узел короче, чем поперёк: это перетяжка, а не шарик.
	var pulse: float = (want_r / base_r) * (1.0 + 0.16 * beat)
	mark.scale = Vector3(pulse, pulse * 0.62, pulse)


## Перевыборка ломаной по равной длине дуги. Нужна затем, что цепочка звеньев
## умеет только равные шаги: если путь нарезан неравномерно, тело разъезжается
## с расчётом, и всё, что мы ставим «по точкам пути», повисает мимо тела.
func _resample(dense: Array, n: int) -> Array:
	var acc: Array = [0.0]
	var total: float = 0.0
	for i in range(1, dense.size()):
		total += (dense[i] - dense[i - 1]).length()
		acc.append(total)
	var out: Array = []
	var step: float = total / float(n)
	var j: int = 1
	for k in n + 1:
		var want: float = step * float(k)
		while j < acc.size() - 1 and float(acc[j]) < want:
			j += 1
		var a0: float = float(acc[j - 1])
		var a1: float = float(acc[j])
		var t0: float = 0.0 if a1 - a0 < 0.00001 else (want - a0) / (a1 - a0)
		out.append((dense[j - 1] as Vector3).lerp(dense[j], clampf(t0, 0.0, 1.0)))
	return out


func _free_arm(a: Dictionary) -> void:
	var r: Node3D = a["root"]
	if is_instance_valid(r):
		r.queue_free()
	if a.has("mark") and is_instance_valid(a["mark"]):
		a["mark"].queue_free()


## НОЖ. Это та же палочка, только вытянутая в лезвие, — ровно как она уже
## делает в кадре (_wand_blade в мире). Здесь у неё есть остриё: точка, по
## пути которой и считается рез.
func _make_knife() -> void:
	knife = Node3D.new()
	rig.add_child(knife)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.028, 0.34, 0.006)
	blade.mesh = bm
	var m := StandardMaterial3D.new()
	# СТАЛЬ, А НЕ ПЛАСТИК. Светлое альбедо с малой шероховатостью в темноте
	# читалось белой линейкой: у железа альбедо ТЁМНОЕ, светится оно только
	# отражением, и именно этим оно и похоже на железо.
	m.albedo_color = Color(0.34, 0.36, 0.40)
	m.metallic = 1.0
	m.roughness = 0.28
	m.emission_enabled = true
	m.emission = Color(0.22, 0.42, 0.32)
	m.emission_energy_multiplier = 0.12
	blade.mesh.material = m
	blade.position = Vector3(0.0, 0.17, 0.0)
	knife.add_child(blade)
	knife_blade = blade
	_blade_y = blade.position.y
	# Рукоять и бусина с палочки: игрок должен узнать свою вещь.
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.016
	gm.bottom_radius = 0.019
	gm.height = 0.13
	gm.radial_segments = 8
	grip.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.18, 0.15)
	gmat.roughness = 0.9
	grip.mesh.material = gmat
	grip.position = Vector3(0.0, -0.06, 0.0)
	knife.add_child(grip)
	var bead := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	bead.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.55, 0.95, 0.72)
	bmat.emission_enabled = true
	bmat.emission = Color(0.45, 1.0, 0.70)
	bmat.emission_energy_multiplier = 2.2
	bead.mesh.material = bmat
	bead.position = Vector3(0.0, -0.13, 0.0)
	knife.add_child(bead)
	knife_bead = bead
	_bead_glow = bmat.emission_energy_multiplier
	knife_tip = Node3D.new()
	knife_tip.position = Vector3(0.0, 0.34, 0.0)
	knife.add_child(knife_tip)


## ЛЕЗВИЕ РАСТЁТ ИЗ РУКОЯТИ.
##
## Три вещи разом, и все три обязательны, иначе это читается не превращением,
## а включением ножа:
##   1. сталь ВЫТЯГИВАЕТСЯ из рукояти — не появляется целиком, а лезет наружу,
##      поэтому и масштаб, и смещение идут вместе: основание стоит на месте;
##   2. сначала она ТОЛЩЕ, чем станет, и на последней трети утоньшается —
##      масса перетекает в длину, как и положено жидкой твари;
##   3. нож при этом ДОВОРАЧИВАЕТСЯ: пол-оборота вокруг себя, чтобы плоскость
##      встала к лицу. Без доворота выходит выдвижной штык, а не превращение.
## И бусина разгорается вчетверо на середине хода — это она и переливается
## в лезвие, — а к концу садится обратно.
func _pose_blade() -> void:
	if knife_blade == null:
		return
	var k: float = clampf(blade_t, 0.0, 1.0)
	# Мягкий старт и причаливание: линейный рост читается механикой.
	var e: float = k * k * (3.0 - 2.0 * k)
	knife_blade.visible = e > 0.001
	knife_blade.scale = Vector3(
		# Утолщение к середине и утоньшение к концу.
		1.0 + 0.9 * sin(e * PI) * (1.0 - e * 0.5),
		maxf(0.02, e),
		1.0 + 1.6 * sin(e * PI))
	# Основание лезвия остаётся у рукояти: центр едет вместе с ростом.
	knife_blade.position.y = _blade_y * e
	# ВЕРТИМ САМО ЛЕЗВИЕ, А НЕ НОЖ. Поворот я сперва писал в knife.rotation.y —
	# и стенд намерил «поворот 1°»: позу ножа целиком переписывает _pose_knife
	# из прицела, каждый кадр. Лезвие же его собственный ребёнок, стоит на оси,
	# и оборот вокруг Y разворачивает ровно плоскость стали.
	var over: float = sin(e * PI) * 0.16
	knife_blade.rotation.y = (1.0 - e) * PI + over
	if knife_bead != null:
		var flare: float = sin(e * PI)
		knife_bead.scale = Vector3.ONE * (1.0 + 1.3 * flare)
		var bm: StandardMaterial3D = knife_bead.mesh.material
		if bm != null:
			bm.emission_energy_multiplier = _bead_glow * (1.0 + 3.0 * flare)


## ХВАТ НАЧАЛСЯ. Щупальца выходят из-за краёв кадра и смыкаются на лице.
func begin() -> void:
	live = true
	t = 0.0
	aim = Vector2.ZERO
	visible = true
	if rig != null:
		rig.visible = true
	blade_prev = Vector3.ZERO
	blade_t = 0.0
	_pose_blade()
	for a in arms:
		a["hp"] = ARM_HP
		a["since"] = 0.0
		a["alive"] = SEGS
		a["cut"] = false
		a["hurt"] = 0.0
		a["pull"] = 0.0
		for j in a["joints"]:
			j["mesh"].visible = true


func finish() -> void:
	live = false
	if rig != null:
		rig.visible = false
	if lamp != null:
		lamp.light_energy = 0.0
	for p in pieces:
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	pieces.clear()
	# Капли с линзы сходят сами, но если хват кончился — стираем сразу: иначе
	# игрок побежит дальше, а на экране останется чужая кровь.
	for d in drops:
		if is_instance_valid(d["node"]):
			d["node"].queue_free()
	drops.clear()
	for a in arms:
		if a.has("drip") and is_instance_valid(a["drip"]):
			a["drip"].queue_free()
			a.erase("drip")


## КУДА ИГРОК ОТВЁЛ НОЖ. Мышь двигает не голову, а руку: доли экрана, от −1 до 1.
func aim_by(rel: Vector2) -> void:
	aim.x = clampf(aim.x + rel.x, -1.0, 1.0)
	aim.y = clampf(aim.y + rel.y, -1.0, 1.0)


func tick(delta: float, grip: float) -> void:
	if not live:
		return
	t += delta
	cut_lock = maxf(0.0, cut_lock - delta)
	if lamp != null:
		# Свет разгорается вместе с хваткой: чем крепче держат, тем ближе лицо
		# к телу и тем больше видно.
		# ЯРЧЕ, ЧЕМ ХОТЕЛОСЬ БЫ ПО КРАСОТЕ.
		#
		# Я держал лампу тусклой, чтобы тьма работала, — и получил ровно то, что
		# сказал играющий: «не видно щупалец, которые надо резать». В хвате
		# темнота перестаёт быть атмосферой и становится помехой: резать надо
		# то, что ВИДНО. Свет живёт эти несколько секунд и гаснет вместе с
		# хватом, так что тьме он не мешает.
		lamp.light_energy = lerpf(lamp.light_energy, 1.05 + 0.55 * grip, delta * 7.0)
	if blade_t < 1.0:
		blade_t = minf(1.0, blade_t + delta / BLADE_GROW)
		_pose_blade()
	_pose_knife(delta)
	# РАНЫ ЗАТЯГИВАЮТСЯ. Считаем ДО поз: щупальце, которое не добили, должно
	# успеть поменять метку в этом же кадре.
	for a in arms:
		if bool(a["cut"]):
			continue
		if int(a["hp"]) >= ARM_HP:
			a["since"] = 0.0
			continue
		a["since"] = float(a["since"]) + delta
		if float(a["since"]) >= REGROW:
			a["since"] = 0.0
			a["hp"] = int(a["hp"]) + 1
			a["hurt"] = 0.6
			healed.emit()
	for i in arms.size():
		_pose_arm(arms[i], i, delta, grip)
	_move_pieces(delta)
	_move_drops(delta)
	for a2 in arms:
		_pose_mark(a2, delta)


## Нож держат перед собой и ведут рукой. Он и наклоняется по ходу движения —
## неподвижное лезвие, ездящее по экрану, читается курсором.
func _pose_knife(delta: float) -> void:
	if knife == null:
		return
	# НОЖ ХОДИТ ПО ТОЙ ЖЕ ОБОЛОЧКЕ, ЧТО И ЩУПАЛЬЦА.
	#
	# Это оказалось главным. Нож ездил по маленькому прямоугольнику перед
	# грудью, а щупальца лежат на сфере в двух третях метра от лица — и замер
	# показал прямо: до двух щупалец из трёх ОСТРИЁ НЕ ДОСТАВАЛО НИКОГДА,
	# сколько ни маши. Играющий это и почувствовал: «не видно, что резать», —
	# видно-то было, только попасть было нельзя.
	#
	# Теперь прицел — это УГОЛ, а не смещение: остриё ведём по сфере радиусом
	# с оболочку щупалец. Куда смотришь ножом, туда он и дотягивается.
	var ax: float = aim.x * 0.62
	var ay: float = -aim.y * 0.46
	var dirv := Vector3(sin(ax) * cos(ay), sin(ay), -cos(ax) * cos(ay))
	var want_tip: Vector3 = dirv * (SHELL * 0.62)
	# Рука отстаёт от мыши: у железа есть вес, и запаздывание — это он и есть.
	var was_tip: Vector3 = knife_tip.global_position
	tip_aim = tip_aim.lerp(want_tip, clampf(delta * 13.0, 0.0, 1.0))
	var lean: float = clampf(aim.x, -1.0, 1.0)
	var tilt: float = clampf(-aim.y, -1.0, 1.0)
	# Лезвие смотрит вверх-влево от кисти: так видно и клинок, и то, что за ним.
	knife.rotation = Vector3(
		deg_to_rad(-24.0 + 26.0 * tilt),
		deg_to_rad(14.0 * lean),
		deg_to_rad(-44.0 - 18.0 * lean))
	# И ставим кисть так, чтобы ОСТРИЁ попало в намеченную точку.
	knife.position = tip_aim - knife.transform.basis * knife_tip.position
	var run: Vector3 = (knife_tip.global_position - was_tip) / maxf(delta, 0.001)
	var sway: float = clampf(run.x * 0.05, -0.4, 0.4)
	knife.rotation.z -= sway


## ЩУПАЛЬЦЕ ЛЕЖИТ ПО ДУГЕ: от края кадра к лицу. Дуга живая — она дышит и
## подтягивается вместе с хваткой, поэтому целиться приходится заново.
func _pose_arm(a: Dictionary, idx: int, delta: float, grip: float) -> void:
	var root: Node3D = a["root"]
	var ang: float = float(a["ang"])
	var ph: float = float(a["ph"]) + t * float(a["wobble"])
	a["hurt"] = maxf(0.0, float(a["hurt"]) - delta * 2.0)
	# Обрубленное отползает: тянем его назад за кадр.
	if bool(a["cut"]):
		a["pull"] = minf(1.0, float(a["pull"]) + delta * 1.6)
	var pull: float = float(a["pull"])
	# ОНИ ОБВИВАЮТ, А НЕ ТЫЧУТ.
	#
	# Дуга Безье от края кадра к лицу давала палку: щупальце входило прямо и
	# упиралось в середину, и три таких складывались в звезду. Живое так не
	# держит — оно ОБОРАЧИВАЕТСЯ вокруг головы.
	#
	# Поэтому путь считается в полярных: угол по дороге уезжает (curl), радиус
	# сходится к лицу, а глубина — из-за спины вперёд с провисом. Получается
	# виток, а не отрезок, и каждое щупальце входит в кадр со своей стороны.
	var curl: float = float(a["curl"])
	# ПУТЬ СЧИТАЕМ ЧАСТО, А ЗВЕНЬЯ СТАВИМ РОВНО.
	#
	# Раньше я брал SEGS+1 точек прямо по параметру: шаги по кривой выходили
	# РАЗНОЙ длины, а звенья цепочки — одинаковой, и тело ложилось не туда,
	# где считался путь. Отсюда и главная беда: светящийся узел висел в
	# воздухе рядом со щупальцем, а не на нём, — и игрок не понимал, что резать.
	#
	# Теперь: шестьдесят точек по кривой, потом перевыборка по РАВНОЙ ДЛИНЕ
	# ДУГИ. Тогда звено в точности ложится на свой кусок пути.
	var dense: Array = []
	var fine := 60
	for k in fine + 1:
		var u: float = float(k) / float(fine)
		var sm: float = u * u * (3.0 - 2.0 * u)
		var th: float = ang + curl * sm + sin(ph * 0.8) * 0.10
		var rad: float = lerpf(0.92, 0.22, sm) + 0.06 * sin(ph * 1.6 + u * 4.0)
		var z: float = lerpf(0.34 + pull * 1.2, -TIP_NEAR - pull * 1.3, sm) \
			- sin(sm * PI) * 0.34
		# ВЫШЕ И ШИРЕ ПО ВЕРТИКАЛИ. Виток жался к низу кадра: сверху пустота,
		# а глаз смотрит в середину — оттого и «не видно, что резать». Поднимаем
		# на ладонь и растягиваем по высоте почти до круга.
		var p := Vector3(cos(th) * rad, sin(th) * rad * 0.95 + 0.16, z)
		p += Vector3(sin(ph * 2.1 + u * 5.0), cos(ph * 1.7 + u * 4.2), 0.0) * 0.035 * u
		dense.append(p)
	var pts: Array = _resample(dense, SEGS)
	a["pts"] = pts
	root.position = pts[0]
	# ЗВЕНО ПОДГОНЯЕТСЯ ПОД ДУГУ. Цепочка звеньев жёсткой длины не ляжет на
	# кривую другой длины: кончик либо не доходит, либо проскакивает мимо лица.
	# Считаем длину дуги каждый кадр и растягиваем звенья под неё.
	var total: float = 0.0
	for k2 in SEGS:
		total += (pts[k2 + 1] - pts[k2]).length()
	var segl: float = total / float(SEGS)
	var base_seg: float = ARM_LEN / float(SEGS)
	var alive: int = int(a["alive"])
	for k in SEGS:
		var jd: Dictionary = a["joints"][k]
		var j: Node3D = jd["node"]
		var mi: MeshInstance3D = jd["mesh"]
		if k >= alive:
			mi.visible = false
			continue
		mi.visible = true
		if k > 0:
			j.position = Vector3(0.0, -segl, 0.0)
		mi.position.y = -segl * 0.5
		mi.scale.y = segl / base_seg
		var dir: Vector3 = (pts[k + 1] - pts[k])
		if dir.length() < 0.0005:
			continue
		# ДУГА — В ОСЯХ ГОЛОВЫ, А ПОВОРОТ СТАВИТСЯ В ОСЯХ МИРА. Направление
		# брали из точек дуги как есть и прикладывали через global_transform:
		# пока игрок смотрел в исходную сторону, оси совпадали и всё было на
		# месте, — стенд так и ловил. Стоило повернуться — цепочка уходила за
		# спину, а в кадре оставались одни метки: они стоят по дуге, а не по
		# звеньям. Играющий (18.09): «щупалец не видно, только точки».
		dir = (rig.global_transform.basis * dir).normalized()
		# Локальная −Y звена должна смотреть вдоль дуги. Кватернион «из DOWN в
		# dir» — самый короткий поворот, который это делает.
		var b := Basis(Quaternion(Vector3.DOWN, dir))
		j.global_transform = Transform3D(b, j.global_position)
		# Раненое подрагивает.
		if float(a["hurt"]) > 0.01:
			mi.position.x = sin(t * 60.0 + float(k)) * 0.012 * float(a["hurt"])
		else:
			mi.position.x = 0.0


## РЕЗ. Считается по отрезку, который остриё прошло за кадр, — в пространстве,
## а не по экрану. Возвращает: -1 мимо, иначе номер задетого щупальца.
##
## Медленное ведение не режет. Без нижнего порога щупальца распадались бы от
## того, что игрок просто держит мышь в кулаке, — и нож стал бы ластиком.
func try_cut(delta: float) -> int:
	if not live or knife_tip == null:
		return -1
	# НЕДОРОСШИМ ЛЕЗВИЕМ НЕ РЕЖУТ. Полсекунды, пока сталь лезет из рукояти,
	# в руке огрызок — и засчитывать им порезы значит показывать одно, а
	# считать другое. Заодно это и есть та пауза, за которую игрок успевает
	# увидеть само превращение.
	if blade_t < 0.8:
		blade_prev = knife_tip.global_position
		return -1
	var now: Vector3 = knife_tip.global_position
	if blade_prev == Vector3.ZERO:
		blade_prev = now
		return -1
	if cut_lock > 0.0:
		blade_prev = now
		return -1
	var moved: float = now.distance_to(blade_prev)
	var speed: float = moved / maxf(delta, 0.0001)
	var from: Vector3 = blade_prev
	blade_prev = now
	if speed < SWING_MIN:
		return -1
	for i in arms.size():
		var a: Dictionary = arms[i]
		if bool(a["cut"]) or not a.has("pts"):
			continue
		var pts: Array = a["pts"]
		var alive: int = int(a["alive"])
		# БЬЮТ ПО МЕТКЕ, А НЕ ПО ВСЕЙ ДЛИНЕ. Если засчитывать удар в любое
		# место, светящееся кольцо превращается в украшение: целиться незачем,
		# маши где попало. Окно шире самого кольца на звено в каждую сторону —
		# метка показывает, а не наказывает за миллиметр.
		var mk: int = int(a.get("mark_seg", alive / 2))
		var lo: int = maxi(mk - 1, 0)
		var hi: int = mini(mk + 1, alive - 1)
		for k in range(lo, hi + 1):
			var p0: Vector3 = rig.global_transform * pts[k]
			var p1: Vector3 = rig.global_transform * pts[k + 1]
			if _seg_dist(from, now, p0, p1) > HIT_R:
				continue
			return _wound(i, k, (p0 + p1) * 0.5)
	return -1


## Задели щупальце на звене k. Первый раз — надруб, второй — обрубаем.
func _wound(i: int, k: int, at: Vector3) -> int:
	cut_lock = CUT_LOCK
	var a: Dictionary = arms[i]
	a["hurt"] = 1.0
	a["since"] = 0.0
	a["hp"] = int(a["hp"]) - 1
	if int(a["hp"]) > 0:
		splash(at, false)
		lens_drops(2, at)
		touched.emit(i, false)
		hurt_at.emit(at, false)
		return i
	# ОБРУБАЕМ РОВНО ТАМ, ГДЕ ПРОШЛО ЛЕЗВИЕ. Не у корня и не у кончика: игрок
	# должен видеть, что срез там, куда он попал.
	var cut_at: int = clampi(k, 1, SEGS - 1)
	a["cut"] = true
	a["alive"] = cut_at
	_drop_piece(a, cut_at)
	splash(at, true)
	lens_drops(5, at)
	_drip(a)
	touched.emit(i, true)
	hurt_at.emit(at, true)
	return i


## Отрубленный кусок живёт сам: летит по дуге, кувыркается и гаснет.
func _drop_piece(a: Dictionary, from_seg: int) -> void:
	var pts: Array = a["pts"]
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var segl: float = ARM_LEN / float(SEGS)
	var rest: int = SEGS - from_seg
	cm.top_radius = maxf(ARM_R * pow(1.0 - float(from_seg) / float(SEGS), 0.8), 0.014)
	cm.bottom_radius = 0.012
	cm.height = segl * float(rest)
	cm.radial_segments = 12
	cm.rings = 3
	mi.mesh = cm
	mi.material_override = _mat()
	add_child(mi)
	mi.top_level = true
	var mid: Vector3 = rig.global_transform * pts[from_seg]
	var end: Vector3 = rig.global_transform * pts[SEGS]
	mi.global_position = (mid + end) * 0.5
	var dir: Vector3 = (end - mid).normalized()
	mi.global_transform = Transform3D(Basis(Quaternion(Vector3.DOWN, dir)),
		mi.global_position)
	# Летит вниз и в сторону от лица: вверх он бы «выпрыгивал», а он падает.
	var away: Vector3 = (mid - _head.global_position).normalized()
	# Отрубленное не падает кирпичом: оно ещё живое и потому ХЛЕЩЕТ — уходит
	# вбок с вращением, а вниз его тянет уже потом.
	var whip: Vector3 = (end - mid).normalized().cross(Vector3.UP).normalized()
	pieces.append({"node": mi, "v": away * _rng.randf_range(0.8, 1.6)
		+ whip * _rng.randf_range(-2.2, 2.2)
		+ Vector3(0.0, _rng.randf_range(0.4, 1.1), 0.0),
		"spin": Vector3(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-4.0, 4.0),
			_rng.randf_range(-6.0, 6.0)), "t": 2.6})


func _move_pieces(delta: float) -> void:
	for p in pieces:
		var n: Node3D = p["node"]
		if not is_instance_valid(n):
			continue
		p["t"] = float(p["t"]) - delta
		var v: Vector3 = p["v"]
		v.y -= 9.0 * delta
		p["v"] = v
		n.global_position += v * delta
		var sp: Vector3 = p["spin"]
		n.rotate_x(sp.x * delta)
		n.rotate_y(sp.y * delta)
		n.rotate_z(sp.z * delta)
		if float(p["t"]) <= 0.0:
			n.queue_free()
	var keep: Array = []
	for p in pieces:
		if float(p["t"]) > 0.0 and is_instance_valid(p["node"]):
			keep.append(p)
	pieces = keep


## Ближайшее расстояние между двумя отрезками. Нужно ровно оно: пересеклись —
## ноль, разошлись — насколько.
func _seg_dist(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var u: Vector3 = a1 - a0
	var v: Vector3 = b1 - b0
	var w: Vector3 = a0 - b0
	var uu: float = u.dot(u)
	var uv: float = u.dot(v)
	var vv: float = v.dot(v)
	var uw: float = u.dot(w)
	var vw: float = v.dot(w)
	var den: float = uu * vv - uv * uv
	var s: float = 0.0
	var tt: float = 0.0
	if den > 0.000001:
		s = clampf((uv * vw - vv * uw) / den, 0.0, 1.0)
		tt = clampf((uu * vw - uv * uw) / den, 0.0, 1.0)
	else:
		s = 0.0
		tt = clampf(vw / maxf(vv, 0.000001), 0.0, 1.0)
	var pa: Vector3 = a0 + u * s
	var pb: Vector3 = b0 + v * tt
	return pa.distance_to(pb)


## ДЛЯ СТЕНДА. Настоящий взмах поперёк ближайшего целого щупальца — и делается
## он ТЕМ ЖЕ ПУТЁМ, что у игрока: через прицел. Ставить нож руками было нечестно
## вдвойне — стенд бы не заметил, что игроку до щупальца просто не дотянуться.
func bot_slash() -> bool:
	if not live or knife_tip == null:
		return false
	for a in arms:
		if bool(a["cut"]) or not a.has("pts") or not a.has("mark_seg"):
			continue
		var pts: Array = a["pts"]
		var k: int = int(a["mark_seg"])
		var mid: Vector3 = (pts[k] + pts[k + 1]) * 0.5
		var goal: Vector2 = _aim_for(mid)
		# Поперёк тела: берём направление звена, переводим в прицел и идём
		# перпендикулярно ему.
		var along: Vector2 = _aim_for(pts[k + 1]) - _aim_for(pts[k])
		var cross := Vector2(-along.y, along.x)
		if cross.length() < 0.001:
			cross = Vector2(1.0, 0.0)
		cross = cross.normalized() * 0.42
		aim = (goal - cross).clamp(Vector2(-1, -1), Vector2(1, 1))
		_pose_knife(1.0 / 60.0)
		blade_prev = knife_tip.global_position
		aim = (goal + cross).clamp(Vector2(-1, -1), Vector2(1, 1))
		_pose_knife(1.0 / 60.0)
		cut_lock = 0.0
		return try_cut(1.0 / 60.0) >= 0
	return false


## Обратный перевод: в какой прицел надо встать, чтобы остриё смотрело в точку.
## Прямой перевод живёт в _pose_knife, и эти двое обязаны совпадать.
func _aim_for(local_point: Vector3) -> Vector2:
	var d: Vector3 = local_point.normalized()
	var ay: float = asin(clampf(d.y, -1.0, 1.0))
	var ax: float = atan2(d.x, -d.z)
	return Vector2(clampf(ax / 0.62, -1.0, 1.0), clampf(-ay / 0.46, -1.0, 1.0))


# ─────────────────────────── жижа ───────────────────────────
##
## Резать в темноте то, что никак не отзывается, — упражнение, а не сцена.
## Отзывается оно тремя способами сразу, и все три нужны:
##   1. БРЫЗГИ из-под лезвия — короткий веер капель;
##   2. КАПЛИ НА ЛИНЗЕ — то, что долетело до тебя: единственное, что напоминает,
##      что между тобой и этим нет ничего;
##   3. КУЛЬТЯ ТЕЧЁТ — обрубок не замирает, из него льёт ещё несколько секунд.

var drops: Array = []            ## капли на «линзе»
var drop_tex: Texture2D
var lens: Node3D


func _gore_ready() -> void:
	if lens != null:
		return
	lens = Node3D.new()
	# Ближе к глазу, чем всё остальное: это на тебе, а не в мире.
	lens.position = Vector3(0.0, 0.0, -0.16)
	rig.add_child(lens)
	drop_tex = _make_drop_tex()


## Капля рисуется в памяти: мягкое пятно, слегка вытянутое вниз.
func _make_drop_tex() -> Texture2D:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var dx: float = (float(x) + 0.5) / float(n) - 0.5
			var dy: float = (float(y) + 0.5) / float(n) - 0.5
			var d: float = sqrt(dx * dx + dy * dy * 0.55) * 2.0
			if d > 1.0:
				continue
			var a: float = pow(1.0 - d, 1.6)
			img.set_pixel(x, y, Color(0.30, 0.055, 0.050, a))
	return ImageTexture.create_from_image(img)


## БРЫЗГИ. Одноразовый выброс в точке реза: доли секунды, и существует он
## затем, чтобы удар был ВИДЕН, а не только услышан.
func splash(at: Vector3, strong: bool) -> void:
	var ps := GPUParticles3D.new()
	add_child(ps)
	ps.top_level = true
	ps.global_position = at
	ps.amount = 26 if strong else 12
	ps.lifetime = 0.9 if strong else 0.6
	ps.one_shot = true
	ps.explosiveness = 0.92
	ps.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.2 if strong else 0.7
	pm.initial_velocity_max = 3.6 if strong else 1.8
	pm.gravity = Vector3(0, -6.5, 0)
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	ps.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.016
	sm.height = 0.032
	sm.radial_segments = 6
	sm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.30, 0.045, 0.040)
	dm.roughness = 0.2
	dm.emission_enabled = true
	dm.emission = Color(0.36, 0.05, 0.04)
	dm.emission_energy_multiplier = 0.55
	sm.material = dm
	ps.draw_pass_1 = sm
	var tm := Timer.new()
	tm.wait_time = float(ps.lifetime) + 0.4
	tm.one_shot = true
	ps.add_child(tm)
	tm.timeout.connect(ps.queue_free)
	tm.start()


## КАПЛИ НА ЛИНЗЕ. Долетело до лица — осталось на лице.
func lens_drops(n: int, from: Vector3) -> void:
	_gore_ready()
	var local: Vector3 = rig.global_transform.affine_inverse() * from
	var dir := Vector2(local.x, local.y)
	if dir.length() > 0.001:
		dir = dir.normalized()
	for i in n:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		# Мелкие: на шестнадцати сантиметрах от глаза трёхсантиметровая капля
		# закрывает восьмую часть экрана.
		var sz: float = _rng.randf_range(0.004, 0.013)
		q.size = Vector2(sz, sz * _rng.randf_range(1.0, 1.6))
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_texture = drop_tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 1, 1, _rng.randf_range(0.30, 0.65))
		mi.material_override = m
		mi.position = Vector3(
			dir.x * _rng.randf_range(0.01, 0.055) + _rng.randf_range(-0.03, 0.03),
			dir.y * _rng.randf_range(0.01, 0.055) + _rng.randf_range(-0.03, 0.03),
			0.0)
		lens.add_child(mi)
		drops.append({"node": mi, "mat": m, "t": _rng.randf_range(1.6, 3.2),
			"v": _rng.randf_range(0.004, 0.016), "wait": _rng.randf_range(0.0, 0.5)})


func _move_drops(delta: float) -> void:
	var keep: Array = []
	for d in drops:
		var mi: MeshInstance3D = d["node"]
		if not is_instance_valid(mi):
			continue
		d["t"] = float(d["t"]) - delta
		d["wait"] = maxf(0.0, float(d["wait"]) - delta)
		if float(d["wait"]) <= 0.0:
			# Ползёт вниз и разгоняется: капля на стекле так себя и ведёт.
			d["v"] = float(d["v"]) + delta * 0.010
			mi.position.y -= float(d["v"]) * delta * 2.0
		var m: StandardMaterial3D = d["mat"]
		var a: Color = m.albedo_color
		a.a = clampf(float(d["t"]) * 0.7, 0.0, 1.0)
		m.albedo_color = a
		if float(d["t"]) <= 0.0:
			mi.queue_free()
		else:
			keep.append(d)
	drops = keep


## КУЛЬТЯ ТЕЧЁТ. Пара секунд ручейка — именно он превращает «щупальце стало
## короче» в «я его отрезал».
func _drip(a: Dictionary) -> void:
	var alive: int = int(a["alive"])
	if alive <= 0:
		return
	var jd: Dictionary = a["joints"][alive - 1]
	var j: Node3D = jd["node"]
	var ps := GPUParticles3D.new()
	j.add_child(ps)
	ps.position = Vector3(0.0, -(ARM_LEN / float(SEGS)), 0.0)
	ps.amount = 26
	ps.lifetime = 1.5
	ps.one_shot = false
	ps.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, -7.0, 0)
	pm.scale_min = 0.3
	pm.scale_max = 0.8
	ps.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	sm.radial_segments = 6
	sm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.26, 0.04, 0.035)
	dm.emission_enabled = true
	dm.emission = Color(0.34, 0.05, 0.04)
	dm.emission_energy_multiplier = 0.5
	sm.material = dm
	ps.draw_pass_1 = sm
	a["drip"] = ps
