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
var hit_stop_ticks_left := 0


func _init(first_fighter: RefCounted, second_fighter: RefCounted, catalog: FighterCatalog = null) -> void:
	first = first_fighter
	second = second_fighter
	exchange = CombatExchangeScript.new(catalog)


## One fixed simulation tick. New button presses replace older buffered presses.
## A press is eligible on its arrival tick and the following five ticks.
func advance(first_input: Dictionary = {}, second_input: Dictionary = {}) -> Dictionary:
	_store_press(0, first_input)
	_store_press(1, second_input)
	if hit_stop_ticks_left > 0:
		hit_stop_ticks_left -= 1
		tick_index += 1
		var stationary_positions := {
			"first_x": first.x,
			"second_x": second.x,
			"first_bounced": false,
			"second_bounced": false,
		}
		return {
			"tick": tick_index,
			"hit_stop": true,
			"hit_stop_ticks_left": hit_stop_ticks_left,
			"movement": {"first_x": first.x, "second_x": second.x},
			"first_shield": false,
			"second_shield": false,
			"attacks": {"first_hit": {}, "second_hit": {}, "positions": stationary_positions},
			"projectiles": {"first_hit": {}, "second_hit": {}, "positions": stationary_positions.duplicate(), "projectiles_cancelled": false},
			"first_timed_damage": 0,
			"second_timed_damage": 0,
		}
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
	hit_stop_ticks_left = _hit_stop_for(attacks, projectiles)
	var first_timed_damage: int = first.tick()
	var second_timed_damage: int = second.tick()
	_age_buffer(0)
	_age_buffer(1)
	tick_index += 1
	return {
		"tick": tick_index,
		"hit_stop": false,
		"hit_stop_ticks_left": hit_stop_ticks_left,
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
	hit_stop_ticks_left = 0


func snapshot() -> Dictionary:
	return {
		"tick": tick_index,
		"hit_stop_ticks_left": hit_stop_ticks_left,
		"first": first.snapshot(),
		"second": second.snapshot(),
		"pending": [pending[0].duplicate(true), pending[1].duplicate(true)],
		"remaining": remaining.duplicate(),
	}


func restore_snapshot(state: Dictionary) -> void:
	tick_index = int(state["tick"])
	hit_stop_ticks_left = int(state["hit_stop_ticks_left"])
	first.restore_snapshot(state["first"])
	second.restore_snapshot(state["second"])
	pending[0] = state["pending"][0].duplicate(true)
	pending[1] = state["pending"][1].duplicate(true)
	remaining[0] = int(state["remaining"][0])
	remaining[1] = int(state["remaining"][1])


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


func _hit_stop_for(attacks: Dictionary, projectiles: Dictionary) -> int:
	var max_damage := 0
	var connected := false
	for exchange_result: Dictionary in [attacks, projectiles]:
		for key: String in ["first_hit", "second_hit"]:
			var hit: Dictionary = exchange_result[key]
			if not hit.is_empty():
				connected = true
				max_damage = maxi(max_damage, int(hit.get("damage", 0)))
	if not connected:
		return 0
	return mini(GameConfig.HIT_STOP_MAX_TICKS, GameConfig.HIT_STOP_BASE_TICKS + max_damage / GameConfig.HIT_STOP_DAMAGE_STEP)
