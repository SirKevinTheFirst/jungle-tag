extends Node3D
## Headless check: the 60 s black hole opens just ahead of where the local player looks.

var world: Node
var frame := 0


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 4242
	game.config.max_players = 6
	net.players = {1: {"name": "Tester", "color": Color("c9772b")}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	world._round_started = true
	add_child(world)


func _process(_d: float) -> void:
	frame += 1
	if frame == 20:
		world.local.input.yaw = 1.1
		world.local.frozen = true
		world._hole_timer = 0.5
		world.mode.phase = "play"
	if frame == 120:
		var l: Node3D = world.local
		var ok := false
		for hid in world.holes:
			var to: Vector3 = world.holes[hid].global_position - l.global_position
			to.y = 0
			var fwd := Vector3(-sin(l.input.yaw), 0, -cos(l.input.yaw))
			print("hole dist %.1f m, facing dot %.2f" % [to.length(), fwd.dot(to.normalized())])
			ok = ok or (to.length() < 12.0 and fwd.dot(to.normalized()) > 0.7)
		print("HOLE IN FRONT: ", "PASS" if ok else "FAIL")
		get_tree().quit(0 if ok else 1)
