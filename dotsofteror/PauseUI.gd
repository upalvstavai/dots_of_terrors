extends Control
## Пауза: громкость (общая, музыка, звуки), мышь, яркость, качество,
## управление, перезапуск, сброс дневника, выход.
##
## Все они одного рода: без них игру нельзя дать чужому человеку. У него другие
## колонки, другой экран, другая мышь и, может быть, геймпад — и каждый раз,
## когда что-то из этого не подошло, он решит, что игра такая.

const Settings := preload("res://Settings.gd")
const UI := preload("res://UI.gd")
const Lang := preload("res://Lang.gd")
const StartScript := preload("res://StartUI.gd")

signal resumed
signal restarted
signal wiped
signal quit_game
signal quality_changed
## Закрыли МЕНЮ НАСТРОЕК со стартового экрана — не паузу, а именно меню.
signal closed

const W := 340.0
const ROW := 40.0
const SLIDER_H := 18.0

## Ползунки: ключ настройки, подпись, границы и как показать значение.
const SLIDERS := [
	["volume", "volume", 0.0, 1.0, 0.01, "%"],
	["music", "music", 0.0, 1.0, 0.01, "%"],
	["sounds", "sounds", 0.0, 1.0, 0.01, "%"],
	["mouse", "sens", 0.25, 3.0, 0.05, "x"],
	["gamma", "gamma", 0.6, 1.6, 0.05, "x"],
]

var _sl: Dictionary = {}          ## ключ -> HSlider
var _rows: Array = []             ## кнопки главной страницы
var _wipe_btn: Button
var _wiped: bool = false
var _qbtn: Button
var _fbtn: Button                 ## полный экран
var _lbtn: Button                 ## язык
var _cbtn: Button                 ## управление
var _hbtn: Button                 ## как играть
## ЭТО МЕНЮ, А НЕ ПАУЗА. Играющий (18.09): «сделай отдельное меню настроек в
## начале игры, снеси всё туда». Настройки жили в паузе, а на стартовом экране
## торчали только громкость и язык. Теперь одна и та же страница открывается
## и оттуда, и из паузы — только в меню нет «продолжить», «заново» и «выйти».
var menu_mode: bool = false
var _pause_only: Array = []       ## кнопки, которых в меню настроек нет
var _menu_back: Button
## Пока крутят яркость, ЗАТЕМНЕНИЕ ПАУЗЫ РАСХОДИТСЯ. Иначе настройка бессмысленна:
## мир под меню закрыт заливкой на 88%, и по нему нельзя судить, стало ли видно.
var _gam_t: float = 0.0
## 0 — главная страница, 1 — управление.
var _page: int = 0
var _keys: Array = []             ## кнопки страницы управления
var _bind: String = ""            ## какое действие ждёт клавишу
var _back_btn: Button
var _reset_btn: Button
## Где кончились кнопки управления: подсказку про геймпад рисуем ПОД ними, а не
## по числу на глаз — иначе она наезжает на «назад», как и наехала.
var _hint_y: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	for row in SLIDERS:
		var s := HSlider.new()
		s.min_value = float(row[2])
		s.max_value = float(row[3])
		s.step = float(row[4])
		s.custom_minimum_size = Vector2(W, SLIDER_H)
		var key: String = str(row[0])
		s.value_changed.connect(func(v: float) -> void: _on_slider(key, v))
		add_child(s)
		_sl[key] = s
	_qbtn = _add_btn(_quality_text(), _on_quality)
	_fbtn = _add_btn(_full_text(), _on_full)
	_lbtn = _add_btn(Lang.t("lang_name"), _on_lang)
	_cbtn = _add_btn(Lang.t("controls"), func() -> void: _go(1))
	# КАК ИГРАТЬ. Клавиши и правила стояли на главном экране — теперь здесь.
	_hbtn = _add_btn(Lang.t("howto"), func() -> void: _go(2))
	_pause_only.append(_add_btn(Lang.t("resume"), _on_resume))
	_pause_only.append(_add_btn(Lang.t("restart"), _on_restart))
	_wipe_btn = _add_btn(Lang.t("wipe"), _on_wipe)
	_pause_only.append(_wipe_btn)
	_pause_only.append(_add_btn(Lang.t("quit_game"), _on_quit))
	_menu_back = _add_btn(Lang.t("bind_back"), _on_resume)
	# Страница управления: по кнопке на действие, плюс сброс и возврат.
	for a in Settings.BIND_ACTIONS:
		var act: String = str(a)
		var b := _mk_btn("")
		b.pressed.connect(func() -> void: _start_bind(act))
		_keys.append({"act": act, "btn": b})
	_reset_btn = _mk_btn(Lang.t("bind_reset"))
	_reset_btn.pressed.connect(_on_reset_binds)
	_back_btn = _mk_btn(Lang.t("bind_back"))
	_back_btn.pressed.connect(func() -> void: _go(0))
	set_process(false)


