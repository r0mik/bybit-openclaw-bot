extends Node2D
## Game controller: map, player input, selection, orders, combat, collisions.

const Defs = preload("res://scripts/defs.gd")
const UnitScript = preload("res://scripts/unit.gd")
const BuildingScript = preload("res://scripts/building.gd")
const MineralScript = preload("res://scripts/mineral.gd")
const AIScript = preload("res://scripts/ai.gd")
const HUDScript = preload("res://scripts/hud.gd")

const MAP_SIZE := Vector2(4000, 3000)
const CELL := 48.0
const PLAYER := 0
const ENEMY := 1
const TEAM_COLORS := [Color(0.25, 0.55, 1.0), Color(0.95, 0.28, 0.22)]

var map_size := MAP_SIZE
var bank := [50, 50]
var upgrades := [{"weapons": 0, "armor": 0}, {"weapons": 0, "armor": 0}]
var entities: Node2D
var overlay: Node2D
var camera: Camera2D
var hud
var ais: Array = []
var selection: Array = []
var control_groups := {}
var last_group_key := -1
var last_group_time := 0.0
var dragging := false
var drag_start := Vector2.ZERO
var placing := ""
var attack_mode := false
var markers: Array = []
var effects: Array = []
var game_over := false
var elapsed := 0.0
var win_check := 1.0
var start_positions := [Vector2(450, 450), Vector2(3550, 2550)]
var autotest := false
var building_textures := {}
var mineral_textures: Array = []
var unit_textures := {}
var sprite_meta := {}
var sprite_res := 2.0
var sprite_dirs := 16
var ground_texture: Texture2D
var report_timer := 0.0


func _ready() -> void:
	randomize()
	_load_textures()
	autotest = "--autotest" in OS.get_cmdline_user_args()
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	overlay = Node2D.new()
	overlay.z_index = 100
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_setup_map()
	hud = HUDScript.new()
	add_child(hud)
	hud.setup(self)
	_add_ai(ENEMY)
	if autotest:
		_add_ai(PLAYER)  # AI vs AI to exercise every system
	camera.position = start_positions[PLAYER] + Vector2(300, 150)
	show_message("Добывай минералы, строй армию и уничтожь красную базу!")


func _load_textures() -> void:
	sprite_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites.json"))
	sprite_res = float(sprite_meta.res)
	sprite_dirs = int(sprite_meta.dirs)
	for kind in Defs.UNITS:
		for t in [PLAYER, ENEMY]:
			unit_textures["%s_%d" % [kind, t]] = load("res://assets/units/%s_%d.png" % [kind, t])
	for kind in Defs.BUILDINGS:
		for t in [PLAYER, ENEMY]:
			building_textures["%s_%d" % [kind, t]] = load("res://assets/buildings/%s_%d.png" % [kind, t])
	for v in 3:
		mineral_textures.append(load("res://assets/minerals/minerals_%d.png" % v))
	ground_texture = load("res://assets/terrain/ground.png")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func building_texture(kind: String, t: int) -> Texture2D:
	return building_textures["%s_%d" % [kind, t]]


func unit_texture(kind: String, t: int) -> Texture2D:
	return unit_textures["%s_%d" % [kind, t]]


## Height of the sprite above the ground anchor, in game pixels.
func unit_top(kind: String) -> float:
	return float(sprite_meta.units[kind].top)


func building_top(kind: String) -> float:
	return float(sprite_meta.buildings[kind].top)


func mineral_texture(v: int) -> Texture2D:
	return mineral_textures[v]


func _add_ai(t: int) -> void:
	var ai = AIScript.new()
	ai.game = self
	ai.team = t
	add_child(ai)
	ais.append(ai)


# --- Map --------------------------------------------------------------------

func _setup_map() -> void:
	for t in [PLAYER, ENEMY]:
		var base: Vector2 = start_positions[t]
		_spawn_mineral_field(base)
		spawn_building(t, "cc", base, false)
		for i in 4:
			spawn_unit(t, "worker", base + Vector2(-40 + i * 27, 85))
	for pos in [Vector2(450, 2550), Vector2(3550, 450), Vector2(2000, 1500)]:
		_spawn_mineral_field(pos)
	for u in get_tree().get_nodes_in_group("units"):
		u.order_gather(best_mineral(u.position))


