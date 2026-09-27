class_name ShieldRuntime
extends RefCounted

const COOLDOWN_TICKS := GameConfig.SHIELD_COOLDOWN_TICKS
const REQUIRED_CONTACTS := GameConfig.SHIELD_REQUIRED_CONTACTS

var strength: int
var cooldown_ticks_left := 0
var contacts_left := 0
var active_ticks_left := 0
var recovery_ticks_left := 0
var active := false


func _init(shield_strength: int) -> void:
	strength = clampi(shield_strength, 0, GameConfig.BUILD_BUDGET)


func is_ready() -> bool:
	return strength > 0 and cooldown_ticks_left == 0 and contacts_left == 0 and recovery_ticks_left == 0 and not active


func activate() -> bool:
	if not is_ready():
		return false
	active = true
	active_ticks_left = GameConfig.SHIELD_ACTIVE_TICKS
	return true


## The parry absorbs one hit, then immediately begins both recharge gates.
func absorb_hit() -> int:
	if not active:
		return 0
	active = false
	active_ticks_left = 0
	_start_recharge()
	return strength


## Called when the fixed active window ends without contact.
func whiff() -> void:
	if active:
		active = false
		active_ticks_left = 0
		_start_recharge()
		recovery_ticks_left = GameConfig.SHIELD_WHIFF_RECOVERY_TICKS


func tick() -> void:
	cooldown_ticks_left = maxi(0, cooldown_ticks_left - 1)
	recovery_ticks_left = maxi(0, recovery_ticks_left - 1)
	if active:
		active_ticks_left -= 1
		if active_ticks_left <= 0:
			whiff()


## Any damaging basic/move hit or blocked hit counts for the attacker.
## Flourishes and whiffs never call this method.
func record_contact_action() -> void:
	contacts_left = maxi(0, contacts_left - 1)


func _start_recharge() -> void:
	cooldown_ticks_left = COOLDOWN_TICKS
	contacts_left = REQUIRED_CONTACTS


func reset_round() -> void:
	cooldown_ticks_left = 0
	contacts_left = 0
	active_ticks_left = 0
	recovery_ticks_left = 0
	active = false


func snapshot() -> Dictionary:
	return {
		"strength": strength,
		"cooldown_ticks_left": cooldown_ticks_left,
		"contacts_left": contacts_left,
		"active_ticks_left": active_ticks_left,
		"recovery_ticks_left": recovery_ticks_left,
		"active": active,
	}


func restore_snapshot(state: Dictionary) -> void:
	strength = int(state["strength"])
	cooldown_ticks_left = int(state["cooldown_ticks_left"])
	contacts_left = int(state["contacts_left"])
	active_ticks_left = int(state["active_ticks_left"])
	recovery_ticks_left = int(state["recovery_ticks_left"])
	active = bool(state["active"])
