extends Node
## Networking: hosting, joining, room codes, the lobby roster and all gameplay RPCs.
##
## Model: the host is the authoritative server. It owns the round timer, roles, tagging,
## camouflage validation and the AI gorillas. Each client simulates only its own gorilla
## and streams its state to the host; the host streams snapshots of everybody back.

signal lobby_changed
signal join_failed(reason: String)
signal joined
signal public_code_ready(code: String)

const DEFAULT_PORT := 24680
const PROTOCOL_VERSION := 3
const CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const SEND_RATE := 20.0

## id -> {"name": String, "color": Color}
var players := {}
var password := ""
var port := DEFAULT_PORT
var is_online := false
## The running world registers itself here so in-match RPCs can be forwarded to it.
var world: Node = null
## Clients that reported their world as loaded (host only).
var ready_peers := {}

var _pending_name := ""
var _pending_color := Color.WHITE
var _pending_password := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func my_id() -> int:
	return multiplayer.get_unique_id()


func is_host() -> bool:
	return multiplayer.is_server()


# ------------------------------------------------------------------ hosting / joining
func start_solo() -> void:
	leave()
	players = {1: {"name": Game.profile_name, "color": Game.profile_color}}
	Game.config.seed = randi() % 1000000
	Game.roster = Game.build_match_roster(players)
	Game.start_world()


func host(p_port: int, p_password: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, maxi(1, int(Game.config.max_players) - 1))
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	port = p_port
	password = p_password
	is_online = true
	players = {1: {"name": Game.profile_name, "color": Game.profile_color}}
	lobby_changed.emit()
	return OK


func join(address_or_code: String, p_password: String) -> Error:
	leave()
	var target := parse_address(address_or_code)
	if target.is_empty():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(target.ip, target.port)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	is_online = true
	_pending_name = Game.profile_name
	_pending_color = Game.profile_color
	_pending_password = p_password
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_online = false
	players.clear()
	world = null


func _on_peer_connected(_id: int) -> void:
	pass  # The client introduces itself with request_join.


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	if players.has(id):
		var pname: String = players[id].name
		players.erase(id)
		_broadcast_lobby()
		if world:
			game_event.rpc("player_left", {"id": id, "name": pname})


