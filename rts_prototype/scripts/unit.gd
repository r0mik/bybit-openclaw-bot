extends Node2D
## A mobile unit: worker, marine or tank. Logic is a simple state machine.

const Defs = preload("res://scripts/defs.gd")

enum State { IDLE, MOVE, ATTACK, ATTACK_MOVE, HOLD, GATHER, RETURN, BUILD }

var game
var team := 0
var kind := "marine"
var stats: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var radius := 10.0
var speed := 100.0
var state: int = State.IDLE
var target_pos := Vector2.ZERO
var target = null
var mineral_target = null
var carrying := 0
var mine_timer := 0.0
var build_kind := ""
var build_pos := Vector2.ZERO
var cooldown_left := 0.0
var acquire_timer := 0.0
var shot_flash := 0.0
var shot_to := Vector2.ZERO
var facing := 0.0
var selected := false
var last_dist := INF
var stuck_time := 0.0
var build_timer := 0.0


func setup(g, t: int, k: String) -> void:
	game = g
	team = t
	kind = k
	stats = Defs.UNITS[k]
	max_hp = stats.hp
	hp = max_hp
	radius = stats.radius
	speed = stats.speed
	acquire_timer = randf() * 0.3
	facing = randf() * TAU
	add_to_group("units")


func is_alive() -> bool:
	return hp > 0.0


func is_worker() -> bool:
	return kind == "worker"


func is_idle() -> bool:
	return state == State.IDLE


func is_mining() -> bool:
	return state == State.GATHER or state == State.RETURN


func surface_distance(p: Vector2) -> float:
	return maxf(0.0, p.distance_to(position) - radius)


func take_damage(amount: float, attacker) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		game.kill(self)
		return
	# Idle combat units fight back.
	if not is_worker() and state == State.IDLE and game.valid(attacker) and not game.valid(target):
		target = attacker


# --- Orders -----------------------------------------------------------------

func _reset_order() -> void:
	if state == State.BUILD and build_kind != "":
		game.refund(team, Defs.BUILDINGS[build_kind].cost)
	build_kind = ""
	target = null
	last_dist = INF
	stuck_time = 0.0


func order_move(p: Vector2) -> void:
	_reset_order()
	state = State.MOVE
	target_pos = p


func order_attack_move(p: Vector2) -> void:
	_reset_order()
	state = State.ATTACK_MOVE
	target_pos = p


func order_attack(t) -> void:
	_reset_order()
	state = State.ATTACK
	target = t


func order_stop() -> void:
	_reset_order()
	state = State.IDLE


func order_hold() -> void:
	_reset_order()
	state = State.HOLD


func order_gather(m) -> void:
	if not is_worker() or not game.valid(m):
		return
	_reset_order()
	mineral_target = m
	state = State.RETURN if carrying > 0 else State.GATHER


func order_return() -> void:
	if not is_worker() or carrying <= 0:
		return
	_reset_order()
	state = State.RETURN


func order_build(k: String, p: Vector2) -> void:
	_reset_order()
	state = State.BUILD
	build_kind = k
	build_pos = p
	build_timer = 0.0


# --- Behaviour --------------------------------------------------------------

func _process(delta: float) -> void:
	if hp <= 0.0:
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	shot_flash = maxf(0.0, shot_flash - delta)
	acquire_timer -= delta
	match state:
		State.IDLE:
			_do_idle(delta)
		State.HOLD:
			_do_hold()
		State.MOVE:
			if _move_to(target_pos, delta, 4.0):
				state = State.IDLE
		State.ATTACK:
			if game.valid(target):
				_engage(target, delta, true)
			else:
				target = null
				state = State.IDLE
		State.ATTACK_MOVE:
			_do_attack_move(delta)
		State.GATHER:
			_do_gather(delta)
		State.RETURN:
			_do_return(delta)
		State.BUILD:
			_do_build(delta)
	queue_redraw()


func _do_idle(delta: float) -> void:
	if is_worker():
		return
	if game.valid(target) and game.edge_dist(self, target) <= stats.sight * 1.3:
		_engage(target, delta, true)
		return
	target = null
	if acquire_timer <= 0.0:
		acquire_timer = 0.3
		target = game.find_enemy(self, stats.sight)


func _do_hold() -> void:
	if not game.valid(target) or game.edge_dist(self, target) > stats.range:
		target = null
		if acquire_timer <= 0.0:
			acquire_timer = 0.25
			target = game.find_enemy(self, stats.range)
	if target != null:
		_engage(target, 0.0, false)


func _do_attack_move(delta: float) -> void:
	if game.valid(target) and game.edge_dist(self, target) <= stats.sight * 1.3:
		_engage(target, delta, true)
		return
	target = null
	if acquire_timer <= 0.0:
		acquire_timer = 0.25
		target = game.find_enemy(self, stats.sight)
		if target != null:
			return
	if _move_to(target_pos, delta, 6.0):
		state = State.IDLE


