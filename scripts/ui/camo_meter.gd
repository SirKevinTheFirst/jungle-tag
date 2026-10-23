class_name CamoMeter
extends Control
## Round camouflage indicator: green ring drains while active, grey ring fills during cooldown.

var fraction := 1.0
var mode := 0   # 0 ready, 1 active, 2 cooldown
var _pulse := 0.0


func _process(delta: float) -> void:
	_pulse += delta
	if mode == 0:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	draw_circle(c, r + 4.0, Color(0.03, 0.08, 0.03, 0.9))
	draw_arc(c, r, 0, TAU, 48, Color(0.2, 0.3, 0.2, 0.8), 7.0, true)
	var col := Color(0.55, 1.0, 0.3)
	if mode == 2:
		col = Color(0.6, 0.65, 0.6)
	elif mode == 0:
		col = Color(0.55, 1.0, 0.3).lerp(Color(0.9, 1.0, 0.6), 0.5 + 0.5 * sin(_pulse * 4.0))
	var start := -PI * 0.5
	draw_arc(c, r, start, start + TAU * clampf(fraction, 0.0, 1.0), 48, col, 7.0, true)
	# leaf icon
	var leaf := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		leaf.append(c + Vector2(sin(t * PI) * r * 0.32, (t - 0.5) * r * 1.0).rotated(0.6))
	for i in range(12, -1, -1):
		var t := float(i) / 12.0
		leaf.append(c + Vector2(-sin(t * PI) * r * 0.32, (t - 0.5) * r * 1.0).rotated(0.6))
	var leaf_col := col if mode != 2 else Color(0.4, 0.45, 0.4)
	draw_colored_polygon(leaf, leaf_col.darkened(0.25))
	draw_line(c + Vector2(0, -r * 0.5).rotated(0.6), c + Vector2(0, r * 0.55).rotated(0.6), Color(0.05, 0.15, 0.05), 2.0)
	var font := get_theme_default_font()
	draw_string(font, c + Vector2(r * 0.45, r * 0.95), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
