extends RefCounted
## Procedural terrain: height field, splat (material) map and the ground mesh.
## World units (1 = 10 game px). Playable area is 0..size; beyond it rise border mountains.
## Hills are flat-topped plateaus with steep rocky cliffs; lakes are bowls filled with water.

const STEP := 2.0       # grid resolution in world units
const MARGIN := 70.0    # terrain drawn beyond the playable area

var size: Vector2
var hills: Array        # {c: Vector2, r: float, h: float}
var lakes: Array        # {c: Vector2, r: float, depth: float}
var flats: Array        # {c: Vector2, r: float}  (bases / expansions stay flat)
var origin: Vector2     # world position of grid cell (0, 0)
var cols := 0
var rows := 0
var heights := PackedFloat32Array()

var _gentle := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _edge := FastNoiseLite.new()
var _grass := FastNoiseLite.new()


func _init(size_world: Vector2, hills_: Array, lakes_: Array, flats_: Array) -> void:
	size = size_world
	hills = hills_
	lakes = lakes_
	flats = flats_
	_gentle.seed = 11
	_gentle.frequency = 0.014
	_detail.seed = 12
	_detail.frequency = 0.09
	_edge.seed = 13
	_edge.frequency = 0.05
	_grass.seed = 14
	_grass.frequency = 0.012
	_grass.fractal_octaves = 4
	origin = -Vector2(MARGIN, MARGIN)
	cols = int((size.x + 2.0 * MARGIN) / STEP) + 1
	rows = int((size.y + 2.0 * MARGIN) / STEP) + 1
	heights.resize(cols * rows)
	for j in rows:
		for i in cols:
			heights[j * cols + i] = _height_raw(origin.x + i * STEP, origin.y + j * STEP)


func _height_raw(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _gentle.get_noise_2d(x, z) * 0.7 + _detail.get_noise_2d(x, z) * 0.12
	for f in flats:
		h *= smoothstep(f.r * 0.6, f.r, p.distance_to(f.c))
	for hl in hills:
		var d := p.distance_to(hl.c)
		if d > hl.r * 1.3:
			continue
		var a: float = (p - hl.c).angle()
		var rr: float = hl.r * (1.0 + 0.14 * _edge.get_noise_2d(cos(a) * 30.0 + hl.c.x, sin(a) * 30.0 + hl.c.y))
		var cliff := 1.0 - smoothstep(rr * 0.8, rr, d)
		var dome := 1.0 - smoothstep(0.0, rr * 0.8, d)
		h += hl.h * cliff + dome * 0.9 + cliff * _detail.get_noise_2d(x * 2.0, z * 2.0) * 0.5
	for lk in lakes:
		var d := p.distance_to(lk.c)
		if d > lk.r * 1.3:
			continue
		var a: float = (p - lk.c).angle()
		var rr: float = lk.r * (1.0 + 0.1 * _edge.get_noise_2d(cos(a) * 25.0 - lk.c.x, sin(a) * 25.0))
		h -= lk.depth * (1.0 - smoothstep(rr * 0.45, rr * 1.05, d))
	var outside := maxf(maxf(-x, x - size.x), maxf(-z, z - size.y))
	if outside > -4.0:  # border mountains: steep rocky wall, then ridges
		var ridge := 1.0 + 0.6 * _edge.get_noise_2d(x * 1.3, z * 1.3) + 0.3 * _detail.get_noise_2d(x * 0.5, z * 0.5)
		h += smoothstep(-4.0, 12.0, outside) * 11.0 * ridge + maxf(0.0, outside - 12.0) * 0.35 * ridge
	return h


## Bilinear height lookup (world units).
func height(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / STEP, 0.0, cols - 1.001)
	var fz := clampf((z - origin.y) / STEP, 0.0, rows - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * cols + i]
	var h10 := heights[j * cols + i + 1]
	var h01 := heights[(j + 1) * cols + i]
	var h11 := heights[(j + 1) * cols + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal(x: float, z: float) -> Vector3:
	var e := STEP
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


## Weight of each ground layer at a world point: grass, rock, sand (dirt is the remainder).
func layers(x: float, z: float) -> Color:
	var h := height(x, z)
	var slope := 1.0 - normal(x, z).y
	var rock := smoothstep(0.12, 0.3, slope)
	var g := smoothstep(0.1, 0.35, _grass.get_noise_2d(x, z) + _detail.get_noise_2d(x, z) * 0.15)
	g = maxf(g, smoothstep(2.0, 3.5, h) * (1.0 - rock))  # grassy plateau tops
	var sand := 0.0
	for lk in lakes:
		var d := Vector2(x, z).distance_to(lk.c)
		sand = maxf(sand, 1.0 - smoothstep(lk.r * 0.95, lk.r * 1.35, d))
	sand *= 1.0 - rock
	g *= (1.0 - rock) * (1.0 - sand)
	return Color(g, rock, sand, 1.0)


func splat_texture() -> ImageTexture:
	var img := Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	for j in rows:
		for i in cols:
			img.set_pixel(i, j, layers(origin.x + i * STEP, origin.y + j * STEP))
	return ImageTexture.create_from_image(img)


func build_mesh() -> ArrayMesh:
	var n := cols * rows
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	verts.resize(n)
	norms.resize(n)
	uvs.resize(n)
	tangents.resize(n * 4)
	for j in rows:
		for i in cols:
			var k := j * cols + i
			var x := origin.x + i * STEP
			var z := origin.y + j * STEP
			verts[k] = Vector3(x, heights[k], z)
			var hl := heights[k - 1] if i > 0 else heights[k]
			var hr := heights[k + 1] if i < cols - 1 else heights[k]
			var hu := heights[k - cols] if j > 0 else heights[k]
			var hd := heights[k + cols] if j < rows - 1 else heights[k]
			norms[k] = Vector3(hl - hr, 2.0 * STEP, hu - hd).normalized()
			uvs[k] = Vector2(float(i) / (cols - 1), float(j) / (rows - 1))
			tangents[k * 4] = 1.0
			tangents[k * 4 + 3] = 1.0
	var idx := PackedInt32Array()
	idx.resize((cols - 1) * (rows - 1) * 6)
	var w := 0
	for j in rows - 1:
		for i in cols - 1:
			var a := j * cols + i
			var b := a + 1
			var c := a + cols
			var d := c + 1
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
			idx[w + 3] = b; idx[w + 4] = d; idx[w + 5] = c
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
