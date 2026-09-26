class_name CombatResolver
extends RefCounted

var catalog: FighterCatalog


func _init(source_catalog: FighterCatalog = null) -> void:
	catalog = source_catalog if source_catalog != null else FighterCatalog.new()


## Pure hit resolution. Callers apply the returned state changes simultaneously
## when two attacks connect on the same tick.
func resolve_hit(attack: Dictionary, context: Dictionary = {}) -> Dictionary:
	var raw_damage: int = maxi(0, int(attack.get("damage", 0)))
	var combo_index: int = maxi(0, int(context.get("combo_index", 0)))
	var combo_percent: int = maxi(50, 100 - combo_index * 10)
	var weakened_percent: int = clampi(int(context.get("attacker_weakened_percent", 0)), 0, 100)
	var scaled_damage: int = raw_damage * combo_percent / 100
	scaled_damage = scaled_damage * (100 - weakened_percent) / 100

	var effect_id: String = str(attack.get("effect", ""))
	var shield: int = maxi(0, int(context.get("active_shield", 0)))
	if effect_id == "guard_break":
		shield /= 2
	var damage_through: int = maxi(0, scaled_damage - shield)
	var penetration_percent := 100
	if scaled_damage > 0:
		penetration_percent = damage_through * 100 / scaled_damage

	var result := {
		"raw_damage": raw_damage,
		"combo_index": combo_index,
		"combo_percent": combo_percent,
		"damage_before_shield": scaled_damage,
		"shield_value": shield,
		"damage": damage_through,
		"penetration_percent": penetration_percent,
		"effect": {},
		"heal": 0,
		"drain_charge": false,
		"cancel_windup": false,
		"refund_charge": false,
	}
	if effect_id == "" or not catalog.effects.has(effect_id) or scaled_damage <= 0:
		return result

	var effect: Dictionary = catalog.effects[effect_id]
	var kind: String = str(effect["kind"])
	var control_immune: bool = int(context.get("defender_control_immunity_ticks", 0)) > 0
	if control_immune and (kind == "control" or kind == "shock"):
		return result
	match kind:
		"timed_damage":
			result["effect"] = {
				"id": effect_id,
				"total_damage": int(effect["total"]) * damage_through / scaled_damage,
				"duration_ticks": int(effect["duration_ticks"]),
				"replace": true,
			}
		"displacement":
			result["effect"] = {
				"id": effect_id,
				"strength_percent": penetration_percent,
				"direction": int(effect["direction"]),
				"cancels_action": false,
			}
		"weaken":
			result["effect"] = {
				"id": effect_id,
				"percent": int(effect["percent"]) * damage_through / scaled_damage,
				"duration_ticks": int(effect["duration_ticks"]),
				"replace": true,
			}
		"lifesteal":
			result["heal"] = damage_through * int(effect["percent"]) / 100
		"control":
			var duration: int = int(effect["duration_ticks"]) * damage_through / scaled_damage
			result["effect"] = {
				"id": effect_id,
				"duration_ticks": duration,
				"pauses_windup": true,
				"grants_control_immunity": duration >= GameConfig.CONTROL_TRIGGER_TICKS,
				"immunity_ticks": GameConfig.CONTROL_IMMUNITY_TICKS if duration >= GameConfig.CONTROL_TRIGGER_TICKS else 0,
			}
		"charge_drain":
			result["drain_charge"] = damage_through * 100 >= scaled_damage * int(effect["threshold_percent"])
		"shock":
			var duration: int = int(effect["duration_ticks"]) * damage_through / scaled_damage
			var reaches_threshold: bool = damage_through * 100 >= scaled_damage * int(effect["threshold_percent"])
			result["effect"] = {
				"id": effect_id,
				"duration_ticks": duration,
				"grants_control_immunity": duration >= GameConfig.CONTROL_TRIGGER_TICKS,
				"immunity_ticks": GameConfig.CONTROL_IMMUNITY_TICKS if duration >= GameConfig.CONTROL_TRIGGER_TICKS else 0,
			}
			result["cancel_windup"] = reaches_threshold and bool(context.get("defender_in_windup", false))
			result["refund_charge"] = result["cancel_windup"]
		"guard_break":
			pass
	return result
