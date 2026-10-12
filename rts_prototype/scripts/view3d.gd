extends Node3D
## Real-time 3D presentation (StarCraft II style): dynamic sun light with soft shadows, sky
## ambient + reflections, bloom, SSAO (Forward+), normal-mapped terrain and particle effects.
## Game logic stays 2D in game pixels; every entity is mirrored here by a 3D model.
## Coordinates: logic (x, y) in px  ->  world (x / PX, 0, y / PX).

const Models = preload("res://scripts/models.gd")
const Defs = preload("res://scripts/defs.gd")
const TerrainScript = preload("res://scripts/terrain.gd")
const Doodads = preload("res://scripts/doodads.gd")
const WATER_LEVEL := -0.35
const PX := 10.0
const PITCH := 56.0
const FOV := 38.0
const ZOOM_MIN := 28.0
const ZOOM_MAX := 140.0
## Units are drawn a bit larger than their collision size (readability, like in SC2).
const UNIT_SCALE := {"worker": 1.4, "marine": 1.45, "tank": 1.05, "wraith": 0.95}

var game
var camera: Camera3D
var focus := Vector2.ZERO   # logic point the camera looks at
var dist := 52.0            # camera distance to the focus point (zoom)
var builders: Array = []    # Models instance per team (shares materials)
var views := {}             # entity -> Node3D root
var heights := {}           # model kind -> height in world units
var time := 0.0
var terrain  # scripts/terrain.gd

var fx_root: Node3D
var _additive: StandardMaterial3D
var _smoke: StandardMaterial3D
var _ring_mats := {}
var _tracers: Array = []    # {node, t, dur}
var _lights: Array = []     # {light, t, dur, energy}
var _markers: Array = []    # {node, mat, t}
var _scorches: Array = []   # {node, mat, t}
var _ghost: Node3D
var _ghost_kind := ""
var _ghost_ok_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D
var _fire_ramp: Gradient
var _smoke_ramp: Gradient
var _spark_ramp: Gradient


func setup(g, team_colors: Array) -> void:
	game = g
	for c in team_colors:
		builders.append(Models.new(c))
	_make_environment()
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 1.0
	camera.far = 600.0
	camera.current = true
	add_child(camera)
	fx_root = Node3D.new()
	add_child(fx_root)
	_make_fx_resources()
	_make_terrain()
	_make_water()
	_make_doodads()


# --- World setup --------------------------------------------------------------

func _make_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.33, 0.55)
	sky_mat.sky_horizon_color = Color(0.62, 0.64, 0.68)
	sky_mat.ground_horizon_color = Color(0.5, 0.47, 0.42)
	sky_mat.ground_bottom_color = Color(0.16, 0.14, 0.11)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = true       # Forward+ only; ignored by the Compatibility renderer
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.3
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)


func _make_terrain() -> void:
	var flats := []
	for p in game.start_positions + game.expansions:
		flats.append({"c": p / PX, "r": 50.0})
	terrain = TerrainScript.new(game.map_size / PX, _to_world(game.hills), _to_world(game.lakes), flats)
	var mi := MeshInstance3D.new()
	mi.mesh = terrain.build_mesh()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scripts/terrain.gdshader")
	for layer in ["dirt", "grass", "rock"]:
		sm.set_shader_parameter(layer + "_tex", load("res://assets/terrain/%s.png" % layer))
		sm.set_shader_parameter(layer + "_nrm", load("res://assets/terrain/%s_n.png" % layer))
	var noise := FastNoiseLite.new()
	noise.seed = 4
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = noise
	sm.set_shader_parameter("mask", nt)
	sm.set_shader_parameter("map_size", game.map_size / PX)
	sm.set_shader_parameter("splat", terrain.splat_texture())
	sm.set_shader_parameter("splat_origin", terrain.origin)
	sm.set_shader_parameter("splat_size", Vector2((terrain.cols - 1) * terrain.STEP, (terrain.rows - 1) * terrain.STEP))
	mi.material_override = sm
	add_child(mi)


