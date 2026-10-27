extends Node3D
## Plays one round of a tag mode with AI gorillas and checks its rules.
##   godot --headless --fixed-fps 60 --path . res://tools/modes_test.tscn -- <mode number>

var world: Node
var frame := 0
var failures := 0
var mode := 4
var feed: Array = []
var result := ""
var saw := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = int(args[0])
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 900 + mode
	game.config.mode = mode
	game.config.black_holes = false
	game.config.max_players = 8
	game.config.fill_bots = true
	game.config.round_time = 120
	game.config.taggers = 0
	net.players = {1: {"name": "Tester", "color": Color.RED}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	world.mode.tag_feed.connect(func(t): feed.append(t))
	print("mode: ", Game.mode_name(mode))


func _check(ok: bool, what: String) -> void:
	print(("ok: " if ok else "FAIL: ") + what)
	if not ok:
		failures += 1


func _physics_process(_d: float) -> void:
	frame += 1
	var gm: GameMode = world.mode
	if frame == 60:
		world.local.control = Gorilla.Ctrl.AI
		var brain := AIBrain.new()
		brain.name = "Brain"
		world.local.add_child(brain)
		brain.setup(world.local, world, 5)
	if gm.phase == "play":
		for r in gm.roles.values():
			saw[r] = true
		match mode:
			Game.MODE_HUNT:
				# every gorilla still in has exactly one hunter
				var alive := gm.roles.keys().filter(func(i): return gm.roles[i] == "hunter")
				var hunted := {}
				for h in alive:
					hunted[gm.hunt_target(h)] = int(hunted.get(gm.hunt_target(h), 0)) + 1
				for h in alive:
					if alive.size() > 1 and int(hunted.get(h, 0)) != 1:
						_check(false, "hunt circle broken for %d" % h)
						get_tree().quit(1)
	if gm.phase == "end" and result == "":
		result = gm.last_result
		print("result: ", result, "  (after %.0f s)" % (frame / 60.0))
		print("feed: ", feed.slice(0, 8))
		_finish()
	if frame > 60 * 135 and result == "":
		_check(false, "round never ended")
		_finish()


func _finish() -> void:
	var gm: GameMode = world.mode
	_check(result != "", "round ended with a result")
	match mode:
		Game.MODE_CASUAL:
			_check(feed.is_empty(), "nobody gets tagged in casual")
		Game.MODE_FREEZE:
			_check(saw.has("frozen"), "gorillas got frozen")
			_check(feed.any(func(t): return t.contains("unfroze")) or result.contains("Everyone is frozen"), "someone got unfrozen (or IT froze everyone)")
		Game.MODE_ELIMINATION, Game.MODE_HUNT:
			_check(saw.has("out"), "gorillas got knocked out")
		Game.MODE_BOMB:
			_check(feed.any(func(t): return t.contains("BOOM")), "the bomb went off")
			_check(feed.any(func(t): return t.contains("passed the bomb")), "the bomb got passed")
		Game.MODE_PAINT:
			_check(feed.any(func(t): return t.contains("splatted")), "teams splatted each other")
			_check(saw.has("red") and saw.has("blue"), "two teams")
	if mode != Game.MODE_CASUAL:
		_check(not feed.is_empty(), "tags happened (%d)" % feed.size())
	print("== %s (%d failures) ==" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)
