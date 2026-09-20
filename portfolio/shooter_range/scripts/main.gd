extends Node3D

const ARENA_X = 42.0
const CYAN = Color("50e2cb")
const WALL = Color("344a59")
const DARK = Color("172935")
const CREAM = Color("c6ccbe")

var player: VectorPlayer
var hud: VectorHUD
var sound: VectorSound
var actors: Node3D
var effects: Node3D
var bots: Array[VectorBot] = []
var targets: Array[VectorTarget] = []
var cover_boxes: Array[Dictionary] = []
var navigation: AStarGrid2D
var playing: bool = false
var has_session: bool = false
var mode: String = "range"
var score: int = 0
var shots: int = 0
var hits: int = 0
var kills: int = 0
var wave: int = 0
var next_wave_left: float = 0.0
var message: String = ""
var message_left: float = 0.0
var session_seconds: float = 0.0

func _ready() -> void:
	Engine.max_fps = 60
	_inputs()
	_lighting()
	actors = Node3D.new()
	actors.name = "Actors"
	add_child(actors)
	effects = Node3D.new()
	effects.name = "TransientEffects"
	add_child(effects)
	_build_range()
	_build_arena()
	_build_navigation()
	sound = VectorSound.new()
	add_child(sound)
	player = VectorPlayer.new()
	player.name = "Player"
	player.game = self
	add_child(player)
	player.reset_at(Vector3(0, 0.05, 7))
	var canvas = CanvasLayer.new()
	add_child(canvas)
	hud = VectorHUD.new()
	hud.game = self
	canvas.add_child(hud)
	hud.show_menu()
	if "--capture-range" in OS.get_cmdline_user_args(): _capture_demo("range")
	if "--capture-arena" in OS.get_cmdline_user_args(): _capture_demo("arena")

func _inputs() -> void:
	var keys = {
		"move_forward": KEY_W, "move_back": KEY_S,
		"move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "reload": KEY_R,
		"weapon_1": KEY_1, "weapon_2": KEY_2, "weapon_3": KEY_3
	}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var key = InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action, key)
	for action in {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT, "next_weapon": MOUSE_BUTTON_WHEEL_DOWN, "prev_weapon": MOUSE_BUTTON_WHEEL_UP}:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event = InputEventMouseButton.new()
		event.button_index = {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT, "next_weapon": MOUSE_BUTTON_WHEEL_DOWN, "prev_weapon": MOUSE_BUTTON_WHEEL_UP}[action]
		InputMap.action_add_event(action, event)

func _lighting() -> void:
	var world = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("142c45")
	sky_material.sky_horizon_color = Color("93b8c4")
	sky_material.ground_bottom_color = Color("182938")
	sky_material.ground_horizon_color = Color("93b8c4")
	sky_material.sky_curve = 0.22
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bddce5")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("344b5d")
	environment.fog_density = 0.004
	world.environment = environment
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_color = Color("fff1d0")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	add_child(sun)

func _floor(center: Vector3, size: Vector3) -> void:
	VectorGeo.box(self, center, size, Color("253b47"), true)
	# Fine painted floor divisions provide depth without external textures.
	for x in range(int(center.x - size.x * 0.5) + 2, int(center.x + size.x * 0.5), 2):
		VectorGeo.box(self, Vector3(x, 0.007, center.z), Vector3(0.022, 0.012, size.z), Color("344d59"))
	for z in range(int(center.z - size.z * 0.5) + 2, int(center.z + size.z * 0.5), 2):
		VectorGeo.box(self, Vector3(center.x, 0.008, z), Vector3(size.x, 0.012, 0.022), Color("344d59"))

