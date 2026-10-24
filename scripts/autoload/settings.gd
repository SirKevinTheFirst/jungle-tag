extends Node
## Persistent user settings (graphics, audio, controls) and input map setup.

signal changed

const PATH := "user://settings.cfg"

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]

var quality: int = 2
var fullscreen: bool = false
var vsync: bool = true
var max_fps: int = 0           # 0 = unlimited
var render_scale: float = 1.0
var view_distance: float = 260.0
var vegetation_density: float = 1.0
var shadows: bool = true
var ssao: bool = true
var glow: bool = true
var fov: float = 80.0
var mouse_sensitivity: float = 0.0025
var invert_y: bool = false
var master_volume: float = 0.8
var music_volume: float = 0.5
var sfx_volume: float = 0.9
var ambience_volume: float = 0.8
var show_fps: bool = false


func _ready() -> void:
	_setup_input_map()
	_ensure_audio_buses()
	load_settings()
	apply()


func _setup_input_map() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL, KEY_C],
		"vine": [KEY_E],
		"camo": [KEY_G],
		"pause": [KEY_ESCAPE],
		"scoreboard": [KEY_TAB],
		"camera_toggle": [KEY_V],
		"binoculars": [KEY_B],
		"banana_boost": [KEY_F],
		"chat": [KEY_ENTER, KEY_KP_ENTER, KEY_T],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {"grab_left": MOUSE_BUTTON_LEFT, "grab_right": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)


func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	# A little reverb on effects makes the jungle feel bigger.
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx_idx) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.55
		rev.wet = 0.12
		rev.dry = 1.0
		AudioServer.add_bus_effect(sfx_idx, rev)


func apply_quality_preset(q: int) -> void:
	quality = clampi(q, 0, 3)
	match quality:
		0:
			shadows = false; ssao = false; glow = false
			render_scale = 0.75; view_distance = 160.0; vegetation_density = 0.45
		1:
			shadows = true; ssao = false; glow = true
			render_scale = 0.9; view_distance = 210.0; vegetation_density = 0.7
		2:
			shadows = true; ssao = true; glow = true
			render_scale = 1.0; view_distance = 260.0; vegetation_density = 1.0
		3:
			shadows = true; ssao = true; glow = true
			render_scale = 1.0; view_distance = 340.0; vegetation_density = 1.35


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale
		vp.msaa_3d = Viewport.MSAA_2X if quality >= 2 else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality >= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality >= 2 else 2048, true)
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Ambience", ambience_volume)
	changed.emit()


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for key in _keys():
		cf.set_value("settings", key, get(key))
	cf.save(PATH)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for key in _keys():
		if cf.has_section_key("settings", key):
			set(key, cf.get_value("settings", key))


func _keys() -> Array:
	return ["quality", "fullscreen", "vsync", "max_fps", "render_scale", "view_distance",
		"vegetation_density", "shadows", "ssao", "glow", "fov", "mouse_sensitivity", "invert_y",
		"master_volume", "music_volume", "sfx_volume", "ambience_volume", "show_fps"]
