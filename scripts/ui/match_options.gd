class_name MatchOptions
extends GridContainer
## Game mode, round length, player count and AI bot options (menu + lobby).

signal changed

var editable := true
var _mode: OptionButton
var _time: OptionButton
var _count: OptionButton
var _bots: SpinBox
var _fill: CheckBox


func _ready() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 18)
	add_theme_constant_override("v_separation", 10)
	_mode = OptionButton.new()
	for n in Game.MODE_NAMES:
		_mode.add_item(n)
	_time = OptionButton.new()
	for t in Game.ROUND_TIMES:
		_time.add_item("%d min" % (t / 60) if t >= 60 else "%d s" % t)
	_count = OptionButton.new()
	for c in Game.PLAYER_COUNTS:
		_count.add_item("%d players" % c)
	_bots = SpinBox.new()
	_bots.min_value = 0
	_bots.max_value = 15
	_fill = CheckBox.new()
	_fill.text = "Fill empty slots with AI"
	_add("Game mode", _mode)
	_add("Round time", _time)
	_add("Player count", _count)
	_add("AI gorillas", _bots)
	_add("", _fill)
	refresh()
	_mode.item_selected.connect(func(i):
		Game.config.mode = i
		_emit())
	_time.item_selected.connect(func(i):
		Game.config.round_time = Game.ROUND_TIMES[i]
		_emit())
	_count.item_selected.connect(func(i):
		Game.config.max_players = Game.PLAYER_COUNTS[i]
		Game.config.bot_count = mini(int(Game.config.bot_count), Game.config.max_players - 1)
		refresh()
		_emit())
	_bots.value_changed.connect(func(v):
		Game.config.bot_count = int(v)
		_emit())
	_fill.toggled.connect(func(on):
		Game.config.fill_bots = on
		refresh()
		_emit())


func _add(text: String, c: Control) -> void:
	var l := UITheme.label(text, 18)
	l.custom_minimum_size = Vector2(150, 0)
	add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(c)


func _emit() -> void:
	Sfx.play("ui_click", -6.0)
	changed.emit()


## Cycles the player count (used by the main menu's Player Count button).
func cycle_player_count() -> void:
	var i := Game.PLAYER_COUNTS.find(int(Game.config.max_players))
	i = (i + 1) % Game.PLAYER_COUNTS.size()
	Game.config.max_players = Game.PLAYER_COUNTS[i]
	Game.config.bot_count = mini(int(Game.config.bot_count), Game.config.max_players - 1)
	refresh()
	changed.emit()


func refresh() -> void:
	if _mode == null:
		return
	_mode.selected = int(Game.config.mode)
	_time.selected = maxi(0, Game.ROUND_TIMES.find(int(Game.config.round_time)))
	_count.selected = maxi(0, Game.PLAYER_COUNTS.find(int(Game.config.max_players)))
	_bots.max_value = int(Game.config.max_players) - 1
	_bots.set_value_no_signal(int(Game.config.bot_count))
	_fill.set_pressed_no_signal(bool(Game.config.fill_bots))
	_bots.editable = editable and not Game.config.fill_bots
	for c in [_mode, _time, _count]:
		c.disabled = not editable
	_fill.disabled = not editable