func _build_range() -> void:
	_floor(Vector3(0, -0.16, -10), Vector3(30, 0.32, 48))
	VectorGeo.box(self, Vector3(-15, 2.3, -10), Vector3(0.5, 4.6, 48), WALL, true)
	VectorGeo.box(self, Vector3(15, 2.3, -10), Vector3(0.5, 4.6, 48), WALL, true)
	VectorGeo.box(self, Vector3(0, 3.5, -34), Vector3(30, 7, 0.6), DARK, true)
	VectorGeo.box(self, Vector3(0, 1.6, 14), Vector3(30, 3.2, 0.6), DARK, true)
	VectorGeo.label(self, Vector3(0, 5.25, -33.63), "01   /   PRECISION", 90, CREAM)
	VectorGeo.label(self, Vector3(0, 3.96, -33.62), "VECTOR   •   TRAINING GROUNDS", 31, CYAN)
	for z in [9, -1, -11, -21, -31]:
		for x in [-14.6, 14.6]:
			VectorGeo.box(self, Vector3(x, 2.7, z), Vector3(0.38, 5.4, 0.5), CREAM)
			VectorGeo.box(self, Vector3(x * 0.989, 2.75, z + 0.28), Vector3(0.12, 3.6, 0.06), CYAN, false, 0.45)
		VectorGeo.box(self, Vector3(0, 5.35, z), Vector3(29.4, 0.30, 0.42), DARK)
		VectorGeo.box(self, Vector3(0, 5.14, z + 0.06), Vector3(12, 0.04, 0.12), Color("b5e2de"), false, 0.6)
	for x in [-10, -3.3, 3.3, 10]:
		VectorGeo.box(self, Vector3(x, 0.021, -15), Vector3(0.055, 0.02, 33), CYAN)
	for z in [-7, -17, -27]:
		VectorGeo.box(self, Vector3(0, 0.024, z), Vector3(21, 0.02, 0.09), Color("d7cf99"))
		VectorGeo.label(self, Vector3(-12.0, 0.5, z), "%02d M" % (7 - z), 38, CREAM)
	for x in [-4.6, 4.6]:
		VectorGeo.box(self, Vector3(x, 0.47, 3), Vector3(0.28, 0.94, 5), WALL, true)
		VectorGeo.box(self, Vector3(x, 0.97, 3), Vector3(0.35, 0.08, 5), CREAM)
	var placements = [Vector3(-7, 1.7, -10), Vector3(0, 1.7, -13), Vector3(7, 1.7, -10), Vector3(-5, 1.7, -23), Vector3(5, 1.7, -23), Vector3(0, 1.9, -28)]
	for i in placements.size():
		var target = VectorTarget.new()
		target.game = self
		target.position = placements[i]
		target.moving = i == 5
		actors.add_child(target)
		targets.append(target)
		VectorGeo.label(self, placements[i] + Vector3(0, 1.35, 0), "MOVING" if i == 5 else "T-%02d" % (i + 1), 20, CYAN)
	# A equipment bench gives the starting area a recognizable silhouette.
	VectorGeo.box(self, Vector3(-10, 0.9, 7), Vector3(5, 0.18, 1.5), CREAM, true)
	for x in [-11.8, -8.2]: VectorGeo.box(self, Vector3(x, 0.45, 7), Vector3(0.2, 0.9, 1.2), DARK, true)
	for x in [-11, -9.5]:
		VectorGeo.box(self, Vector3(x, 1.16, 7), Vector3(0.7, 0.4, 0.6), DARK)
		VectorGeo.box(self, Vector3(x, 1.38, 7), Vector3(0.3, 0.015, 0.25), CYAN)
	VectorGeo.label(self, Vector3(9, 2.15, 9.3), "[ TAB ]\nCOMBAT ARENA →", 35, CYAN)

func _build_arena() -> void:
	_floor(Vector3(ARENA_X, -0.16, -6), Vector3(30, 0.32, 40))
	for x in [ARENA_X - 15, ARENA_X + 15]:
		VectorGeo.box(self, Vector3(x, 2.8, -6), Vector3(0.55, 5.6, 40), WALL, true)
		VectorGeo.box(self, Vector3(x + (0.31 if x < ARENA_X else -0.31), 1.0, -6), Vector3(0.04, 0.08, 39), Color("f5aa68"), false, 0.5)
	VectorGeo.box(self, Vector3(ARENA_X, 3.4, -26), Vector3(30, 6.8, 0.5), DARK, true)
	VectorGeo.box(self, Vector3(ARENA_X, 2, 14), Vector3(30, 4, 0.5), DARK, true)
	VectorGeo.label(self, Vector3(ARENA_X, 4.9, -25.65), "02   /   LIVE FIRE", 85, CREAM)
	VectorGeo.label(self, Vector3(ARENA_X, 3.75, -25.64), "MOVE    •    TAKE COVER    •    ENGAGE", 29, Color("ffb473"))
	cover_boxes = [
		{"at": Vector3(-7, 1.25, -6), "size": Vector3(4, 2.5, 3)},
		{"at": Vector3(5, 1.25, -12), "size": Vector3(4, 2.5, 3)},
		{"at": Vector3(-1, 1.1, -18), "size": Vector3(5, 2.2, 2.2)},
		{"at": Vector3(8, 1.1, 1), "size": Vector3(3, 2.2, 4)},
		{"at": Vector3(-2, 1.05, -1), "size": Vector3(3, 2.1, 3)}
	]
	for i in cover_boxes.size():
		var cover = cover_boxes[i]
		var at: Vector3 = cover.at + Vector3(ARENA_X, 0, 0)
		var dimensions: Vector3 = cover.size
		VectorGeo.box(self, at, dimensions, Color("647d83") if i % 2 == 0 else Color("586b77"), true)
		VectorGeo.box(self, at + Vector3(0, dimensions.y * 0.5 + 0.025, 0), Vector3(dimensions.x + 0.08, 0.08, dimensions.z + 0.08), CREAM)
		VectorGeo.box(self, at + Vector3(0, 0.50, dimensions.z * 0.5 + 0.014), Vector3(dimensions.x - 0.18, 0.095, 0.025), Color("ffc27a"))
		VectorGeo.label(self, at + Vector3(0, -0.12, dimensions.z * 0.5 + 0.04), "C / 0%d" % (i + 1), 32, Color("d4ddd0"))
	for z in [-23, -14, -5, 4, 12]:
		for x in [-14.7, 14.7]:
			VectorGeo.box(self, Vector3(ARENA_X + x, 3.0, z), Vector3(0.38, 6, 0.40), CREAM)
		VectorGeo.box(self, Vector3(ARENA_X, 5.95, z), Vector3(30, 0.2, 0.3), DARK)
	for x in [-11, 0, 11]:
		VectorGeo.box(self, Vector3(ARENA_X + x, 0.021, -5), Vector3(0.06, 0.02, 35), Color("7a6c52"))
	VectorGeo.box(self, Vector3(ARENA_X, 0.023, 6), Vector3(25, 0.02, 0.16), Color("ffc27a"))

