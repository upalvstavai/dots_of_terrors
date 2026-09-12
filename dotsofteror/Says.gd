extends Node
## РАСПОРЯДИТЕЛЬ ФРАЗ. Он решает не ЧТО сказать, а МОЖНО ЛИ сейчас.
##
## Зачем отдельный узел: правила частоты важнее самих фраз, и если разложить их
## по местам вызова, они расползутся и разойдутся. Слом четвёртой стены — удар
## одноразовый. Услышав четвёртую фразу за забег, игрок понимает, что это
## скрипт, и весь приём переворачивается: тварь становится комментатором, а
## комментатора не боятся.
##
## Поэтому здесь один вход — try_say — и он чаще отвечает «нет», чем «да».

const Settings := preload("res://Settings.gd")
const Lang := preload("res://Lang.gd")

## Сколько фраз за забег, не считая фаталити.
const BUDGET := 3
## До этой секунды забега молчим: сначала игра должна стать обычной, иначе
## ломать нечего.
const WARMUP := 90.0
## И столько между фразами.
const GAP := 240.0

var voice                       ## VoiceUI
var left: int = BUDGET
var clock: float = 0.0
var last_said: float = -9999.0
var said_run: Dictionary = {}   ## что уже звучало в этом забеге


func _process(delta: float) -> void:
	clock += delta


## Попробовать сказать. Возвращает true, только если фраза действительно
## прозвучала. args — подстановки в текст, как у обычных строк Lang.
##
## once_ever: фраза даётся ОДИН РАЗ ЗА ВСЮ ИГРУ и помнится между запусками.
## Такие держатся на правде — «ты закрыл игру, я подождал», — и повторить их
## нельзя: во второй раз это уже не правда, а фокус.
func try_say(key: String, once_ever: bool = false, args: Array = []) -> bool:
	if voice == null or left <= 0:
		return false
	if clock < WARMUP or clock - last_said < GAP:
		return false
	if said_run.has(key):
		return false
	if once_ever and Settings.was_said(key):
		return false
	_speak(key, args)
	left -= 1
	if once_ever:
		Settings.note_said(key)
	return true


## Фраза фаталити. Она вне бюджета и вне пауз: это последнее, что игрок слышит
## за забег, и молчать там нельзя из-за счётчика.
func say_now(key: String, args: Array = []) -> void:
	if voice == null:
		return
	_speak(key, args)


func _speak(key: String, args: Array) -> void:
	var text: String = Lang.t(key)
	if not args.is_empty():
		text = text % args
	voice.say(text)
	said_run[key] = true
	last_said = clock
