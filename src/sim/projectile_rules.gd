class_name ProjectileRules
extends RefCounted


func spawn(fighter: RefCounted, attack: Dictionary, move_data: Dictionary) -> bool:
	if not fighter.active_projectile.is_empty():
		return false
	fighter.active_projectile = {
		"id": attack["id"],
		"x": fighter.x + fighter.facing * GameConfig.PROJECTILE_SPAWN_OFFSET,
		"min_y": fighter.y + int(move_data["hitbox_min_y"]),
		"max_y": fighter.y + int(move_data["hitbox_max_y"]),
		"direction": fighter.facing,
		"speed": int(move_data["projectile_speed"]),
		"radius": int(move_data["projectile_radius"]),
		"range_left": int(move_data["range"]),
		"damage": int(attack["damage"]),
		"effect": str(attack["effect"]),
	}
	return true


## Advances both projectiles once and returns attacks that connected this tick.
## Opposing projectiles cancel before either can damage a fighter.
func advance(first: RefCounted, second: RefCounted) -> Dictionary:
	var first_old := _move(first)
	var second_old := _move(second)
	var events := {"first_attack": {}, "second_attack": {}, "cancelled": false}
	if not first.active_projectile.is_empty() and not second.active_projectile.is_empty():
		if _projectiles_meet(first.active_projectile, first_old, second.active_projectile, second_old):
			first.active_projectile.clear()
			second.active_projectile.clear()
			events["cancelled"] = true
			return events
	if not first.active_projectile.is_empty():
		if _crosses_fighter(first.active_projectile, first_old, second):
			events["first_attack"] = _attack_from(first.active_projectile)
			first.active_projectile.clear()
		else:
			_expire_if_needed(first)
	if not second.active_projectile.is_empty():
		if _crosses_fighter(second.active_projectile, second_old, first):
			events["second_attack"] = _attack_from(second.active_projectile)
			second.active_projectile.clear()
		else:
			_expire_if_needed(second)
	return events


func _move(fighter: RefCounted) -> int:
	if fighter.active_projectile.is_empty():
		return 0
	var projectile: Dictionary = fighter.active_projectile
	var old_x: int = projectile["x"]
	var step := mini(int(projectile["speed"]), int(projectile["range_left"]))
	projectile["x"] = old_x + int(projectile["direction"]) * step
	projectile["range_left"] = int(projectile["range_left"]) - step
	fighter.active_projectile = projectile
	return old_x


func _projectiles_meet(first: Dictionary, first_old: int, second: Dictionary, second_old: int) -> bool:
	if int(first["direction"]) == int(second["direction"]):
		return false
	if int(first["min_y"]) >= int(second["max_y"]) or int(second["min_y"]) >= int(first["max_y"]):
		return false
	var first_min := mini(first_old, int(first["x"])) - int(first["radius"])
	var first_max := maxi(first_old, int(first["x"])) + int(first["radius"])
	var second_min := mini(second_old, int(second["x"])) - int(second["radius"])
	var second_max := maxi(second_old, int(second["x"])) + int(second["radius"])
	return first_min <= second_max and second_min <= first_max


func _crosses_fighter(projectile: Dictionary, old_x: int, defender: RefCounted) -> bool:
	var bottom: int = defender.y
	var height := GameConfig.HURTBOX_DUCK_HEIGHT if defender.ducking else GameConfig.HURTBOX_STANDING_HEIGHT
	if int(projectile["min_y"]) >= bottom + height or int(projectile["max_y"]) <= bottom:
		return false
	var left := mini(old_x, int(projectile["x"])) - int(projectile["radius"])
	var right := maxi(old_x, int(projectile["x"])) + int(projectile["radius"])
	return left <= defender.x and defender.x <= right


func _attack_from(projectile: Dictionary) -> Dictionary:
	return {
		"kind": "projectile",
		"id": projectile["id"],
		"damage": projectile["damage"],
		"effect": projectile["effect"],
	}


func _expire_if_needed(fighter: RefCounted) -> void:
	var projectile: Dictionary = fighter.active_projectile
	if int(projectile["range_left"]) <= 0 or absi(int(projectile["x"])) > GameConfig.ARENA_HALF_WIDTH:
		fighter.active_projectile.clear()