func _build_navigation() -> void:
	navigation = AStarGrid2D.new()
	navigation.region = Rect2i(-13, -24, 26, 36)
	navigation.cell_size = Vector2.ONE
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for x in range(-13, 13):
		for z in range(-24, 12):
			var point = Vector2(x + 0.5, z + 0.5)
			for cover in cover_boxes:
				if absf(point.x - cover.at.x) < cover.size.x * 0.5 + 0.48 and absf(point.y - cover.at.z) < cover.size.z * 0.5 + 0.48:
					navigation.set_point_solid(Vector2i(x, z), true)

func _cell(at: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(at.x - ARENA_X)), -13, 12), clampi(int(floor(at.z)), -24, 11))

func _free_cell(cell: Vector2i) -> Vector2i:
	if not navigation.is_point_solid(cell): return cell
	for radius in range(1, 14):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var test = cell + Vector2i(x, y)
				if navigation.region.has_point(test) and not navigation.is_point_solid(test): return test
	return Vector2i(0, 10)

func navigation_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var ids = navigation.get_id_path(_free_cell(_cell(from)), _free_cell(_cell(to)))
	var result = PackedVector3Array()
	for cell in ids: result.append(Vector3(ARENA_X + cell.x + 0.5, 0, cell.y + 0.5))
	return result

func random_arena_point() -> Vector3:
	var cell = _free_cell(Vector2i(randi_range(-12, 11), randi_range(-23, 9)))
	return Vector3(ARENA_X + cell.x + 0.5, 0, cell.y + 0.5)

func cover_point(from: Vector3, threat: Vector3) -> Vector3:
	var chosen = from
	var best_distance = INF
	for cover in cover_boxes:
		for side in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var half = cover.size.x * 0.5 if side.x != 0 else cover.size.z * 0.5
			var candidate: Vector3 = cover.at + Vector3(ARENA_X, -cover.at.y, 0) + side * (half + 1.1)
			var query = PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 1.4, threat + Vector3.UP * 1.2, 1)
			var hit = get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and from.distance_to(candidate) < best_distance:
				chosen = candidate
				best_distance = from.distance_to(candidate)
	return chosen

func start_session(selected_mode: String) -> void:
	playing = false
	for bot in bots:
		if is_instance_valid(bot):
			bot.collision_layer = 0
			bot.queue_free()
	bots.clear()
	for effect in effects.get_children(): effect.queue_free()
	mode = selected_mode
	score = 0
	shots = 0
	hits = 0
	kills = 0
	wave = 0
	next_wave_left = 0
	session_seconds = 0
	player.reset_at(Vector3(0 if mode == "range" else ARENA_X, 0.08, 7 if mode == "range" else 10))
	for target in targets:
		target.visible = mode == "range"
		target.collision_layer = 4 if mode == "range" else 0
	playing = true
	has_session = true
	hud.hide_menu()
	hud.damage_flash = 0
	hud.hit_left = 0
	if mode == "arena":
		announce("ЗАЙМИ УКРЫТИЕ. КОНТАКТ ЧЕРЕЗ 3 СЕКУНДЫ", 3)
		next_wave_left = 3
	else: announce("ПОПРОБУЙ ОРУЖИЕ: 1 / 2 / 3. ДАЛЬНЯЯ МИШЕНЬ ДВИЖЕТСЯ", 5)
	sound.play("start")

