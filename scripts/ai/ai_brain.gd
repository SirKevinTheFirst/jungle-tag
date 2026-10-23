class_name AIBrain
extends Node
## Drives a bot gorilla on the host by filling in its input each frame, just like a player.
## Chases, flees, climbs trees and ladders, swings on vines, hides in leaves and camouflages.

const THINK_RATE := 0.2
const SIGHT_RANGE := 58.0
const FLEE_RANGE := 24.0

var g: Gorilla
var world: Node
var rng := RandomNumberGenerator.new()

var _think := 0.0
var _goal := Vector3.ZERO
var _has_goal := false
var _goal_kind := ""          # chase, flee, hide, wander, climb_tree
var _target_id := -1
var _last_seen := {}          # id -> [pos, time]
var _hide_spot := {}
var _hide_reached := false
var _climb_tree := {}
var _climb_height := 0.0
var _grab_toggle := 0.0
var _swing_time := 0.0
var _stuck_check := 0.0
var _stuck_pos := Vector3.ZERO
var _unstick_time := 0.0
var _unstick_dir := Vector3.ZERO
var _vine_try := 0.0
var _crouch := false
var _sprint := true
var _reaction := 0.0
var _time := 0.0
var _jump_cool := 0.0


func setup(p_g: Gorilla, p_world: Node, p_seed: int) -> void:
	g = p_g
	world = p_world
	rng.seed = p_seed
	_think = rng.randf() * THINK_RATE
	_reaction = rng.randf_range(0.15, 0.45)


func _physics_process(delta: float) -> void:
	if g == null or not is_instance_valid(g):
		return
	_time += delta
	if world.maze and world.maze.contains(g.global_position):
		_maze_escape()
		return
	_think -= delta
	_jump_cool -= delta
	if _think <= 0.0:
		_think = THINK_RATE
		_decide()
	_steer(delta)


## Inside the black hole maze: follow the shortest path to the exit.
func _maze_escape() -> void:
	var maze: Maze = world.maze
	var inp := g.input
	inp.sprint = true
	inp.crouch = false
	inp.grab_l = false
	inp.grab_r = false
	if g.stun_time > 0.0:
		inp.move = Vector2.ZERO
		return
	var cell := maze.world_to_cell(g.global_position)
	var target := maze.exit_pos() if cell == maze.exit_cell else maze.cell_center(maze.next_step(cell, maze.exit_cell))
	var to := target - g.global_position
	to.y = 0.0
	inp.yaw = atan2(-to.x, -to.z)
	inp.move = Vector2(0, 1)


# ======================================================================== decisions
func _decide() -> void:
	var gm: GameMode = world.mode
	if g.frozen or g.stun_time > 0.0:
		_has_goal = false
		return
	var my_pos := g.global_position
	_crouch = false
	_sprint = true
	if g.is_tagger():
		_decide_tagger(gm, my_pos)
	else:
		_decide_runner(gm, my_pos)


func _decide_tagger(gm: GameMode, my_pos: Vector3) -> void:
	var best_id := -1
	var best_score := INF
	for id in world.gorillas:
		var o: Gorilla = world.gorillas[id]
		if o == g or o.is_tagger():
			continue
		if can_see(g, o):
			_last_seen[id] = [o.global_position, _time]
			var d := my_pos.distance_to(o.global_position)
			if gm._no_tagback.get(g.net_id, -1) == id:
				d += 1000.0  # can't tag them back, so chase anyone else first
			# stick with the current target a little to avoid dithering
			var s := d * (0.75 if id == _target_id else 1.0)
			if s < best_score:
				best_score = s
				best_id = id
	if best_id != -1:
		_target_id = best_id
		var o: Gorilla = world.gorillas[best_id]
		var lead := o.velocity if o.control != Gorilla.Ctrl.REMOTE else o._net_vel
		var d := my_pos.distance_to(o.global_position)
		_set_goal(o.global_position + lead * clampf(d / 12.0, 0.0, 0.8), "chase")
		# occasionally sneak up with camouflage
		if d > 10.0 and d < 25.0 and g.camo_cooldown <= 0.0 and not g.camo_active and rng.randf() < 0.03:
			g.input.camo = true
		return
	# lost sight: go to the last place we saw someone
	var recent := -1
	var recent_t := -INF
	for id in _last_seen:
		if world.gorillas.has(id) and _time - _last_seen[id][1] < 7.0 and _last_seen[id][1] > recent_t:
			recent_t = _last_seen[id][1]
			recent = id
	if recent != -1 and my_pos.distance_to(_last_seen[recent][0]) > 2.5:
		_set_goal(_last_seen[recent][0], "chase")
		return
	# search: hide-and-seek seekers check hiding spots; others drift towards the nearest runner
	if not _has_goal or my_pos.distance_to(_goal) < 3.0 or _goal_kind != "search":
		if gm.mode == Game.MODE_HIDE_SEEK and rng.randf() < 0.7:
			var spot := _random_spot(my_pos, 60.0, false)
			if not spot.is_empty():
				_set_goal(spot.pos, "search")
				return
		var nearest: Gorilla = null
		var nd := INF
		for id in world.gorillas:
			var o: Gorilla = world.gorillas[id]
			if o != g and not o.is_tagger():
				var d := my_pos.distance_to(o.global_position)
				if d < nd:
					nd = d
					nearest = o
		if nearest:
			# a rough guess of where they are, not their exact position
			var fuzz := Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
			_set_goal(nearest.global_position + fuzz, "search")
		else:
			_wander(my_pos)


