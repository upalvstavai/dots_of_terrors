extends RefCounted
## Записки и дневник. Перенос из HTML (NOTES / journal / openNote).
##
## Раньше на всех столах лежала одна фраза — второй стол уже ничего не добавлял.
## Теперь каждая своя, и они складываются в историю, не рассказывая её: существо
## не отсюда, кто-то его разозлил, кого-то обманули, и ему нужен КТО-ТО конкретный.
## Прямо не сказано ничего — догадка остаётся за игроком.
##
## Порядок случайный: игрок собирает чужие обрывки не по порядку, хронология тут
## была бы ложью.

const PHRASES := [
	"это существо не из нашего мира",
	"не доверяй ему",
	"он бог",
	"мы его разозлили и он нам мстит",
	"меня обманули",
	"ему нужен он",
	"никому не доверяй",
]

## На этих двух держится вся вторая часть, поэтому они кладутся в первую очередь —
## в те комнаты, что ближе к дороге игрока.
const KEY := ["не доверяй ему", "никому не доверяй", "ему нужен он"]

const START_NOTE := "Я не могу себя долго контролировать"
const SAVE_PATH := "user://journal.json"


## Дневник копится МЕЖДУ забегами. Столы стоят в стороне от дороги, за один заход
## игрок читает две-три записки из восьми, а лабиринт каждый раз новый — вернуться
## к прочитанному нельзя. Без накопления лор просто не собирается в голове.
static func load_journal() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return []
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return []
	var raw := f.get_as_text()
	f.close()
	var data = JSON.parse_string(raw)
	if data is Array:
		return data
	return []


static func save_journal(list: Array) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(list))
	f.close()


static func total() -> int:
	return PHRASES.size() + 1      # семь на столах плюс стартовая


## Порядок раскладки: ключевые фразы первыми, остальные вперемешку.
static func order(rng: RandomNumberGenerator) -> Array:
	var rest := []
	for p in PHRASES:
		if not KEY.has(p):
			rest.append(p)
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = rest[i]
		rest[i] = rest[j]
		rest[j] = t
	var out := KEY.duplicate()
	out.append_array(rest)
	return out