func _mk_btn(text: String) -> Button:
	# ТА ЖЕ КНОПКА, ЧТО НА СТАРТОВОМ ЭКРАНЕ. Здесь стояли родные кнопки Godot —
	# серые коробки из другой программы, — и пауза выглядела служебным окном
	# поверх игры, а не её частью.
	var b := UI.button(text, 14, UI.INK, Color(1, 1, 1))
	b.custom_minimum_size = Vector2(W, 30)
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.visible = false
	add_child(b)
	return b


func _add_btn(text: String, fn: Callable) -> Button:
	var b := _mk_btn(text)
	b.custom_minimum_size = Vector2(W, 32)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(fn)
	_rows.append(b)
	return b


func _quality_text() -> String:
	return Lang.t("quality") + ": " + Lang.t("q%d" % Settings.quality)


func _full_text() -> String:
	return Lang.t("full_on") if Settings.is_fullscreen() else Lang.t("full_off")


func _on_full() -> void:
	Settings.toggle_fullscreen()
	_fbtn.text = _full_text()
	queue_redraw()


## Язык меняем здесь же, и все подписи страницы — сразу: иначе половина меню
## осталась бы на старом языке до перезапуска.
func _on_lang() -> void:
	Lang.toggle()
	_relabel()


func _relabel() -> void:
	_qbtn.text = _quality_text()
	_fbtn.text = _full_text()
	_lbtn.text = Lang.t("lang_name")
	_cbtn.text = Lang.t("controls")
	_hbtn.text = Lang.t("howto")
	(_pause_only[0] as Button).text = Lang.t("resume")
	(_pause_only[1] as Button).text = Lang.t("restart")
	_wipe_btn.text = Lang.t("wipe")
	(_pause_only[3] as Button).text = Lang.t("quit_game")
	_menu_back.text = Lang.t("bind_back")
	_reset_btn.text = Lang.t("bind_reset")
	_back_btn.text = Lang.t("bind_back")
	queue_redraw()


## Открыть как МЕНЮ НАСТРОЕК со стартового экрана.
func open_menu() -> void:
	menu_mode = true
	if not visible:
		_open()


func toggle() -> void:
	if visible:
		_on_resume()
	else:
		_open()


func _open() -> void:
	_relabel()
	_wiped = false
	_bind = ""
	_page = 0
	_pull()
	_gam_t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


## Затянуть в ползунки то, что сейчас в настройках.
func _pull() -> void:
	_sl["volume"].value = Settings.volume
	_sl["music"].value = Settings.music
	_sl["sounds"].value = Settings.sounds
	_sl["mouse"].value = Settings.mouse
	_sl["gamma"].value = Settings.gamma


func _go(page: int) -> void:
	_page = page
	_bind = ""
	queue_redraw()


