extends Node3D
## Headless smoke tests. Run from the project folder:
##   godot --headless --fixed-fps 60 --path . res://tools/test_runner.tscn
## Builds a solo match with bots, then checks terrain collision, climbing,
## vine swinging, camouflage timers and that the AI produces tags.

var world: Node
var frame := 0
var phase := 0
var failures := 0
var t0 := 0
var _wait := 0
var _data := {}


func _ready() -> void:
	print("== Jungle Tag smoke test ==")
	var scripts := []
	_collect("res://scripts", scripts)
	for p in scripts:
		var s = load(p)
		if s == null:
			_fail("script failed to load: " + p)
	print("loaded %d scripts" % scripts.size())
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.mode = 0
	game.config.max_players = 8
	game.config.fill_bots = true
	game.config.round_time = 60
	game.config.seed = 4242
	net.players = {1: {"name": "Tester", "color": Color.RED}}
	game.roster = game.build_match_roster(net.players)
	t0 = Time.get_ticks_msec()
	var w = load("res://scenes/world.tscn").instantiate()
	w._round_started = true  # rounds are started manually later in the test
	add_child(w)


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)


func _fail(msg: String) -> void:
	failures += 1
	printerr("FAIL: " + msg)


func _ok(msg: String) -> void:
	print("ok: " + msg)


func _process(_delta: float) -> void:
	frame += 1
	if world == null:
		world = get_node_or_null("World")
		if world == null:
			return
		print("world built in %d ms" % (Time.get_ticks_msec() - t0))
		_check_world()
		return
	match phase:
		0:
			_wait += 1
			if _wait > 10:
				_terrain_test()
				_start_climb_test()
				phase = 1
				_wait = 0
		1:
			_wait += 1
			_drive_climb()
			if _wait > 150:
				_end_climb_test()
				_start_vine_test()
				phase = 2
				_wait = 0
		2:
			_wait += 1
			_drive_vine()
			if _wait > 240:
				_end_vine_test()
				_start_camo_test()
				phase = 3
				_wait = 0
		3:
			_wait += 1
			if _wait == 60 * 16:
				_check_camo_ended()
			if _wait > 60 * 16:
				_start_ai_test()
				phase = 4
				_wait = 0
		4:
			_wait += 1
			for id in world.gorillas:
				var inside: bool = world.maze.contains(world.gorillas[id].global_position)
				if inside:
					_data.in_maze[id] = true
				elif _data.in_maze.has(id):
					_data.escaped[id] = true
			if _wait % 600 == 0:
				var near := 999.0
				for hid in world.holes:
					for gid in world.gorillas:
						near = minf(near, world.holes[hid].global_position.distance_to(world.gorillas[gid].global_position))
				if world.holes.is_empty():
					world._hole_timer = 0.0  # holes come every 60 s in game; speed that up for the test
				print("  nearest gorilla to a hole: %.1f m" % near)
				print("  t=%ds holes_open=%d in_maze_ever=%d escaped=%d shadow=%s" % [_wait / 60, world.holes.size(), _data.in_maze.size(), _data.escaped.size(), str(world.npcs[99999].global_position.snapped(Vector3.ONE * 0.1))])
			if _wait > 60 * 150:
				_end_ai_test()
				print("== %s (%d failures) ==" % ["PASSED" if failures == 0 else "FAILED", failures])
				get_tree().quit(1 if failures > 0 else 0)


func _check_world() -> void:
	world._round_started = true  # rounds are started manually later in the test
	var j = world.jungle
	print("trees=%d vines=%d hide_spots=%d spawns=%d platforms=%d gorillas=%d" % [j.trees.size(), j.vines.size(), j.hide_spots.size(), j.spawn_points.size(), j.platforms.size(), world.gorillas.size()])
	if j.trees.size() < 60: _fail("too few trees")
	if j.vines.size() < 80: _fail("too few vines")
	if world.gorillas.size() != 8: _fail("expected 8 gorillas")
	var shapes := 0
	for c in j.get_children():
		if c is StaticBody3D:
			shapes += c.get_child_count()
	print("collision shapes: %d" % shapes)


func _terrain_test() -> void:
	var j = world.jungle
	var space = world.get_world_3d().direct_space_state
	var worst := 0.0
	for p in [Vector2(0, 0), Vector2(40, -30), Vector2(-70, 80), Vector2(100, 100), Vector2(-120, -60)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200, p.y), Vector3(p.x, -50, p.y), 1)
		var terrain_only := []
		var hit = space.intersect_ray(q)
		# skip props that sit above the terrain
		while not hit.is_empty() and not hit.collider.is_in_group("terrain"):
			terrain_only.append(hit.collider.get_rid())
			q.exclude = terrain_only
			hit = space.intersect_ray(q)
		if hit.is_empty():
			_fail("no terrain under %s" % p)
			continue
		worst = maxf(worst, absf(hit.position.y - j.ground_height(p.x, p.y)))
	if worst > 0.6:
		_fail("terrain collision differs from ground_height by %.2f" % worst)
	else:
		_ok("terrain collision matches heights (max error %.2f m)" % worst)


func _local():
	return world.local


