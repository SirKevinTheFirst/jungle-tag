extends Node3D
## The match scene: builds lighting and the jungle, spawns gorillas, runs network sync
## and forwards gameplay events to the game mode and HUD.

const GorillaScript := preload("res://scripts/player/gorilla.gd")

var jungle: Jungle
var gorillas := {}          # id -> Gorilla
var local: Gorilla
var mode: GameMode
var hud: HUD
var pause_menu: PauseMenu
var env: Environment
var sun: DirectionalLight3D

var _snap_timer := 0.0
var _bird_timer := 3.0
var _ready_clients := {}
var _round_started := false
var _start_wait := 8.0
var _bird_rng := RandomNumberGenerator.new()

# black holes and the maze
const SHADOW_ID := 99999
var maze: Maze
var npcs := {}              # id -> Gorilla that is not a player (the maze Shadow)
var holes := {}             # id -> BlackHole
var _hole_timer := 60.0
var _hole_next_id := 1
var _maze_cooldown := {}    # id -> seconds before maze events can affect them again
var _hole_rng := RandomNumberGenerator.new()

# power-ups and the end-of-round frenzy
const MAX_POWERUPS := 12
var powerups := {}          # id -> PowerUp
var _pu_timer := 3.0
var _pu_next_id := 1
var frenzy := false


func _ready() -> void:
	Net.world = self
	_build_environment()
	jungle = Jungle.new()
	jungle.name = "Jungle"
	add_child(jungle)
	jungle.build(int(Game.config.seed))
	maze = Maze.new()
	maze.name = "Maze"
	add_child(maze)
	maze.build(int(Game.config.seed))
	_hole_rng.seed = int(Game.config.seed) + 5
	mode = GameMode.new()
	mode.name = "GameMode"
	add_child(mode)
	mode.setup(self)
	_spawn_all()
	_spawn_shadow()
	hud = HUD.new()
	add_child(hud)
	hud.setup(self)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.setup(self)
	_start_ambience()
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Net.is_host():
		for id in Net.ready_peers:
			_ready_clients[id] = true
	else:
		Net.client_world_ready.rpc_id(1)


func _exit_tree() -> void:
	if Net.world == self:
		Net.world = null
	Sfx.stop_music()


# ======================================================================== setup
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# dusk: a darker, moodier jungle
	sky_mat.sky_top_color = Color(0.06, 0.09, 0.22)
	sky_mat.sky_horizon_color = Color(0.55, 0.32, 0.28)
	sky_mat.ground_horizon_color = Color(0.2, 0.18, 0.16)
	sky_mat.ground_bottom_color = Color(0.03, 0.05, 0.03)
	sky_mat.sky_energy_multiplier = 0.7
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.18, 0.22)
	env.fog_density = 0.006
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.62, 0.42)
	sun.light_energy = 0.6
	sun.rotation_degrees = Vector3(-22.0, -38.0, 0.0)
	sun.light_cull_mask = 0xFFFFF & ~Maze.LAYER  # never lights the underground maze
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_bias = 0.04
	sun.shadow_blur = 1.2
	add_child(sun)


func _apply_settings() -> void:
	env.ssao_enabled = Settings.ssao
	env.glow_enabled = Settings.glow
	sun.shadow_enabled = Settings.shadows
	sun.directional_shadow_max_distance = 90.0 if Settings.quality <= 1 else 140.0
	env.fog_density = clampf(1.6 / Settings.view_distance, 0.004, 0.012)


func _spawn_all() -> void:
	var my_id := Net.my_id()
	var i := 0
	var ids: Array = Game.roster.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = Game.roster[id]
		var ctrl := Gorilla.Ctrl.REMOTE
		if id == my_id:
			ctrl = Gorilla.Ctrl.LOCAL
		elif info.bot and Net.is_host():
			ctrl = Gorilla.Ctrl.AI
		var g: Gorilla = GorillaScript.new()
		g.setup(id, info.name, info.color, ctrl, jungle, self)
		add_child(g)
		g.global_position = jungle.spawn_points[i % jungle.spawn_points.size()]
		g._net_pos = g.global_position
		gorillas[id] = g
		if ctrl == Gorilla.Ctrl.LOCAL:
			local = g
			g.input.yaw = randf() * TAU
		elif ctrl == Gorilla.Ctrl.AI:
			var brain := AIBrain.new()
			brain.name = "Brain"
			g.add_child(brain)
			brain.setup(g, self, int(Game.config.seed) + id)
		i += 1


