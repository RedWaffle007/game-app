extends Node3D

const CombatantStateScript := preload("res://src/sim/combatant_state.gd")
const MatchSessionScript := preload("res://src/sim/match_session.gd")
const TouchControlsScript := preload("res://src/ui/touch_controls.gd")
const LanLinkScript := preload("res://src/network/lan_link.gd")
const WORLD_SCALE := 0.01
const PRESET_NAMES := ["balanced", "glass_cannon", "poisoner", "pure_nuke", "turtle"]

var catalog: FighterCatalog
var validated_builds: Dictionary = {}
var example_builds: Dictionary = {}
var session: RefCounted
var lan: LanLink
var lan_mode := "offline"
var lan_menu: PanelContainer
var lan_ip_input: LineEdit
var lan_status_label: Label
var lan_open_button: Button
var lan_reveal_panel: PanelContainer
var lan_reveal_label: Label
var lan_reveal_ticks := 0
var lan_reveal_text := ""
var lan_first_build: Dictionary = {}
var lan_second_build: Dictionary = {}
var player_body: MeshInstance3D
var bot_body: MeshInstance3D
var player_projectile: MeshInstance3D
var bot_projectile: MeshInstance3D
var player_health: ProgressBar
var bot_health: ProgressBar
var player_effects_label: Label
var bot_effects_label: Label
var round_label: Label
var fps_label: Label
var status_label: Label
var moves_label: Label
var help_label: Label
var next_label: Label
var touch
var queued_action: Dictionary = {}
var queued_jump := false
var queued_dash := false
var training_dummy := false
var player_preset_index := 0
var previous_player_x := 0
var previous_bot_x := 0
var previous_player_hp := GameConfig.MAX_HP
var previous_bot_hp := GameConfig.MAX_HP
var player_flash_ticks := 0
var bot_flash_ticks := 0
var fps_is_low := false
var client_has_targets := false
var client_player_target := Vector3.ZERO
var client_bot_target := Vector3.ZERO
var client_player_projectile_target := Vector3.ZERO
var client_bot_projectile_target := Vector3.ZERO


func _ready() -> void:
	Engine.physics_ticks_per_second = GameConfig.TICKS_PER_SECOND
	var file := FileAccess.open("res://data/example_builds.json", FileAccess.READ)
	if file == null:
		push_error("Missing example builds")
		return
	var examples: Dictionary = JSON.parse_string(file.get_as_text())
	example_builds = examples
	catalog = FighterCatalog.new()
	var validator := BuildValidator.new(catalog)
	for build_name: String in PRESET_NAMES:
		var checked: Dictionary = validator.validate(examples[build_name])
		if not checked["valid"]:
			push_error("Invalid %s example build: %s" % [build_name, checked["errors"]])
			return
		validated_builds[build_name] = checked
	_create_arena()
	_create_hud()
	lan = LanLinkScript.new()
	lan.name = "LanLink"
	add_child(lan, true)
	lan.status_changed.connect(_on_lan_status)
	lan.client_build_received.connect(_on_lan_client_build)
	lan.match_started.connect(_on_lan_match_started)
	lan.countdown_received.connect(_on_lan_countdown)
	lan.snapshot_received.connect(_on_lan_snapshot)
	lan.transition_requested.connect(_on_lan_transition)
	lan.peer_left.connect(_on_lan_peer_left)
	_start_match()


