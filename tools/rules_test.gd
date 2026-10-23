extends Node3D
## Headless checks for match rules: multiple taggers, no tag-backs, weather changes.
##   godot --headless --fixed-fps 60 --path . res://tools/rules_test.tscn

var world: Node
var frame := 0
var failures := 0


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.mode = 0
	game.config.max_players = 8
	game.config.fill_bots = true
	game.config.seed = 4242
	game.config.taggers = 3
	net.players = {1: {"name": "Tester", "color": Color.RED}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	world._round_started = true
	add_child(world)


func _check(ok: bool, what: String) -> void:
	print(("ok: " if ok else "FAIL: ") + what)
	if not ok:
		failures += 1


func _process(_d: float) -> void:
	frame += 1
	if frame == 10:
		var gm: GameMode = world.mode
		gm.start_round()
		var its := gm.roles.values().filter(func(r): return r == "it").size()
		_check(its == 3, "3 taggers chosen when the option is 3 (got %d)" % its)
		# freeze everyone so only our staged tags happen
		for id in world.gorillas:
			world.gorillas[id].frozen = true
			world.gorillas[id].set_physics_process(false)
		gm.phase = "play"
		gm.time_left = 999.0
		var it_id := -1
		var runners := []
		for id in gm.roles:
			if gm.roles[id] == "it" and it_id == -1:
				it_id = id
			elif gm.roles[id] == "runner":
				runners.append(id)
		var a: int = runners[0]
		var b: int = runners[1]
		# tagger tags a
		gm._do_tag(it_id, a)
		_check(gm.roles[a] == "it" and gm.roles[it_id] == "runner", "tag passes IT to the runner")
		gm._immune.clear()
		for id in world.gorillas:
			world.gorillas[id].stun_time = 0.0
			world.gorillas[id].frozen = false
			world.gorillas[id].global_position = Vector3(200 + id % 97 * 7, 0, 200)
		world.gorillas[a].global_position = Vector3(0, 5, 0)
		world.gorillas[it_id].global_position = Vector3(0.5, 5, 0)
		gm._check_tags()
		_check(gm.roles[it_id] == "runner", "no tag-back on the gorilla who just tagged you")
		world.gorillas[it_id].global_position = Vector3(50, 5, 0)
		world.gorillas[b].global_position = Vector3(0.5, 5, 0)
		gm._check_tags()
		_check(gm.roles[b] == "it", "tagging someone different works")
		_check(world.weather.raining and world.weather.mix > 0.99, "matches start rainy")
		world.weather._timer = 0.05
	if frame == 30:
		_check(not world.weather.raining, "weather turns sunny after its timer")
	if frame == 30 + 60 * 11:
		_check(world.weather.mix < 0.01, "sky fades fully to sunshine")
		print("== %s (%d failures) ==" % ["PASSED" if failures == 0 else "FAILED", failures])
		get_tree().quit(1 if failures > 0 else 0)
