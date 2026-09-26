class_name SpatialRules
extends RefCounted


## Resolve both displacement effects from the same pre-hit positions.
## Return positions and bounce flags; callers commit both positions together.
func resolve(first_x: int, second_x: int, first_hit: Dictionary, second_hit: Dictionary) -> Dictionary:
	var first_result := _target_x(second_x, first_x, second_hit.get("effect", {}))
	var second_result := _target_x(first_x, second_x, first_hit.get("effect", {}))
	var proposed_first: int = first_result["x"]
	var proposed_second: int = second_result["x"]
	if proposed_first == first_x and proposed_second == second_x:
		return {
			"first_x": first_x,
			"second_x": second_x,
			"first_bounced": first_result["bounced"],
			"second_bounced": second_result["bounced"],
		}
	var settled := _keep_spacing(proposed_first, proposed_second, first_x <= second_x)
	return {
		"first_x": settled["first_x"],
		"second_x": settled["second_x"],
		"first_bounced": first_result["bounced"],
		"second_bounced": second_result["bounced"],
	}


func _target_x(attacker_x: int, defender_x: int, application: Dictionary) -> Dictionary:
	var result := {"x": defender_x, "bounced": false}
	var effect_id: String = str(application.get("id", ""))
	if effect_id != "knockback" and effect_id != "pull" and effect_id != "stagger":
		return result
	if attacker_x == defender_x:
		return result
	var strength := clampi(int(application.get("strength_percent", 0)), 0, 100)
	if strength == 0:
		return result
	var side := 1 if defender_x > attacker_x else -1
	var gap := absi(defender_x - attacker_x)
	var distance := 0
	if effect_id == "knockback":
		distance = maxi(0, GameConfig.LONG_RANGE - gap) * strength / 100
	elif effect_id == "pull":
		distance = maxi(0, gap - GameConfig.CLOSE_RANGE) * strength / 100
	else:
		distance = GameConfig.STAGGER_PUSH_DISTANCE * strength / 100
	var desired_x := defender_x - side * distance if effect_id == "pull" else defender_x + side * distance
	var edge := GameConfig.ARENA_HALF_WIDTH
	if effect_id == "stagger":
		result["x"] = clampi(desired_x, -edge, edge)
	elif desired_x > edge:
		result["x"] = edge - (desired_x - edge)
		result["bounced"] = true
	elif desired_x < -edge:
		result["x"] = -edge + (-edge - desired_x)
		result["bounced"] = true
	else:
		result["x"] = desired_x
	# A wall bounce may send the defender toward the attacker. Keep the
	# original sides and the minimum gap; displacement never causes a cross-up.
	if side > 0:
		result["x"] = maxi(attacker_x + GameConfig.MIN_FIGHTER_SPACING, int(result["x"]))
	else:
		result["x"] = mini(attacker_x - GameConfig.MIN_FIGHTER_SPACING, int(result["x"]))
	return result


func _keep_spacing(first_x: int, second_x: int, first_was_left: bool) -> Dictionary:
	var left := first_x if first_was_left else second_x
	var right := second_x if first_was_left else first_x
	var gap := GameConfig.MIN_FIGHTER_SPACING
	var edge := GameConfig.ARENA_HALF_WIDTH
	if right - left < gap:
		var overlap := gap - (right - left)
		left = maxi(-edge, left - overlap / 2)
		right = mini(edge, right + overlap - overlap / 2)
		if right - left < gap:
			if left == -edge:
				right = left + gap
			else:
				left = right - gap
	return {"first_x": left if first_was_left else right, "second_x": right if first_was_left else left}
