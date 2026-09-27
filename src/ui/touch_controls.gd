class_name TouchControls
extends Control

var slots: Dictionary = {}
var labels: Dictionary = {}
var fingers: Dictionary = {}
var continue_mode := ""
var pressed_jump := false
var pressed_dash := false
var pressed_dash_direction := 0
var pressed_continue := false
var pressed_training_toggle := false
var pressed_cycle_build := false
var pressed_action: Dictionary = {}
var pad_finger := -999
var pad_start := Vector2.ZERO
var pad_position := Vector2.ZERO
var pad_start_ms := 0
var pad_vertical := 0
var pad_flicked := false
# A negative count displays infinity for a charge-free Flourish.
var move_charges: Array[int] = [-1, -1, -1, -1]
var shield_ready := true
var training_dummy := false
var build_caption := "BUILD\n1/5"
var lan_locked := false


func configure(view_size: Vector2, safe_area: Rect2) -> void:
	clear_all()
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
		"pad": _slot(pad, 110 * scale, "MOVE"),
		"training": _slot(pad + Vector2(0, -185) * scale, 45 * scale, "DUMMY" if training_dummy else "BOT"),
		"build": _slot(pad + Vector2(110, -185) * scale, 45 * scale, build_caption),
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
		label.visible = _slot_visible(slot_name)
	queue_redraw()


func set_continue_mode(mode: String) -> void:
	if continue_mode == mode:
		return
	clear_all()
	continue_mode = mode
	if slots.has("continue"):
		slots["continue"]["caption"] = mode
		labels["continue"].text = mode
	for slot_name: String in labels:
		labels[slot_name].visible = _slot_visible(slot_name)
	queue_redraw()


func set_lan_locked(locked: bool) -> void:
	lan_locked = locked
	for slot_name: String in labels:
		labels[slot_name].visible = _slot_visible(slot_name)
	queue_redraw()


func set_combat_status(charges: Array[int], shield: ShieldRuntime) -> void:
	var changed := false
	for index in 4:
		var next_charge := charges[index] if index < charges.size() else -1
		if move_charges[index] != next_charge:
			move_charges[index] = next_charge
			changed = true
		var label_key := "move_%d" % index
		if labels.has(label_key):
			var charge_caption := "%d\n×%d" % [index + 1, next_charge] if next_charge >= 0 else "%d\n∞" % (index + 1)
			if labels[label_key].text != charge_caption:
				labels[label_key].text = charge_caption
	var next_shield_ready: bool = shield.is_ready()
	if shield_ready != next_shield_ready:
		shield_ready = next_shield_ready
		changed = true
	if labels.has("shield"):
		var caption := "SHIELD"
		if shield.strength <= 0:
			caption = "NO\nSHIELD"
		elif shield.active:
			caption = "SHIELD\nACTIVE"
		elif shield.cooldown_ticks_left > 0:
			caption = "SHIELD\n%ds" % ceili(shield.cooldown_ticks_left / 60.0)
		elif shield.contacts_left > 0:
			caption = "SHIELD\n%d HIT" % shield.contacts_left
		if labels["shield"].text != caption:
			labels["shield"].text = caption
	if changed:
		queue_redraw()


func set_training_mode(is_dummy: bool) -> void:
	if training_dummy == is_dummy:
		return
	training_dummy = is_dummy
	if slots.has("training"):
		slots["training"]["caption"] = "DUMMY" if is_dummy else "BOT"
		labels["training"].text = slots["training"]["caption"]
	queue_redraw()


func set_build_index(index: int, total: int) -> void:
	build_caption = "BUILD\n%d/%d" % [index, total]
	if slots.has("build"):
		slots["build"]["caption"] = build_caption
		labels["build"].text = build_caption


func horizontal() -> int:
	if pad_finger == -999 or continue_mode != "":
		return 0
	var offset: Vector2 = pad_position - slots["pad"]["center"]
	var dead_zone: float = slots["pad"]["radius"] * 0.23
	if absf(offset.x) <= dead_zone:
		return 0
	return 1 if offset.x > 0 else -1


func ducking() -> bool:
	return pad_finger != -999 and pad_vertical == 1 and continue_mode == ""


func consume_presses() -> Dictionary:
	var result := {
		"jump": pressed_jump,
		"dash": pressed_dash,
		"dash_direction": pressed_dash_direction,
		"continue": pressed_continue,
		"training_toggle": pressed_training_toggle,
		"cycle_build": pressed_cycle_build,
		"action": pressed_action.duplicate(true),
	}
	pressed_jump = false
	pressed_dash = false
	pressed_dash_direction = 0
	pressed_continue = false
	pressed_training_toggle = false
	pressed_cycle_build = false
	pressed_action = {}
	return result


