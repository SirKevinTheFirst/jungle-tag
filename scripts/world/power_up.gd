class_name PowerUp
extends Node3D
## A floating, glowing pickup. The host decides who grabs it.

const KINDS := ["speed", "jump", "camo"]
const COLORS := {"speed": Color(1.0, 0.75, 0.1), "jump": Color(0.2, 0.8, 1.0), "camo": Color(0.4, 1.0, 0.3)}
const LABELS := {"speed": "SPEED", "jump": "SUPER JUMP", "camo": "CAMO REFILL"}

var id := 0
var kind := "speed"
var _t := 0.0
var _orb: MeshInstance3D


func setup(p_id: int, p_kind: String) -> void:
	id = p_id
	kind = p_kind


func _ready() -> void:
	var c: Color = COLORS[kind]
	_orb = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.45
	m.height = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 4.0
	m.material = mat
	_orb.mesh = m
	add_child(_orb)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 0.72
	tm.material = mat
	ring.mesh = tm
	_orb.add_child(ring)
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 1.5
	l.omni_range = 5.0
	add_child(l)
	var lbl := Label3D.new()
	lbl.text = LABELS[kind]
	lbl.font_size = 48
	lbl.pixel_size = 0.008
	lbl.modulate = c.lightened(0.3)
	lbl.outline_size = 10
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 1.1
	lbl.visibility_range_end = 30.0
	add_child(lbl)


func _process(delta: float) -> void:
	_t += delta
	_orb.position.y = 0.9 + sin(_t * 2.5) * 0.25
	_orb.rotation.y += delta * 2.0
	_orb.rotation.x = sin(_t) * 0.4
