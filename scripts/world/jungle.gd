class_name Jungle
extends Node3D
## Procedurally builds the 300 x 300 m jungle from a seed. Every peer builds the same
## gameplay geometry from the shared seed, so nothing about the map is sent over the network.
## Purely decorative vegetation density follows the local graphics setting.

const HALF := 150.0
const GRID_STEP := 2.0
const GRID_N := 151
const WATER_Y := -0.6
const PLATEAU_H := 22.0
const RIVER_START_Z := -106.0
const CAVE_CENTER := Vector2(-92.0, 60.0)
const CAVE_FLOOR := 2.0
const LOG_CENTER := Vector2(52.0, 92.0)
# secret cave complex inside the plateau, entered from behind the waterfall
const SC_CELL := 4.4
const SC_NX := 16
const SC_NZ := 6
const SC_FLOOR := 1.6
const SC_CEIL := 3.6
const SC_Z0 := -113.7          # south edge of the tunnels (z decreases going north)
const SC_EXITS := [[15, 2, 1.0], [0, 4, -1.0]]   # [cell x, cell z, side] tunnels out of the cliff sides
const SC_SHAFT := Vector2i(12, 4)                  # ladder shaft up to the plateau top

var seed_value := 1
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var heights := PackedFloat32Array()
var plateau_x := 0.0
var secret_cave_spots: Array[Vector3] = []   # dead ends deep in the waterfall cave (bananas start there)
var secret_cave_open := []                   # [x][z] -> [north, east, south, west] open passages

## Gameplay data used by players and AI
var trees: Array = []          # [{pos: Vector3 (base), radius, height, branches: [{start, end, radius}]}]
var vines: Array[Vine] = []
var hide_spots: Array = []     # [{pos: Vector3, radius: float, kind: String}]
var spawn_points: Array[Vector3] = []
var platforms: Array = []      # [{pos: Vector3 (top centre), size}]
var foliage_grid := {}         # Vector2i -> Array of [Vector3 centre, radius]

var _batches := {}
var _mats := {}
var _meshes := {}
var _body_climb: StaticBody3D
var _body_solid: StaticBody3D
var _vine_mesh: ArrayMesh
var _vine_mat: ShaderMaterial


func build(p_seed: int) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	noise.seed = p_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.011
	noise.fractal_octaves = 4
	noise2.seed = p_seed + 99
	noise2.frequency = 0.05
	plateau_x = river_x(RIVER_START_Z)
	_make_materials()
	_body_climb = StaticBody3D.new()
	_body_climb.name = "ClimbableGeometry"
	_body_climb.add_to_group("climbable")
	add_child(_body_climb)
	_body_solid = StaticBody3D.new()
	_body_solid.name = "SolidGeometry"
	add_child(_body_solid)

	_build_terrain()
	_build_water()
	_build_waterfall()
	_build_cliff_rocks()
	_build_cave()
	_build_secret_cave()
	_build_hollow_log()
	_build_trees()
	_build_bridges()
	_build_stilt_platforms()
	_build_bushes()
	_build_rock_outcrops()
	_build_bounds()
	_pick_spawns()
	# decorative vegetation uses its own RNG so graphics settings never change gameplay geometry
	var veg := RandomNumberGenerator.new()
	veg.seed = p_seed * 7 + 3
	_build_ground_cover(veg, Settings.vegetation_density)
	_flush_batches()
	_build_ambient_audio()


# ======================================================================== terrain
func river_x(z: float) -> float:
	return 22.0 * sin(z * 0.017 + 0.6) + 8.0 * sin(z * 0.043) - 5.0


func _raw_height(x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	var h := 1.5 + n * 6.0 + noise2.get_noise_2d(x, z) * 0.8
	var d := maxf(absf(x), absf(z))
	var rim := smoothstep(122.0, 150.0, d)
	h += rim * rim * 28.0
	# rocky plateau at the north end with a cliff face and a stream on top
	var pm := plateau_mask(x, z)
	if pm > 0.0:
		# kept perfectly flat over the waterfall cave so its rock roof matches the surface
		h = lerpf(h, PLATEAU_H + n * 0.4 * (0.0 if _in_cave_zone(x, z) else 1.0), pm)
		var ds := absf(x - plateau_x)
		h -= smoothstep(4.5, 2.0, ds) * 1.4 * pm
	# flattened clearing for the cave
	var dc := Vector2(x, z).distance_to(CAVE_CENTER)
	h = lerpf(h, CAVE_FLOOR, 1.0 - smoothstep(27.0, 36.0, dc))
	# flattened ground under the hollow log
	var dl := Vector2(x, z).distance_to(LOG_CENTER)
	h = lerpf(h, 1.2, 1.0 - smoothstep(10.0, 16.0, dl))
	# river channel
	if z > RIVER_START_Z - 8.0:
		var dr := absf(x - river_x(z))
		var k := smoothstep(RIVER_START_Z - 8.0, RIVER_START_Z, z)
		h = lerpf(h, -2.6, smoothstep(13.0, 6.0, dr) * k)
	# plunge pool under the waterfall
	var dp := Vector2(x, z).distance_to(Vector2(plateau_x, RIVER_START_Z + 2.0))
	h = lerpf(h, -3.2, smoothstep(13.0, 7.0, dp) * (1.0 - pm))
	return h


func plateau_mask(x: float, z: float) -> float:
	var dx := maxf(0.0, absf(x - plateau_x) - 36.0)
	var dz := maxf(0.0, z - (-112.0))
	return 1.0 - smoothstep(0.0, 3.5, maxf(dx, dz))


## Ground height matching the collision heightmap.
func ground_height(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / GRID_STEP, 0.0, GRID_N - 1.001)
	var gz := clampf((z + HALF) / GRID_STEP, 0.0, GRID_N - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var h00 := heights[iz * GRID_N + ix]
	var h10 := heights[iz * GRID_N + ix + 1]
	var h01 := heights[(iz + 1) * GRID_N + ix]
	var h11 := heights[(iz + 1) * GRID_N + ix + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func is_in_water(p: Vector3) -> bool:
	if p.y > WATER_Y:
		return false
	if plateau_mask(p.x, p.z) > 0.5:
		return false
	# far below the riverbed (the black hole maze, the cave) there is no water
	var gh := ground_height(p.x, p.z)
	return gh < WATER_Y and p.y > gh - 3.0


func is_river(x: float, z: float, margin: float = 0.0) -> bool:
	return z > RIVER_START_Z - 10.0 and absf(x - river_x(z)) < 11.0 + margin \
		or Vector2(x, z).distance_to(Vector2(plateau_x, RIVER_START_Z + 2.0)) < 13.0 + margin


func _build_terrain() -> void:
	heights.resize(GRID_N * GRID_N)
	for iz in GRID_N:
		for ix in GRID_N:
			heights[iz * GRID_N + ix] = _raw_height(-HALF + ix * GRID_STEP, -HALF + iz * GRID_STEP)
	# the drawn and collidable terrain is hollowed out under the plateau for the waterfall cave;
	# ground_height() keeps reporting the surface on top
	var carved := heights.duplicate()
	for iz in GRID_N:
		for ix in GRID_N:
			var i := iz * GRID_N + ix
			carved[i] = _cave_carve(-HALF + ix * GRID_STEP, -HALF + iz * GRID_STEP, heights[i])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in GRID_N:
		for ix in GRID_N:
			var x := -HALF + ix * GRID_STEP
			var z := -HALF + iz * GRID_STEP
			var h := carved[iz * GRID_N + ix]
			var dr := absf(x - river_x(z)) if z > RIVER_START_Z - 6.0 else 99.0
			var sand := smoothstep(16.0, 9.0, dr) if h < 2.2 else 0.0
			var mud := clampf(noise2.get_noise_2d(x * 0.7, z * 0.7) * 1.6, 0.0, 1.0) * (1.0 - sand)
			if Vector2(x, z).distance_to(CAVE_CENTER) < 30.0:
				mud = maxf(mud, 0.6)
			st.set_color(Color(1.0 - sand - mud, mud, sand))
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, h, z))
	for iz in GRID_N - 1:
		for ix in GRID_N - 1:
			var i := iz * GRID_N + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + GRID_N)
			st.add_index(i + 1)
			st.add_index(i + GRID_N + 1)
			st.add_index(i + GRID_N)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	mi.material_override = _mats.terrain
	add_child(mi)
	# collision: heightmap with 1 m cells, scaled x2 (uniform) to 2 m cells
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.add_to_group("terrain")
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = GRID_N
	shape.map_depth = GRID_N
	var data := PackedFloat32Array()
	data.resize(GRID_N * GRID_N)
	for i in heights.size():
		data[i] = carved[i] / GRID_STEP
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * GRID_STEP
	body.add_child(cs)


