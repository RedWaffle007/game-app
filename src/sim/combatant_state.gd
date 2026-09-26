class_name CombatantState
extends RefCounted

var name: String
var hp := GameConfig.MAX_HP
var moves: Dictionary = {}
var move_order: Array[String] = []
var active_effects: Dictionary = {}
var last_used_move_id := ""
var windup_move_id := ""
var control_ticks_left := 0
var control_immunity_ticks_left := 0


func _init(fighter_name: String, computed_moves: Array) -> void:
	name = fighter_name
	for raw_move: Variant in computed_moves:
		var move: Dictionary = raw_move
		if bool(move.get("flourish", false)):
			continue
		var stored := move.duplicate(true)
		stored["max_charges"] = int(move["charges"])
		moves[move["id"]] = stored
		move_order.append(str(move["id"]))


func begin_move(move_id: String) -> bool:
	if control_ticks_left > 0 or not moves.has(move_id):
		return false
	var move: Dictionary = moves[move_id]
	if int(move["charges"]) <= 0:
		return false
	move["charges"] = int(move["charges"]) - 1
	moves[move_id] = move
	last_used_move_id = move_id
	windup_move_id = move_id
	return true


func finish_windup() -> void:
	windup_move_id = ""


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
	return timed_damage


func snapshot() -> Dictionary:
	return {
		"name": name,
		"hp": hp,
		"moves": moves.duplicate(true),
		"move_order": move_order.duplicate(),
		"active_effects": active_effects.duplicate(true),
		"last_used_move_id": last_used_move_id,
		"windup_move_id": windup_move_id,
		"control_ticks_left": control_ticks_left,
		"control_immunity_ticks_left": control_immunity_ticks_left,
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