func _spawn_mineral_field(center: Vector2) -> void:
	var to_center := MAP_SIZE / 2.0 - center
	var dir := Vector2.UP if to_center.length() < 10.0 else -to_center.normalized()
	for i in 8:
		var ang := deg_to_rad(-63.0 + i * 18.0)
		spawn_mineral(center + dir.rotated(ang) * 250.0)


func spawn_unit(t: int, kind: String, pos: Vector2):
	var u = UnitScript.new()
	u.position = pos
	u.setup(self, t, kind)
	entities.add_child(u)
	return u


func spawn_building(t: int, kind: String, pos: Vector2, constructing: bool):
	var b = BuildingScript.new()
	b.position = pos
	b.setup(self, t, kind, constructing)
	entities.add_child(b)
	return b


func spawn_mineral(pos: Vector2):
	var m = MineralScript.new()
	m.position = pos
	m.setup(self)
	entities.add_child(m)
	return m


# --- Queries ----------------------------------------------------------------

func valid(e) -> bool:
	return is_instance_valid(e) and e.is_alive()


func team_color(t: int) -> Color:
	return TEAM_COLORS[t]


func team_units(t: int) -> Array:
	var res := []
	for u in get_tree().get_nodes_in_group("units"):
		if u.team == t and u.is_alive():
			res.append(u)
	return res


func team_buildings(t: int) -> Array:
	var res := []
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == t and b.is_alive():
			res.append(b)
	return res


func has_completed(t: int, kind: String) -> bool:
	for b in team_buildings(t):
		if b.kind == kind and b.is_complete():
			return true
	return false


func rect_point_dist(r: Rect2, p: Vector2) -> float:
	var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(c)


func edge_dist(a, b) -> float:
	return maxf(0.0, b.surface_distance(a.position) - a.radius)


func best_mineral(p: Vector2):
	var counts := {}
	for u in get_tree().get_nodes_in_group("units"):
		if u.is_worker() and valid(u.mineral_target) and u.is_mining():
			counts[u.mineral_target] = counts.get(u.mineral_target, 0) + 1
	var best = null
	var best_score := INF
	for m in get_tree().get_nodes_in_group("minerals"):
		if not m.is_alive():
			continue
		var score: float = p.distance_to(m.position) + 70.0 * counts.get(m, 0)
		if score < best_score:
			best_score = score
			best = m
	return best


func nearest_dropoff(t: int, p: Vector2):
	var best = null
	var best_d := INF
	for b in team_buildings(t):
		if b.kind == "cc" and b.is_complete():
			var d := p.distance_to(b.position)
			if d < best_d:
				best_d = d
				best = b
	return best


func find_enemy(u, radius: float):
	var best = null
	var best_score := INF
	for e in get_tree().get_nodes_in_group("units"):
		if e.team == u.team or not e.is_alive() or not u.can_target(e):
			continue
		var d := edge_dist(u, e)
		if d <= radius:
			var score := d + (60.0 if e.is_worker() else 0.0)
			if score < best_score:
				best_score = score
				best = e
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == u.team or not b.is_alive():
			continue
		var d := edge_dist(u, b)
		if d <= radius and d + 200.0 < best_score:
			best_score = d + 200.0
			best = b
	return best


func entity_at(p: Vector2):
	# Sprites stand up from their ground anchor, so also test the body, not only the feet.
	for u in get_tree().get_nodes_in_group("units"):
		if not u.is_alive():
			continue
		var body: Vector2 = u.position + Vector2(0, -unit_top(u.kind) * 0.5)
		if p.distance_to(u.position) <= u.radius + 4.0 or p.distance_to(body) <= u.radius + 4.0:
			return u
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.is_alive() and b.pick_rect().has_point(p):
			return b
	for m in get_tree().get_nodes_in_group("minerals"):
		if m.is_alive() and p.distance_to(m.position) <= m.radius + 4.0:
			return m
	return null