func _build_water() -> void:
	# river strip following the channel
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := RIVER_START_Z - 4.0
	var rows := 0
	while z <= HALF + 2.0:
		var cx := river_x(z)
		st.set_uv(Vector2(0, z * 0.1))
		st.add_vertex(Vector3(cx - 13.0, WATER_Y, z))
		st.set_uv(Vector2(1, z * 0.1))
		st.add_vertex(Vector3(cx + 13.0, WATER_Y, z))
		rows += 1
		z += 3.0
	for r in rows - 1:
		var i := r * 2
		st.add_index(i); st.add_index(i + 1); st.add_index(i + 2)
		st.add_index(i + 1); st.add_index(i + 3); st.add_index(i + 2)
	st.generate_normals()
	var river := MeshInstance3D.new()
	river.name = "River"
	river.mesh = st.commit()
	river.material_override = _mats.water
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)
	# plunge pool disc
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(28, 26)
	pool.mesh = pm
	pool.material_override = _mats.water
	pool.position = Vector3(plateau_x, WATER_Y, RIVER_START_Z + 2.0)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	# stream on top of the plateau
	var stream := MeshInstance3D.new()
	var sm := PlaneMesh.new()
	sm.size = Vector2(6.5, 40)
	stream.mesh = sm
	var smat: ShaderMaterial = _mats.water.duplicate()
	smat.set_shader_parameter("flow", Vector2(0.0, 1.2))
	stream.material_override = smat
	stream.position = Vector3(plateau_x, PLATEAU_H - 0.5, -131.0)
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stream)


func _build_waterfall() -> void:
	var lip_z := -110.5
	var top := PLATEAU_H - 0.5
	var bottom := WATER_Y - 0.5
	# overhanging lip the water pours from
	_rock_box(Vector3(plateau_x, PLATEAU_H - 1.2, lip_z + 1.5), Vector3(13, 2.4, 5.5), 0.0)
	# hidden alcove behind the falling water: ledge, side pillars
	_rock_box(Vector3(plateau_x, -0.9, lip_z + 1.6), Vector3(12, 5.0, 4.4), 0.0)
	_rock_box(Vector3(plateau_x - 7.2, 10.0, lip_z + 1.8), Vector3(2.6, 22.0, 5.4), 0.0)
	_rock_box(Vector3(plateau_x + 7.2, 10.0, lip_z + 1.8), Vector3(2.6, 22.0, 5.4), 0.0)
	# stepping boulders out of the pool onto the ledge
	_boulder(Vector3(plateau_x + 3.0, -1.6, lip_z + 5.8), Vector3(1.6, 2.2, 1.4))
	_boulder(Vector3(plateau_x - 2.5, -1.8, lip_z + 6.4), Vector3(1.4, 1.9, 1.3))
	hide_spots.append({"pos": Vector3(plateau_x, 1.7, lip_z + 1.4), "radius": 4.0, "kind": "waterfall"})
	_add_foliage_sphere(Vector3(plateau_x, 2.5, lip_z + 1.4), 3.5)
	var sheet := MeshInstance3D.new()
	sheet.name = "Waterfall"
	var qm := QuadMesh.new()
	qm.size = Vector2(9.0, top - bottom)
	sheet.mesh = qm
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/waterfall.gdshader")
	sheet.material_override = wmat
	sheet.position = Vector3(plateau_x, (top + bottom) * 0.5, lip_z + 4.1)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)
	# mist and splash particles
	var mist := GPUParticles3D.new()
	mist.name = "Mist"
	mist.amount = 60
	mist.lifetime = 2.5
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(4.5, 0.3, 1.0)
	pmat.direction = Vector3(0, 1, 1)
	pmat.spread = 50.0
	pmat.initial_velocity_min = 1.5
	pmat.initial_velocity_max = 3.5
	pmat.gravity = Vector3(0, 0.2, 0)
	pmat.scale_min = 1.5
	pmat.scale_max = 3.0
	mist.process_material = pmat
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.5
	pmesh.height = 1.0
	pmesh.radial_segments = 8
	pmesh.rings = 4
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(1, 1, 1, 0.18)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmesh.material = mm
	mist.draw_pass_1 = pmesh
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist.position = Vector3(plateau_x, WATER_Y, lip_z + 4.5)
	add_child(mist)


func _build_cliff_rocks() -> void:
	# boulders along the plateau cliffs give climbable routes up
	var x0 := plateau_x - 37.5
	var x1 := plateau_x + 37.5
	var x := x0
	while x <= x1:
		if absf(x - plateau_x) > 9.0:
			var by := ground_height(x, -110.0)
			var s := rng.randf_range(2.0, 3.6)
			_boulder(Vector3(x, by + s * 0.4, -110.5 + rng.randf_range(-0.8, 0.8)), Vector3(s, s * rng.randf_range(1.0, 1.8), s))
			if rng.randf() < 0.6:
				var s2 := rng.randf_range(1.6, 2.6)
				_boulder(Vector3(x + rng.randf_range(-2, 2), by + s * 1.2 + s2 * 0.5, -111.5), Vector3(s2, s2, s2))
		x += rng.randf_range(4.5, 7.0)
	for side in [-1.0, 1.0]:
		var z := -148.0
		while z < -112.0:
			var cx: float = plateau_x + side * 41.5
			var s := rng.randf_range(2.0, 3.4)
			_boulder(Vector3(cx + side * 0.6, ground_height(cx + side * 3.0, z) + s * 0.5, z), Vector3(s, s * 1.5, s))
			z += rng.randf_range(5.0, 8.0)
	# a wooden ladder up the cliff for the less acrobatic, with a little landing at the top
	var lx := plateau_x - 20.0
	var lbase := ground_height(lx, -108.5)
	_ladder(Vector3(lx, lbase, -108.6), PLATEAU_H - lbase + 1.0, Vector3(0, 0, 1))
	_wood_box(Vector3(lx, PLATEAU_H - 0.1, -109.5), Vector3(2.2, 0.2, 2.2), true)


func _build_cave() -> void:
	var c := Vector3(CAVE_CENTER.x, CAVE_FLOOR, CAVE_CENTER.y)
	var boxes := [
		# north wall
		[Vector3(0, 3, -8.5), Vector3(22, 6, 3)],
		# south wall with entrance
		[Vector3(-6.5, 3, 8.5), Vector3(9, 6, 3)],
		[Vector3(6.5, 3, 8.5), Vector3(9, 6, 3)],
		[Vector3(0, 4.75, 8.5), Vector3(4, 2.5, 3)],
		# west wall with the secret tunnel opening
		[Vector3(-9.5, 3, -4.125), Vector3(3, 6, 5.75)],
		[Vector3(-9.5, 3, 4.125), Vector3(3, 6, 5.75)],
		[Vector3(-9.5, 4.2, 0), Vector3(3, 3.6, 2.5)],
		# east wall
		[Vector3(9.5, 3, 0), Vector3(3, 6, 14)],
		# roof
		[Vector3(0, 7, 0), Vector3(22, 2, 20)],
		# secret tunnel heading west...
		[Vector3(-15.5, 1.2, -2.0), Vector3(9, 2.4, 1.5)],
		[Vector3(-15.5, 1.2, 2.0), Vector3(9, 2.4, 1.5)],
		[Vector3(-15.5, 2.9, 0), Vector3(9, 1.0, 5.5)],
		# ...then turning north to a hidden exit
		[Vector3(-22.0, 1.2, 2.0), Vector3(4.0, 2.4, 1.5)],
		[Vector3(-24.75, 1.2, -5.0), Vector3(1.5, 2.4, 15.5)],
		[Vector3(-17.25, 1.2, -7.75), Vector3(1.5, 2.4, 10.0)],
		[Vector3(-21.0, 2.9, -5.0), Vector3(9, 1.0, 15.5)],
	]
	for b in boxes:
		_rock_box(c + b[0], b[1], 0.0)
	# rocky mound look: boulders piled over the cave
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 12.0)
		var p := c + Vector3(cos(a) * r, 7.5 + rng.randf_range(-0.5, 1.5), sin(a) * r * 0.85)
		var s := rng.randf_range(2.0, 4.5)
		_boulder(p, Vector3(s, s * 0.7, s))
	for i in 10:
		var a := rng.randf() * TAU
		var p := c + Vector3(cos(a) * 12.5, rng.randf_range(1.0, 4.0), sin(a) * 11.0)
		if p.z > c.z + 7.0 and absf(p.x - c.x) < 4.0:
			continue
		var s := rng.randf_range(2.0, 3.5)
		_boulder(p, Vector3(s, s, s))
	# glowing mushrooms and a cool light inside
	for i in 18:
		var p := c + Vector3(rng.randf_range(-7.5, 7.5), 0.15, rng.randf_range(-6.5, 6.5))
		if i > 12:
			p = c + Vector3(rng.randf_range(-23.5, -12.0), 0.15, rng.randf_range(-1.0, 1.0))
		var s := rng.randf_range(0.2, 0.45)
		_add_batch("mushroom", Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), p), Color.from_hsv(rng.randf_range(0.45, 0.6), 0.7, 1.0))
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.9, 1.0)
	light.light_energy = 2.2
	light.omni_range = 14.0
	light.position = c + Vector3(0, 4.0, 0)
	light.shadow_enabled = false
	add_child(light)
	hide_spots.append({"pos": c + Vector3(-5, 0.5, -4), "radius": 4.0, "kind": "cave"})
	hide_spots.append({"pos": c + Vector3(-21, 0.5, -5), "radius": 2.0, "kind": "tunnel"})
	# bushes hiding the secret exit
	for i in 4:
		var p := c + Vector3(-21 + rng.randf_range(-3, 3), 0.6, -15 + rng.randf_range(-2, 1))
		_bush(p, rng.randf_range(1.4, 2.0))