func _physics_process(_delta: float) -> void:
	if session == null:
		if touch != null:
			touch.consume_presses()
		return
	if lan_menu.visible:
		touch.consume_presses()
		queued_action = {}
		queued_jump = false
		queued_dash = false
		if lan_mode == "client_match":
			lan.send_input({"horizontal": 0, "duck": false})
		elif lan_mode == "host_match" and (session.phase == "fighting" or session.phase == "sudden_death"):
			session.advance({}, lan.take_remote_input())
			if session.simulation.tick_index % 3 == 0 or session.phase == "round_over" or session.phase == "match_over":
				lan.send_snapshot(session.snapshot())
			_sync_visuals()
			_update_hud()
		return
	if lan_mode == "hosting" or lan_mode == "joining":
		touch.consume_presses()
		return
	if lan_mode == "host_reveal":
		touch.consume_presses()
		lan_reveal_ticks -= 1
		if lan_reveal_ticks % 60 == 0:
			var seconds: int = lan_reveal_ticks / 60
			lan.send_countdown(seconds)
			_set_reveal_countdown(seconds)
		if lan_reveal_ticks <= 0:
			lan_mode = "host_match"
			lan_reveal_panel.visible = false
			lan_open_button.visible = true
		return
	if lan_mode == "client_reveal":
		touch.consume_presses()
		return
	var touch_press: Dictionary = touch.consume_presses()
	if bool(touch_press["training_toggle"]) and lan_mode == "offline":
		training_dummy = not training_dummy
		touch.set_training_mode(training_dummy)
	if bool(touch_press["cycle_build"]) and lan_mode == "offline":
		_cycle_player_build()
		return
	if bool(touch_press["continue"]):
		if lan_mode == "client_match":
			lan.request_round_transition("rematch" if session.phase == "match_over" else "next")
			return
		if session.phase == "round_over" and session.start_next_round():
			touch.clear_all()
			queued_action = {}
			queued_jump = false
			queued_dash = false
			_sync_visuals()
			_update_hud()
			if lan_mode == "host_match":
				lan.send_snapshot(session.snapshot())
			return
		elif session.phase == "match_over":
			if lan_mode == "host_match":
				_start_lan_match()
			else:
				_start_match()
			return
	if session.phase == "round_over" or session.phase == "match_over":
		return
	var direction := clampi(int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A)) + touch.horizontal(), -1, 1)
	if bool(touch_press["dash"]):
		direction = int(touch_press["dash_direction"])
	var action: Dictionary = queued_action
	if action.is_empty():
		action = touch_press["action"]
		if str(action.get("kind", "")) == "move_slot":
			var slot: int = int(action["slot"])
			var order: Array[String] = _local_fighter().move_order
			action = {"kind": "move", "id": order[slot]} if slot < order.size() else {}
	var player_input := {
		"horizontal": direction,
		"duck": Input.is_key_pressed(KEY_S) or touch.ducking(),
		"jump": queued_jump or bool(touch_press["jump"]),
		"dash": queued_dash or bool(touch_press["dash"]),
		"action": action,
	}
	queued_jump = false
	queued_dash = false
	queued_action = {}
	if lan_mode == "client_match":
		lan.send_input(player_input)
		return
	if lan_mode == "host_match":
		session.advance(player_input, lan.take_remote_input())
		if session.simulation.tick_index % 3 == 0 or session.phase == "round_over" or session.phase == "match_over":
			lan.send_snapshot(session.snapshot())
	else:
		session.advance(player_input, _bot_input())
	_sync_visuals()
	_update_hud()


