extends Control
## Main menu: Play (solo with AI), Black Hole Maze Run, Host Game, Join Game, Player Count, Settings, Quit.

var _right: PanelContainer
var _pages := {}
var _status: Label
var _count_button: Button
var _options: MatchOptions
var _join_status: Label
var _join_code: LineEdit
var _join_pass: LineEdit
var _host_port: SpinBox
var _host_private: CheckBox
var _host_pass: LineEdit
var _host_name: LineEdit


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(MenuBackground.new())
	Sfx.play_music()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	add_child(margin)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 50)
	margin.add_child(hbox)

	# left: title + main buttons + gorilla preview
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size = Vector2(420, 0)
	hbox.add_child(left)
	left.add_child(UITheme.title("JUNGLE TAG", 76))
	var sub := UITheme.label("swing - climb - camouflage - tag", 22, Color(0.85, 1.0, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(sub)
	left.add_child(Control.new())
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UITheme.button("Play", _on_play, 340))
	buttons.add_child(UITheme.button("Black Hole Maze Run", _on_maze_run, 340))
	buttons.add_child(UITheme.button("Host Game", func(): _show("host"), 340))
	buttons.add_child(UITheme.button("Join Game", func(): _show("join"), 340))
	_count_button = UITheme.button("", _on_count, 340)
	buttons.add_child(_count_button)
	buttons.add_child(UITheme.button("Settings", func(): _show("settings"), 340))
	buttons.add_child(UITheme.button("Quit", func(): get_tree().quit(), 340))
	var bc := CenterContainer.new()
	bc.add_child(buttons)
	left.add_child(bc)
	_status = UITheme.label(Game.menu_message, 18, UITheme.WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_status)
	Game.menu_message = ""

	# right: swappable page
	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right_box)
	_right = PanelContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_child(_right)
	_build_setup_page()
	_build_host_page()
	_build_join_page()
	var sp := SettingsPanel.new()
	sp.closed.connect(func(): _show("setup"))
	_pages["settings"] = sp
	for k in _pages:
		_right.add_child(_pages[k])
	_show("setup")
	_update_count_button()
	Net.join_failed.connect(_on_join_failed)
	Net.joined.connect(func(): Game.go_to_lobby())
	var ver := UITheme.label("v%s (build %d)  -  Godot %s" % [ProjectSettings.get_setting("application/config/version"), int(ProjectSettings.get_setting("application/config/build", 0)), Engine.get_version_info().string], 14, UITheme.MUTED)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-300, -30)
	add_child(ver)


func _show(page: String) -> void:
	for k in _pages:
		_pages[k].visible = k == page
	if page == "setup":
		_options.refresh()


func _build_setup_page() -> void:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 30)
	var preview := GorillaPreview.new()
	var prof := ProfileEditor.new()
	_options = MatchOptions.new()
	_options.changed.connect(_update_count_button)
	var hint := UITheme.label("Play starts a solo match right away with AI gorillas filling the jungle. Host Game opens an online lobby for friends.", 16, UITheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size = Vector2(380, 0)
	var col := UITheme.col([UITheme.label("Match Setup", 30, UITheme.ACCENT), prof, HSeparator.new(), _options, hint], 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(UITheme.col([preview], 0))
	page.add_child(col)
	_pages["setup"] = page


func _build_host_page() -> void:
	_host_name = LineEdit.new()
	_host_name.text = "%s's Jungle" % Game.profile_name
	_host_port = SpinBox.new()
	_host_port.min_value = 1024
	_host_port.max_value = 65535
	_host_port.value = Net.DEFAULT_PORT
	_host_private = CheckBox.new()
	_host_private.text = "Private room (password)"
	_host_pass = LineEdit.new()
	_host_pass.placeholder_text = "Room password"
	_host_pass.secret = true
	_host_pass.editable = false
	_host_private.toggled.connect(func(on): _host_pass.editable = on)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 10)
	for pair in [["Room name", _host_name], ["Port (UDP)", _host_port], ["", _host_private], ["Password", _host_pass]]:
		g.add_child(UITheme.label(pair[0], 18))
		(pair[1] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(pair[1])
	var info := UITheme.label("Friends on your Wi-Fi/LAN can join straight away with the room code. For friends elsewhere, forward UDP port %d on your router (or everyone joins the same Tailscale / ZeroTier / Radmin VPN network) and share the Internet code from the lobby." % Net.DEFAULT_PORT, 16, UITheme.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.custom_minimum_size = Vector2(520, 0)
	var page := UITheme.col([
		UITheme.label("Host a Game", 30, UITheme.ACCENT), g,
		UITheme.label("Mode, round time and player count are set in the lobby.", 16, UITheme.MUTED),
		info,
		UITheme.row([UITheme.button("Open Lobby", _on_host, 220), UITheme.button("Back", func(): _show("setup"), 140)]),
	], 14)
	_pages["host"] = page


func _build_join_page() -> void:
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "Room code (ABCDE-FGHIJ) or IP address"
	_join_code.custom_minimum_size = Vector2(420, 0)
	_join_pass = LineEdit.new()
	_join_pass.placeholder_text = "Password (private rooms only)"
	_join_pass.secret = true
	_join_status = UITheme.label("", 18, UITheme.MUTED)
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_join_status.custom_minimum_size = Vector2(420, 0)
	var page := UITheme.col([
		UITheme.label("Join a Game", 30, UITheme.ACCENT),
		UITheme.label("Ask the host for their room code.", 16, UITheme.MUTED),
		_join_code, _join_pass,
		UITheme.row([UITheme.button("Join", _on_join, 200), UITheme.button("Back", func(): _show("setup"), 140)]),
		_join_status,
	], 14)
	_pages["join"] = page


func _update_count_button() -> void:
	_count_button.text = "Player Count: %d" % int(Game.config.max_players)


func _on_count() -> void:
	_show("setup")
	_options.cycle_player_count()
	_update_count_button()


func _on_play() -> void:
	Net.start_solo()


func _on_maze_run() -> void:
	Game.config.mode = Game.MODE_MAZE
	Net.start_solo()


func _on_host() -> void:
	Game.config.room_name = _host_name.text.strip_edges().substr(0, 28)
	var pw := _host_pass.text if _host_private.button_pressed else ""
	var err := Net.host(int(_host_port.value), pw)
	if err != OK:
		_status.text = "Could not open port %d (error %d). Is another copy already hosting?" % [int(_host_port.value), err]
		return
	Game.go_to_lobby()


func _on_join() -> void:
	var err := Net.join(_join_code.text, _join_pass.text)
	if err != OK:
		_join_status.text = "That room code doesn't look right."
		_join_status.add_theme_color_override("font_color", UITheme.WARN)
		return
	_join_status.text = "Connecting..."
	_join_status.add_theme_color_override("font_color", UITheme.MUTED)


func _on_join_failed(reason: String) -> void:
	_show("join")
	_join_status.text = reason
	_join_status.add_theme_color_override("font_color", UITheme.WARN)