# ======================================================================== waterfall cave
## Inside the rock band around the waterfall cave (no plateau noise, no props from the surface).
func _in_cave_zone(x: float, z: float) -> bool:
	return absf(x - plateau_x) <= 39.7 and z <= -110.2 and z >= -144.6


## Over the cave: the stream channel and the ladder shaft opening have no ground to put things on.
func _cave_roof_blocked(x: float, z: float, margin: float) -> bool:
	if not _in_cave_zone(x, z):
		return false
	var sc := sc_center(SC_SHAFT)
	return absf(x - plateau_x) < 5.0 or (absf(x - sc.x) < 2.2 + margin and absf(z - sc.z) < 2.2 + margin)


## Terrain height with the cave hollowed out (used for the drawn and collidable terrain only).
func _cave_carve(x: float, z: float, h: float) -> float:
	var u := x - plateau_x
	if absf(u) <= 37.4 and z <= -111.5 and z >= -142.3:
		return SC_FLOOR
	if absf(u) <= 3.0 and z > -111.5 and z <= -108.0:
		return SC_FLOOR
	for e in SC_EXITS:
		var zc := sc_center(Vector2i(e[0], e[1])).z
		var su: float = u * e[2]
		if su >= 35.0 and su <= 46.0 and absf(z - zc) <= 3.8:
			return lerpf(SC_FLOOR, h, clampf((su - 39.7) / 6.3, 0.0, 1.0))
	return h


func sc_center(c: Vector2i) -> Vector3:
	return Vector3(plateau_x - 35.2 + (c.x + 0.5) * SC_CELL, SC_FLOOR, SC_Z0 - (c.y + 0.5) * SC_CELL)


## A rock box spanning world x0..x1, y0..y1, z0..z1.
func _rock_span(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	if x1 - x0 < 0.05 or y1 - y0 < 0.05 or z1 - z0 < 0.05:
		return
	_rock_box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, y1 - y0, z1 - z0), 0.0)


## A maze of tunnels inside the plateau: a grotto right behind the falling water, a crystal
## chamber in the middle, twisting passages with dead ends, two hidden tunnels out of the
## cliff sides and a ladder shaft up to the plateau top.
func _build_secret_cave() -> void:
	var px := plateau_x
	var x0 := px - 35.2
	var x1 := px + 35.2
	var zs := SC_Z0                          # south edge
	var zn := SC_Z0 - SC_NZ * SC_CELL        # north edge
	var f := SC_FLOOR
	var top := f + SC_CEIL
	var stream_top := PLATEAU_H - 1.4
	# --- carve the tunnels (recursive backtracker, plus extra loops)
	var open := []
	for i in SC_NX:
		var col := []
		for j in SC_NZ:
			col.append([false, false, false, false])   # north(j+1), east(i+1), south(j-1), west(i-1)
		open.append(col)
	var dirs := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var seen := {Vector2i(7, 0): true}
	var stack: Array[Vector2i] = [Vector2i(7, 0)]
	while not stack.is_empty():
		var cur: Vector2i = stack[-1]
		var opts := []
		for d in 4:
			var nb: Vector2i = cur + dirs[d]
			if nb.x >= 0 and nb.y >= 0 and nb.x < SC_NX and nb.y < SC_NZ and not seen.has(nb):
				opts.append(d)
		if opts.is_empty():
			stack.pop_back()
			continue
		var d: int = opts[rng.randi_range(0, opts.size() - 1)]
		var nb: Vector2i = cur + dirs[d]
		open[cur.x][cur.y][d] = true
		open[nb.x][nb.y][(d + 2) % 4] = true
		seen[nb] = true
		stack.append(nb)
	for k in 9:
		var i := rng.randi_range(0, SC_NX - 2)
		var j := rng.randi_range(0, SC_NZ - 1)
		open[i][j][1] = true
		open[i + 1][j][3] = true
	# rooms: the grotto behind the waterfall and the crystal chamber
	var rooms := [[Rect2i(7, 0, 2, 2), "grotto"], [Rect2i(5, 3, 6, 2), "crystal"]]
	for room in rooms:
		var r: Rect2i = room[0]
		for i in range(r.position.x, r.end.x):
			for j in range(r.position.y, r.end.y):
				if i + 1 < r.end.x:
					open[i][j][1] = true
					open[i + 1][j][3] = true
				if j + 1 < r.end.y:
					open[i][j][0] = true
					open[i][j + 1][2] = true
	secret_cave_open = open
	# --- rock: floor, inner walls, roof
	_rock_span(x0, x1, f - 0.35, f + 0.05, zn, zs)
	for i in SC_NX:
		for j in SC_NZ:
			var c := sc_center(Vector2i(i, j))
			if i < SC_NX - 1 and not open[i][j][1]:
				_rock_box(Vector3(c.x + SC_CELL * 0.5, f + SC_CEIL * 0.5, c.z), Vector3(0.7, SC_CEIL, SC_CELL + 0.7), 0.0)
			if j < SC_NZ - 1 and not open[i][j][0]:
				_rock_box(Vector3(c.x, f + SC_CEIL * 0.5, c.z - SC_CELL * 0.5), Vector3(SC_CELL + 0.7, SC_CEIL, 0.7), 0.0)
			if Vector2i(i, j) == SC_SHAFT:
				continue
			var roof_top := stream_top if absf(c.x - px) < SC_CELL else PLATEAU_H
			_rock_span(c.x - SC_CELL * 0.5, c.x + SC_CELL * 0.5, top, roof_top, c.z - SC_CELL * 0.5, c.z + SC_CELL * 0.5)
	# --- thick outer rock (fills the gap between the tunnels and the old plateau surface)
	var exit_z := {}
	for e in SC_EXITS:
		exit_z[e[2]] = sc_center(Vector2i(e[0], e[1])).z
	for side in [-1.0, 1.0]:
		var a: float = px + side * 35.2
		var b: float = px + side * 39.7
		var lo := minf(a, b)
		var hi := maxf(a, b)
		var ez: float = exit_z[side]
		_rock_span(lo, hi, f - 1.0, PLATEAU_H, ez + 1.6, -110.2)
		_rock_span(lo, hi, f - 1.0, PLATEAU_H, -144.6, ez - 1.6)
		_rock_span(lo, hi, f + 3.0, PLATEAU_H, ez - 1.6, ez + 1.6)   # tunnel roof
		_rock_span(lo, hi, f - 0.35, f + 0.05, ez - 1.6, ez + 1.6)   # tunnel floor
	# north
	_rock_span(px - 39.7, px - SC_CELL, f - 1.0, PLATEAU_H, -144.6, zn)
	_rock_span(px + SC_CELL, px + 39.7, f - 1.0, PLATEAU_H, -144.6, zn)
	_rock_span(px - SC_CELL, px + SC_CELL, f - 1.0, stream_top, -144.6, zn)
	# south: solid cliff rock, except a doorway straight behind the waterfall
	_rock_span(px - 35.2, px - 6.0, f - 1.0, PLATEAU_H, zs, -110.2)
	_rock_span(px + 6.0, px + 35.2, f - 1.0, PLATEAU_H, zs, -110.2)
	_rock_span(px - 6.0, px - 1.3, -1.5, stream_top, zs, -110.7)
	_rock_span(px + 1.3, px + 6.0, -1.5, stream_top, zs, -110.7)
	_rock_span(px - 1.3, px + 1.3, f + 3.0, stream_top, zs, -110.7)
	_rock_span(px - 1.3, px + 1.3, f - 0.35, f + 0.05, zs, -110.7)
	# --- the ladder shaft up to the plateau, hidden in bushes at the top
	var sc := sc_center(SC_SHAFT)
	_ladder(Vector3(sc.x, f + 0.05, sc.z - SC_CELL * 0.5 + 0.5), PLATEAU_H - f + 0.6, Vector3(0, 0, 1))
	for k in 5:
		var a := float(k) / 5.0 * TAU + 0.4
		_bush(Vector3(sc.x + cos(a) * 3.4, PLATEAU_H + 0.6, sc.z + sin(a) * 3.4), rng.randf_range(1.2, 1.7))
	var shaft_light := OmniLight3D.new()
	shaft_light.light_color = Color(1.0, 0.95, 0.8)
	shaft_light.light_energy = 1.2
	shaft_light.omni_range = 8.0
	shaft_light.position = sc + Vector3(0, 3.0, 0)
	add_child(shaft_light)
	# --- bushes over the cliff-side tunnel mouths
	for e in SC_EXITS:
		var ez: float = sc_center(Vector2i(e[0], e[1])).z
		var mx: float = px + e[2] * 41.0
		for k in 3:
			var bz := ez + (k - 1) * 2.0 + rng.randf_range(-0.4, 0.4)
			_bush(Vector3(mx + e[2] * rng.randf_range(0.5, 2.5), ground_height(mx, bz) + 0.5, bz), rng.randf_range(1.2, 1.6))
	# --- inside: crystals, torches, mushrooms
	var crystal_mat := StandardMaterial3D.new()
	crystal_mat.albedo_color = Color(0.4, 0.85, 1.0)
	crystal_mat.emission_enabled = true
	crystal_mat.emission = Color(0.3, 0.8, 1.0)
	crystal_mat.emission_energy_multiplier = 2.5
	crystal_mat.metallic = 0.3
	crystal_mat.roughness = 0.1
	var crystal_mat2: StandardMaterial3D = crystal_mat.duplicate()
	crystal_mat2.albedo_color = Color(0.85, 0.45, 1.0)
	crystal_mat2.emission = Color(0.75, 0.3, 1.0)
	for room in rooms:
		var r: Rect2i = room[0]
		var a := sc_center(r.position)
		var b := sc_center(r.end - Vector2i.ONE)
		var mid := (a + b) * 0.5
		var hx := absf(b.x - a.x) * 0.5 + SC_CELL * 0.5 - 0.8
		var hz := absf(b.z - a.z) * 0.5 + SC_CELL * 0.5 - 0.8
		var count := 10 if room[1] == "grotto" else 22
		for k in count:
			var p := mid + Vector3(rng.randf_range(-hx, hx), 0.0, rng.randf_range(-hz, hz))
			if room[1] == "grotto" and absf(p.x - px) < 1.6 and p.z > zs - 3.0:
				continue   # keep the doorway clear
			_crystal(p, rng.randf_range(0.5, 1.6), crystal_mat if rng.randf() < 0.6 else crystal_mat2)
		var l := OmniLight3D.new()
		l.light_color = Color(0.4, 0.85, 1.0) if room[1] == "grotto" else Color(0.7, 0.45, 1.0)
		l.light_energy = 2.4
		l.omni_range = 12.0 if room[1] == "grotto" else 16.0
		l.position = mid + Vector3(0, SC_CEIL - 0.8, 0)
		add_child(l)
		hide_spots.append({"pos": mid + Vector3(0, 0.5, 0), "radius": 3.0, "kind": "waterfall_cave"})
	# dead ends: bananas start there, and they are the best hiding places
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.6, 0.2)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.5, 0.1)
	flame_mat.emission_energy_multiplier = 4.0
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var torches := 0
	for i in SC_NX:
		for j in SC_NZ:
			var cell := Vector2i(i, j)
			var c := sc_center(cell)
			var exits := 0
			for d in 4:
				if open[i][j][d]:
					exits += 1
			var is_exit := false
			for e in SC_EXITS:
				if e[0] == i and e[1] == j:
					is_exit = true
			if exits == 1 and not is_exit and cell != SC_SHAFT:
				secret_cave_spots.append(c)
				hide_spots.append({"pos": c + Vector3(0, 0.5, 0), "radius": 1.6, "kind": "tunnel"})
			# glowing mushrooms along the floor
			if rng.randf() < 0.55:
				for k in rng.randi_range(1, 3):
					var p := c + Vector3(rng.randf_range(-1.6, 1.6), 0.15, rng.randf_range(-1.6, 1.6))
					var s := rng.randf_range(0.2, 0.42)
					_add_batch("mushroom", Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), p), Color.from_hsv(rng.randf_range(0.45, 0.85), 0.7, 1.0))
			# torches on a closed wall every so often
			if torches < 9 and (i * 7 + j * 3) % 5 == 0:
				for d in 4:
					if open[i][j][d]:
						continue
					var dir := Vector3(dirs[d].x, 0, -dirs[d].y)
					var tp := c + dir * (SC_CELL * 0.5 - 0.45) + Vector3(0, 2.2, 0)
					_wood_box(tp + Vector3(0, -0.3, 0), Vector3(0.12, 0.6, 0.12), false)
					var flame := MeshInstance3D.new()
					var fm := SphereMesh.new()
					fm.radius = 0.12
					fm.height = 0.34
					fm.radial_segments = 8
					fm.rings = 4
					fm.material = flame_mat
					flame.mesh = fm
					flame.position = tp + Vector3(0, 0.1, 0)
					flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(flame)
					var tl := OmniLight3D.new()
					tl.light_color = Color(1.0, 0.6, 0.3)
					tl.light_energy = 1.6
					tl.omni_range = 7.0
					tl.position = tp - dir * 0.4 + Vector3(0, 0.2, 0)
					add_child(tl)
					torches += 1
					break


