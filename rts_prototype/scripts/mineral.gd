extends Node2D
## A mineral patch workers can harvest.

var game
var team := -1
var amount := 1500
var radius := 20.0
var variant := 0


func setup(g) -> void:
	game = g
	add_to_group("minerals")
	variant = randi() % 3


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
	var tex: Texture2D = game.mineral_texture(variant)
	var k := 0.6 + 0.4 * amount / 1500.0  # patches shrink as they are mined out
	var sz := tex.get_size() * 0.5 * k
	draw_texture_rect(tex, Rect2(Vector2(-sz.x / 2.0, -sz.y * 0.68), sz), false)
