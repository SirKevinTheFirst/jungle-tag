class_name Maze
extends Node3D
## The dark underground maze that black holes drop gorillas into.
## Generated from the match seed (recursive backtracker), so every peer gets the same layout.
## Lives far below the jungle; the sun does not light it (render layer 3).

const N := 11              # cells per side
const CELL := 4.6          # metres per cell
const WALL_H := 3.4
const WALL_T := 0.7
const ORIGIN := Vector3(-25.0, -80.0, -25.0)   # corner of cell (0, 0) on the floor
const LAYER := 4           # render layer bit for maze geometry (layer 3)

var rng := RandomNumberGenerator.new()
## walls[x][z] = [north_open, east_open, south_open, west_open]  (north = -z)
var open := []
var start_cell := Vector2i(0, 0)
var exit_cell := Vector2i(N - 1, N - 1)

var _body: StaticBody3D
var _wall_xf: Array[Transform3D] = []


func build(seed_value: int) -> void:
	rng.seed = seed_value * 31 + 7
	_carve()
	_body = StaticBody3D.new()
	_body.name = "MazeBody"
	add_child(_body)
	var size := N * CELL
	# floor and ceiling
	_box(ORIGIN + Vector3(size * 0.5, -0.5, size * 0.5), Vector3(size + 2, 1.0, size + 2))
	_box(ORIGIN + Vector3(size * 0.5, WALL_H + 0.5, size * 0.5), Vector3(size + 2, 1.0, size + 2))
	# outer walls
	for side in 4:
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, side * PI * 0.5)
		var c := ORIGIN + Vector3(size * 0.5, WALL_H * 0.5, size * 0.5) + dir * (size * 0.5 + WALL_T * 0.5)
		_box(c, Vector3(absf(dir.z) * size + WALL_T * 2.0 + 0.01, WALL_H, absf(dir.x) * size + WALL_T * 2.0 + 0.01))
	# inner walls: east and south side of each cell when closed
	for x in N:
		for z in N:
			var c := cell_center(Vector2i(x, z))
			c.y = ORIGIN.y + WALL_H * 0.5
			if x < N - 1 and not open[x][z][1]:
				_box(c + Vector3(CELL * 0.5, 0, 0), Vector3(WALL_T, WALL_H, CELL + WALL_T))
			if z < N - 1 and not open[x][z][2]:
				_box(c + Vector3(0, 0, CELL * 0.5), Vector3(CELL + WALL_T, WALL_H, WALL_T))
	_build_visuals()


func _carve() -> void:
	open.clear()
	for x in N:
		var col := []
		for z in N:
			col.append([false, false, false, false])
		open.append(col)
	var visited := {}
	var stack: Array[Vector2i] = [start_cell]
	visited[start_cell] = true
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while not stack.is_empty():
		var cur: Vector2i = stack[-1]
		var options := []
		for i in 4:
			var nb: Vector2i = cur + dirs[i]
			if nb.x >= 0 and nb.y >= 0 and nb.x < N and nb.y < N and not visited.has(nb):
				options.append(i)
		if options.is_empty():
			stack.pop_back()
			continue
		var d: int = options[rng.randi_range(0, options.size() - 1)]
		var nb: Vector2i = cur + dirs[d]
		open[cur.x][cur.y][d] = true
		open[nb.x][nb.y][(d + 2) % 4] = true
		visited[nb] = true
		stack.append(nb)
	# knock out a few extra walls so there are loops (more ways to dodge the Shadow)
	for i in 14:
		var x := rng.randi_range(0, N - 2)
		var z := rng.randi_range(0, N - 1)
		open[x][z][1] = true
		open[x + 1][z][3] = true


