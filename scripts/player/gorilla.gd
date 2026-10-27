class_name Gorilla
extends CharacterBody3D
## One gorilla: the local player, an AI bot (on the host) or a network puppet.
## Handles momentum movement, trunk/branch climbing, vine swinging, swimming,
## camouflage timers and visuals. Tag rules live in the game mode (host only).

enum Ctrl { LOCAL, AI, REMOTE }
enum State { GROUND, AIR, CLIMB, SWING, SWIM, MANTLE }

const WALK_SPEED := 6.5
const SPRINT_SPEED := 10.5
const CROUCH_SPEED := 3.0
const GROUND_ACCEL := 55.0
const GROUND_DECEL := 40.0
const MOMENTUM_DECAY := 7.0
const AIR_ACCEL := 14.0
const AIR_CONTROL_SPEED := 7.5
const JUMP_VELOCITY := 8.2
const GRAVITY := 22.0
const MAX_FALL := 45.0
const COYOTE := 0.12
const JUMP_BUFFER := 0.15

const CLIMB_SPEED := 4.3
const CLIMB_SPRINT_SPEED := 6.2
const CLIMB_REACH := 1.9
const CLIMB_STICK_DIST := 0.6
const HAND_PULL := 3.8
const WALL_JUMP_OUT := 6.5
const WALL_JUMP_UP := 7.0

const SWING_GRAVITY := 21.0
const SWING_PUMP := 13.0
const VINE_REACH := 2.7
const HAND_HEIGHT := 1.05
const RELEASE_BOOST := 1.12
const MAX_SWING_SPEED := 32.0

const TAGGER_SPEED_BONUS := 1.12   # chasers are a little faster, like in Gorilla Tag

const CAMO_MAX := 15.0
const CAMO_COOLDOWN := 20.0

const STAND_HEIGHT := 1.5
const CROUCH_HEIGHT := 0.95

class GInput:
	var move := Vector2.ZERO   # x = right, y = forward
	var yaw := 0.0
	var pitch := 0.0
	var jump := false          # pressed this frame
	var jump_held := false
	var sprint := false
	var crouch := false
	var grab_l := false        # held
	var grab_r := false
	var grab_l_pressed := false
	var grab_r_pressed := false
	var vine := false          # pressed this frame
	var camo := false          # pressed this frame

	func clear_edges() -> void:
		jump = false
		grab_l_pressed = false
		grab_r_pressed = false
		vine = false
		camo = false

var net_id := 1
var display_name := "Gorilla"
var color := Color("6b4a35")
var control: Ctrl = Ctrl.LOCAL
var state: State = State.AIR
var input := GInput.new()
var jungle: Jungle
var world: Node

# role / game flags (set by the game mode via world events)
var role := "runner"           # runner, it, infected, seeker, hider
var frozen := false            # seekers during hide time
var stun_time := 0.0
var tags := 0
var speed_boost := 0.0         # seconds left of the speed power-up
var banana_boost := 0.0        # seconds left of double sprint speed (10 bananas)
var jump_boost := 0.0          # seconds left of the super jump power-up
var score := 0.0

# camouflage
var camo_active := false
var camo_time := 0.0           # seconds of camo left
var camo_cooldown := 0.0       # seconds until camo can be used again
var camo_visual := 0.0         # smoothed 0..1 for the transition
var _camo_requested := false

# movement internals
var _coyote := 0.0
var _jump_buffer := 0.0
var _vine_buffer := 0.0
var _climb_normal := Vector3.FORWARD
var _climb_point := Vector3.ZERO
var _climb_boost := Vector3.ZERO
var _climb_phase := 0.0
var _climb_cooldown := 0.0
var _last_hand := 0            # 1 = left, 2 = right
var _hanging := false
var _vine: Vine = null
var _last_vine: Vine = null
var _last_vine_timer := 0.0
var _rope_len := 5.0
var _swing_vel := Vector3.ZERO
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_t := 0.0
var _crouched := false
var _was_on_floor := false
var _fall_speed := 0.0
var _model_yaw := 0.0
var _reach_l = null
var _reach_r = null
var _reach_timer_l := 0.0
var _reach_timer_r := 0.0
var _swipe_cooldown := 0.0
var _flash := 0.0
var _step_timer := 0.0

# remote interpolation
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_age := 0.0
var _net_state := 0
var _net_vine_id := -1
var _net_flags := 0
var _send_timer := 0.0

# nodes
var model: GorillaModel
var collider: CollisionShape3D
var capsule: CapsuleShape3D
var nameplate: Label3D
var _bubble: Label3D
var _bubble_time := 0.0
var role_ring: MeshInstance3D
var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var first_person := false
var binoculars := false           # local only: hold B to zoom in
var _bino_fov := 16.0
var leaf_burst: GPUParticles3D
var _cam_shake := 0.0


func setup(p_id: int, p_name: String, p_color: Color, p_control: Ctrl, p_jungle: Jungle, p_world: Node) -> void:
	net_id = p_id
	display_name = p_name
	color = p_color
	control = p_control
	jungle = p_jungle
	world = p_world
	name = "G_%d" % p_id


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.35
	max_slides = 5
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = STAND_HEIGHT
	collider = CollisionShape3D.new()
	collider.shape = capsule
	collider.position = Vector3(0, STAND_HEIGHT * 0.5, 0)
	add_child(collider)
	model = GorillaModel.new()
	model.name = "Model"
	add_child(model)
	model.set_color(color)
	_build_nameplate()
	_build_leaf_burst()
	if control == Ctrl.LOCAL:
		_build_camera()
		nameplate.visible = false
	_net_pos = global_position