## Converts hill / lake definitions from game px to world units.
func _to_world(arr: Array) -> Array:
	var out := []
	for o in arr:
		var d := {"c": o.pos / PX, "r": o.r / PX}
		if o.has("h"):
			d["h"] = o.h
		else:
			d["depth"] = 3.5
		out.append(d)
	return out


func _make_water() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.03
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.noise = noise
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/water.gdshader")
	mat.set_shader_parameter("ripples", nt)
	for l in game.lakes:
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * l.r / PX * 2.6
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(l.pos.x / PX, WATER_LEVEL, l.pos.y / PX)
		add_child(mi)


## Height of the ground (world units) under a logic point (game px).
func ground_h(p: Vector2) -> float:
	return terrain.height(p.x / PX, p.y / PX)


func _on_ground(x: float, z: float, scale: float, rng: RandomNumberGenerator, sink := 0.1) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
	return Transform3D(b, Vector3(x, terrain.height(x, z) - sink * scale, z))


## Palms, bushes, grass, boulders, pebbles and supply crates.
func _make_doodads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var map_w: Vector2 = game.map_size / PX
	var foliage := ShaderMaterial.new()
	foliage.shader = load("res://scripts/foliage.gdshader")
	var grass_mat: ShaderMaterial = foliage.duplicate()
	grass_mat.set_shader_parameter("sway", 0.08)
	grass_mat.set_shader_parameter("speed", 2.4)
	var palms := [[], [], [], []]
	var bushes := [[], [], []]
	var boulders := [[], [], []]
	var pebbles := [[], [], []]
	for h in game.hills:
		var c: Vector2 = h.pos / PX
		var r: float = h.r / PX
		for i in rng.randi_range(5, 8):  # oasis on the plateau
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r * 0.5
			_add_palm(palms, bushes, c.x + cos(a) * d, c.y + sin(a) * d, rng)
		for i in 16:  # boulders at the foot of the cliffs
			var a := rng.randf() * TAU
			var d := r * rng.randf_range(0.8, 1.02)
			boulders[i % 3].append(_on_ground(c.x + cos(a) * d, c.y + sin(a) * d, rng.randf_range(0.9, 2.6), rng, 0.3))
	for l in game.lakes:
		var c: Vector2 = l.pos / PX
		var r: float = l.r / PX
		for i in 14:  # palms along the sandy shore
			var a := i * TAU / 14.0 + rng.randf_range(-0.15, 0.15)
			var d := r * rng.randf_range(0.97, 1.12)
			_add_palm(palms, bushes, c.x + cos(a) * d, c.y + sin(a) * d, rng)
		for i in 10:
			var a := rng.randf() * TAU
			var d := r * rng.randf_range(0.85, 1.0)
			boulders[i % 3].append(_on_ground(c.x + cos(a) * d, c.y + sin(a) * d, rng.randf_range(0.5, 1.4), rng, 0.3))
	for i in 320:  # groves and boulders on the border mountains
		var side := rng.randi() % 4
		var t := rng.randf()
		var out := rng.randf_range(2.0, 40.0)
		var x: float = [t * map_w.x, map_w.x + out, t * map_w.x, -out][side]
		var z: float = [-out, t * map_w.y, map_w.y + out, t * map_w.y][side]
		if rng.randf() < 0.3:
			_add_palm(palms, bushes, x, z, rng)
		else:
			boulders[i % 3].append(_on_ground(x, z, rng.randf_range(2.0, 6.5), rng, 0.25))
	for i in 600:
		var x := rng.randf_range(-20.0, map_w.x + 20.0)
		var z := rng.randf_range(-20.0, map_w.y + 20.0)
		pebbles[i % 3].append(_on_ground(x, z, rng.randf_range(0.12, 0.45), rng, 0.2))
	var tufts := [[], [], []]
	var placed := 0
	var tries := 0
	while placed < 7000 and tries < 60000:
		tries += 1
		var x := rng.randf_range(-15.0, map_w.x + 15.0)
		var z := rng.randf_range(-15.0, map_w.y + 15.0)
		var lay: Color = terrain.layers(x, z)
		if lay.r < 0.45 or lay.g > 0.2 or rng.randf() > lay.r or terrain.height(x, z) < WATER_LEVEL + 0.1:
			continue
		tufts[placed % 3].append(_on_ground(x, z, rng.randf_range(1.1, 2.2), rng, 0.05))
		placed += 1
		if rng.randf() < 0.06:
			bushes[placed % 3].append(_on_ground(x, z, rng.randf_range(0.5, 1.0), rng))
	for k in 4:
		_add_multimesh(Doodads.palm(100 + k), foliage, palms[k], true)
	for k in 3:
		_add_multimesh(Doodads.bush(200 + k), foliage, bushes[k], true)
		_add_multimesh(Doodads.grass_tuft(300 + k), grass_mat, tufts[k], false)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_texture = load("res://assets/terrain/rock.png")
	rock_mat.normal_enabled = true
	rock_mat.normal_texture = load("res://assets/terrain/rock_n.png")
	rock_mat.uv1_triplanar = true
	rock_mat.uv1_scale = Vector3.ONE * 0.35
	rock_mat.albedo_color = Color(0.78, 0.74, 0.68)
	rock_mat.roughness = 0.9
	for k in 3:
		var rm := _rock_mesh(k + 3)
		_add_multimesh(rm, rock_mat, boulders[k], true)
		_add_multimesh(rm, rock_mat, pebbles[k], false)
	_make_supply_dumps(rng)


