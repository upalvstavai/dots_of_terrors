extends RefCounted
## Данные полотен, перенесены один в один из HTML-прототипа.
## Двадцать фигур: на забег берутся шесть и сортируются по числу точек,
## чтобы рисунок усложнялся к концу. Кто умирал на пятом полотне, раньше
## перерисовывал те же четыре — отсюда и пул.

const POOL := [
	{"name": "ключ", "pts": [Vector2(0.34, 0.18), Vector2(0.5, 0.16), Vector2(0.52, 0.34), Vector2(0.64, 0.36), Vector2(0.62, 0.48), Vector2(0.52, 0.46), Vector2(0.5, 0.8), Vector2(0.34, 0.78)]},
	{"name": "птица", "pts": [Vector2(0.22, 0.55), Vector2(0.38, 0.36), Vector2(0.5, 0.44), Vector2(0.68, 0.26), Vector2(0.63, 0.5), Vector2(0.74, 0.55), Vector2(0.55, 0.62), Vector2(0.38, 0.72)]},
	{"name": "лампа", "pts": [Vector2(0.42, 0.14), Vector2(0.58, 0.14), Vector2(0.66, 0.42), Vector2(0.55, 0.45), Vector2(0.55, 0.62), Vector2(0.62, 0.78), Vector2(0.38, 0.78), Vector2(0.45, 0.62), Vector2(0.45, 0.45), Vector2(0.34, 0.42)]},
	{"name": "мотылёк", "pts": [Vector2(0.5, 0.2), Vector2(0.66, 0.3), Vector2(0.74, 0.55), Vector2(0.58, 0.55), Vector2(0.62, 0.78), Vector2(0.5, 0.66), Vector2(0.38, 0.78), Vector2(0.42, 0.55), Vector2(0.26, 0.55), Vector2(0.34, 0.3)]},
	{"name": "дом", "pts": [Vector2(0.3, 0.8), Vector2(0.3, 0.42), Vector2(0.5, 0.2), Vector2(0.7, 0.42), Vector2(0.7, 0.8), Vector2(0.58, 0.8), Vector2(0.58, 0.6), Vector2(0.42, 0.6), Vector2(0.42, 0.8)]},
	{"name": "улитка", "pts": [Vector2(0.5, 0.18), Vector2(0.64, 0.24), Vector2(0.74, 0.38), Vector2(0.72, 0.56), Vector2(0.6, 0.7), Vector2(0.44, 0.74), Vector2(0.3, 0.68), Vector2(0.22, 0.54), Vector2(0.26, 0.38), Vector2(0.38, 0.28), Vector2(0.5, 0.36)]},
	{"name": "рыба", "pts": [Vector2(0.22, 0.5), Vector2(0.34, 0.34), Vector2(0.54, 0.32), Vector2(0.68, 0.44), Vector2(0.8, 0.3), Vector2(0.8, 0.7), Vector2(0.68, 0.56), Vector2(0.54, 0.68), Vector2(0.34, 0.66)]},
	{"name": "дерево", "pts": [Vector2(0.44, 0.82), Vector2(0.44, 0.58), Vector2(0.3, 0.52), Vector2(0.24, 0.38), Vector2(0.36, 0.28), Vector2(0.5, 0.18), Vector2(0.64, 0.28), Vector2(0.76, 0.4), Vector2(0.64, 0.54), Vector2(0.56, 0.58), Vector2(0.56, 0.82)]},
	{"name": "рука", "pts": [Vector2(0.32, 0.82), Vector2(0.29, 0.56), Vector2(0.24, 0.36), Vector2(0.36, 0.34), Vector2(0.42, 0.24), Vector2(0.52, 0.26), Vector2(0.6, 0.3), Vector2(0.68, 0.42), Vector2(0.68, 0.6), Vector2(0.6, 0.82)]},
	{"name": "глаз", "pts": [Vector2(0.2, 0.5), Vector2(0.32, 0.34), Vector2(0.46, 0.26), Vector2(0.6, 0.3), Vector2(0.74, 0.4), Vector2(0.82, 0.5), Vector2(0.7, 0.62), Vector2(0.56, 0.7), Vector2(0.4, 0.68), Vector2(0.28, 0.6)]},
	{"name": "череп", "pts": [Vector2(0.34, 0.3), Vector2(0.44, 0.18), Vector2(0.58, 0.18), Vector2(0.68, 0.3), Vector2(0.7, 0.48), Vector2(0.6, 0.58), Vector2(0.6, 0.74), Vector2(0.42, 0.74), Vector2(0.42, 0.58), Vector2(0.32, 0.48)]},
	{"name": "кораблик", "pts": [Vector2(0.48, 0.14), Vector2(0.76, 0.48), Vector2(0.5, 0.48), Vector2(0.24, 0.48), Vector2(0.18, 0.64), Vector2(0.32, 0.8), Vector2(0.7, 0.8), Vector2(0.84, 0.64), Vector2(0.62, 0.48)]},
	{"name": "часы", "pts": [Vector2(0.26, 0.14), Vector2(0.74, 0.14), Vector2(0.66, 0.3), Vector2(0.54, 0.46), Vector2(0.66, 0.62), Vector2(0.74, 0.78), Vector2(0.26, 0.78), Vector2(0.34, 0.62), Vector2(0.46, 0.46), Vector2(0.34, 0.3)]},
	{"name": "цветок", "pts": [Vector2(0.5, 0.82), Vector2(0.5, 0.54), Vector2(0.34, 0.48), Vector2(0.28, 0.32), Vector2(0.42, 0.24), Vector2(0.5, 0.12), Vector2(0.6, 0.24), Vector2(0.74, 0.32), Vector2(0.68, 0.48), Vector2(0.6, 0.5)]},
	{"name": "колокол", "pts": [Vector2(0.5, 0.1), Vector2(0.62, 0.2), Vector2(0.68, 0.4), Vector2(0.76, 0.6), Vector2(0.8, 0.72), Vector2(0.2, 0.72), Vector2(0.24, 0.6), Vector2(0.32, 0.4), Vector2(0.38, 0.2)]},
	{"name": "замок", "pts": [Vector2(0.32, 0.44), Vector2(0.32, 0.32), Vector2(0.4, 0.22), Vector2(0.5, 0.18), Vector2(0.6, 0.22), Vector2(0.68, 0.32), Vector2(0.68, 0.44), Vector2(0.78, 0.44), Vector2(0.78, 0.8), Vector2(0.22, 0.8), Vector2(0.22, 0.44)]},
	{"name": "змея", "pts": [Vector2(0.16, 0.7), Vector2(0.3, 0.78), Vector2(0.46, 0.7), Vector2(0.58, 0.58), Vector2(0.68, 0.44), Vector2(0.64, 0.28), Vector2(0.5, 0.2), Vector2(0.36, 0.26), Vector2(0.34, 0.4), Vector2(0.46, 0.46)]},
	{"name": "гроб", "pts": [Vector2(0.42, 0.12), Vector2(0.58, 0.12), Vector2(0.68, 0.28), Vector2(0.7, 0.42), Vector2(0.62, 0.62), Vector2(0.58, 0.84), Vector2(0.42, 0.84), Vector2(0.38, 0.62), Vector2(0.3, 0.42), Vector2(0.32, 0.28)]},
	{"name": "дверь", "pts": [Vector2(0.32, 0.84), Vector2(0.32, 0.3), Vector2(0.42, 0.18), Vector2(0.58, 0.18), Vector2(0.68, 0.3), Vector2(0.68, 0.84), Vector2(0.58, 0.84), Vector2(0.58, 0.52), Vector2(0.42, 0.52), Vector2(0.42, 0.84)]},
	{"name": "свеча", "pts": [Vector2(0.5, 0.12), Vector2(0.6, 0.24), Vector2(0.54, 0.36), Vector2(0.44, 0.36), Vector2(0.38, 0.24), Vector2(0.36, 0.44), Vector2(0.36, 0.8), Vector2(0.64, 0.8), Vector2(0.64, 0.44)]},
	{"name": "корона", "pts": [Vector2(0.18, 0.66), Vector2(0.22, 0.34), Vector2(0.31, 0.5), Vector2(0.36, 0.24), Vector2(0.44, 0.42), Vector2(0.5, 0.16), Vector2(0.56, 0.42), Vector2(0.64, 0.24), Vector2(0.69, 0.5), Vector2(0.78, 0.34), Vector2(0.82, 0.66), Vector2(0.7, 0.78), Vector2(0.5, 0.82), Vector2(0.3, 0.78)]},
	{"name": "дом с трубой", "pts": [Vector2(0.2, 0.82), Vector2(0.2, 0.5), Vector2(0.34, 0.5), Vector2(0.34, 0.32), Vector2(0.42, 0.32), Vector2(0.42, 0.42), Vector2(0.5, 0.16), Vector2(0.72, 0.4), Vector2(0.8, 0.5), Vector2(0.8, 0.82), Vector2(0.62, 0.82), Vector2(0.62, 0.6), Vector2(0.44, 0.6), Vector2(0.44, 0.82)]},
	{"name": "ворота", "pts": [Vector2(0.16, 0.86), Vector2(0.16, 0.42), Vector2(0.24, 0.24), Vector2(0.4, 0.14), Vector2(0.6, 0.14), Vector2(0.76, 0.24), Vector2(0.84, 0.42), Vector2(0.84, 0.86), Vector2(0.7, 0.86), Vector2(0.7, 0.44), Vector2(0.6, 0.3), Vector2(0.4, 0.3), Vector2(0.3, 0.44), Vector2(0.3, 0.86)]},
	{"name": "решётка", "pts": [Vector2(0.18, 0.18), Vector2(0.82, 0.18), Vector2(0.82, 0.82), Vector2(0.18, 0.82), Vector2(0.18, 0.5), Vector2(0.82, 0.5), Vector2(0.82, 0.34), Vector2(0.18, 0.34), Vector2(0.18, 0.66), Vector2(0.82, 0.66), Vector2(0.5, 0.66), Vector2(0.5, 0.18), Vector2(0.34, 0.18), Vector2(0.34, 0.82), Vector2(0.66, 0.82), Vector2(0.66, 0.18)]},
	{"name": "дерево большое", "pts": [Vector2(0.44, 0.88), Vector2(0.44, 0.6), Vector2(0.28, 0.56), Vector2(0.16, 0.46), Vector2(0.24, 0.34), Vector2(0.36, 0.3), Vector2(0.34, 0.18), Vector2(0.5, 0.1), Vector2(0.66, 0.18), Vector2(0.64, 0.3), Vector2(0.76, 0.34), Vector2(0.84, 0.46), Vector2(0.72, 0.56), Vector2(0.56, 0.6), Vector2(0.56, 0.88)]},
	{"name": "рука с пальцами", "pts": [Vector2(0.28, 0.88), Vector2(0.24, 0.62), Vector2(0.16, 0.44), Vector2(0.22, 0.36), Vector2(0.3, 0.46), Vector2(0.32, 0.26), Vector2(0.4, 0.2), Vector2(0.44, 0.36), Vector2(0.5, 0.18), Vector2(0.58, 0.22), Vector2(0.58, 0.4), Vector2(0.66, 0.28), Vector2(0.72, 0.36), Vector2(0.7, 0.56), Vector2(0.66, 0.88)]},
	{"name": "маска", "pts": [Vector2(0.24, 0.3), Vector2(0.4, 0.2), Vector2(0.6, 0.2), Vector2(0.76, 0.3), Vector2(0.8, 0.5), Vector2(0.72, 0.66), Vector2(0.6, 0.78), Vector2(0.5, 0.86), Vector2(0.4, 0.78), Vector2(0.28, 0.66), Vector2(0.2, 0.5), Vector2(0.32, 0.44), Vector2(0.42, 0.5), Vector2(0.58, 0.5), Vector2(0.68, 0.44)]},
	{"name": "лестница", "pts": [Vector2(0.32, 0.9), Vector2(0.32, 0.12), Vector2(0.68, 0.12), Vector2(0.68, 0.9), Vector2(0.68, 0.74), Vector2(0.32, 0.74), Vector2(0.32, 0.58), Vector2(0.68, 0.58), Vector2(0.68, 0.42), Vector2(0.32, 0.42), Vector2(0.32, 0.26), Vector2(0.68, 0.26), Vector2(0.5, 0.26), Vector2(0.5, 0.9)]},
	{"name": "песочные часы", "pts": [Vector2(0.2, 0.1), Vector2(0.8, 0.1), Vector2(0.7, 0.26), Vector2(0.58, 0.4), Vector2(0.5, 0.5), Vector2(0.58, 0.62), Vector2(0.7, 0.76), Vector2(0.8, 0.9), Vector2(0.2, 0.9), Vector2(0.3, 0.76), Vector2(0.42, 0.62), Vector2(0.34, 0.5), Vector2(0.42, 0.4), Vector2(0.3, 0.26)]},
	{"name": "рыба большая", "pts": [Vector2(0.14, 0.5), Vector2(0.28, 0.32), Vector2(0.44, 0.26), Vector2(0.6, 0.3), Vector2(0.72, 0.4), Vector2(0.82, 0.3), Vector2(0.88, 0.5), Vector2(0.82, 0.7), Vector2(0.72, 0.6), Vector2(0.6, 0.7), Vector2(0.44, 0.74), Vector2(0.28, 0.68), Vector2(0.2, 0.6), Vector2(0.36, 0.5)]},
]

