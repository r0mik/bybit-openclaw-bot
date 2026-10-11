extends Node2D
## A mineral patch workers can harvest.

var game
var team := -1
var amount := 1500
var radius := 20.0
var variant := 0
var selected := false


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
