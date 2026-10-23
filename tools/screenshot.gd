extends Node3D
## Renders a few screenshots of a solo match (needs a real renderer, e.g. under xvfb):
##   godot --path . res://tools/screenshot.tscn
## Images are written to user://screens/.

var world: Node
var frame := 0
var shots := [
	[Vector3(10, 30, 60), Vector3(0, 8, 0)],
	[Vector3(-60, 18, 95), Vector3(-92, 4, 60)],
]
var shot := 0


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 4242
	game.config.max_players = 6
	net.players = {1: {"name": "Camera", "color": Color("c9772b")}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	DirAccess.make_dir_recursive_absolute("user://screens")


func _process(_d: float) -> void:
	frame += 1
	if frame == 30:
		# a third-person view behind the player
		world.local.input.yaw = 0.6
		world.local.input.pitch = -0.15
		world.local.camo_active = false
	if frame == 90:
		_save("player")
		world.local.apply_camo_state(true, 15.0, 0.0)
	if frame == 160:
		_save("player_camo")
		var cam := Camera3D.new()
		cam.far = 400
		add_child(cam)
		cam.current = true
		cam.global_position = shots[0][0]
		cam.look_at(shots[0][1])
	if frame == 220:
		_save("overview")
		var cam := get_viewport().get_camera_3d()
		var p: Vector3 = world.jungle.waterfall_view_pos()
		cam.global_position = p
		cam.look_at(Vector3(world.jungle.plateau_x, 10, -108))
	if frame == 280:
		_save("waterfall")
		var cam := get_viewport().get_camera_3d()
		cam.global_position = shots[1][0]
		cam.look_at(shots[1][1])
	if frame == 340:
		_save("cave")
		var t: Dictionary = world.jungle.trees[5]
		var cam := get_viewport().get_camera_3d()
		cam.global_position = t.pos + Vector3(14, t.height * 0.5, 14)
		cam.look_at(t.pos + Vector3(0, t.height * 0.45, 0))
	if frame == 400:
		_save("tree")
		get_tree().quit()


func _save(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screens/%s.png" % n)
	print("saved ", ProjectSettings.globalize_path("user://screens/%s.png" % n))
