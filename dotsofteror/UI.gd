extends RefCounted
## ОДНА ТИПОГРАФИКА НА ВСЮ ИГРУ.
##
## До сих пор каждый экран рисовал себя сам: шрифт по умолчанию, свои размеры,
## свои цвета — и потому игра выглядела не строго, а никак. Играющий сказал
## прямо: «интерфейс нищий, а ведь это первое, что цепляет игрока».
##
## Здесь лежат ровно две вещи, из которых собирается весь интерфейс: две
## гарнитуры и семь цветов. Экраны берут их отсюда и нигде не заводят своих —
## тогда правка одного цвета правит игру целиком, а не одно окно из шести.

const TITLE_TTF := preload("res://fonts/CormorantGaramond.ttf")
const TEXT_TTF := preload("res://fonts/Inter.ttf")

# ЦВЕТА. Игра тёмная, и палитра построена от черноты вверх, а не от белого вниз.
const GROUND := Color(0.035, 0.035, 0.045)   ## подложка экранов
const INK := Color(0.88, 0.87, 0.83)         ## основной текст
const DIM := Color(0.52, 0.51, 0.49)         ## второстепенный
const FAINT := Color(0.30, 0.30, 0.31)       ## почти фон: подписи, разделители
const ACCENT := Color(0.42, 0.84, 0.62)      ## клавиши и всё, что нажимают
const BLOOD := Color(0.76, 0.24, 0.20)       ## опасность и главное действие
const PAPER := Color(0.83, 0.78, 0.66)       ## «бумага»: записки и рисунки


## Начертание нужного веса. Шрифты переменные, и вес — это не отдельный файл,
## а ось внутри одного: FontVariation даёт с него любой.
static func text(weight: int = 400) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = TEXT_TTF
	f.variation_opentype = {"wght": weight}
	return f


static func title(weight: int = 500, spacing: int = 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = TITLE_TTF
	f.variation_opentype = {"wght": weight}
	# Разрядка задаётся здесь же: заголовок без неё читается абзацем, а не
	# именем игры.
	f.spacing_glyph = spacing
	return f


## Кнопка в стиле игры: без коробки, с тонкой рамкой, которая зажигается под
## курсором. Родная кнопка Godot — серый прямоугольник из другой программы.
static func button(text_s: String, size_px: int = 16, color: Color = INK,
		hot: Color = Color(1, 1, 1)) -> Button:
	var b := Button.new()
	b.text = text_s
	b.add_theme_font_override("font", text(500))
	b.add_theme_font_size_override("font_size", size_px)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", hot)
	b.add_theme_color_override("font_pressed_color", hot)
	b.add_theme_color_override("font_focus_color", color)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_content_margin_all(8.0)
	var over := flat.duplicate() as StyleBoxFlat
	over.bg_color = Color(1, 1, 1, 0.045)
	var down := flat.duplicate() as StyleBoxFlat
	down.bg_color = Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", over)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("focus", flat)
	b.focus_mode = Control.FOCUS_NONE
	return b


## Тонкая линейка-разделитель. Рисуется не полосой в цвете текста, а
## растворяющейся к краям: сплошная черта делит экран, а нам нужно связать.
static func rule(to: CanvasItem, at: Vector2, width: float, tint: Color = FAINT) -> void:
	var steps := 24
	for i in steps:
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var a: float = sin(t0 * PI)
		to.draw_line(at + Vector2(width * (t0 - 0.5), 0.0),
			at + Vector2(width * (t1 - 0.5), 0.0),
			Color(tint.r, tint.g, tint.b, tint.a * a), 1.0)
