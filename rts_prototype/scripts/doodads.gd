extends RefCounted
## Procedural decoration meshes: palm trees, bushes, grass tufts, crates and barrels.
## Vegetation stores its colour in vertex colours; alpha is the wind-sway weight (foliage.gdshader).


static func _col(c: Color, sway: float) -> Color:
	return Color(c.r, c.g, c.b, sway)


## Palm tree ~ 6-8 world units tall: curved ringed trunk, drooping folded fronds, coconuts.
static func palm(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var height := rng.randf_range(5.5, 8.0)
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.8, 2.0)
	var mesh := ArrayMesh.new()
	# trunk
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 10
	var sides := 7
	var rings := []
	for s in segs + 1:
		var t := float(s) / segs
		var c := lean * t * t + Vector3(0, height * t, 0)
		var r := lerpf(0.34, 0.2, t) * (1.08 if s % 2 == 0 else 0.94)
		rings.append({"c": c, "r": r})
	for s in segs:
		var a0: Dictionary = rings[s]
		var a1: Dictionary = rings[s + 1]
		var shade := 0.8 if s % 2 == 0 else 1.0
		var col := _col(Color(0.55, 0.42, 0.28) * shade, 0.0)
		for k in sides:
			var t0 := k * TAU / sides
			var t1 := (k + 1) * TAU / sides
			var p00: Vector3 = a0.c + Vector3(cos(t0), 0, sin(t0)) * a0.r
			var p01: Vector3 = a0.c + Vector3(cos(t1), 0, sin(t1)) * a0.r
			var p10: Vector3 = a1.c + Vector3(cos(t0), 0, sin(t0)) * a1.r
			var p11: Vector3 = a1.c + Vector3(cos(t1), 0, sin(t1)) * a1.r
			for v in [p00, p10, p01, p01, p10, p11]:
				st.set_color(col)
				st.add_vertex(v)
	st.generate_normals()
	st.commit(mesh)
	# fronds
	var top: Vector3 = rings[segs].c
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := rng.randi_range(8, 10)
	for f in fronds:
		var ang := f * TAU / fronds + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(3.2, 4.4)
		var lift := rng.randf_range(0.5, 0.9)
		var green := Color(0.28, 0.5, 0.18).lerp(Color(0.45, 0.58, 0.2), rng.randf())
		var pts := 7
		var spine := []
		for i in pts:
			var t := float(i) / (pts - 1)
			spine.append(top + dir * length * t + Vector3(0, lift * t * 2.0 - 1.9 * t * t, 0))
		for i in pts - 1:
			var t0 := float(i) / (pts - 1)
			var t1 := float(i + 1) / (pts - 1)
			var w0 := sin(PI * clampf(t0 * 1.1, 0.0, 1.0)) * 0.6 + 0.05
			var w1 := sin(PI * clampf(t1 * 1.1, 0.0, 1.0)) * 0.6 + 0.05
			var s0: Vector3 = spine[i]
			var s1: Vector3 = spine[i + 1]
			var fold := Vector3(0, -0.22, 0)
			var c0 := _col(green.darkened(0.25 * (1.0 - t0)), t0)
			var c1 := _col(green.lightened(0.15 * t1), t1)
			for sgn in [-1.0, 1.0]:
				var e0: Vector3 = s0 + side * w0 * sgn + fold * w0
				var e1: Vector3 = s1 + side * w1 * sgn + fold * w1
				for pair in [[s0, c0], [e0, c0], [s1, c1], [s1, c1], [e0, c0], [e1, c1]]:
					st.set_color(pair[1])
					st.add_vertex(pair[0])
	# coconuts
	var nut := SphereMesh.new()
	nut.radius = 0.18
	nut.height = 0.36
	nut.radial_segments = 8
	nut.rings = 4
	var nut_arrays := nut.get_mesh_arrays()
	var nut_v: PackedVector3Array = nut_arrays[Mesh.ARRAY_VERTEX]
	var nut_i: PackedInt32Array = nut_arrays[Mesh.ARRAY_INDEX]
	for k in 3:
		var off := top + Vector3(cos(k * 2.1), -0.35, sin(k * 2.1)) * 0.3 + Vector3(0, -0.1 * k, 0)
		for ii in nut_i:
			st.set_color(_col(Color(0.36, 0.26, 0.14), 0.15))
			st.add_vertex(nut_v[ii] + off)
	st.generate_normals()
	st.commit(mesh)
	return mesh


## Leafy bush: a few noisy blobs.
static func bush(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.25, 0.42, 0.16).lerp(Color(0.4, 0.45, 0.18), rng.randf())
	for b in rng.randi_range(3, 5):
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		var arr := sphere.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var r := rng.randf_range(0.45, 0.8)
		var off := Vector3(rng.randf_range(-0.6, 0.6), r * 0.6, rng.randf_range(-0.6, 0.6))
		for ii in ix:
			var p: Vector3 = v[ii]
			var q: Vector3 = p * r * (1.0 + noise.get_noise_3dv(p + off) * 0.45)
			q.y *= 0.8
			var shade := 0.7 + 0.4 * clampf(p.y * 0.5 + 0.5, 0.0, 1.0)
			st.set_color(_col(base * shade, clampf(q.y + off.y, 0.0, 1.5) * 0.35))
			st.add_vertex(q + off)
	st.generate_normals()
	return st.commit()


## Grass tuft: a fan of tapered blades.
static func grass_tuft(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 9:
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x) * 0.06
		var h := rng.randf_range(0.5, 1.0)
		var tip := dir * rng.randf_range(0.2, 0.45) + Vector3(0, h, 0)
		var mid := dir * 0.08 + Vector3(0, h * 0.5, 0)
		var col := Color(0.32, 0.46, 0.16).lerp(Color(0.55, 0.55, 0.22), rng.randf())
		var verts := [[-side, col.darkened(0.4), 0.0], [side, col.darkened(0.4), 0.0], [mid - side * 0.7, col, 0.5],
				[side, col.darkened(0.4), 0.0], [mid + side * 0.7, col, 0.5], [mid - side * 0.7, col, 0.5],
				[mid - side * 0.7, col, 0.5], [mid + side * 0.7, col, 0.5], [tip, col.lightened(0.2), 1.0]]
		for v in verts:
			st.set_color(_col(v[1], v[2]))
			st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()


static func crate() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(1.0, 1.0, 1.0)
	return m


static func barrel() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.4
	m.bottom_radius = 0.4
	m.height = 1.1
	m.radial_segments = 12
	return m