func _decide_runner(gm: GameMode, my_pos: Vector3) -> void:
	var threat: Gorilla = null
	var td := INF
	for id in world.gorillas:
		var o: Gorilla = world.gorillas[id]
		if o == g or not o.is_tagger():
			continue
		var d := my_pos.distance_to(o.global_position)
		if d < td and (d < 6.0 or can_see(g, o)):
			td = d
			threat = o
	var hiding_mode := gm.mode == Game.MODE_HIDE_SEEK
	# camouflage when danger is near
	if threat and td < 20.0 and not g.camo_active and g.camo_cooldown <= 0.0:
		var chance := 0.5 if hiding_mode else 0.18
		if rng.randf() < chance:
			g.input.camo = true
	if threat and (td < (7.0 if (hiding_mode and _hide_reached) else FLEE_RANGE)):
		_hide_reached = false
		var away := (my_pos - threat.global_position)
		away.y = 0
		away = away.normalized()
		# bias away from the map edge
		var to_center := (-my_pos * Vector3(1, 0, 1)).normalized()
		var edge := clampf((maxf(absf(my_pos.x), absf(my_pos.z)) - 100.0) / 30.0, 0.0, 1.0)
		var dir := (away + to_center * edge * 1.5 + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))).normalized()
		# climb a nearby tree when the chaser is still a little way off
		if td > 6.0 and td < 16.0 and rng.randf() < 0.12:
			var tree := _nearest_tree(my_pos, 9.0)
			if not tree.is_empty():
				_start_tree_climb(tree, tree.pos.y + tree.height * rng.randf_range(0.3, 0.55))
				return
		_set_goal(my_pos + dir * 18.0, "flee")
		return
	if hiding_mode or rng.randf() < 0.02 or _goal_kind == "hide":
		if _hide_spot.is_empty() or (_hide_reached and rng.randf() < 0.01):
			_hide_spot = _random_spot(my_pos, 80.0, true)
			_hide_reached = false
		if not _hide_spot.is_empty():
			var sp: Vector3 = _hide_spot.pos
			if my_pos.distance_to(sp) < maxf(1.5, _hide_spot.radius * 0.6):
				_hide_reached = true
				_has_goal = false
				_crouch = true
				if threat and td < 25.0 and not g.camo_active and g.camo_cooldown <= 0.0:
					g.input.camo = true
				return
			_set_goal(sp, "hide")
			_sprint = not hiding_mode or gm.phase == "hide"
			return
	if not _has_goal or my_pos.distance_to(_goal) < 3.0:
		_wander(my_pos)


func _wander(my_pos: Vector3) -> void:
	var a := rng.randf() * TAU
	var r := rng.randf_range(10.0, 35.0)
	var p := my_pos + Vector3(cos(a) * r, 0, sin(a) * r)
	p.x = clampf(p.x, -120.0, 120.0)
	p.z = clampf(p.z, -100.0, 125.0)
	p.y = world.jungle.ground_height(p.x, p.z)
	_set_goal(p, "wander")
	_sprint = rng.randf() < 0.4


func _set_goal(p: Vector3, kind: String) -> void:
	_goal = p
	_has_goal = true
	_goal_kind = kind