func supply_used(t: int) -> int:
	var n := 0
	for u in team_units(t):
		n += int(u.stats.supply)
	for b in team_buildings(t):
		for item in b.queue:
			if Defs.UNITS.has(item):
				n += int(Defs.UNITS[item].supply)
	return n


func supply_cap(t: int) -> int:
	var n := 0
	for b in team_buildings(t):
		if b.is_complete():
			n += int(b.stats.get("supply", 0))
	return mini(n, Defs.MAX_SUPPLY)


func can_place(kind: String, pos: Vector2, margin := 6.0) -> bool:
	var size: Vector2 = Defs.BUILDINGS[kind].size
	var r := Rect2(pos - size / 2.0, size)
	if r.position.x < 20 or r.position.y < 20 or r.end.x > MAP_SIZE.x - 20 or r.end.y > MAP_SIZE.y - 20:
		return false
	var grown := r.grow(margin)
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.is_alive() and grown.intersects(b.rect()):
			return false
	var gap := 70.0 if kind == "cc" else 16.0
	for m in get_tree().get_nodes_in_group("minerals"):
		if m.is_alive() and rect_point_dist(r, m.position) < m.radius + gap:
			return false
	return true


## Simple obstacle avoidance: slide along buildings and around mineral patches.
func steer_around(u, dir: Vector2, goal: Vector2) -> Vector2:
	if u.is_air():
		return dir
	var ahead: Vector2 = u.position + dir * (u.radius + 14.0)
	for b in get_tree().get_nodes_in_group("buildings"):
		var r: Rect2 = b.rect().grow(u.radius + 1.0)
		if not r.has_point(ahead) or r.has_point(goal):
			continue
		var p: Vector2 = u.position
		if p.x > r.position.x and p.x < r.end.x:
			var sx := signf(goal.x - b.position.x)
			return Vector2(sx if sx != 0.0 else 1.0, 0.0)
		var sy := signf(goal.y - b.position.y)
		return Vector2(0.0, sy if sy != 0.0 else 1.0)
	for m in get_tree().get_nodes_in_group("minerals"):
		var min_d: float = m.radius + u.radius + 2.0
		if ahead.distance_to(m.position) < min_d and goal.distance_to(m.position) > min_d:
			var n: Vector2 = (u.position - m.position).normalized()
			var t := Vector2(-n.y, n.x)
			return t if t.dot(dir) >= 0.0 else -t
	return dir


func snap(p: Vector2) -> Vector2:
	return (p / 20.0).round() * 20.0


# --- Economy & combat -------------------------------------------------------

func add_minerals(t: int, n: int) -> void:
	bank[t] += n


func refund(t: int, n: int) -> void:
	bank[t] += n


func try_train(b, uk: String) -> bool:
	var st: Dictionary = Defs.UNITS[uk]
	if not b.can_train(uk):
		return false
	if bank[b.team] < st.cost:
		if b.team == PLAYER:
			show_message("Недостаточно минералов")
		return false
	if supply_used(b.team) + int(st.supply) > supply_cap(b.team):
		if b.team == PLAYER:
			show_message("Нужно больше Supply Depot (D рабочим)")
		return false
	bank[b.team] -= st.cost
	b.queue.append(uk)
	b.queue_costs.append(st.cost)
	return true


## Next research level for a team, counting research already in progress.
func upgrade_level(t: int, key: String) -> int:
	var n: int = upgrades[t][key]
	for b in team_buildings(t):
		if b.is_researching(key):
			n += 1
	return n


func upgrade_cost(t: int, key: String) -> int:
	var lvl := upgrade_level(t, key)
	var costs: Array = Defs.UPGRADES[key].cost
	return costs[mini(lvl, costs.size() - 1)]


func try_research(b, key: String) -> bool:
	var up: Dictionary = Defs.UPGRADES[key]
	if not b.can_research(key):
		return false
	if upgrade_level(b.team, key) >= up.max:
		if b.team == PLAYER:
			show_message("%s: максимальный уровень" % up.name)
		return false
	var cost := upgrade_cost(b.team, key)
	if bank[b.team] < cost:
		if b.team == PLAYER:
			show_message("Недостаточно минералов")
		return false
	bank[b.team] -= cost
	b.queue.append(key)
	b.queue_costs.append(cost)
	return true


