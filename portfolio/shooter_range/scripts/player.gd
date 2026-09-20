extends CharacterBody3D
class_name VectorPlayer

const SPECS = [
	preload("res://weapons/01_pistol.tres"),
	preload("res://weapons/02_rifle.tres"),
	preload("res://weapons/03_shotgun.tres")
]
var game: Node3D
var camera: Camera3D
var rig: Node3D
var muzzle: Node3D
var flash: MeshInstance3D
var weapon_models: Array[Node3D] = []
var magazines: Array[int] = [12, 30, 6]
var selected: int = 0
var cooldown: float = 0.0
var reload_left: float = 0.0
var health: float = 100.0
var health_delay: float = 0.0
var recoil_push: float = 0.0
var flash_left: float = 0.0
var step_phase: float = 0.0
var aiming: bool = false
var speed: float = 5.2
var sensitivity: float = 0.0018

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	var collider = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.31
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.64
	camera.fov = 76
	camera.near = 0.035
	camera.far = 120
	add_child(camera)
	camera.make_current()
	rig = Node3D.new()
	camera.add_child(rig)
	for i in SPECS.size():
		weapon_models.append(_make_weapon(i))
	muzzle = Node3D.new()
	rig.add_child(muzzle)
	muzzle.position = Vector3(0.0, 0.0, -0.78)
	flash = VectorGeo.cylinder(muzzle, Vector3.ZERO, 0.055, 0.14, Color("fff0a8"), 2.0)
	flash.rotation.x = PI * 0.5
	flash.visible = false
	equip(0)

func reset_at(at: Vector3) -> void:
	global_position = at
	rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	health = 100
	health_delay = 0
	reload_left = 0
	cooldown = 0
	recoil_push = 0
	for i in SPECS.size(): magazines[i] = SPECS[i].magazine_size
	equip(0)

func spec() -> VectorWeaponSpec:
	return SPECS[selected]

func equip(index: int) -> void:
	selected = posmod(index, SPECS.size())
	reload_left = 0
	cooldown = maxf(cooldown, 0.18)
	for i in weapon_models.size(): weapon_models[i].visible = i == selected
	if is_instance_valid(muzzle):
		muzzle.position.z = -0.46 if selected == 0 else (-0.88 if selected == 1 else -0.94)

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(game) or not game.playing: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * sensitivity
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sensitivity, -1.42, 1.42)
	if event.is_action_pressed("reload"): reload_weapon()
	if event.is_action_pressed("weapon_1"): equip(0)
	if event.is_action_pressed("weapon_2"): equip(1)
	if event.is_action_pressed("weapon_3"): equip(2)
	if event.is_action_pressed("next_weapon"): equip(selected + 1)
	if event.is_action_pressed("prev_weapon"): equip(selected - 1)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not game.playing: return
	cooldown = maxf(0, cooldown - delta)
	if reload_left > 0:
		reload_left = maxf(0, reload_left - delta)
		if reload_left == 0:
			magazines[selected] = spec().magazine_size
			game.sound.play("reload", -4)
	health_delay = maxf(0, health_delay - delta)
	if health_delay == 0 and health > 0 and health < 100:
		health = minf(100, health + delta * 12)
	aiming = Input.is_action_pressed("aim") and reload_left == 0
	var movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(movement.x, 0, movement.y)).normalized()
	var sprinting = Input.is_action_pressed("sprint") and not aiming
	var pace = 8.0 if sprinting else (3.3 if aiming else 5.2)
	velocity.x = move_toward(velocity.x, direction.x * pace, delta * 30)
	velocity.z = move_toward(velocity.z, direction.z * pace, delta * 30)
	if not is_on_floor(): velocity.y -= 24 * delta
	elif Input.is_action_just_pressed("jump"): velocity.y = 6.7
	move_and_slide()
	var wants_fire = Input.is_action_pressed("fire") if spec().automatic else Input.is_action_just_pressed("fire")
	if wants_fire and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		fire_weapon()
	if global_position.y < -8: receive_hit(200)

func _process(delta: float) -> void:
	if not is_instance_valid(rig): return
	var active = is_instance_valid(game) and game.playing
	if active:
		step_phase += delta * Vector2(velocity.x, velocity.z).length() * 1.8
		recoil_push = move_toward(recoil_push, 0, delta * 5)
		flash_left = maxf(0, flash_left - delta)
	flash.visible = flash_left > 0
	var aim = aiming and active
	var resting = Vector3(0.0, -0.16, -0.32) if aim else Vector3(0.30, -0.27, -0.47)
	var walking = minf(Vector2(velocity.x, velocity.z).length() / 5.0, 1.0) if active else 0.0
	resting += Vector3(sin(step_phase) * 0.008, absf(cos(step_phase)) * 0.009, 0) * walking
	resting.z += recoil_push * 0.05
	var reload_tilt = 0.0
	if reload_left > 0:
		var progress = 1.0 - reload_left / spec().reload_seconds
		reload_tilt = sin(progress * PI)
		resting.y -= reload_tilt * 0.18
	rig.position = rig.position.lerp(resting, 1 - exp(-delta * 20))
	rig.rotation.x = recoil_push * 0.07 - reload_tilt * 0.6
	rig.rotation.z = reload_tilt * 0.4
	camera.fov = lerpf(camera.fov, 53.0 if aim else 76.0, 1 - exp(-delta * 12))