func _on_connected_to_server() -> void:
	request_join.rpc_id(1, _pending_name, _pending_color, _pending_password, PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Could not reach the host. Check the room code and that the host's port is open.")


func _on_server_disconnected() -> void:
	leave()
	Game.go_to_menu("The host closed the room.")


@rpc("any_peer", "reliable")
func request_join(p_name: String, p_color: Color, p_password: String, version: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if version != PROTOCOL_VERSION:
		reason = "Game version mismatch. Make sure everyone has the same build."
	elif password != "" and p_password != password:
		reason = "Wrong room password."
	elif players.size() >= int(Game.config.max_players):
		reason = "The room is full."
	elif Game.in_match:
		reason = "A match is already running. Ask the host to return to the lobby."
	if reason != "":
		_join_rejected.rpc_id(id, reason)
		# Give the message a moment to arrive before dropping the peer.
		get_tree().create_timer(0.5).timeout.connect(func():
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))
		return
	players[id] = {"name": _unique_name(Game.sanitize_name(p_name)), "color": p_color}
	_broadcast_lobby()


func _unique_name(n: String) -> String:
	var names := []
	for id in players:
		names.append(players[id].name)
	var out := n
	var i := 2
	while out in names:
		out = "%s%d" % [n, i]
		i += 1
	return out


@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	leave()
	join_failed.emit(reason)


func _broadcast_lobby() -> void:
	var cfg: Dictionary = Game.config.duplicate()
	sync_lobby.rpc(players, cfg)


@rpc("authority", "reliable", "call_local")
func sync_lobby(p_players: Dictionary, cfg: Dictionary) -> void:
	var first_time := not is_host() and players.is_empty()
	players = p_players
	Game.config = cfg
	if first_time:
		joined.emit()
	lobby_changed.emit()


## Called on the host when it edits lobby settings.
func host_update_config() -> void:
	if is_host():
		_broadcast_lobby()


## Called by any lobby member to change their name/colour.
func update_profile() -> void:
	if is_host():
		players[1] = {"name": Game.profile_name, "color": Game.profile_color}
		_broadcast_lobby()
	else:
		_update_profile.rpc_id(1, Game.profile_name, Game.profile_color)


@rpc("any_peer", "reliable")
func _update_profile(p_name: String, p_color: Color) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and players.has(id):
		players.erase(id)
		players[id] = {"name": _unique_name(Game.sanitize_name(p_name)), "color": p_color}
		_broadcast_lobby()


func host_start_match() -> void:
	if not is_host():
		return
	Game.config.seed = randi() % 1000000
	var roster := Game.build_match_roster(players)
	begin_match.rpc(Game.config.duplicate(), roster)


@rpc("authority", "reliable", "call_local")
func begin_match(cfg: Dictionary, roster: Dictionary) -> void:
	ready_peers.clear()
	Game.config = cfg
	Game.roster = roster
	Game.start_world()


func host_return_to_lobby() -> void:
	if is_host():
		back_to_lobby.rpc()


@rpc("authority", "reliable", "call_local")
func back_to_lobby() -> void:
	world = null
	Game.go_to_lobby()


# ------------------------------------------------------------------ in-match traffic
## Client -> host: finished building the world and is ready for round state.
@rpc("any_peer", "reliable")
func client_world_ready() -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	ready_peers[id] = true
	if world:
		world.on_client_ready(id)


## Client -> host: own gorilla state.
@rpc("any_peer", "unreliable_ordered")
func client_state(data: PackedFloat32Array) -> void:
	if world and is_host():
		world.on_client_state(multiplayer.get_remote_sender_id(), data)


## Host -> clients: positions/animation of every gorilla.
@rpc("authority", "unreliable_ordered")
func snapshot(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if world:
		world.on_snapshot(ids, data)


## Client -> host: wants to toggle camouflage. Host validates timers.
@rpc("any_peer", "reliable")
func request_camo(on: bool) -> void:
	if world and is_host():
		world.server_camo_request(multiplayer.get_remote_sender_id(), on)


## Client -> host: a chat message.
@rpc("any_peer", "reliable")
func request_chat(text: String) -> void:
	if world and is_host():
		world.server_chat(multiplayer.get_remote_sender_id(), text)


func send_chat(text: String) -> void:
	if is_host():
		if world:
			world.server_chat(my_id(), text)
	else:
		request_chat.rpc_id(1, text)


## Client -> host: wants to use 10 bananas for a sprint boost.
@rpc("any_peer", "reliable")
func request_banana() -> void:
	if world and is_host():
		world.bananas.server_request(multiplayer.get_remote_sender_id())


func send_banana_request() -> void:
	if is_host():
		if world:
			world.bananas.server_request(my_id())
	else:
		request_banana.rpc_id(1)


## Client -> host: swiped a hand (slightly longer tag reach for a moment).
@rpc("any_peer", "unreliable")
func request_swipe() -> void:
	if world and is_host():
		world.server_swipe(multiplayer.get_remote_sender_id())


## Host -> everyone: reliable gameplay events (tags, roles, round state, camo state...).
@rpc("authority", "reliable", "call_local")
func game_event(type: String, data: Dictionary) -> void:
	if world:
		world.on_game_event(type, data)


## Sends a gameplay event from the host to everyone (works offline too).
func broadcast_event(type: String, data: Dictionary) -> void:
	game_event.rpc(type, data)


## Sends something to the host, or handles it directly when we are the host.
func send_camo_request(on: bool) -> void:
	if is_host():
		if world:
			world.server_camo_request(my_id(), on)
	else:
		request_camo.rpc_id(1, on)


func send_swipe() -> void:
	if is_host():
		if world:
			world.server_swipe(my_id())
	else:
		request_swipe.rpc_id(1)


# ------------------------------------------------------------------ room codes
func local_ip() -> String:
	var best := ""
	for ip in IP.get_local_addresses():
		if ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			return ip
		if best == "":
			best = ip
	return best if best != "" else "127.0.0.1"


func make_room_code(ip: String, p_port: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var v := 0
	for p in parts:
		v = (v << 8) | (int(p) & 255)
	v = (v << 16) | (p_port & 0xFFFF)
	var code := ""
	for i in 10:
		code = CODE_ALPHABET[v & 31] + code
		v >>= 5
	return code.substr(0, 5) + "-" + code.substr(5, 5)


func decode_room_code(code: String) -> Dictionary:
	var c := code.to_upper().replace("-", "").replace(" ", "").replace("O", "0").replace("I", "1").replace("L", "1")
	if c.length() != 10:
		return {}
	var v := 0
	for ch in c:
		var idx := CODE_ALPHABET.find(ch)
		if idx < 0:
			return {}
		v = (v << 5) | idx
	var p_port := v & 0xFFFF
	v >>= 16
	var ip := "%d.%d.%d.%d" % [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]
	return {"ip": ip, "port": p_port}


## Accepts a room code, "ip", "ip:port" or "hostname:port".
func parse_address(text: String) -> Dictionary:
	text = text.strip_edges()
	if text.is_empty():
		return {}
	var decoded := decode_room_code(text)
	if not decoded.is_empty() and not text.contains("."):
		return decoded
	var host_part := text
	var p_port := DEFAULT_PORT
	if text.contains(":"):
		host_part = text.get_slice(":", 0)
		p_port = int(text.get_slice(":", 1))
	if host_part.is_empty():
		return {}
	return {"ip": host_part, "port": p_port}


## Looks up the host's public IP so friends outside the local network can join.
func fetch_public_code() -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 6.0
	req.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		req.queue_free()
		var ip := body.get_string_from_utf8().strip_edges()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.count(".") == 3:
			public_code_ready.emit(make_room_code(ip, port))
		else:
			public_code_ready.emit(""))
	if req.request("https://api.ipify.org") != OK:
		req.queue_free()
		public_code_ready.emit("")