func spawn_wave() -> void:
	wave += 1
	var locations = [Vector3(-10, 0.05, -21), Vector3(1, 0.05, -23), Vector3(10, 0.05, -21), Vector3(-10, 0.05, -12), Vector3(10, 0.05, -12)]
	for i in range(2 + wave):
		var bot = VectorBot.new()
		bot.game = self
		bot.position = locations[i] + Vector3(ARENA_X, 0, 0)
		bot.skill = 0.85 + wave * 0.1
		actors.add_child(bot)
		bots.append(bot)
	announce("ВОЛНА %d / 3 — %d БОТОВ" % [wave, 2 + wave], 2.5)

func alive_bots() -> int:
	var count = 0
	for bot in bots:
		if is_instance_valid(bot) and not bot.dead: count += 1
	return count

func bot_defeated(_bot: VectorBot, headshot: bool) -> void:
	kills += 1
	score += 150 if headshot else 100
	sound.play("kill")
	if alive_bots() == 0:
		announce("ЗОНА ЧИСТА" if wave == 3 else "ВОЛНА ПРОЙДЕНА. ПЕРЕДЫШКА 4 СЕКУНДЫ", 4)
		next_wave_left = 2 if wave == 3 else 4

func finish_session(won: bool) -> void:
	playing = false
	has_session = false
	var accuracy = int(float(hits) / maxf(shots, 1) * 100)
	hud.show_menu("АРЕНА ПРОЙДЕНА" if won else "ПОПРОБУЙ ЕЩЁ РАЗ", "Счёт %d · Целей %d · Точность %d%%\nВремя %d:%02d. Можно выбрать другую зону." % [score, kills, accuracy, int(session_seconds) / 60, int(session_seconds) % 60])

func resume_session() -> void:
	if not has_session: return
	playing = true
	hud.hide_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ESCAPE, KEY_TAB]:
			if playing:
				playing = false
				hud.show_menu("ПАУЗА / СМЕНА ЗОНЫ", "Продолжи тренировку или выбери другую зону.\nНовая сессия сбрасывает счёт.", true)
			elif has_session: resume_session()
			get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_F5: start_session(mode)

func _process(delta: float) -> void:
	if not playing: return
	session_seconds += delta
	message_left = maxf(0, message_left - delta)
	if next_wave_left > 0:
		next_wave_left = maxf(0, next_wave_left - delta)
		if next_wave_left == 0:
			if wave >= 3: finish_session(true)
			else: spawn_wave()

func announce(words: String, duration: float) -> void:
	message = words
	message_left = duration

func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	if effects.get_child_count() > 180: return
	var beam = VectorGeo.beam(effects, from, to, color, 0.009)
	var tween = beam.create_tween()
	tween.tween_interval(0.045)
	tween.tween_callback(beam.queue_free)

func impact(at: Vector3, normal: Vector3, on_target: bool) -> void:
	if effects.get_child_count() > 160: return
	var fleck = VectorGeo.box(effects, at + normal * 0.016, Vector3(0.06, 0.06, 0.06), Color("ffde9b") if on_target else Color("a1b8bd"), false, 0.5)
	var tween = fleck.create_tween()
	tween.tween_property(fleck, "scale", Vector3.ONE * 0.01, 0.25)
	tween.tween_callback(fleck.queue_free)

func pop_number(at: Vector3, words: String, color: Color) -> void:
	if effects.get_child_count() > 150: return
	var label = VectorGeo.label(effects, at + Vector3(0, 0.2, 0), words, 26, color)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.006
	var tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.55, 0.48)
	tween.tween_property(label, "modulate:a", 0.0, 0.48)
	tween.chain().tween_callback(label.queue_free)

func _capture_demo(selected_mode: String) -> void:
	await get_tree().process_frame
	start_session(selected_mode)
	player.equip(1)
	if selected_mode == "arena":
		next_wave_left = 0
		spawn_wave()
		player.global_position = Vector3(ARENA_X + 4, 0.05, 8)
		player.camera.look_at(Vector3(ARENA_X, 1.4, -12))
	else:
		player.camera.look_at(Vector3(0, 1.85, -17))
	message_left = 0
	await get_tree().create_timer(1.5).timeout
	playing = false
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var path = "/private/tmp/vector-" + selected_mode + ".png"
	var result = image.save_png(path)
	print("CAPTURE ", path, " status=", result)
	get_tree().quit()