func complete_upgrade(t: int, key: String) -> void:
	upgrades[t][key] += 1
	if t == PLAYER:
		show_message("Исследование завершено: %s +%d" % [Defs.UPGRADES[key].name, upgrades[t][key]])


func item_name(item: String) -> String:
	if Defs.UPGRADES.has(item):
		return "%s +%d" % [Defs.UPGRADES[item].name, upgrades[PLAYER][item] + 1]
	return Defs.UNITS[item].name


func try_order_build(w, kind: String, pos: Vector2) -> bool:
	var st: Dictionary = Defs.BUILDINGS[kind]
	var t: int = w.team
	if st.has("requires") and not has_completed(t, st.requires):
		if t == PLAYER:
			show_message("Сначала нужен %s" % Defs.BUILDINGS[st.requires].name)
		return false
	if bank[t] < st.cost:
		if t == PLAYER:
			show_message("Недостаточно минералов")
		return false
	if not can_place(kind, pos):
		if t == PLAYER:
			show_message("Здесь строить нельзя")
		return false
	bank[t] -= st.cost
	w.order_build(kind, pos)
	return true


func worker_build(w) -> void:
	if can_place(w.build_kind, w.build_pos):
		spawn_building(w.team, w.build_kind, w.build_pos, true)
	else:
		refund(w.team, Defs.BUILDINGS[w.build_kind].cost)
		if w.team == PLAYER:
			show_message("Место занято — строительство отменено")


func on_building_complete(b) -> void:
	if b.team == PLAYER:
		show_message("%s построен" % b.stats.name)


## Weapons upgrades add 20% damage per level, armour removes a flat 1.5 per level.
func scaled_damage(attacker, target, dmg: float) -> float:
	var w: int = upgrades[attacker.team].weapons
	var a: int = upgrades[target.team].armor
	return maxf(dmg * (1.0 + 0.2 * w) - a * 1.5, dmg * 0.4)


func deal_damage(attacker, target, dmg: float, splash: float) -> void:
	if splash > 0.0:
		var center: Vector2 = target.position
		effects.append({"pos": center, "t": 0.0, "r": splash, "color": Color(1.0, 0.6, 0.2)})
		var all: Array = get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("buildings")
		for e in all:
			if e.team != attacker.team and e.is_alive() and attacker.can_target(e) and e.surface_distance(center) <= splash:
				e.take_damage(scaled_damage(attacker, e, dmg if e == target else dmg * 0.5), attacker)
	else:
		target.take_damage(scaled_damage(attacker, target, dmg), attacker)


func kill(e) -> void:
	var big: bool = e.is_in_group("buildings")
	if not e.is_in_group("minerals"):
		effects.append({"pos": e.position, "t": 0.0, "r": 80.0 if big else 26.0, "color": Color(1.0, 0.45, 0.1)})
	selection.erase(e)
	for k in control_groups:
		control_groups[k].erase(e)
	e.queue_free()


# --- Player commands --------------------------------------------------------

func selected_units() -> Array:
	return selection.filter(func(e): return valid(e) and e.is_in_group("units") and e.team == PLAYER)


func selected_buildings() -> Array:
	return selection.filter(func(e): return valid(e) and e.is_in_group("buildings") and e.team == PLAYER)


func set_selection(arr: Array) -> void:
	for e in selection:
		if is_instance_valid(e):
			e.selected = false
	selection = arr.filter(func(e): return valid(e))
	for e in selection:
		e.selected = true


