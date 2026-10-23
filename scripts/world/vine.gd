class_name Vine
extends MeshInstance3D
## A hanging vine. The node origin is the anchor point on a branch.
## Visuals are bent on the GPU (vine.gdshader); the swing physics lives in the gorilla.

const MAX_VISUAL_DIST := 90.0

var id := 0
var length := 10.0
var grabbed_by: Node3D = null
## Global position of the grabbing hand, written by the gorilla every frame.
var hand_pos := Vector3.ZERO
var hand_vel := Vector3.ZERO

var _phase := 0.0
var _tip_offset := Vector3.ZERO   # free-swinging tip offset from rest (spring simulated)
var _tip_vel := Vector3.ZERO
var _time := 0.0
var _last_grab_len := 5.0


func setup(p_id: int, p_length: float, mesh_res: Mesh, mat: Material, phase: float) -> void:
	id = p_id
	length = p_length
	mesh = mesh_res
	material_override = mat.duplicate()
	_phase = phase
	add_to_group("vines")
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apply(Vector3(0, -length * 0.5, 0), Vector3(0, -length, 0), 0.5)


func anchor() -> Vector3:
	return global_position


## Current global position of the tip (approximate when idle).
func tip() -> Vector3:
	if grabbed_by:
		return hand_pos + Vector3.DOWN * maxf(0.0, length - _last_grab_len)
	return global_position + Vector3(0, -length, 0) + _tip_offset


## Closest point on the vine to p and the distance to it.
func closest_point(p: Vector3) -> Vector3:
	var a := global_position
	var b := tip()
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return a + ab * t


func grab(by: Node3D) -> void:
	grabbed_by = by


func release(vel: Vector3) -> void:
	if grabbed_by == null:
		return
	grabbed_by = null
	# the free part of the vine keeps swinging after it is let go
	var rest := global_position + Vector3(0, -length, 0)
	_tip_offset = (hand_pos - global_position).normalized() * length - (rest - global_position)
	_tip_vel = vel * 0.6


func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_3d()
	if grabbed_by == null and cam and cam.global_position.distance_squared_to(global_position) > MAX_VISUAL_DIST * MAX_VISUAL_DIST:
		return
	if grabbed_by:
		var hp := hand_pos - global_position
		var grab_len := clampf(hp.length(), 0.3, length)
		_last_grab_len = grab_len
		var split := clampf(grab_len / length, 0.05, 0.98)
		var tail := hp + Vector3.DOWN * (length - grab_len) - hand_vel * 0.06 * (length - grab_len)
		_apply(hp, tail, split)
	else:
		# damped spring pulls the tip back to rest, plus a gentle breeze
		var k := 6.0 / maxf(length, 1.0)
		_tip_vel += (-_tip_offset * k * 9.0) * delta
		_tip_vel *= exp(-0.8 * delta)
		_tip_offset += _tip_vel * delta
		_tip_offset.y = clampf(_tip_offset.y, -0.5, length * 0.9)
		var breeze := Vector3(sin(_time * 0.8 + _phase), 0, cos(_time * 0.6 + _phase * 1.7)) * (0.04 * length)
		var tip_local := Vector3(0, -length, 0) + _tip_offset + breeze
		# keep the rope length roughly constant while swinging
		tip_local = tip_local.normalized() * length
		var mid := tip_local * 0.5 + (breeze * 0.5 + _tip_offset * 0.15)
		_apply(mid, tip_local, 0.5)


func _apply(p1: Vector3, p2: Vector3, split: float) -> void:
	var m := material_override as ShaderMaterial
	m.set_shader_parameter("vine_p1", p1)
	m.set_shader_parameter("vine_p2", p2)
	m.set_shader_parameter("vine_split", split)
