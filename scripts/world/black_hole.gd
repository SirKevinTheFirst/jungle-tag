class_name BlackHole
extends Node3D
## A swirling black hole that bursts out of the jungle floor for a while.
## Walking into it drops you into the underground maze (decided by the host).

const RADIUS := 2.3
const PULL_RADIUS := 11.0
const PULL_SPEED := 9.0

var id := 0
var life := 20.0
var _age := 0.0
var _ring: MeshInstance3D
var _closing := false
var _marker: Label3D


func setup(p_id: int, p_life: float) -> void:
	id = p_id
	life = p_life


func _ready() -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS * 0.6
	cyl.height = 0.3
	cyl.radial_segments = 32
	var black := StandardMaterial3D.new()
	black.albedo_color = Color.BLACK
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = black
	disc.mesh = cyl
	disc.position.y = 0.05
	add_child(disc)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.15
	torus.outer_radius = RADIUS + 0.35
	torus.rings = 32
	torus.ring_segments = 8
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.45, 0.1, 0.8)
	glow.emission_enabled = true
	glow.emission = Color(0.55, 0.15, 1.0)
	glow.emission_energy_multiplier = 3.5
	torus.material = glow
	_ring.mesh = torus
	_ring.position.y = 0.15
	add_child(_ring)
	# dark swirl of particles being sucked down
	var p := GPUParticles3D.new()
	p.amount = 70
	p.lifetime = 1.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = RADIUS + 1.5
	pm.emission_ring_inner_radius = RADIUS
	pm.emission_ring_height = 0.2
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.radial_accel_min = -6.0
	pm.radial_accel_max = -4.0
	pm.tangential_accel_min = 5.0
	pm.tangential_accel_max = 8.0
	pm.gravity = Vector3(0, -1.5, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color = Color(0.35, 0.1, 0.6)
	p.process_material = pm
	var q := SphereMesh.new()
	q.radius = 0.1
	q.height = 0.2
	q.radial_segments = 6
	q.rings = 3
	var qm := StandardMaterial3D.new()
	qm.vertex_color_use_as_albedo = true
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = qm
	p.draw_pass_1 = q
	p.position.y = 0.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.2, 1.0)
	light.light_energy = 2.5
	light.omni_range = 9.0
	light.position.y = 1.0
	add_child(light)
	# tall purple beam so you can spot it over the trees
	var beam := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.3
	bc.bottom_radius = 1.2
	bc.height = 60.0
	bc.cap_top = false
	bc.cap_bottom = false
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.6, 0.25, 1.0, 0.35)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bc.material = beam_mat
	beam.mesh = bc
	beam.position.y = 30.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	# waypoint marker that shows through trees with the distance
	_marker = Label3D.new()
	_marker.text = "BLACK HOLE"
	_marker.font_size = 40
	_marker.pixel_size = 0.0015
	_marker.fixed_size = true
	_marker.no_depth_test = true
	_marker.modulate = Color(0.85, 0.6, 1.0)
	_marker.outline_size = 12
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.position.y = 6.0
	add_child(_marker)
	scale = Vector3(0.01, 0.01, 0.01)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play_at("round_end", global_position, 2.0, 0.5, 70.0)
	Sfx.play_at("infect", global_position, 0.0, 0.6, 50.0)


func _process(delta: float) -> void:
	_age += delta
	_ring.rotate_y(delta * 3.0)
	_ring.scale = Vector3.ONE * (1.0 + sin(_age * 6.0) * 0.05)
	var cam := get_viewport().get_camera_3d()
	if cam:
		_marker.text = "BLACK HOLE\n%d m" % int(cam.global_position.distance_to(global_position))
	if _age > life and not _closing:
		close()


func close() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func swallows(p: Vector3) -> bool:
	if _closing or _age < 0.6:
		return false
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	return d < RADIUS * 0.85 and absf(p.y - global_position.y) < 2.0
