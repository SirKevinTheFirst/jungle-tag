extends Node3D
## Renders a screenshot inside the black hole maze to user://screens/ (needs a real renderer).

var world: Node
var frame := 0


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 4242
	game.config.mode = Game.MODE_MAZE
	game.config.max_players = 2
	game.config.fill_bots = false
	game.config.bot_count = 0
	net.players = {1: {"name": "Camera", "color": Color("c9772b")}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	DirAccess.make_dir_recursive_absolute("user://screens")


func _process(_d: float) -> void:
	frame += 1
	if frame == 20:
		world.local.input.yaw = PI * 0.75
		world.local.input.pitch = -0.1
		Net.send_chat("where is the exit??")
		world.hud.chat_line("Banjo [AI]", Color("6fb3ff"), "follow me, i think it's this way")
	if frame == 45:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://screens/maze.png")
		print("saved maze")
		get_tree().quit()
