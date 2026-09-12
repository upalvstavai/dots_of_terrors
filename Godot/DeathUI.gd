extends Control
## Экран смерти. Три поимки монстром — и лабиринт складывается заново.
##
## Кнопка НЕ «начать заново»: сданные полотна остаются при игроке, меняется
## только карта. Слово «заново» здесь врало бы ровно в ту сторону, из-за
## которой человек и закрывает игру, — «всё насмарку».
##
## Раньше об этом сообщала ОДНА строка в углу: скример догорал, экран
## возвращался в обычный вид, игрок молча переставал ходить. Со стороны это
## неотличимо от «игра сломалась» или «монстр перестал нападать» — именно так
## это и прочиталось при первой же проверке.

const Lang := preload("res://Lang.gd")

signal restarted

var _btn: Button
var _t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_btn = Button.new()
	_btn.text = Lang.t("d_back")
	_btn.custom_minimum_size = Vector2(240, 46)
	_btn.add_theme_font_size_override("font_size", 17)
	_btn.add_theme_color_override("font_color", Color(0.78, 0.26, 0.22))
	_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.42, 0.36))
	_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn.pressed.connect(_on_restart)
	add_child(_btn)
	set_process(false)


func open() -> void:
	_t = 0.0
	_btn.text = Lang.t("d_back")
	visible = true
	set_process(true)
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)


func _on_restart() -> void:
	restarted.emit()


func _process(delta: float) -> void:
	_t += delta
	size = get_viewport().get_visible_rect().size
	_btn.position = Vector2((size.x - _btn.size.x) * 0.5, size.y * 0.5 + 60.0)
	queue_redraw()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	# Наливается за полторы секунды, а не появляется щелчком: удар уже случился,
	# и экран должен догнать его, а не перебить.
	var a: float = clampf(_t / 1.5, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.004, 0.006, a * 0.94))
	if a < 0.35:
		return
	var k: float = (a - 0.35) / 0.65
	draw_string(f, Vector2(0, size.y * 0.5 - 40.0), Lang.t("d_title"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, Color(0.80, 0.22, 0.18, k))
	draw_string(f, Vector2(0, size.y * 0.5 - 4.0), Lang.t("d_sub"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(0.55, 0.32, 0.30, k * 0.9))
	draw_string(f, Vector2(0, size.y - 46.0), Lang.t("d_key"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(0.42, 0.30, 0.28, k * 0.8))
