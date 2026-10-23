class_name UITheme
extends RefCounted
## Builds the jungle-styled UI theme used by every menu and the HUD.

const BG := Color(0.06, 0.13, 0.08, 0.88)
const PANEL := Color(0.09, 0.2, 0.11, 0.92)
const ACCENT := Color(0.55, 0.85, 0.25)
const ACCENT_DARK := Color(0.2, 0.45, 0.12)
const TEXT := Color(0.96, 0.98, 0.9)
const MUTED := Color(0.7, 0.8, 0.65)
const WARN := Color(1.0, 0.45, 0.3)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20
	var panel := _box(PANEL, 14, 2, Color(0.35, 0.6, 0.2, 0.6))
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var normal := _box(Color(0.16, 0.34, 0.14), 10, 2, Color(0.35, 0.6, 0.2))
	var hover := _box(Color(0.24, 0.48, 0.18), 10, 2, ACCENT)
	var pressed := _box(Color(0.12, 0.26, 0.1), 10, 2, ACCENT)
	var disabled := _box(Color(0.12, 0.18, 0.12), 10, 2, Color(0.2, 0.3, 0.2))
	var focus := _box(Color(0, 0, 0, 0), 10, 2, Color(0.9, 1.0, 0.6))
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, normal if cls != "CheckBox" and cls != "CheckButton" else StyleBoxEmpty.new())
		t.set_stylebox("hover", cls, hover if cls != "CheckBox" and cls != "CheckButton" else StyleBoxEmpty.new())
		t.set_stylebox("pressed", cls, pressed if cls != "CheckBox" and cls != "CheckButton" else StyleBoxEmpty.new())
		t.set_stylebox("disabled", cls, disabled if cls != "CheckBox" and cls != "CheckButton" else StyleBoxEmpty.new())
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color(1, 1, 0.85))
		t.set_color("font_pressed_color", cls, ACCENT)
		t.set_color("font_disabled_color", cls, Color(0.5, 0.55, 0.5))
	for b in [normal, hover, pressed, disabled]:
		b.content_margin_left = 16
		b.content_margin_right = 16
		b.content_margin_top = 8
		b.content_margin_bottom = 8
	var edit := _box(Color(0.04, 0.09, 0.05, 0.95), 8, 2, Color(0.3, 0.5, 0.2))
	edit.content_margin_left = 10
	edit.content_margin_right = 10
	edit.content_margin_top = 6
	edit.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", _box(Color(0.04, 0.09, 0.05, 0.95), 8, 2, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "SpinBox", edit)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("slider", "HSlider", _box(Color(0.1, 0.2, 0.1), 4, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber_area", "HSlider", _box(ACCENT_DARK, 4, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 4, 0, Color.TRANSPARENT))
	var tab_sel := _box(Color(0.2, 0.42, 0.16), 8, 0, Color.TRANSPARENT)
	var tab_unsel := _box(Color(0.1, 0.2, 0.1), 8, 0, Color.TRANSPARENT)
	for b in [tab_sel, tab_unsel]:
		b.content_margin_left = 14
		b.content_margin_right = 14
		b.content_margin_top = 6
		b.content_margin_bottom = 6
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_unsel)
	t.set_stylebox("tab_hovered", "TabContainer", tab_sel)
	t.set_stylebox("panel", "TabContainer", _box(Color(0.06, 0.14, 0.07, 0.9), 8, 0, Color.TRANSPARENT))
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.08, 0.17, 0.09, 0.98), 8, 2, ACCENT_DARK))
	t.set_stylebox("hover", "PopupMenu", _box(Color(0.24, 0.48, 0.18), 6, 0, Color.TRANSPARENT))
	t.set_stylebox("panel", "ItemList", _box(Color(0.04, 0.09, 0.05, 0.9), 8, 0, Color.TRANSPARENT))
	_theme = t
	return t


static func _box(c: Color, radius: int, border: int, border_color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.anti_aliasing = true
	return s


static func label(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size: int = 64) -> Label:
	var l := label(text, size, Color(0.85, 1.0, 0.45))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.15, 0.03))
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(text: String, cb: Callable, min_w: int = 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func():
		Sfx.play("ui_click", -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -14.0))
	return b


static func row(children: Array, sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


static func col(children: Array, sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for c in children:
		v.add_child(c)
	return v
