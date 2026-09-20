extends Control
class_name VectorHUD

const CYAN = Color("50e2cb")
const INK = Color("101d29")
const MUTED = Color("8ea3b2")
var game: Node3D
var menu: PanelContainer
var menu_title: Label
var menu_description: Label
var continue_button: Button
var range_button: Button
var arena_button: Button
var hit_left: float = 0.0
var critical: bool = false
var damage_flash: float = 0.0
var font: Font = ThemeDB.fallback_font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_menu()
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if is_instance_valid(menu):
		menu.position = Vector2(48, maxf(24, (size.y - menu.size.y) * 0.5))

func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func _label(parent: Control, value: String, size_px: int, color: Color) -> Label:
	var item = Label.new()
	item.text = value
	item.add_theme_font_size_override("font_size", size_px)
	item.add_theme_color_override("font_color", color)
	parent.add_child(item)
	return item

func _button(parent: Control, value: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = value
	button.custom_minimum_size.y = 56
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _style(Color("1c303e"), Color("36505d")))
	button.add_theme_stylebox_override("hover", _style(Color("24483f"), CYAN))
	button.add_theme_stylebox_override("pressed", _style(Color("356859"), CYAN))
	button.add_theme_stylebox_override("focus", _style(Color(0.1, 0.25, 0.23, 0.3), CYAN))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _make_menu() -> void:
	menu = PanelContainer.new()
	menu.custom_minimum_size = Vector2(470, 0)
	menu.size.x = 470
	menu.add_theme_stylebox_override("panel", _style(Color(0.045, 0.075, 0.11, 0.96), Color("2c4453")))
	add_child(menu)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	menu.add_child(layout)
	_label(layout, "FIELD SYSTEMS  /  FPS PROTOTYPE", 13, CYAN)
	_label(layout, "VECTOR", 68, Color("f2f0df"))
	menu_title = _label(layout, "ИСПЫТАТЕЛЬНЫЙ ПОЛИГОН", 17, Color.WHITE)
	menu_description = _label(layout, "Три оружия. Две зоны. Один точный выстрел.", 16, MUTED)
	menu_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_description.custom_minimum_size = Vector2(420, 48)
	continue_button = _button(layout, "ПРОДОЛЖИТЬ", func(): game.resume_session())
	continue_button.visible = false
	range_button = _button(layout, "01    ТИР  /  ТОЧНОСТЬ И ОРУЖИЕ", func(): game.start_session("range"))
	arena_button = _button(layout, "02    АРЕНА  /  БОЕВЫЕ БОТЫ", func(): game.start_session("arena"))
	_label(layout, "ЧУВСТВИТЕЛЬНОСТЬ МЫШИ", 12, MUTED)
	var sensitivity = HSlider.new()
	sensitivity.min_value = 0.5
	sensitivity.max_value = 2.0
	sensitivity.step = 0.05
	sensitivity.value = 1.0
	sensitivity.value_changed.connect(func(value): game.player.sensitivity = 0.0018 * value)
	layout.add_child(sensitivity)
	var sound_toggle = CheckButton.new()
	sound_toggle.text = "Звук"
	sound_toggle.button_pressed = true
	sound_toggle.toggled.connect(func(enabled): AudioServer.set_bus_mute(0, not enabled))
	layout.add_child(sound_toggle)
	_label(layout, "WASD  движение    SHIFT  бег    SPACE  прыжок\nЛКМ  огонь    ПКМ  прицел    R  перезарядка\n1 / 2 / 3  оружие    ESC / TAB  меню    F5  заново", 13, MUTED)
	_label(layout, "GODOT 4  ·  ЛОКАЛЬНЫЙ ОДИНОЧНЫЙ ПРОТОТИП", 11, Color("607a8c"))

func show_menu(title: String = "ИСПЫТАТЕЛЬНЫЙ ПОЛИГОН", description: String = "Три оружия. Две зоны. Один точный выстрел.", resumable: bool = false) -> void:
	menu_title.text = title
	menu_description.text = description
	continue_button.visible = resumable
	menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_layout")
	if resumable: continue_button.grab_focus()
	else: range_button.grab_focus()

func hide_menu() -> void:
	menu.visible = false
	if DisplayServer.get_name() != "headless": Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func mark_hit(headshot: bool) -> void:
	hit_left = 0.18
	critical = headshot

func _process(delta: float) -> void:
	hit_left = maxf(0, hit_left - delta)
	damage_flash = maxf(0, damage_flash - delta * 1.5)
	queue_redraw()

