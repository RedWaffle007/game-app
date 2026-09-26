class_name TouchControls
extends Control

var slots: Dictionary = {}
var labels: Dictionary = {}
var fingers: Dictionary = {}
var continue_mode := ""
var pressed_jump := false
var pressed_dash := false
var pressed_continue := false
var pressed_action: Dictionary = {}


func configure(view_size: Vector2, safe_area: Rect2) -> void:
	var bounds := safe_area.intersection(Rect2(Vector2.ZERO, view_size))
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		bounds = Rect2(Vector2.ZERO, view_size)
	var scale := minf(bounds.size.x / 1280.0, bounds.size.y / 720.0)
	var left := bounds.position.x
	var right := bounds.end.x
	var bottom := bounds.end.y
	var pad := Vector2(left + 145 * scale, bottom - 145 * scale)
	var attack := Vector2(right - 210 * scale, bottom - 145 * scale)
	slots = {
		"left": _slot(pad + Vector2(-75, 0) * scale, 43 * scale, "◀"),
		"right": _slot(pad + Vector2(75, 0) * scale, 43 * scale, "▶"),
		"up": _slot(pad + Vector2(0, -75) * scale, 43 * scale, "JUMP"),
		"down": _slot(pad + Vector2(0, 75) * scale, 43 * scale, "DUCK"),
		"dash": _slot(pad + Vector2(155, 65) * scale, 43 * scale, "DASH"),
		"basic": _slot(attack, 60 * scale, "HIT"),
		"shield": _slot(attack + Vector2(140, 93) * scale, 43 * scale, "SHIELD"),
		"move_0": _slot(attack + Vector2(-125, -115) * scale, 43 * scale, "1"),
		"move_1": _slot(attack + Vector2(-45, -175) * scale, 43 * scale, "2"),
		"move_2": _slot(attack + Vector2(45, -175) * scale, 43 * scale, "3"),
		"move_3": _slot(attack + Vector2(125, -115) * scale, 43 * scale, "4"),
		"continue": _slot(bounds.get_center(), 84 * scale, continue_mode),
	}
	for slot_name: String in slots:
		if not labels.has(slot_name):
			var label := Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(label)
			labels[slot_name] = label
		var label: Label = labels[slot_name]
		var slot: Dictionary = slots[slot_name]
		var radius: float = slot["radius"]
		label.position = slot["center"] - Vector2(radius, radius)
		label.size = Vector2(radius * 2, radius * 2)
		label.text = slot["caption"]
		label.add_theme_font_size_override("font_size", maxi(11, int(17 * scale)))
		label.visible = slot_name == "continue" if continue_mode != "" else slot_name != "continue"
	queue_redraw()


func set_continue_mode(mode: String) -> void:
	if continue_mode == mode:
		return
	continue_mode = mode
	if slots.has("continue"):
		slots["continue"]["caption"] = mode
		labels["continue"].text = mode
	for slot_name: String in labels:
		labels[slot_name].visible = slot_name == "continue" if mode != "" else slot_name != "continue"
	queue_redraw()


func horizontal() -> int:
	var direction := 0
	for slot_name: String in fingers.values():
		if slot_name == "left":
			direction -= 1
		elif slot_name == "right":
			direction += 1
	return clampi(direction, -1, 1)


func ducking() -> bool:
	return fingers.values().has("down")


func consume_presses() -> Dictionary:
	var result := {
		"jump": pressed_jump,
		"dash": pressed_dash,
		"continue": pressed_continue,
		"action": pressed_action.duplicate(true),
	}
	pressed_jump = false
	pressed_dash = false
	pressed_continue = false
	pressed_action = {}
	return result


func clear_all() -> void:
	fingers.clear()
	consume_presses()
	queue_redraw()


func press_at(finger: int, position_in_view: Vector2) -> void:
	var slot_name := _slot_at(position_in_view)
	fingers[finger] = slot_name
	_queue_press(slot_name)
	queue_redraw()


func drag_to(finger: int, position_in_view: Vector2) -> void:
	if not fingers.has(finger):
		return
	var slot_name := _slot_at(position_in_view)
	if fingers[finger] != slot_name:
		fingers[finger] = slot_name
		_queue_press(slot_name)
		queue_redraw()


func release(finger: int) -> void:
	fingers.erase(finger)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			press_at(event.index, event.position)
		else:
			release(event.index)
	elif event is InputEventScreenDrag:
		drag_to(event.index, event.position)
	elif not OS.has_feature("mobile") and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_at(-1, event.position)
		else:
			release(-1)
	elif not OS.has_feature("mobile") and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		drag_to(-1, event.position)


func _draw() -> void:
	for slot_name: String in slots:
		if (slot_name == "continue") != (continue_mode != ""):
			continue
		var slot: Dictionary = slots[slot_name]
		var active := fingers.values().has(slot_name)
		var color := Color(0.22, 0.59, 0.85, 0.85) if active else Color(0.12, 0.2, 0.28, 0.72)
		draw_circle(slot["center"], slot["radius"], color)


func _slot(center: Vector2, radius: float, caption: String) -> Dictionary:
	return {"center": center, "radius": radius, "caption": caption}


func _slot_at(point: Vector2) -> String:
	for slot_name: String in slots:
		if (slot_name == "continue") != (continue_mode != ""):
			continue
		var slot: Dictionary = slots[slot_name]
		if point.distance_squared_to(slot["center"]) <= slot["radius"] * slot["radius"]:
			return slot_name
	return ""


func _queue_press(slot_name: String) -> void:
	match slot_name:
		"up":
			pressed_jump = true
		"dash":
			pressed_dash = true
		"basic":
			pressed_action = {"kind": "basic"}
		"shield":
			pressed_action = {"kind": "shield"}
		"continue":
			pressed_continue = true
		"move_0", "move_1", "move_2", "move_3":
			pressed_action = {"kind": "move_slot", "slot": int(slot_name.right(1))}