func _spawn_shadow() -> void:
	var g: Gorilla = GorillaScript.new()
	var ctrl := Gorilla.Ctrl.AI if Net.is_host() else Gorilla.Ctrl.REMOTE
	g.setup(SHADOW_ID, "The Shadow", Color(0.08, 0.04, 0.12), ctrl, jungle, self)
	add_child(g)
	g.global_position = maze.cell_center(Vector2i(Maze.N / 2, Maze.N / 2)) + Vector3(0, 0.3, 0)
	g._net_pos = g.global_position
	g.set_role("it")
	g.nameplate.modulate = Color(0.75, 0.5, 1.0)
	npcs[SHADOW_ID] = g
	if ctrl == Gorilla.Ctrl.AI:
		var brain := MazeBrain.new()
		g.add_child(brain)
		brain.setup(g, self)


func get_any(id: int) -> Gorilla:
	var g: Gorilla = gorillas.get(id)
	return g if g else npcs.get(id)


func _start_ambience() -> void:
	for snd in [["amb_jungle", -6.0], ["amb_wind", -14.0]]:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.get_stream(snd[0])
		p.bus = "Ambience"
		p.volume_db = snd[1]
		p.autoplay = true
		add_child(p)
	Sfx.play_music()


func random_spawn() -> Vector3:
	return jungle.spawn_points[randi() % jungle.spawn_points.size()]


func is_input_blocked() -> bool:
	return pause_menu != null and pause_menu.visible


# ======================================================================== loop
func _process(delta: float) -> void:
	var was := frenzy
	frenzy = mode.phase == "play" and mode.time_left > 0.0 and mode.time_left <= 30.0
	if frenzy and not was:
		hud.show_message("FRENZY!", "Last 30 seconds - everyone is faster!")
		Sfx.play("round_start", 0.0, 1.3)
	# random bird calls up in the trees around the listener
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = _bird_rng.randf_range(1.5, 5.0)
		var cam := get_viewport().get_camera_3d()
		if cam:
			var a := _bird_rng.randf() * TAU
			var p := cam.global_position + Vector3(cos(a) * _bird_rng.randf_range(10, 35), _bird_rng.randf_range(8, 25), sin(a) * _bird_rng.randf_range(10, 35))
			Sfx.play_at("bird_%d" % _bird_rng.randi_range(0, 3), p, _bird_rng.randf_range(-10.0, -2.0), _bird_rng.randf_range(0.85, 1.2), 70.0)


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	if not _round_started:
		_start_wait -= delta
		var humans := 0
		for id in Game.roster:
			if not Game.roster[id].bot and id != 1 and gorillas.has(id):
				humans += 1
		if _ready_clients.size() >= humans or _start_wait <= 0.0:
			_round_started = true
			mode.start_round()
	_update_black_holes(delta)
	_update_powerups(delta)
	if Net.is_online:
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snap_timer = 1.0 / Net.SEND_RATE
			var ids := PackedInt32Array()
			var data := PackedFloat32Array()
			for id in gorillas:
				ids.append(id)
				data.append_array(gorillas[id].pack_state())
			for id in npcs:
				ids.append(id)
				data.append_array(npcs[id].pack_state())
			Net.snapshot.rpc(ids, data)


# ======================================================================== network glue
func on_client_ready(id: int) -> void:
	_ready_clients[id] = true
	if _round_started:
		# late loader: bring it up to date
		Net.game_event.rpc_id(id, "round_state", {"phase": mode.phase, "time": mode.time_left, "roles": mode.roles, "mode": mode.mode})
		for gid in gorillas:
			var g: Gorilla = gorillas[gid]
			if g.camo_active or g.camo_cooldown > 0.0:
				Net.game_event.rpc_id(id, "camo", {"id": gid, "on": g.camo_active, "t": g.camo_time, "cd": g.camo_cooldown})


func on_client_state(id: int, data: PackedFloat32Array) -> void:
	var g: Gorilla = gorillas.get(id)
	if g == null or data.size() < Gorilla.STATE_SIZE:
		return
	# keep reported positions inside the map
	data[0] = clampf(data[0], -150.0, 150.0)
	data[2] = clampf(data[2], -150.0, 150.0)
	data[1] = clampf(data[1], -40.0, 120.0)
	g.apply_net_state(data, 0)


