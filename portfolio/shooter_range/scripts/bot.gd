extends CharacterBody3D
class_name VectorBot

enum State { PATROL, SEARCH, ENGAGE, RELOAD }
var game: Node3D
var state: State = State.PATROL
var health: float = 100.0
var rounds: int = 10
var reload_left: float = 0.0
var think_left: float = 0.0
var fire_left: float = 1.3
var path_left: float = 0.0
var memory: float = 0.0
var last_known: Vector3
var destination: Vector3
var path: PackedVector3Array = []
var path_index: int = 0
var visible_player: bool = false
var dead: bool = false
var visual: Node3D
var head: Node3D
var muzzle: Node3D
var legs: Array[Node3D] = []
var visor: MeshInstance3D
var walk_phase: float = 0.0
var health_bar: Node3D
var skill: float = 1.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var collider = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.9
	collider.shape = shape
	collider.position.y = 0.95
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	var orange = Color("d67c4f")
	var dark = Color("25333e")
	VectorGeo.box(visual, Vector3(0, 1.17, 0), Vector3(0.56, 0.64, 0.33), orange)
	VectorGeo.box(visual, Vector3(0, 1.18, -0.19), Vector3(0.35, 0.37, 0.045), dark)
	VectorGeo.box(visual, Vector3(0, 1.19, -0.22), Vector3(0.18, 0.035, 0.025), Color("ffe8a4"), false, 0.5)
	head = VectorGeo.box(visual, Vector3(0, 1.69, 0), Vector3(0.36, 0.32, 0.34), dark)
	visor = VectorGeo.cylinder(visual, Vector3(0, 1.71, -0.185), 0.065, 0.03, Color("ffb573"), 0.8)
	visor.rotation.x = PI * 0.5
	VectorGeo.box(visual, Vector3(-0.34, 1.23, -0.07), Vector3(0.18, 0.44, 0.18), dark).rotation.x = -0.7
	VectorGeo.box(visual, Vector3(0.34, 1.23, -0.12), Vector3(0.18, 0.44, 0.18), dark).rotation.x = -0.9
	VectorGeo.box(visual, Vector3(0.20, 1.22, -0.42), Vector3(0.12, 0.13, 0.58), Color("111b24"))
	muzzle = Node3D.new()
	visual.add_child(muzzle)
	muzzle.position = Vector3(0.20, 1.22, -0.76)
	for x in [-0.17, 0.17]:
		var pivot = Node3D.new()
		visual.add_child(pivot)
		pivot.position = Vector3(x, 0.85, 0)
		VectorGeo.box(pivot, Vector3(0, -0.34, 0), Vector3(0.22, 0.67, 0.23), dark)
		VectorGeo.box(pivot, Vector3(0, -0.72, -0.05), Vector3(0.24, 0.14, 0.35), orange)
		legs.append(pivot)
	health_bar = Node3D.new()
	add_child(health_bar)
	health_bar.position.y = 2.15
	VectorGeo.box(health_bar, Vector3.ZERO, Vector3(0.68, 0.045, 0.045), Color("ff9d68"), false, 0.4)
	last_known = global_position
	destination = game.random_arena_point()

func eye() -> Vector3:
	return global_position + Vector3(0, 1.62, 0)