## Shows a chat message in a speech bubble over the gorilla's head for a few seconds.
func say(text: String) -> void:
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.pixel_size = 0.005
		_bubble.font_size = 40
		_bubble.outline_size = 14
		_bubble.modulate = Color(1, 1, 0.9)
		_bubble.outline_modulate = Color(0.1, 0.08, 0.05)
		_bubble.width = 600.0
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_bubble.position = Vector3(0, 2.6, 0)
		_bubble.visibility_range_end = 40.0
		add_child(_bubble)
	_bubble.text = text
	_bubble.visible = true
	_bubble_time = 6.0


func _build_nameplate() -> void:
	nameplate = Label3D.new()
	nameplate.text = display_name
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = false
	nameplate.fixed_size = false
	nameplate.pixel_size = 0.006
	nameplate.font_size = 48
	nameplate.outline_size = 12
	nameplate.position = Vector3(0, 2.25, 0)
	nameplate.visibility_range_end = 45.0
	add_child(nameplate)
	role_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.4
	torus.rings = 16
	torus.ring_segments = 8
	role_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.05)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	role_ring.material_override = mat
	role_ring.position = Vector3(0, 2.0, 0)
	role_ring.visible = false
	role_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(role_ring)


func _build_leaf_burst() -> void:
	leaf_burst = GPUParticles3D.new()
	leaf_burst.emitting = false
	leaf_burst.one_shot = true
	leaf_burst.amount = 40
	leaf_burst.lifetime = 1.2
	leaf_burst.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.7
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.3, 0.8, 0.2))
	grad.set_color(1, Color(0.45, 0.35, 0.1))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_initial_ramp = gt
	leaf_burst.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.12)
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = lm
	leaf_burst.draw_pass_1 = quad
	leaf_burst.position = Vector3(0, 1.0, 0)
	leaf_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leaf_burst)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0, 1.45, 0)
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 4.2
	spring_arm.margin = 0.25
	spring_arm.collision_mask = 1
	spring_arm.position = Vector3(0.55, 0.25, 0)
	spring_arm.add_excluded_object(get_rid())
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	spring_arm.shape = sphere
	camera_pivot.add_child(spring_arm)
	camera = Camera3D.new()
	camera.fov = Settings.fov
	camera.far = Settings.view_distance + 60.0
	camera.near = 0.08
	camera.cull_mask = 0xFFFFF
	spring_arm.add_child(camera)
	camera.current = true
	model.set_render_layer(1 | 2)
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	if camera:
		camera.fov = Settings.fov
		camera.far = Settings.view_distance + 60.0


# ======================================================================== input
func _unhandled_input(event: InputEvent) -> void:
	if control != Ctrl.LOCAL:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Settings.mouse_sensitivity
		if binoculars:
			sens *= camera.fov / Settings.fov  # finer aim while zoomed in
		input.yaw -= event.relative.x * sens
		input.pitch -= event.relative.y * sens * (-1.0 if Settings.invert_y else 1.0)
		input.pitch = clampf(input.pitch, deg_to_rad(-80.0), deg_to_rad(70.0))
	elif binoculars and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_bino_fov = clampf(_bino_fov * (0.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.18), 6.0, 35.0)
	elif event.is_action_pressed("camera_toggle"):
		first_person = not first_person
		_apply_camera_mode()


func _apply_camera_mode() -> void:
	if spring_arm == null:
		return
	var fp := first_person or binoculars
	spring_arm.spring_length = 0.0 if fp else 4.2
	spring_arm.position = Vector3(0, 0.1, -0.1) if fp else Vector3(0.55, 0.25, 0)
	# layer 2 holds the local gorilla's own body; hide it in first person
	camera.cull_mask = 0xFFFFD if fp else 0xFFFFF


func _gather_local_input() -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not captured or (world and world.has_method("is_input_blocked") and world.is_input_blocked()):
		input.move = Vector2.ZERO
		input.sprint = false
		input.crouch = false
		input.jump_held = false
		input.grab_l = false
		input.grab_r = false
		return
	input.move = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	if input.move.length() > 1.0:
		input.move = input.move.normalized()
	input.sprint = Input.is_action_pressed("sprint")
	input.crouch = Input.is_action_pressed("crouch")
	input.jump_held = Input.is_action_pressed("jump")
	input.grab_l = Input.is_action_pressed("grab_left")
	input.grab_r = Input.is_action_pressed("grab_right")
	if Input.is_action_just_pressed("jump"):
		input.jump = true
	if Input.is_action_just_pressed("grab_left"):
		input.grab_l_pressed = true
	if Input.is_action_just_pressed("grab_right"):
		input.grab_r_pressed = true
	if Input.is_action_just_pressed("vine"):
		input.vine = true
	if Input.is_action_just_pressed("camo"):
		input.camo = true


# ======================================================================== helpers
func look_dir() -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.RIGHT, input.pitch).rotated(Vector3.UP, input.yaw)


func flat_forward() -> Vector3:
	return Vector3(-sin(input.yaw), 0, -cos(input.yaw))


