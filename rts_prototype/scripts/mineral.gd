extends Node2D
## A mineral patch workers can harvest.

var game
var team := -1
var amount := 1500
var radius := 20.0
var shards: Array = []


func setup(g) -> void:
	game = g
	add_to_group("minerals")
	for i in 4:
		var off := Vector2(randf_range(-9, 9), randf_range(-7, 7))
		shards.append({"off": off, "h": randf_range(12, 20), "w": randf_range(6, 9)})


func is_alive() -> bool:
	return amount > 0


func surface_distance(p: Vector2) -> float:
	return maxf(0.0, p.distance_to(position) - radius)


func take(n: int) -> int:
	var t := mini(n, amount)
	amount -= t
	if amount <= 0:
		game.kill(self)
	return t


func _draw() -> void:
	draw_circle(Vector2(0, 6), radius, Color(0, 0, 0, 0.25))
	var k := 0.5 + 0.5 * amount / 1500.0
	for s in shards:
		var o: Vector2 = s.off
		var h: float = s.h * k
		var w: float = s.w
		var pts := PackedVector2Array([o + Vector2(0, -h), o + Vector2(w, 0), o + Vector2(0, h * 0.4), o + Vector2(-w, 0)])
		draw_colored_polygon(pts, Color(0.35, 0.8, 1.0))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.75, 0.95, 1.0), 1.0)