func can_see_player() -> bool:
	if not is_instance_valid(game.player) or game.player.health <= 0: return false
	var from = eye()
	var to = game.player.global_position + Vector3(0, 1.1, 0)
	if from.distance_to(to) > 28: return false
	# Only world and player: another bot must not hide the player from perception.
	var query = PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	query.exclude = [get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == game.player

func hear_shot(at: Vector3) -> void:
	if dead or global_position.distance_to(at) > 24: return
	last_known = at
	memory = 5.0
	if state == State.PATROL: state = State.SEARCH

func _physics_process(delta: float) -> void:
	if dead or not game.playing: return
	think_left -= delta
	path_left -= delta
	fire_left = maxf(0, fire_left - delta)
	memory = maxf(0, memory - delta)
	if reload_left > 0:
		reload_left = maxf(0, reload_left - delta)
		if reload_left == 0: rounds = 10
	if think_left <= 0:
		think_left = 0.18
		_think()
	if path_left <= 0:
		path_left = 0.5
		path = game.navigation_path(global_position, destination)
		path_index = 1 if path.size() > 1 else 0
	var travel = Vector3.ZERO
	if path_index < path.size():
		var next = path[path_index]
		next.y = global_position.y
		if global_position.distance_to(next) < 0.40:
			path_index += 1
		else:
			travel = (next - global_position).normalized()
	var pace = 2.5 if state == State.ENGAGE else 3.0
	velocity.x = move_toward(velocity.x, travel.x * pace, delta * 13)
	velocity.z = move_toward(velocity.z, travel.z * pace, delta * 13)
	if not is_on_floor(): velocity.y -= 24 * delta
	move_and_slide()
	var facing = game.player.global_position if visible_player else (global_position + travel)
	var flat = facing - global_position
	if flat.length_squared() > 0.1:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-flat.x, -flat.z), delta * 9)
	walk_phase += delta * travel.length() * 9
	for i in legs.size(): legs[i].rotation.x = sin(walk_phase + i * PI) * 0.42 * travel.length()
	if visible_player and fire_left == 0 and reload_left == 0:
		shoot()
	health_bar.scale.x = maxf(health / 100.0, 0.001)
	health_bar.rotation.y = visual.rotation.y

func _think() -> void:
	visible_player = can_see_player()
	var player_at = game.player.global_position
	var distance = global_position.distance_to(player_at)
	if visible_player:
		last_known = player_at
		memory = 4.5
	if reload_left > 0:
		state = State.RELOAD
		return
	if rounds <= 0:
		reload_left = 1.9
		state = State.RELOAD
		destination = game.cover_point(global_position, player_at)
		path_left = 0
		return
	if visible_player:
		state = State.ENGAGE
		if distance > 13:
			destination = player_at
		elif distance < 5:
			destination = global_position + (global_position - player_at).normalized() * 4
		elif global_position.distance_to(destination) < 1.0 or randf() < 0.07:
			var perpendicular = (player_at - global_position).cross(Vector3.UP).normalized()
			destination = global_position + perpendicular * [-3.0, 3.0].pick_random()
	elif memory > 0:
		state = State.SEARCH
		destination = last_known
	else:
		state = State.PATROL
		if global_position.distance_to(destination) < 1.0:
			destination = game.random_arena_point()

func shoot() -> void:
	if dead or not game.playing or reload_left > 0 or rounds <= 0: return
	# Recheck visibility at the moment of firing, not just at the AI tick.
	if not can_see_player(): return
	rounds -= 1
	fire_left = randf_range(0.38, 0.65) / skill
	var origin = muzzle.global_position
	var target = game.player.global_position + Vector3(0, 1.15, 0)
	var distance = origin.distance_to(target)
	var error = distance * 0.038 / skill
	target += Vector3(randf_range(-error, error), randf_range(-error, error), 0)
	var direction = (target - origin).normalized()
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * 60, 1 | 2)
	query.exclude = [get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	var endpoint = origin + direction * 60
	if not hit.is_empty():
		endpoint = hit.position
		if hit.collider == game.player: game.player.receive_hit(8.0)
		else: game.impact(hit.position, hit.normal, false)
	game.tracer(origin, endpoint, Color("ffb36d"))
	game.sound.play("enemy", -9)

func receive_hit(damage: float, at: Vector3, direction: Vector3) -> int:
	if dead: return 0
	var headshot = at.y - global_position.y > 1.50
	health -= damage * (2.0 if headshot else 1.0)
	memory = 6
	last_known = game.player.global_position
	game.pop_number(at, str(int(damage * (2 if headshot else 1))), Color("ffdb9e") if headshot else Color.WHITE)
	if health <= 0:
		dead = true
		collision_layer = 0
		collision_mask = 0
		game.bot_defeated(self, headshot)
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "rotation:x", -1.5, 0.24)
		tween.tween_property(visual, "position", direction * 0.6 + Vector3(0, -0.6, 0), 0.3)
		tween.chain().tween_interval(0.8)
		tween.chain().tween_callback(queue_free)
	return 2 if headshot else 1
