extends Node
## Simple computer opponent: economy, supply, production, attack waves.

const Defs = preload("res://scripts/defs.gd")

var game
var team := 1
var think_timer := 1.0
var wave_size := 6
var elapsed := 0.0
var reserve := 0  # minerals held back for the next planned building


func _process(delta: float) -> void:
	elapsed += delta
	think_timer -= delta
	if think_timer > 0.0 or game.game_over:
		return
	think_timer = 0.6
	_think()


func _think() -> void:
	var units: Array = game.team_units(team)
	var buildings: Array = game.team_buildings(team)
	var cc = null
	for b in buildings:
		if b.kind == "cc" and b.is_complete():
			cc = b
			break
	var workers := []
	var army := []
	for u in units:
		if u.is_worker():
			workers.append(u)
		else:
			army.append(u)
	if cc != null:
		_economy(cc, workers, buildings)
	_military(cc, army, buildings)


func _count(kind: String, buildings: Array, workers: Array) -> int:
	var n := 0
	for b in buildings:
		if b.kind == kind:
			n += 1
	for w in workers:
		if w.build_kind == kind:
			n += 1
	return n


func _economy(cc, workers: Array, buildings: Array) -> void:
	for w in workers:
		if w.is_idle():
			w.order_gather(game.best_mineral(w.position))
	var used: int = game.supply_used(team)
	var cap: int = game.supply_cap(team)
	var pending_depots := 0
	for b in buildings:
		if b.kind == "depot" and b.constructing:
			pending_depots += 1
	for w in workers:
		if w.build_kind == "depot":
			pending_depots += 1
	if cap < Defs.MAX_SUPPLY and used + 4 >= cap + pending_depots * 8:
		if game.bank[team] >= 100:
			_build("depot", cc, workers)
		return  # save up for the depot
	if workers.size() + cc.queue.size() < 18 and cc.queue.is_empty():
		game.try_train(cc, "worker")
	# Tech/defence build order: first entry whose conditions hold gets built.
	var rax := _count("barracks", buildings, workers)
	var plan := [
		["barracks", rax < 3 and elapsed > 25.0 + rax * 70.0],
		["bunker", _count("bunker", buildings, workers) < 1 and elapsed > 110.0 and game.has_completed(team, "barracks")],
		["factory", _count("factory", buildings, workers) == 0 and elapsed > 160.0 and game.has_completed(team, "barracks")],
		["ebay", _count("ebay", buildings, workers) == 0 and elapsed > 200.0],
		["turret", _count("turret", buildings, workers) < 2 and game.has_completed(team, "ebay")],
		["starport", _count("starport", buildings, workers) == 0 and elapsed > 280.0 and game.has_completed(team, "factory")],
	]
	reserve = 0
	for entry in plan:
		if entry[1]:
			var cost: int = Defs.BUILDINGS[entry[0]].cost
			if game.bank[team] >= cost:
				_build(entry[0], cc, workers)
			else:
				reserve = cost
			break


func _build(kind: String, cc, workers: Array) -> bool:
	if workers.is_empty():
		return false
	var spot = _find_spot(kind, cc.position)
	if spot == null:
		return false
	var w = null
	for cand in workers:
		if cand.build_kind == "" and cand.carrying == 0:
			w = cand
			break
	if w == null:
		w = workers[0]
	return game.try_order_build(w, kind, spot)


func _find_spot(kind: String, center: Vector2):
	var toward: Vector2 = (game.map_size / 2.0 - center).normalized()
	var defensive: bool = kind == "bunker" or kind == "turret"
	for i in 120:
		var ang := randf_range(-0.6, 0.6) if defensive else randf_range(-1.6, 1.6)
		var far := i / 40 * 120.0  # widen the search ring when the base gets crowded
		var dist := randf_range(380.0, 520.0) if defensive else randf_range(170.0, 430.0 + far)
		var p: Vector2 = game.snap(center + toward.rotated(ang) * dist)
		if game.can_place(kind, p, 45.0):  # leave walkways between AI buildings
			return p
	return null


func _military(cc, army: Array, buildings: Array) -> void:
	for b in buildings:
		if not b.is_complete() or game.bank[team] - reserve < 50:
			continue
		if b.kind == "barracks" and b.queue.size() < 2:
			game.try_train(b, "marine")
		elif b.kind == "factory" and b.queue.size() < 1:
			game.try_train(b, "tank")
		elif b.kind == "starport" and b.queue.size() < 1:
			game.try_train(b, "wraith")
		elif b.kind == "ebay" and b.queue.is_empty() and game.bank[team] >= 250:
			if not game.try_research(b, "weapons"):
				game.try_research(b, "armor")
	if army.is_empty():
		return
	var home: Vector2 = cc.position if cc != null else army[0].position
	var threat = _threat_near(home, 800.0)
	if threat != null:
		for a in army:
			if a.is_idle() and a.position.distance_to(home) < 1200.0:
				a.order_attack_move(threat.position)
		return
	if army.size() >= wave_size:
		var tgt = _enemy_target(home)
		if tgt != null:
			for a in army:
				a.order_attack_move(tgt.position)
			wave_size = mini(wave_size + 4, 40)
		return
	# Units already out on the field keep pushing towards the next target.
	for a in army:
		if a.is_idle() and a.position.distance_to(home) > 900.0:
			var tgt = _enemy_target(a.position)
			if tgt != null:
				a.order_attack_move(tgt.position)


func _threat_near(p: Vector2, r: float):
	for u in game.get_tree().get_nodes_in_group("units"):
		if u.team != team and u.is_alive() and u.position.distance_to(p) < r:
			return u
	return null


func _enemy_target(from: Vector2):
	var best = null
	var best_d := INF
	for b in game.get_tree().get_nodes_in_group("buildings"):
		if b.team != team and b.is_alive():
			var d := from.distance_to(b.position)
			if d < best_d:
				best_d = d
				best = b
	if best == null:
		for u in game.get_tree().get_nodes_in_group("units"):
			if u.team != team and u.is_alive():
				return u
	return best