func _process(delta: float) -> void:
	if _gam_t > 0.0:
		_gam_t = maxf(0.0, _gam_t - delta)
		queue_redraw()
	size = get_viewport().get_visible_rect().size
	var x: float = (size.x - W) * 0.5
	var main: bool = _page == 0
	for s in _sl.values():
		(s as HSlider).visible = main
	for b in _rows:
		var show: bool = main
		if menu_mode and _pause_only.has(b):
			show = false
		if not menu_mode and b == _menu_back:
			show = false
		(b as Button).visible = show
	for k in _keys:
		(k["btn"] as Button).visible = _page == 1
	_reset_btn.visible = _page == 1
	_back_btn.visible = not main
	if _page == 2:
		_back_btn.position = Vector2(x, size.y * 0.5 + 250.0)
	elif main:
		var y: float = size.y * 0.5 - 218.0
		for row in SLIDERS:
			(_sl[str(row[0])] as HSlider).position = Vector2(x, y + 16.0)
			y += 42.0
		y += 6.0
		for b in _rows:
			if not (b as Button).visible:
				continue
			(b as Button).position = Vector2(x, y)
			y += ROW
	if _page == 1:
		var y2: float = size.y * 0.5 - 232.0
		for k in _keys:
			var b: Button = k["btn"]
			b.text = "%s   —   %s" % [Lang.t("b_" + str(k["act"])),
				Lang.t("bind_hint") if _bind == str(k["act"]) else Settings.key_of(str(k["act"]))]
			b.position = Vector2(x, y2)
			y2 += 32.0
		y2 += 10.0
		_reset_btn.position = Vector2(x, y2)
		_back_btn.position = Vector2(x, y2 + 34.0)
		_hint_y = y2 + 34.0 + 46.0


## ЛОВИМ КЛАВИШУ. Только когда ждём назначения: в остальное время меню не должно
## глотать ввод, иначе ESC перестанет закрывать паузу.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	# ESC на странице управления возвращает НА ШАГ НАЗАД, а не закрывает паузу:
	# иначе из настроек клавиш нельзя выйти, не выйдя заодно и из меню.
	if _bind == "":
		if _page != 0 and k.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_go(0)
		elif menu_mode and k.keycode == KEY_ESCAPE:
			# Из меню настроек ESC — назад на стартовый экран, а не в игру.
			get_viewport().set_input_as_handled()
			_on_resume()
		return
	get_viewport().set_input_as_handled()
	if k.keycode == KEY_ESCAPE:
		_bind = ""
		queue_redraw()
		return
	Settings.bind_key(_bind, k.physical_keycode)
	_bind = ""
	queue_redraw()


func _start_bind(action: String) -> void:
	_bind = action
	queue_redraw()


func _on_reset_binds() -> void:
	Settings.reset_binds()
	_bind = ""
	queue_redraw()


## Качество переключается по кругу и применяется СРАЗУ: игрок должен увидеть
## разницу, не выходя из паузы, иначе решит, что настройка не работает.
func _on_quality() -> void:
	Settings.set_quality((Settings.quality + 1) % 3)
	_qbtn.text = _quality_text()
	quality_changed.emit()
	queue_redraw()


func _on_slider(key: String, v: float) -> void:
	match key:
		"volume": Settings.set_volume(v)
		"music": Settings.set_music(v)
		"sounds": Settings.set_sounds(v)
		"mouse": Settings.set_mouse(v)
		"gamma":
			Settings.set_gamma(v)
			_gam_t = 1.4
	queue_redraw()


func _on_resume() -> void:
	visible = false
	set_process(false)
	if menu_mode:
		menu_mode = false
		closed.emit()
		return
	resumed.emit()


func _on_restart() -> void:
	visible = false
	set_process(false)
	restarted.emit()


## Стирание в два нажатия. Дневник копится между забегами и по-другому не
## восстанавливается — случайный щелчок не должен убивать весь собранный лор.
func _on_wipe() -> void:
	if not _wiped:
		_wiped = true
		_wipe_btn.text = Lang.t("wipe_sure")
		return
	_wiped = false
	_wipe_btn.text = Lang.t("wipe_done")
	wiped.emit()


