extends Control
## Лист записки и дневник. Одно и то же окно в двух режимах.

const Notes := preload("res://Notes.gd")

signal closed

var text: String = ""
var journal: Array = []
var mode: String = "note"      ## "note" или "journal"
var t: float = 0.0


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
	t = 1.0
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
	draw_rect(r, Color(0.925, 0.91, 0.86, e))
	draw_rect(r, Color(0.47, 0.45, 0.41, e * 0.5), false, 1.0)
	if t < 1.0:
		return
	var f := ThemeDB.fallback_font
	var fs: int = int(clampf(w / 17.0, 15.0, 24.0))
	draw_string(f, Vector2(r.position.x + w * 0.11, r.position.y + h * 0.45), text,
		HORIZONTAL_ALIGNMENT_CENTER, w * 0.78, fs, Color(0.106, 0.102, 0.094))
	draw_string(f, Vector2(r.position.x, r.position.y + h - 26.0), "E — убрать",
		HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.35, 0.34, 0.31, 0.75))


## Ненайденное показано прочерками: игрок видит не только что собрал, но и сколько
## упустил. Это единственная причина свернуть в комнату на следующем забеге.
func _draw_journal() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.008, 0.016, 0.93))
	var f := ThemeDB.fallback_font
	var total := Notes.total()
	draw_string(f, Vector2(0, maxf(58.0, size.y * 0.12)), "ЗАПИСКИ",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(0.925, 0.91, 0.86, 0.92))
	var col := Color(0.22, 1.0, 0.62) if journal.size() >= total else Color(0.48, 0.66, 0.56, 0.9)
	draw_string(f, Vector2(0, maxf(80.0, size.y * 0.12 + 24.0)),
		"НАЙДЕНО %d ИЗ %d" % [journal.size(), total],
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, col)
	var top: float = maxf(112.0, size.y * 0.12 + 56.0)
	var lh: float = minf(34.0, (size.y - top - 60.0) / total)
	var fs: int = int(clampf(lh * 0.55, 13.0, 18.0))
	for i in total:
		var y := top + i * lh
		if i < journal.size():
			draw_string(f, Vector2(0, y), "«%s»" % journal[i],
				HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0.925, 0.91, 0.86, 0.88))
		else:
			draw_string(f, Vector2(0, y), "— — — — — — —",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0.47, 0.45, 0.41, 0.45))
	draw_string(f, Vector2(0, size.y - 28.0), "J или Esc — закрыть",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(0.35, 0.34, 0.31, 0.8))
