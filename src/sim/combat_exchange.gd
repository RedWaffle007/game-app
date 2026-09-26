class_name CombatExchange
extends RefCounted

var resolver: CombatResolver


func _init(source_catalog: FighterCatalog = null) -> void:
	resolver = CombatResolver.new(source_catalog)


## Resolve both declared attacks against the state at the start of the tick.
## An empty action means no attack. Move charges are spent when the attack begins.
## Position and hitbox checks belong to the caller; actions supplied here landed.
func resolve(first: RefCounted, second: RefCounted, first_action: Dictionary, second_action: Dictionary) -> Dictionary:
	var first_attack := _prepare(first, first_action)
	var second_attack := _prepare(second, second_action)
	# Actions that land this tick have finished wind-up. Shock only refunds a
	# previously pending wind-up, never an attack that already connected.
	if not first_attack.is_empty():
		first.finish_windup()
	if not second_attack.is_empty():
		second.finish_windup()
	var first_hit := _resolve_one(first_attack, first, second)
	var second_hit := _resolve_one(second_attack, second, first)
	var first_hp_before: int = first.hp
	var second_hp_before: int = second.hp

	# Both results were calculated before damage or control effects were applied.
	# Thus a lethal hit or Shock from one side cannot erase the other side's hit.
	if not first_hit.is_empty():
		second.apply_incoming_hit(first_hit)
		if second.shield.active:
			second.shield.absorb_hit()
		first.shield.record_contact_action()
	if not second_hit.is_empty():
		first.apply_incoming_hit(second_hit)
		if first.shield.active:
			first.shield.absorb_hit()
		second.shield.record_contact_action()
	# Commit net HP from the pre-hit snapshot for both fighters.
	first.hp = clampi(first_hp_before - int(second_hit.get("damage", 0)) + int(first_hit.get("heal", 0)), 0, GameConfig.MAX_HP)
	second.hp = clampi(second_hp_before - int(first_hit.get("damage", 0)) + int(second_hit.get("heal", 0)), 0, GameConfig.MAX_HP)

	return {"first_hit": first_hit, "second_hit": second_hit}


func _prepare(fighter: RefCounted, action: Dictionary) -> Dictionary:
	var kind: String = str(action.get("kind", ""))
	if kind == "basic":
		if fighter.can_basic_attack():
			return {"damage": GameConfig.BASIC_ATTACK_DAMAGE, "effect": "", "kind": kind}
		return {}
	if kind == "move":
		var move_id: String = str(action.get("id", ""))
		if fighter.begin_move(move_id):
			var move: Dictionary = fighter.moves[move_id]
			return {"damage": int(move["damage"]), "effect": str(move["effect"]), "kind": kind, "id": move_id}
	return {}


func _resolve_one(attack: Dictionary, attacker: RefCounted, defender: RefCounted) -> Dictionary:
	if attack.is_empty():
		return {}
	var context: Dictionary = defender.resolver_context(defender.shield.strength if defender.shield.active else 0)
	context["attacker_weakened_percent"] = attacker.current_weaken_percent()
	return resolver.resolve_hit(attack, context)