func _random_spot(near: Vector3, radius: float, for_hiding: bool) -> Dictionary:
	var spots: Array = world.jungle.hide_spots
	var choices := []
	for s in spots:
		var p: Vector3 = s.pos
		if p.distance_to(near) > radius:
			continue
		var gh: float = world.jungle.ground_height(p.x, p.z)
		var high := p.y - gh > 3.0
		if high and s.kind != "treehouse":
			continue  # canopies need fancy climbing; bots stick to reachable spots
		choices.append(s)
	if choices.is_empty():
		return {}
	var s: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
	if for_hiding and s.kind == "treehouse":
		# head for the ladder instead
		return s
	return s


func _nearest_tree(p: Vector3, max_d: float) -> Dictionary:
	var best := {}
	var bd := max_d
	for t in world.jungle.trees:
		var d: float = Vector2(t.pos.x, t.pos.z).distance_to(Vector2(p.x, p.z)) - t.radius
		if d < bd:
			bd = d
			best = t
	return best


func _start_tree_climb(tree: Dictionary, height: float) -> void:
	_climb_tree = tree
	_climb_height = height
	_set_goal(tree.pos, "climb_tree")


## Could 'obs' notice 'tgt'? Camouflage, foliage and crouching all shrink the sight range.
func can_see(obs: Gorilla, tgt: Gorilla) -> bool:
	var a := obs.global_position + Vector3(0, 1.3, 0)
	var b := tgt.global_position + Vector3(0, 0.9, 0)
	var d := a.distance_to(b)
	var stealth := tgt.stealth()
	var sight := SIGHT_RANGE * (1.0 - stealth)
	if d > maxf(sight, 2.5):
		return false
	var q := PhysicsRayQueryParameters3D.create(a, b, 1, [obs.get_rid(), tgt.get_rid()])
	var hit := obs.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()


# ======================================================================== steering
func _steer(delta: float) -> void:
	var inp := g.input
	inp.move = Vector2.ZERO
	inp.sprint = _sprint
	inp.crouch = _crouch and g.state == Gorilla.State.GROUND
	inp.grab_l = false
	inp.grab_r = false
	inp.jump_held = false
	if not _has_goal or g.frozen or g.stun_time > 0.0:
		return
	var pos := g.global_position
	var to_goal := _goal - pos
	var flat := Vector3(to_goal.x, 0, to_goal.z)
	var dist := flat.length()
	var dir := flat / maxf(dist, 0.001)

	match g.state:
		Gorilla.State.CLIMB:
			_steer_climb(delta, dir)
			return
		Gorilla.State.SWING:
			_steer_swing(delta, dir)
			return

	# tree climbing goal: walk to the trunk and grab it
	if _goal_kind == "climb_tree" and not _climb_tree.is_empty():
		var tc: Vector3 = _climb_tree.pos
		var tflat := Vector3(tc.x - pos.x, 0, tc.z - pos.z)
		var td: float = tflat.length() - _climb_tree.radius
		dir = tflat.normalized()
		if td < 1.3:
			_face(dir, 0.0)
			inp.grab_l = true
			inp.grab_l_pressed = true
			inp.move = Vector2(0, 1)
			return

	# a chased gorilla up a tree: climb after it
	if _goal_kind == "chase" and _goal.y - pos.y > 4.0 and dist < 9.0 and _climb_tree.is_empty():
		var tree := _nearest_tree(_goal, 6.0)
		if not tree.is_empty():
			_start_tree_climb(tree, _goal.y + 0.5)
			return

	if _unstick_time > 0.0:
		_unstick_time -= delta
		dir = _unstick_dir
	else:
		dir = _avoid(pos, dir)
	_face(dir, 0.0)
	var arrive := dist < 1.2 and _goal_kind != "chase" and _goal_kind != "flee"
	if not arrive:
		inp.move = Vector2(0, 1)
	# hop over low obstacles and off ledges
	if g.state == Gorilla.State.GROUND and _jump_cool <= 0.0:
		if _need_jump(pos, dir):
			inp.jump = true
			_jump_cool = 0.6
	# tagger lunges with a swipe when close
	if _goal_kind == "chase" and dist < 2.6 and rng.randf() < 0.3:
		inp.grab_r_pressed = true
	# vines along the way
	_vine_try -= delta
	if _vine_try <= 0.0 and g.state == Gorilla.State.AIR:
		inp.vine = true
		_vine_try = 0.15
	elif g.state == Gorilla.State.GROUND and _vine_try <= 0.0 and g.horizontal_speed() > 5.0 and dist > 12.0:
		if _vine_ahead(pos, dir):
			inp.jump = true
			_vine_try = 0.1
			_swing_time = 0.0
	# stuck detection
	_stuck_check -= delta
	if _stuck_check <= 0.0:
		_stuck_check = 1.5
		if not arrive and pos.distance_to(_stuck_pos) < 0.8 and g.state != Gorilla.State.SWIM:
			_unstick_time = 1.0
			_unstick_dir = dir.rotated(Vector3.UP, rng.randf_range(1.2, 2.4) * (1.0 if rng.randf() < 0.5 else -1.0))
			inp.jump = true
		_stuck_pos = pos