func _on_quit() -> void:
	quit_game.emit()


func _draw() -> void:
	var f := UI.text(400)
	# Затемнение, а не глухая заливка: пауза не должна прятать мир, из паузы
	# возвращаются обратно в него.
	var dim: float = lerpf(0.88, 0.16, clampf(_gam_t, 0.0, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.015, dim))
	var x: float = (size.x - W) * 0.5
	# Цвета из общей палитры, а не свои: ядовито-зелёный 0.22/1.0/0.62 был ярче
	# всего, что есть в игре, и подписи ползунков светились сильнее заголовка.
	var green := UI.ACCENT
	var grey := UI.DIM
	if _page == 0:
		# Заголовок — книжной антиквой, как заглавие игры.
		draw_string(UI.title(400, 6), Vector2(0, size.y * 0.5 - 256.0),
			Lang.t("settings") if menu_mode else Lang.t("paused"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, UI.INK)
		var y: float = size.y * 0.5 - 218.0
		for row in SLIDERS:
			var key: String = str(row[0])
			var val: float = float(_sl[key].value)
			var txt: String = ("%d%%" % int(round(val * 100.0))) if str(row[5]) == "%" \
				else ("x%.2f" % val)
			draw_string(f, Vector2(x, y), Lang.t(str(row[1])),
				HORIZONTAL_ALIGNMENT_LEFT, W, 13, green)
			draw_string(f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_RIGHT, W, 13, grey)
			y += 42.0
	elif _page == 2:
		_draw_howto(f)
	else:
		draw_string(f, Vector2(0, size.y * 0.5 - 262.0), Lang.t("controls"),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color(0.84, 0.83, 0.79))
		# Геймпад НЕ переназначается, и об этом надо сказать прямо, иначе игрок
		# будет искать, где это делается.
		var yp: float = _hint_y
		for line in Lang.t("bind_pad").split("\n"):
			draw_string(f, Vector2(0, yp), line, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12,
				Color(0.42, 0.41, 0.39))
			yp += 16.0
	draw_string(f, Vector2(0, size.y - 34.0), Lang.t("esc_back"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(0.42, 0.41, 0.39))


## СТРАНИЦА «КАК ИГРАТЬ»: клавиши двумя столбцами и правила под ними — то, что
## раньше висело на главном экране.
func _draw_howto(f: Font) -> void:
	var top: float = size.y * 0.5 - 262.0
	draw_string(UI.title(400, 6), Vector2(0, top), Lang.t("howto"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, UI.INK)
	var cx: float = size.x * 0.5
	var fk := UI.text(600)
	var y0: float = top + 50.0
	for col in [[StartScript.KEY_LEFT, cx - 420.0], [StartScript.KEY_RIGHT, cx + 60.0]]:
		var y: float = y0
		for pair in col[0]:
			var cap: String = str(pair[0])
			if cap == "":
				cap = Lang.t("k_mouse") if pair[1] == "k_look" else Lang.t("k_space")
			draw_string(fk, Vector2(float(col[1]), y), cap, HORIZONTAL_ALIGNMENT_RIGHT,
				120.0, 13, UI.ACCENT)
			draw_string(f, Vector2(float(col[1]) + 132.0, y), Lang.t(str(pair[1])),
				HORIZONTAL_ALIGNMENT_LEFT, 340.0, 14, UI.INK)
			y += 25.0
	var yr: float = y0 + 4.0 * 25.0 + 24.0
	UI.rule(self, Vector2(cx, yr - 12.0), 420.0, UI.FAINT)
	for k in StartScript.RULE_KEYS:
		if str(k) == "":
			yr += 10.0
			continue
		draw_string(f, Vector2(0, yr + 10.0), Lang.t(str(k)),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, UI.DIM)
		yr += 24.0
