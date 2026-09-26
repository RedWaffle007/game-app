class_name ShieldRuntime
extends RefCounted

const COOLDOWN_TICKS := 180
const REQUIRED_CONTACTS := 2

var strength: int
var cooldown_ticks_left := 0
var contacts_left := 0
var active := false


func _init(shield_strength: int) -> void:
	strength = clampi(shield_strength, 0, GameConfig.BUILD_BUDGET)


func is_ready() -> bool:
	return strength > 0 and cooldown_ticks_left == 0 and contacts_left == 0 and not active


func activate() -> bool:
	if not is_ready():
		return false
	active = true
	return true


## The parry absorbs one hit, then immediately begins both recharge gates.
func absorb_hit() -> int:
	if not active:
		return 0
	active = false
	_start_recharge()
	return strength


## Called when the fixed active window ends without contact.
func whiff() -> void:
	if active:
		active = false
		_start_recharge()


func tick() -> void:
	cooldown_ticks_left = maxi(0, cooldown_ticks_left - 1)


## Any damaging basic/move hit or blocked hit counts for both fighters.
## Flourishes and whiffs never call this method.
func record_contact_action() -> void:
	contacts_left = maxi(0, contacts_left - 1)


func _start_recharge() -> void:
	cooldown_ticks_left = COOLDOWN_TICKS
	contacts_left = REQUIRED_CONTACTS

