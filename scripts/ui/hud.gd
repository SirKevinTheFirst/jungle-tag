class_name HUD
extends CanvasLayer
## In-match HUD: name, mode, timer, player count, role, camouflage meter with cooldown,
## interaction hints, kill feed, big round messages, scoreboard and seeker blindfold.

var world: Node
var _name_label: Label
var _mode_label: Label
var _count_label: Label
var _timer_label: Label
var _phase_label: Label
var _role_panel: PanelContainer
var _role_label: Label
var _camo_meter: CamoMeter
var _banana_box: PanelContainer
var chat_open := false
var _chat_box: VBoxContainer
var _chat_edit: LineEdit
var _chat_hint: Label
var _banana_text: Label
var _boost_label: Label
var _camo_text: Label
var _hint: Label
var _msg: Label
var _msg_sub: Label
var _msg_time := 0.0
var _feed_box: VBoxContainer
var _scoreboard: PanelContainer
var _score_grid: GridContainer
var _blindfold: ColorRect
var _blind_label: Label
var _fps: Label
var _vignette: ColorRect
var _bino: ColorRect
var _bino_label: Label
var _speed_label: Label
var _hint_timer := 0.0


func setup(p_world: Node) -> void:
	world = p_world
	layer = 5
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	# camouflage vignette (green leafy edges)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = """shader_type canvas_item;
uniform float amount = 0.0;
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }
void fragment(){
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.6, 1.0));
	float edge = smoothstep(0.45, 0.85, d + sin(UV.x * 40.0) * sin(UV.y * 30.0) * 0.03);
	COLOR = vec4(0.08, 0.3, 0.06, edge * 0.55 * amount);
}"""
	vm.shader = vs
	_vignette.material = vm
	root.add_child(_vignette)

	# binoculars: two round lenses, black around them
	_bino = ColorRect.new()
	_bino.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bino.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	var bs := Shader.new()
	bs.code = """shader_type canvas_item;
