class_name BuildValidator
extends RefCounted

var catalog: FighterCatalog


func _init(source_catalog: FighterCatalog = null) -> void:
	catalog = source_catalog if source_catalog != null else FighterCatalog.new()


func validate(build: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var computed_moves: Array[Dictionary] = []
	var total := 0
	var seen_moves := {}
	var seen_effects := {}
	var raw_moves: Variant = build.get("moves", [])

	if not raw_moves is Array:
		errors.append("moves must be an array")
		raw_moves = []
	if raw_moves.size() != GameConfig.MAX_MOVES:
		errors.append("build must contain exactly %d moves" % GameConfig.MAX_MOVES)

	for index in raw_moves.size():
		var choice: Variant = raw_moves[index]
		if not choice is Dictionary:
			errors.append("move %d must be an object" % index)
			continue
		var move_id: String = str(choice.get("id", ""))
		var effect_id: String = str(choice.get("effect", ""))
		var power_value: Variant = choice.get("power", -1)
		if not _is_whole_number(power_value):
			errors.append("%s power must be an integer" % move_id)
			continue
		# JSON.parse_string() represents JSON numbers as floats. Convert only
		# mathematically integral values before they enter the simulation.
		var power := int(power_value)
		if not catalog.moves.has(move_id):
			errors.append("unknown move: %s" % move_id)
			continue
		if seen_moves.has(move_id):
			errors.append("move may only be selected once: %s" % move_id)
		seen_moves[move_id] = true
		if power < 0:
			errors.append("%s power cannot be negative" % move_id)
			continue
		if power > 0 and power < GameConfig.MIN_ATTACK_POWER:
			errors.append("%s needs at least %d power" % [move_id, GameConfig.MIN_ATTACK_POWER])
		if power == 0 and effect_id != "":
			errors.append("a Flourish cannot carry an effect: %s" % move_id)
		if effect_id != "":
			if not catalog.effects.has(effect_id):
				errors.append("unknown effect: %s" % effect_id)
			elif seen_effects.has(effect_id):
				errors.append("an effect may only be used once: %s" % effect_id)
			else:
				seen_effects[effect_id] = true

		var cost := catalog.move_cost(move_id, power, effect_id)
		if cost < 0:
			cost = 0
		total += cost
		computed_moves.append({
			"id": move_id,
			"power": power,
			"effect": effect_id,
			"cost": cost,
			"damage": catalog.move_damage(move_id, power),
			"air_allowed": bool(catalog.moves[move_id]["air"]),
			"charges": catalog.charges_for_cost(cost),
			"flourish": power == 0,
			"wasted_power": maxi(0, power - _max_useful_power(move_id)),
		})

	if seen_effects.size() > GameConfig.MAX_EFFECTS:
		errors.append("build may contain at most %d effects" % GameConfig.MAX_EFFECTS)

	var shield_value: Variant = build.get("shield", -1)
	var shield := 0
	if not _is_whole_number(shield_value):
		errors.append("shield must be an integer")
	else:
		shield = int(shield_value)
		if shield < 0 or shield > GameConfig.BUILD_BUDGET:
			errors.append("shield must be between 0 and %d" % GameConfig.BUILD_BUDGET)
		else:
			total += shield

	if total != GameConfig.BUILD_BUDGET:
		errors.append("build costs %d PP; expected exactly %d" % [total, GameConfig.BUILD_BUDGET])

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"total_cost": total,
		"shield": shield,
		"moves": computed_moves,
	}


func _max_useful_power(move_id: String) -> int:
	var rate: int = int(catalog.moves[move_id]["damage_rate"])
	return (GameConfig.MAX_DAMAGE_PER_HIT * 100 + rate - 1) / rate


func _is_whole_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(value) and value == floor(value)
	return false
