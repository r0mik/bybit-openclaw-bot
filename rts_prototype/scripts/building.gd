extends Node2D
## A static structure: produces units, provides supply, accepts minerals (CC).

const Defs = preload("res://scripts/defs.gd")

var game
var team := 0
var kind := "cc"
var stats: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var size := Vector2(100, 100)
var constructing := false
var build_progress := 0.0
var queue: Array = []
var prod_progress := 0.0
var rally := Vector2.ZERO
var has_rally := false
var selected := false


func setup(g, t: int, k: String, under_construction: bool) -> void:
	game = g
	team = t
	kind = k
	stats = Defs.BUILDINGS[k]
	max_hp = stats.hp
	size = stats.size
	constructing = under_construction
	hp = max_hp * 0.1 if constructing else max_hp
	add_to_group("buildings")


func is_alive() -> bool:
	return hp > 0.0


func is_complete() -> bool:
	return not constructing


func rect() -> Rect2:
	return Rect2(position - size / 2.0, size)


func surface_distance(p: Vector2) -> float:
	return game.rect_point_dist(rect(), p)


func can_train(uk: String) -> bool:
	return not constructing and uk in stats.trains and queue.size() < 5


func take_damage(amount: float, _attacker) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		game.kill(self)


func cancel_last() -> void:
	if queue.is_empty():
		return
	var uk: String = queue.pop_back()
	game.refund(team, Defs.UNITS[uk].cost)
	if queue.is_empty():
		prod_progress = 0.0


func _process(delta: float) -> void:
	if hp <= 0.0:
		return
	if constructing:
		build_progress += delta / stats.time
		hp = minf(max_hp, hp + max_hp * 0.9 * delta / stats.time)
		if build_progress >= 1.0:
			constructing = false
			game.on_building_complete(self)
	elif not queue.is_empty():
		var uk: String = queue[0]
		prod_progress += delta / Defs.UNITS[uk].time
		if prod_progress >= 1.0:
			prod_progress = 0.0
			queue.pop_front()
			_spawn(uk)
	queue_redraw()


func _spawn(uk: String) -> void:
	var r: float = Defs.UNITS[uk].radius
	var p := position + Vector2(randf_range(-25.0, 25.0), size.y / 2.0 + r + 6.0)
	var u = game.spawn_unit(team, uk, p)
	if has_rally:
		var m = game.entity_at(rally)
		if uk == "worker" and m != null and m.is_in_group("minerals"):
			u.order_gather(m)
		else:
			u.order_move(rally)
	elif uk == "worker":
		u.order_gather(game.best_mineral(u.position))


func _draw() -> void:
	var col: Color = game.team_color(team)
	var a := 0.5 if constructing else 1.0
	var r := Rect2(-size / 2.0, size)
	draw_rect(r, Color(col.darkened(0.6), a))
	draw_rect(r.grow(-8.0), Color(col.darkened(0.3), a))
	match kind:
		"cc":
			draw_circle(Vector2.ZERO, 26.0, Color(col.lightened(0.1), a))
			draw_circle(Vector2.ZERO, 14.0, Color(col.darkened(0.5), a))
		"depot":
			draw_line(r.position + Vector2(10, 10), r.end - Vector2(10, 10), Color(col.lightened(0.3), a), 4.0)
			draw_line(Vector2(r.end.x - 10, r.position.y + 10), Vector2(r.position.x + 10, r.end.y - 10), Color(col.lightened(0.3), a), 4.0)
		"barracks":
			for i in 3:
				var y := r.position.y + 18.0 + i * 20.0
				draw_line(Vector2(r.position.x + 14, y), Vector2(r.end.x - 14, y), Color(col.lightened(0.2), a), 5.0)
		"factory":
			draw_rect(Rect2(-22, -22, 44, 44), Color(col.lightened(0.15), a))
			draw_line(Vector2(-30, 0), Vector2(30, 0), Color(col.darkened(0.6), a), 6.0)
	draw_rect(r, Color(col.lightened(0.25), a), false, 2.0)
	if selected:
		draw_rect(r.grow(5.0), Color(0.3, 1.0, 0.3), false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-size.x / 2.0, -size.y / 2.0 + 16.0), stats.short,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(1, 1, 1, 0.85))
	# HP bar
	var f := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-size.x / 2.0, -size.y / 2.0 - 10.0, size.x, 5.0), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-size.x / 2.0, -size.y / 2.0 - 10.0, size.x * f, 5.0), Color(1.0 - f, f, 0.15))
	# Construction / production progress
	var bar := Rect2(-size.x / 2.0 + 10.0, size.y / 2.0 - 16.0, size.x - 20.0, 6.0)
	if constructing:
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * build_progress, bar.size.y)), Color(0.3, 0.8, 1.0))
	elif not queue.is_empty():
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * prod_progress, bar.size.y)), Color(1.0, 0.85, 0.2))
