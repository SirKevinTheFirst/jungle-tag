extends Node3D
## Puts a gorilla in every cell of the black hole maze and does everything a player might
## (walk into walls, sprint, jump, grab with both hands) and checks it never rises off the floor.
##   godot --headless --fixed-fps 60 --path . res://tools/maze_float_test.tscn

var world: Node
var g: Gorilla
var frame := 0
var cell := 0
var t := 0
var worst := -999.0
var worst_info := ""
var failures := 0


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


func _physics_process(_d: float) -> void:
	frame += 1
	if frame < 10:
		return
	if frame == 10:
		g = world.local
		g.control = Gorilla.Ctrl.AI
		world._hole_timer = 9999.0
		var sh: Gorilla = world.npcs[world.SHADOW_ID]
		sh.set_physics_process(false)
		sh.global_position = Vector3(500, -200, 500)
		_place()
	t += 1
	var m: Maze = world.maze
	if t >= 180:
		cell += 1
		if cell >= Maze.N * Maze.N:
			var ok := worst < 0.6
			print(("ok: " if ok else "FAIL: ") + "never floats in the black hole maze (highest when not jumping: %s)" % worst_info)
			print("== %s ==" % ("PASSED" if ok else "FAILED"))
			get_tree().quit(0 if ok else 1)
			return
		_place()
	# a mix of actions, changing every half second
	var phase := (t / 30) % 6
	g.input.yaw = (t / 30) * 1.3
	g.input.move = Vector2(0, 1) if phase != 5 else Vector2.ZERO
	g.input.sprint = phase >= 2
	g.input.jump = phase == 3 and t % 30 == 1
	g.input.jump_held = phase == 3
	g.input.grab_l = phase == 4
	g.input.grab_r = phase == 4
	g.input.grab_l_pressed = phase == 4 and t % 30 == 1
	g.input.grab_r_pressed = phase == 4 and t % 30 == 15
	var y := g.global_position.y - Maze.ORIGIN.y
	# a jump goes about 1.3 m up; anything higher, or staying up, is floating
	if not m.contains(g.global_position):
		return   # walked onto the exit and went back up to the jungle; fine
	if g.state == Gorilla.State.SWIM:
		worst = 99.0
		worst_info = "cell %d is SWIMMING (slow and floaty)" % cell
	if phase != 3 and t % 30 > 20 and y > worst:
		worst = y
		worst_info = "cell %d state %d y %.2f" % [cell, g.state, y]


func _place() -> void:
	var m: Maze = world.maze
	var c := Vector2i(cell % Maze.N, cell / Maze.N)
	if c == m.exit_cell:
		c = Vector2i(0, 0)
	g.respawn(m.cell_center(c) + Vector3(0, 0.3, 0))
	t = 0