func _add_palm(palms: Array, bushes: Array, x: float, z: float, rng: RandomNumberGenerator) -> void:
	palms[rng.randi() % 4].append(_on_ground(x, z, rng.randf_range(0.8, 1.15), rng, 0.0))
	for k in rng.randi_range(1, 2):
		var a := rng.randf() * TAU
		bushes[rng.randi() % 3].append(_on_ground(x + cos(a) * 1.6, z + sin(a) * 1.6, rng.randf_range(0.6, 1.1), rng))


## Abandoned crates and fuel barrels near the expansions.
func _make_supply_dumps(rng: RandomNumberGenerator) -> void:
	var crate_mat: StandardMaterial3D = builders[0].mat("warm").duplicate()
	crate_mat.albedo_color = Color(0.55, 0.45, 0.3)
	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.55, 0.18, 0.12)
	barrel_mat.roughness = 0.5
	barrel_mat.metallic = 0.4
	var crates := []
	var barrels := []
	for e in game.expansions:
		var to_c: Vector2 = game.map_size / 2.0 - e
		var dir := to_c.normalized() if to_c.length() > 1.0 else Vector2.DOWN
		var base: Vector2 = (e + dir.rotated(PI / 2.0) * 230.0) / PX
		for i in 5:
			var s := rng.randf_range(0.8, 1.2)
			var xf := _on_ground(base.x + rng.randf_range(-2.0, 2.0), base.y + rng.randf_range(-2.0, 2.0), s, rng, -0.5)
			crates.append(xf)
			if rng.randf() < 0.4:
				crates.append(Transform3D(xf.basis.rotated(Vector3.UP, 0.4), xf.origin + Vector3(0, s, 0)))
		for i in 4:
			barrels.append(_on_ground(base.x + 3.0 + rng.randf_range(-1.0, 1.5), base.y + rng.randf_range(-1.5, 1.5), 1.0, rng, -0.55))
	_add_multimesh(Doodads.crate(), crate_mat, crates, true)
	_add_multimesh(Doodads.barrel(), barrel_mat, barrels, true)


