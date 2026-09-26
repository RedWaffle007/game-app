extends Node3D

const CombatantStateScript := preload("res://src/sim/combatant_state.gd")
const MatchSessionScript := preload("res://src/sim/match_session.gd")
const WORLD_SCALE := 0.01

var catalog: FighterCatalog
var validated_builds: Dictionary = {}
var session: RefCounted
var player_body: MeshInstance3D
var bot_body: MeshInstance3D
var player_projectile: MeshInstance3D
var bot_projectile: MeshInstance3D
var player_health: ProgressBar
var bot_health: ProgressBar
var round_label: Label
var status_label: Label
var moves_label: Label
var queued_action: Dictionary = {}
var queued_jump := false
var queued_dash := false


func _ready() -> void:
	Engine.physics_ticks_per_second = GameConfig.TICKS_PER_SECOND
	var file := FileAccess.open("res://data/example_builds.json", FileAccess.READ)
	if file == null:
		push_error("Missing example builds")
		return
	var examples: Dictionary = JSON.parse_string(file.get_as_text())
	catalog = FighterCatalog.new()
	var validator := BuildValidator.new(catalog)
	for build_name: String in ["balanced", "poisoner"]:
		var checked: Dictionary = validator.validate(examples[build_name])
		if not checked["valid"]:
			push_error("Invalid %s example build: %s" % [build_name, checked["errors"]])
			return
		validated_builds[build_name] = checked
	_create_arena()
	_create_hud()
	_start_match()


func _physics_process(_delta: float) -> void:
	if session == null or session.phase == "match_over":
		return
	if session.phase == "round_over":
		return
	var direction := int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
	var player_input := {
		"horizontal": direction,
		"duck": Input.is_key_pressed(KEY_S),
		"jump": queued_jump,
		"dash": queued_dash,
		"action": queued_action,
	}
	queued_jump = false
	queued_dash = false
	queued_action = {}
	session.advance(player_input, _bot_input())
	_sync_visuals()
	_update_hud()


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
				var order: Array[String] = session.simulation.first.move_order
				if index < order.size():
					queued_action = {"kind": "move", "id": order[index]}
		KEY_ENTER, KEY_KP_ENTER:
			if session != null and session.start_next_round():
				_sync_visuals()
				_update_hud()
		KEY_R:
			if session != null and session.phase == "match_over":
				_start_match()


func _start_match() -> void:
	var player := CombatantStateScript.new("Player", validated_builds["balanced"]["moves"], validated_builds["balanced"]["shield"], -GameConfig.START_DISTANCE_FROM_CENTER)
	var bot := CombatantStateScript.new("Bot", validated_builds["poisoner"]["moves"], validated_builds["poisoner"]["shield"], GameConfig.START_DISTANCE_FROM_CENTER)
	session = MatchSessionScript.new(player, bot, catalog)
	queued_action = {}
	queued_jump = false
	queued_dash = false
	_sync_visuals()
	_update_hud()


func _bot_input() -> Dictionary:
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
	round_label = _label(root, Vector2(480, 18), 22)
	status_label = _label(root, Vector2(420, 72), 18)
	moves_label = _label(root, Vector2(28, 82), 17)
	_label(root, Vector2(28, 620), 17).text = "A/D move · W jump · S duck · Shift dash · Space attack · 1–4 moves · F shield"
	_label(root, Vector2(28, 650), 17).text = "Enter: next round · R: rematch after result"


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
	player_body.position = Vector3(player.x * WORLD_SCALE, player.y * WORLD_SCALE + 0.9, 0)
	bot_body.position = Vector3(bot.x * WORLD_SCALE, bot.y * WORLD_SCALE + 0.9, 0)
	_sync_projectile(player_projectile, player.active_projectile)
	_sync_projectile(bot_projectile, bot.active_projectile)


func _sync_projectile(visual: MeshInstance3D, projectile: Dictionary) -> void:
	visual.visible = not projectile.is_empty()
	if visual.visible:
		visual.position = Vector3(int(projectile["x"]) * WORLD_SCALE, (int(projectile["min_y"]) + int(projectile["max_y"])) * WORLD_SCALE / 2.0, 0)


func _update_hud() -> void:
	var player: RefCounted = session.simulation.first
	var bot: RefCounted = session.simulation.second
	player_health.value = player.hp
	bot_health.value = bot.hp
	round_label.text = "Round %d   %d–%d   %ds" % [session.round_number, session.first_rounds_won, session.second_rounds_won, (session.round_ticks_left + 59) / 60]
	if session.phase == "round_over":
		status_label.text = "Draw — press Enter to replay" if session.last_round_winner == "draw" else "%s wins the round — press Enter" % session.last_round_winner.capitalize()
	elif session.phase == "match_over":
		status_label.text = "%s wins the match — press R" % session.match_winner.capitalize()
	elif session.phase == "sudden_death":
		status_label.text = "SUDDEN DEATH — first damaging hit wins"
	else:
		status_label.text = "Player %d HP                                Bot %d HP" % [player.hp, bot.hp]
	var move_lines := ""
	for index in player.move_order.size():
		var move_id: String = player.move_order[index]
		move_lines += "%d %s: %d   " % [index + 1, catalog.moves[move_id]["name"], player.moves[move_id]["charges"]]
	moves_label.text = move_lines
