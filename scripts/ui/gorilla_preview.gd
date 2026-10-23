class_name GorillaPreview
extends SubViewportContainer
## A small 3D turntable showing your gorilla in the chosen colour.

var _vp: SubViewport
var _model: GorillaModel
var _t := 0.0
var _camo_demo := 0.0


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(300, 320)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.25, 3.2)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	cam.fov = 40
	_vp.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	light.light_energy = 1.3
	_vp.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.75, 0.6)
	e.ambient_light_energy = 0.8
	env.environment = e
	_vp.add_child(env)
	_model = GorillaModel.new()
	_vp.add_child(_model)
	_model.rotation.y = PI


func _process(delta: float) -> void:
	_t += delta
	_model.set_color(Game.profile_color)
	_model.rotation.y = PI + sin(_t * 0.6) * 0.7
	# show off the camouflage every few seconds
	var cycle := fmod(_t, 9.0)
	var target := 1.0 if cycle > 5.0 and cycle < 8.0 else 0.0
	_camo_demo = move_toward(_camo_demo, target, delta / 0.8)
	_model.set_camo(_camo_demo, 1.0)
	_model.animate(delta, {"speed": 0.0, "mode": "ground", "crouch": false, "vy": 0.0, "climb_phase": 0.0, "swing_local": Vector3.ZERO, "reach_l": null, "reach_r": null})