func _text(at: Vector2, words: String, font_size: int = 18, color: Color = Color.WHITE) -> void:
	draw_string(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player): return
	var w = size.x
	var h = size.y
	if is_instance_valid(menu) and menu.visible:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.06, 0.24))
		_text(Vector2(w - 260, h - 46), "TRAIN. ADAPT. REPEAT.", 17, Color("b4c6c7"))
		return
	var player = game.player
	var weapon = player.spec()
	draw_rect(Rect2(24, 24, 262, 65), Color(0.035, 0.07, 0.10, 0.83))
	draw_rect(Rect2(24, 24, 3, 65), CYAN)
	_text(Vector2(43, 50), "VECTOR", 24, Color("f0f1dd"))
	_text(Vector2(43, 73), "01 / ТРЕНИРОВОЧНЫЙ ТИР" if game.mode == "range" else "02 / БОЕВАЯ АРЕНА", 13, CYAN)
	draw_rect(Rect2(w - 283, 24, 259, 65), Color(0.035, 0.07, 0.10, 0.83))
	_text(Vector2(w - 265, 49), "СЧЁТ  %05d" % game.score, 22)
	var accuracy = int(float(game.hits) / maxf(game.shots, 1) * 100)
	_text(Vector2(w - 265, 73), "ТОЧНОСТЬ %d%%    %s" % [accuracy, "ПОПАДАНИЙ %d" % game.hits if game.mode == "range" else "ЦЕЛЕЙ %d" % game.kills], 12, MUTED)
	# Bottom status cards deliberately leave most of the view unobstructed.
	draw_rect(Rect2(24, h - 105, 222, 78), Color(0.035, 0.07, 0.10, 0.88))
	_text(Vector2(42, h - 78), "СОСТОЯНИЕ", 12, MUTED)
	var health_color = CYAN if player.health > 35 else Color("ff9677")
	_text(Vector2(42, h - 43), "%03d" % int(player.health), 29, health_color)
	draw_rect(Rect2(111, h - 60, 112, 6), Color("2d424d"))
	draw_rect(Rect2(111, h - 60, 112 * player.health / 100, 6), health_color)
	_text(Vector2(111, h - 39), "ВОССТАНОВЛЕНИЕ" if player.health < 100 and player.health_delay <= 0 else "БРОНЯ / HP", 10, MUTED)
	draw_rect(Rect2(w - 298, h - 116, 274, 89), Color(0.035, 0.07, 0.10, 0.88))
	draw_rect(Rect2(w - 298, h - 116, 3, 89), weapon.accent)
	_text(Vector2(w - 279, h - 90), weapon.short_name, 14, weapon.accent)
	_text(Vector2(w - 280, h - 45), "%02d" % player.magazines[player.selected], 43)
	_text(Vector2(w - 214, h - 45), "/ %02d  ∞" % weapon.magazine_size, 19, MUTED)
	_text(Vector2(w - 127, h - 45), "АВТО" if weapon.automatic else "ОДИН", 12, MUTED)
	if player.reload_left > 0:
		var progress = 1.0 - player.reload_left / weapon.reload_seconds
		draw_rect(Rect2(w - 279, h - 34, 236 * progress, 3), weapon.accent)
		_text(Vector2(w * 0.5 - 63, h * 0.5 + 55), "ПЕРЕЗАРЯДКА", 13, weapon.accent)
	var center = size * 0.5
	var gap = (3.5 if player.aiming else 7.0) + player.recoil_push * 7
	if weapon.pellets > 1: gap += 4
	var cross_color = Color(0.9, 1, 0.94, 0.9)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + direction * gap, center + direction * (gap + 5), cross_color, 1.5)
	draw_circle(center, 1.4, cross_color)
	if hit_left > 0:
		var hit_color = Color("ffc37b") if critical else Color.WHITE
		for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(center + direction * 10, center + direction * 17, hit_color, 2.0)
	if game.message_left > 0:
		var text_width = font.get_string_size(game.message, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_rect(Rect2(w * 0.5 - text_width * 0.5 - 20, 105, text_width + 40, 43), Color(0.035, 0.07, 0.1, 0.9))
		_text(Vector2(w * 0.5 - text_width * 0.5, 134), game.message, 22, Color("f2e2bf"))
	if game.mode == "arena":
		_text(Vector2(44, 116), "ВОЛНА %d / 3    БОТОВ: %d" % [game.wave, game.alive_bots()], 15, Color("ffc18a"))
	var help = "1  2  3   ОРУЖИЕ       R   ПЕРЕЗАРЯДКА       TAB   СМЕНА ЗОНЫ"
	var help_width = font.get_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_text(Vector2(w * 0.5 - help_width * 0.5, h - 22), help, 11, MUTED)
	if damage_flash > 0:
		var red = Color(0.9, 0.16, 0.08, damage_flash * 0.28)
		for rect in [Rect2(0, 0, w, 12), Rect2(0, h - 12, w, 12), Rect2(0, 0, 12, h), Rect2(w - 12, 0, 12, h)]: draw_rect(rect, red)
