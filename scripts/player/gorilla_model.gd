class_name GorillaModel
extends Node3D
## Cartoon gorilla built from primitives with fully procedural animation
## (idle, run/knuckle-walk, jump, climb, hang, vine swing, crouch) and the camouflage look.

const FUR_SHADER := preload("res://shaders/gorilla.gdshader")

var base_color := Color("6b4a35")
var _parts: Array[GeometryInstance3D] = []

var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var forearm_l: Node3D
var forearm_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D

var _phase := 0.0
var _blink := 0.0
var _eyes: Array[Node3D] = []
var _step_accum := 0.0
var _last_step_side := 0

# per-gorilla materials (plain uniforms so the Compatibility renderer works too)
var _mat_fur: ShaderMaterial
var _mat_skin: ShaderMaterial
var _mat_eye: ShaderMaterial
var _mat_pupil: ShaderMaterial
var _mats: Array[ShaderMaterial] = []


func _init() -> void:
	if true:
		_mat_fur = ShaderMaterial.new()
		_mat_fur.shader = FUR_SHADER
		_mat_skin = ShaderMaterial.new()
		_mat_skin.shader = FUR_SHADER
		_mat_skin.set_shader_parameter("part_color", Color(0.24, 0.19, 0.17))
		_mat_skin.set_shader_parameter("tint_strength", 0.25)
		_mat_skin.set_shader_parameter("fur_noise", 0.3)
		_mat_eye = ShaderMaterial.new()
		_mat_eye.shader = FUR_SHADER
		_mat_eye.set_shader_parameter("part_color", Color(0.98, 0.98, 0.95))
		_mat_eye.set_shader_parameter("tint_strength", 0.0)
		_mat_eye.set_shader_parameter("fur_noise", 0.0)
		_mat_pupil = ShaderMaterial.new()
		_mat_pupil.shader = FUR_SHADER
		_mat_pupil.set_shader_parameter("part_color", Color(0.05, 0.04, 0.04))
		_mat_pupil.set_shader_parameter("tint_strength", 0.0)
		_mat_pupil.set_shader_parameter("fur_noise", 0.0)
	_mats = [_mat_fur, _mat_skin, _mat_eye, _mat_pupil]
	_build()


func _sphere(parent: Node3D, r: float, pos: Vector3, scale_v: Vector3, mat: Material, segments: int = 16) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segments
	m.rings = segments / 2
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale_v
	parent.add_child(mi)
	_parts.append(mi)
	return mi


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	_parts.append(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3, pname: String) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	parent.add_child(n)
	return n