func _box(c: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = c
	_body.add_child(cs)
	_wall_xf.append(Transform3D(Basis.from_scale(size), c))


func _build_visuals() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rock.gdshader")
	mat.set_shader_parameter("rock_color", Color(0.22, 0.2, 0.26))
	mat.set_shader_parameter("moss_color", Color(0.18, 0.1, 0.28))
	mat.set_shader_parameter("moss_amount", 0.4)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = _wall_xf.size()
	for i in _wall_xf.size():
		mm.set_instance_transform(i, _wall_xf[i])
		mm.set_instance_color(i, Color(1, 1, 1))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MazeWalls"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.layers = LAYER
	add_child(mmi)
	# soft purple fill so the walls are always just visible (only lights the maze)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.45, 0.85)
	fill.light_energy = 0.45
	fill.light_cull_mask = LAYER
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-60, 30, 0)
	add_child(fill)
	# eerie purple lights along the way, glowing mushrooms, and the green exit
	for i in 12:
		var cell := Vector2i(rng.randi_range(0, N - 1), rng.randi_range(0, N - 1))
		var l := OmniLight3D.new()
		l.light_color = Color(0.65, 0.4, 1.0)
		l.light_energy = 2.4
		l.omni_range = 11.0
		l.position = cell_center(cell) + Vector3(0, WALL_H - 0.6, 0)
		add_child(l)
	var mush_mat := StandardMaterial3D.new()
	mush_mat.albedo_color = Color(0.5, 0.3, 0.9)
	mush_mat.emission_enabled = true
	mush_mat.emission = Color(0.6, 0.3, 1.0)
	mush_mat.emission_energy_multiplier = 3.0
	var mush := SphereMesh.new()
	mush.radius = 0.2
	mush.height = 0.2
	mush.is_hemisphere = true
	mush.material = mush_mat
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = mush
	mm2.instance_count = 60
	for i in 60:
		var cell := Vector2i(rng.randi_range(0, N - 1), rng.randi_range(0, N - 1))
		var off := Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-1.6, 1.6))
		var s := rng.randf_range(0.7, 1.8)
		mm2.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), cell_center(cell) + off))
	var mmi2 := MultiMeshInstance3D.new()
	mmi2.multimesh = mm2
	mmi2.layers = LAYER
	mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi2)
	# exit pad
	var pad := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 1.4
	cyl.height = 0.15
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.3, 1.0, 0.4)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.3, 1.0, 0.4)
	pad_mat.emission_energy_multiplier = 4.0
	cyl.material = pad_mat
	pad.mesh = cyl
	pad.layers = LAYER
	pad.position = exit_pos()
	add_child(pad)
	var beam := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 1.2
	bc.bottom_radius = 1.2
	bc.height = WALL_H
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.25)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bc.material = beam_mat
	beam.mesh = bc
	beam.layers = LAYER
	beam.position = exit_pos() + Vector3(0, WALL_H * 0.5, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var el := OmniLight3D.new()
	el.light_color = Color(0.4, 1.0, 0.5)
	el.light_energy = 3.0
	el.omni_range = 10.0
	el.position = exit_pos() + Vector3(0, 1.5, 0)
	add_child(el)
	var lbl := Label3D.new()
	lbl.text = "EXIT"
	lbl.font_size = 96
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.6, 1.0, 0.6)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = exit_pos() + Vector3(0, 2.4, 0)
	lbl.layers = LAYER
	add_child(lbl)


func cell_center(c: Vector2i) -> Vector3:
	return ORIGIN + Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((p.x - ORIGIN.x) / CELL), 0, N - 1), clampi(floori((p.z - ORIGIN.z) / CELL), 0, N - 1))


func start_pos() -> Vector3:
	return cell_center(start_cell) + Vector3(0, 0.3, 0)


func exit_pos() -> Vector3:
	return cell_center(exit_cell) + Vector3(0, 0.05, 0)


func contains(p: Vector3) -> bool:
	var size := N * CELL
	return p.y < ORIGIN.y + WALL_H + 2.0 and p.y > ORIGIN.y - 5.0 \
		and p.x > ORIGIN.x - 1.0 and p.x < ORIGIN.x + size + 1.0 \
		and p.z > ORIGIN.z - 1.0 and p.z < ORIGIN.z + size + 1.0


## The next cell to walk to on the shortest path from 'from' to 'to' (BFS over open walls).
func next_step(from: Vector2i, to: Vector2i) -> Vector2i:
	if from == to:
		return to
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			break
		for i in 4:
			if not open[cur.x][cur.y][i]:
				continue
			var nb: Vector2i = cur + dirs[i]
			if not prev.has(nb):
				prev[nb] = cur
				queue.append(nb)
	if not prev.has(to):
		return from
	var step: Vector2i = to
	while prev[step] != from:
		step = prev[step]
	return step
