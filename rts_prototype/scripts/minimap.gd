extends Control
## Minimap: overview of the whole map. LMB moves camera, RMB orders a move.

var game


func _ready() -> void:
	custom_minimum_size = Vector2(240, 180)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


func _to_mini(p: Vector2) -> Vector2:
	return p / game.map_size * size


func _draw() -> void:
	if game == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.13, 0.09))
	for m in game.get_tree().get_nodes_in_group("minerals"):
		draw_rect(Rect2(_to_mini(m.position) - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.4, 0.85, 1.0))
	for b in game.get_tree().get_nodes_in_group("buildings"):
		var r: Rect2 = b.rect()
		draw_rect(Rect2(_to_mini(r.position), r.size / game.map_size * size), game.team_color(b.team))
	for u in game.get_tree().get_nodes_in_group("units"):
		draw_rect(Rect2(_to_mini(u.position) - Vector2(1.5, 1.5), Vector2(3, 3)), game.team_color(u.team).lightened(0.3))
	var cam: Camera2D = game.camera
	var view: Vector2 = get_viewport_rect().size / cam.zoom
	var vr := Rect2(_to_mini(cam.position - view / 2.0), view / game.map_size * size)
	draw_rect(vr, Color(1, 1, 1, 0.9), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.5, 0.45), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var wp: Vector2 = (event.position / size * game.map_size).clamp(Vector2.ZERO, game.map_size)
		if event.button_index == MOUSE_BUTTON_LEFT:
			game.camera.position = wp
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			game.minimap_command(wp)
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		game.camera.position = (event.position / size * game.map_size).clamp(Vector2.ZERO, game.map_size)
		accept_event()