func _start_climb_test() -> void:
	var g = _local()
	g.control = 1  # drive it like an AI so the test can set inputs
	var tree: Dictionary = world.jungle.trees[0]
	for t in world.jungle.trees:
		if t.height > 30 and world.jungle.plateau_mask(t.pos.x, t.pos.z) < 0.01:
			tree = t
			break
	var dir := Vector3(1, 0, 0)
	var base: Vector3 = tree.pos
	var p: Vector3 = base + dir * (tree.radius + 1.0)
	p.y = world.jungle.ground_height(p.x, p.z) + 0.2
	g.respawn(p)
	g.input.yaw = atan2(dir.x, dir.z)  # face the trunk (looking along -dir)
	g.input.pitch = 0.0
	_data.climb_start = p.y
	_data.tree = tree


func _drive_climb() -> void:
	var g = _local()
	g.input.grab_l = true
	if _wait == 5:
		g.input.grab_l_pressed = true
	if _wait % 20 == 10:
		g.input.grab_r_pressed = true
	g.input.grab_r = _wait > 10
	g.input.move = Vector2(0, 1)


func _end_climb_test() -> void:
	var g = _local()
	var rise: float = g.global_position.y - _data.climb_start
	print("climb: state=%d rise=%.1f m" % [g.state, rise])
	if rise > 4.0:
		_ok("climbed the trunk")
	else:
		_fail("did not climb (rise %.2f)" % rise)
	g.input.grab_l = false
	g.input.grab_r = false
	g.input.move = Vector2.ZERO


func _start_vine_test() -> void:
	var g = _local()
	var vine = null
	for v in world.jungle.vines:
		var tip: Vector3 = v.anchor() + Vector3(0, -v.length, 0)
		if v.length > 8.0 and tip.y - world.jungle.ground_height(tip.x, tip.z) > 1.0:
			vine = v
			break
	if vine == null:
		_fail("no suitable vine")
		return
	_data.vine = vine
	# start a bit to the side so there is a swing to do
	var hand_target: Vector3 = vine.anchor() + Vector3(0, -vine.length * 0.7, 0)
	g.respawn(hand_target - Vector3(0, Gorilla.HAND_HEIGHT + 0.85, 0))
	g.velocity = Vector3(6, 0, 0)
	g.input.vine = true
	g.input.yaw = -PI / 2.0  # face +x
	_data.max_err = 0.0


func _drive_vine() -> void:
	var g = _local()
	if not _data.has("vine"):
		return
	if _wait == 2 and g.state != Gorilla.State.SWING:
		_fail("vine grab failed, state %d" % g.state)
	if g.state == Gorilla.State.SWING:
		g.input.move = Vector2(0, 1) if int(_wait / 40) % 2 == 0 else Vector2(0, -1)
		var d: float = g.hand_point().distance_to(_data.vine.anchor())
		_data.max_err = maxf(_data.max_err, d - g._rope_len)
		_data.swing_speed = maxf(_data.get("swing_speed", 0.0), g._swing_vel.length())
	if _wait == 200:
		g.input.jump = true


func _end_vine_test() -> void:
	var g = _local()
	if not _data.has("vine"):
		return
	print("vine: rope stretch max %.3f m, top swing speed %.1f m/s, state after release %d, vel %.1f" % [_data.max_err, _data.get("swing_speed", 0.0), g.state, g.velocity.length()])
	if _data.max_err > 0.15:
		_fail("rope stretched too much")
	elif _data.get("swing_speed", 0.0) < 4.0:
		_fail("swing never built speed")
	else:
		_ok("vine swing holds rope length and builds speed")
	if g.state == Gorilla.State.SWING:
		_fail("did not release vine")
	g.input.move = Vector2.ZERO


func _start_camo_test() -> void:
	var g = _local()
	g.respawn(world.jungle.spawn_points[0])
	g.input.camo = true
	_data.camo_frame_check = true


func _check_camo_ended() -> void:
	var g = _local()
	print("camo: active=%s time=%.1f cooldown=%.1f visual=%.2f" % [g.camo_active, g.camo_time, g.camo_cooldown, g.camo_visual])
	if g.camo_active:
		_fail("camo should have ended after 15 s")
	elif g.camo_cooldown < 18.0 or g.camo_cooldown > 20.0:
		_fail("camo cooldown should be ~20 s, got %.1f" % g.camo_cooldown)
	else:
		_ok("camouflage lasts 15 s then 20 s cooldown")
	g.input.camo = true
	g._tick_camo(0.0)


func _start_ai_test() -> void:
	var g = _local()
	# hand the test player to the AI as well so the whole round plays itself
	var brain := AIBrain.new()
	g.add_child(brain)
	brain.setup(g, world, 99)
	world.mode.start_round()
	world._hole_timer = 8.0
	_data.in_maze = {}
	_data.escaped = {}
	_data.states = {}
	_data.tags = 0
	world.mode.tag_feed.connect(func(_t): _data.tags += 1)


func _end_ai_test() -> void:
	var states := {}
	for g in world.gorillas.values():
		states[g.state] = true
	print("ai: tags=%d phase=%s time_left=%.1f roles=%s" % [_data.tags, world.mode.phase, world.mode.time_left, str(world.mode.roles.values())])
	for g in world.gorillas.values():
		print("  %s pos=%s state=%d role=%s camo_cd=%.1f" % [g.display_name, str(g.global_position.snapped(Vector3.ONE * 0.1)), g.state, g.role, g.camo_cooldown])
	print("maze: %d gorillas fell in, %d escaped" % [_data.in_maze.size(), _data.escaped.size()])
	if _data.in_maze.size() < 1:
		_fail("nobody fell into a black hole")
	else:
		_ok("black holes swallow gorillas into the maze")
	if _data.tags < 1:
		_fail("AI never tagged anyone in 60 s")
	else:
		_ok("AI chased and tagged (%d tags)" % _data.tags)