func _crystal(p: Vector3, s: float, mat: StandardMaterial3D) -> void:
	var cluster := rng.randi_range(2, 4)
	for k in cluster:
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.18 * s
		cm.height = rng.randf_range(0.7, 1.4) * s
		cm.radial_segments = 6
		cm.rings = 1
		cm.material = mat
		m.mesh = cm
		m.position = p + Vector3(rng.randf_range(-0.3, 0.3), cm.height * 0.4, rng.randf_range(-0.3, 0.3))
		m.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)


func _build_hollow_log() -> void:
	var length := 16.0
	var r_out := 1.9
	var r_in := 1.45
	var axis_y := ground_height(LOG_CENTER.x, LOG_CENTER.y) + r_out - 0.5
	var center := Vector3(LOG_CENTER.x, axis_y, LOG_CENTER.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 16
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		for layer in 2:
			var r := r_out if layer == 0 else r_in
			var p00 := Vector3(-length * 0.5, sin(a0) * r, cos(a0) * r)
			var p01 := Vector3(-length * 0.5, sin(a1) * r, cos(a1) * r)
			var p10 := Vector3(length * 0.5, sin(a0) * r, cos(a0) * r)
			var p11 := Vector3(length * 0.5, sin(a1) * r, cos(a1) * r)
			var quad := [p00, p10, p11, p00, p11, p01] if layer == 0 else [p00, p11, p10, p00, p01, p11]
			for v in quad:
				st.add_vertex(v)
		# end rings
		for ex in [-length * 0.5, length * 0.5]:
			var o0 := Vector3(ex, sin(a0) * r_out, cos(a0) * r_out)
			var o1 := Vector3(ex, sin(a1) * r_out, cos(a1) * r_out)
			var i0 := Vector3(ex, sin(a0) * r_in, cos(a0) * r_in)
			var i1 := Vector3(ex, sin(a1) * r_in, cos(a1) * r_in)
			var ring := [o0, o1, i1, o0, i1, i0] if ex > 0 else [o0, i1, o1, o0, i0, i1]
			for v in ring:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "HollowLog"
	mi.mesh = st.commit()
	mi.material_override = _mats.bark_dark
	mi.position = center
	add_child(mi)
	# octagon of boxes for collision, walkable inside
	var oct := 8
	var chord := 2.0 * r_out * tan(PI / oct) + 0.1
	for i in oct:
		var a := TAU * i / oct
		var offset := Vector3(0, cos(a), sin(a)) * (r_in + r_out) * 0.5
		var basis := Basis(Vector3.RIGHT, a)
		_add_box_shape(_body_climb, Transform3D(basis, center + offset), Vector3(length, r_out - r_in, chord))
	hide_spots.append({"pos": center + Vector3(0, -r_in + 0.4, 0), "radius": 2.0, "kind": "log"})
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		_fern_at(center + Vector3(side * (length * 0.5 + rng.randf_range(0.3, 1.5)), -axis_y + ground_height(LOG_CENTER.x, LOG_CENTER.y), rng.randf_range(-2, 2)), 1.6)


# ======================================================================== trees
func _build_trees() -> void:
	var attempts := 0
	var target := 95
	while trees.size() < target and attempts < 6000:
		attempts += 1
		var x := rng.randf_range(-128.0, 128.0)
		var z := rng.randf_range(-140.0, 128.0)
		if is_river(x, z, 3.0):
			continue
		if Vector2(x, z).distance_to(CAVE_CENTER) < 30.0 or Vector2(x, z).distance_to(LOG_CENTER) < 12.0:
			continue
		var pm := plateau_mask(x, z)
		if pm > 0.02 and pm < 0.98:
			continue
		if pm >= 0.98 and (absf(x - plateau_x) < 8.0 or z > -116.0 or _cave_roof_blocked(x, z, 4.0)):
			continue
		if pm < 0.02 and z < -104.0 and absf(x - plateau_x) < 42.0:
			continue
		var ok := true
		for t in trees:
			if Vector2(t.pos.x, t.pos.z).distance_to(Vector2(x, z)) < 13.0:
				ok = false
				break
		if not ok:
			continue
		var radius := rng.randf_range(1.0, 2.4)
		var height := rng.randf_range(20.0, 46.0) * (0.85 if pm > 0.5 else 1.0)
		var base := Vector3(x, ground_height(x, z) - 0.5, z)
		trees.append({"pos": base, "radius": radius, "height": height, "branches": [], "platform": -1.0})
	_plan_platforms_and_beams()
	for i in trees.size():
		_build_tree(i)


var _bridge_pairs: Array = []
var _beam_pairs: Array = []
var _treehouse_ids: Array = []


func _plan_platforms_and_beams() -> void:
	var used := {}
	# rope bridges between tree platforms
	for i in trees.size():
		if _bridge_pairs.size() >= 14:
			break
		if used.has(i):
			continue
		for j in range(i + 1, trees.size()):
			if used.has(j):
				continue
			var a: Dictionary = trees[i]
			var b: Dictionary = trees[j]
			var d: float = Vector2(a.pos.x, a.pos.z).distance_to(Vector2(b.pos.x, b.pos.z))
			if d > 15.0 and d < 28.0 and absf(a.pos.y - b.pos.y) < 4.0:
				var h: float = maxf(a.pos.y, b.pos.y) + minf(a.height, b.height) * rng.randf_range(0.28, 0.4)
				a.platform = h
				b.platform = h
				used[i] = true
				used[j] = true
				_bridge_pairs.append([i, j])
				break
	# thick connecting beams between close trees
	for i in trees.size():
		if _beam_pairs.size() >= 26:
			break
		for j in range(i + 1, trees.size()):
			var a: Dictionary = trees[i]
			var b: Dictionary = trees[j]
			var d: float = Vector2(a.pos.x, a.pos.z).distance_to(Vector2(b.pos.x, b.pos.z))
			if d < 18.0 and rng.randf() < 0.7:
				_beam_pairs.append([i, j, rng.randf_range(0.45, 0.7)])
				break
	# treehouses on big trees without platforms
	for i in trees.size():
		if _treehouse_ids.size() >= 6:
			break
		var t: Dictionary = trees[i]
		if t.platform < 0.0 and t.radius > 1.5 and t.height > 26.0 and not used.has(i):
			_treehouse_ids.append(i)
			t.platform = t.pos.y + clampf(t.height * 0.38, 11.0, 17.0)
			used[i] = true


func _build_tree(i: int) -> void:
	var t: Dictionary = trees[i]
	var base: Vector3 = t.pos
	var r: float = t.radius
	var h: float = t.height
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = r * 0.88
	trunk_shape.height = h
	var cs := CollisionShape3D.new()
	cs.shape = trunk_shape
	cs.position = base + Vector3(0, h * 0.5, 0)
	_body_climb.add_child(cs)
	var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.03))
	_add_batch("trunk", Transform3D(lean * Basis().scaled(Vector3(r, h, r)), base + Vector3(0, h * 0.5, 0)), _bark_tint())
	# buttress roots: little ramps to scramble up
	var roots := rng.randi_range(3, 5)
	for k in roots:
		var a := TAU * k / roots + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var len := r * rng.randf_range(1.6, 2.4)
		var root_top := base + Vector3(0, r * 1.8, 0) + dir * r * 0.6
		var root_end := base + dir * (r + len) + Vector3(0, 0.3, 0)
		_beam(root_top, root_end, r * 0.32, "root", true)
	# branches
	var count := rng.randi_range(3, 6)
	for k in count:
		var y := h * rng.randf_range(0.32, 0.88)
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), rng.randf_range(0.05, 0.22), sin(a)).normalized()
		var blen := rng.randf_range(5.0, 11.0)
		var br := rng.randf_range(0.38, 0.62)
		var start := base + Vector3(0, y, 0) + Vector3(dir.x, 0, dir.z) * r * 0.5
		var end := start + dir * blen
		_beam(start, end, br, "branch", true)
		t.branches.append({"start": start, "end": end, "radius": br})
		# leaf clump at the end of each branch
		var cr := rng.randf_range(2.2, 3.8)
		_canopy(end + Vector3(0, cr * 0.4, 0), cr)
		# vines hanging from the branch
		if rng.randf() < 0.6:
			var vt := rng.randf_range(0.65, 0.95)
			var ap := start.lerp(end, vt) + Vector3(0, -br * 0.8, 0)
			var gh := ground_height(ap.x, ap.z)
			var vlen := clampf(rng.randf_range(7.0, 16.0), 4.0, ap.y - gh - 1.6)
			if vlen >= 4.0:
				_vine(ap, vlen)
	# crown
	var crown := base + Vector3(0, h, 0)
	var crown_r := r * 2.4 + rng.randf_range(3.0, 5.0)
	_canopy(crown, crown_r)
	for k in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), rng.randf_range(-0.4, 0.2), sin(a)) * crown_r * rng.randf_range(0.7, 1.1)
		_canopy(crown + off, crown_r * rng.randf_range(0.55, 0.8))
	# vines from the crown edge
	for k in rng.randi_range(0, 2):
		var a := rng.randf() * TAU
		var ap := crown + Vector3(cos(a), -0.5, sin(a)) * crown_r * 0.8
		ap.y -= crown_r * 0.4
		var gh := ground_height(ap.x, ap.z)
		var vlen := clampf(rng.randf_range(10.0, 18.0), 4.0, ap.y - gh - 2.0)
		if vlen >= 4.0:
			_vine(ap, vlen)
	hide_spots.append({"pos": crown + Vector3(0, -crown_r * 0.4, 0), "radius": crown_r * 0.6, "kind": "canopy"})
	# platform ring / treehouse
	if t.platform > 0.0:
		if i in _treehouse_ids:
			_treehouse(t)
		else:
			_ring_platform(t, 5.2 + r * 2.0)


