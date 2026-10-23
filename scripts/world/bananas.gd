class_name Bananas
extends Node3D
## Bananas scattered around the jungle. Eat 10, then press F for 30 seconds of double sprint speed.
## Starting spots come from the match seed (same on every peer); the host decides who eats what
## and where each eaten banana grows back.

const COUNT := 45
const NEED := 10
const BOOST_TIME := 30.0
const EAT_RADIUS := 1.6

var world: Node
var counts := {}          # gorilla id -> bananas eaten towards the next boost
var _nodes := {}          # banana id -> Node3D
var _rng := RandomNumberGenerator.new()
var _mat: StandardMaterial3D
var _tip_mat: StandardMaterial3D
var _t := 0.0


func setup(p_world: Node) -> void:
	world = p_world
	_rng.seed = int(Game.config.seed) + 77
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.85, 0.15)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.8, 0.1)
	_mat.emission_energy_multiplier = 0.5
	_mat.roughness = 0.5
	_tip_mat = StandardMaterial3D.new()
	_tip_mat.albedo_color = Color(0.3, 0.2, 0.08)
	# a few start hidden in the dead ends of the waterfall cave
	var cave: Array = world.jungle.secret_cave_spots
	for i in COUNT:
		var b := _make_banana()
		add_child(b)
		b.global_position = cave[i] if i < mini(6, cave.size()) else random_spot()
		_nodes[i] = b


func _make_banana() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.position.y = 0.7
	root.add_child(body)
	# a curved banana from short segments along an arc
	var segs := 6
	for s in segs:
		var a := lerpf(-0.75, 0.75, (s + 0.5) / segs)
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		var thick := 0.075 * (1.0 - absf(a) * 0.45)
		cyl.top_radius = thick
		cyl.bottom_radius = thick
		cyl.height = 0.13
		cyl.radial_segments = 8
		cyl.rings = 1
		cyl.material = _tip_mat if s == 0 or s == segs - 1 else _mat
		seg.mesh = cyl
		seg.position = Vector3(sin(a) * 0.4, -cos(a) * 0.4 + 0.4, 0)
		seg.rotation.z = a
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(seg)
	return root


## A random spot on open ground (used for the starting bananas and for regrowing them).
func random_spot() -> Vector3:
	var j: Node = world.jungle
	for attempt in 40:
		var x := _rng.randf_range(-125.0, 125.0)
		var z := _rng.randf_range(-105.0, 125.0)
		if j.is_river(x, z, 2.5) or j.plateau_mask(x, z) > 0.02:
			continue
		return Vector3(x, j.ground_height(x, z), z)
	return Vector3(0, j.ground_height(0, 0), 0)


func _process(delta: float) -> void:
	_t += delta
	for bid in _nodes:
		var b: Node3D = _nodes[bid]
		var body: Node3D = b.get_child(0)
		body.rotation.y = _t * 1.6 + bid
		body.position.y = 0.7 + sin(_t * 2.2 + bid) * 0.12
	if not Net.is_host() or world.mode == null:
		return
	if world.mode.phase != "play" and world.mode.phase != "hide":
		return
	for gid in world.gorillas:
		var g: Gorilla = world.gorillas[gid]
		var p := g.global_position
		for bid in _nodes:
			var bp: Vector3 = _nodes[bid].global_position
			if absf(p.y - bp.y) < 2.2 and Vector2(p.x - bp.x, p.z - bp.z).length() < EAT_RADIUS:
				Net.broadcast_event("banana_eaten", {"bid": bid, "id": gid, "count": int(counts.get(gid, 0)) + 1, "pos": random_spot()})
				break
		# bots use their banana power as soon as they have it
		if g.control == Gorilla.Ctrl.AI and int(counts.get(gid, 0)) >= NEED and g.banana_boost <= 0.0:
			server_request(gid)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("banana_boost") and world.local and int(counts.get(world.local.net_id, 0)) >= NEED:
		Net.send_banana_request()


## Host: someone asked to use their banana power.
func server_request(id: int) -> void:
	var g: Gorilla = world.gorillas.get(id)
	if g == null or int(counts.get(id, 0)) < NEED or g.banana_boost > 0.0:
		return
	Net.broadcast_event("banana_boost", {"id": id, "count": int(counts.get(id, 0)) - NEED})


func on_eaten(d: Dictionary) -> void:
	counts[d.id] = int(d.count)
	var b: Node3D = _nodes.get(d.bid)
	if b:
		b.global_position = d.pos
		b.scale = Vector3.ONE * 0.05
		b.create_tween().tween_property(b, "scale", Vector3.ONE, 0.5).set_delay(1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var g: Gorilla = world.gorillas.get(d.id)
	if g == null:
		return
	Sfx.play_at("ui_click", g.global_position, 0.0, 1.6, 20.0)
	if g == world.local:
		Sfx.play("beep_high", -10.0, 1.4)
		if int(d.count) == NEED:
			world.hud.show_message("BANANA POWER READY!", "Press F for 2x sprint speed for 30 seconds")
			Sfx.play("camo_ready")


func on_boost(d: Dictionary) -> void:
	counts[d.id] = int(d.count)
	var g: Gorilla = world.gorillas.get(d.id)
	if g == null:
		return
	g.banana_boost = BOOST_TIME
	g.flash()
	Sfx.play_at("vine_grab", g.global_position, 2.0, 1.5, 30.0)
	if g == world.local:
		world.hud.show_message("BANANA BOOST!", "Hold Shift: 2x sprint speed for 30 seconds")
		Sfx.play("round_start", -6.0, 1.4)
	elif world.local:
		world.hud.feed("%s used a BANANA BOOST!" % g.display_name)