uniform float aspect = 1.777;
void fragment(){
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = 0.36;
	float d = min(length(p - vec2(-0.21, 0.0)), length(p - vec2(0.21, 0.0)));
	float lens = smoothstep(r, r - 0.025, d);
	float ring = smoothstep(r - 0.06, r, d) * lens;
	COLOR = vec4(0.0, 0.0, 0.0, max(1.0 - lens, ring * 0.55));
}"""
	bm.shader = bs
	_bino.material = bm
	_bino.visible = false
	root.add_child(_bino)
	_bino_label = UITheme.label("", 18)
	_bino_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bino_label.position.y -= 70
	_bino_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bino_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bino.add_child(_bino_label)

	# top-left info
	var info := PanelContainer.new()
	info.position = Vector2(20, 20)
	root.add_child(info)
	_name_label = UITheme.label("", 24)
	_mode_label = UITheme.label("", 18, UITheme.MUTED)
	_count_label = UITheme.label("", 18, UITheme.MUTED)
	info.add_child(UITheme.col([_name_label, _mode_label, _count_label], 2))

	# top-centre timer
	var timer_box := PanelContainer.new()
	timer_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_box.position = Vector2(-90, 16)
	timer_box.custom_minimum_size = Vector2(180, 0)
	root.add_child(timer_box)
	_timer_label = UITheme.label("0:00", 40)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label = UITheme.label("", 16, UITheme.MUTED)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(UITheme.col([_timer_label, _phase_label], 0))

	# top-right role badge
	_role_panel = PanelContainer.new()
	_role_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_role_panel.position = Vector2(-260, 20)
	_role_panel.custom_minimum_size = Vector2(240, 0)
	root.add_child(_role_panel)
	_role_label = UITheme.label("RUNNER", 30)
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_panel.add_child(_role_label)

	# kill feed under the role badge
	_feed_box = VBoxContainer.new()
	_feed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed_box.position = Vector2(-420, 110)
	_feed_box.custom_minimum_size = Vector2(400, 0)
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_feed_box)

	# bottom-right camouflage meter
	var camo_box := PanelContainer.new()
	camo_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	camo_box.position = Vector2(-250, -150)
	camo_box.custom_minimum_size = Vector2(230, 130)
	root.add_child(camo_box)
	_camo_meter = CamoMeter.new()
	_camo_meter.custom_minimum_size = Vector2(96, 96)
	_camo_text = UITheme.label("CAMO\nREADY", 18)
	_camo_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var camo_row := UITheme.row([_camo_meter, _camo_text], 12)
	camo_box.add_child(camo_row)

	# bananas: count above the camo meter, big countdown while the boost runs
	_banana_box = PanelContainer.new()
	_banana_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_banana_box.position = Vector2(-250, -238)
	_banana_box.custom_minimum_size = Vector2(230, 76)
	root.add_child(_banana_box)
	_banana_text = UITheme.label("", 18, Color(1.0, 0.88, 0.3))
	_banana_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banana_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banana_box.add_child(_banana_text)
	_boost_label = UITheme.label("", 34, Color(1.0, 0.88, 0.25))
	_boost_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_boost_label.position.y -= 150
	_boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boost_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boost_label.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.0))
	_boost_label.add_theme_constant_override("outline_size", 10)
	root.add_child(_boost_label)

	# speed readout bottom-left
	_speed_label = UITheme.label("", 16, UITheme.MUTED)
	_speed_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_speed_label.position = Vector2(24, -44)
	root.add_child(_speed_label)

	# chat: recent messages bottom-left, Enter (or T) to type
	_chat_box = VBoxContainer.new()
	_chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_box.position = Vector2(24, -300)
	_chat_box.custom_minimum_size = Vector2(560, 200)
	_chat_box.alignment = BoxContainer.ALIGNMENT_END
	_chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chat_box)
	_chat_edit = LineEdit.new()
	_chat_edit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_edit.position = Vector2(24, -92)
	_chat_edit.custom_minimum_size = Vector2(560, 40)
	_chat_edit.max_length = 120
	_chat_edit.placeholder_text = "Say something... (Enter to send, Esc to cancel)"
	_chat_edit.visible = false
	_chat_edit.text_submitted.connect(_send_chat)
	_chat_edit.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			_close_chat()
			_chat_edit.accept_event())
	root.add_child(_chat_edit)
	_chat_hint = UITheme.label("Enter / T: chat", 14, UITheme.MUTED)
	_chat_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_hint.position = Vector2(24, -70)
	root.add_child(_chat_hint)

	# crosshair + hint
	var cross := UITheme.label("+", 26, Color(1, 1, 1, 0.7))
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-8, -18)
	root.add_child(cross)
	_hint = UITheme.label("", 18, Color(1, 1, 0.8))
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.position = Vector2(-200, 30)
	_hint.custom_minimum_size = Vector2(400, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	root.add_child(_hint)

	# big centre message
	_msg = UITheme.title("", 60)
	_msg.set_anchors_preset(Control.PRESET_CENTER)
	_msg.position = Vector2(-500, -200)
	_msg.custom_minimum_size = Vector2(1000, 0)
	root.add_child(_msg)
	_msg_sub = UITheme.label("", 26)
	_msg_sub.set_anchors_preset(Control.PRESET_CENTER)
	_msg_sub.position = Vector2(-500, -118)
	_msg_sub.custom_minimum_size = Vector2(1000, 0)
	_msg_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	_msg_sub.add_theme_constant_override("outline_size", 8)
	root.add_child(_msg_sub)

	# seeker blindfold
	_blindfold = ColorRect.new()
	_blindfold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blindfold.color = Color(0.02, 0.05, 0.02, 0.96)
	_blindfold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blindfold.visible = false
	root.add_child(_blindfold)
	_blind_label = UITheme.title("", 44)
	_blind_label.set_anchors_preset(Control.PRESET_CENTER)
	_blind_label.position = Vector2(-500, -40)
	_blind_label.custom_minimum_size = Vector2(1000, 0)
	_blindfold.add_child(_blind_label)

	# scoreboard (hold Tab)
	_scoreboard = PanelContainer.new()
	_scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard.position = Vector2(-380, -300)
	_scoreboard.custom_minimum_size = Vector2(760, 0)
	_scoreboard.visible = false
	root.add_child(_scoreboard)
	_score_grid = GridContainer.new()
	_score_grid.columns = 5
	_score_grid.add_theme_constant_override("h_separation", 26)
	_score_grid.add_theme_constant_override("v_separation", 6)
	var sb_title := UITheme.label("SCOREBOARD", 30, UITheme.ACCENT)
	sb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoreboard.add_child(UITheme.col([sb_title, _score_grid], 12))

	_fps = UITheme.label("", 16, UITheme.MUTED)
	_fps.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_fps.position = Vector2(24, -70)
	root.add_child(_fps)

	world.mode.round_message.connect(show_message)
	world.mode.tag_feed.connect(feed)


func show_message(text: String, sub: String = "") -> void:
	_msg.text = text
	_msg_sub.text = sub
	_msg_time = 3.5


func feed(text: String) -> void:
	var l := UITheme.label(text, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_feed_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)
	if _feed_box.get_child_count() > 5:
		_feed_box.get_child(0).queue_free()


func _process(delta: float) -> void:
	var me: Gorilla = world.local
	var gm: GameMode = world.mode
	if me == null or gm == null:
		return
	_name_label.text = me.display_name
	_name_label.add_theme_color_override("font_color", me.color.lightened(0.35))
	_mode_label.text = Game.mode_name(gm.mode)
	_count_label.text = "%d gorillas in the jungle" % world.gorillas.size()
	var t := ceili(gm.time_left)
	_timer_label.text = "%d:%02d" % [t / 60, t % 60]
	_timer_label.add_theme_color_override("font_color", UITheme.WARN if gm.phase == "play" and gm.time_left < 15.0 else UITheme.TEXT)
	match gm.phase:
		"warmup": _phase_label.text = "GET READY"
		"hide": _phase_label.text = "HIDING TIME"
		"play": _phase_label.text = "ROUND IN PROGRESS"
		"end": _phase_label.text = "NEXT ROUND SOON"
	_update_role(me, gm)
	_update_camo(me)
	_update_bananas(me)
	_update_hint(me, delta)
	var spd := me.velocity.length()
	_speed_label.text = "%.0f m/s" % spd if spd > 0.5 else ""
	_msg_time -= delta
	var a := clampf(_msg_time, 0.0, 1.0)
	_msg.modulate.a = a
	_msg_sub.modulate.a = a
	var blind := gm.phase == "hide" and me.role == "seeker"
	_blindfold.visible = blind
	if blind:
		_blind_label.text = "You are a SEEKER\nThe gorillas are hiding... %d" % ceili(gm.time_left)
	_scoreboard.visible = Input.is_action_pressed("scoreboard") or gm.phase == "end"
	if _scoreboard.visible:
		_update_scoreboard(gm)
	_fps.visible = Settings.show_fps
	if Settings.show_fps:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	(_vignette.material as ShaderMaterial).set_shader_parameter("amount", me.camo_visual)
	_bino.visible = me.binoculars
	if me.binoculars:
		var vs := get_viewport().get_visible_rect().size
		(_bino.material as ShaderMaterial).set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		_bino_label.text = "BINOCULARS  %.1fx   (scroll to zoom)" % (Settings.fov / maxf(me.camera.fov, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if chat_open or not event.is_action_pressed("chat"):
		return
	if world.pause_menu and world.pause_menu.visible:
		return
	chat_open = true
	_chat_edit.text = ""
	_chat_edit.visible = true
	_chat_hint.visible = false
	_chat_edit.grab_focus()
	get_viewport().set_input_as_handled()


func _send_chat(text: String) -> void:
	if text.strip_edges() != "":
		Net.send_chat(text)
	_close_chat()


func _close_chat() -> void:
	chat_open = false
	_chat_edit.release_focus()
	_chat_edit.visible = false
	_chat_hint.visible = true


## Adds a line to the chat box; it fades out after a while.
func chat_line(who: String, col: Color, text: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(560, 0)
	l.add_theme_font_size_override("normal_font_size", 18)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.text = "[color=#%s][b]%s:[/b][/color] %s" % [col.lightened(0.35).to_html(false), who, text.replace("[", "[lb]")]
	_chat_box.add_child(l)
	while _chat_box.get_child_count() > 7:
		_chat_box.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func _update_bananas(me: Gorilla) -> void:
	if world.bananas == null:
		return
	var n := int(world.bananas.counts.get(me.net_id, 0))
	var need := Bananas.NEED
	if me.banana_boost > 0.0:
		_banana_text.text = "BANANA BOOST ON\n2x sprint speed"
		_boost_label.text = "BANANA BOOST  %d" % ceili(me.banana_boost)
		_boost_label.modulate.a = 1.0 if me.banana_boost > 5.0 else 0.5 + 0.5 * absf(sin(me.banana_boost * 8.0))
		_banana_box.modulate = Color.WHITE
	elif n >= need:
		_banana_text.text = "BANANA POWER READY\nPress F!"
		_boost_label.text = ""
		_banana_box.modulate = Color(1, 1, 1, 0.65 + 0.35 * absf(sin(Time.get_ticks_msec() / 250.0)))
	else:
		_banana_text.text = "BANANAS  %d / %d\neat %d for a sprint boost" % [n, need, need]
		_boost_label.text = ""
		_banana_box.modulate = Color.WHITE


func _update_role(me: Gorilla, gm: GameMode) -> void:
	var r := me.role
	var text := "RUNNER"
	var col := Color(0.3, 0.75, 0.3)
	match r:
		"it":
			text = "YOU'RE IT!"
			col = Color(0.9, 0.25, 0.15)
		"infected":
			text = "INFECTED"
			col = Color(1.0, 0.5, 0.1)
		"seeker":
			text = "SEEKER"
			col = Color(0.85, 0.3, 0.2)
		"hider":
			text = "HIDER"
			col = Color(0.3, 0.7, 0.35)
	if gm.mode == Game.MODE_MAZE:
		text = "ESCAPES: %d" % int(gm.stats.get(me.net_id, {}).get("escapes", 0))
		col = Color(0.5, 0.3, 0.85)
	if me.stun_time > 0.0:
		text += "  (stunned)"
	_role_label.text = text
	var sb := (UITheme.get_theme().get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate() as StyleBoxFlat
	sb.bg_color = col.darkened(0.35)
	sb.border_color = col.lightened(0.3)
	_role_panel.add_theme_stylebox_override("panel", sb)


func _update_camo(me: Gorilla) -> void:
	if me.camo_active:
		_camo_meter.fraction = me.camo_time / Gorilla.CAMO_MAX
		_camo_meter.mode = 1
		var eff := int(round(me.camo_effect() * 82.0))
		_camo_text.text = "CAMO ON\n%.0fs left\n%d%% hidden" % [ceilf(me.camo_time), eff]
		_camo_text.add_theme_color_override("font_color", Color(0.6, 1.0, 0.4))
	elif me.camo_cooldown > 0.0:
		_camo_meter.fraction = 1.0 - me.camo_cooldown / Gorilla.CAMO_COOLDOWN
		_camo_meter.mode = 2
		_camo_text.text = "COOLDOWN\n%.0fs" % ceilf(me.camo_cooldown)
		_camo_text.add_theme_color_override("font_color", UITheme.MUTED)
	else:
		_camo_meter.fraction = 1.0
		_camo_meter.mode = 0
		_camo_text.text = "CAMO READY\npress G"
		_camo_text.add_theme_color_override("font_color", UITheme.TEXT)
	_camo_meter.queue_redraw()


func _update_hint(me: Gorilla, delta: float) -> void:
	_hint_timer -= delta
	if _hint_timer > 0.0:
		return
	_hint_timer = 0.12
	var text := ""
	if world.maze and world.maze.contains(me.global_position):
		_hint.text = "BLACK HOLE MAZE: find the green EXIT - avoid the Shadow!"
		return
	match me.state:
		Gorilla.State.SWING:
			text = "WASD pump the swing - E or Space to let go"
		Gorilla.State.CLIMB:
			text = "Hold LMB/RMB to cling - alternate clicks to pull - Space to leap" if not me._hanging else "Hanging: Space to pull up, release to drop"
		_:
			var o := me.chest()
			var q := PhysicsRayQueryParameters3D.create(o, o + me.look_dir() * Gorilla.CLIMB_REACH, 1, [me.get_rid()])
			var hit := me.get_world_3d().direct_space_state.intersect_ray(q)
			if me._is_climbable(hit) and hit.normal.y < 0.7:
				text = "LMB / RMB to climb"
			else:
				var hp := me.hand_point()
				for v in world.jungle.vines:
					var a: Vector3 = v.anchor()
					if absf(a.x - hp.x) < 4.0 and absf(a.z - hp.z) < 4.0 and v.closest_point(hp).distance_to(hp) < Gorilla.VINE_REACH:
						text = "E to grab the vine"
						break
	_hint.text = text


func _update_scoreboard(gm: GameMode) -> void:
	for c in _score_grid.get_children():
		c.queue_free()
	var stat_name := "Time as IT" if gm.mode == Game.MODE_CLASSIC else "Survived"
	var maze_run := gm.mode == Game.MODE_MAZE
	for h in ["Gorilla", "Role", "Escapes" if maze_run else "Tags", stat_name, ""]:
		_score_grid.add_child(UITheme.label(h, 18, UITheme.ACCENT))
	var ids: Array = world.gorillas.keys()
	ids.sort_custom(func(a, b):
		var sa: Dictionary = gm.stats.get(a, {"tags": 0})
		var sb: Dictionary = gm.stats.get(b, {"tags": 0})
		var key := "escapes" if gm.mode == Game.MODE_MAZE else "tags"
		return int(sa.get(key, 0)) > int(sb.get(key, 0)))
	for id in ids:
		var g: Gorilla = world.gorillas[id]
		var st: Dictionary = gm.stats.get(id, {"tags": 0, "it_time": 0.0, "survived": 0.0})
		var name_l := UITheme.label(g.display_name, 18, g.color.lightened(0.4))
		if g == world.local:
			name_l.text = "> " + g.display_name
		_score_grid.add_child(name_l)
		_score_grid.add_child(UITheme.label(g.role.to_upper(), 18, UITheme.WARN if g.is_tagger() else UITheme.TEXT))
		_score_grid.add_child(UITheme.label(str(st.get("escapes", 0) if maze_run else st.tags), 18))
		var secs := float(st.it_time if gm.mode == Game.MODE_CLASSIC else st.survived)
		_score_grid.add_child(UITheme.label("%d:%02d" % [int(secs) / 60, int(secs) % 60], 18))
		_score_grid.add_child(UITheme.label("AI" if Game.is_bot_id(id) else "", 14, UITheme.MUTED))