func _steer_climb(delta: float, goal_dir: Vector3) -> void:
	var inp := g.input
	inp.grab_l = true
	inp.grab_r = true
	inp.sprint = true
	var pos := g.global_position
	var target_h := _climb_height if not _climb_tree.is_empty() else _goal.y
	if pos.y < target_h - 0.5:
		inp.move = Vector2(0, 1)
		_grab_toggle -= delta
		if _grab_toggle <= 0.0:
			_grab_toggle = 0.28
			if rng.randf() < 0.5:
				inp.grab_l_pressed = true
			else:
				inp.grab_r_pressed = true
		_stuck_check -= delta
		if _stuck_check <= 0.0:
			_stuck_check = 1.2
			if pos.distance_to(_stuck_pos) < 0.4:
				# blocked by a branch: shuffle sideways around the trunk
				_unstick_time = 0.8
			_stuck_pos = pos
		if _unstick_time > 0.0:
			_unstick_time -= delta
			inp.move = Vector2(1, 0.3)
	else:
		# at height: leap off towards the goal (or away from the chaser)
		var jump_dir := goal_dir
		if _goal_kind == "climb_tree" or _goal_kind == "flee":
			jump_dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		_face(jump_dir, 0.0)
		inp.jump = true
		_climb_tree = {}
		_has_goal = false
		_think = 0.4


func _steer_swing(delta: float, goal_dir: Vector3) -> void:
	var inp := g.input
	_swing_time += delta
	_face(goal_dir, 0.0)
	inp.move = Vector2(0, 1)
	inp.sprint = true
	var v := g._swing_vel
	var hv := Vector3(v.x, 0, v.z)
	if (_swing_time > 0.6 and hv.dot(goal_dir) > 7.0 and v.y > -1.0) or _swing_time > 3.0:
		inp.jump = true
		_swing_time = 0.0
		_vine_try = 0.8


func _face(dir: Vector3, pitch: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	g.input.yaw = atan2(-dir.x, -dir.z)
	g.input.pitch = pitch


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [g.get_rid()])
	return g.get_world_3d().direct_space_state.intersect_ray(q)


func _avoid(pos: Vector3, dir: Vector3) -> Vector3:
	var eye := pos + Vector3(0, 1.1, 0)
	if _ray(eye, eye + dir * 2.4).is_empty():
		return dir
	for ang in [0.6, -0.6, 1.2, -1.2, 1.9, -1.9]:
		var d := dir.rotated(Vector3.UP, ang)
		if _ray(eye, eye + d * 2.4).is_empty():
			return d
	return -dir


func _need_jump(pos: Vector3, dir: Vector3) -> bool:
	var knee := pos + Vector3(0, 0.45, 0)
	var head := pos + Vector3(0, 1.6, 0)
	var low := _ray(knee, knee + dir * 1.4)
	if not low.is_empty() and _ray(head, head + dir * 1.6).is_empty():
		return true
	# ledge ahead while up high: jump across
	var ahead := pos + dir * 1.6 + Vector3(0, 0.5, 0)
	var floor_hit := _ray(ahead, ahead + Vector3.DOWN * 2.5)
	if floor_hit.is_empty():
		var gh: float = world.jungle.ground_height(pos.x, pos.z)
		if pos.y - gh > 2.0:
			return true
	return false


func _vine_ahead(pos: Vector3, dir: Vector3) -> bool:
	var hand := pos + Vector3(0, 2.0, 0)
	for v in world.jungle.vines:
		var a: Vector3 = v.anchor()
		if absf(a.x - pos.x) > 6.0 or absf(a.z - pos.z) > 6.0:
			continue
		var cp: Vector3 = v.closest_point(hand + dir * 2.5)
		if cp.distance_to(hand + dir * 2.5) < 2.0 and v.grabbed_by == null:
			return true
	return false