## Commands available for the current selection (used by hotkeys and HUD buttons).
func get_commands() -> Array:
	var cmds := []
	if game_over:
		return cmds
	var units := selected_units()
	var blds := selected_buildings()
	if not units.is_empty():
		cmds.append({"key": KEY_A, "label": "Атака (A)", "fn": cmd_attack})
		cmds.append({"key": KEY_S, "label": "Стоп (S)", "fn": cmd_stop})
		cmds.append({"key": KEY_H, "label": "Держать (H)", "fn": cmd_hold})
		if units.any(func(u): return u.is_worker()):
			for bk in Defs.WORKER_BUILDS:
				var st: Dictionary = Defs.BUILDINGS[bk]
				cmds.append({"key": st.hotkey, "label": "%s (%s) %d" % [st.name, OS.get_keycode_string(st.hotkey), st.cost],
					"fn": func(): start_placing(bk)})
	elif not blds.is_empty():
		var kinds := []
		for b in blds:
			for uk in b.stats.trains:
				if not uk in kinds:
					kinds.append(uk)
		for uk in kinds:
			var st: Dictionary = Defs.UNITS[uk]
			cmds.append({"key": st.hotkey, "label": "%s (%s) %d" % [st.name, OS.get_keycode_string(st.hotkey), st.cost],
				"fn": func(): train_selected(uk)})
		var research := []
		for b in blds:
			for key in b.stats.get("research", []):
				if not key in research:
					research.append(key)
		for key in research:
			var up: Dictionary = Defs.UPGRADES[key]
			var lvl := upgrade_level(PLAYER, key)
			var label := "%s +%d (%s) %d" % [up.name, lvl + 1, OS.get_keycode_string(up.hotkey), upgrade_cost(PLAYER, key)]
			if lvl >= up.max:
				label = "%s: макс." % up.name
			cmds.append({"key": up.hotkey, "label": label, "fn": func(): research_selected(key)})
		if blds.any(func(b): return not b.queue.is_empty()):
			cmds.append({"key": KEY_X, "label": "Отмена (X)", "fn": cmd_cancel})
	return cmds


func cmd_attack() -> void:
	attack_mode = true
	placing = ""


func cmd_stop() -> void:
	for u in selected_units():
		u.order_stop()


func cmd_hold() -> void:
	for u in selected_units():
		u.order_hold()


func cmd_cancel() -> void:
	for b in selected_buildings():
		if not b.queue.is_empty():
			b.cancel_last()
			return


func research_selected(key: String) -> void:
	for b in selected_buildings():
		if b.can_research(key):
			try_research(b, key)
			return


func train_selected(uk: String) -> void:
	var best = null
	for b in selected_buildings():
		if b.can_train(uk) and (best == null or b.queue.size() < best.queue.size()):
			best = b
	if best != null:
		try_train(best, uk)


func start_placing(kind: String) -> void:
	var st: Dictionary = Defs.BUILDINGS[kind]
	if st.has("requires") and not has_completed(PLAYER, st.requires):
		show_message("Сначала нужен %s" % Defs.BUILDINGS[st.requires].name)
		return
	if bank[PLAYER] < st.cost:
		show_message("Недостаточно минералов")
		return
	attack_mode = false
	placing = kind


func _try_place(wp: Vector2, keep: bool) -> void:
	var p := snap(wp)
	var workers := selected_units().filter(func(u): return u.is_worker())
	if workers.is_empty():
		placing = ""
		return
	workers.sort_custom(func(a, b): return a.position.distance_to(p) < b.position.distance_to(p))
	var w = workers[0]
	for cand in workers:
		if cand.build_kind == "":
			w = cand
			break
	if try_order_build(w, placing, p):
		add_marker(p, Color(0.3, 1.0, 0.3))
		if not keep:
			placing = ""


func issue_move(units: Array, p: Vector2, attack := false) -> void:
	var n := units.size()
	var cols := int(ceil(sqrt(n)))
	var rows := int(ceil(float(n) / cols))
	for i in n:
		var off := Vector2((i % cols - (cols - 1) / 2.0) * 28.0, (i / cols - (rows - 1) / 2.0) * 28.0)
		if attack:
			units[i].order_attack_move(p + off)
		else:
			units[i].order_move(p + off)


