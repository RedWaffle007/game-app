class_name HitGeometry
extends RefCounted


## All intervals are half-open. A shared edge is not enough to land a hit.
func connects(attacker: RefCounted, defender: RefCounted, attack: Dictionary) -> bool:
	var horizontal_delta: int = defender.x - attacker.x
	if not bool(attack.get("hits_behind", false)) and horizontal_delta * attacker.facing < 0:
		return false
	if absi(horizontal_delta) > int(attack.get("range", 0)):
		return false
	var attack_bottom: int = attacker.y + int(attack.get("hitbox_min_y", 0))
	var attack_top: int = attacker.y + int(attack.get("hitbox_max_y", 0))
	var hurtbox_bottom: int = defender.y
	var hurtbox_height := GameConfig.HURTBOX_DUCK_HEIGHT if defender.ducking else GameConfig.HURTBOX_STANDING_HEIGHT
	var hurtbox_top: int = hurtbox_bottom + hurtbox_height
	return attack_bottom < hurtbox_top and attack_top > hurtbox_bottom
