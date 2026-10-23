class_name ProfileEditor
extends VBoxContainer
## Username field and colour swatches.

signal changed

var _name: LineEdit
var _swatches: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UITheme.label("Your gorilla", 18, UITheme.MUTED))
	_name = LineEdit.new()
	_name.text = Game.profile_name
	_name.max_length = 16
	_name.placeholder_text = "Username"
	_name.text_changed.connect(func(t):
		Game.profile_name = Game.sanitize_name(t)
		Game.save_profile()
		changed.emit())
	add_child(_name)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for c in Game.COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(20)
		sb.set_border_width_all(3)
		sb.border_color = Color(0, 0, 0, 0.4)
		b.add_theme_stylebox_override("normal", sb)
		var sh := sb.duplicate() as StyleBoxFlat
		sh.border_color = Color.WHITE
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.pressed.connect(func():
			Game.profile_color = c
			Game.save_profile()
			Sfx.play("ui_click", -4.0)
			_update()
			changed.emit())
		b.set_meta("color", c)
		_swatches.append(b)
		grid.add_child(b)
	add_child(grid)
	_update()


func _update() -> void:
	for b in _swatches:
		var c: Color = b.get_meta("color")
		var sb := (b.get_theme_stylebox("normal") as StyleBoxFlat)
		sb.border_color = Color.WHITE if c.is_equal_approx(Game.profile_color) else Color(0, 0, 0, 0.4)