func _right_click(p: Vector2) -> void:
	var units := selected_units()
	if units.is_empty():
		var blds := selected_buildings()
		for b in blds:
			b.rally = p
			b.has_rally = true
		if not blds.is_empty():
			add_marker(p, Color(1.0, 0.9, 0.3))
		return
	var t = entity_at(p)
	if t != null and t.is_in_group("minerals"):
		var others := []
		for u in units:
			if u.is_worker():
				u.order_gather(t)
			else:
				others.append(u)
		if not others.is_empty():
			issue_move(others, p)
		add_marker(p, Color(0.4, 0.9, 1.0))
	elif t != null and t.team != PLAYER:
		for u in units:
			u.order_attack(t)
		add_marker(p, Color(1.0, 0.25, 0.2))
	elif t != null and t.is_in_group("buildings") and t.kind == "cc":
		var others := []
		for u in units:
			if u.is_worker() and u.carrying > 0:
				u.order_return()
			else:
				others.append(u)
		if not others.is_empty():
			issue_move(others, p)
		add_marker(p, Color(0.3, 1.0, 0.3))
	else:
		issue_move(units, p)
		add_marker(p, Color(0.3, 1.0, 0.3))


func minimap_command(wp: Vector2) -> void:
	var units := selected_units()
	if not units.is_empty():
		issue_move(units, wp, attack_mode)
		attack_mode = false


func add_marker(p: Vector2, c: Color) -> void:
	markers.append({"pos": p, "t": 0.0, "color": c})


func show_message(text: String) -> void:
	if hud != null:
		hud.show_message(text)
	if autotest:
		print("[msg] ", text)


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var wp := get_global_mouse_position()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if placing != "":
						_try_place(wp, event.shift_pressed)
					elif attack_mode:
						var units := selected_units()
						var t = entity_at(wp)
						if t != null and t.team >= 0 and t.team != PLAYER:
							for u in units:
								u.order_attack(t)
						else:
							issue_move(units, wp, true)
						add_marker(wp, Color(1.0, 0.25, 0.2))
						attack_mode = false
					else:
						dragging = true
						drag_start = wp
				elif dragging:
					dragging = false
					_finish_selection(drag_start, wp, event.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if placing != "" or attack_mode:
						placing = ""
						attack_mode = false
					elif not game_over:
						_right_click(wp)
			MOUSE_BUTTON_WHEEL_UP:
				camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.4, 0.4), Vector2(1.6, 1.6))
			MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.4, 0.4), Vector2(1.6, 1.6))
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		camera.position -= event.relative / camera.zoom
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_key(event: InputEventKey) -> void:
	var key := event.keycode
	if game_over and key == KEY_R:
		get_tree().reload_current_scene()
		return
	if key == KEY_ESCAPE:
		placing = ""
		attack_mode = false
		return
	if key >= KEY_1 and key <= KEY_9:
		var n := int(key - KEY_0)
		if event.ctrl_pressed:
			control_groups[n] = selection.duplicate()
			show_message("Группа %d назначена" % n)
		elif control_groups.has(n):
			set_selection(control_groups[n])
			var now := Time.get_ticks_msec() / 1000.0
			if last_group_key == n and now - last_group_time < 0.4 and not selection.is_empty():
				camera.position = selection[0].position
			last_group_key = n
			last_group_time = now
		return
	if key == KEY_SPACE:
		camera.position = start_positions[PLAYER]
		return
	for c in get_commands():
		if c.key == key:
			c["fn"].call()
			return


func _finish_selection(a: Vector2, b: Vector2, add: bool) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	var picked := []
	if r.size.length() < 8.0 / camera.zoom.x:
		var e = entity_at(b)
		if e != null and e.team >= 0:
			picked = [e]
	else:
		for u in team_units(PLAYER):
			if r.grow(u.radius).has_point(u.position):
				picked.append(u)
		if picked.is_empty():
			for bl in team_buildings(PLAYER):
				if r.intersects(bl.pick_rect()):
					picked.append(bl)
	if add:
		var s := selection.filter(func(e): return valid(e) and e.team == PLAYER)
		for p in picked:
			if p.team != PLAYER:
				continue
			if s.has(p):
				s.erase(p)
			else:
				s.append(p)
		set_selection(s)
	else:
		set_selection(picked)


