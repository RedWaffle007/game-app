class_name EffectRuntime
extends RefCounted


## Timed effects are keyed by id, so applying the newest instance replaces the old.
## A zero-strength application removes it, implementing a fully blocked cleanse.
static func replace_timed(active: Dictionary, application: Dictionary) -> void:
	var effect_id: String = str(application.get("id", ""))
	if effect_id == "":
		return
	var strength: int = int(application.get("total_damage", application.get("percent", 0)))
	if strength <= 0:
		active.erase(effect_id)
		return
	var stored := application.duplicate(true)
	stored["elapsed_ticks"] = 0
	active[effect_id] = stored


## Returns damage due this tick. The cumulative formula delivers the exact total
## despite integer division, without floating point or stored fractional values.
static func tick_timed_damage(active: Dictionary, effect_id: String) -> int:
	if not active.has(effect_id):
		return 0
	var effect: Dictionary = active[effect_id]
	var duration: int = int(effect.get("duration_ticks", 0))
	var total: int = int(effect.get("total_damage", 0))
	if duration <= 0:
		active.erase(effect_id)
		return 0
	var before: int = int(effect.get("elapsed_ticks", 0))
	var after := mini(before + 1, duration)
	var damage := total * after / duration - total * before / duration
	effect["elapsed_ticks"] = after
	if after >= duration:
		active.erase(effect_id)
	else:
		active[effect_id] = effect
	return damage

