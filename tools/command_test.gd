extends Node3D
## AI gorillas obey chat orders ("Mango follow me", "everyone stay", "Kiwi tag Tester").
##   godot --headless --fixed-fps 60 --path . res://tools/command_test.tscn

var world: Node
var frame := 0
var failures := 0
var b1 := -1
var b2 := -1
var d0 := 0.0


func _ready() -> void:
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.config.seed = 777
	game.config.mode = Game.MODE_CLASSIC
	game.config.black_holes = false
	game.config.max_players = 6
	game.config.fill_bots = true
	game.config.round_time = 120
	net.players = {1: {"name": "Tester", "color": Color.RED}}
	game.roster = game.build_match_roster(net.players)
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)


func _check(ok: bool, what: String) -> void:
	print(("ok: " if ok else "FAIL: ") + what)
	if not ok:
		failures += 1


func _brain(id: int) -> AIBrain:
	return world.gorillas[id].get_node("Brain")


func _first(id: int) -> String:
	return world.gorillas[id].display_name.split(" ")[0]


func _physics_process(_d: float) -> void:
	frame += 1
	if frame == 60 * 3:
		var bots: Array = world.gorillas.keys().filter(func(b): return Game.is_bot_id(b))
		bots.sort_custom(func(a, b): return world.gorillas[a].global_position.distance_to(world.local.global_position) < world.gorillas[b].global_position.distance_to(world.local.global_position))
		b1 = bots[0]
		b2 = bots[1]
		d0 = world.gorillas[b1].global_position.distance_to(world.local.global_position)
		Net.send_chat("wait what")
		_check(_brain(b1).order == "" and _brain(b2).order == "", "plain chat isn't an order")
		Net.send_chat("%s follow me" % _first(b1))
		_check(_brain(b1).order == "follow", "%s follows when told (was %.0f m away)" % [_first(b1), d0])
		_check(_brain(b2).order == "", "other gorillas ignore orders for someone else")
	if frame == 60 * 15:
		var d: float = world.gorillas[b1].global_position.distance_to(world.local.global_position)
		_check(d < maxf(5.0, d0 * 0.5), "follower came over to me (%.1f m)" % d)
		Net.send_chat("everyone stay here")
		var all_stay := true
		for b in world.gorillas:
			if Game.is_bot_id(b) and _brain(b).order != "stay":
				all_stay = false
		_check(all_stay, "'everyone stay here' reaches every gorilla")
		Net.send_chat("%s tag Tester" % _first(b2))
		_check(_brain(b2).order == "chase" and _brain(b2).order_target == 1, "'tag Tester' makes them chase me")
		Net.send_chat("%s dance" % _first(b1))
		_check(_brain(b1).order == "dance", "dance order")
		Net.send_chat("%s chase %s" % [_first(b1), _first(b2)])
		_check(_brain(b1).order == "chase" and _brain(b1).order_target == b2, "'X chase Y' targets Y")
		Net.send_chat("%s tag me" % _first(b2))
		_check(_brain(b2).order == "chase" and _brain(b2).order_target == 1, "'tag me' targets me")
	if frame == 60 * 18:
		var lines: int = world.hud._chat_box.get_child_count()
		_check(lines >= 6, "gorillas answer orders in chat (%d lines)" % lines)
		print("== %s (%d failures) ==" % ["PASSED" if failures == 0 else "FAILED", failures])
		get_tree().quit(1 if failures else 0)
