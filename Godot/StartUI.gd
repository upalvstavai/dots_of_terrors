extends Control
## ТОЧКИ УЖАСА — стартовый экран.
##
## В браузерной версии он был, при переносе я его потерял, и игра стала
## запускаться прямо в тёмный коридор без единой подсказки. Человек, который
## не знает, что палочка лежит СЗАДИ, проводит первые минуты в полной темноте
## и решает, что игра сломана.
##
## Здесь нет ничего лишнего: только то, без чего не сыграть. Всё остальное
## игра должна рассказать сама — звуком, светом и тем, что с тобой делают.

const Settings := preload("res://Settings.gd")
const Lang := preload("res://Lang.gd")

signal started
signal credits
signal viewer

## Тексты живут в Lang.gd. Здесь только КЛЮЧИ и раскладка — чтобы правка
## формулировки не требовала лезть в разметку экрана.
const KEY_ROWS := [
	["W A S D", "k_move"],
	["", "k_look"],
	["", "k_dash"],
	["F", "k_flash"],
	["E", "k_read"],
	["J", "k_journal"],
	["G", "k_thread"],
	["Q", "k_turn"],
	["ESC", "k_pause"],
	["R", "k_restart"],
]
const RULE_KEYS := ["r1", "r2", "r3", "r4", "r5", "r6", "", "r7", "r8", "", "r9"]


## Переживает перезагрузку сцены: после трёх поимок правила уже прочитаны,
## и заставлять читать их снова на пятой смерти — это наказание, а не подсказка.
static var seen: bool = false

var _t: float = 0.0
var _btn: Button
var _quit: Button
var _cred: Button
var _view: Button
var _lang: Button
var _slider: HSlider


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, а не IGNORE: экран обязан ПЕРЕХВАТЫВАТЬ мышь, иначе щелчки уходят
	# в игру под ним — можно было крутить камеру и брать палочку сквозь заставку.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Подложку рисуем в _draw, а НЕ отдельным ColorRect: Control рисует сначала
	# себя, потом детей, — узел-подложка закрыл бы собственный текст экрана.
	_btn = Button.new()
	_btn.text = Lang.t("wake")
	_btn.custom_minimum_size = Vector2(230, 46)
	_btn.add_theme_font_size_override("font_size", 18)
	_btn.add_theme_color_override("font_color", Color(0.88, 0.31, 0.26))
	_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.38))
	# TOP_LEFT, потому что позицию задаём вручную в _process: пресет с якорями
	# внизу-по-центру каждый кадр спорил бы с ручной позицией.
	_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn.pressed.connect(_go)
	add_child(_btn)
	# Громкость ставят ДО игры, а не когда уже страшно и лезть в меню некогда.
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = Settings.volume
	_slider.custom_minimum_size = Vector2(230, 18)
	_slider.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_slider.value_changed.connect(func(v: float) -> void: Settings.set_volume(v))
	add_child(_slider)
	_quit = Button.new()
	_quit.text = Lang.t("quit")
	_quit.custom_minimum_size = Vector2(96, 28)
	_quit.add_theme_font_size_override("font_size", 13)
	_quit.add_theme_color_override("font_color", Color(0.45, 0.44, 0.42))
	_quit.add_theme_color_override("font_hover_color", Color(0.80, 0.79, 0.76))
	_quit.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_quit.pressed.connect(func() -> void: get_tree().quit())
	add_child(_quit)
	_cred = Button.new()
	_cred.text = Lang.t("credits")
	_cred.custom_minimum_size = Vector2(168, 28)
	_cred.add_theme_font_size_override("font_size", 13)
	_cred.add_theme_color_override("font_color", Color(0.45, 0.44, 0.42))
	_cred.add_theme_color_override("font_hover_color", Color(0.80, 0.79, 0.76))
	_cred.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cred.pressed.connect(func() -> void: credits.emit())
	add_child(_cred)
	# СМОТРОВАЯ. Отдельная комната, где монстром можно управлять кнопками.
	# Это инструмент, а не часть игры, и В СОБРАННОЙ ИГРЕ ЭТОЙ КНОПКИ НЕТ:
	# решает Settings.creator_tools(), а не моя память — см. комментарий там.
	if Settings.creator_tools():
		_make_viewer_btn()
	# Переключатель языка на самом видном экране. Если издатель не может прочесть
	# первую страницу, дальше он не пойдёт.
	_lang = Button.new()
	_lang.text = Lang.t("lang_name")
	# ЗАМЕТНАЯ. Тёмно-серая надпись «РУССКИЙ» в углу читалась как подпись, а не
	# как кнопка: её просто не находили и просили добавить то, что уже есть.
	_lang.custom_minimum_size = Vector2(250, 30)
	_lang.add_theme_font_size_override("font_size", 14)
	_lang.add_theme_color_override("font_color", Color(0.78, 0.77, 0.74))
	_lang.add_theme_color_override("font_hover_color", Color(0.98, 0.97, 0.94))
	_lang.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lang.pressed.connect(_on_lang)
	add_child(_lang)
	set_process(true)


