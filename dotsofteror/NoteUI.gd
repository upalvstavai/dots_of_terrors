extends Control
## Лист записки и дневник. Одно и то же окно в двух режимах.

const Notes := preload("res://Notes.gd")
const Lang := preload("res://Lang.gd")

signal closed

var text: String = ""
var journal: Array = []
var mode: String = "note"      ## "note" или "journal"
var t: float = 0.0
var paper: Texture2D = load("res://tex/paper_color.jpg")


## С рождения узел НЕ СЧИТАЕТ. Godot включает _process всем, у кого есть такой
## метод, — и записка тикала с первого кадра игры, задолго до того, как его
## открывали. У записки из-за этого таймер уходил в ноль сам собой: полотно объявляло
## себя проваленным на второй секунде, закрывалось и ЗАБИРАЛО КУРСОР — на
## стартовом экране пропадала стрелка, и нажать «проснуться» было нечем.
func _ready() -> void:
	set_process(false)


func show_note(note_text: String) -> void:
	mode = "note"
	text = note_text
	t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func show_journal(list: Array) -> void:
	mode = "journal"
	journal = list
	# Блокнот тоже РАСКРЫВАЕТСЯ, а не появляется готовым. Раньше t сразу ставился
	# в единицу, и дневник возникал щелчком — как окно настроек, а не как вещь,
	# которую достали из кармана.
	t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)
	closed.emit()


func _process(delta: float) -> void:
	if t < 1.0:
		t = minf(1.0, t + delta / 0.22)     # лист разворачивается
		queue_redraw()


func _draw() -> void:
	if mode == "journal":
		_draw_journal()
	else:
		_draw_note()


func _draw_note() -> void:
	var e: float = t * t * (3.0 - 2.0 * t)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.008, 0.016, e * 0.82))
	var w: float = minf(size.x * 0.5, 520.0) * e
	var h: float = minf(size.y * 0.62, 660.0) * e
	var r := Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)
	_draw_sheet(r, e)
	if t < 1.0:
		return
	var f := ThemeDB.fallback_font
	var fs: int = int(clampf(w / 17.0, 15.0, 24.0))
	draw_string(f, Vector2(r.position.x + w * 0.11, r.position.y + h * 0.45), text,
		HORIZONTAL_ALIGNMENT_CENTER, w * 0.78, fs, Color(0.106, 0.102, 0.094))
	draw_string(f, Vector2(r.position.x, r.position.y + h - 26.0), Lang.t("close_note"),
		HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.35, 0.34, 0.31, 0.75))


## Лист бумаги: фактура вместо ровной заливки. Смятая бумага под тусклым светом
## — это половина ощущения «я нашёл чью-то записку», а ровный прямоугольник
## читается как окно интерфейса.
func _draw_sheet(r: Rect2, a: float) -> void:
	if paper != null:
		draw_texture_rect(paper, r, false, Color(1.02, 1.0, 0.94, a))
	else:
		draw_rect(r, Color(0.925, 0.91, 0.86, a))
	# Тень по краю: лист лежит НА чём-то, а не наклеен на экран.
	draw_rect(r, Color(0.30, 0.28, 0.25, a * 0.55), false, 2.0)


## Ненайденное показано прочерками: игрок видит не только что собрал, но и сколько
## упустил. Это единственная причина свернуть в комнату на следующем забеге.
func _draw_journal() -> void:
	var e: float = t * t * (3.0 - 2.0 * t)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.008, 0.016, e * 0.93))
	# РАЗВОРОТ: две страницы расходятся от середины. Ширина растёт, высота нет —
	# так книга и открывается, а равномерное увеличение читалось бы как зум.
	var w: float = minf(size.x * 0.78, 900.0)
	var h: float = minf(size.y * 0.74, 700.0)
	var half: float = w * 0.5 * e
	var cx: float = size.x * 0.5
	var y0: float = (size.y - h) * 0.5
	_draw_sheet(Rect2(cx - half, y0, half, h), e)
	_draw_sheet(Rect2(cx, y0, half, h), e)
	# Корешок: тень в сгибе, иначе две страницы читаются как один лист.
	draw_rect(Rect2(cx - 3.0, y0, 6.0, h), Color(0.16, 0.14, 0.12, e * 0.8))
	if t < 1.0:
		return
	# Вся вёрстка считается ОТ РАЗВОРОТА, а не от экрана. Иначе заголовок и
	# подсказка висят за краем бумаги, светлые по чёрному, — и разворот
	# перестаёт быть вещью, становится подложкой под интерфейс.
	var f := ThemeDB.fallback_font
	var total := Notes.total()
	var x0: float = cx - w * 0.5
	draw_string(f, Vector2(x0, y0 + 42.0), Lang.t("notes"),
		HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(0.13, 0.12, 0.10, 0.95))
	var col := Color(0.10, 0.42, 0.24) if journal.size() >= total else Color(0.34, 0.31, 0.27, 0.9)
	draw_string(f, Vector2(x0, y0 + 66.0), Lang.t("found") % [journal.size(), total],
		HORIZONTAL_ALIGNMENT_CENTER, w, 13, col)
	var top: float = y0 + 104.0
	var lh: float = minf(34.0, (h - 150.0) / float(total))
	var fs: int = int(clampf(lh * 0.55, 13.0, 18.0))
	for i in total:
		var y := top + i * lh
		if i < journal.size():
			draw_string(f, Vector2(x0, y), "«%s»" % journal[i],
				HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.14, 0.13, 0.11, 0.92))
		else:
			draw_string(f, Vector2(x0, y), "— — — — — — —",
				HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.47, 0.45, 0.41, 0.45))
	draw_string(f, Vector2(x0, y0 + h - 22.0), Lang.t("close_journal"),
		HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.35, 0.34, 0.31, 0.8))