func _process(delta: float) -> void:
	if lan_mode != "client_match" or not client_has_targets:
		return
	var weight := minf(1.0, delta * 18.0)
	player_body.position = player_body.position.lerp(client_player_target, weight)
	bot_body.position = bot_body.position.lerp(client_bot_target, weight)
	if player_projectile.visible:
		player_projectile.position = player_projectile.position.lerp(client_player_projectile_target, weight)
	if bot_projectile.visible:
		bot_projectile.position = bot_projectile.position.lerp(client_bot_projectile_target, weight)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: InputEventKey = event
	match key.keycode:
		KEY_W:
			queued_jump = true
		KEY_SHIFT:
			queued_dash = true
		KEY_SPACE:
			queued_action = {"kind": "basic"}
		KEY_F:
			queued_action = {"kind": "shield"}
		KEY_1, KEY_2, KEY_3, KEY_4:
			if session != null:
				var index: int = int(key.keycode) - KEY_1
				var order: Array[String] = _local_fighter().move_order
				if index < order.size():
					queued_action = {"kind": "move", "id": order[index]}
		KEY_ENTER, KEY_KP_ENTER:
			if lan_mode == "client_match" and session != null and session.phase == "round_over":
				lan.request_round_transition("next")
			elif session != null and session.start_next_round():
				touch.clear_all()
				queued_action = {}
				queued_jump = false
				queued_dash = false
				_sync_visuals()
				_update_hud()
				if lan_mode == "host_match":
					lan.send_snapshot(session.snapshot())
		KEY_R:
			if session != null and session.phase == "match_over":
				if lan_mode == "client_match":
					lan.request_round_transition("rematch")
				elif lan_mode == "host_match":
					_start_lan_match()
				else:
					_start_match()
		KEY_T:
			if lan_mode == "offline":
				training_dummy = not training_dummy
				if touch != null:
					touch.set_training_mode(training_dummy)
		KEY_B:
			if lan_mode == "offline":
				_cycle_player_build()


func _cycle_player_build() -> void:
	player_preset_index = (player_preset_index + 1) % PRESET_NAMES.size()
	if touch != null:
		touch.set_build_index(player_preset_index + 1, PRESET_NAMES.size())
	_start_match()


func _start_match() -> void:
	var selected_preset: String = PRESET_NAMES[player_preset_index]
	var player := CombatantStateScript.new("Player", validated_builds[selected_preset]["moves"], validated_builds[selected_preset]["shield"], -GameConfig.START_DISTANCE_FROM_CENTER)
	var bot := CombatantStateScript.new("Bot", validated_builds["poisoner"]["moves"], validated_builds["poisoner"]["shield"], GameConfig.START_DISTANCE_FROM_CENTER)
	session = MatchSessionScript.new(player, bot, catalog)
	client_has_targets = false
	queued_action = {}
	queued_jump = false
	queued_dash = false
	if touch != null:
		touch.clear_all()
	_sync_visuals()
	_update_hud()


func _start_lan_match() -> void:
	var first := CombatantStateScript.new("Host", lan_first_build["moves"], lan_first_build["shield"], -GameConfig.START_DISTANCE_FROM_CENTER)
	var second := CombatantStateScript.new("Guest", lan_second_build["moves"], lan_second_build["shield"], GameConfig.START_DISTANCE_FROM_CENTER)
	session = MatchSessionScript.new(first, second, catalog)
	client_has_targets = false
	lan_mode = "host_reveal"
	lan_reveal_ticks = 180
	queued_action = {}
	queued_jump = false
	queued_dash = false
	touch.clear_all()
	touch.set_lan_locked(true)
	lan.send_match(lan_first_build, lan_second_build)
	lan.send_countdown(3)
	_show_build_reveal()
	_sync_visuals()
	_update_hud()


func _local_fighter() -> RefCounted:
	return session.simulation.second if lan_mode.begins_with("client_") else session.simulation.first


func _on_lan_client_build(build: Dictionary) -> void:
	if lan_mode != "hosting":
		return
	var checked: Dictionary = BuildValidator.new(catalog).validate(build)
	if not checked["valid"]:
		_on_lan_status("Guest build rejected: %s" % [checked["errors"]])
		lan.reject_client("Build rejected by host")
		return
	lan_first_build = validated_builds[PRESET_NAMES[player_preset_index]]
	lan_second_build = checked
	_start_lan_match()


