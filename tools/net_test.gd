extends Node3D
## Two-process network test. Start the host, then the client:
##   godot --headless --path . res://tools/net_test.tscn -- host
##   godot --headless --path . res://tools/net_test.tscn -- client
## Checks joining, the lobby, match start, movement sync both ways and server-side camouflage.

const PORT := 24999
var role := "host"
var t := 0.0
var started := false
var start_pos := Vector3.ZERO
var client_id := 0
var bot_start := {}
var done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	var game = get_node("/root/Game")
	var net = get_node("/root/Net")
	game.profile_name = role.capitalize()
	game.config.max_players = 4
	game.config.fill_bots = true
	game.config.round_time = 60
	if role == "host":
		print("host: ", net.host(PORT, "secret"))
	else:
		net.join_failed.connect(func(r): _finish(false, "join failed: " + r))
		print("client: ", net.join("127.0.0.1:%d" % PORT, "secret"))
	# survive the scene changes into the lobby/world
	_detach.call_deferred()


func _detach() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	tree.current_scene = null


func _process(delta: float) -> void:
	t = Time.get_ticks_msec() / 1000.0
	var net = get_node("/root/Net")
	var game = get_node("/root/Game")
	if t > 40.0 and not done:
		_finish(false, "timeout")
	if role == "host" and not started and net.players.size() == 2:
		started = true
		for id in net.players:
			if id != 1:
				client_id = id
		print("host: client joined as %s, lobby=%s" % [client_id, str(net.players.values().map(func(p): return p.name))])
		net.host_start_match()
	var w = net.world
	if w == null or w.local == null:
		return
	if role == "client":
		var g = w.local
		if start_pos == Vector3.ZERO:
			start_pos = g.global_position
			for id in w.gorillas:
				if game.is_bot_id(id):
					bot_start[id] = w.gorillas[id].global_position
			g.control = 1
		# walk forward and stream our state like a real client does
		g.input.move = Vector2(0, 1)
		g.input.yaw = 0.0
		if Engine.get_physics_frames() % 3 == 0:
			net.client_state.rpc_id(1, g.pack_state())
		if t > 14.0 and t < 14.1:
			net.send_camo_request(true)
		if t > 18.0 and not done:
			var moved_bots := 0
			for id in bot_start:
				if w.gorillas[id].global_position.distance_to(bot_start[id]) > 2.0:
					moved_bots += 1
			print("client: bots moving=%d/%d camo_active=%s phase=%s roles=%d" % [moved_bots, bot_start.size(), g.camo_active, w.mode.phase, w.mode.roles.size()])
			_finish(moved_bots > 0 and g.camo_active and w.mode.roles.size() == 4, "client checks")
	else:
		var cg = w.gorillas.get(client_id)
		if cg and start_pos == Vector3.ZERO:
			start_pos = cg.global_position
		if t > 20.0 and not done:
			var d: float = cg.global_position.distance_to(start_pos) if cg else 0.0
			print("host: client gorilla at %s, moved %.1f m from spawn, camo=%s" % [str(cg.global_position) if cg else "?", d, cg.camo_active if cg else false])
			_finish(cg != null and d > 3.0 and cg.camo_active, "host checks")


func _finish(ok: bool, what: String) -> void:
	done = true
	print("%s %s: %s" % [role, what, "PASS" if ok else "FAIL"])
	get_tree().create_timer(1.5).timeout.connect(func(): get_tree().quit(0 if ok else 1))