# --- Frame update -----------------------------------------------------------

func _process(delta: float) -> void:
	elapsed += delta
	_update_camera(delta)
	_resolve_collisions()
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		dragging = false
		_finish_selection(drag_start, get_global_mouse_position(), Input.is_key_pressed(KEY_SHIFT))
	for m in markers:
		m.t += delta
	markers = markers.filter(func(m): return m.t < 0.6)
	for e in effects:
		e.t += delta
	effects = effects.filter(func(e): return e.t < 0.45)
	overlay.queue_redraw()
	win_check -= delta
	if win_check <= 0.0 and not game_over:
		win_check = 1.0
		if team_buildings(PLAYER).is_empty():
			game_over = true
			hud.show_big("ПОРАЖЕНИЕ", Color(1.0, 0.3, 0.25))
			if autotest:
				print("[result] RED wins at %.0fs" % elapsed)
		elif team_buildings(ENEMY).is_empty():
			game_over = true
			hud.show_big("ПОБЕДА!", Color(0.4, 1.0, 0.4))
			if autotest:
				print("[result] BLUE wins at %.0fs" % elapsed)
	if autotest:
		_autotest_screenshot()
		report_timer -= delta
		if report_timer <= 0.0:
			report_timer = 30.0
			for t in [PLAYER, ENEMY]:
				var counts := {}
				for u in team_units(t):
					counts[u.kind] = counts.get(u.kind, 0) + 1
				var bcounts := {}
				for b in team_buildings(t):
					bcounts[b.kind] = bcounts.get(b.kind, 0) + 1
				print("[%4.0fs] team %d: minerals=%d supply=%d/%d units=%s buildings=%s" % [
					elapsed, t, bank[t], supply_used(t), supply_cap(t), counts, bcounts])


## Debug helper: `-- --autotest --screenshot=<path> --shot-time=<sec>` saves one frame.
func _autotest_screenshot() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--screenshot="):
			continue
		var at := 240.0
		for a2 in OS.get_cmdline_user_args():
			if a2.begins_with("--shot-time="):
				at = float(a2.trim_prefix("--shot-time="))
		if elapsed >= at and not has_meta("shot_done"):
			set_meta("shot_done", true)
			var army := team_units(PLAYER).filter(func(u): return not u.is_worker())
			set_selection(army)
			camera.position = start_positions[PLAYER] + Vector2(350, 200)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshot="))
			print("[shot] saved")


func _update_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if DisplayServer.window_is_focused() and not autotest:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		var edge := 12.0
		if mp.x >= 0 and mp.y >= 0 and mp.x <= vs.x and mp.y <= vs.y:
			if mp.x < edge: dir.x -= 1
			if mp.x > vs.x - edge: dir.x += 1
			if mp.y < edge: dir.y -= 1
			if mp.y > vs.y - edge: dir.y += 1
	camera.position += dir.normalized() * 1100.0 * delta / camera.zoom.x
	camera.position = camera.position.clamp(Vector2.ZERO, MAP_SIZE)