## Правила привязаны к НОМЕРУ полотна, а не к фигуре: эскалация обучения — замысел.
##   no_nums — номерков нет, порядок читается по яркости точек
##   lamp    — полотно в темноте, светит пятно вокруг курсора
##   drift   — точки медленно плывут
const MODS := [[], [], ["no_nums"], ["lamp"], ["drift"], ["no_nums", "drift"]]
const MOD_NAME := {"no_nums": "НОМЕРКОВ НЕТ", "lamp": "ПОЛОТНО В ТЕМНОТЕ", "drift": "ТОЧКИ ПЛЫВУТ"}

## Дверь для финала. Форма фиксированная: она обязана читаться как дверь.
## Выхода нет — есть стена, и дверь надо нарисовать. Тем самым действием,
## которым игрок занимался всю игру.
## ПОСЛЕДНИЙ РИСУНОК — не дверь, а ОНО САМО, на 25 точек.
## Дверь на десять точек была слишком лёгкой: времени полно, форма простая.
## А главное — так финал становится честнее: чтобы выйти, надо дорисовать
## то, от чего ты бежал. Оно стоит у тебя за спиной, пока ты выводишь его контур.
const DOOR := {"name": "оно", "pts": [Vector2(0.5, 0.06), Vector2(0.58, 0.12), Vector2(0.62, 0.2), Vector2(0.7, 0.18), Vector2(0.78, 0.24), Vector2(0.74, 0.34), Vector2(0.82, 0.4), Vector2(0.76, 0.5), Vector2(0.84, 0.58), Vector2(0.74, 0.64), Vector2(0.78, 0.76), Vector2(0.66, 0.74), Vector2(0.62, 0.86), Vector2(0.5, 0.78), Vector2(0.38, 0.86), Vector2(0.34, 0.74), Vector2(0.22, 0.76), Vector2(0.26, 0.64), Vector2(0.16, 0.58), Vector2(0.24, 0.5), Vector2(0.18, 0.4), Vector2(0.26, 0.34), Vector2(0.22, 0.24), Vector2(0.3, 0.18), Vector2(0.38, 0.12)]}

