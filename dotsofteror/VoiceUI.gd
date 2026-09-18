extends CanvasLayer
const UI := preload("res://UI.gd")
## ГОЛОС ТВАРИ. Отдельный слой, а не строчка в углу.
##
## Подсказки игры живут в левом верхнем углу зелёным шрифтом: «ВСПЫШКА. ОНО
## ОТСТУПИЛО», «ПАЛОЧКА ВЫПАЛА». Если фразы твари появятся там же и тем же
## видом, они прочитаются интерфейсом — очередной служебной строкой, которую
## глаз пропускает. Поэтому здесь всё другое: середина экрана, свой шрифт,
## медленное проявление и уход.
##
## И на время фразы гаснет ВСЁ ОСТАЛЬНОЕ. Пока оно говорит, ничего больше на
## экране быть не должно: ни счётчика полотен, ни полоски безумия. Иначе выходит
## не «с тобой заговорили», а «выскочило окно».

signal speaking(on: bool)

var label: Label
var _t: float = 0.0
var _hold: float = 0.0
var _fade_in: float = 0.9
var _fade_out: float = 1.6
## Место под озвучку. Пока фразы только текстом, но живой голос появится, и
## вызов должен остаться один — поэтому дорожка задаётся здесь, а не у каждого
## места, откуда говорят.
var clip: String = ""
var sfx


func _ready() -> void:
	layer = 64            # выше всего игрового интерфейса
	label = Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# ГОЛОС — КНИЖНОЙ АНТИКВОЙ. Фразы твари не должны читаться интерфейсом: у
	# подсказок свой шрифт и свой угол экрана, а это говорят тебе.
	label.add_theme_font_override("font", UI.title(400, 3))
	label.add_theme_font_size_override("font_size", 38)
	# Не зелёный, как подсказки, и не белый, как записки: почти бесцветный.
	label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.82))
	# Тень, иначе на светлом проломе текста не видно вовсе.
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	add_child(label)
	set_process(true)


## Сказать. seconds — сколько держать на полной яркости, не считая проявления.
func say(text: String, seconds: float = 3.4) -> void:
	if text.is_empty():
		return
	label.text = text
	_t = 0.0
	_hold = seconds
	speaking.emit(true)
	if sfx != null and not clip.is_empty():
		sfx.play(clip, 0.0)


func busy() -> bool:
	return _hold > 0.0 or label.modulate.a > 0.01


func _process(delta: float) -> void:
	if not busy():
		return
	_t += delta
	if _t < _fade_in:
		label.modulate.a = _t / _fade_in
	elif _t < _fade_in + _hold:
		label.modulate.a = 1.0
	else:
		var k: float = (_t - _fade_in - _hold) / _fade_out
		label.modulate.a = maxf(0.0, 1.0 - k)
		if label.modulate.a <= 0.001:
			_hold = 0.0
			label.text = ""
			speaking.emit(false)
