extends Control
## Pre-match lobby: room codes, player list, host settings, profile and start button.

var _list: VBoxContainer
var _options: MatchOptions
var _code_label: Label
var _net_code_label: Label
var _slots: Label
var _start: Button
var _status: Label
var _summary: Label


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(MenuBackground.new())
	Sfx.play_music()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 50)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	var room_title := UITheme.title(str(Game.config.get("room_name", "Jungle Room")), 52)
	root.add_child(room_title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# left: players
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	cols.add_child(left)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_slots = UITheme.label("", 18, UITheme.MUTED)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UITheme.col([UITheme.label("Players", 28, UITheme.ACCENT), _slots, scroll], 10))

	# right: codes, settings, profile
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	right.add_child(rv)
	if Net.is_host():
		var lan_code := Net.make_room_code(Net.local_ip(), Net.port)
		_code_label = UITheme.label("LAN room code:  %s   (%s:%d)" % [lan_code, Net.local_ip(), Net.port], 20)
		var copy := UITheme.button("Copy", func(): DisplayServer.clipboard_set(lan_code), 100)
		rv.add_child(UITheme.row([_code_label, copy]))
		_net_code_label = UITheme.label("Internet code: not fetched yet", 20, UITheme.MUTED)
		var fetch := UITheme.button("Get Internet Code", func():
			_net_code_label.text = "Internet code: looking up your public IP..."
			Net.fetch_public_code(), 240)
		rv.add_child(UITheme.row([_net_code_label, fetch]))
		Net.public_code_ready.connect(func(code):
			if code == "":
				_net_code_label.text = "Internet code: lookup failed (are you online?)"
			else:
				_net_code_label.text = "Internet code:  %s" % code
				DisplayServer.clipboard_set(code))
		var tip := UITheme.label("Internet play needs UDP port %d forwarded to this PC (or a shared VPN like Tailscale/ZeroTier). %s" % [Net.port, "Private room: password required." if Net.password != "" else "Public room: no password."], 15, UITheme.MUTED)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD
		rv.add_child(tip)
	else:
		rv.add_child(UITheme.label("Waiting for the host to start the match...", 20, UITheme.MUTED))
	rv.add_child(HSeparator.new())
	rv.add_child(UITheme.label("Match settings" + ("" if Net.is_host() else " (set by host)"), 24, UITheme.ACCENT))
	_options = MatchOptions.new()
	_options.editable = Net.is_host()
	_options.changed.connect(func():
		Net.host_update_config()
		_refresh())
	rv.add_child(_options)
	_summary = UITheme.label("", 16, UITheme.MUTED)
	rv.add_child(_summary)
	rv.add_child(HSeparator.new())
	var prof := ProfileEditor.new()
	prof.changed.connect(func(): Net.update_profile())
	rv.add_child(prof)

	# bottom buttons
	_status = UITheme.label("", 18, UITheme.MUTED)
	_start = UITheme.button("Start Match", func(): Net.host_start_match(), 260)
	_start.visible = Net.is_host()
	var leave := UITheme.button("Leave", func():
		Net.leave()
		Game.go_to_menu(), 160)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UITheme.row([_status, spacer, leave, _start], 14))
	Net.lobby_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	_options.editable = Net.is_host()
	_options.refresh()
	for c in _list.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.players[id]
		var sw := ColorRect.new()
		sw.color = p.color
		sw.custom_minimum_size = Vector2(28, 28)
		var tag := "  (host)" if id == 1 else ""
		if id == Net.my_id():
			tag += "  (you)"
		_list.add_child(UITheme.row([sw, UITheme.label(p.name + tag, 22)], 12))
	var humans := Net.players.size()
	var maxp := int(Game.config.max_players)
	var slots := maxi(0, maxp - humans)
	var bots := slots if Game.config.fill_bots else mini(int(Game.config.bot_count), slots)
	for i in bots:
		var sw := ColorRect.new()
		sw.color = Color(0.3, 0.35, 0.3)
		sw.custom_minimum_size = Vector2(28, 28)
		_list.add_child(UITheme.row([sw, UITheme.label("AI gorilla", 20, UITheme.MUTED)], 12))
	_slots.text = "%d / %d players  -  %d AI" % [humans, maxp, bots]
	_summary.text = "%s, %d min rounds" % [Game.mode_name(), int(Game.config.round_time) / 60] if int(Game.config.round_time) >= 60 else "%s, %d s rounds" % [Game.mode_name(), int(Game.config.round_time)]
	if Net.is_host():
		_status.text = "Share the room code with your friends, then press Start."