func _on_lan_match_started(first_build: Dictionary, second_build: Dictionary) -> void:
	if lan_mode != "joining" and lan_mode != "client_match":
		return
	lan_first_build = first_build
	lan_second_build = second_build
	var first := CombatantStateScript.new("Host", first_build["moves"], first_build["shield"], -GameConfig.START_DISTANCE_FROM_CENTER)
	var second := CombatantStateScript.new("Guest", second_build["moves"], second_build["shield"], GameConfig.START_DISTANCE_FROM_CENTER)
	session = MatchSessionScript.new(first, second, catalog)
	client_has_targets = false
	lan_mode = "client_reveal"
	queued_action = {}
	queued_jump = false
	queued_dash = false
	touch.clear_all()
	touch.set_lan_locked(true)
	_show_build_reveal()
	_sync_visuals()
	_update_hud()


func _on_lan_countdown(seconds: int) -> void:
	if lan_mode != "client_reveal":
		return
	_set_reveal_countdown(seconds)
	if seconds <= 0:
		lan_mode = "client_match"
		lan_reveal_panel.visible = false
		lan_open_button.visible = true


func _on_lan_snapshot(state: Dictionary) -> void:
	if lan_mode != "client_match" or session == null or not state.has("simulation"):
		return
	var previous_round: int = session.round_number
	var previous_player_position := player_body.position
	var previous_bot_position := bot_body.position
	var previous_player_projectile_position := player_projectile.position
	var previous_bot_projectile_position := bot_projectile.position
	var had_player_projectile := player_projectile.visible
	var had_bot_projectile := bot_projectile.visible
	session.restore_snapshot(state)
	_sync_visuals()
	client_player_target = player_body.position
	client_bot_target = bot_body.position
	client_player_projectile_target = player_projectile.position
	client_bot_projectile_target = bot_projectile.position
	if previous_round == session.round_number:
		player_body.position = previous_player_position
		bot_body.position = previous_bot_position
		if had_player_projectile and player_projectile.visible:
			player_projectile.position = previous_player_projectile_position
		if had_bot_projectile and bot_projectile.visible:
			bot_projectile.position = previous_bot_projectile_position
	client_has_targets = true
	_update_hud()


func _on_lan_transition(kind: String) -> void:
	if lan_mode != "host_match":
		return
	if kind == "next" and session.phase == "round_over":
		if session.start_next_round():
			lan.send_snapshot(session.snapshot())
			_sync_visuals()
			_update_hud()
	elif kind == "rematch" and session.phase == "match_over":
		_start_lan_match()


func _on_lan_peer_left() -> void:
	lan_reveal_panel.visible = false
	lan_open_button.visible = true
	if lan.hosting:
		lan_mode = "hosting"
	else:
		lan_mode = "offline"
		lan.close()
	_start_match()
	touch.set_lan_locked(lan_mode != "offline")
	if lan_mode == "hosting":
		status_label.text = "Waiting for another player"
	else:
		status_label.text = "%s — offline" % lan_status_label.text


func _on_lan_status(message: String) -> void:
	if lan_status_label != null:
		lan_status_label.text = message
	if lan_mode == "hosting" or lan_mode == "joining":
		status_label.text = message


func _bot_input() -> Dictionary:
	if training_dummy:
		return {"horizontal": 0}
	var player: RefCounted = session.simulation.first
	var bot: RefCounted = session.simulation.second
	var gap: int = absi(player.x - bot.x)
	var result := {"horizontal": 0}
	if gap > GameConfig.BASIC_ATTACK_RANGE - 10:
		result["horizontal"] = 1 if player.x > bot.x else -1
	if gap <= 130 and session.simulation.tick_index % 75 == 0:
		for move_id: String in bot.move_order:
			if int(bot.moves[move_id]["charges"]) > 0 and bot.can_begin_move(move_id):
				result["action"] = {"kind": "move", "id": move_id}
				break
	elif gap <= 85 and session.simulation.tick_index % 30 == 0:
		result["action"] = {"kind": "basic"}
	elif gap <= 110 and session.simulation.tick_index % 180 == 90:
		result["action"] = {"kind": "shield"}
	return result


