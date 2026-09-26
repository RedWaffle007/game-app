class_name DuelSimulator
extends RefCounted

var catalog: FighterCatalog
var validator: BuildValidator
var resolver: CombatResolver


func _init(source_catalog: FighterCatalog = null) -> void:
	catalog = source_catalog if source_catalog != null else FighterCatalog.new()
	validator = BuildValidator.new(catalog)
	resolver = CombatResolver.new(catalog)


## A deterministic smoke simulation for balance tooling. Fighters alternate legal
## charged attacks; movement, timing and player decisions will be added later.
func simulate(build_a: Dictionary, build_b: Dictionary, max_turns: int = 100) -> Dictionary:
	var checked_a := validator.validate(build_a)
	var checked_b := validator.validate(build_b)
	if not checked_a["valid"] or not checked_b["valid"]:
		return {"valid": false, "errors_a": checked_a["errors"], "errors_b": checked_b["errors"]}
	var fighters := [
		_make_fighter("A", checked_a),
		_make_fighter("B", checked_b),
	]
	var log: Array[Dictionary] = []
	var turn := 0
	while turn < max_turns and fighters[0]["hp"] > 0 and fighters[1]["hp"] > 0:
		var attacker_index := turn % 2
		var defender_index := 1 - attacker_index
		var move := _next_move(fighters[attacker_index])
		if move.is_empty():
			break
		var hit := resolver.resolve_hit({"damage": move["damage"], "effect": move["effect"]})
		fighters[defender_index]["hp"] = maxi(0, fighters[defender_index]["hp"] - hit["damage"])
		fighters[attacker_index]["hp"] = mini(GameConfig.MAX_HP, fighters[attacker_index]["hp"] + hit["heal"])
		log.append({
			"turn": turn,
			"attacker": fighters[attacker_index]["name"],
			"move": move["id"],
			"damage": hit["damage"],
			"defender_hp": fighters[defender_index]["hp"],
		})
		turn += 1
	var winner := "draw"
	if fighters[0]["hp"] > fighters[1]["hp"]:
		winner = "A"
	elif fighters[1]["hp"] > fighters[0]["hp"]:
		winner = "B"
	return {"valid": true, "winner": winner, "turns": turn, "fighters": fighters, "log": log}


func _make_fighter(fighter_name: String, checked_build: Dictionary) -> Dictionary:
	var attacks: Array[Dictionary] = []
	for move: Dictionary in checked_build["moves"]:
		if not move["flourish"]:
			attacks.append(move.duplicate(true))
	return {"name": fighter_name, "hp": GameConfig.MAX_HP, "attacks": attacks, "cursor": 0}


func _next_move(fighter: Dictionary) -> Dictionary:
	var attacks: Array = fighter["attacks"]
	if attacks.is_empty():
		return {}
	for offset in attacks.size():
		var index: int = (int(fighter["cursor"]) + offset) % attacks.size()
		if int(attacks[index]["charges"]) > 0:
			attacks[index]["charges"] -= 1
			fighter["cursor"] = (index + 1) % attacks.size()
			return attacks[index]
	return {}

