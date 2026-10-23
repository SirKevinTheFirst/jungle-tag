extends Node3D
## Walks a gorilla through the waterfall cave: in through the doorway behind the waterfall,
## along the tunnels and out of each hidden side exit, and to the ladder shaft.
##   godot --headless --fixed-fps 60 --path . res://tools/cave_test.tscn

var world: Node
var g: Gorilla
var j: Jungle
var frame := 0
var failures := 0
var routes := []
var route_i := -1
var path: Array = []
var wp := 0
var t := 0


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 4242
	game.config.max_players = 2
	game.config.fill_bots = false
	game.config.bot_count = 0
	net.players = {1: {"name": "Tester", "color": Color.RED}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	world._round_started = true
	add_child(world)


func _check(ok: bool, what: String) -> void:
	print(("ok: " if ok else "FAIL: ") + what)
	if not ok:
		failures += 1


func _bfs(from: Vector2i, to: Vector2i) -> Array:
	var dirs := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var prev := {from: from}
	var q: Array[Vector2i] = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == to:
			break
		for d in 4:
			if j.secret_cave_open[c.x][c.y][d]:
				var nb: Vector2i = c + dirs[d]
				if not prev.has(nb):
					prev[nb] = c
					q.append(nb)
	if not prev.has(to):
		return []
	var out := [to]
	while out[0] != from:
		out.push_front(prev[out[0]])
	return out


func _start_route(i: int) -> void:
	route_i = i
	var r: Dictionary = routes[i]
	path = [Vector3(j.plateau_x, 0, -108.0)]   # in front of the doorway, on the ledge
	for c in _bfs(Vector2i(7, 0), r.cell):
		path.append(j.sc_center(c))
	path.append(r.out)
	g.respawn(Vector3(j.plateau_x, Jungle.SC_FLOOR + 0.4, -107.6))
	wp = 0
	t = 0


func _process(_d: float) -> void:
	frame += 1
	if frame == 10:
		j = world.jungle
		g = world.local
		g.control = Gorilla.Ctrl.AI
		world.mode.phase = "warmup"
		world._hole_timer = 9999.0
		var px := j.plateau_x
		_check(j.secret_cave_spots.size() >= 4, "cave has dead ends to hide in (%d)" % j.secret_cave_spots.size())
		# the roof is solid over the grotto
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		var c := j.sc_center(Vector2i(7, 1))
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3(0, 2, 0), c + Vector3(0, 40, 0)))
		_check(not hit.is_empty() and hit.position.y < Jungle.SC_FLOOR + Jungle.SC_CEIL + 0.2, "grotto has a rock roof")
		for e in Jungle.SC_EXITS:
			var ec := j.sc_center(Vector2i(e[0], e[1]))
			routes.append({"name": "side exit %s" % ("east" if e[2] > 0 else "west"), "cell": Vector2i(e[0], e[1]), "out": Vector3(px + e[2] * 46.0, 0, ec.z)})
		var sc := j.sc_center(Jungle.SC_SHAFT)
		routes.append({"name": "ladder shaft", "cell": Jungle.SC_SHAFT, "out": sc + Vector3(0, 0, 0.6)})
		_start_route(0)
	if route_i < 0 or route_i >= routes.size():
		return
	t += 1
	var target: Vector3 = path[wp]
	var to := target - g.global_position
	to.y = 0
	if to.length() < 1.0:
		wp += 1
		if wp >= path.size():
			_check(true, "walked in behind the waterfall and reached the %s (%.0f s)" % [routes[route_i].name, t / 60.0])
			_next()
			return
		target = path[wp]
		to = target - g.global_position
		to.y = 0
	g.input.yaw = atan2(-to.x, -to.z)
	g.input.move = Vector2(0, 1)
	g.input.sprint = false
	if t > 60 * 60:
		_check(false, "stuck going to the %s at %s (waypoint %d of %d)" % [routes[route_i].name, g.global_position, wp, path.size()])
		_next()


func _next() -> void:
	if route_i + 1 < routes.size():
		_start_route(route_i + 1)
	else:
		route_i = 99
		print("== %s (%d failures) ==" % ["PASSED" if failures == 0 else "FAILED", failures])
		get_tree().quit(1 if failures > 0 else 0)
