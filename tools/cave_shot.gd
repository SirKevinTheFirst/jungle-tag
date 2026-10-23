extends Node3D
## Renders screenshots of the waterfall cave to user://screens/ (needs a real renderer).

var world: Node
var frame := 0
var cam: Camera3D
var shots := []


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 4242
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
		world.weather.raining = false
		world.weather.mix = 0.0
		var j: Jungle = world.jungle
		var px := j.plateau_x
		var f := Jungle.SC_FLOOR
		shots = [
			["cave_door", Vector3(px + 3, 2.6, -104.0), Vector3(px, 2.4, -112.0)],
			["cave_grotto", j.sc_center(Vector2i(7, 0)) + Vector3(2.5, 2.4, 1.2), j.sc_center(Vector2i(7, 1)) + Vector3(-2, 1.0, -2)],
			["cave_crystal", j.sc_center(Vector2i(5, 3)) + Vector3(0, 2.6, 0), j.sc_center(Vector2i(10, 4)) + Vector3(0, 0.8, 0)],
			["cave_tunnel", j.sc_center(Vector2i(2, 2)) + Vector3(0, 1.8, 0), j.sc_center(Vector2i(2, 5)) + Vector3(0, 1.5, 0)],
			["cave_outside", Vector3(px + 30, 30, -80), Vector3(px, 14, -118)],
		]
		cam = Camera3D.new()
		cam.far = 400
		add_child(cam)
		cam.current = true
		world.local.visible = false
		world.local.set_physics_process(false)
		world.hud.visible = false
	if frame >= 30 and (frame - 30) % 40 == 0:
		var k := (frame - 30) / 40
		if k > 0:
			_save(shots[k - 1][0])
		if k >= shots.size():
			get_tree().quit()
			return
		cam.global_position = shots[k][1]
		cam.look_at(shots[k][2])


func _save(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screens/%s.png" % n)
	print("saved ", n)
