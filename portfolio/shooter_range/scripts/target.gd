extends StaticBody3D
class_name VectorTarget

var game: Node3D
var moving: bool = false
var base_x: float = 0.0
var phase: float = 0.0
var pulse: float = 0.0
var face: Node3D
var light_ring: MeshInstance3D

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	base_x = position.x
	phase = position.z
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.2, 1.55, 0.22)
	collider.shape = shape
	add_child(collider)
	face = Node3D.new()
	add_child(face)
	VectorGeo.box(face, Vector3.ZERO, Vector3(1.15, 1.50, 0.16), Color("d6d4bc"))
	for ring in [[0.51, "263c49"], [0.36, "d6d4bc"], [0.22, "263c49"], [0.095, "50e2cb"]]:
		var disc = VectorGeo.cylinder(face, Vector3(0, 0.12, 0.09 + (0.52 - ring[0]) * 0.025), ring[0], 0.012, Color(ring[1]))
		disc.rotation.x = PI * 0.5
	light_ring = VectorGeo.cylinder(face, Vector3(0, 0.12, 0.115), 0.06, 0.016, Color("50e2cb"), 0.4)
	light_ring.rotation.x = PI * 0.5
	VectorGeo.box(self, Vector3(0, -1.15, -0.08), Vector3(0.075, 1.15, 0.08), Color("526273"))

func _physics_process(delta: float) -> void:
	if not game.playing: return
	phase += delta
	if moving: position.x = base_x + sin(phase * 0.72) * 3.5
	pulse = maxf(0, pulse - delta * 5)
	face.rotation.x = -pulse * 0.11
	light_ring.material_override.emission_energy_multiplier = 0.4 + pulse * 4

func receive_hit(_damage: float, at: Vector3, _direction: Vector3) -> int:
	pulse = 1
	var local = to_local(at) - Vector3(0, 0.12, 0)
	var radius = Vector2(local.x, local.y).length()
	var points = 100 if radius < 0.17 else (50 if radius < 0.36 else 25)
	game.score += points
	game.pop_number(at, "+%d" % points, Color("50e2cb"))
	return 2 if points == 100 else 1