func _ring_platform(t: Dictionary, size: float) -> void:
	var c := Vector3(t.pos.x, t.platform, t.pos.z)
	_wood_box(c, Vector3(size, 0.35, size), true)
	# railing posts on the corners
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_wood_box(c + Vector3(sx * size * 0.45, 0.6, sz * size * 0.45), Vector3(0.2, 1.0, 0.2), false)
	platforms.append({"pos": c + Vector3(0, 0.2, 0), "size": size})
	# a ladder from the ground on one platform in three
	if rng.randf() < 0.4:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var lp := c + dir * (size * 0.5 + 0.15)
		var gh := ground_height(lp.x, lp.z)
		_ladder(Vector3(lp.x, gh, lp.z), t.platform - gh + 0.2, dir)


func _treehouse(t: Dictionary) -> void:
	var c := Vector3(t.pos.x, t.platform, t.pos.z)
	var s := 9.0
	_wood_box(c, Vector3(s, 0.4, s), true)
	var wall_h := 2.8
	var door_side := rng.randi_range(0, 3)
	for side in 4:
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, side * PI * 0.5)
		var across := dir.cross(Vector3.UP)
		var wc := c + dir * (s * 0.5 - 0.15) + Vector3(0, wall_h * 0.5 + 0.2, 0)
		var size_along := Vector3(absf(across.x) * s + 0.3, wall_h, absf(across.z) * s + 0.3)
		if side == door_side:
			# two wall halves leaving a doorway
			for half in [-1.0, 1.0]:
				var hc: Vector3 = wc + across * half * (s * 0.5 - 1.6)
				var hs := Vector3(maxf(absf(across.x) * 3.2, 0.3), wall_h, maxf(absf(across.z) * 3.2, 0.3))
				_wood_box(hc, hs, true)
		else:
			# low wall with a window gap above
			var low := size_along
			low.y = 1.1
			_wood_box(wc + Vector3(0, -wall_h * 0.5 + 0.55, 0), low, true)
			var top := size_along
			top.y = 0.6
			_wood_box(wc + Vector3(0, wall_h * 0.5 - 0.3, 0), top, true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_wood_box(c + Vector3(sx * (s * 0.5 - 0.15), wall_h * 0.5 + 0.2, sz * (s * 0.5 - 0.15)), Vector3(0.35, wall_h, 0.35), true)
	# roof: a flat collision slab you can land on and a prism on top
	_add_box_shape(_body_climb, Transform3D(Basis(), c + Vector3(0, wall_h + 0.45, 0)), Vector3(s + 1.0, 0.3, s + 1.0))
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(s + 1.6, 3.0, s + 1.6)
	roof.mesh = pm
	roof.material_override = _mats.thatch
	roof.position = c + Vector3(0, wall_h + 1.9, 0)
	add_child(roof)
	_add_box_shape(_body_solid, Transform3D(Basis(), c + Vector3(0, wall_h + 1.9, 0)), Vector3(s * 0.55, 2.4, s * 0.55))
	var door_dir := Vector3(1, 0, 0).rotated(Vector3.UP, door_side * PI * 0.5)
	var lp := c + door_dir * (s * 0.5 + 0.15)
	var gh := ground_height(lp.x, lp.z)
	_ladder(Vector3(lp.x, gh, lp.z), t.platform - gh + 0.2, door_dir)
	hide_spots.append({"pos": c + Vector3(0, 0.6, 0), "radius": 3.5, "kind": "treehouse"})
	platforms.append({"pos": c + Vector3(0, 0.2, 0), "size": s})


func _build_bridges() -> void:
	# rope bridges between tree platforms
	for pair in _bridge_pairs:
		var a: Dictionary = trees[pair[0]]
		var b: Dictionary = trees[pair[1]]
		var pa := Vector3(a.pos.x, a.platform, a.pos.z)
		var pb := Vector3(b.pos.x, b.platform, b.pos.z)
		var dir := (pb - pa).normalized()
		var sa: float = (5.2 + a.radius * 2.0) * 0.5
		var sb: float = (5.2 + b.radius * 2.0) * 0.5
		_plank_bridge(pa + dir * (sa - 0.3), pb - dir * (sb - 0.3), 1.8, true)
	# beams between close trees
	for pair in _beam_pairs:
		var a: Dictionary = trees[pair[0]]
		var b: Dictionary = trees[pair[1]]
		var h: float = minf(a.height, b.height) * pair[2]
		var pa: Vector3 = a.pos + Vector3(0, h, 0)
		var pb: Vector3 = b.pos + Vector3(0, h + rng.randf_range(-2.0, 2.0), 0)
		_beam(pa, pb, rng.randf_range(0.55, 0.8), "branch", true)
		var mid := pa.lerp(pb, 0.5)
		var gh := ground_height(mid.x, mid.z)
		if mid.y - gh > 7.0:
			_vine(mid + Vector3(0, -0.6, 0), clampf(mid.y - gh - 2.5, 4.0, 15.0))
	# wooden bridges across the river
	for z in [-60.0, 5.0, 70.0, 125.0]:
		var cx := river_x(z)
		var left := Vector3(cx - 15.0, 0, z)
		var right := Vector3(cx + 15.0, 0, z)
		left.y = ground_height(left.x, left.z) + 0.25
		right.y = ground_height(right.x, right.z) + 0.25
		var deck_y := maxf(maxf(left.y, right.y), 1.4)
		_plank_bridge(Vector3(left.x, deck_y, z), Vector3(right.x, deck_y, z), 3.0, false)
		# ramps down to the banks if needed
		for end in [left, right]:
			if deck_y - end.y > 0.4:
				var outward := Vector3(-1, 0, 0) if end == left else Vector3(1, 0, 0)
				_plank_bridge(Vector3(end.x, deck_y, z), Vector3(end.x, end.y, z) + outward * 4.0, 3.0, false)


func _plank_bridge(a: Vector3, b: Vector3, width: float, rope: bool) -> void:
	var span := b - a
	var len := span.length()
	if len < 0.5:
		return
	var dir := span / len
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var side := Vector3.UP.cross(flat).normalized()
	var up_axis := dir.cross(side).normalized()
	var basis := Basis(side, up_axis, dir)
	_add_box_shape(_body_climb, Transform3D(basis, (a + b) * 0.5 - up_axis * 0.1), Vector3(width, 0.25, len))
	var n := int(len / 0.55)
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		_add_batch("plank", Transform3D(_sl(basis, Vector3(width, 0.12, 0.42)), p), _wood_tint())
	# side rails
	for s in [-1.0, 1.0]:
		var off: Vector3 = side * s * width * 0.5 + up_axis * 0.9
		if rope:
			_beam(a + off, b + off, 0.05, "rope", false)
			var posts := maxi(2, int(len / 3.0))
			for i in posts + 1:
				var p: Vector3 = a.lerp(b, float(i) / posts) + side * s * width * 0.5
				_add_batch("rope", Transform3D(Basis().scaled(Vector3(0.05, 0.9, 0.05)), p + up_axis * 0.45), Color.WHITE)
		else:
			_add_batch("plank", Transform3D(_sl(basis, Vector3(0.15, 0.15, len)), (a + b) * 0.5 + off), _wood_tint())
			var posts := maxi(2, int(len / 2.5))
			for i in posts + 1:
				var p: Vector3 = a.lerp(b, float(i) / posts) + side * s * width * 0.5
				_add_batch("plank", Transform3D(Basis().scaled(Vector3(0.15, 0.9, 0.15)), p + Vector3(0, 0.45, 0)), _wood_tint())
			_add_box_shape(_body_solid, Transform3D(basis, (a + b) * 0.5 + off - up_axis * 0.4), Vector3(0.15, 1.0, len))


func _build_stilt_platforms() -> void:
	var made := 0
	var tries := 0
	while made < 12 and tries < 400:
		tries += 1
		var x := rng.randf_range(-120.0, 120.0)
		var z := rng.randf_range(-95.0, 125.0)
		if is_river(x, z, 4.0) or Vector2(x, z).distance_to(CAVE_CENTER) < 32.0:
			continue
		var clear := true
		for t in trees:
			if Vector2(t.pos.x, t.pos.z).distance_to(Vector2(x, z)) < 7.0:
				clear = false
				break
		if not clear:
			continue
		var gh := ground_height(x, z)
		var h := rng.randf_range(3.5, 9.0)
		var size := rng.randf_range(4.5, 7.0)
		var top := Vector3(x, gh + h, z)
		_wood_box(top, Vector3(size, 0.35, size), true)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var pp := Vector3(x + sx * (size * 0.5 - 0.3), 0, z + sz * (size * 0.5 - 0.3))
				var pgh := ground_height(pp.x, pp.z)
				var post_h := top.y - pgh
				_wood_box(Vector3(pp.x, pgh + post_h * 0.5, pp.z), Vector3(0.35, post_h, 0.35), true)
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var lp := top + dir * (size * 0.5 + 0.15)
		_ladder(Vector3(lp.x, ground_height(lp.x, lp.z), lp.z), h + 0.2, dir)
		platforms.append({"pos": top + Vector3(0, 0.2, 0), "size": size})
		# leafy roof on some platforms
		if rng.randf() < 0.5:
			_canopy(top + Vector3(0, 3.5, 0), size * 0.55)
		made += 1


func _build_bushes() -> void:
	var count := 0
	var tries := 0
	while count < 520 and tries < 5000:
		tries += 1
		var x := rng.randf_range(-138.0, 138.0)
		var z := rng.randf_range(-146.0, 138.0)
		if is_river(x, z, -1.5):
			continue
		var pm := plateau_mask(x, z)
		if pm > 0.05 and pm < 0.95:
			continue
		var dc := Vector2(x, z).distance_to(CAVE_CENTER)
		if dc < 13.0 or _cave_roof_blocked(x, z, 3.0):
			continue
		# clusters of bushes look more natural
		var cluster := rng.randi_range(1, 4)
		for k in cluster:
			var px := x + rng.randf_range(-2.5, 2.5)
			var pz := z + rng.randf_range(-2.5, 2.5)
			var r := rng.randf_range(1.1, 2.3)
			_bush(Vector3(px, ground_height(px, pz) + r * 0.45, pz), r)
			count += 1


func _bush(p: Vector3, r: float) -> void:
	_add_batch("bush", Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * 0.8, r)), p), _leaf_tint(0.8))
	hide_spots.append({"pos": p, "radius": r, "kind": "bush"})
	_add_foliage_sphere(p, r * 1.05)
	# a big leaf or two poking out
	if rng.randf() < 0.5:
		_add_batch("bigleaf", Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * r * 0.9), p + Vector3(0, -r * 0.35, 0)), Color.WHITE)


