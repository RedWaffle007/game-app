class_name CombatantState
extends RefCounted

var name: String
var hp := GameConfig.MAX_HP
var x := 0
var y := 0
var ducking := false
var facing := 1
var round_start_x := 0
var round_start_facing := 1
var moves: Dictionary = {}
var move_order: Array[String] = []
var active_projectile: Dictionary = {}
var active_effects: Dictionary = {}
var last_used_move_id := ""
var windup_move_id := ""
var control_ticks_left := 0
var control_immunity_ticks_left := 0
var airborne_ticks_left := 0
var airborne_hits_taken := 0
var combo_source := ""
var combo_hits_taken := 0
var shield: ShieldRuntime


func _init(fighter_name: String, computed_moves: Array, shield_strength: int = 0, start_x: int = 0) -> void:
	name = fighter_name
	x = clampi(start_x, -GameConfig.ARENA_HALF_WIDTH, GameConfig.ARENA_HALF_WIDTH)
	round_start_x = x
	facing = -1 if x > 0 else 1
	round_start_facing = facing
	shield = ShieldRuntime.new(shield_strength)
	for raw_move: Variant in computed_moves:
		var move: Dictionary = raw_move
		var stored := move.duplicate(true)
		stored["max_charges"] = int(move["charges"])
		moves[move["id"]] = stored
		move_order.append(str(move["id"]))


func begin_move(move_id: String) -> bool:
	if control_ticks_left > 0 or ducking or shield.active or shield.recovery_ticks_left > 0 or windup_move_id != "" or not moves.has(move_id):
		return false
	var move: Dictionary = moves[move_id]
	if airborne_ticks_left > 0 and not bool(move.get("air_allowed", true)):
		return false
	if bool(move.get("flourish", false)):
		windup_move_id = move_id
		return true
	if int(move["charges"]) <= 0:
		return false
	move["charges"] = int(move["charges"]) - 1
	moves[move_id] = move
	last_used_move_id = move_id
	windup_move_id = move_id
	return true


func can_basic_attack() -> bool:
	return control_ticks_left == 0 and not shield.active and shield.recovery_ticks_left == 0 and windup_move_id == ""


func activate_shield() -> bool:
	if control_ticks_left > 0 or windup_move_id != "":
		return false
	return shield.activate()


func finish_windup() -> void:
	windup_move_id = ""


func set_ducking(wants_to_duck: bool) -> bool:
	if wants_to_duck and (airborne_ticks_left > 0 or y > 0 or control_ticks_left > 0):
		return false
	ducking = wants_to_duck
	return true


func land() -> void:
	y = 0
	airborne_ticks_left = 0
	airborne_hits_taken = 0
	if combo_source == "uppercut":
		if control_ticks_left > 0:
			combo_source = "stagger"
		else:
			_clear_combo()


func reset_round() -> void:
	hp = GameConfig.MAX_HP
	x = round_start_x
	y = 0
	ducking = false
	facing = round_start_facing
	for move_id: String in move_order:
		var move: Dictionary = moves[move_id]
		move["charges"] = int(move["max_charges"])
		moves[move_id] = move
	active_projectile.clear()
	active_effects.clear()
	last_used_move_id = ""
	windup_move_id = ""
	control_ticks_left = 0
	control_immunity_ticks_left = 0
	airborne_ticks_left = 0
	airborne_hits_taken = 0
	_clear_combo()
	shield.reset_round()


func can_receive_hit() -> bool:
	return airborne_ticks_left == 0 or airborne_hits_taken < GameConfig.MAX_AIRBORNE_COMBO_HITS


func combo_index_for_hit() -> int:
	if combo_source == "stagger" and control_ticks_left > 0:
		return combo_hits_taken
	if combo_source == "uppercut" and airborne_ticks_left > 0:
		return combo_hits_taken
	return 0


## Called after hit resolution with the defender's pre-hit airborne state.
func register_landed_hit(attack: Dictionary, hit: Dictionary, was_airborne: bool) -> void:
	if attack.is_empty() or int(hit.get("damage", 0)) <= 0:
		return
	var prior_combo_index := int(hit.get("combo_index", 0))
	if was_airborne:
		airborne_hits_taken += 1
	if bool(attack.get("launch", false)):
		y = GameConfig.LAUNCH_HURTBOX_BOTTOM_Y
		ducking = false
		airborne_ticks_left = GameConfig.UPPERCUT_AIRBORNE_TICKS
		if not was_airborne:
			airborne_hits_taken = 0
		combo_source = "uppercut"
		combo_hits_taken = prior_combo_index + 1
		return
	var application: Dictionary = hit.get("effect", {})
	if str(application.get("id", "")) == "stagger" and int(application.get("duration_ticks", 0)) > 0:
		if not was_airborne or combo_source != "uppercut":
			combo_source = "stagger"
		combo_hits_taken = prior_combo_index + 1
	elif prior_combo_index > 0:
		combo_hits_taken = prior_combo_index + 1