func _make_viewer_btn() -> void:
	_view = Button.new()
	_view.text = Lang.t("viewer")
	_view.custom_minimum_size = Vector2(130, 28)
	_view.add_theme_font_size_override("font_size", 13)
	_view.add_theme_color_override("font_color", Color(0.38, 0.42, 0.40))
	_view.add_theme_color_override("font_hover_color", Color(0.55, 0.90, 0.70))
	_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_view.pressed.connect(func() -> void: viewer.emit())
	add_child(_view)


func _process(delta: float) -> void:
	_t += delta
	# Размер берём у окна прямо: экран обязан закрывать мир целиком при любом
	# разрешении и после разворота на весь экран.
	size = get_viewport().get_visible_rect().size
	if _btn != null:
		_btn.position = Vector2((size.x - _btn.size.x) * 0.5, size.y - 78.0)
		# Ползунок в пустой правый верхний угол, а не под текст: снизу он лёг
		# прямо поверх правил — видел это на снятом из игры кадре.
		_slider.position = Vector2(size.x - _slider.size.x - 28.0, 52.0)
		_quit.position = Vector2(size.x - _quit.size.x - 24.0, size.y - 44.0)
		_cred.position = Vector2(24.0, size.y - 44.0)
		if _view != null:
			_view.position = Vector2(200.0, size.y - 44.0)
		_lang.position = Vector2(24.0, 24.0)
	queue_redraw()


## Только кнопка. «Любая клавиша» плоха тем, что игра начинается от случайного
## нажатия, пока человек ещё читает управление, — а читать там есть что.
func _on_lang() -> void:
	Lang.toggle()
	_lang.text = Lang.t("lang_name")
	_btn.text = Lang.t("wake")
	_quit.text = Lang.t("quit")
	_cred.text = Lang.t("credits")
	if _view != null:
		_view.text = Lang.t("viewer")
	queue_redraw()


func _go() -> void:
	seen = true
	skip()
	started.emit()


## Спрятать без запуска: экран не нужен, но и тратить кадры на перерисовку
## невидимого узла незачем.
func skip() -> void:
	visible = false
	set_process(false)


func _draw() -> void:
	var f := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.012, 0.02))

	var y: float = maxf(50.0, size.y * 0.09)
	draw_string(f, Vector2(0, y), Lang.t("title"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 40,
		Color(0.85, 0.84, 0.80))
	y += 26.0
	draw_string(f, Vector2(0, y), Lang.t("sub"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13,
		Color(0.30, 0.48, 0.39))

	y += 42.0
	for k in ["intro1", "intro2", "intro3"]:
		draw_string(f, Vector2(0, y), Lang.t(k), HORIZONTAL_ALIGNMENT_CENTER, size.x, 15,
			Color(0.76, 0.75, 0.72))
		y += 20.0

	# Две колонки: клавиша и что делает. Так глаз находит нужное, не читая всё.
	y += 12.0
	var col := size.x * 0.5
	for pair in KEY_ROWS:
		var cap: String = str(pair[0])
		if cap == "":
			cap = Lang.t("k_mouse") if pair[1] == "k_look" else Lang.t("k_space")
		draw_string(f, Vector2(col - 320.0, y), cap, HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 15,
			Color(0.22, 1.0, 0.62))
		draw_string(f, Vector2(col + 16.0, y), Lang.t(str(pair[1])), HORIZONTAL_ALIGNMENT_LEFT, 320.0, 15,
			Color(0.70, 0.69, 0.66))
		y += 18.0

	y += 12.0
	for k in RULE_KEYS:
		if k == "":
			y += 8.0
			continue
		draw_string(f, Vector2(0, y), Lang.t(str(k)), HORIZONTAL_ALIGNMENT_CENTER, size.x, 14,
			Color(0.62, 0.61, 0.58))
		y += 17.0

	if _slider != null:
		var pct := str(int(round(Settings.volume * 100.0))) + "%"
		draw_string(f, Vector2(_slider.position.x, _slider.position.y - 8.0), Lang.t("volume"),
			HORIZONTAL_ALIGNMENT_LEFT, 230.0, 13, Color(0.22, 1.0, 0.62))
		draw_string(f, Vector2(_slider.position.x, _slider.position.y - 8.0), pct,
			HORIZONTAL_ALIGNMENT_RIGHT, 230.0, 13, Color(0.62, 0.61, 0.58))

	# Рамка вокруг кнопки, пульсирует — чтобы её было видно среди текста
	if _btn != null:
		var a: float = 0.35 + 0.35 * sin(_t * 2.4)
		draw_rect(Rect2(_btn.position - Vector2(3, 3), _btn.size + Vector2(6, 6)),
			Color(0.85, 0.30, 0.26, a), false, 1.5)