func _create_arena() -> void:
	var ground := _box(Vector3(21.0, 0.2, 3.0), Color(0.25, 0.28, 0.31))
	ground.position = Vector3(0, -0.13, 0)
	for side in [-1, 1]:
		var wall := _box(Vector3(0.2, 3.0, 3.0), Color(0.34, 0.38, 0.42))
		wall.position = Vector3(side * 10.1, 1.4, 0)
	player_body = _fighter_mesh(Color(0.23, 0.68, 0.98))
	bot_body = _fighter_mesh(Color(0.98, 0.4, 0.3))
	player_projectile = _projectile_mesh(Color(0.25, 0.75, 1.0))
	bot_projectile = _projectile_mesh(Color(1.0, 0.45, 0.2))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	camera.position = Vector3(0, 4, 24)
	add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	add_child(light)


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	add_child(instance)
	return instance


func _fighter_mesh(color: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.8
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	add_child(instance)
	return instance


func _projectile_mesh(color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.visible = false
	add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	player_health = _health_bar(root, Vector2(28, 25))
	bot_health = _health_bar(root, Vector2(952, 25))
	player_effects_label = _label(root, Vector2(28, 55), 14)
	bot_effects_label = _label(root, Vector2(952, 55), 14)
	round_label = _label(root, Vector2(480, 18), 22)
	fps_label = _label(root, Vector2(600, 46), 14)
	fps_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.92))
	status_label = _label(root, Vector2(420, 72), 18)
	moves_label = _label(root, Vector2(28, 82), 17)
	help_label = _label(root, Vector2(28, 120), 17)
	help_label.text = "A/D move · W jump · S duck · Shift dash · Space attack · 1–4 moves · F shield · T bot/dummy · B build"
	next_label = _label(root, Vector2(28, 150), 17)
	next_label.text = "Enter: next round · R: rematch after result"
	help_label.visible = not OS.has_feature("mobile")
	next_label.visible = not OS.has_feature("mobile")
	touch = TouchControlsScript.new()
	root.add_child(touch)
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_lan_menu(root)
	get_viewport().size_changed.connect(_refresh_touch_layout)
	_refresh_touch_layout()


func _create_lan_menu(root: Control) -> void:
	lan_open_button = Button.new()
	lan_open_button.text = "LAN"
	lan_open_button.size = Vector2(90, 42)
	lan_open_button.pressed.connect(_on_lan_menu_toggle)
	root.add_child(lan_open_button)
	lan_menu = PanelContainer.new()
	lan_menu.visible = false
	root.add_child(lan_menu)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	lan_menu.add_child(stack)
	var heading := Label.new()
	heading.text = "LAN MATCH  ·  same Wi-Fi  ·  UDP 27185"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(heading)
	lan_status_label = Label.new()
	lan_status_label.text = "Choose Host or enter the host phone's local IP."
	lan_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(lan_status_label)
	lan_ip_input = LineEdit.new()
	lan_ip_input.placeholder_text = "Host IP, e.g. 192.168.1.20"
	lan_ip_input.text = ""
	stack.add_child(lan_ip_input)
	for option in ["Host", "Join", "Offline", "Close"]:
		var button := Button.new()
		button.text = option
		stack.add_child(button)
		match option:
			"Host":
				button.pressed.connect(_on_lan_host_pressed)
			"Join":
				button.pressed.connect(_on_lan_join_pressed)
			"Offline":
				button.pressed.connect(_on_lan_offline_pressed)
			"Close":
				button.pressed.connect(_on_lan_menu_toggle)
	lan_reveal_panel = PanelContainer.new()
	lan_reveal_panel.visible = false
	root.add_child(lan_reveal_panel)
	lan_reveal_label = Label.new()
	lan_reveal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lan_reveal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lan_reveal_label.add_theme_font_size_override("font_size", 18)
	lan_reveal_panel.add_child(lan_reveal_label)


