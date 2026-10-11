extends CanvasLayer
## On-screen interface: resources, selection info, command buttons, minimap.

const Defs = preload("res://scripts/defs.gd")
const MinimapScript = preload("res://scripts/minimap.gd")

var game
var res_label: Label
var info_label: Label
var cmd_grid: GridContainer
var msg_label: Label
var msg_time := 0.0
var big_label: Label
var minimap
var cmd_signature := ""


func setup(g) -> void:
	game = g
	# Top bar
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_bottom = 32.0
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var top_box := HBoxContainer.new()
	top.add_child(top_box)
	res_label = Label.new()
	res_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_label.add_theme_font_size_override("font_size", 18)
	top_box.add_child(res_label)
	var help := Label.new()
	help.text = "ЛКМ — выбор   ПКМ — приказ   A — атака   Ctrl+1..9 — группы   Space — база   "
	help.modulate = Color(1, 1, 1, 0.6)
	top_box.add_child(help)
	# Message line
	msg_label = Label.new()
	msg_label.anchor_right = 1.0
	msg_label.offset_top = 40.0
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 20)
	msg_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.add_theme_constant_override("outline_size", 4)
	add_child(msg_label)
	# Bottom panel
	var bottom := PanelContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_top = -196.0
	bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bottom)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	bottom.add_child(box)
	minimap = MinimapScript.new()
	minimap.game = game
	box.add_child(minimap)
	info_label = Label.new()
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.custom_minimum_size = Vector2(380, 0)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 16)
	box.add_child(info_label)
	cmd_grid = GridContainer.new()
	cmd_grid.columns = 4
	cmd_grid.custom_minimum_size = Vector2(720, 0)
	box.add_child(cmd_grid)
	# Big centered text (victory / defeat)
	big_label = Label.new()
	big_label.anchor_right = 1.0
	big_label.anchor_bottom = 1.0
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_label.add_theme_font_size_override("font_size", 72)
	big_label.add_theme_color_override("font_outline_color", Color.BLACK)
	big_label.add_theme_constant_override("outline_size", 10)
	big_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(big_label)


func show_message(text: String) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_time = 3.0


func show_big(text: String, color: Color) -> void:
	big_label.text = text + "\n[R] — заново"
	big_label.add_theme_color_override("font_color", color)


func _process(delta: float) -> void:
	if game == null:
		return
	var t := int(game.elapsed)
	res_label.text = "   Минералы: %d      Supply: %d / %d      Оружие +%d  Броня +%d      Время: %d:%02d" % [
		game.bank[0], game.supply_used(0), game.supply_cap(0), game.upgrades[0].weapons, game.upgrades[0].armor, t / 60, t % 60]
	msg_time -= delta
	msg_label.modulate.a = clampf(msg_time, 0.0, 1.0)
	_update_info()
	_update_commands()


func _update_info() -> void:
	var sel: Array = game.selection.filter(func(e): return game.valid(e))
	if sel.is_empty():
		info_label.text = "Ничего не выбрано.\n\nВыдели рабочих (SCV) и строй здания,\nвыдели Command Center / Barracks и нанимай юнитов."
		return
	if sel.size() == 1:
		var e = sel[0]
		var owner_str := "Ваш" if e.team == 0 else "Противник"
		var txt := ""
		if e.is_in_group("units"):
			txt = "%s — %s\nHP: %d / %d\nУрон: %d   Дальность: %d" % [e.stats.name, owner_str, ceil(e.hp), e.max_hp, e.stats.damage, e.stats.range]
			if e.carrying > 0:
				txt += "\nНесёт минералы: %d" % e.carrying
		else:
			txt = "%s — %s\nHP: %d / %d" % [e.stats.name, owner_str, ceil(e.hp), e.max_hp]
			if e.constructing:
				txt += "\nСтроится: %d%%" % int(e.build_progress * 100.0)
			elif not e.queue.is_empty():
				txt += "\nПроизводство: %s %d%%" % [game.item_name(e.queue[0]), int(e.prod_progress * 100.0)]
				if e.queue.size() > 1:
					txt += "  (+%d в очереди)" % (e.queue.size() - 1)
			if e.stats.has("damage"):
				txt += "\nОборона: урон %d, дальность %d" % [e.stats.damage, e.stats.range]
			if e.stats.has("research"):
				txt += "\nУлучшения: Оружие +%d, Броня +%d" % [game.upgrades[e.team].weapons, game.upgrades[e.team].armor]
			if e.team == 0 and not e.stats.trains.is_empty():
				txt += "\nПКМ — точка сбора"
		info_label.text = txt
		return
	var counts := {}
	for e in sel:
		var n: String = e.stats.name
		counts[n] = counts.get(n, 0) + 1
	var lines := ["Выбрано: %d" % sel.size()]
	for n in counts:
		lines.append("  %s × %d" % [n, counts[n]])
	info_label.text = "\n".join(lines)


func _update_commands() -> void:
	var cmds: Array = game.get_commands()
	var labels := []
	for c in cmds:
		labels.append(c.label)
	var sig := "|".join(labels)
	if sig == cmd_signature:
		return
	cmd_signature = sig
	for child in cmd_grid.get_children():
		child.queue_free()
	for c in cmds:
		var b := Button.new()
		b.text = c.label
		b.custom_minimum_size = Vector2(178, 40)
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(c["fn"])
		cmd_grid.add_child(b)
