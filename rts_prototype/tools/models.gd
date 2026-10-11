extends RefCounted
## 3D models of buildings, units and minerals, assembled from primitive meshes.
## World scale: 1 unit = 10 game pixels. Units face +X. The ground is y = 0.
## Building footprints are stretched in depth (Z) by 1 / sin(CAMERA_PITCH) so that, seen from
## the tilted camera, the footprint covers exactly the building's collision rectangle in game.

const CAMERA_PITCH := 50.0
const PX := 10.0  # game pixels per world unit

var team_color := Color(0.27, 0.57, 1.0)
var _mats := {}


func _init(tc: Color) -> void:
	team_color = tc


static func depth_scale() -> float:
	return 1.0 / sin(deg_to_rad(CAMERA_PITCH))


# --- Materials --------------------------------------------------------------

func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.roughness = 0.6
	match name:
		"metal":
			_textured(m, "metal", Color(0.52, 0.55, 0.6), 0.35)
			m.metallic = 0.25
		"dark":
			_textured(m, "metal", Color(0.3, 0.32, 0.36), 0.35)
			m.metallic = 0.2
		"warm":
			_textured(m, "metal", Color(0.5, 0.43, 0.35), 0.3)
		"roof":
			_textured(m, "ribs", Color(0.5, 0.53, 0.56), 0.8)
		"hazard":
			_textured(m, "hazard", Color.WHITE, 1.2)
		"team":
			m.albedo_color = team_color.darkened(0.15)
			m.roughness = 0.45
			m.metallic = 0.2
		"team_dark":
			m.albedo_color = team_color.darkened(0.45)
			m.roughness = 0.5
		"glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = team_color.lightened(0.45)
		"red_glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.35, 0.25)
		"amber_glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.75, 0.3)
		"fire_glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.45, 0.1)
		"glass":
			m.albedo_color = team_color.lerp(Color(0.3, 0.8, 1.0), 0.35).darkened(0.25)
			m.roughness = 0.08
			m.metallic = 0.4
			m.metallic_specular = 1.0
			m.rim_enabled = true
			m.rim = 0.6
		"black":
			m.albedo_color = Color(0.07, 0.07, 0.08)
		"rubber":
			m.albedo_color = Color(0.14, 0.14, 0.15)
			m.roughness = 0.9
		"yellow":
			m.albedo_color = Color(0.9, 0.7, 0.15)
			m.roughness = 0.45
		"crystal":
			m.albedo_color = Color(0.35, 0.8, 1.0)
			m.roughness = 0.12
			m.metallic_specular = 1.0
			m.emission_enabled = true
			m.emission = Color(0.1, 0.45, 0.9)
			m.emission_energy_multiplier = 0.7
			m.rim_enabled = true
			m.rim = 0.8
	_mats[name] = m
	return m


func _textured(m: StandardMaterial3D, tex: String, tint: Color, scale: float) -> void:
	m.albedo_texture = load("res://assets/materials/%s.png" % tex)
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale


# --- Primitives -------------------------------------------------------------

func box(parent: Node3D, size: Vector3, pos: Vector3, m: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, m, rot)


func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: String,
		rot := Vector3.ZERO, seg := 24) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = seg
	mesh.rings = 1
	return _add(parent, mesh, pos, m, rot)