func _build() -> void:
	hips = _pivot(self, Vector3(0, 0.62, 0), "Hips")
	torso = _pivot(hips, Vector3(0, 0.05, 0), "Torso")
	_sphere(torso, 0.5, Vector3(0, 0.38, 0), Vector3(1.05, 1.05, 0.85), _mat_fur, 20)
	_sphere(torso, 0.36, Vector3(0, 0.3, -0.24), Vector3(1.0, 1.1, 0.5), _mat_skin)   # belly / chest plate
	_sphere(torso, 0.42, Vector3(0, 0.0, 0.02), Vector3(1.0, 0.7, 0.9), _mat_fur)      # lower body
	head = _pivot(torso, Vector3(0, 0.86, -0.12), "Head")
	_sphere(head, 0.31, Vector3.ZERO, Vector3(1.0, 0.95, 1.0), _mat_fur, 18)
	_sphere(head, 0.12, Vector3(0, 0.23, 0.04), Vector3(1.6, 0.9, 1.4), _mat_fur)       # crest
	_sphere(head, 0.23, Vector3(0, -0.07, -0.2), Vector3(1.05, 0.8, 0.75), _mat_skin)   # face
	_sphere(head, 0.15, Vector3(0, -0.15, -0.3), Vector3(1.25, 0.75, 0.85), _mat_skin)  # muzzle
	var brow := _sphere(head, 0.2, Vector3(0, 0.08, -0.26), Vector3(1.45, 0.32, 0.5), _mat_skin)
	brow.name = "Brow"
	for sx in [-1.0, 1.0]:
		var eye := _pivot(head, Vector3(sx * 0.1, 0.0, -0.33), "Eye")
		_sphere(eye, 0.065, Vector3.ZERO, Vector3.ONE, _mat_eye, 10)
		_sphere(eye, 0.036, Vector3(0, 0, -0.045), Vector3.ONE, _mat_pupil, 8)
		_eyes.append(eye)
		_sphere(head, 0.07, Vector3(sx * 0.3, 0.02, 0.0), Vector3(0.6, 1.0, 1.0), _mat_skin, 10)  # ears
		_sphere(head, 0.025, Vector3(sx * 0.04, -0.12, -0.43), Vector3.ONE, _mat_pupil, 6)        # nostrils
	# arms: long and strong
	arm_l = _pivot(torso, Vector3(-0.5, 0.58, -0.02), "ArmL")
	arm_r = _pivot(torso, Vector3(0.5, 0.58, -0.02), "ArmR")
	for arm in [arm_l, arm_r]:
		_sphere(arm, 0.2, Vector3.ZERO, Vector3.ONE, _mat_fur, 12)   # shoulder
		_capsule(arm, 0.15, 0.62, Vector3(0, -0.28, 0), _mat_fur)
		var fore := _pivot(arm, Vector3(0, -0.55, 0), "Forearm")
		_capsule(fore, 0.17, 0.62, Vector3(0, -0.27, 0), _mat_fur)
		var hand := _pivot(fore, Vector3(0, -0.6, 0), "Hand")
		_sphere(hand, 0.17, Vector3.ZERO, Vector3(1.0, 0.85, 1.15), _mat_skin, 12)
		if arm == arm_l:
			forearm_l = fore
			hand_l = hand
		else:
			forearm_r = fore
			hand_r = hand
	# short legs
	leg_l = _pivot(hips, Vector3(-0.22, -0.05, 0.02), "LegL")
	leg_r = _pivot(hips, Vector3(0.22, -0.05, 0.02), "LegR")
	for leg in [leg_l, leg_r]:
		_capsule(leg, 0.15, 0.42, Vector3(0, -0.15, 0), _mat_fur)
		var shin := _pivot(leg, Vector3(0, -0.3, 0), "Shin")
		_capsule(shin, 0.13, 0.36, Vector3(0, -0.12, 0), _mat_fur)
		_sphere(shin, 0.13, Vector3(0, -0.28, -0.08), Vector3(1.0, 0.55, 1.6), _mat_skin, 10)  # foot
		if leg == leg_l:
			shin_l = shin
		else:
			shin_r = shin
	set_color(base_color)
	set_camo(0.0, 1.0)


func set_color(c: Color) -> void:
	base_color = c
	for m in _mats:
		m.set_shader_parameter("base_color", c)


func set_camo(amount: float, visibility: float) -> void:
	for m in _mats:
		m.set_shader_parameter("camo", amount)
		m.set_shader_parameter("visibility", visibility)


func set_flash(v: float) -> void:
	for m in _mats:
		m.set_shader_parameter("flash", v)


func set_render_layer(layer_bits: int) -> void:
	for p in _parts:
		p.layers = layer_bits


func hand_global(left: bool) -> Vector3:
	return (hand_l if left else hand_r).global_position


