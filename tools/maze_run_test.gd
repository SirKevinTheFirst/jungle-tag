extends Node3D
## Black Hole Maze Run and chat checks.
##   godot --headless --fixed-fps 60 --path . res://tools/maze_run_test.tscn

var world: Node
var frame := 0
var failures := 0


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 4242
	game.config.mode = Game.MODE_MAZE
	game.config.max_players = 6
	game.config.fill_bots = true
	game.config.round_time = 60
	net.players = {1: {"name": "Tester", "color": Color.RED}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)


func _check(ok: bool, what: String) -> void:
	print(("ok: " if ok else "FAIL: ") + what)
	if not ok:
		failures += 1


func _physics_process(_d: float) -> void:
	frame += 1
	if frame == 60 * 3:
		var all_in := true
		for id in world.gorillas:
			if not world.maze.contains(world.gorillas[id].global_position):
				all_in = false
		_check(all_in, "everyone starts inside the black hole maze")
		_check(not world.mode.roles.values().has("it"), "no gorilla is a tagger (only the Shadow)")
		world.local.control = Gorilla.Ctrl.AI   # let a brain drive our gorilla too
		var brain := AIBrain.new()
		world.local.add_child(brain)
		brain.setup(world.local, world, 7)
		Net.send_chat("hello everyone")
	if frame == 60 * 7:
		var lines: int = world.hud._chat_box.get_child_count()
		_check(lines >= 2, "chat message shows, and a bot answered (%d lines)" % lines)
		_check(world.local._bubble != null and world.local._bubble.text == "hello everyone", "chat shows over the gorilla's head")
		Net.send_chat("purple monkey dishwasher")
	if frame == 60 * 10:
		var lines: int = world.hud._chat_box.get_child_count()
		_check(lines >= 4, "any message gets a bot reply (%d lines)" % lines)
		_check(BotChat.topic_of("this is fun") == "any", "'this' doesn't count as 'hi'")
		_check(BotChat.topic_of("where is the exit") == "where", "topic replies work")
		_check(BotChat.topic_of("ur such a noob") == "insult", "trash talk gets noticed")
		var styled := BotChat.make_line("hi %s", {"s": "Kev"}, "Bo", "Mango", "hype")
		_check(styled.to_lower().begins_with("hi kev"), "lines get styled (%s)" % styled)
	if world.mode.phase == "end" and frame > 60 * 11:
		var total := 0
		for id in world.mode.stats:
			total += int(world.mode.stats[id].get("escapes", 0))
		_check(total > 0, "gorillas escaped and scored (%d escapes)" % total)
		_check(world.mode.last_result.contains("escaped the most"), "round result: " + world.mode.last_result)
		_check(world.holes.is_empty(), "no black holes on the surface in maze run")
		print("== %s (%d failures) ==" % ["PASSED" if failures == 0 else "FAILED", failures])
		get_tree().quit(1 if failures > 0 else 0)
	if frame > 60 * 120:
		_check(false, "round never ended")
		get_tree().quit(1)