func _rock_mesh(seed: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 18
	sphere.rings = 10
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.8
	for i in verts.size():
		var v := verts[i]
		v *= 1.0 + noise.get_noise_3dv(v * 1.3) * 0.5
		v.y *= 0.65
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_normals()
	return st.commit()


func _add_multimesh(mesh: Mesh, mat: Material, xforms: Array, shadows := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _make_fx_resources() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_additive = StandardMaterial3D.new()
	_additive.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_additive.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_additive.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_additive.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_additive.vertex_color_use_as_albedo = true
	_additive.albedo_texture = tex
	_smoke = _additive.duplicate()
	_smoke.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_fire_ramp = _ramp([Color(1.0, 0.75, 0.35, 0.7), Color(1.0, 0.45, 0.1, 0.55), Color(0.5, 0.1, 0.02, 0)])
	_smoke_ramp = _ramp([Color(0.25, 0.23, 0.2, 0.0), Color(0.22, 0.2, 0.18, 0.55), Color(0.3, 0.3, 0.3, 0)])
	_spark_ramp = _ramp([Color(1.0, 0.95, 0.6, 1), Color(1.0, 0.6, 0.2, 0)])
	_ghost_ok_mat = _holo_mat(Color(0.3, 1.0, 0.4, 0.35))
	_ghost_bad_mat = _holo_mat(Color(1.0, 0.25, 0.2, 0.35))


func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray(colors)
	return g


func _holo_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _ring_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _ring_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
		_ring_mats[key] = m
	return _ring_mats[key]


func _ring(radius: float, c: Color) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = radius
	t.outer_radius = radius + 0.16
	t.rings = 48
	t.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.scale = Vector3(1, 0.12, 1)
	mi.position.y = 0.05
	mi.material_override = _ring_mat(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Entities -----------------------------------------------------------------

func add_entity(e) -> void:
	var root := Node3D.new()
	var model: Node3D
	var ring_r := 1.0
	if e.is_in_group("minerals"):
		model = builders[0].minerals(e.variant)
		var l := OmniLight3D.new()
		l.light_color = Color(0.35, 0.75, 1.0)
		l.light_energy = 0.8
		l.omni_range = 4.0
		l.position.y = 1.5
		root.add_child(l)
		ring_r = 2.2
	else:
		model = builders[e.team].build(e.kind)
		if e.is_in_group("units"):
			var k: float = UNIT_SCALE.get(e.kind, 1.0)
			model.scale = Vector3.ONE * k
			ring_r = e.radius / PX * k + 0.25
		else:
			ring_r = maxf(e.size.x, e.size.y) / PX * 0.62
			if e.constructing:
				var holo := MeshInstance3D.new()
				holo.name = "Holo"
				var bm := BoxMesh.new()
				bm.size = Vector3(e.size.x / PX, _height_of(e.kind, model), e.size.y / PX)
				holo.mesh = bm
				holo.position.y = bm.size.y / 2.0
				holo.material_override = _holo_mat(Color(0.35, 0.75, 1.0, 0.12))
				holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(holo)
	model.name = "Model"
	root.add_child(model)
	var anims := []
	_collect_anims(model, anims)
	root.set_meta("anims", anims)
	var kind: String = "minerals" if e.is_in_group("minerals") else e.kind
	_height_of(kind, model)
	var friendly: bool = e.team == 0
	var col := Color(0.3, 1.0, 0.35) if friendly else (Color(1.0, 0.85, 0.3) if e.team < 0 else Color(1.0, 0.3, 0.25))
	var ring := _ring(ring_r, col)
	ring.name = "Ring"
	ring.visible = false
	root.add_child(ring)
	add_child(root)
	views[e] = root
	_sync(e, root, 1.0)


func _collect_anims(n: Node, out: Array) -> void:
	if n is Node3D and n.has_meta("anim"):
		out.append({"node": n, "kind": n.get_meta("anim"), "speed": n.get_meta("speed"), "scale": n.scale,
				"phase": randf() * TAU})
	for c in n.get_children():
		_collect_anims(c, out)


## Spinning radars / holograms, pulsing energy cores, and defence turrets tracking their target.
func _animate_building(e, root: Node3D, model: Node3D, delta: float) -> void:
	for a in root.get_meta("anims", []):
		var n: Node3D = a.node
		if a.kind == "spin":
			n.rotation.y += delta * a.speed
		else:
			n.scale = a.scale * (1.0 + 0.12 * sin(time * a.speed * 2.0 + a.phase))
	var tur: Node3D = model.get_node_or_null("Turret")
	if tur:
		if game.valid(e.target):
			tur.rotation.y = lerp_angle(tur.rotation.y, -(e.target.position - e.position).angle(), minf(1.0, delta * 6.0))
		else:
			tur.rotation.y += delta * 0.4


func remove_entity(e) -> void:
	if views.has(e):
		views[e].queue_free()
		views.erase(e)


func _height_of(kind: String, model: Node3D) -> float:
	if not heights.has(kind):
		heights[kind] = maxf(_max_y(model, Transform3D.IDENTITY), 0.5)  # includes model.scale
	return heights[kind]


func _max_y(n: Node, parent_xf: Transform3D) -> float:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * n.transform
	var h := 0.0
	if n is MeshInstance3D:
		h = (xf * n.get_aabb()).end.y
	for c in n.get_children():
		h = maxf(h, _max_y(c, xf))
	return h


## Height of an entity's model in world units (for HP bars and picking).
func top_of(e) -> float:
	var kind: String = "minerals" if e.is_in_group("minerals") else e.kind
	return heights.get(kind, 2.0)


func _sync(e, root: Node3D, delta: float) -> void:
	var model: Node3D = root.get_node("Model")
	var p3 := Vector3(e.position.x / PX, ground_h(e.position), e.position.y / PX)
	root.get_node("Ring").visible = e.selected
	if e.is_in_group("units"):
		var moved := root.position.distance_to(p3) > 0.002
		root.position = p3
		var seed := float(e.get_instance_id() % 97)
		model.rotation.y = lerp_angle(model.rotation.y, -e.facing, minf(1.0, delta * 12.0))
		match e.kind:
			"marine", "worker":
				var bob := absf(sin(time * 11.0 + seed)) * 0.12 if moved else 0.0
				model.position.y = lerpf(model.position.y, bob, minf(1.0, delta * 15.0))
				if e.kind == "worker":
					model.get_node("Carry").visible = e.carrying > 0
					if e.is_mining() and e.carrying == 0 and e.mine_timer > 0.0 and randf() < delta * 4.0:
						_burst(p3 + Vector3(0, 1.0, 0) + Vector3(cos(e.facing), 0, sin(e.facing)) * 1.0,
								6, _spark_ramp, _additive, 3.0, 0.25, 0.35, Vector3(0, -6, 0))
			"wraith":
				var body: Node3D = model.get_node("Body")
				body.position.y = 3.0 + sin(time * 2.2 + seed) * 0.18
				body.rotation.x = lerpf(body.rotation.x, 0.25 if moved else 0.0, minf(1.0, delta * 3.0))
			"tank":
				var tur: Node3D = model.get_node("Turret")
				var want := 0.0
				if game.valid(e.target):
					want = -(e.target.position - e.position).angle() - model.rotation.y
				tur.rotation.y = lerp_angle(tur.rotation.y, want, minf(1.0, delta * 6.0))
	elif e.is_in_group("buildings"):
		p3.y = _footprint_h(e.position, e.size)
		root.position = p3
		var holo := root.get_node_or_null("Holo")
		if e.constructing:
			model.scale = Vector3(1.0, maxf(0.03, e.build_progress), 1.0)
			if holo:
				holo.visible = true
			if randf() < delta * 7.0:
				var h: float = top_of(e) * e.build_progress
				var off := Vector3(randf_range(-0.5, 0.5) * e.size.x / PX, h, randf_range(-0.5, 0.5) * e.size.y / PX)
				_burst(p3 + off, 8, _spark_ramp, _additive, 4.0, 0.25, 0.4, Vector3(0, -8, 0))
		else:
			model.scale = Vector3.ONE
			_animate_building(e, root, model, delta)
			if holo:
				holo.queue_free()
			if e.hp < e.max_hp * 0.6 and not root.has_meta("fire"):
				root.set_meta("fire", true)
				var spots := 1 if e.hp > e.max_hp * 0.35 else 2
				for i in spots:
					var off := Vector3(randf_range(-0.3, 0.3) * e.size.x / PX, top_of(e) * 0.7, randf_range(-0.3, 0.3) * e.size.y / PX)
					root.add_child(_fire_emitter(off))
	else:  # minerals
		root.position = p3
		var k: float = 0.6 + 0.4 * e.amount / 1500.0
		model.scale = Vector3(k, k, k)


## Lowest ground point under a footprint, so buildings never float on slopes.
func _footprint_h(p: Vector2, size: Vector2) -> float:
	var h := ground_h(p)
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			h = minf(h, ground_h(p + Vector2(sx * size.x, sy * size.y)))
	return h


func _process(delta: float) -> void:
	time += delta
	var p := deg_to_rad(PITCH)
	var target := Vector3(focus.x / PX, ground_h(focus) * 0.5, focus.y / PX)
	camera.transform = Transform3D(Basis(), target + Vector3(0, sin(p), cos(p)) * dist).looking_at(target, Vector3.UP)
	for e in views.keys():
		if is_instance_valid(e):
			_sync(e, views[e], delta)
		else:
			remove_entity(e)
	_update_ghost()
	_update_fx(delta)


# --- Camera & picking -----------------------------------------------------------

func zoom(factor: float) -> void:
	dist = clampf(dist * factor, ZOOM_MIN, ZOOM_MAX)


func screen_to_ground(sp: Vector2) -> Vector2:
	var o := camera.project_ray_origin(sp)
	var d := camera.project_ray_normal(sp)
	if absf(d.y) < 1e-4:
		return focus
	var level := 0.0
	var hit := o
	for i in 4:  # refine the ray / height-field intersection
		hit = o + d * ((level - o.y) / d.y)
		level = terrain.height(hit.x, hit.z)
	return Vector2(hit.x, hit.z) * PX


func mouse_ground() -> Vector2:
	return screen_to_ground(get_viewport().get_mouse_position())


func to_screen(p: Vector2, h := 0.0) -> Vector2:
	return camera.unproject_position(Vector3(p.x / PX, h + ground_h(p), p.y / PX))


## Screen-space length of a world distance r (world units) measured at point p, height h.
func px_size(p: Vector2, r: float, h := 0.0) -> float:
	return to_screen(p, h).distance_to(to_screen(p + Vector2(r * PX, 0), h))


## Visible ground area as 4 logic points (for the minimap).
func view_polygon() -> PackedVector2Array:
	var vs := get_viewport().get_visible_rect().size
	return PackedVector2Array([screen_to_ground(Vector2.ZERO), screen_to_ground(Vector2(vs.x, 0)),
			screen_to_ground(vs), screen_to_ground(Vector2(0, vs.y))])


func _building_screen_rect(b) -> Rect2:
	var h := top_of(b)
	var r := Rect2()
	var first := true
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for y in [0.0, h]:
				var sp := to_screen(b.position + Vector2(sx * b.size.x, sy * b.size.y), y)
				if first:
					r = Rect2(sp, Vector2.ZERO)
					first = false
				else:
					r = r.expand(sp)
	return r


## Entity under the screen point: units first (nearest to the cursor), then buildings, minerals.
func pick(sp: Vector2):
	var best = null
	var best_d := INF
	for e in views:
		if not game.valid(e) or not e.is_in_group("units"):
			continue
		var h := top_of(e)
		var c := to_screen(e.position, h * 0.5)
		var r := maxf(px_size(e.position, e.radius / PX + 0.3, h * 0.5), px_size(e.position, h * 0.45, h * 0.5))
		var d := c.distance_to(sp)
		if d < r and d < best_d:
			best_d = d
			best = e
	if best != null:
		return best
	for e in views:
		if game.valid(e) and e.is_in_group("buildings") and _building_screen_rect(e).has_point(sp):
			return e
	for e in views:
		if game.valid(e) and e.is_in_group("minerals"):
			if to_screen(e.position, 1.0).distance_to(sp) < px_size(e.position, 2.2, 1.0):
				return e
	return null


func units_in_rect(rect: Rect2, team: int) -> Array:
	var res := []
	for e in views:
		if game.valid(e) and e.is_in_group("units") and e.team == team:
			if rect.has_point(to_screen(e.position, top_of(e) * 0.4)):
				res.append(e)
	return res


func buildings_in_rect(rect: Rect2, team: int) -> Array:
	var res := []
	for e in views:
		if game.valid(e) and e.is_in_group("buildings") and e.team == team:
			if rect.intersects(_building_screen_rect(e)):
				res.append(e)
	return res


# --- Placement ghost ------------------------------------------------------------

func _update_ghost() -> void:
	var kind: String = game.placing
	if kind != _ghost_kind:
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		_ghost_kind = kind
		if kind != "":
			_ghost = builders[0].build(kind)
			add_child(_ghost)
	if _ghost == null:
		return
	var p: Vector2 = game.snap(mouse_ground())
	_ghost.position = Vector3(p.x / PX, _footprint_h(p, Defs.BUILDINGS[kind].size) + 0.02, p.y / PX)
	var mat := _ghost_ok_mat if game.can_place(kind, p) else _ghost_bad_mat
	_override_all(_ghost, mat)


func _override_all(n: Node, mat: Material) -> void:
	if n is GeometryInstance3D:
		n.material_override = mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_override_all(c, mat)


# --- Effects ----------------------------------------------------------------------

func _world(p: Vector2, h := 0.0) -> Vector3:
	return Vector3(p.x / PX, h + ground_h(p), p.y / PX)


func _burst(pos: Vector3, amount: int, ramp: Gradient, mat: Material, speed: float, size: float,
		life: float, gravity := Vector3(0, -2, 0), spread := 180.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.material = mat
	p.mesh = q
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = gravity
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.color_ramp = ramp
	p.position = pos
	fx_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)
	return p


func _flash_light(pos: Vector3, c: Color, energy: float, rng: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	fx_root.add_child(l)
	_lights.append({"light": l, "t": 0.0, "dur": dur, "energy": energy})


func _fire_emitter(offset: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = offset
	for k in 2:
		var p := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.material = _additive if k == 0 else _smoke
		p.mesh = q
		p.amount = 14 if k == 0 else 18
		p.lifetime = 0.7 if k == 0 else 2.2
		p.direction = Vector3.UP
		p.spread = 15.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 2.5 if k == 0 else 3.5
		p.gravity = Vector3(0.6, 1.0, 0) if k == 1 else Vector3.ZERO
		p.scale_amount_min = 0.6 if k == 0 else 1.0
		p.scale_amount_max = 1.2 if k == 0 else 2.4
		p.color_ramp = _fire_ramp if k == 0 else _smoke_ramp
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.4
		n.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.2)
	l.light_energy = 1.5
	l.omni_range = 5.0
	n.add_child(l)
	return n


## Weapon fire: tracer from muzzle to target, muzzle flash, impact.
func fx_shot(attacker, target, splash: bool) -> void:
	if not views.has(attacker) or not is_instance_valid(target):
		return
	var a_h := top_of(attacker)
	var dir: Vector2 = (target.position - attacker.position).normalized()
	var muzzle: Vector3
	var color := Color(1.0, 0.85, 0.4)
	var width := 0.06
	if attacker.is_in_group("buildings"):
		muzzle = _world(attacker.position, a_h * 0.75)
		if attacker.kind == "turret":
			color = Color(1.0, 0.45, 0.15)
			width = 0.14
	else:
		var fwd: float = attacker.radius / PX + 0.4
		muzzle = _world(attacker.position + dir * fwd * PX, a_h * 0.55)
		match attacker.kind:
			"tank":
				muzzle = _world(attacker.position + dir * 3.0 * PX, 1.62)
				color = Color(1.0, 0.6, 0.2)
				width = 0.16
			"wraith":
				color = game.team_color(attacker.team).lightened(0.4)
				width = 0.09
			"worker":
				return
	var t_h: float = top_of(target) * 0.45 if not target.is_in_group("buildings") else top_of(target) * 0.5
	var hit := _world(target.position, t_h) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	_tracer(muzzle, hit, color, width)
	_burst(muzzle, 3, _fire_ramp, _additive, 0.5, 0.5 if width < 0.1 else 1.2, 0.08, Vector3.ZERO)
	_burst(hit, 5, _spark_ramp, _additive, 4.0, 0.25, 0.3, Vector3(0, -8, 0))
	if splash or width >= 0.14:
		_flash_light(muzzle, color, 3.0, 6.0, 0.15)
	if splash:
		fx_explosion(target.position, 1.0)


func _tracer(from: Vector3, to: Vector3, c: Color, width: float) -> void:
	var len := from.distance_to(to)
	if len < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, len)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 5.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	mi.global_transform = Transform3D(Basis(), (from + to) / 2.0).looking_at(to, Vector3.UP)
	_tracers.append({"node": mi, "t": 0.0, "dur": 0.07})


## Explosion: fireball, smoke column, sparks, light flash and a scorch mark.
func fx_explosion(p: Vector2, size: float) -> void:
	var pos := _world(p, 0.6 * size)
	_burst(pos, int(18 * size) + 6, _fire_ramp, _additive, 5.0 * size, 1.6 * size, 0.6, Vector3(0, 1.5, 0))
	_burst(pos, int(12 * size) + 4, _smoke_ramp, _smoke, 3.0 * size, 2.6 * size, 1.8, Vector3(0.5, 2.0, 0))
	_burst(pos, int(16 * size) + 6, _spark_ramp, _additive, 10.0 * size, 0.3, 0.7, Vector3(0, -12, 0))
	_flash_light(pos + Vector3(0, 1, 0), Color(1.0, 0.6, 0.25), 6.0 * size, 7.0 * size + 3.0, 0.35)
	var sc := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.0) * size
	q.orientation = PlaneMesh.FACE_Y
	sc.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _additive.albedo_texture
	m.albedo_color = Color(0.05, 0.04, 0.03, 0.7)
	sc.material_override = m
	sc.position = _world(p, 0.03)
	sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(sc)
	_scorches.append({"node": sc, "mat": m, "t": 0.0})


func fx_death(e) -> void:
	if e.is_in_group("buildings"):
		var s: float = maxf(e.size.x, e.size.y) / 60.0
		fx_explosion(e.position, s)
		for i in 3:
			var off := Vector2(randf_range(-0.4, 0.4) * e.size.x, randf_range(-0.4, 0.4) * e.size.y)
			fx_explosion(e.position + off, s * 0.6)
	elif e.is_in_group("units"):
		fx_explosion(e.position, 1.3 if e.kind in ["tank", "wraith"] else 0.6)


func fx_marker(p: Vector2, c: Color) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.6
	t.outer_radius = 0.8
	t.rings = 32
	t.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.position = _world(p, 0.08)
	mi.scale = Vector3(1, 0.1, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	_markers.append({"node": mi, "mat": m, "t": 0.0})


func _update_fx(delta: float) -> void:
	for tr in _tracers:
		tr.t += delta
		if tr.t >= tr.dur:
			tr.node.queue_free()
	_tracers = _tracers.filter(func(tr): return tr.t < tr.dur)
	for l in _lights:
		l.t += delta
		l.light.light_energy = l.energy * maxf(0.0, 1.0 - l.t / l.dur)
		if l.t >= l.dur:
			l.light.queue_free()
	_lights = _lights.filter(func(l): return l.t < l.dur)
	for mk in _markers:
		mk.t += delta
		var k: float = mk.t / 0.6
		var s := 1.6 - k
		mk.node.scale = Vector3(s, 0.1, s)
		mk.mat.albedo_color.a = 1.0 - k
		if k >= 1.0:
			mk.node.queue_free()
	_markers = _markers.filter(func(mk): return mk.t < 0.6)
	for sc in _scorches:
		sc.t += delta
		if sc.t > 6.0:
			sc.mat.albedo_color.a = 0.7 * maxf(0.0, 1.0 - (sc.t - 6.0) / 4.0)
		if sc.t >= 10.0:
			sc.node.queue_free()
	_scorches = _scorches.filter(func(sc): return sc.t < 10.0)
