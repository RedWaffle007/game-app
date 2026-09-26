class_name DuelSimulator
extends RefCounted

const CombatantStateScript := preload("res://src/sim/combatant_state.gd")
const CombatExchangeScript := preload("res://src/sim/combat_exchange.gd")

var catalog: FighterCatalog
var validator: BuildValidator
var exchange: RefCounted


func _init(source_catalog: FighterCatalog = null) -> void:
	catalog = source_catalog if source_catalog != null else FighterCatalog.new()
	validator = BuildValidator.new(catalog)
	exchange = CombatExchangeScript.new(catalog)


## A deterministic smoke simulation for balance tooling. Fighters alternate legal
## charged attacks at a configurable interval. This is not match AI; it exists to
## exercise complete builds and effect state without graphics or player input.
func simulate(
	build_a: Dictionary,
	build_b: Dictionary,
	max_turns: int = 100,
	ticks_between_turns: int = GameConfig.TICKS_PER_SECOND
) -> Dictionary:
	var checked_a := validator.validate(build_a)
	var checked_b := validator.validate(build_b)
	if not checked_a["valid"] or not checked_b["valid"]:
		return {"valid": false, "errors_a": checked_a["errors"], "errors_b": checked_b["errors"]}
	var fighters: Array = [
		_make_fighter("A", checked_a),
		_make_fighter("B", checked_b),
	]
	var cursors := [0, 0]
	var log: Array[Dictionary] = []
	var turn := 0
	while turn < max_turns and fighters[0].hp > 0 and fighters[1].hp > 0:
		var attacker_index := turn % 2
		var defender_index := 1 - attacker_index
		var selection := _next_action(fighters[attacker_index], int(cursors[attacker_index]))
		var action: Dictionary = selection["action"]
		cursors[attacker_index] = selection["next_cursor"]
		var resolved: Dictionary
		if attacker_index == 0:
			resolved = exchange.resolve(fighters[0], fighters[1], action, {})
		else:
			resolved = exchange.resolve(fighters[0], fighters[1], {}, action)
		var hit: Dictionary = resolved["first_hit"] if attacker_index == 0 else resolved["second_hit"]
		var timed_damage := [0, 0]
		for ignored in maxi(0, ticks_between_turns):
			for fighter_index in fighters.size():
				timed_damage[fighter_index] += fighters[fighter_index].tick()
		log.append({
			"turn": turn,
			"attacker": fighters[attacker_index].name,
			"move": action.get("id", "basic"),
			"damage": int(hit.get("damage", 0)),
			"timed_damage": timed_damage[defender_index],
			"defender_hp": fighters[defender_index].hp,
		})
		turn += 1
	var winner := "draw"
	if fighters[0].hp > fighters[1].hp:
		winner = "A"
	elif fighters[1].hp > fighters[0].hp:
		winner = "B"
	return {
		"valid": true,
		"winner": winner,
		"turns": turn,
		"fighters": [fighters[0].snapshot(), fighters[1].snapshot()],
		"log": log,
	}


func _make_fighter(fighter_name: String, checked_build: Dictionary) -> RefCounted:
	return CombatantStateScript.new(fighter_name, checked_build["moves"], checked_build["shield"])


func _next_action(fighter: RefCounted, cursor: int) -> Dictionary:
	for offset in fighter.move_order.size():
		var index: int = (cursor + offset) % fighter.move_order.size()
		var move_id: String = fighter.move_order[index]
		if int(fighter.moves[move_id]["charges"]) > 0:
			return {"action": {"kind": "move", "id": move_id}, "next_cursor": (index + 1) % fighter.move_order.size()}
	return {"action": {"kind": "basic"}, "next_cursor": cursor}
