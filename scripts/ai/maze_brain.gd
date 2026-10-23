class_name MazeBrain
extends Node
## Drives "The Shadow", the tagger that prowls the black hole maze (host only).

var g: Gorilla
var world: Node
var rng := RandomNumberGenerator.new()
var _think := 0.0
var _patrol := Vector2i(5, 5)
var _waypoint := Vector3.ZERO


func setup(p_g: Gorilla, p_world: Node) -> void:
	g = p_g
	world = p_world
	rng.seed = 777


func _physics_process(delta: float) -> void:
	if g == null:
		return
	var maze: Maze = world.maze
	var inp := g.input
	_think -= delta
	if _think <= 0.0:
		_think = 0.25
		var my_cell := maze.world_to_cell(g.global_position)
		var target_cell := _patrol
		var target_pos := Vector3.ZERO
		var best := INF
		for id in world.gorillas:
			var o: Gorilla = world.gorillas[id]
			if not maze.contains(o.global_position):
				continue
			var d := o.global_position.distance_to(g.global_position)
			if d < best:
				best = d
				target_cell = maze.world_to_cell(o.global_position)
				target_pos = o.global_position
		if best == INF and my_cell == _patrol:
			_patrol = Vector2i(rng.randi_range(0, Maze.N - 1), rng.randi_range(0, Maze.N - 1))
			target_cell = _patrol
		if best < INF and target_cell == my_cell:
			_waypoint = target_pos
		else:
			_waypoint = maze.cell_center(maze.next_step(my_cell, target_cell))
		inp.sprint = false  # walks, so a sprinting gorilla can always outrun it
	var to := _waypoint - g.global_position
	to.y = 0.0
	if to.length() > 0.3:
		inp.yaw = atan2(-to.x, -to.z)
		inp.move = Vector2(0, 1)
	else:
		inp.move = Vector2.ZERO
