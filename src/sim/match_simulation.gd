class_name MatchSimulation
extends RefCounted

const CombatExchangeScript := preload("res://src/sim/combat_exchange.gd")
const MovementRulesScript := preload("res://src/sim/movement_rules.gd")

var first: RefCounted
var second: RefCounted
var exchange: RefCounted
var movement: RefCounted = MovementRulesScript.new()
var pending: Array[Dictionary] = [{}, {}]
var remaining: Array[int] = [0, 0]
var tick_index := 0


func _init(first_fighter: RefCounted, second_fighter: RefCounted, catalog: FighterCatalog = null) -> void:
	first = first_fighter
	second = second_fighter
	exchange = CombatExchangeScript.new(catalog)


## One fixed simulation tick. New button presses replace older buffered presses.
## A press is eligible on its arrival tick and the following five ticks.
func advance(first_input: Dictionary = {}, second_input: Dictionary = {}) -> Dictionary:
	_store_press(0, first_input)
	_store_press(1, second_input)
	var positions: Dictionary = movement.advance(first, second, first_input, second_input)
	var first_action := _take_ready_action(0, first)
	var second_action := _take_ready_action(1, second)
	# Both shields open before either checked attack is resolved.
	var first_shield := _activate_if_requested(first, first_action)
	var second_shield := _activate_if_requested(second, second_action)
	var first_attack: Dictionary = {} if first_shield else first_action
	var second_attack: Dictionary = {} if second_shield else second_action
	var attacks: Dictionary = exchange.resolve_attempts(first, second, first_attack, second_attack)
	var projectiles: Dictionary = exchange.advance_projectiles(first, second)
	var first_timed_damage: int = first.tick()
	var second_timed_damage: int = second.tick()
	_age_buffer(0)
	_age_buffer(1)
	tick_index += 1
	return {
		"tick": tick_index,
		"movement": positions,
		"first_shield": first_shield,
		"second_shield": second_shield,
		"attacks": attacks,
		"projectiles": projectiles,
		"first_timed_damage": first_timed_damage,
		"second_timed_damage": second_timed_damage,
	}


func reset_round() -> void:
	first.reset_round()
	second.reset_round()
	pending = [{}, {}]
	remaining = [0, 0]
	tick_index = 0


func snapshot() -> Dictionary:
	return {
		"tick": tick_index,
		"first": first.snapshot(),
		"second": second.snapshot(),
		"pending": [pending[0].duplicate(true), pending[1].duplicate(true)],
		"remaining": remaining.duplicate(),
	}


func _store_press(index: int, input: Dictionary) -> void:
	var action: Dictionary = input.get("action", {})
	if not action.is_empty():
		pending[index] = action.duplicate(true)
		remaining[index] = GameConfig.INPUT_BUFFER_TICKS


func _take_ready_action(index: int, fighter: RefCounted) -> Dictionary:
	if remaining[index] <= 0 or pending[index].is_empty():
		return {}
	var action: Dictionary = pending[index]
	var kind: String = str(action.get("kind", ""))
	var ready := false
	if kind == "basic":
		ready = fighter.can_basic_attack()
	elif kind == "shield":
		ready = fighter.control_ticks_left == 0 and fighter.windup_move_id == "" and fighter.shield.is_ready()
	elif kind == "move":
		var move_id: String = str(action.get("id", ""))
		ready = fighter.can_begin_move(move_id)
		if ready and bool(exchange.resolver.catalog.moves.get(move_id, {}).get("projectile", false)):
			ready = fighter.active_projectile.is_empty()
	if not ready:
		return {}
	pending[index] = {}
	remaining[index] = 0
	return action


func _activate_if_requested(fighter: RefCounted, action: Dictionary) -> bool:
	if str(action.get("kind", "")) == "shield":
		return fighter.activate_shield()
	return false


func _age_buffer(index: int) -> void:
	if remaining[index] > 0:
		remaining[index] -= 1
		if remaining[index] == 0:
			pending[index] = {}