func _build_rock_outcrops() -> void:
	for i in 34:
		var x := rng.randf_range(-130.0, 130.0)
		var z := rng.randf_range(-100.0, 130.0)
		if Vector2(x, z).distance_to(CAVE_CENTER) < 30.0:
			continue
		var in_river := is_river(x, z, 0.0)
		var gh := ground_height(x, z)
		var s := rng.randf_range(1.2, 3.5) if not in_river else rng.randf_range(0.9, 1.6)
		_boulder(Vector3(x, gh + s * 0.3, z), Vector3(s * rng.randf_range(1.0, 1.6), s, s))
		if not in_river and rng.randf() < 0.5:
			var s2 := s * 0.6
			_boulder(Vector3(x + s, gh + s2 * 0.3, z + rng.randf_range(-1, 1)), Vector3(s2, s2, s2))
	# stepping stones across the river
	for z in [-30.0, 40.0, 100.0]:
		var cx := river_x(z)
		var x := cx - 9.0
		while x < cx + 9.0:
			_boulder(Vector3(x, -1.8, z + rng.randf_range(-0.6, 0.6)), Vector3(1.1, 2.0, 1.1))
			x += rng.randf_range(2.2, 2.8)


func _build_ground_cover(veg: RandomNumberGenerator, density: float) -> void:
	var counts := {"grass": int(5500 * density), "fern": int(1700 * density), "bigleaf": int(450 * density), "flower": int(900 * density)}
	for kind in counts:
		var placed := 0
		var tries := 0
		while placed < counts[kind] and tries < counts[kind] * 3:
			tries += 1
			var x := veg.randf_range(-140.0, 140.0)
			var z := veg.randf_range(-146.0, 140.0)
			var h := ground_height(x, z)
			if h < WATER_Y + 0.2:
				continue
			var pm := plateau_mask(x, z)
			if pm > 0.05 and pm < 0.95:
				continue
			if Vector2(x, z).distance_to(CAVE_CENTER) < 12.5 or _cave_roof_blocked(x, z, 0.5):
				continue
			var s := veg.randf_range(0.7, 1.4)
			var b := Basis().rotated(Vector3.UP, veg.randf() * TAU).scaled(Vector3.ONE * s)
			var col := Color.WHITE
			if kind == "flower":
				col = [Color("ff4f7b"), Color("ffd23f"), Color("ff8a3d"), Color("c86bff"), Color("ffffff")][veg.randi_range(0, 4)]
				b = Basis().scaled(Vector3.ONE * veg.randf_range(0.7, 1.3))
			_add_batch(kind, Transform3D(b, Vector3(x, h - 0.05, z)), col)
			placed += 1