func clear_all() -> void:
	fingers.clear()
	pad_finger = -999
	pad_vertical = 0
	pad_flicked = false
	consume_presses()
	queue_redraw()


func press_at(finger: int, position_in_view: Vector2, at_ms: int = -1) -> void:
	var slot_name := _slot_at(position_in_view)
	if slot_name == "pad":
		if pad_finger != -999:
			return
		pad_finger = finger
		pad_start = position_in_view
		pad_position = position_in_view
		pad_start_ms = at_ms if at_ms >= 0 else Time.get_ticks_msec()
		pad_flicked = false
		pad_vertical = 0
		_update_pad(position_in_view, pad_start_ms)
	fingers[finger] = slot_name
	if slot_name != "pad":
		_queue_press(slot_name)
	queue_redraw()


func drag_to(finger: int, position_in_view: Vector2, at_ms: int = -1) -> void:
	if not fingers.has(finger):
		return
	if finger == pad_finger:
		_update_pad(position_in_view, at_ms if at_ms >= 0 else Time.get_ticks_msec())
		queue_redraw()
		return
	var slot_name := _slot_at(position_in_view)
	if slot_name == "pad":
		return
	if fingers[finger] != slot_name:
		fingers[finger] = slot_name
		_queue_press(slot_name)
		queue_redraw()


func release(finger: int) -> void:
	if finger == pad_finger:
		pad_finger = -999
		pad_vertical = 0
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
		if not _slot_visible(slot_name):
			continue
		var slot: Dictionary = slots[slot_name]
		var active := fingers.values().has(slot_name)
		var color := Color(0.22, 0.59, 0.85, 0.85) if active else Color(0.12, 0.2, 0.28, 0.72)
		if slot_name.begins_with("move_") and move_charges[int(slot_name.right(1))] == 0:
			color = Color(0.15, 0.15, 0.17, 0.72)
		elif slot_name == "shield" and not shield_ready:
			color = Color(0.15, 0.15, 0.17, 0.72)
		draw_circle(slot["center"], slot["radius"], color)
		if slot_name == "pad":
			var knob: Vector2 = slot["center"]
			if pad_finger != -999:
				knob += (pad_position - knob).limit_length(slot["radius"] * 0.65)
			draw_circle(knob, slot["radius"] * 0.25, Color(0.65, 0.84, 0.95, 0.9))


func _slot(center: Vector2, radius: float, caption: String) -> Dictionary:
	return {"center": center, "radius": radius, "caption": caption}


func _slot_at(point: Vector2) -> String:
	for slot_name: String in slots:
		if not _slot_visible(slot_name):
			continue
		var slot: Dictionary = slots[slot_name]
		if point.distance_squared_to(slot["center"]) <= slot["radius"] * slot["radius"]:
			return slot_name
	return ""


func _slot_visible(slot_name: String) -> bool:
	if continue_mode != "":
		return slot_name == "continue"
	return slot_name != "continue" and (not lan_locked or (slot_name != "training" and slot_name != "build"))


func _queue_press(slot_name: String) -> void:
	match slot_name:
		"basic":
			pressed_action = {"kind": "basic"}
		"shield":
			pressed_action = {"kind": "shield"}
		"continue":
			pressed_continue = true
		"training":
			pressed_training_toggle = true
		"build":
			pressed_cycle_build = true
		"move_0", "move_1", "move_2", "move_3":
			pressed_action = {"kind": "move_slot", "slot": int(slot_name.right(1))}


func _update_pad(position_in_view: Vector2, at_ms: int) -> void:
	pad_position = position_in_view
	var offset: Vector2 = pad_position - slots["pad"]["center"]
	var vertical_threshold: float = slots["pad"]["radius"] * 0.4
	var next_vertical := 0
	if offset.y < -vertical_threshold:
		next_vertical = -1
	elif offset.y > vertical_threshold:
		next_vertical = 1
	if next_vertical == -1 and pad_vertical != -1:
		pressed_jump = true
	pad_vertical = next_vertical
	var swipe: Vector2 = pad_position - pad_start
	if not pad_flicked and at_ms - pad_start_ms <= 180 and absf(swipe.x) >= slots["pad"]["radius"] * 0.75 and absf(swipe.y) <= absf(swipe.x) * 0.6:
		pressed_dash = true
		pressed_dash_direction = 1 if swipe.x > 0 else -1
		pad_flicked = true
