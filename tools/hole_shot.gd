extends Node3D
## Renders black hole screenshots (near and far) to user://screens/ (needs a real renderer).

var world: Node
var frame := 0


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 4242
	game.config.max_players = 6
	net.players = {1: {"name": "Camera", "color": Color("c9772b")}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	world._hole_timer = 9999.0
	DirAccess.make_dir_recursive_absolute("user://screens")


func _hole_at(dist: float, id: int) -> void:
	var l: Node3D = world.local
	var fwd := Vector3(-sin(l.input.yaw), 0, -cos(l.input.yaw))
	var p: Vector3 = l.global_position + fwd * dist
	p.y = world.jungle.ground_height(p.x, p.z) + 0.05
	world.on_game_event("hole_open", {"id": id, "pos": p, "life": 99.0})


func _process(_d: float) -> void:
	frame += 1
	if frame == 30:
		world.local.input.yaw = 0.6
		world.local.input.pitch = -0.1
		world.local.frozen = true
		_hole_at(14.0, 500)
	if frame == 110:
		_save("hole_near")
		world.holes[500].queue_free()
		_hole_at(55.0, 501)
	if frame == 190:
		_save("hole_far")
		get_tree().quit()


func _save(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screens/%s.png" % n)
	print("saved ", n)
