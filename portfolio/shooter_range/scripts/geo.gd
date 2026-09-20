extends RefCounted
class_name VectorGeo

static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var result = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.83
	if glow > 0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = glow
	return result

static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color, solid: bool = false, glow: float = 0.0) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(root)
	root.position = at
	var mesh = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color, glow)
	root.add_child(mesh)
	if solid:
		root.collision_layer = 1
		root.collision_mask = 0
		var collision = CollisionShape3D.new()
		var bounds = BoxShape3D.new()
		bounds.size = size
		collision.shape = bounds
		root.add_child(collision)
	return root

static func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	var shape = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	instance.mesh = shape
	instance.material_override = material(color, glow)
	parent.add_child(instance)
	instance.position = at
	return instance

static func label(parent: Node3D, at: Vector3, words: String, size: int = 54, color: Color = Color.WHITE) -> Label3D:
	var label = Label3D.new()
	label.text = words
	label.font_size = size
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	parent.add_child(label)
	label.position = at
	return label

static func beam(parent: Node3D, a: Vector3, b: Vector3, color: Color, radius: float = 0.012) -> MeshInstance3D:
	var distance = a.distance_to(b)
	var mesh = cylinder(parent, (a + b) * 0.5, radius, maxf(distance, 0.001), color, 1.0)
	if distance > 0.001:
		var direction = (b - a).normalized()
		var up = Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
		mesh.basis = Basis.looking_at(direction, up) * Basis(Vector3.RIGHT, PI * 0.5)
	return mesh
