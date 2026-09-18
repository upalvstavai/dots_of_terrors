extends Node
var t := 0.0
func _ready() -> void:
	print("[тест] ready")
func _process(delta: float) -> void:
	t += delta
	if t > 1.0:
		print("[тест] process ок")
		get_tree().quit()
