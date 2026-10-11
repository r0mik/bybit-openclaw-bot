extends SceneTree
## Saves every 3D model from scripts/models.gd as an editable scene in models/ (blue team).
## Run: godot --headless --path . --script res://tools/export_models.gd

const Models = preload("res://scripts/models.gd")
const Defs = preload("res://scripts/defs.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://models"))
	var b = Models.new(Color(0.27, 0.57, 1.0))
	var kinds: Array = Defs.BUILDINGS.keys() + Defs.UNITS.keys()
	for kind in kinds:
		_save(b.build(kind), kind)
	for v in 3:
		_save(b.minerals(v), "minerals_%d" % v)
	print("models exported")
	quit()


func _save(model: Node3D, file_name: String) -> void:
	_set_owner(model, model)
	var ps := PackedScene.new()
	ps.pack(model)
	ResourceSaver.save(ps, "res://models/%s.tscn" % file_name)
	model.free()


func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)