func _fern_at(p: Vector3, s: float) -> void:
	_add_batch("fern", Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p), Color.WHITE)


func _build_bounds() -> void:
	for side in 4:
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, side * PI * 0.5)
		var size := Vector3(absf(dir.z) * 320 + 2, 220, absf(dir.x) * 320 + 2)
		_add_box_shape(_body_solid, Transform3D(Basis(), dir * (HALF - 4.0) + Vector3(0, 90, 0)), size)


func _pick_spawns() -> void:
	var tries := 0
	while spawn_points.size() < 24 and tries < 2000:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(10.0, 70.0)
		var x := cos(a) * r + 10.0
		var z := sin(a) * r + 10.0
		if is_river(x, z, 3.0) or plateau_mask(x, z) > 0.0:
			continue
		var p := Vector3(x, ground_height(x, z) + 1.2, z)
		var ok := true
		for t in trees:
			if Vector2(t.pos.x, t.pos.z).distance_to(Vector2(x, z)) < t.radius + 3.0:
				ok = false
				break
		for s in spawn_points:
			if s.distance_to(p) < 6.0:
				ok = false
		if ok:
			spawn_points.append(p)
	if spawn_points.is_empty():
		spawn_points.append(Vector3(0, ground_height(0, 0) + 2.0, 0))


func _build_ambient_audio() -> void:
	var z := RIVER_START_Z + 10.0
	while z < HALF:
		Sfx.make_loop_emitter("amb_river", self, Vector3(river_x(z), WATER_Y + 0.5, z), -4.0, 38.0)
		z += 32.0
	Sfx.make_loop_emitter("amb_waterfall", self, Vector3(plateau_x, 2.0, -105.0), 4.0, 95.0)
	Sfx.make_loop_emitter("amb_waterfall", self, Vector3(plateau_x, 18.0, -108.0), -2.0, 70.0)


# ======================================================================== building blocks
func _beam(a: Vector3, b: Vector3, radius: float, kind: String, collide: bool) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.05:
		return
	var basis := _basis_from_y(d / len)
	var mid := (a + b) * 0.5
	var col := Color.WHITE if kind == "rope" else _bark_tint()
	_add_batch(kind, Transform3D(_sl(basis, Vector3(radius, len, radius)), mid), col)
	if collide:
		_add_box_shape(_body_climb, Transform3D(basis, mid), Vector3(radius * 2.0, len, radius * 1.8))


func _canopy(p: Vector3, r: float) -> void:
	_add_batch("canopy", Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * rng.randf_range(0.6, 0.85), r)), p), _leaf_tint(1.0))
	_add_foliage_sphere(p, r * 0.9)


func _vine(anchor: Vector3, length: float) -> void:
	var v := Vine.new()
	v.name = "Vine%d" % vines.size()
	add_child(v)
	v.position = anchor
	v.setup(vines.size(), length, _vine_mesh, _vine_mat, rng.randf() * TAU)
	vines.append(v)
	# small knot of leaves where it hangs from
	_add_batch("bush", Transform3D(Basis().scaled(Vector3.ONE * 0.6), anchor + Vector3(0, 0.2, 0)), _leaf_tint(0.9))


func _wood_box(c: Vector3, size: Vector3, collide: bool) -> void:
	_add_batch("plank", Transform3D(Basis().scaled(size), c), _wood_tint())
	if collide:
		_add_box_shape(_body_climb, Transform3D(Basis(), c), size)


func _rock_box(c: Vector3, size: Vector3, yaw: float) -> void:
	var b := Basis().rotated(Vector3.UP, yaw)
	_add_batch("rockbox", Transform3D(_sl(b, size), c), _rock_tint())
	_add_box_shape(_body_climb, Transform3D(b, c), size)


func _boulder(c: Vector3, size: Vector3) -> void:
	var b := Basis().rotated(Vector3.UP, rng.randf() * TAU)
	_add_batch("boulder", Transform3D(_sl(b, size), c), _rock_tint())
	var shape := SphereShape3D.new()
	shape.radius = minf(size.x, minf(size.y, size.z)) * 0.95
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = c
	_body_climb.add_child(cs)
	if size.y > size.x * 1.2:
		# tall rocks: stack a second sphere to cover the height
		var cs2 := CollisionShape3D.new()
		cs2.shape = shape
		cs2.position = c + Vector3(0, size.y - shape.radius, 0)
		_body_climb.add_child(cs2)


func _ladder(base: Vector3, height: float, out_dir: Vector3) -> void:
	var side := Vector3.UP.cross(out_dir).normalized()
	var c := base + Vector3(0, height * 0.5, 0)
	var b := Basis(side, Vector3.UP, out_dir.normalized())
	_add_box_shape(_body_climb, Transform3D(b, c), Vector3(1.0, height, 0.25))
	for s in [-0.45, 0.45]:
		_add_batch("plank", Transform3D(_sl(b, Vector3(0.12, height, 0.12)), c + side * s), _wood_tint())
	var rungs := int(height / 0.45)
	for i in rungs:
		_add_batch("plank", Transform3D(_sl(b, Vector3(0.9, 0.08, 0.1)), base + Vector3(0, 0.3 + i * 0.45, 0)), _wood_tint())


