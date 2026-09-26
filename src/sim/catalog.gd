class_name FighterCatalog
extends RefCounted

const MOVES_PATH := "res://data/moves.json"
const EFFECTS_PATH := "res://data/effects.json"

var moves: Dictionary
var effects: Dictionary


func _init(
	moves_override: Dictionary = {},
	effects_override: Dictionary = {}
) -> void:
	moves = moves_override.duplicate(true) if not moves_override.is_empty() else _load_json(MOVES_PATH)
	effects = effects_override.duplicate(true) if not effects_override.is_empty() else _load_json(EFFECTS_PATH)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "Missing catalog file: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Catalog must contain a JSON object: %s" % path)
	return parsed


func move_damage(move_id: String, power: int) -> int:
	if power <= 0 or not moves.has(move_id):
		return 0
	var rate: int = int(moves[move_id]["damage_rate"])
	return mini(GameConfig.MAX_DAMAGE_PER_HIT, power * rate / 100)


func move_cost(move_id: String, power: int, effect_id: String = "") -> int:
	if power == 0:
		return 0
	if not moves.has(move_id):
		return -1
	var cost: int = int(moves[move_id]["base_cost"]) + power
	if effect_id != "":
		if not effects.has(effect_id):
			return -1
		cost += int(effects[effect_id]["cost"])
	return cost


func charges_for_cost(cost: int) -> int:
	if cost <= 0:
		return 0
	return clampi(GameConfig.CHARGE_POOL / cost, GameConfig.MIN_CHARGES, GameConfig.MAX_CHARGES)