func _on_lan_menu_toggle() -> void:
	lan_menu.visible = not lan_menu.visible
	queued_action = {}
	queued_jump = false
	queued_dash = false
	if touch != null:
		touch.clear_all()


func _on_lan_host_pressed() -> void:
	var raw_build: Dictionary = example_builds[PRESET_NAMES[player_preset_index]]
	if lan.host(raw_build) != OK:
		return
	lan_mode = "hosting"
	touch.set_lan_locked(true)
	lan_menu.visible = false
	status_label.text = "Hosting at %s:%d — waiting for player" % [_local_ipv4(), LanLink.PORT]


func _on_lan_join_pressed() -> void:
	var address := lan_ip_input.text.strip_edges()
	if address.is_empty():
		lan_status_label.text = "Enter the host phone's local IP address."
		return
	var raw_build: Dictionary = example_builds[PRESET_NAMES[player_preset_index]]
	if lan.join(address, raw_build) != OK:
		return
	lan_mode = "joining"
	touch.set_lan_locked(true)
	lan_menu.visible = false
	status_label.text = "Connecting to %s:%d" % [address, LanLink.PORT]


func _on_lan_offline_pressed() -> void:
	lan.close()
	lan_mode = "offline"
	lan_menu.visible = false
	lan_reveal_panel.visible = false
	lan_open_button.visible = true
	touch.set_lan_locked(false)
	_start_match()


func _show_build_reveal() -> void:
	lan_reveal_text = "HOST\n%s\n\nGUEST\n%s" % [_build_summary(lan_first_build), _build_summary(lan_second_build)]
	lan_menu.visible = false
	lan_open_button.visible = false
	lan_reveal_panel.visible = true
	_set_reveal_countdown(3)


func _set_reveal_countdown(seconds: int) -> void:
	lan_reveal_label.text = "%s\n\nMatch starts in %d" % [lan_reveal_text, seconds]


func _build_summary(build: Dictionary) -> String:
	var lines: Array[String] = ["Shield: %d PP" % int(build["shield"])]
	for raw_move: Variant in build["moves"]:
		var move: Dictionary = raw_move
		var move_id: String = str(move["id"])
		var charges := "∞" if bool(move.get("flourish", false)) else str(move["charges"])
		var effect_id: String = str(move.get("effect", ""))
		var effect_text := ""
		if effect_id != "":
			effect_text = "  + %s" % effect_id.capitalize()
		lines.append("%s  ·  %d power  ·  %s uses%s" % [catalog.moves[move_id]["name"], int(move["power"]), charges, effect_text])
	return "\n".join(lines)


func _local_ipv4() -> String:
	for address: String in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
		if address.begins_with("172."):
			var pieces := address.split(".")
			if pieces.size() == 4 and int(pieces[1]) >= 16 and int(pieces[1]) <= 31:
				return address
	return "phone's local IP"