func flat_right() -> Vector3:
	return Vector3(cos(input.yaw), 0, -sin(input.yaw))


func wish_dir() -> Vector3:
	var w := flat_forward() * input.move.y + flat_right() * input.move.x
	return w.limit_length(1.0)


func chest() -> Vector3:
	return global_position + Vector3(0, 0.95, 0)


func hand_point() -> Vector3:
	return global_position + Vector3(0, HAND_HEIGHT + 0.85, 0)


func is_tagger() -> bool:
	return role == "it" or role == "infected" or role == "seeker"


func horizontal_speed() -> float:
	var v := _net_vel if control == Ctrl.REMOTE else velocity
	return Vector2(v.x, v.z).length()


## How effective the camouflage is right now: moving fast weakens it.
func camo_effect() -> float:
	var spd := horizontal_speed()
	var penalty := clampf((spd - 2.5) / 10.0, 0.0, 0.45)
	return camo_visual * (1.0 - penalty)


## 0..1 how hard this gorilla is to notice (camouflage + foliage + crouch).
func stealth() -> float:
	var s := camo_effect() * 0.75
	if jungle:
		s = maxf(s, jungle.foliage_cover(global_position + Vector3(0, 0.8, 0)) * 0.7)
		if camo_visual > 0.1:
			s = clampf(s + jungle.foliage_cover(global_position + Vector3(0, 0.8, 0)) * 0.25, 0.0, 0.95)
	if _crouched:
		s += 0.1
	return clampf(s, 0.0, 0.95)


func _space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return _space().intersect_ray(q)


