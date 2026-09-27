class_name LanLink
extends Node

signal status_changed(message: String)
signal client_build_received(build: Dictionary)
signal match_started(first_build: Dictionary, second_build: Dictionary)
signal countdown_received(seconds: int)
signal snapshot_received(state: Dictionary)
signal transition_requested(kind: String)
signal peer_left

const PORT := 27185

var hosting := false
var client_id := 0
var selected_build: Dictionary = {}
var outgoing_sequence := 0
var last_control_sequence := -1
var last_press_sequence := -1
var remote_direction := 0
var remote_duck := false
var remote_jump := false
var remote_dash := false
var remote_dash_direction := 0
var remote_action: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(build: Dictionary) -> Error:
	close()
	selected_build = build.duplicate(true)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 1)
	if error != OK:
		status_changed.emit("Could not host LAN match (%d)" % error)
		return error
	hosting = true
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Hosting on UDP %d — waiting for player" % PORT)
	return OK


func join(address: String, build: Dictionary) -> Error:
	close()
	selected_build = build.duplicate(true)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), PORT)
	if error != OK:
		status_changed.emit("Could not connect to %s (%d)" % [address, error])
		return error
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Connecting to %s:%d" % [address, PORT])
	return OK


func close() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	hosting = false
	client_id = 0
	outgoing_sequence = 0
	last_control_sequence = -1
	last_press_sequence = -1
	remote_direction = 0
	remote_duck = false
	remote_jump = false
	remote_dash = false
	remote_dash_direction = 0
	remote_action = {}


func send_input(input: Dictionary) -> void:
	if hosting or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	outgoing_sequence += 1
	_receive_controls.rpc_id(1, clampi(int(input.get("horizontal", 0)), -1, 1), bool(input.get("duck", false)), outgoing_sequence)
	var action: Dictionary = input.get("action", {})
	if bool(input.get("jump", false)) or bool(input.get("dash", false)) or not action.is_empty():
		_receive_press.rpc_id(1, bool(input.get("jump", false)), bool(input.get("dash", false)), clampi(int(input.get("horizontal", 0)), -1, 1), action, outgoing_sequence)


func take_remote_input() -> Dictionary:
	var input := {
		"horizontal": remote_dash_direction if remote_dash else remote_direction,
		"duck": remote_duck,
		"jump": remote_jump,
		"dash": remote_dash,
		"action": remote_action.duplicate(true),
	}
	remote_jump = false
	remote_dash = false
	remote_dash_direction = 0
	remote_action = {}
	return input


func send_match(first_build: Dictionary, second_build: Dictionary) -> void:
	if hosting and client_id != 0:
		_receive_match.rpc_id(client_id, first_build, second_build)


func reject_client(message: String) -> void:
	if hosting and client_id != 0:
		_receive_rejection.rpc_id(client_id, message)


func send_snapshot(state: Dictionary) -> void:
	if hosting and client_id != 0:
		_receive_snapshot.rpc_id(client_id, state)


func send_countdown(seconds: int) -> void:
	if hosting and client_id != 0:
		_receive_countdown.rpc_id(client_id, seconds)


func request_round_transition(kind: String) -> void:
	if not hosting:
		_receive_transition.rpc_id(1, kind)


func _on_peer_connected(id: int) -> void:
	if hosting and client_id == 0:
		client_id = id
		status_changed.emit("Player connected — waiting for build")


func _on_peer_disconnected(id: int) -> void:
	if hosting and id == client_id:
		client_id = 0
		remote_direction = 0
		remote_duck = false
		remote_jump = false
		remote_dash = false
		remote_dash_direction = 0
		remote_action = {}
		peer_left.emit()
		status_changed.emit("Player disconnected")


func _on_connected_to_server() -> void:
	status_changed.emit("Connected — waiting for host")
	_receive_build.rpc_id(1, selected_build)


func _on_connection_failed() -> void:
	close()
	status_changed.emit("LAN connection failed")
	peer_left.emit()


func _on_server_disconnected() -> void:
	close()
	status_changed.emit("Host disconnected")
	peer_left.emit()


@rpc("any_peer", "call_remote", "reliable")
func _receive_build(build: Dictionary) -> void:
	if hosting and multiplayer.get_remote_sender_id() == client_id:
		client_build_received.emit(build)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_controls(direction: int, duck: bool, sequence: int) -> void:
	if not hosting or multiplayer.get_remote_sender_id() != client_id or sequence <= last_control_sequence:
		return
	last_control_sequence = sequence
	remote_direction = clampi(direction, -1, 1)
	remote_duck = duck


@rpc("any_peer", "call_remote", "reliable")
func _receive_press(jump: bool, dash: bool, dash_direction: int, action: Dictionary, sequence: int) -> void:
	if not hosting or multiplayer.get_remote_sender_id() != client_id or sequence <= last_press_sequence:
		return
	last_press_sequence = sequence
	remote_jump = remote_jump or jump
	remote_dash = remote_dash or dash
	if dash:
		remote_dash_direction = clampi(dash_direction, -1, 1)
	var kind: String = str(action.get("kind", ""))
	if kind == "basic" or kind == "shield":
		remote_action = {"kind": kind}
	elif kind == "move":
		var move_id: String = str(action.get("id", ""))
		if move_id.length() <= 64:
			remote_action = {"kind": "move", "id": move_id}


@rpc("authority", "call_remote", "reliable")
func _receive_match(first_build: Dictionary, second_build: Dictionary) -> void:
	if not hosting:
		match_started.emit(first_build, second_build)


@rpc("authority", "call_remote", "reliable")
func _receive_rejection(message: String) -> void:
	if not hosting:
		close()
		status_changed.emit(message)
		peer_left.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(state: Dictionary) -> void:
	if not hosting:
		snapshot_received.emit(state)


@rpc("authority", "call_remote", "reliable")
func _receive_countdown(seconds: int) -> void:
	if not hosting:
		countdown_received.emit(seconds)


@rpc("any_peer", "call_remote", "reliable")
func _receive_transition(kind: String) -> void:
	if hosting and multiplayer.get_remote_sender_id() == client_id and (kind == "next" or kind == "rematch"):
		transition_requested.emit(kind)
