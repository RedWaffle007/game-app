class_name MatchSession
extends RefCounted

const MatchSimulationScript := preload("res://src/sim/match_simulation.gd")

var simulation: RefCounted
var phase := "fighting"
var round_number := 1
var round_ticks_left := GameConfig.ROUND_TICKS
var first_rounds_won := 0
var second_rounds_won := 0
var last_round_winner := ""
var match_winner := ""


func _init(first: RefCounted, second: RefCounted, catalog: FighterCatalog = null) -> void:
	simulation = MatchSimulationScript.new(first, second, catalog)


## The clock counts real fixed ticks, including hit-stop. Round transitions are
## explicit so presentation can show a result before start_next_round().
func advance(first_input: Dictionary = {}, second_input: Dictionary = {}) -> Dictionary:
	if phase != "fighting" and phase != "sudden_death":
		return {"accepted": false, "phase": phase, "step": {}}
	var step: Dictionary = simulation.advance(first_input, second_input)
	if phase == "fighting":
		round_ticks_left = maxi(0, round_ticks_left - 1)
	var first_hp: int = simulation.first.hp
	var second_hp: int = simulation.second.hp
	if first_hp == 0 or second_hp == 0:
		if first_hp == second_hp:
			_finish_round("draw")
		else:
			_finish_round("second" if first_hp == 0 else "first")
	elif phase == "sudden_death":
		var first_damage := _hit_damage(step, "first_hit")
		var second_damage := _hit_damage(step, "second_hit")
		if first_damage > 0 and second_damage > 0:
			_finish_round("draw")
		elif first_damage > 0:
			_finish_round("first")
		elif second_damage > 0:
			_finish_round("second")
	elif round_ticks_left == 0:
		if first_hp > second_hp:
			_finish_round("first")
		elif second_hp > first_hp:
			_finish_round("second")
		else:
			phase = "sudden_death"
	return {"accepted": true, "phase": phase, "step": step, "round_winner": last_round_winner, "match_winner": match_winner}


func start_next_round() -> bool:
	if phase != "round_over":
		return false
	simulation.reset_round()
	round_number += 1
	round_ticks_left = GameConfig.ROUND_TICKS
	last_round_winner = ""
	phase = "fighting"
	return true


func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round_number": round_number,
		"round_ticks_left": round_ticks_left,
		"first_rounds_won": first_rounds_won,
		"second_rounds_won": second_rounds_won,
		"last_round_winner": last_round_winner,
		"match_winner": match_winner,
		"simulation": simulation.snapshot(),
	}


func _hit_damage(step: Dictionary, key: String) -> int:
	return int(step["attacks"][key].get("damage", 0)) + int(step["projectiles"][key].get("damage", 0))


func _finish_round(winner: String) -> void:
	last_round_winner = winner
	if winner == "first":
		first_rounds_won += 1
	elif winner == "second":
		second_rounds_won += 1
	if first_rounds_won >= GameConfig.ROUNDS_TO_WIN:
		match_winner = "first"
		phase = "match_over"
	elif second_rounds_won >= GameConfig.ROUNDS_TO_WIN:
		match_winner = "second"
		phase = "match_over"
	else:
		phase = "round_over"
