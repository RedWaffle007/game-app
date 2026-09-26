class_name MovementRules
extends RefCounted

const SpatialRulesScript := preload("res://src/sim/spatial_rules.gd")

var spatial: RefCounted = SpatialRulesScript.new()


## Input is an integer horizontal direction (-1, 0, 1) and optional
## jump/dash/duck booleans. Both inputs resolve from the same starting positions.
func advance(first: RefCounted, second: RefCounted, first_input: Dictionary, second_input: Dictionary) -> Dictionary:
	var first_was_left: bool = first.x <= second.x
	var proposed_first := _advance_one(first, first_input)
	var proposed_second := _advance_one(second, second_input)
	var settled: Dictionary = spatial.settle_positions(proposed_first, proposed_second, first_was_left)
	first.x = settled["first_x"]
	second.x = settled["second_x"]
	first.facing = 1 if first.x < second.x else -1
	second.facing = -first.facing
	return settled


func _advance_one(fighter: RefCounted, input: Dictionary) -> int:
	var direction := clampi(int(input.get("horizontal", 0)), -1, 1)
	var controlled: bool = fighter.control_ticks_left > 0
	fighter.set_ducking(bool(input.get("duck", false)))
	if not controlled and not fighter.ducking and bool(input.get("jump", false)) and fighter.jumps_used < GameConfig.MAX_JUMPS:
		fighter.jumps_used += 1
		fighter.vertical_speed = GameConfig.JUMP_SPEED
	if fighter.y > 0 or fighter.vertical_speed > 0:
		if fighter.airborne_ticks_left == 0 or fighter.vertical_speed != 0:
			fighter.y += fighter.vertical_speed
			fighter.vertical_speed -= GameConfig.GRAVITY_PER_TICK
			if fighter.y <= 0:
				fighter.land()
	if controlled or fighter.ducking:
		fighter.dash_ticks_left = 0
		return fighter.x
	if bool(input.get("dash", false)) and fighter.dash_ticks_left == 0:
		fighter.dash_direction = direction if direction != 0 else fighter.facing
		fighter.dash_ticks_left = GameConfig.DASH_TICKS
	if fighter.dash_ticks_left > 0:
		fighter.dash_ticks_left -= 1
		return fighter.x + fighter.dash_direction * GameConfig.DASH_SPEED
	return fighter.x + direction * GameConfig.WALK_SPEED
