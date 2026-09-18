extends Control
## Благодарности. Люди выложили работу бесплатно — назвать их имя стоит ноль.
##
## Экран нужен не только из вежливости: лицензии CC-BY и OGA-BY РАЗРЕШАЮТ брать
## что угодно, но требуют указать автора. Пока экрана не было, такие паки
## приходилось обходить стороной, и выбор сужался в разы.
##
## Список ведётся здесь и в sfx/ИСТОЧНИК.txt. Добавил запись — впиши сюда, иначе
## титры разъедутся с тем, что лежит в папке.

const Lang := preload("res://Lang.gd")
const UI := preload("res://UI.gd")

signal closed



## [автор, работа, лицензия, где звучит]
const ENTRIES := [
	["rubberduck", "25 CC0 mud sfx", "CC0", "шаги по мокрому"],
	["rubberduck", "40 CC0 water / splash / slime SFX", "CC0", "течение из проломов"],
	["rubberduck", "80 CC0 creature SFX", "CC0", "дыхание"],
	["AntumDeluge", "Scrapes", "CC0", "скрёб и шорох в камне"],
	["bart", "Heartbeat sounds", "CC0", "сердце"],
	["qubodup", "Impact", "CC0", "удар при поимке"],
	["qubodup", "15 vocal male strain/hurt/pain sounds", "CC0", "голос игрока"],
	["ambientCG", "Fabric045, Fabric062, Wood066, WoodFloor043, Plaster001",
		"CC0", "ткань, дерево, пол и стены детской"],
	["Poly Haven", "old_bed_frame, painted_wooden_nightstand, throw_pillows_01",
		"CC0", "кровать, тумбочка и подушка в детской"],
	["Quaternius", "Man in Long Sleeves", "CC0", "вторая форма монстра"],
	["Nicole Marie T", "CC0 Deep Monster Roar", "CC0", "рык фигуры"],
	["Will Leamon", "Fleshy Fight Sounds", "OGA-BY 3.0", "удар при поимке"],
]

const TAIL := ["cred_cc0", "cred_by", "", "cred_rest1", "cred_rest2"]

var _back: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_back = Button.new()
	_back.text = Lang.t("back")
	_back.custom_minimum_size = Vector2(160, 38)
	_back.add_theme_font_size_override("font_size", 15)
	_back.add_theme_color_override("font_color", Color(0.74, 0.73, 0.70))
	_back.add_theme_color_override("font_hover_color", Color(0.95, 0.94, 0.90))
	_back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_back.pressed.connect(_on_back)
	add_child(_back)
	set_process(false)


func open() -> void:
	visible = true
	set_process(true)
	queue_redraw()


func _on_back() -> void:
	visible = false
	set_process(false)
	closed.emit()


func _process(_delta: float) -> void:
	size = get_viewport().get_visible_rect().size
	_back.position = Vector2((size.x - _back.size.x) * 0.5, size.y - 62.0)


func _draw() -> void:
	var f := UI.text(400)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.012, 0.02))
	var y: float = maxf(56.0, size.y * 0.10)
	draw_string(f, Vector2(0, y), Lang.t("credits"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 28,
		Color(0.84, 0.83, 0.79))
	y += 30.0
	draw_string(f, Vector2(0, y), Lang.t("cred_intro"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13,
		Color(0.42, 0.41, 0.39))

	# Три колонки: автор, работа, лицензия. Так глаз находит нужное строкой.
	y += 44.0
	var col := size.x * 0.5
	for e in ENTRIES:
		draw_string(f, Vector2(col - 330.0, y), str(e[0]), HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 14,
			Color(0.22, 1.0, 0.62))
		draw_string(f, Vector2(col - 168.0, y), str(e[1]), HORIZONTAL_ALIGNMENT_LEFT, 300.0, 14,
			Color(0.76, 0.75, 0.72))
		draw_string(f, Vector2(col + 144.0, y), str(e[2]), HORIZONTAL_ALIGNMENT_LEFT, 80.0, 14,
			Color(0.55, 0.54, 0.52))
		draw_string(f, Vector2(col + 210.0, y), str(e[3]), HORIZONTAL_ALIGNMENT_LEFT, 220.0, 13,
			Color(0.42, 0.41, 0.39))
		y += 24.0

	y += 34.0
	for k in TAIL:
		if k == "":
			y += 8.0
			continue
		draw_string(f, Vector2(0, y), Lang.t(str(k)), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13,
			Color(0.55, 0.54, 0.52))
		y += 20.0