func _engage(t, delta: float, can_chase: bool) -> void:
	var d: float = game.edge_dist(self, t)
	if d <= stats.range:
		facing = (t.position - position).angle()
		if cooldown_left <= 0.0:
			cooldown_left = stats.cooldown
			shot_flash = 0.08
			shot_to = t.position
			game.deal_damage(self, t, float(stats.damage), float(stats.get("splash", 0.0)))
	elif can_chase:
		_move_to(t.position, delta, 0.0)


func _do_gather(delta: float) -> void:
	if carrying > 0:
		state = State.RETURN
		return
	if not game.valid(mineral_target):
		mineral_target = game.best_mineral(position)
		if mineral_target == null:
			state = State.IDLE
			return
	if game.edge_dist(self, mineral_target) > 5.0:
		_move_to(mineral_target.position, delta, 0.0)
		mine_timer = 0.0
		return
	facing = (mineral_target.position - position).angle()
	mine_timer += delta
	if mine_timer >= 2.2:
		mine_timer = 0.0
		carrying = mineral_target.take(5)
		state = State.RETURN


func _do_return(delta: float) -> void:
	var cc = game.nearest_dropoff(team, position)
	if cc == null:
		state = State.IDLE
		return
	if game.edge_dist(self, cc) > 6.0:
		_move_to(cc.position, delta, 0.0)
		return
	game.add_minerals(team, carrying)
	carrying = 0
	state = State.GATHER


func _do_build(delta: float) -> void:
	var size: Vector2 = Defs.BUILDINGS[build_kind].size
	var r := Rect2(build_pos - size / 2.0, size)
	if game.rect_point_dist(r, position) > radius + 10.0:
		build_timer += delta
		if build_timer > 30.0:  # can't get there: give up and refund
			order_stop()
			return
		_move_to(build_pos, delta, 0.0)
		return
	game.worker_build(self)
	build_kind = ""
	mineral_target = null
	state = State.GATHER


## Moves towards p. Returns true when arrived (or stuck close to the goal in a crowd).
func _move_to(p: Vector2, delta: float, arrive: float) -> bool:
	var to := p - position
	var dist := to.length()
	if dist <= maxf(arrive, 0.01):
		return true
	if dist >= last_dist - speed * delta * 0.25:
		stuck_time += delta
	else:
		stuck_time = 0.0
	last_dist = dist
	if arrive > 0.0 and stuck_time > 0.7 and dist < 80.0:
		stuck_time = 0.0
		return true
	var step := minf(speed * delta, dist)
	var dir: Vector2 = game.steer_around(self, to / dist, p)
	position += dir * step
	facing = dir.angle()
	return false


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var col: Color = game.team_color(team)
	if selected:
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 32, Color(0.3, 1.0, 0.3), 2.0)
	var dir := Vector2.RIGHT.rotated(facing)
	match kind:
		"worker":
			draw_circle(Vector2.ZERO, radius, col.darkened(0.15))
			draw_circle(Vector2.ZERO, radius * 0.55, Color(0.95, 0.75, 0.3))
			draw_line(dir * radius * 0.4, dir * (radius + 5.0), Color(0.8, 0.8, 0.8), 3.0)
		"marine":
			draw_circle(Vector2.ZERO, radius, col)
			draw_circle(Vector2.ZERO, radius * 0.5, col.lightened(0.4))
			draw_line(Vector2.ZERO, dir * (radius + 7.0), Color(0.2, 0.2, 0.2), 3.0)
		"tank":
			var pts := PackedVector2Array()
			for c in [Vector2(-1.1, -0.75), Vector2(1.1, -0.75), Vector2(1.1, 0.75), Vector2(-1.1, 0.75)]:
				pts.append((c * radius).rotated(facing))
			draw_colored_polygon(pts, col.darkened(0.3))
			draw_circle(Vector2.ZERO, radius * 0.6, col)
			draw_line(Vector2.ZERO, dir * (radius + 16.0), Color(0.15, 0.15, 0.15), 5.0)
	if carrying > 0:
		draw_circle(Vector2(0, -radius - 3.0), 4.0, Color(0.4, 0.9, 1.0))
	if shot_flash > 0.0:
		draw_line(dir * (radius + 6.0), to_local(shot_to), Color(1.0, 0.95, 0.5), 2.0)
	if selected or hp < max_hp:
		var w := radius * 2.4
		var y := -radius - 10.0
		var f := clampf(hp / max_hp, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, y, w, 4.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w / 2.0, y, w * f, 4.0), Color(1.0 - f, f, 0.15))
