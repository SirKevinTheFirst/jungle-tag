extends Node3D
## Renders rain, sunshine and binocular screenshots to user://screens/ (needs a real renderer).

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
	DirAccess.make_dir_recursive_absolute("user://screens")


func _process(_d: float) -> void:
	frame += 1
	if frame == 30:
		world.local.input.yaw = 0.6
		world.local.input.pitch = -0.05
	if frame == 100:
		_save("rain")
		world.weather.raining = false
		world.weather.mix = 0.0
	if frame == 160:
		_save("sunny")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Input.action_press("binoculars")
	if frame == 230:
		_save("binoculars")
		get_tree().quit()


func _save(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screens/%s.png" % n)
	print("saved ", n)