func current_weaken_percent() -> int:
	if not active_effects.has("weaken"):
		return 0
	return int(active_effects["weaken"].get("percent", 0))


func resolver_context(active_shield: int = 0, combo_index: int = 0) -> Dictionary:
	return {
		"active_shield": active_shield,
		"combo_index": combo_index,
		"attacker_weakened_percent": current_weaken_percent(),
		"defender_in_windup": windup_move_id != "",
		"defender_control_immunity_ticks": control_immunity_ticks_left,
	}


func apply_incoming_hit(result: Dictionary) -> void:
	hp = maxi(0, hp - int(result.get("damage", 0)))
	var application: Dictionary = result.get("effect", {})
	if not application.is_empty():
		var effect_id: String = str(application.get("id", ""))
		match effect_id:
			"burn", "poison", "weaken":
				EffectRuntime.replace_timed(active_effects, application)
			"stagger", "shock":
				if int(application.get("duration_ticks", 0)) > 0:
					_apply_control(application)
	if bool(result.get("drain_charge", false)):
		_drain_last_used_move()
	if bool(result.get("cancel_windup", false)):
		_refund_and_cancel_windup()


func apply_heal(amount: int) -> void:
	hp = mini(GameConfig.MAX_HP, hp + maxi(0, amount))


## Advances all gameplay state by exactly one simulation tick and returns damage
## caused by timed effects during that tick.
func tick() -> int:
	var timed_damage := 0
	for effect_id: String in ["burn", "poison"]:
		timed_damage += EffectRuntime.tick_timed_damage(active_effects, effect_id)
	EffectRuntime.tick_duration(active_effects, "weaken")
	hp = maxi(0, hp - timed_damage)
	control_ticks_left = maxi(0, control_ticks_left - 1)
	control_immunity_ticks_left = maxi(0, control_immunity_ticks_left - 1)
	airborne_ticks_left = maxi(0, airborne_ticks_left - 1)
	if airborne_ticks_left == 0:
		if y == GameConfig.LAUNCH_HURTBOX_BOTTOM_Y:
			y = 0
		airborne_hits_taken = 0
		if combo_source == "uppercut":
			if control_ticks_left > 0:
				combo_source = "stagger"
			else:
				_clear_combo()
	if control_ticks_left == 0 and combo_source == "stagger":
		if airborne_ticks_left > 0:
			combo_source = "uppercut"
		else:
			_clear_combo()
	shield.tick()
	return timed_damage


func snapshot() -> Dictionary:
	return {
		"name": name,
		"hp": hp,
		"x": x,
		"y": y,
		"ducking": ducking,
		"facing": facing,
		"round_start_x": round_start_x,
		"round_start_facing": round_start_facing,
		"moves": moves.duplicate(true),
		"move_order": move_order.duplicate(),
		"active_projectile": active_projectile.duplicate(true),
		"active_effects": active_effects.duplicate(true),
		"last_used_move_id": last_used_move_id,
		"windup_move_id": windup_move_id,
		"control_ticks_left": control_ticks_left,
		"control_immunity_ticks_left": control_immunity_ticks_left,
		"airborne_ticks_left": airborne_ticks_left,
		"airborne_hits_taken": airborne_hits_taken,
		"combo_source": combo_source,
		"combo_hits_taken": combo_hits_taken,
		"shield": shield.snapshot(),
	}


func _apply_control(application: Dictionary) -> void:
	var duration := maxi(0, int(application.get("duration_ticks", 0)))
	control_ticks_left = duration
	if bool(application.get("grants_control_immunity", false)):
		# Starting the gate immediately blocks chains; adding the control duration
		# preserves the full 1.5 seconds of immunity after control ends.
		control_immunity_ticks_left = duration + int(application.get("immunity_ticks", 0))


func _drain_last_used_move() -> void:
	if last_used_move_id == "" or not moves.has(last_used_move_id):
		return
	var move: Dictionary = moves[last_used_move_id]
	move["charges"] = maxi(0, int(move["charges"]) - 1)
	moves[last_used_move_id] = move


func _refund_and_cancel_windup() -> void:
	if windup_move_id == "" or not moves.has(windup_move_id):
		return
	var move: Dictionary = moves[windup_move_id]
	move["charges"] = mini(int(move["max_charges"]), int(move["charges"]) + 1)
	moves[windup_move_id] = move
	windup_move_id = ""


func _clear_combo() -> void:
	combo_source = ""
	combo_hits_taken = 0