func _is_climbable(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var c: Object = hit.collider
	if c is Node and (c as Node).is_in_group("climbable"):
		return true
	# steep terrain (cliffs) is climbable too
	if c is Node and (c as Node).is_in_group("terrain") and hit.normal.y < 0.45:
		return true
	return false


# ======================================================================== main loop
func _physics_process(delta: float) -> void:
	if control == Ctrl.REMOTE:
		stun_time = maxf(0.0, stun_time - delta)
		banana_boost = maxf(0.0, banana_boost - delta)
		_remote_update(delta)
		_update_visuals(delta)
		return
	if control == Ctrl.LOCAL:
		_gather_local_input()
	_tick_timers(delta)
	_black_hole_pull(delta)
	if input.camo:
		_toggle_camo()
	if stun_time > 0.0 or frozen:
		_frozen_update(delta)
	else:
		match state:
			State.GROUND, State.AIR:
				_free_move(delta)
			State.CLIMB:
				_climb_update(delta)
			State.SWING:
				_swing_update(delta)
			State.SWIM:
				_swim_update(delta)
			State.MANTLE:
				_mantle_update(delta)
	_update_visuals(delta)
	input.clear_edges()
	_send_state(delta)
	# safety net: never fall out of the world
	if global_position.y < -110.0:
		respawn(world.random_spawn() if world else Vector3(0, 10, 0))


## Open black holes suck in anything that strays too close.
func _black_hole_pull(delta: float) -> void:
	if world == null or not ("holes" in world) or (state != State.GROUND and state != State.AIR):
		return
	for hid in world.holes:
		var h: Node3D = world.holes[hid]
		if not is_instance_valid(h):
			continue
		var to := h.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < BlackHole.PULL_RADIUS and d > 0.05 and absf(h.global_position.y - global_position.y) < 4.0:
			var k := 1.0 - d / BlackHole.PULL_RADIUS
			# drag straight toward the centre: gentle at the edge, impossible to resist near the middle
			var step := minf(d, BlackHole.PULL_SPEED * k * k * delta)
			global_position += to / d * step
			if control == Ctrl.LOCAL and k > 0.5:
				_cam_shake = maxf(_cam_shake, 0.15 * k)


func _tick_timers(delta: float) -> void:
	_coyote -= delta
	_jump_buffer -= delta
	_vine_buffer -= delta
	_climb_cooldown -= delta
	_last_vine_timer -= delta
	_swipe_cooldown -= delta
	stun_time = maxf(0.0, stun_time - delta)
	speed_boost = maxf(0.0, speed_boost - delta)
	banana_boost = maxf(0.0, banana_boost - delta)
	jump_boost = maxf(0.0, jump_boost - delta)
	if input.jump:
		_jump_buffer = JUMP_BUFFER
	if input.vine:
		_vine_buffer = 0.25
	_tick_camo(delta)


func _tick_camo(delta: float) -> void:
	if camo_active:
		camo_time = maxf(0.0, camo_time - delta)
		if camo_time <= 0.0 and Net.is_host() and world:
			world.server_camo_request(net_id, false)
	elif camo_cooldown > 0.0:
		var before := camo_cooldown
		camo_cooldown = maxf(0.0, camo_cooldown - delta)
		if before > 0.0 and camo_cooldown <= 0.0 and control == Ctrl.LOCAL:
			Sfx.play("camo_ready", -6.0)


func _toggle_camo() -> void:
	if camo_active or camo_cooldown <= 0.0:
		if control == Ctrl.LOCAL:
			Net.send_camo_request(not camo_active)
		elif world:
			world.server_camo_request(net_id, not camo_active)
	elif control == Ctrl.LOCAL:
		Sfx.play("beep", -10.0, 0.7)


## Applied on every peer when the host confirms a camouflage change.
func apply_camo_state(on: bool, time_left: float, cooldown: float) -> void:
	var changed := on != camo_active
	camo_active = on
	camo_time = time_left
	camo_cooldown = cooldown
	if changed:
		Sfx.play_at("camo_on" if on else "camo_off", global_position + Vector3(0, 1, 0), -2.0 if on else -4.0)
		if on:
			leaf_burst.restart()
			leaf_burst.emitting = true


## Applied on every peer when the host confirms a power-up pickup.
func apply_powerup(kind: String) -> void:
	match kind:
		"speed":
			speed_boost = 8.0
		"jump":
			jump_boost = 8.0
		"camo":
			camo_cooldown = 0.0
	flash()
	leaf_burst.restart()
	leaf_burst.emitting = true
	Sfx.play_at("camo_ready", global_position + Vector3(0, 1, 0), 2.0, 1.3)


func respawn(p: Vector3) -> void:
	_release_vine(false)
	global_position = p
	velocity = Vector3.ZERO
	state = State.AIR
	_net_pos = p


# ======================================================================== ground & air
func _free_move(delta: float) -> void:
	_update_crouch(input.crouch and state == State.GROUND)
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE
		state = State.GROUND
	else:
		state = State.AIR
	var wish := wish_dir()
	var target_speed := CROUCH_SPEED if _crouched else (SPRINT_SPEED if input.sprint else WALK_SPEED)
	if is_tagger():
		target_speed *= TAGGER_SPEED_BONUS
	if speed_boost > 0.0:
		target_speed *= 1.5
	if banana_boost > 0.0 and input.sprint and not _crouched:
		target_speed *= 2.0
	if world and world.get("frenzy"):
		target_speed *= 1.15
	var h := Vector3(velocity.x, 0, velocity.z)
	if on_floor:
		var desired := wish * target_speed
		if h.length() > target_speed + 0.5 and wish.dot(h.normalized()) > 0.3:
			# carry momentum from swings and jumps, bleed it off gently
			h = h.move_toward(desired, MOMENTUM_DECAY * delta)
			h = h.lerp(h.length() * wish, 1.0 - exp(-4.0 * delta))
		elif wish.length() > 0.05:
			h = h.move_toward(desired, GROUND_ACCEL * delta)
		else:
			h = h.move_toward(Vector3.ZERO, GROUND_DECEL * delta)
	else:
		if wish.length() > 0.05:
			var cur := h.length()
			var nh := h + wish * AIR_ACCEL * delta
			var cap := maxf(cur, AIR_CONTROL_SPEED)
			if nh.length() > cap:
				nh = nh.normalized() * cap
			h = nh
		h *= 1.0 - 0.04 * delta
	velocity.x = h.x
	velocity.z = h.z
	if not on_floor:
		var g := GRAVITY * (0.78 if input.jump_held and velocity.y > 0.0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -MAX_FALL)
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY * (1.08 if _crouched else 1.0) * (1.6 if jump_boost > 0.0 else 1.0)
		_jump_buffer = 0.0
		_coyote = 0.0
		state = State.AIR
		Sfx.play_at("jump", global_position, -8.0, randf_range(0.9, 1.1))
	if not on_floor:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor and _fall_speed > 7.0:
		Sfx.play_at("land", global_position, -6.0 + minf(_fall_speed * 0.2, 6.0))
		if control == Ctrl.LOCAL:
			_cam_shake = clampf(_fall_speed / 40.0, 0.0, 0.3)
	if now_floor:
		_fall_speed = 0.0
	_was_on_floor = now_floor
	# grabbing
	var pressed_hand := 1 if input.grab_l_pressed else (2 if input.grab_r_pressed else 0)
	if pressed_hand != 0:
		if not _try_start_climb(pressed_hand):
			_swipe(pressed_hand)
	elif (input.grab_l or input.grab_r) and not now_floor and _climb_cooldown <= 0.0:
		# holding a hand out while flying at a tree latches on automatically
		_try_start_climb(1 if input.grab_l else 2)
	if state != State.CLIMB and _vine_buffer > 0.0:
		_try_grab_vine()
	if state != State.CLIMB and state != State.SWING and jungle and jungle.is_in_water(global_position + Vector3(0, 0.7, 0)):
		state = State.SWIM
		Sfx.play_at("land", global_position, -4.0, 0.6)


func _update_crouch(want: bool) -> void:
	if want == _crouched:
		return
	if not want:
		# only stand up if there is room
		var hit := _ray(global_position + Vector3(0, CROUCH_HEIGHT, 0), global_position + Vector3(0, STAND_HEIGHT + 0.1, 0))
		if not hit.is_empty():
			return
	_crouched = want
	capsule.height = CROUCH_HEIGHT if want else STAND_HEIGHT
	collider.position.y = capsule.height * 0.5


func _swipe(hand: int) -> void:
	if _swipe_cooldown > 0.0:
		return
	_swipe_cooldown = 0.35
	var target := chest() + look_dir() * 1.6
	if hand == 1:
		_reach_l = target
		_reach_timer_l = 0.25
	else:
		_reach_r = target
		_reach_timer_r = 0.25
	if control == Ctrl.LOCAL:
		Net.send_swipe()
	elif world:
		world.server_swipe(net_id)


# ======================================================================== climbing
func _try_start_climb(hand: int) -> bool:
	if _climb_cooldown > 0.0 and state == State.AIR:
		return false
	var o := chest()
	var dirs := [look_dir(), flat_forward(), Vector3.UP, (flat_forward() + Vector3.UP).normalized(), (flat_forward() + Vector3.DOWN * 0.5).normalized()]
	if wish_dir().length() > 0.1:
		dirs.append(wish_dir())
	for d in dirs:
		var hit := _ray(o, o + d * CLIMB_REACH)
		if _is_climbable(hit) and hit.normal.y < 0.7:
			_start_climb(hit, hand)
			return true
	return false


func _start_climb(hit: Dictionary, hand: int) -> void:
	if state == State.SWING:
		_release_vine(false)
	_update_crouch(false)
	state = State.CLIMB
	_climb_normal = hit.normal
	_climb_point = hit.position
	_hanging = _climb_normal.y < -0.55
	_last_hand = hand
	# keep a little of the incoming momentum along the surface
	velocity = (velocity - _climb_normal * velocity.dot(_climb_normal)) * 0.35
	_climb_boost = Vector3.ZERO
	_set_reach(hand, hit.position)
	Sfx.play_at("climb_%d" % randi_range(0, 2), hit.position, -4.0)


func _set_reach(hand: int, p: Vector3) -> void:
	if hand == 1:
		_reach_l = p
		_reach_timer_l = 0.35
	else:
		_reach_r = p
		_reach_timer_r = 0.35


func _climb_update(delta: float) -> void:
	var holding := input.grab_l or input.grab_r
	if not holding or input.crouch:
		_exit_climb(_climb_normal * 1.5)
		return
	if input.jump:
		if _hanging:
			if _try_mantle_up():
				return
			_exit_climb(Vector3.DOWN * 1.0)
			return
		# wall jump: kick off the surface, up and towards where we look
		var out := _climb_normal * WALL_JUMP_OUT + Vector3.UP * WALL_JUMP_UP + Vector3(look_dir().x, 0, look_dir().z) * 3.5
		_exit_climb(out)
		_climb_cooldown = 0.3
		Sfx.play_at("jump", global_position, -6.0)
		return
	var o := chest()
	var hit := _ray(o, o - _climb_normal * (CLIMB_REACH + 0.4))
	if not _is_climbable(hit):
		# maybe we went past the top: try to pull ourselves onto it
		if input.move.y > 0.1 and _try_mantle_ledge():
			return
		var hit2 := _ray(o + Vector3.DOWN * 0.6, o + Vector3.DOWN * 0.6 - _climb_normal * (CLIMB_REACH + 0.4))
		if not _is_climbable(hit2):
			_exit_climb(Vector3.ZERO)
			return
		hit = hit2
	_climb_normal = _climb_normal.slerp(hit.normal, 0.3).normalized()
	_climb_point = hit.position
	_hanging = _climb_normal.y < -0.55
	if _climb_normal.y > 0.72:
		# we are on top of the surface now
		state = State.GROUND
		return
	var n := _climb_normal
	var move := Vector3.ZERO
	var speed := CLIMB_SPRINT_SPEED if input.sprint else CLIMB_SPEED
	if _hanging:
		var f := flat_forward()
		var r := flat_right()
		move = (f * input.move.y + r * input.move.x)
		move = (move - n * move.dot(n)).limit_length(1.0)
		speed *= 0.8
	else:
		var up_t := (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
		var right_t := up_t.cross(n).normalized()
		var cam_r := flat_right()
		var sgn := 1.0 if cam_r.dot(right_t) >= -0.2 else -1.0
		move = (up_t * input.move.y + right_t * sgn * input.move.x).limit_length(1.0)
	# alternate hands to pull yourself along faster, Gorilla Tag style
	var pressed := 1 if input.grab_l_pressed else (2 if input.grab_r_pressed else 0)
	if pressed != 0:
		var boost_dir := move if move.length() > 0.1 else (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
		var strength := HAND_PULL if pressed != _last_hand else HAND_PULL * 0.4
		_climb_boost += boost_dir * strength
		_climb_boost = _climb_boost.limit_length(7.0)
		_last_hand = pressed
		_set_reach(pressed, hit.position + boost_dir * 0.6)
		_climb_phase += PI * 0.5
		Sfx.play_at("climb_%d" % randi_range(0, 2), hit.position, -5.0, randf_range(0.9, 1.15))
	_climb_boost *= exp(-4.5 * delta)
	if move.length() > 0.05:
		_climb_phase += delta * speed * 2.2
		_step_timer -= delta * speed
		if _step_timer <= 0.0:
			_step_timer = 2.4
			Sfx.play_at("climb_%d" % randi_range(0, 2), hit.position, -12.0, randf_range(0.85, 1.1))
	var hit_pos: Vector3 = hit.position
	var dist := (o - hit_pos).dot(n)
	var stick := -n * (dist - CLIMB_STICK_DIST) * 10.0
	var target := move * speed + _climb_boost + stick
	velocity = velocity.lerp(target, 1.0 - exp(-14.0 * delta))
	move_and_slide()
	if is_on_floor() and input.move.y < -0.1 and not _hanging:
		state = State.GROUND


func _exit_climb(push: Vector3) -> void:
	state = State.AIR
	velocity += push
	_climb_cooldown = maxf(_climb_cooldown, 0.15)
	_hanging = false


func _try_mantle_ledge() -> bool:
	# look for a floor just above and beyond the surface edge
	var probe := chest() + Vector3.UP * 1.4 - _climb_normal * 0.9
	var down := _ray(probe, probe + Vector3.DOWN * 2.6)
	if down.is_empty() or down.normal.y < 0.6:
		return false
	return _begin_mantle(down.position + Vector3.UP * 0.05)


func _try_mantle_up() -> bool:
	# hanging under a branch: pull up and over it
	var f := flat_forward()
	for off in [Vector3.ZERO, f * 0.8, -f * 0.8]:
		var probe: Vector3 = _climb_point + Vector3.UP * 3.0 + off
		var down := _ray(probe, probe + Vector3.DOWN * 3.2)
		if not down.is_empty() and down.normal.y > 0.6 and down.position.y > _climb_point.y:
			if _begin_mantle(down.position + Vector3.UP * 0.05):
				return true
	return false


func _begin_mantle(target: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = STAND_HEIGHT
	q.shape = shape
	q.transform = Transform3D(Basis(), target + Vector3(0, STAND_HEIGHT * 0.5 + 0.05, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	if not _space().intersect_shape(q, 1).is_empty():
		return false
	state = State.MANTLE
	_mantle_from = global_position
	_mantle_to = target
	_mantle_t = 0.0
	velocity = Vector3.ZERO
	Sfx.play_at("climb_%d" % randi_range(0, 2), target, -4.0, 0.9)
	return true


func _mantle_update(delta: float) -> void:
	_mantle_t = minf(1.0, _mantle_t + delta / 0.28)
	var t := _mantle_t
	# arc: rise first, then move over the edge
	var p := _mantle_from.lerp(_mantle_to, t)
	p.y = lerpf(_mantle_from.y, _mantle_to.y, minf(1.0, t * 1.6)) + sin(t * PI) * 0.3
	global_position = p
	if _mantle_t >= 1.0:
		state = State.GROUND
		velocity = flat_forward() * 2.0


# ======================================================================== vines
func _try_grab_vine() -> bool:
	if jungle == null:
		return false
	var hp := hand_point()
	var best: Vine = null
	var best_d := VINE_REACH
	for v in jungle.vines:
		if v == _last_vine and _last_vine_timer > 0.0:
			continue
		if v.grabbed_by != null and v.grabbed_by != self:
			continue
		var a := v.anchor()
		if absf(a.x - hp.x) > v.length + 3.0 or absf(a.z - hp.z) > v.length + 3.0:
			continue
		var cp := v.closest_point(hp)
		var d := minf(cp.distance_to(hp), cp.distance_to(chest()))
		if d < best_d:
			best_d = d
			best = v
	if best == null:
		return false
	_grab_vine(best)
	return true


func _grab_vine(v: Vine) -> void:
	_vine_buffer = 0.0
	_update_crouch(false)
	_vine = v
	_rope_len = clampf(v.anchor().distance_to(hand_point()), 2.5, v.length)
	_swing_vel = velocity
	state = State.SWING
	v.grab(self)
	v.hand_pos = hand_point()
	_reach_r = null
	Sfx.play_at("vine_grab", hand_point(), -3.0)


func _swing_update(delta: float) -> void:
	if _vine == null:
		state = State.AIR
		return
	if input.vine or input.jump:
		_release_vine(input.jump)
		return
	var anchor := _vine.anchor()
	var v := _swing_vel
	v.y -= SWING_GRAVITY * delta
	var hand := hand_point()
	var rope_dir := (hand - anchor).normalized()
	# pump: push along the tangent in the direction you steer
	var wish := wish_dir()
	if wish.length() > 0.05:
		var tangential := wish - rope_dir * wish.dot(rope_dir)
		v += tangential * SWING_PUMP * delta * (1.2 if input.sprint else 1.0)
	# slide down the vine with crouch, climb it with sprint + forward is pump; keep simple
	if input.crouch:
		_rope_len = minf(_vine.length, _rope_len + 3.0 * delta)
	v *= 1.0 - 0.025 * delta
	v = v.limit_length(MAX_SWING_SPEED)
	var p := hand + v * delta
	var d := p - anchor
	if d.length() > _rope_len:
		var radial := d.normalized()
		p = anchor + radial * _rope_len
		var vr := v.dot(radial)
		if vr > 0.0:
			v -= radial * vr
	velocity = (p - hand) / delta
	move_and_slide()
	if get_slide_collision_count() > 0:
		v = v.lerp(velocity, 0.5)
	_swing_vel = v
	_vine.hand_pos = hand_point()
	_vine.hand_vel = v
	# whoosh at the bottom of a fast swing
	_step_timer -= delta
	if v.length() > 9.0 and _step_timer <= 0.0 and v.y > -1.0 and v.y < 1.0:
		_step_timer = 0.8
		Sfx.play_at("swing", global_position, -6.0 + minf(v.length() * 0.3, 6.0), randf_range(0.9, 1.1))
	if is_on_floor() and v.length() < 2.0:
		_release_vine(false)


func _release_vine(jumped: bool) -> void:
	if _vine == null:
		if state == State.SWING:
			state = State.AIR
		return
	var v := _swing_vel * RELEASE_BOOST + Vector3.UP * (4.0 if jumped else 1.2)
	_vine.release(_swing_vel)
	_last_vine = _vine
	_last_vine_timer = 0.45
	_vine = null
	state = State.AIR
	velocity = v
	_climb_cooldown = 0.0
	if _swing_vel.length() > 6.0:
		Sfx.play_at("swing", global_position, -4.0, 1.2)


func current_vine_id() -> int:
	return _vine.id if _vine else -1


# ======================================================================== swimming / frozen
func _swim_update(delta: float) -> void:
	_update_crouch(false)
	var wish := wish_dir()
	var target := wish * (5.0 if input.sprint else 3.8)
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-4.0 * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-4.0 * delta))
	var surface_y := Jungle.WATER_Y - 0.95
	velocity.y = lerpf(velocity.y, (surface_y - global_position.y) * 4.0, 1.0 - exp(-5.0 * delta))
	if input.jump and global_position.y > surface_y - 0.4:
		velocity.y = JUMP_VELOCITY * 0.95
		state = State.AIR
	move_and_slide()
	if state == State.SWIM and not jungle.is_in_water(global_position + Vector3(0, 0.5, 0)):
		state = State.AIR
	if _vine_buffer > 0.0:
		_try_grab_vine()
	if input.grab_l_pressed or input.grab_r_pressed:
		_try_start_climb(1 if input.grab_l_pressed else 2)


func _frozen_update(delta: float) -> void:
	if state == State.SWING:
		_release_vine(false)
	if state == State.CLIMB:
		state = State.AIR
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
	move_and_slide()


# ======================================================================== visuals
func _anim_mode() -> String:
	var s := state if control != Ctrl.REMOTE else _net_state
	if stun_time > 0.0:
		return "stunned"
	match s:
		State.GROUND:
			return "ground"
		State.CLIMB:
			return "hang" if (_hanging or (control == Ctrl.REMOTE and _net_flags & 4)) else "climb"
		State.SWING:
			return "swing"
		State.SWIM:
			return "swim"
		State.MANTLE:
			return "climb"
	return "air"


func _update_visuals(delta: float) -> void:
	var vel := _net_vel if control == Ctrl.REMOTE else velocity
	var mode := _anim_mode()
	# body facing
	var target_yaw := _model_yaw
	var hv := Vector2(vel.x, vel.z)
	if mode == "climb" or mode == "hang":
		var n := _climb_normal
		if control == Ctrl.REMOTE:
			target_yaw = _model_yaw
		elif Vector2(n.x, n.z).length() > 0.2 and mode == "climb":
			target_yaw = atan2(n.x, n.z)
		else:
			target_yaw = input.yaw
	elif mode == "swing" and hv.length() > 1.0:
		target_yaw = atan2(-vel.x, -vel.z)
	elif hv.length() > 0.6:
		target_yaw = atan2(-vel.x, -vel.z)
	elif control == Ctrl.LOCAL and state == State.GROUND and input.move.length() > 0.1:
		target_yaw = input.yaw
	if control != Ctrl.REMOTE:
		_model_yaw = lerp_angle(_model_yaw, target_yaw, 1.0 - exp(-12.0 * delta))
	model.rotation.y = lerp_angle(model.rotation.y, _model_yaw, 1.0 - exp(-18.0 * delta))
	# swing: tilt along the rope
	if mode == "swing":
		var vine := _vine if control != Ctrl.REMOTE else _remote_vine()
		if vine:
			var rope := (vine.anchor() - hand_point()).normalized()
			var local_rope := model.global_transform.basis.inverse() * rope
			model.rotation.x = lerpf(model.rotation.x, clampf(-local_rope.z, -0.9, 0.9), 0.2)
			model.rotation.z = lerpf(model.rotation.z, clampf(local_rope.x, -0.9, 0.9), 0.2)
	else:
		model.rotation.x = lerpf(model.rotation.x, 0.0, 0.2)
		model.rotation.z = lerpf(model.rotation.z, 0.0, 0.2)
	_reach_timer_l -= delta
	_reach_timer_r -= delta
	if _reach_timer_l <= 0.0:
		_reach_l = null
	if _reach_timer_r <= 0.0:
		_reach_r = null
	var swing_local := model.global_transform.basis.inverse() * vel
	var crouched := _crouched if control != Ctrl.REMOTE else bool(_net_flags & 1)
	var ev := model.animate(delta, {
		"speed": hv.length(), "mode": mode, "crouch": crouched, "vy": vel.y,
		"climb_phase": _climb_phase, "swing_local": swing_local,
		"reach_l": _reach_l, "reach_r": _reach_r,
	})
	if ev == "step" and mode == "ground":
		var vol := -14.0 if crouched else (-6.0 if hv.length() > 8.0 else -9.0)
		Sfx.play_at("step_%d" % randi_range(0, 3), global_position, vol, randf_range(0.9, 1.1), 30.0)
	# camouflage transition
	var target_camo := 1.0 if camo_active else 0.0
	camo_visual = move_toward(camo_visual, target_camo, delta / 0.8)
	var eff := camo_effect()
	var vis := 1.0 - eff * 0.82
	if control == Ctrl.LOCAL:
		vis = maxf(vis, 0.6)
	model.set_camo(camo_visual, vis)
	nameplate.modulate.a = 1.0 - eff
	nameplate.outline_modulate.a = 1.0 - eff
	role_ring.visible = is_tagger() and control != Ctrl.LOCAL
	if role_ring.visible:
		role_ring.rotate_y(delta * 2.5)
		(role_ring.material_override as StandardMaterial3D).albedo_color.a = 1.0 - eff * 0.8
		role_ring.transparency = eff * 0.85
	if _bubble_time > 0.0:
		_bubble_time -= delta
		_bubble.visible = _bubble_time > 0.0 and control != Ctrl.LOCAL
	_flash = maxf(0.0, _flash - delta * 2.5)
	model.set_flash(_flash)
	if camera_pivot:
		camera_pivot.rotation = Vector3(input.pitch, input.yaw, 0)
		if _cam_shake > 0.0:
			_cam_shake = maxf(0.0, _cam_shake - delta)
			camera.h_offset = randf_range(-1, 1) * _cam_shake * 0.3
			camera.v_offset = randf_range(-1, 1) * _cam_shake * 0.3
		else:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		var want_bino: bool = control == Ctrl.LOCAL and Input.is_action_pressed("binoculars") \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not (world and world.is_input_blocked())
		if want_bino != binoculars:
			binoculars = want_bino
			_apply_camera_mode()
			Sfx.play("ui_click", -4.0, 0.7 if binoculars else 0.55)
		if binoculars:
			camera.fov = lerpf(camera.fov, _bino_fov, 1.0 - exp(-14.0 * delta))
		else:
			# a touch of speed FOV
			var spd := vel.length()
			camera.fov = lerpf(camera.fov, Settings.fov + clampf((spd - 8.0) * 0.8, 0.0, 14.0), 1.0 - exp(-8.0 * delta))


## Updates the visual for a role change (called on all peers).
func set_role(r: String) -> void:
	role = r
	match r:
		"infected":
			model.set_color(Color(1.0, 0.42, 0.12))
			nameplate.modulate = Color(1.0, 0.6, 0.3)
		"it", "seeker":
			model.set_color(color)
			nameplate.modulate = Color(1.0, 0.45, 0.35)
		"frozen":
			model.set_color(Color(0.55, 0.85, 1.0))
			nameplate.modulate = Color(0.6, 0.9, 1.0)
		"out":
			model.set_color(Color(0.32, 0.32, 0.34))
			nameplate.modulate = Color(0.6, 0.6, 0.6)
		"red":
			model.set_color(color.lerp(Color(0.9, 0.15, 0.1), 0.65))
			nameplate.modulate = Color(1.0, 0.45, 0.4)
		"blue":
			model.set_color(color.lerp(Color(0.15, 0.35, 0.95), 0.65))
			nameplate.modulate = Color(0.5, 0.65, 1.0)
		_:
			model.set_color(color)
			nameplate.modulate = Color.WHITE
	(role_ring.material_override as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.2) if r == "infected" else Color(1.0, 0.25, 0.1)


func flash() -> void:
	_flash = 1.0


# ======================================================================== networking
## Packs the state that other peers need to render this gorilla.
func pack_state() -> PackedFloat32Array:
	var p := global_position if control != Ctrl.REMOTE else _net_pos
	var v := velocity if control != Ctrl.REMOTE else _net_vel
	var st := state if control != Ctrl.REMOTE else _net_state
	var flags := (1 if _crouched else 0) | (2 if input.sprint else 0) | (4 if _hanging else 0)
	if control == Ctrl.REMOTE:
		flags = _net_flags
	var vid := current_vine_id() if control != Ctrl.REMOTE else _net_vine_id
	return PackedFloat32Array([p.x, p.y, p.z, v.x, v.y, v.z, _model_yaw, float(st), float(vid), float(flags), _climb_phase, input.yaw])


const STATE_SIZE := 12


func apply_net_state(d: PackedFloat32Array, offset: int = 0) -> void:
	_net_pos = Vector3(d[offset], d[offset + 1], d[offset + 2])
	_net_vel = Vector3(d[offset + 3], d[offset + 4], d[offset + 5])
	_model_yaw = d[offset + 6]
	_net_state = int(d[offset + 7])
	_net_vine_id = int(d[offset + 8])
	_net_flags = int(d[offset + 9])
	_climb_phase = d[offset + 10]
	input.yaw = d[offset + 11]
	_net_age = 0.0
	if global_position.distance_to(_net_pos) > 8.0:
		global_position = _net_pos


func _remote_update(delta: float) -> void:
	_net_age += delta
	_tick_camo(delta)
	var predicted := _net_pos + _net_vel * minf(_net_age, 0.25)
	global_position = global_position.lerp(predicted, 1.0 - exp(-14.0 * delta))
	_crouched = bool(_net_flags & 1)
	_hanging = bool(_net_flags & 4)
	# show the vine being held
	var vine := _remote_vine()
	if vine:
		if vine.grabbed_by != self:
			if _vine and _vine != vine and _vine.grabbed_by == self:
				_vine.release(_net_vel)
			vine.grab(self)
			_vine = vine
		vine.hand_pos = hand_point()
		vine.hand_vel = _net_vel
	elif _vine:
		if _vine.grabbed_by == self:
			_vine.release(_net_vel)
		_vine = null


func _remote_vine() -> Vine:
	if _net_vine_id >= 0 and jungle and _net_vine_id < jungle.vines.size():
		return jungle.vines[_net_vine_id]
	return null


func _send_state(delta: float) -> void:
	if control != Ctrl.LOCAL or Net.is_host() or not Net.is_online:
		return
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = 1.0 / Net.SEND_RATE
		Net.client_state.rpc_id(1, pack_state())
