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
	queue_redraw()


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


## Footprint rectangle extended upwards to the top of the sprite (used for mouse picking).
func pick_rect() -> Rect2:
	var top: float = game.building_top(kind)
	return Rect2(position.x - size.x / 2.0, position.y - top, size.x, top + size.y / 2.0)


func _draw() -> void:
	var tex: Texture2D = game.building_texture(kind, team)
	var ts: Vector2 = tex.get_size() / game.sprite_res   # sprite size in game pixels, centred on the footprint
	var full := Rect2(-ts / 2.0, ts)
	var r := Rect2(-size / 2.0, size)
	var top: float = game.building_top(kind)
	if selected:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, size.y / size.x))
		draw_arc(Vector2.ZERO, size.x * 0.66, 0.0, TAU, 48, Color(0.3, 1.0, 0.3), 2.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if constructing:
		# Blueprint ghost, with the finished building rising from the ground.
		draw_texture_rect(tex, full, false, Color(0.45, 0.8, 1.0, 0.3))
		var k := clampf(build_progress, 0.0, 1.0)
		var tp := tex.get_size()
		var src := Rect2(0.0, tp.y * (1.0 - k), tp.x, tp.y * k)
		var dst := Rect2(full.position.x, full.end.y - full.size.y * k, full.size.x, full.size.y * k)
		draw_texture_rect_region(tex, dst, src)
		var y := clampf(dst.position.y, -top, r.end.y)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0.5, 0.9, 1.0, 0.8), 2.0)
		for i in 4:  # welding sparks
			var sx := r.position.x + fposmod(game.elapsed * 97.0 + i * 37.0, r.size.x)
			draw_circle(Vector2(sx, y), 2.0 + randf() * 1.5, Color(1.0, 0.9, 0.5, 0.9))
	else:
		draw_texture_rect(tex, full, false)
	_draw_damage(top)
	if shot_flash > 0.0:
		var muzzle := Vector2(0, -top * 0.75)
		var hit := to_local(shot_to) + Vector2(0, -6.0)
		var col := Color(1.0, 0.55, 0.2) if kind == "turret" else Color(1.0, 0.95, 0.5)
		draw_line(muzzle, hit, col, 2.5 if kind == "turret" else 1.5)
		draw_circle(muzzle, 3.5, Color(col, 0.9))
	# HP bar above the sprite
	var f := clampf(hp / max_hp, 0.0, 1.0)
	var bar_y := -top - 10.0
	draw_rect(Rect2(-size.x / 2.0, bar_y, size.x, 5.0), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-size.x / 2.0, bar_y, size.x * f, 5.0), Color(1.0 - f, f, 0.15))
	# Production progress
	if not constructing and not queue.is_empty():
		var bar := Rect2(-size.x / 2.0 + 10.0, size.y / 2.0 + 4.0, size.x - 20.0, 5.0)
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * prod_progress, bar.size.y)), Color(1.0, 0.85, 0.2))


## Fire and smoke on badly damaged buildings.
func _draw_damage(top: float) -> void:
	var f := hp / max_hp
	if constructing or f > 0.6:
		return
	var spots := 1 if f > 0.35 else 3
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	var t: float = game.elapsed
	for i in spots:
		var p := Vector2(rng.randf_range(-0.35, 0.35) * size.x, -top * 0.45 + rng.randf_range(-0.2, 0.3) * size.y)
		for j in 3:  # rising smoke puffs
			var k := fposmod(t * 0.6 + j / 3.0 + i * 0.17, 1.0)
			draw_circle(p + Vector2(k * 12.0, -k * 44.0), 7.0 + k * 13.0, Color(0.1, 0.1, 0.1, 0.6 * (1.0 - k)))
		var flick := 0.75 + 0.25 * sin(t * 17.0 + i * 2.1)
		draw_circle(p, 11.0 * flick, Color(1.0, 0.3, 0.05, 0.8))
		draw_circle(p + Vector2(0, -3), 6.0 * flick, Color(1.0, 0.85, 0.3, 0.95))