## Main animation update. 'st' carries the gorilla's state for this frame.
## Returns "step" when a footstep should be played this frame.
func animate(delta: float, st: Dictionary) -> String:
	var event := ""
	var speed: float = st.speed
	var mode: String = st.mode
	var crouch: bool = st.crouch
	var k := 1.0 - exp(-14.0 * delta)
	var t_hips := Vector3(0, 0.62, 0)
	var r_torso := Vector3.ZERO
	var r_head := Vector3.ZERO
	var q_arm_l := Quaternion.IDENTITY
	var q_arm_r := Quaternion.IDENTITY
	var r_fore_l := 0.0
	var r_fore_r := 0.0
	var r_leg_l := 0.0
	var r_leg_r := 0.0
	var r_shin_l := 0.0
	var r_shin_r := 0.0
	var spread := 0.18

	match mode:
		"ground":
			var run := clampf(speed / 10.5, 0.0, 1.0)
			_phase += delta * (4.0 + speed * 1.05)
			if speed < 0.4:
				# idle: breathing and swaying arms
				var br := sin(Time.get_ticks_msec() * 0.003)
				t_hips.y += br * 0.015
				r_torso.x = 0.12 + br * 0.03
				q_arm_l = _qa(Vector3(0.15 + br * 0.05, 0, -0.12))
				q_arm_r = _qa(Vector3(0.15 + br * 0.05, 0, 0.12))
				r_fore_l = -0.3
				r_fore_r = -0.3
			else:
				var s := sin(_phase)
				var c := cos(_phase)
				t_hips.y += absf(c) * 0.08 * (0.4 + run)
				r_torso.x = lerpf(0.2, 0.75, run)            # leans forward into a knuckle run
				r_head.x = -r_torso.x * 0.7
				var swing := lerpf(0.7, 1.35, run)
				q_arm_l = _qa(Vector3(-0.2 - run * 0.7 + s * swing, 0, -0.15))
				q_arm_r = _qa(Vector3(-0.2 - run * 0.7 - s * swing, 0, 0.15))
				r_fore_l = -0.25 - maxf(0.0, -s) * 0.6
				r_fore_r = -0.25 - maxf(0.0, s) * 0.6
				r_leg_l = -s * 0.9 * (0.5 + run * 0.5)
				r_leg_r = s * 0.9 * (0.5 + run * 0.5)
				r_shin_l = maxf(0.0, s) * 1.0
				r_shin_r = maxf(0.0, -s) * 1.0
				var side := 1 if s > 0.0 else -1
				if side != _last_step_side:
					_last_step_side = side
					event = "step"
			if crouch:
				t_hips.y -= 0.22
				r_torso.x += 0.35
				r_leg_l -= 0.9
				r_leg_r -= 0.9
				r_shin_l += 1.5
				r_shin_r += 1.5
		"air":
			var vy: float = st.vy
			var up := clampf(vy / 8.0, -1.0, 1.0)
			r_torso.x = 0.15 - up * 0.1
			q_arm_l = _qa(Vector3(-1.6 - up * 0.6, 0, -0.9))
			q_arm_r = _qa(Vector3(-1.6 - up * 0.6, 0, 0.9))
			r_fore_l = -0.4
			r_fore_r = -0.4
			r_leg_l = -0.6 + up * 0.3
			r_leg_r = -0.3 + up * 0.3
			r_shin_l = 1.1
			r_shin_r = 0.7
		"climb":
			var cp: float = st.climb_phase
			var s := sin(cp)
			r_torso.x = -0.05
			r_head.x = -0.35
			q_arm_l = _qa(Vector3(-2.5 + s * 0.45, 0, -0.25))
			q_arm_r = _qa(Vector3(-2.5 - s * 0.45, 0, 0.25))
			r_fore_l = -0.5 - maxf(0.0, s) * 0.6
			r_fore_r = -0.5 - maxf(0.0, -s) * 0.6
			r_leg_l = -0.8 - s * 0.5
			r_leg_r = -0.8 + s * 0.5
			r_shin_l = 1.2
			r_shin_r = 1.2
			spread = 0.35
		"hang":
			var cp: float = st.climb_phase
			var s := sin(cp)
			r_torso.x = 0.0
			r_head.x = -0.6
			q_arm_l = _qa(Vector3(-3.0 + s * 0.25, 0, -0.15))
			q_arm_r = _qa(Vector3(-3.0 - s * 0.25, 0, 0.15))
			r_leg_l = -0.3 + s * 0.4
			r_leg_r = -0.3 - s * 0.4
			r_shin_l = 0.5
			r_shin_r = 0.5
		"swing":
			# right hand holds the vine overhead, body trails the motion
			var sv: Vector3 = st.swing_local
			r_torso.x = clampf(-sv.z * 0.06, -0.8, 0.8)
			r_torso.z = clampf(sv.x * 0.05, -0.6, 0.6)
			r_head.x = -0.3
			q_arm_r = _qa(Vector3(-3.05, 0, 0.1))
			q_arm_l = _qa(Vector3(-1.2, 0, -1.1))
			r_fore_l = -0.6
			r_leg_l = clampf(sv.z * 0.08, -1.0, 1.0) - 0.3
			r_leg_r = clampf(sv.z * 0.08, -1.0, 1.0) - 0.1
			r_shin_l = 0.8
			r_shin_r = 0.5
		"swim":
			_phase += delta * 5.0
			var s := sin(_phase)
			r_torso.x = 1.0
			r_head.x = -0.9
			q_arm_l = _qa(Vector3(-1.5 + s * 1.2, 0, -0.4))
			q_arm_r = _qa(Vector3(-1.5 - s * 1.2, 0, 0.4))
			r_leg_l = s * 0.5
			r_leg_r = -s * 0.5
		"stunned":
			_phase += delta * 9.0
			r_torso.x = 0.3
			r_head.z = sin(_phase) * 0.4
			q_arm_l = _qa(Vector3(0.2, 0, -1.2 + sin(_phase) * 0.3))
			q_arm_r = _qa(Vector3(0.2, 0, 1.2 - sin(_phase) * 0.3))

	# hand reaching for a grab target overrides the arm pose
	if st.has("reach_l") and st.reach_l != null:
		q_arm_l = _aim_arm(arm_l, st.reach_l)
		r_fore_l = -0.1
	if st.has("reach_r") and st.reach_r != null:
		q_arm_r = _aim_arm(arm_r, st.reach_r)
		r_fore_r = -0.1

	hips.position = hips.position.lerp(t_hips, k)
	# pose values above use "negative = forward/up"; flip to Godot's rotation sense here
	torso.rotation = _lerp_rot(torso.rotation, Vector3(-r_torso.x, r_torso.y, r_torso.z), k)
	head.rotation = _lerp_rot(head.rotation, Vector3(-r_head.x, r_head.y, r_head.z), k)
	arm_l.quaternion = arm_l.quaternion.slerp(q_arm_l, k)
	arm_r.quaternion = arm_r.quaternion.slerp(q_arm_r, k)
	forearm_l.rotation.x = lerp_angle(forearm_l.rotation.x, -r_fore_l, k)
	forearm_r.rotation.x = lerp_angle(forearm_r.rotation.x, -r_fore_r, k)
	leg_l.rotation = _lerp_rot(leg_l.rotation, Vector3(-r_leg_l, 0, -spread * 0.5), k)
	leg_r.rotation = _lerp_rot(leg_r.rotation, Vector3(-r_leg_r, 0, spread * 0.5), k)
	shin_l.rotation.x = lerp_angle(shin_l.rotation.x, -r_shin_l, k)
	shin_r.rotation.x = lerp_angle(shin_r.rotation.x, -r_shin_r, k)

	# blinking
	_blink -= delta
	var eye_scale := 1.0
	if _blink < 0.0:
		eye_scale = 0.1
		if _blink < -0.12:
			_blink = randf_range(2.0, 5.0)
	for e in _eyes:
		e.scale.y = lerpf(e.scale.y, eye_scale, 0.6)
	return event


func _aim_arm(arm: Node3D, target: Vector3) -> Quaternion:
	var parent_inv := (arm.get_parent() as Node3D).global_transform.basis.inverse()
	var dir := (parent_inv * (target - arm.global_position)).normalized()
	if dir.length_squared() < 0.01:
		return arm.quaternion
	return Quaternion(Vector3.DOWN, dir)


func _qa(v: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(-v.x, v.y, v.z))


func _lerp_rot(a: Vector3, b: Vector3, k: float) -> Vector3:
	return Vector3(lerp_angle(a.x, b.x, k), lerp_angle(a.y, b.y, k), lerp_angle(a.z, b.z, k))
