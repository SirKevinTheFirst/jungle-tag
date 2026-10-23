class_name Weather
extends Node
## Rain and sunshine. Matches start in light rain under grey clouds; every 3 minutes the
## host flips the weather and every peer fades the sky, light, fog, rain and sound over a few seconds.

const CHANGE_EVERY := 180.0
const FADE_TIME := 10.0

const RAIN := {
	"top": Color(0.13, 0.14, 0.17), "horizon": Color(0.32, 0.33, 0.35), "sky_energy": 0.55,
	"sun": 0.12, "sun_color": Color(0.75, 0.8, 0.9), "ambient": 0.42,
	"fog": Color(0.24, 0.26, 0.29), "fog_mul": 1.7, "exposure": 0.85, "saturation": 0.85,
}
const SUN := {
	"top": Color(0.2, 0.4, 0.75), "horizon": Color(0.78, 0.62, 0.45), "sky_energy": 0.95,
	"sun": 0.95, "sun_color": Color(1.0, 0.86, 0.66), "ambient": 0.55,
	"fog": Color(0.42, 0.47, 0.52), "fog_mul": 1.0, "exposure": 0.95, "saturation": 1.18,
}

var world: Node
var raining := true
var mix := 1.0              # 1 = full rain look, 0 = full sun
var _timer := CHANGE_EVERY
var _rain: GPUParticles3D
var _sound: AudioStreamPlayer
var _thunder_timer := 25.0
var _flash := 0.0


func setup(p_world: Node) -> void:
	world = p_world
	_build_rain()
	_sound = AudioStreamPlayer.new()
	_sound.stream = Sfx.get_stream("amb_rain")
	_sound.bus = "Ambience"
	_sound.volume_db = -8.0
	add_child(_sound)
	_sound.play()
	_apply()


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = [900, 1600, 2400, 3200][clampi(Settings.quality, 0, 3)]
	_rain.lifetime = 1.3
	_rain.preprocess = 1.3
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 1, 26)
	pm.direction = Vector3(0.08, -1, 0.04)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3(0, -6, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	_rain.draw_pass_1 = q
	add_child(_rain)


## Host: time the weather changes.
func _process(delta: float) -> void:
	if Net.is_host() and world.mode and world.mode.phase != "warmup":
		_timer -= delta
		if _timer <= 0.0:
			_timer = CHANGE_EVERY
			Net.broadcast_event("weather", {"rain": not raining})
	var target := 1.0 if raining else 0.0
	mix = move_toward(mix, target, delta / FADE_TIME)
	# rain follows the camera, and never falls in the underground maze
	var cam := get_viewport().get_camera_3d()
	var underground := cam != null and cam.global_position.y < -40.0
	if cam:
		_rain.global_position = cam.global_position + Vector3(0, 14, 0)
	_rain.amount_ratio = 0.0 if underground else mix
	_rain.emitting = mix > 0.01 and not underground
	_sound.volume_db = linear_to_db(maxf(mix * (0.2 if underground else 1.0), 0.0001)) - 8.0
	# the odd rumble of thunder with a flash while it pours
	if raining and mix > 0.9:
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_thunder_timer = randf_range(25.0, 60.0)
			_flash = 1.0
			get_tree().create_timer(randf_range(0.4, 1.6)).timeout.connect(func(): Sfx.play("thunder", -4.0 if not underground else -16.0, randf_range(0.85, 1.1)))
	_flash = maxf(0.0, _flash - delta * 3.0)
	_apply()


func set_raining(on: bool) -> void:
	if on == raining:
		return
	raining = on
	_timer = CHANGE_EVERY
	if world.hud:
		if on:
			world.hud.show_message("IT'S STARTING TO RAIN", "Grey skies roll in over the jungle")
		else:
			world.hud.show_message("THE SUN IS COMING OUT", "The rain clears up")


func _apply() -> void:
	var env: Environment = world.env
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	var k := mix
	sky_mat.sky_top_color = SUN.top.lerp(RAIN.top, k)
	sky_mat.sky_horizon_color = SUN.horizon.lerp(RAIN.horizon, k)
	sky_mat.sky_energy_multiplier = lerpf(SUN.sky_energy, RAIN.sky_energy, k) + _flash * 1.5
	world.sun.light_energy = lerpf(SUN.sun, RAIN.sun, k) + _flash * 2.0
	world.sun.light_color = SUN.sun_color.lerp(RAIN.sun_color, k)
	env.ambient_light_energy = lerpf(SUN.ambient, RAIN.ambient, k) + _flash * 0.8
	env.fog_light_color = SUN.fog.lerp(RAIN.fog, k)
	env.fog_density = clampf(1.6 / Settings.view_distance, 0.004, 0.012) * lerpf(SUN.fog_mul, RAIN.fog_mul, k)
	env.tonemap_exposure = lerpf(SUN.exposure, RAIN.exposure, k)
	env.adjustment_saturation = lerpf(SUN.saturation, RAIN.saturation, k)