func reload_weapon() -> void:
	if reload_left > 0 or magazines[selected] >= spec().magazine_size: return
	reload_left = spec().reload_seconds
	game.sound.play("reload")

func fire_weapon() -> bool:
	if not game.playing or cooldown > 0 or reload_left > 0: return false
	if magazines[selected] <= 0:
		game.sound.play("empty")
		cooldown = 0.2
		reload_weapon()
		return false
	var weapon = spec()
	magazines[selected] -= 1
	cooldown = weapon.fire_interval
	game.shots += 1
	game.sound.play(["pistol", "rifle", "shotgun"][selected])
	var connected = false
	var is_head = false
	var spread = deg_to_rad(weapon.spread_degrees) * (0.35 if aiming else 1.0)
	if Vector2(velocity.x, velocity.z).length() > 4: spread *= 1.6
	var origin = camera.global_position
	var forward = -camera.global_basis.z
	for pellet in weapon.pellets:
		var angle = randf() * TAU
		var radius = sqrt(randf()) * tan(spread)
		var direction = (forward + camera.global_basis.x * cos(angle) * radius + camera.global_basis.y * sin(angle) * radius).normalized()
		var endpoint = origin + direction * 90
		var query = PhysicsRayQueryParameters3D.create(origin, endpoint, 1 | 4)
		query.exclude = [get_rid()]
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			endpoint = hit.position
			if hit.collider.has_method("receive_hit"):
				var result = hit.collider.receive_hit(weapon.damage, hit.position, direction)
				connected = connected or result > 0
				is_head = is_head or result == 2
			game.impact(hit.position, hit.normal, connected)
		game.tracer(muzzle.global_position, endpoint, weapon.accent)
	if connected:
		game.hits += 1
		game.hud.mark_hit(is_head)
		game.sound.play("hit", -3)
	for bot in game.bots:
		if is_instance_valid(bot): bot.hear_shot(global_position)
	recoil_push = weapon.recoil
	camera.rotation.x = minf(camera.rotation.x + deg_to_rad(weapon.recoil * 0.4), 1.42)
	flash_left = 0.045
	return true

func receive_hit(damage: float) -> void:
	if health <= 0 or not game.playing: return
	health = maxf(0, health - damage)
	health_delay = 5.0
	game.hud.damage_flash = 0.8
	if health <= 0: game.finish_session(false)

func _make_weapon(index: int) -> Node3D:
	var root = Node3D.new()
	rig.add_child(root)
	var metal = Color("273542")
	var dark = Color("111b25")
	var cream = Color("b8c3be")
	var accent = SPECS[index].accent
	# Distinct silhouettes built from original simple geometry.
	if index == 0:
		VectorGeo.box(root, Vector3(0, 0, -0.18), Vector3(0.095, 0.095, 0.36), cream)
		VectorGeo.box(root, Vector3(0, -0.11, -0.04), Vector3(0.078, 0.20, 0.10), dark).rotation.x = -0.16
		var barrel = VectorGeo.cylinder(root, Vector3(0, 0, -0.37), 0.035, 0.12, dark)
		barrel.rotation.x = PI * 0.5
		VectorGeo.box(root, Vector3(0, 0.055, -0.30), Vector3(0.018, 0.025, 0.028), accent, false, 0.4)
	else:
		var length = 0.55 if index == 1 else 0.62
		VectorGeo.box(root, Vector3(0, 0, -0.26), Vector3(0.11, 0.13, length), metal)
		VectorGeo.box(root, Vector3(0, -0.12, -0.04), Vector3(0.085, 0.22, 0.11), dark).rotation.x = -0.2
		VectorGeo.box(root, Vector3(0, 0.015, 0.13), Vector3(0.085, 0.15, 0.22), cream)
		var barrel = VectorGeo.cylinder(root, Vector3(0, 0.014, -0.65), 0.032 if index == 1 else 0.045, 0.38, dark)
		barrel.rotation.x = PI * 0.5
		if index == 1:
			VectorGeo.box(root, Vector3(0, -0.13, -0.26), Vector3(0.07, 0.23, 0.14), cream).rotation.x = 0.18
			for offset in [-0.38, -0.44, -0.50]:
				VectorGeo.box(root, Vector3(0, 0.004, offset), Vector3(0.12, 0.14, 0.018), dark)
		else:
			VectorGeo.box(root, Vector3(0, -0.06, -0.49), Vector3(0.13, 0.11, 0.24), cream)
			for offset in [-0.40, -0.46, -0.52, -0.58]:
				VectorGeo.box(root, Vector3(0, -0.11, offset), Vector3(0.135, 0.02, 0.025), dark)
		VectorGeo.box(root, Vector3(0, 0.083, -0.45), Vector3(0.025, 0.055, 0.035), accent, false, 0.5)
	VectorGeo.box(root, Vector3(0.056, 0.015, -0.20), Vector3(0.006, 0.027, 0.12), accent, false, 0.35)
	# Gloves and sleeve intentionally use the same geometric language as the guns.
	VectorGeo.box(root, Vector3(0.022, -0.14, 0.005), Vector3(0.12, 0.105, 0.15), Color("46545c"))
	VectorGeo.box(root, Vector3(0.03, -0.23, 0.08), Vector3(0.115, 0.13, 0.17), dark)
	if index > 0:
		VectorGeo.box(root, Vector3(-0.04, -0.10, -0.45), Vector3(0.13, 0.10, 0.16), Color("46545c"))
	return root