func sphere(parent: Node3D, r: float, pos: Vector3, m: String, scale := Vector3.ONE, half := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r if half else r * 2.0
	mesh.is_hemisphere = half
	mesh.radial_segments = 32
	mesh.rings = 16
	var mi := _add(parent, mesh, pos, m, Vector3.ZERO)
	mi.scale = scale
	return mi


func _add(parent: Node3D, mesh: Mesh, pos: Vector3, m: String, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(m)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _root(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	return n


# --- Buildings --------------------------------------------------------------

func build(kind: String) -> Node3D:
	match kind:
		"cc": return command_center()
		"depot": return supply_depot()
		"barracks": return barracks()
		"factory": return factory()
		"worker": return worker()
		"marine": return marine()
		"tank": return tank()
	push_error("unknown model " + kind)
	return null


func command_center() -> Node3D:
	var r := _root("CommandCenter")
	var w := 13.0
	var d := 10.0 * depth_scale()
	box(r, Vector3(w, 0.5, d), Vector3(0, 0.25, 0), "dark")
	for sx in [-1, 1]:  # chamfered base corners
		for sz in [-1, 1]:
			cyl(r, 1.0, 1.1, 0.6, Vector3(sx * (w / 2 - 1.0), 0.3, sz * (d / 2 - 1.0)), "dark")
	# main hull + upper deck
	box(r, Vector3(10.0, 2.6, d - 3.0), Vector3(0, 1.8, 0), "metal")
	box(r, Vector3(10.1, 0.35, d - 2.9), Vector3(0, 3.0, 0), "team")
	box(r, Vector3(8.0, 1.2, d - 5.0), Vector3(0, 3.7, -0.3), "metal")
	# command dome
	cyl(r, 3.0, 3.2, 0.5, Vector3(0, 4.5, -0.3), "dark", Vector3.ZERO, 32)
	sphere(r, 2.6, Vector3(0, 4.7, -0.3), "glass", Vector3(1, 0.85, 1), true)
	for i in 8:
		var a := i * TAU / 8.0
		box(r, Vector3(0.25, 0.3, 0.25), Vector3(cos(a) * 3.1, 4.85, -0.3 + sin(a) * 3.1), "glow")
	# side wings with vents
	for sx in [-1, 1]:
		var x: float = sx * 5.6
		box(r, Vector3(1.8, 3.0, 6.5), Vector3(x, 2.0, 0.2), "dark")
		box(r, Vector3(1.85, 0.35, 6.55), Vector3(x, 3.3, 0.2), "team")
		for k in 4:
			box(r, Vector3(1.3, 0.14, 0.08), Vector3(x, 1.0 + k * 0.45, 3.47), "black")
	# front entrance
	box(r, Vector3(3.8, 1.9, 0.3), Vector3(0, 1.45, d / 2 - 1.45), "black")
	box(r, Vector3(4.4, 0.35, 0.34), Vector3(0, 2.55, d / 2 - 1.45), "hazard")
	box(r, Vector3(4.0, 0.12, 1.6), Vector3(0, 0.56, d / 2 - 0.6), "hazard")
	for sx in [-1, 1]:
		sphere(r, 0.22, Vector3(sx * 2.4, 2.0, d / 2 - 1.3), "glow")
	# landing struts
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var p := Vector3(sx * (w / 2 - 1.0), 0, sz * (d / 2 - 1.0))
			cyl(r, 0.45, 0.6, 2.4, p + Vector3(0, 1.2, 0), "dark")
			sphere(r, 0.32, p + Vector3(0, 2.55, 0), "glow")
	# antenna
	cyl(r, 0.05, 0.1, 3.0, Vector3(3.4, 5.6, -3.0), "dark")
	sphere(r, 0.18, Vector3(3.4, 7.1, -3.0), "red_glow")
	box(r, Vector3(1.2, 0.08, 0.08), Vector3(3.4, 6.4, -3.0), "dark")
	return r


func supply_depot() -> Node3D:
	var r := _root("SupplyDepot")
	var w := 7.0
	var d := 7.0 * depth_scale()
	box(r, Vector3(w, 0.4, d), Vector3(0, 0.2, 0), "dark")
	box(r, Vector3(6.0, 1.5, d - 1.0), Vector3(0, 1.15, 0), "metal")
	box(r, Vector3(6.1, 0.35, d - 0.9), Vector3(0, 0.6, 0), "hazard")
	for sx in [-1, 1]:  # hatch halves
		box(r, Vector3(3.0, 0.3, d - 1.6), Vector3(sx * 1.45, 2.05, 0), "metal", Vector3(0, 0, -sx * 9.0))
	box(r, Vector3(0.35, 0.25, d - 1.8), Vector3(0, 2.3, 0), "glow")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(r, Vector3(0.7, 0.9, 0.7), Vector3(sx * 2.9, 1.7, sz * (d / 2 - 0.9)), "dark")
			sphere(r, 0.16, Vector3(sx * 2.9, 2.25, sz * (d / 2 - 0.9)), "glow")
	box(r, Vector3(2.4, 0.5, 0.1), Vector3(0, 1.2, d / 2 - 0.45), "team")
	return r


func barracks() -> Node3D:
	var r := _root("Barracks")
	var w := 11.0
	var d := 9.0 * depth_scale()
	box(r, Vector3(w, 0.4, d), Vector3(0, 0.2, 0), "dark")
	var body_d := d - 2.4
	box(r, Vector3(8.6, 2.6, body_d), Vector3(0, 1.7, -0.6), "metal")
	# gabled corrugated roof, ridge along X
	var half := body_d / 2.0
	var slope := 24.0
	var run := half / cos(deg_to_rad(slope))
	for sz in [-1, 1]:
		box(r, Vector3(9.2, 0.25, run + 0.2), Vector3(0, 3.0 + half * tan(deg_to_rad(slope)) / 2.0, -0.6 + sz * half / 2.0),
				"roof", Vector3(sz * slope, 0, 0))
	box(r, Vector3(9.3, 0.35, 0.35), Vector3(0, 3.0 + half * tan(deg_to_rad(slope)), -0.6), "team")
	# painted team band and front door
	var front := -0.6 + half
	box(r, Vector3(8.65, 0.5, 0.08), Vector3(0, 2.6, front + 0.02), "team")
	box(r, Vector3(3.4, 1.9, 0.2), Vector3(0, 1.35, front + 0.05), "black")
	for k in 4:
		box(r, Vector3(3.3, 0.06, 0.05), Vector3(0, 0.65 + k * 0.45, front + 0.17), "dark")
	box(r, Vector3(3.9, 0.3, 0.25), Vector3(0, 2.38, front + 0.08), "hazard")
	box(r, Vector3(4.2, 0.12, 1.6), Vector3(0, 0.46, front + 0.9), "hazard")
	for sx in [-1, 1]:
		sphere(r, 0.2, Vector3(sx * 2.3, 1.9, front + 0.15), "glow")
	# side bunkers
	for sx in [-1, 1]:
		box(r, Vector3(1.0, 1.6, body_d - 1.0), Vector3(sx * 4.9, 1.2, -0.6), "dark")
		for k in 3:
			box(r, Vector3(0.2, 0.18, 0.5), Vector3(sx * 5.42, 1.4, -2.4 + k * 1.8), "glow")
	# satellite dish
	cyl(r, 0.08, 0.12, 1.2, Vector3(3.3, 4.0, -3.4), "dark")
	cyl(r, 1.1, 0.25, 0.35, Vector3(3.3, 4.7, -3.4), "metal", Vector3(-30, 0, 20))
	return r


func factory() -> Node3D:
	var r := _root("Factory")
	var w := 12.0
	var d := 9.0 * depth_scale()
	box(r, Vector3(w, 0.4, d), Vector3(0, 0.2, 0), "dark")
	var hall_d := d - 2.2
	var hx := -1.6
	box(r, Vector3(8.0, 3.0, hall_d), Vector3(hx, 1.9, -0.5), "warm")
	box(r, Vector3(8.05, 0.4, hall_d + 0.05), Vector3(hx, 3.2, -0.5), "team")
	# saw-tooth roof with skylights
	var n := 3
	var seg := hall_d / n
	for i in n:
		var z0 := -0.5 - hall_d / 2.0 + seg * (i + 0.5)
		box(r, Vector3(8.0, 0.22, seg * 1.02), Vector3(hx, 3.85, z0 + 0.15), "warm", Vector3(-22, 0, 0))
		box(r, Vector3(7.6, 0.9, 0.12), Vector3(hx, 3.85, z0 + seg / 2.0 - 0.05), "glass")
	# garage door
	var front := -0.5 + hall_d / 2.0
	box(r, Vector3(4.6, 2.2, 0.2), Vector3(hx, 1.5, front + 0.05), "black")
	for k in 5:
		box(r, Vector3(4.5, 0.06, 0.05), Vector3(hx, 0.6 + k * 0.42, front + 0.17), "dark")
	box(r, Vector3(5.2, 0.3, 0.25), Vector3(hx, 2.75, front + 0.08), "hazard")
	box(r, Vector3(5.4, 0.12, 1.4), Vector3(hx, 0.46, front + 0.8), "hazard")
	# machinery block, chimneys, pipes
	var mx := 4.3
	box(r, Vector3(2.6, 2.4, 5.0), Vector3(mx, 1.6, -2.0), "dark")
	for cz in [-3.4, -1.0]:
		cyl(r, 0.65, 0.8, 5.0, Vector3(mx, 3.0, cz), "metal")
		cyl(r, 0.72, 0.72, 0.3, Vector3(mx, 5.0, cz), "dark")
		cyl(r, 0.5, 0.5, 0.05, Vector3(mx, 5.16, cz), "fire_glow")
		box(r, Vector3(1.8, 0.35, 0.35), Vector3(mx - 1.6, 2.6, cz), "dark")
	# exhaust fan
	cyl(r, 1.2, 1.3, 0.5, Vector3(mx, 0.65, 3.0), "dark", Vector3.ZERO, 32)
	for i in 5:
		box(r, Vector3(1.0, 0.06, 0.35), Vector3(mx, 0.95, 3.0), "metal", Vector3(0, i * 72.0 + 15.0, 12))
	# crane arm
	box(r, Vector3(0.35, 3.4, 0.35), Vector3(-5.4, 2.1, -3.4), "yellow")
	box(r, Vector3(4.0, 0.3, 0.3), Vector3(-3.6, 3.8, -3.4), "yellow")
	sphere(r, 0.2, Vector3(-5.4, 3.95, -3.4), "red_glow")
	return r


# --- Units (face +X) ----------------------------------------------------------

func worker() -> Node3D:
	var r := _root("SCV")
	for sz in [-1, 1]:
		box(r, Vector3(0.4, 0.7, 0.35), Vector3(0, 0.35, sz * 0.32), "dark")
	box(r, Vector3(1.0, 0.85, 1.1), Vector3(-0.05, 1.1, 0), "metal")
	for sz in [-1, 1]:
		box(r, Vector3(0.6, 0.35, 0.4), Vector3(0, 1.5, sz * 0.68), "team")
	box(r, Vector3(0.45, 0.65, 0.8), Vector3(-0.65, 1.2, 0), "dark")
	sphere(r, 0.36, Vector3(0.28, 1.55, 0), "glass")
	cyl(r, 0.0, 0.17, 0.75, Vector3(0.85, 1.0, 0.62), "yellow", Vector3(0, 0, -90))
	box(r, Vector3(0.6, 0.16, 0.16), Vector3(0.6, 1.0, -0.62), "dark")
	box(r, Vector3(0.2, 0.25, 0.08), Vector3(0.95, 1.0, -0.62), "metal")
	return r


func marine() -> Node3D:
	var r := _root("Marine")
	for sz in [-1, 1]:
		box(r, Vector3(0.38, 0.8, 0.34), Vector3(0, 0.4, sz * 0.24), "dark")
	box(r, Vector3(0.7, 0.75, 0.9), Vector3(0, 1.15, 0), "team")
	box(r, Vector3(0.12, 0.45, 0.6), Vector3(0.36, 1.18, 0), "metal")
	for sz in [-1, 1]:
		sphere(r, 0.3, Vector3(0, 1.45, sz * 0.55), "team", Vector3(1.0, 0.8, 1.0))
	box(r, Vector3(0.35, 0.6, 0.65), Vector3(-0.48, 1.2, 0), "dark")
	sphere(r, 0.28, Vector3(0.02, 1.75, 0), "metal")
	box(r, Vector3(0.1, 0.12, 0.34), Vector3(0.25, 1.77, 0), "amber_glow")
	box(r, Vector3(1.15, 0.16, 0.16), Vector3(0.55, 1.15, -0.26), "black")
	box(r, Vector3(0.2, 0.3, 0.12), Vector3(0.35, 0.98, -0.26), "dark")
	return r


func tank() -> Node3D:
	var r := _root("SiegeTank")
	for sz in [-1, 1]:
		box(r, Vector3(3.8, 0.7, 0.7), Vector3(0, 0.38, sz * 1.15), "rubber")
		for k in 5:
			cyl(r, 0.3, 0.3, 0.12, Vector3(-1.4 + k * 0.7, 0.38, sz * 1.52), "dark", Vector3(90, 0, 0), 16)
	box(r, Vector3(3.3, 0.6, 1.7), Vector3(-0.1, 0.85, 0), "team")
	box(r, Vector3(0.7, 0.45, 1.7), Vector3(1.6, 0.75, 0), "team_dark", Vector3(0, 0, 30))
	box(r, Vector3(2.6, 0.2, 1.5), Vector3(-0.3, 1.24, 0), "metal")
	cyl(r, 0.68, 0.78, 0.5, Vector3(-0.3, 1.58, 0), "metal", Vector3.ZERO, 28)
	box(r, Vector3(0.9, 0.18, 0.9), Vector3(-0.35, 1.9, 0), "team")
	cyl(r, 0.09, 0.11, 2.2, Vector3(1.4, 1.62, 0), "black", Vector3(0, 0, -90), 12)
	box(r, Vector3(0.3, 0.22, 0.22), Vector3(2.5, 1.62, 0), "dark")
	cyl(r, 0.02, 0.03, 1.2, Vector3(-1.0, 2.3, 0.45), "dark")
	return r


# --- Minerals -----------------------------------------------------------------

func minerals(variant: int) -> Node3D:
	var r := _root("Minerals%d" % variant)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var shards := []
	for i in rng.randi_range(5, 7):
		shards.append({
			"pos": Vector3(rng.randf_range(-1.1, 1.1), 0, rng.randf_range(-0.8, 0.8)),
			"h": rng.randf_range(1.4, 2.8), "w": rng.randf_range(0.28, 0.45),
			"tilt": Vector3(rng.randf_range(-22, 22), rng.randf_range(0, 360), rng.randf_range(-22, 22)),
		})
	for s in shards:
		var h: float = s.h
		var node := Node3D.new()
		node.position = s.pos
		node.rotation_degrees = s.tilt
		r.add_child(node)
		cyl(node, 0.02, s.w, h, Vector3(0, h / 2.0 - 0.15, 0), "crystal", Vector3.ZERO, 6)
	return r