## РЕАЛЬНЫЙ запас времени — то, что игрок ощущает. Базовый таймер считается из него,
## потому что каждая соединённая точка съедает DOT_TIME_COST. Крутить надо эти числа.
const TIME_NET := [25.0, 20.0, 18.0, 15.0, 15.0, 15.0]
const DOT_TIME_COST := 2.0
const N_CANV := 6
const PALETTE := [Color("39FF9E"), Color("4FD8FF"), Color("FF5FA8")]
const FEAR_STEP := 0.6      ## прибавка к дрожи за каждый провал
const FEAR_MAX := 3.0       ## потолок: выше рисовать физически невозможно
const DISSOLVE_T := 1.15    ## сколько секунд осыпается проваленный рисунок


## Шесть фигур на забег, по возрастанию числа точек.
static func pick(rng: RandomNumberGenerator) -> Array:
	var pool := POOL.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = pool[i]; pool[i] = pool[j]; pool[j] = t
	# Друг сказал: десять точек — мало. Пул теперь разношёрстный (8–16 точек),
	# и шесть фигур на забег берутся ПО ВОЗРАСТАЮЩЕЙ СЛОЖНОСТИ: сначала мелкие,
	# к концу крупные. Просто взять шесть подряд нельзя — выпал бы забег
	# из одних мелких или из одних огромных.
	pool.sort_custom(func(a, b): return a["pts"].size() < b["pts"].size())
	var six := []
	for k in N_CANV:
		var lo: int = int(float(k) * pool.size() / float(N_CANV))
		var hi: int = int(float(k + 1) * pool.size() / float(N_CANV)) - 1
		six.append(pool[lo + rng.randi() % maxi(1, hi - lo + 1)])
	return six


## Таймер полотна = чистый запас + по DOT_TIME_COST на каждую точку фигуры.
static func time_for(index: int, shape: Dictionary) -> float:
	return TIME_NET[index] + shape["pts"].size() * DOT_TIME_COST
