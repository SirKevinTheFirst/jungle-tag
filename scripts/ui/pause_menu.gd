class_name PauseMenu
extends CanvasLayer
## Esc menu during a match. Solo games actually pause; online games keep running.

var world: Node
var _panel: PanelContainer
var _settings: SettingsPanel
var _main: VBoxContainer
var _host_buttons: Array[Button] = []
var root: Control


func setup(p_world: Node) -> void:
	world = p_world
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.get_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	_main = UITheme.col([
		UITheme.title("Paused", 48),
		UITheme.button("Resume", close),
		UITheme.button("Settings", _open_settings),
	], 12)
	if Net.is_host():
		var restart := UITheme.button("Restart Round", func():
			world.mode.start_round()
			close())
		_main.add_child(restart)
		if Net.is_online:
			_main.add_child(UITheme.button("Back to Lobby", func(): Net.host_return_to_lobby()))
	_main.add_child(UITheme.button("Leave Match", _leave))
	var help := UITheme.label("WASD move  -  Mouse look  -  Space jump  -  Shift sprint  -  Ctrl crouch\nLMB/RMB grab & climb  -  E vine  -  G camouflage  -  Tab scores  -  V camera", 15, UITheme.MUTED)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main.add_child(help)
	_panel.add_child(_main)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func():
		_settings.visible = false
		_main.visible = true)
	center.add_child(_settings)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			if _settings.visible:
				_settings.visible = false
				_main.visible = true
				_panel.visible = true
			else:
				close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open() -> void:
	visible = true
	_panel.visible = true
	_main.visible = true
	_settings.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.is_online:
		get_tree().paused = true


func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false


func _open_settings() -> void:
	_panel.visible = false
	_settings.visible = true


func _leave() -> void:
	get_tree().paused = false
	Net.leave()
	Game.go_to_menu()