func _add_box_shape(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


func _add_foliage_sphere(p: Vector3, r: float) -> void:
	var cell := Vector2i(floori(p.x / 10.0), floori(p.z / 10.0))
	var reach := ceili(r / 10.0)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var k := cell + Vector2i(dx, dz)
			if not foliage_grid.has(k):
				foliage_grid[k] = []
			foliage_grid[k].append([p, r])


## How deeply a point is buried in leaves (0 = open, 1 = deep inside a bush or canopy).
func foliage_cover(p: Vector3) -> float:
	var k := Vector2i(floori(p.x / 10.0), floori(p.z / 10.0))
	if not foliage_grid.has(k):
		return 0.0
	var best := 0.0
	for entry in foliage_grid[k]:
		var c: Vector3 = entry[0]
		var r: float = entry[1]
		var d := (p - c).length()
		if d < r:
			best = maxf(best, 1.0 - d / r * 0.6)
	return clampf(best, 0.0, 1.0)


func _sl(b: Basis, s: Vector3) -> Basis:
	return b * Basis.from_scale(s)


func _basis_from_y(y: Vector3) -> Basis:
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _bark_tint() -> Color:
	var v := rng.randf_range(0.8, 1.15)
	return Color(v, v * rng.randf_range(0.92, 1.0), v * rng.randf_range(0.85, 1.0))


func _wood_tint() -> Color:
	var v := rng.randf_range(0.8, 1.2)
	return Color(v, v, v)


func _rock_tint() -> Color:
	var v := rng.randf_range(0.85, 1.15)
	return Color(v, v, v * rng.randf_range(0.95, 1.05))


func _leaf_tint(base: float) -> Color:
	var h := rng.randf_range(-0.06, 0.06)
	return Color(base * (1.0 + h), base * rng.randf_range(0.9, 1.1), base * (1.0 - h))


# ======================================================================== batching
func _add_batch(kind: String, xf: Transform3D, col: Color) -> void:
	var key := kind
	if kind in ["grass", "fern", "bigleaf", "flower", "bush"]:
		key = "%s_%d_%d" % [kind, floori((xf.origin.x + HALF) / 50.0), floori((xf.origin.z + HALF) / 50.0)]
	if not _batches.has(key):
		_batches[key] = {"kind": kind, "xf": [], "col": []}
	_batches[key].xf.append(xf)
	_batches[key].col.append(col)


func _flush_batches() -> void:
	var vis_ranges := {"grass": 55.0, "flower": 60.0, "fern": 110.0, "bigleaf": 120.0, "bush": Settings.view_distance}
	for key in _batches:
		var b: Dictionary = _batches[key]
		var kind: String = b.kind
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _meshes[kind]
		mm.instance_count = b.xf.size()
		for i in b.xf.size():
			mm.set_instance_transform(i, b.xf[i])
			mm.set_instance_color(i, b.col[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + key
		mmi.multimesh = mm
		mmi.material_override = _mats[_material_for(kind)]
		if kind in ["grass", "flower", "fern", "mushroom", "rope"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_ranges.has(kind):
			mmi.visibility_range_end = vis_ranges[kind]
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(mmi)
	_batches.clear()


func _material_for(kind: String) -> String:
	match kind:
		"trunk", "branch", "root": return "bark"
		"plank": return "planks"
		"canopy": return "canopy"
		"bush": return "bush"
		"rockbox", "boulder": return "rock"
		"grass": return "grass"
		"fern": return "fern"
		"bigleaf": return "bigleaf"
		"flower": return "flower"
		"mushroom": return "mushroom"
		"rope": return "rope"
	return "planks"


func _make_materials() -> void:
	var wood: Shader = load("res://shaders/wood.gdshader")
	var bark := ShaderMaterial.new()
	bark.shader = wood
	bark.set_shader_parameter("wood_color", Color(0.42, 0.29, 0.18))
	_mats.bark = bark
	var bark_dark := ShaderMaterial.new()
	bark_dark.shader = wood
	bark_dark.set_shader_parameter("wood_color", Color(0.33, 0.22, 0.14))
	bark_dark.set_shader_parameter("moss_amount", 0.6)
	_mats.bark_dark = bark_dark
	var planks := ShaderMaterial.new()
	planks.shader = wood
	planks.set_shader_parameter("wood_color", Color(0.62, 0.43, 0.25))
	planks.set_shader_parameter("planks", 1.0)
	_mats.planks = planks
	var canopy_sh: Shader = load("res://shaders/canopy.gdshader")
	var canopy := ShaderMaterial.new()
	canopy.shader = canopy_sh
	_mats.canopy = canopy
	var bush := ShaderMaterial.new()
	bush.shader = canopy_sh
	bush.set_shader_parameter("leaf_a", Color(0.12, 0.38, 0.10))
	bush.set_shader_parameter("leaf_b", Color(0.30, 0.58, 0.14))
	bush.set_shader_parameter("sway", 0.08)
	_mats.bush = bush
	var rock := ShaderMaterial.new()
	rock.shader = load("res://shaders/rock.gdshader")
	_mats.rock = rock
	var terrain := ShaderMaterial.new()
	terrain.shader = load("res://shaders/terrain.gdshader")
	_mats.terrain = terrain
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/water.gdshader")
	_mats.water = water
	var leaf_sh: Shader = load("res://shaders/leaf_card.gdshader")
	var grass := ShaderMaterial.new()
	grass.shader = leaf_sh
	grass.set_shader_parameter("shape", 1)
	grass.set_shader_parameter("leaf_a", Color(0.18, 0.42, 0.10))
	grass.set_shader_parameter("leaf_b", Color(0.45, 0.70, 0.18))
	grass.set_shader_parameter("sway", 0.08)
	_mats.grass = grass
	var fern := ShaderMaterial.new()
	fern.shader = leaf_sh
	fern.set_shader_parameter("shape", 2)
	_mats.fern = fern
	var bigleaf := ShaderMaterial.new()
	bigleaf.shader = leaf_sh
	bigleaf.set_shader_parameter("shape", 0)
	bigleaf.set_shader_parameter("leaf_a", Color(0.10, 0.36, 0.12))
	bigleaf.set_shader_parameter("leaf_b", Color(0.30, 0.62, 0.20))
	bigleaf.set_shader_parameter("sway", 0.1)
	_mats.bigleaf = bigleaf
	var flower := StandardMaterial3D.new()
	flower.vertex_color_use_as_albedo = true
	flower.emission_enabled = true
	flower.emission = Color(0.15, 0.1, 0.1)
	flower.roughness = 0.6
	_mats.flower = flower
	var mush := StandardMaterial3D.new()
	mush.vertex_color_use_as_albedo = true
	mush.emission_enabled = true
	mush.emission = Color(0.3, 0.9, 1.0)
	mush.emission_energy_multiplier = 2.5
	_mats.mushroom = mush
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.72, 0.6, 0.38)
	rope.roughness = 1.0
	_mats.rope = rope
	var thatch_std := StandardMaterial3D.new()
	thatch_std.albedo_color = Color(0.62, 0.48, 0.24)
	thatch_std.roughness = 1.0
	_mats.thatch = thatch_std
	_vine_mat = ShaderMaterial.new()
	_vine_mat.shader = load("res://shaders/vine.gdshader")

	# meshes
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.72
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 14
	trunk.rings = 4
	_meshes.trunk = trunk
	var branch := CylinderMesh.new()
	branch.top_radius = 0.55
	branch.bottom_radius = 1.0
	branch.height = 1.0
	branch.radial_segments = 9
	branch.rings = 1
	_meshes.branch = branch
	var root := CylinderMesh.new()
	root.top_radius = 1.0
	root.bottom_radius = 0.5
	root.height = 1.0
	root.radial_segments = 8
	root.rings = 1
	_meshes.root = root
	var rope_mesh := CylinderMesh.new()
	rope_mesh.top_radius = 1.0
	rope_mesh.bottom_radius = 1.0
	rope_mesh.height = 1.0
	rope_mesh.radial_segments = 5
	rope_mesh.rings = 1
	_meshes.rope = rope_mesh
	var blob := SphereMesh.new()
	blob.radius = 1.0
	blob.height = 2.0
	blob.radial_segments = 16
	blob.rings = 9
	_meshes.canopy = blob
	var bush_mesh := SphereMesh.new()
	bush_mesh.radius = 1.0
	bush_mesh.height = 2.0
	bush_mesh.radial_segments = 12
	bush_mesh.rings = 7
	_meshes.bush = bush_mesh
	var box := BoxMesh.new()
	_meshes.plank = box
	_meshes.rockbox = box
	var boulder := SphereMesh.new()
	boulder.radius = 1.0
	boulder.height = 2.0
	boulder.radial_segments = 9
	boulder.rings = 6
	_meshes.boulder = boulder
	var flower_mesh := SphereMesh.new()
	flower_mesh.radius = 0.13
	flower_mesh.height = 0.2
	flower_mesh.radial_segments = 6
	flower_mesh.rings = 3
	_meshes.flower = _offset_mesh(flower_mesh, Vector3(0, 0.35, 0))
	var mush_mesh := SphereMesh.new()
	mush_mesh.radius = 1.0
	mush_mesh.height = 1.0
	mush_mesh.is_hemisphere = true
	mush_mesh.radial_segments = 10
	mush_mesh.rings = 4
	_meshes.mushroom = mush_mesh
	_meshes.grass = _card_cluster(3, Vector2(0.9, 0.55), 0.0, 0.0)
	_meshes.fern = _card_cluster(7, Vector2(0.45, 1.3), deg_to_rad(55.0), 0.05)
	_meshes.bigleaf = _card_cluster(3, Vector2(1.1, 1.7), deg_to_rad(38.0), 0.4)
	_vine_mesh = _make_vine_mesh()


func _offset_mesh(m: PrimitiveMesh, offset: Vector3) -> ArrayMesh:
	var arrays := m.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += offset
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


## Quads radiating from the origin. tilt = 0 gives upright crossed cards (grass).
func _card_cluster(count: int, size: Vector2, tilt: float, stem: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var yaw := TAU * i / count
		var b := Basis().rotated(Vector3.UP, yaw)
		var up := Vector3.UP
		var right := Vector3.RIGHT
		var base := Vector3(0, stem, 0)
		var w := size.x * 0.5
		var corners: Array
		if tilt > 0.0:
			# leaf lies outward from the centre
			var dir := Vector3(0, cos(tilt), sin(tilt))
			corners = [base - right * w, base + right * w, base + right * w + dir * size.y, base - right * w + dir * size.y]
		else:
			corners = [base - right * w, base + right * w, base + right * w + up * size.y, base - right * w + up * size.y]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var c0: Vector3 = corners[0]
		var n: Vector3 = (b * (corners[1] - c0).cross(corners[3] - c0)).normalized()
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP.lerp(n, 0.4).normalized())
			st.set_uv(uvs[idx])
			st.add_vertex(b * corners[idx])
	return st.commit()


func _make_vine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var rings := 32
	var radius := 0.06
	for r in rings:
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var y0 := -float(r) / rings
			var y1 := -float(r + 1) / rings
			var v00 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
			var v01 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
			var v10 := Vector3(cos(a0) * radius, y1, sin(a0) * radius)
			var v11 := Vector3(cos(a1) * radius, y1, sin(a1) * radius)
			for v in [[v00, a0, y0], [v10, a0, y1], [v11, a1, y1], [v00, a0, y0], [v11, a1, y1], [v01, a1, y0]]:
				st.set_normal(Vector3(cos(v[1]), 0, sin(v[1])))
				st.set_uv(Vector2(float(s) / sides, -v[2]))
				st.add_vertex(v[0])
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 27, 50))
	return m


## A nice camera spot looking at the waterfall (used by the screenshot tool).
func waterfall_view_pos() -> Vector3:
	return Vector3(plateau_x + 16.0, 6.0, RIVER_START_Z + 22.0)
