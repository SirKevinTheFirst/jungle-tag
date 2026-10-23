class_name SettingsPanel
extends PanelContainer
## Graphics, controls and audio settings. Used by the main menu and the pause menu.

signal closed

var _controls := {}


func _ready() -> void:
	custom_minimum_size = Vector2(720, 560)
	theme = UITheme.get_theme()
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(680, 440)
	tabs.add_child(_graphics_tab())
	tabs.add_child(_controls_tab())
	tabs.add_child(_audio_tab())
	var back := UITheme.button("Save & Back", func():
		Settings.save_settings()
		closed.emit())
	add_child(UITheme.col([UITheme.title("Settings", 40), tabs, back], 12))


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 10)
	return g


func _graphics_tab() -> Control:
	var g := _grid()
	g.name = "Graphics"
	var preset := OptionButton.new()
	for n in Settings.QUALITY_NAMES:
		preset.add_item(n)
	preset.selected = Settings.quality
	preset.item_selected.connect(func(i):
		Settings.apply_quality_preset(i)
		Settings.apply()
		_refresh())
	_add(g, "Quality preset", preset)
	_add(g, "Fullscreen", _check("fullscreen"))
	_add(g, "V-Sync", _check("vsync"))
	var fps := OptionButton.new()
	var caps := [0, 30, 60, 120, 144, 240]
	for c in caps:
		fps.add_item("Unlimited" if c == 0 else str(c))
	fps.selected = maxi(0, caps.find(Settings.max_fps))
	fps.item_selected.connect(func(i):
		Settings.max_fps = caps[i]
		Settings.apply())
	_add(g, "FPS limit", fps)
	_add(g, "Render scale", _slider("render_scale", 0.5, 1.0, 0.05))
	_add(g, "View distance", _slider("view_distance", 120.0, 400.0, 10.0))
	_add(g, "Vegetation (next match)", _slider("vegetation_density", 0.2, 1.6, 0.05))
	_add(g, "Shadows", _check("shadows"))
	_add(g, "Ambient occlusion", _check("ssao"))
	_add(g, "Glow", _check("glow"))
	_add(g, "Show FPS", _check("show_fps"))
	return _scroll(g, "Graphics")


func _controls_tab() -> Control:
	var g := _grid()
	_add(g, "Mouse sensitivity", _slider("mouse_sensitivity", 0.0005, 0.008, 0.0001))
	_add(g, "Invert mouse Y", _check("invert_y"))
	_add(g, "Field of view", _slider("fov", 60.0, 110.0, 1.0))
	var keys := UITheme.label("W A S D  move\nMouse  look\nSpace  jump / wall jump / let go of vine\nShift  sprint\nCtrl  crouch (and drop while climbing)\nLeft / Right mouse  grab & climb with each hand\nE  grab or release a vine\nG  camouflage\nTab  scoreboard\nV  first / third person\nEsc  pause", 17, UITheme.MUTED)
	var v := UITheme.col([g, keys], 18)
	return _scroll(v, "Controls")


func _audio_tab() -> Control:
	var g := _grid()
	_add(g, "Master", _slider("master_volume", 0.0, 1.0, 0.01))
	_add(g, "Music", _slider("music_volume", 0.0, 1.0, 0.01))
	_add(g, "Effects", _slider("sfx_volume", 0.0, 1.0, 0.01))
	_add(g, "Jungle ambience", _slider("ambience_volume", 0.0, 1.0, 0.01))
	return _scroll(g, "Audio")


func _scroll(c: Control, n: String) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = n
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(c)
	s.add_child(m)
	return s


func _add(g: GridContainer, text: String, ctrl: Control) -> void:
	var l := UITheme.label(text, 18)
	l.custom_minimum_size = Vector2(240, 0)
	g.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(ctrl)


func _check(key: String) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = Settings.get(key)
	c.toggled.connect(func(on):
		Settings.set(key, on)
		Settings.apply())
	_controls[key] = c
	return c


func _slider(key: String, mn: float, mx: float, step: float) -> HBoxContainer:
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = Settings.get(key)
	s.custom_minimum_size = Vector2(260, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := UITheme.label("", 16, UITheme.MUTED)
	val.custom_minimum_size = Vector2(60, 0)
	var fmt := func(v: float) -> String:
		if mx <= 1.0 and key != "mouse_sensitivity":
			return "%d%%" % int(round(v * 100.0))
		if key == "mouse_sensitivity":
			return "%.1f" % (v * 1000.0)
		return "%d" % int(v)
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(v):
		Settings.set(key, v)
		val.text = fmt.call(v)
		Settings.apply())
	_controls[key] = s
	return UITheme.row([s, val])


func _refresh() -> void:
	for key in _controls:
		var c: Control = _controls[key]
		if c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(Settings.get(key))
		elif c is HSlider:
			(c as HSlider).set_value_no_signal(Settings.get(key))