func _refresh_touch_layout() -> void:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var display_safe: Rect2i = DisplayServer.get_display_safe_area()
	var safe := Rect2(Vector2.ZERO, view_size)
	if screen_size.x > 0 and screen_size.y > 0 and display_safe.size.x > 0 and display_safe.size.y > 0:
		var ratio := view_size / Vector2(screen_size)
		safe = Rect2(Vector2(display_safe.position) * ratio, Vector2(display_safe.size) * ratio)
		safe = safe.intersection(Rect2(Vector2.ZERO, view_size))
	var scale := minf(safe.size.x / 1280.0, safe.size.y / 720.0)
	player_health.position = safe.position + Vector2(28, 25) * scale
	bot_health.position = Vector2(safe.end.x - 328 * scale, safe.position.y + 25 * scale)
	player_health.size = Vector2(300, 27) * scale
	bot_health.size = Vector2(300, 27) * scale
	player_effects_label.position = safe.position + Vector2(28, 55) * scale
	bot_effects_label.position = Vector2(safe.end.x - 328 * scale, safe.position.y + 55 * scale)
	round_label.position = Vector2(safe.get_center().x - 160 * scale, safe.position.y + 18 * scale)
	fps_label.position = Vector2(safe.get_center().x - 40 * scale, safe.position.y + 46 * scale)
	status_label.position = Vector2(safe.get_center().x - 220 * scale, safe.position.y + 72 * scale)
	moves_label.position = safe.position + Vector2(28, 82) * scale
	help_label.position = safe.position + Vector2(28, 120) * scale
	next_label.position = safe.position + Vector2(28, 150) * scale
	lan_open_button.position = safe.position + Vector2(28, 184) * scale
	lan_open_button.size = Vector2(90, 42) * scale
	lan_menu.position = safe.get_center() - Vector2(250, 160) * scale
	lan_menu.custom_minimum_size = Vector2(500, 320) * scale
	lan_menu.size = Vector2(500, 320) * scale
	lan_reveal_panel.position = safe.get_center() - Vector2(380, 210) * scale
	lan_reveal_panel.custom_minimum_size = Vector2(760, 420) * scale
	lan_reveal_panel.size = Vector2(760, 420) * scale
	touch.configure(view_size, safe)


