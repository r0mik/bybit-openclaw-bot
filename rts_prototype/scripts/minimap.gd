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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.14, 0.1))
	var k: float = size.x / game.map_size.x
	for h in game.hills:
		draw_circle(_to_mini(h.pos), h.r * k, Color(0.3, 0.33, 0.2))
		draw_arc(_to_mini(h.pos), h.r * k, 0.0, TAU, 24, Color(0.45, 0.42, 0.34), 1.0)
	for l in game.lakes:
		draw_circle(_to_mini(l.pos), l.r * k * 0.9, Color(0.15, 0.35, 0.5))
	for m in game.get_tree().get_nodes_in_group("minerals"):
		draw_rect(Rect2(_to_mini(m.position) - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.4, 0.85, 1.0))
	for b in game.get_tree().get_nodes_in_group("buildings"):
		var r: Rect2 = b.rect()
		draw_rect(Rect2(_to_mini(r.position), r.size / game.map_size * size), game.team_color(b.team))
	for u in game.get_tree().get_nodes_in_group("units"):
		draw_rect(Rect2(_to_mini(u.position) - Vector2(1.5, 1.5), Vector2(3, 3)), game.team_color(u.team).lightened(0.3))
	var poly: PackedVector2Array = game.view.view_polygon()  # camera view trapezoid on the ground
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(_to_mini(p).clamp(Vector2.ZERO, size))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.9), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.5, 0.45), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var wp: Vector2 = (event.position / size * game.map_size).clamp(Vector2.ZERO, game.map_size)
		if event.button_index == MOUSE_BUTTON_LEFT:
			game.view.focus = wp
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			game.minimap_command(wp)
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		game.view.focus = (event.position / size * game.map_size).clamp(Vector2.ZERO, game.map_size)
		accept_event()