func _resolve_collisions() -> void:
	var units := get_tree().get_nodes_in_group("units")
	var grid := {}
	for u in units:
		var k := Vector2i(floori(u.position.x / CELL), floori(u.position.y / CELL))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(u)
	for u in units:
		if not u.is_alive():
			continue
		# Mining workers pass through other units, like in StarCraft.
		var ghost: bool = u.is_worker() and u.is_mining()
		if not ghost:
			var c := Vector2i(floori(u.position.x / CELL), floori(u.position.y / CELL))
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var cell = grid.get(c + Vector2i(dx, dy))
					if cell == null:
						continue
					for o in cell:
						if o == u or o.get_instance_id() < u.get_instance_id() or not o.is_alive():
							continue
						if (o.is_worker() and o.is_mining()) or o.is_air() != u.is_air():
							continue
						var diff: Vector2 = u.position - o.position
						var min_d: float = u.radius + o.radius
						var d := diff.length()
						if d < min_d:
							var n := diff / d if d > 0.01 else Vector2.RIGHT.rotated(randf() * TAU)
							var push := (min_d - d) * 0.5
							u.position += n * push
							o.position -= n * push
		if u.is_air():
			u.position = u.position.clamp(Vector2(10, 10), MAP_SIZE - Vector2(10, 10))
			continue
		for b in get_tree().get_nodes_in_group("buildings"):
			var r: Rect2 = b.rect().grow(u.radius)
			if r.has_point(u.position):
				var p: Vector2 = u.position
				var dl := p.x - r.position.x
				var dr := r.end.x - p.x
				var dt := p.y - r.position.y
				var db := r.end.y - p.y
				var m := minf(minf(dl, dr), minf(dt, db))
				if m == dl: p.x = r.position.x
				elif m == dr: p.x = r.end.x
				elif m == dt: p.y = r.position.y
				else: p.y = r.end.y
				u.position = p
		for mn in get_tree().get_nodes_in_group("minerals"):
			var diff: Vector2 = u.position - mn.position
			var min_d: float = u.radius + mn.radius
			if diff.length_squared() < min_d * min_d:
				var d := diff.length()
				var n := diff / d if d > 0.01 else Vector2.DOWN
				u.position = mn.position + n * min_d
		u.position = u.position.clamp(Vector2(10, 10), MAP_SIZE - Vector2(10, 10))


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_texture_rect(ground_texture, Rect2(Vector2.ZERO, MAP_SIZE), true)
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.5, 0.5, 0.45), false, 4.0)


func _draw_overlay() -> void:
	var mp := get_global_mouse_position()
	for u in selected_units():
		if u.state == UnitScript.State.MOVE or u.state == UnitScript.State.ATTACK_MOVE:
			var c := Color(0.3, 1.0, 0.3, 0.25) if u.state == UnitScript.State.MOVE else Color(1.0, 0.3, 0.2, 0.25)
			overlay.draw_line(u.position, u.target_pos, c, 1.0)
	for b in selected_buildings():
		if b.has_rally:
			overlay.draw_line(b.position, b.rally, Color(1.0, 0.9, 0.3, 0.5), 1.5)
			overlay.draw_circle(b.rally, 5.0, Color(1.0, 0.9, 0.3, 0.8))
	if dragging:
		var r := Rect2(drag_start, Vector2.ZERO).expand(mp)
		overlay.draw_rect(r, Color(0.3, 1.0, 0.3, 0.12), true)
		overlay.draw_rect(r, Color(0.3, 1.0, 0.3, 0.9), false, 1.5)
	if placing != "":
		var size: Vector2 = Defs.BUILDINGS[placing].size
		var p := snap(mp)
		var ok := can_place(placing, p)
		var c := Color(0.2, 1.0, 0.2, 0.35) if ok else Color(1.0, 0.2, 0.2, 0.35)
		overlay.draw_rect(Rect2(p - size / 2.0, size), c, true)
		var tex := building_texture(placing, PLAYER)
		var ts := tex.get_size() / sprite_res
		overlay.draw_texture_rect(tex, Rect2(p - ts / 2.0, ts), false,
				Color(0.7, 1.0, 0.7, 0.6) if ok else Color(1.0, 0.5, 0.5, 0.6))
		overlay.draw_rect(Rect2(p - size / 2.0, size), Color(c, 0.9), false, 2.0)
	if attack_mode:
		var c := Color(1.0, 0.25, 0.2)
		overlay.draw_arc(mp, 12.0, 0.0, TAU, 24, c, 2.0)
		overlay.draw_line(mp + Vector2(-18, 0), mp + Vector2(18, 0), c, 1.5)
		overlay.draw_line(mp + Vector2(0, -18), mp + Vector2(0, 18), c, 1.5)
	for m in markers:
		var k: float = 1.0 - m.t / 0.6
		overlay.draw_arc(m.pos, 4.0 + 14.0 * k, 0.0, TAU, 24, Color(m.color, k), 2.0)
	for e in effects:
		var k: float = e.t / 0.45
		overlay.draw_circle(e.pos, e.r * (0.3 + 0.7 * k), Color(e.color, 0.6 * (1.0 - k)))