func on_snapshot(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	var my_id := Net.my_id()
	for i in ids.size():
		var id := ids[i]
		if id == my_id:
			continue
		var g: Gorilla = get_any(id)
		if g and (i + 1) * Gorilla.STATE_SIZE <= data.size():
			g.apply_net_state(data, i * Gorilla.STATE_SIZE)


## Host: validate and broadcast a camouflage toggle.
func server_camo_request(id: int, on: bool) -> void:
	if not Net.is_host():
		return
	var g: Gorilla = gorillas.get(id)
	if g == null:
		return
	if on:
		if g.camo_active or g.camo_cooldown > 0.0 or mode.phase == "end":
			return
		Net.broadcast_event("camo", {"id": id, "on": true, "t": Gorilla.CAMO_MAX, "cd": 0.0})
	else:
		if not g.camo_active:
			return
		Net.broadcast_event("camo", {"id": id, "on": false, "t": 0.0, "cd": Gorilla.CAMO_COOLDOWN})


func server_swipe(id: int) -> void:
	if Net.is_host():
		mode.server_swipe(id)


## Host: spawn black holes now and then, and run the maze rules.
func _update_black_holes(delta: float) -> void:
	for id in _maze_cooldown.keys():
		_maze_cooldown[id] -= delta
		if _maze_cooldown[id] <= 0.0:
			_maze_cooldown.erase(id)
	if mode.phase == "play" or mode.phase == "hide":
		_hole_timer -= delta
		if _hole_timer <= 0.0:
			# a black hole bursts out right in front of every player (first after 60 s, then every 15-25 s)
			_hole_timer = _hole_rng.randf_range(15.0, 25.0)
			var targets: Array = gorillas.keys().filter(func(i): return gorillas[i].control != Gorilla.Ctrl.AI)
			if targets.is_empty():
				targets = [gorillas.keys()[_hole_rng.randi_range(0, gorillas.size() - 1)]]
			for gid in targets:
				if holes.size() >= 8:
					break
				var p := _pick_hole_spot(gorillas[gid])
				if p != Vector3.INF:
					Net.broadcast_event("hole_open", {"id": _hole_next_id, "pos": p, "life": 40.0})
					_hole_next_id += 1
	else:
		_hole_timer = 60.0  # each new round waits 60 s for its first black hole
	var shadow: Gorilla = npcs.get(SHADOW_ID)
	for id in gorillas:
		if _maze_cooldown.has(id):
			continue
		var g: Gorilla = gorillas[id]
		var p := g.global_position
		if maze.contains(p):
			if Vector2(p.x - maze.exit_pos().x, p.z - maze.exit_pos().z).length() < 1.6:
				_maze_cooldown[id] = 3.0
				Net.broadcast_event("maze_exit", {"id": id, "pos": random_spawn()})
			elif shadow and shadow.stun_time <= 0.0 and shadow.global_position.distance_to(p) < 1.7:
				_maze_cooldown[id] = 3.0
				Net.broadcast_event("maze_caught", {"id": id, "pos": maze.start_pos()})
		else:
			for hid in holes:
				var h: BlackHole = holes[hid]
				if is_instance_valid(h) and h.swallows(p):
					_maze_cooldown[id] = 3.0
					var off := Vector3(_hole_rng.randf_range(-1, 1), 0, _hole_rng.randf_range(-1, 1))
					Net.broadcast_event("maze_enter", {"id": id, "pos": maze.start_pos() + off})
					break


## Host: keep the jungle stocked with power-ups and hand them out.
func _update_powerups(delta: float) -> void:
	if mode.phase != "play" and mode.phase != "hide":
		return
	_pu_timer -= delta
	if _pu_timer <= 0.0 and powerups.size() < MAX_POWERUPS:
		_pu_timer = 4.0
		var sp: Vector3 = jungle.spawn_points[_hole_rng.randi_range(0, jungle.spawn_points.size() - 1)]
		var a := _hole_rng.randf() * TAU
		var r := _hole_rng.randf_range(0.0, 35.0)
		var x := clampf(sp.x + cos(a) * r, -125.0, 125.0)
		var z := clampf(sp.z + sin(a) * r, -105.0, 125.0)
		if not jungle.is_river(x, z, 1.0) and jungle.plateau_mask(x, z) < 0.02:
			var kind: String = PowerUp.KINDS[_hole_rng.randi_range(0, PowerUp.KINDS.size() - 1)]
			Net.broadcast_event("powerup_spawn", {"pid": _pu_next_id, "kind": kind, "pos": Vector3(x, jungle.ground_height(x, z), z)})
			_pu_next_id += 1
	for pid in powerups.keys():
		var pu: PowerUp = powerups[pid]
		if not is_instance_valid(pu):
			continue
		for id in gorillas:
			var g: Gorilla = gorillas[id]
			if (g.global_position + Vector3(0, 0.8, 0)).distance_to(pu.global_position + Vector3(0, 0.9, 0)) < 1.6:
				Net.broadcast_event("powerup_taken", {"pid": pid, "id": id, "kind": pu.kind})
				powerups.erase(pid)
				break


## A spot on open ground just ahead of where this gorilla is looking.
func _pick_hole_spot(g: Gorilla) -> Vector3:
	if maze.contains(g.global_position):
		return Vector3.INF
	var yaw: float = g.input.yaw
	for attempt in 16:
		var a := yaw + (0.0 if attempt < 4 else _hole_rng.randf_range(-0.6, 0.6) if attempt < 10 else _hole_rng.randf() * TAU)
		var r: float = [8.0, 6.0, 10.0, 5.0][attempt] if attempt < 4 else _hole_rng.randf_range(5.0, 10.0)
		var x := clampf(g.global_position.x - sin(a) * r, -125.0, 125.0)
		var z := clampf(g.global_position.z - cos(a) * r, -105.0, 125.0)
		if jungle.is_river(x, z, 2.0) or jungle.plateau_mask(x, z) > 0.02:
			continue
		return Vector3(x, jungle.ground_height(x, z) + 0.05, z)
	return Vector3.INF


func on_game_event(type: String, d: Dictionary) -> void:
	match type:
		"powerup_spawn":
			var pu := PowerUp.new()
			pu.setup(d.pid, d.kind)
			add_child(pu)
			pu.global_position = d.pos
			powerups[d.pid] = pu
		"powerup_taken":
			var pu: PowerUp = powerups.get(d.pid)
			if pu and is_instance_valid(pu):
				pu.queue_free()
			powerups.erase(d.pid)
			var g: Gorilla = gorillas.get(d.id)
			if g:
				g.apply_powerup(d.kind)
				if g == local:
					hud.show_message(PowerUp.LABELS[d.kind] + "!", "Speed x1.5 for 8 s" if d.kind == "speed" else ("Jump way higher for 8 s" if d.kind == "jump" else "Camouflage is ready again"))
		"hole_open":
			var h := BlackHole.new()
			h.setup(d.id, d.life)
			add_child(h)
			h.global_position = d.pos
			holes[d.id] = h
			h.tree_exited.connect(func(): holes.erase(d.id))
			if local:
				var dist := local.global_position.distance_to(d.pos)
				if dist < 30.0:
					hud.show_message("BLACK HOLE!", "One just burst out of the ground right near you")
				else:
					hud.feed("A black hole opened %d m away - follow the purple beam" % int(dist))
		"maze_enter", "maze_exit", "maze_caught":
			var g: Gorilla = gorillas.get(d.id)
			if g == null:
				return
			g.respawn(d.pos)
			g.flash()
			if type == "maze_caught":
				g.stun_time = 1.2
				var shadow: Gorilla = npcs.get(SHADOW_ID)
				if shadow:
					shadow.stun_time = 2.0
					Sfx.play_at("infect", shadow.global_position, 2.0, 0.7)
			if g == local:
				match type:
					"maze_enter":
						hud.show_message("SUCKED INTO A BLACK HOLE!", "Find the green EXIT - and run from the Shadow")
						Sfx.play("round_end", -2.0, 0.6)
					"maze_exit":
						hud.show_message("You escaped the maze!", "Back to the jungle")
						Sfx.play("camo_ready", 0.0)
					"maze_caught":
						hud.show_message("The Shadow got you!", "Back to the start of the maze...")
						Sfx.play("tag", 0.0, 0.7)
			elif type == "maze_enter":
				hud.feed("%s fell into a black hole" % g.display_name)
			elif type == "maze_exit":
				hud.feed("%s escaped the maze" % g.display_name)
		"round_state":
			mode.apply_state(d)
		"timer":
			mode.on_timer(d)
		"tag":
			mode.apply_tag(d)
		"round_end":
			mode.on_round_end(d)
		"camo":
			var g: Gorilla = gorillas.get(d.id)
			if g:
				g.apply_camo_state(d.on, d.t, d.cd)
		"respawn_all":
			for id in d.spawns:
				var g: Gorilla = gorillas.get(id)
				if g:
					g.respawn(d.spawns[id])
					g.camo_active = false
					g.camo_time = 0.0
					g.camo_cooldown = 0.0
					g.tags = 0
		"player_left":
			var g: Gorilla = gorillas.get(d.id)
			if g:
				gorillas.erase(d.id)
				g.queue_free()
			mode.on_player_left(d.id)
			hud.feed("%s left the jungle" % d.name)
