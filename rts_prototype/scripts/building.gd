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
var queue: Array = []          # unit kinds or upgrade keys
var queue_costs: Array = []    # minerals paid for each queue entry (refunded on cancel)
var prod_progress := 0.0
var rally := Vector2.ZERO
var has_rally := false
var selected := false
var radius := 0.0
# static defence (Bunker, Missile Turret)
var target = null
var cooldown_left := 0.0
var acquire_timer := 0.0
var shot_flash := 0.0
var shot_to := Vector2.ZERO


func setup(g, t: int, k: String, under_construction: bool) -> void:
	game = g
	team = t
	kind = k
	stats = Defs.BUILDINGS[k]
	max_hp = stats.hp
	size = stats.size
	radius = minf(size.x, size.y) / 2.0
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


func is_air() -> bool:
	return false


func can_target(_e) -> bool:
	return true


func can_train(uk: String) -> bool:
	return not constructing and uk in stats.trains and queue.size() < 5


func can_research(key: String) -> bool:
	return not constructing and key in stats.get("research", []) and queue.is_empty()


func is_researching(key: String) -> bool:
	return key in queue


func take_damage(amount: float, _attacker) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		game.kill(self)


func cancel_last() -> void:
	if queue.is_empty():
		return
	queue.pop_back()
	game.refund(team, queue_costs.pop_back())
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
		var item: String = queue[0]
		var is_upgrade := Defs.UPGRADES.has(item)
		var t: float = Defs.UPGRADES[item].time if is_upgrade else Defs.UNITS[item].time
		prod_progress += delta / t
		if prod_progress >= 1.0:
			prod_progress = 0.0
			queue.pop_front()
			queue_costs.pop_front()
			if is_upgrade:
				game.complete_upgrade(team, item)
			else:
				_spawn(item)
	if not constructing and stats.has("damage"):
		_defend(delta)


## Static defence: shoot the nearest enemy in range.
func _defend(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	shot_flash = maxf(0.0, shot_flash - delta)
	acquire_timer -= delta
	if not game.valid(target) or game.edge_dist(self, target) > stats.range:
		target = null
		if acquire_timer <= 0.0:
			acquire_timer = 0.3
			target = game.find_enemy(self, stats.range)
	if target != null and cooldown_left <= 0.0:
		cooldown_left = stats.cooldown
		shot_flash = 0.1
		shot_to = target.position
		var dmg: float = stats.damage * (stats.get("air_bonus", 1.0) if target.is_air() else 1.0)
		game.deal_damage(self, target, dmg, 0.0)


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
