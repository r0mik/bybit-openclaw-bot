extends SceneTree
## Renders the 3D models from tools/models.gd into 2.5D sprites (StarCraft-style pre-rendering).
## Each sprite is rendered twice: the model on a transparent background, and only its shadow on
## a white ground plane. tools/compose_sprites.py merges the passes. Also saves every model as a
## .tscn under models/ so it can be inspected in the Godot editor.
## Needs a display (use xvfb-run on a headless machine). See tools/build_assets.sh.

const Models = preload("res://tools/models.gd")
const Defs = preload("res://scripts/defs.gd")

const RES := 2       # texture pixels per game pixel
const SS := 2        # supersampling factor
const RAW := "res://.render/"
const TEAMS := [Color(0.27, 0.57, 1.0), Color(0.94, 0.29, 0.23)]
const DIRS := 16
const UNIT_FRAME := {"worker": 48, "marine": 48, "tank": 80, "wraith": 88}
const MINERAL_FRAME := 64
const MARGIN := 24

var vp: SubViewport
var cam: Camera3D
var ground: MeshInstance3D
var stage: Node3D
var meta := {"res": RES, "dirs": DIRS, "buildings": {}, "units": {}, "minerals": {"frame": MINERAL_FRAME, "variants": 3}}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RAW))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://models"))
	_setup()
	_run()


func _setup() -> void:
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.52)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.tonemap_white = 4.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-52, -38, 0)
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.rotation_degrees = Vector3(-25, 150, 0)
	vp.add_child(fill)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var p := deg_to_rad(Models.CAMERA_PITCH)
	cam.transform = Transform3D(Basis(), Vector3(0, 100 * sin(p), 100 * cos(p))).looking_at(Vector3.ZERO, Vector3.UP)
	cam.near = 1.0
	cam.far = 300.0
	vp.add_child(cam)
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color.WHITE
	gm.roughness = 1.0
	ground.material_override = gm
	vp.add_child(ground)
	stage = Node3D.new()
	vp.add_child(stage)


func _run() -> void:
	await process_frame
	for kind in Defs.BUILDINGS:
		for t in TEAMS.size():
			var model: Node3D = Models.new(TEAMS[t]).build(kind)
			stage.add_child(model)
			var size: Vector2 = Defs.BUILDINGS[kind].size
			var top := size.y / 2.0 + _height(model) * Models.PX * cos(deg_to_rad(Models.CAMERA_PITCH))
			var w := int(size.x) + 2 * MARGIN
			var h := 2 * int(ceil(top + MARGIN * 0.5))
			await _render("%s_%d" % [kind, t], w, h)
			meta.buildings[kind] = {"top": top}
			_finish_model(model, t == 0, kind)
	for kind in UNIT_FRAME:
		for t in TEAMS.size():
			var model: Node3D = Models.new(TEAMS[t]).build(kind)
			stage.add_child(model)
			var f: int = UNIT_FRAME[kind]
			for i in DIRS:
				model.rotation.y = -i * TAU / DIRS
				await _render("%s_%d_%02d" % [kind, t, i], f, f)
			model.rotation.y = 0.0
			meta.units[kind] = {"frame": f, "top": _height(model) * Models.PX * cos(deg_to_rad(Models.CAMERA_PITCH))}
			_finish_model(model, t == 0, kind)
	for v in 3:
		var model: Node3D = Models.new(TEAMS[0]).minerals(v)
		stage.add_child(model)
		await _render("minerals_%d" % v, MINERAL_FRAME, MINERAL_FRAME)
		_finish_model(model, true, "minerals_%d" % v)
	var f := FileAccess.open(RAW + "meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("render done")
	quit()


func _render(name: String, w_px: int, h_px: int) -> void:
	vp.size = Vector2i(w_px * RES * SS, h_px * RES * SS)
	cam.size = h_px / Models.PX
	var model := stage.get_child(0)
	ground.visible = false
	_set_shadow_mode(model, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	await _frame()
	vp.get_texture().get_image().save_png(RAW + name + "_obj.png")
	ground.visible = true
	_set_shadow_mode(model, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	await _frame()
	vp.get_texture().get_image().save_png(RAW + name + "_shadow.png")


func _frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _set_shadow_mode(n: Node, mode: int) -> void:
	if n is GeometryInstance3D:
		n.cast_shadow = mode
	for c in n.get_children():
		_set_shadow_mode(c, mode)


func _height(n: Node) -> float:
	var h := 0.0
	if n is MeshInstance3D:
		h = (n.global_transform * n.get_aabb()).end.y
	for c in n.get_children():
		h = maxf(h, _height(c))
	return h


## Saves the model as an editable scene (team 0 only), then removes it from the stage.
func _finish_model(model: Node3D, save: bool, file_name: String) -> void:
	stage.remove_child(model)
	if save:
		_set_shadow_mode(model, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		_set_owner(model, model)
		var ps := PackedScene.new()
		ps.pack(model)
		ResourceSaver.save(ps, "res://models/%s.tscn" % file_name)
	model.free()


func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)