func _health_bar(parent: Control, pos: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = Vector2(300, 27)
	bar.max_value = GameConfig.MAX_HP
	bar.show_percentage = false
	parent.add_child(bar)
	return bar


func _label(parent: Control, pos: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _sync_visuals() -> void:
	var player: RefCounted = session.simulation.first
	var bot: RefCounted = session.simulation.second
	if session.simulation.tick_index == 0:
		previous_player_x = player.x
		previous_bot_x = bot.x
		previous_player_hp = player.hp
		previous_bot_hp = bot.hp
		player_flash_ticks = 0
		bot_flash_ticks = 0
	if player.hp < previous_player_hp:
		player_flash_ticks = 8
	if bot.hp < previous_bot_hp:
		bot_flash_ticks = 8
	_pose_fighter(player, player_body, Color(0.23, 0.68, 0.98), player.x != previous_player_x, player_flash_ticks)
	_pose_fighter(bot, bot_body, Color(0.98, 0.4, 0.3), bot.x != previous_bot_x, bot_flash_ticks)
	previous_player_x = player.x
	previous_bot_x = bot.x
	previous_player_hp = player.hp
	previous_bot_hp = bot.hp
	player_flash_ticks = maxi(0, player_flash_ticks - 1)
	bot_flash_ticks = maxi(0, bot_flash_ticks - 1)
	_sync_projectile(player_projectile, player.active_projectile)
	_sync_projectile(bot_projectile, bot.active_projectile)


func _pose_fighter(fighter: RefCounted, body: MeshInstance3D, base_color: Color, moved: bool, flash_ticks: int) -> void:
	var height_scale := 0.64 if fighter.ducking else 1.0
	if fighter.y > 0:
		height_scale = 1.05
	body.scale = Vector3(1.0, height_scale, 1.0)
	var walk_bob := 0.04 * absf(sin(session.simulation.tick_index * 0.45)) if moved and fighter.y == 0 and not fighter.ducking else 0.0
	body.position = Vector3(fighter.x * WORLD_SCALE, fighter.y * WORLD_SCALE + 0.9 * height_scale + walk_bob, 0)
	body.rotation.z = -fighter.dash_direction * 0.2 if fighter.dash_ticks_left > 0 else 0.0
	var color := base_color
	if fighter.shield.active:
		color = color.lerp(Color(0.38, 1.0, 0.85), 0.55)
	elif fighter.active_effects.has("poison"):
		color = color.lerp(Color(0.45, 0.9, 0.35), 0.35)
	if flash_ticks > 0:
		color = color.lerp(Color.WHITE, flash_ticks / 8.0)
	var material := body.material_override as StandardMaterial3D
	material.albedo_color = color


func _sync_projectile(visual: MeshInstance3D, projectile: Dictionary) -> void:
	visual.visible = not projectile.is_empty()
	if visual.visible:
		visual.position = Vector3(int(projectile["x"]) * WORLD_SCALE, (int(projectile["min_y"]) + int(projectile["max_y"])) * WORLD_SCALE / 2.0, 0)


func _update_hud() -> void:
	var first: RefCounted = session.simulation.first
	var second: RefCounted = session.simulation.second
	var player: RefCounted = _local_fighter()
	player_health.value = first.hp
	bot_health.value = second.hp
	player_effects_label.text = _effect_summary(first)
	bot_effects_label.text = _effect_summary(second)
	round_label.text = "Round %d   %d–%d   %ds" % [session.round_number, session.first_rounds_won, session.second_rounds_won, (session.round_ticks_left + 59) / 60]
	var fps := int(Engine.get_frames_per_second())
	fps_label.text = "%d FPS" % fps
	var low_fps := fps > 0 and fps < 55
	if low_fps != fps_is_low:
		fps_is_low = low_fps
		fps_label.add_theme_color_override("font_color", Color(0.95, 0.48, 0.38) if low_fps else Color(0.75, 0.85, 0.92))
	if session.phase == "round_over":
		var next_hint := "tap NEXT" if OS.has_feature("mobile") else "press Enter"
		if session.last_round_winner == "draw":
			status_label.text = "Draw — %s to replay" % next_hint
		else:
			status_label.text = "%s wins the round — %s" % [_winner_label(session.last_round_winner), next_hint]
	elif session.phase == "match_over":
		status_label.text = "%s wins the match — %s" % [_winner_label(session.match_winner), "tap REMATCH" if OS.has_feature("mobile") else "press R"]
	elif session.phase == "sudden_death":
		status_label.text = "SUDDEN DEATH — first damaging hit wins"
	else:
		status_label.text = "%s %d HP                                %s %d HP" % ["Player" if lan_mode == "offline" else "Host", first.hp, "Bot" if lan_mode == "offline" else "Guest", second.hp]
	var move_lines := ""
	for index in player.move_order.size():
		var move_id: String = player.move_order[index]
		move_lines += "%d %s: %d   " % [index + 1, catalog.moves[move_id]["name"], player.moves[move_id]["charges"]]
	moves_label.text = "%s  |  %s" % [PRESET_NAMES[player_preset_index].capitalize().replace("_", " "), move_lines]
	if touch != null:
		var charges: Array[int] = []
		for move_id: String in player.move_order:
			var move_state: Dictionary = player.moves[move_id]
			charges.append(-1 if bool(move_state.get("flourish", false)) else int(move_state["charges"]))
		touch.set_combat_status(charges, player.shield)
		if session.phase == "round_over":
			touch.set_continue_mode("NEXT")
		elif session.phase == "match_over":
			touch.set_continue_mode("REMATCH")
		else:
			touch.set_continue_mode("")


func _winner_label(winner: String) -> String:
	if winner == "first":
		return "Player" if lan_mode == "offline" else "Host"
	return "Bot" if lan_mode == "offline" else "Guest"


func _effect_summary(fighter: RefCounted) -> String:
	var parts: Array[String] = []
	for effect_id: String in ["burn", "poison", "weaken"]:
		if fighter.active_effects.has(effect_id):
			var effect: Dictionary = fighter.active_effects[effect_id]
			var remaining: int = maxi(0, int(effect.get("duration_ticks", 0)) - int(effect.get("elapsed_ticks", 0)))
			parts.append("%s %ds" % [effect_id.capitalize(), ceili(remaining / 60.0)])
	if fighter.control_ticks_left > 0:
		parts.append("Stunned %ds" % ceili(fighter.control_ticks_left / 60.0))
	return "  ·  ".join(parts)
