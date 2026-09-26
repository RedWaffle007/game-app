class_name CombatExchange
extends RefCounted

const SpatialRulesScript := preload("res://src/sim/spatial_rules.gd")
const HitGeometryScript := preload("res://src/sim/hit_geometry.gd")
const ProjectileRulesScript := preload("res://src/sim/projectile_rules.gd")

var resolver: CombatResolver
var spatial: RefCounted
var geometry: RefCounted
var projectiles: RefCounted


func _init(source_catalog: FighterCatalog = null) -> void:
	resolver = CombatResolver.new(source_catalog)
	spatial = SpatialRulesScript.new()
	geometry = HitGeometryScript.new()
	projectiles = ProjectileRulesScript.new()


## Resolve both declared attacks against the state at the start of the tick.
## An empty action means no attack. Move charges are spent when the attack begins.
## This path is for scripted balance tests where attacks are already known to land.
func resolve(first: RefCounted, second: RefCounted, first_action: Dictionary, second_action: Dictionary) -> Dictionary:
	return _resolve_pair(first, second, first_action, second_action, false)


## This path checks range, facing, and physical height. A missed move still
## spends its charge, but creates no hit, effect, or shield contact.
func resolve_attempts(first: RefCounted, second: RefCounted, first_action: Dictionary, second_action: Dictionary) -> Dictionary:
	return _resolve_pair(first, second, first_action, second_action, true)


## Called once per simulation tick; fighter.tick() handles other timers.
func advance_projectiles(first: RefCounted, second: RefCounted) -> Dictionary:
	var events: Dictionary = projectiles.advance(first, second)
	var first_attack: Dictionary = events["first_attack"]
	var second_attack: Dictionary = events["second_attack"]
	var first_hit := _resolve_one(first_attack, first, second, false)
	var second_hit := _resolve_one(second_attack, second, first, false)
	var result := _commit_hits(first, second, first_attack, second_attack, first_hit, second_hit)
	result["projectiles_cancelled"] = events["cancelled"]
	return result


func _resolve_pair(first: RefCounted, second: RefCounted, first_action: Dictionary, second_action: Dictionary, check_geometry: bool) -> Dictionary:
	var first_attack := _prepare(first, first_action, check_geometry)
	var second_attack := _prepare(second, second_action, check_geometry)
	# Actions that land this tick have finished wind-up. Shock only refunds a
	# previously pending wind-up, never an attack that already connected.
	if not first_attack.is_empty():
		first.finish_windup()
	if not second_attack.is_empty():
		second.finish_windup()
	var first_hit := _resolve_one(first_attack, first, second, check_geometry)
	var second_hit := _resolve_one(second_attack, second, first, check_geometry)
	return _commit_hits(first, second, first_attack, second_attack, first_hit, second_hit)


func _commit_hits(first: RefCounted, second: RefCounted, first_attack: Dictionary, second_attack: Dictionary, first_hit: Dictionary, second_hit: Dictionary) -> Dictionary:
	var first_hp_before: int = first.hp
	var second_hp_before: int = second.hp
	var first_was_airborne: bool = first.airborne_ticks_left > 0
	var second_was_airborne: bool = second.airborne_ticks_left > 0
	var positions: Dictionary = spatial.resolve(first.x, second.x, first_hit, second_hit)

	# Both results were calculated before damage or control effects were applied.
	# Thus a lethal hit or Shock from one side cannot erase the other side's hit.
	if not first_hit.is_empty():
		second.apply_incoming_hit(first_hit)
		second.register_landed_hit(first_attack, first_hit, second_was_airborne)
		if second.shield.active:
			second.shield.absorb_hit()
		first.shield.record_contact_action()
	if not second_hit.is_empty():
		first.apply_incoming_hit(second_hit)
		first.register_landed_hit(second_attack, second_hit, first_was_airborne)
		if first.shield.active:
			first.shield.absorb_hit()
		second.shield.record_contact_action()
	# Commit net HP from the pre-hit snapshot for both fighters.
	first.hp = clampi(first_hp_before - int(second_hit.get("damage", 0)) + int(first_hit.get("heal", 0)), 0, GameConfig.MAX_HP)
	second.hp = clampi(second_hp_before - int(first_hit.get("damage", 0)) + int(second_hit.get("heal", 0)), 0, GameConfig.MAX_HP)
	first.x = positions["first_x"]
	second.x = positions["second_x"]

	return {"first_hit": first_hit, "second_hit": second_hit, "positions": positions}


func _prepare(fighter: RefCounted, action: Dictionary, check_geometry: bool) -> Dictionary:
	var kind: String = str(action.get("kind", ""))
	if kind == "basic":
		if fighter.can_basic_attack():
			return {
				"damage": GameConfig.BASIC_ATTACK_DAMAGE,
				"effect": "",
				"kind": kind,
				"range": GameConfig.BASIC_ATTACK_RANGE,
				"hitbox_min_y": GameConfig.BASIC_LOW_MIN_Y if fighter.ducking else GameConfig.BASIC_HIGH_MIN_Y,
				"hitbox_max_y": GameConfig.BASIC_LOW_MAX_Y if fighter.ducking else GameConfig.BASIC_HIGH_MAX_Y,
			}
		return {}
	if kind == "move":
		var move_id: String = str(action.get("id", ""))
		var move_data: Dictionary = resolver.catalog.moves.get(move_id, {})
		if check_geometry and bool(move_data.get("projectile", false)) and not fighter.active_projectile.is_empty():
			return {}
		if fighter.begin_move(move_id):
			var move: Dictionary = fighter.moves[move_id]
			if bool(move.get("flourish", false)):
				return {"kind": "flourish", "id": move_id}
			if check_geometry and bool(move_data.get("projectile", false)):
				projectiles.spawn(fighter, {"id": move_id, "damage": int(move["damage"]), "effect": str(move["effect"])}, move_data)
				return {"kind": "projectile_spawn", "id": move_id}
			return {
				"damage": int(move["damage"]),
				"effect": str(move["effect"]),
				"kind": kind,
				"id": move_id,
				"launch": bool(move_data.get("launch", false)),
				"range": int(move_data.get("range", 0)),
				"hitbox_min_y": int(move_data.get("hitbox_min_y", 0)),
				"hitbox_max_y": int(move_data.get("hitbox_max_y", 0)),
				"hits_behind": bool(move_data.get("hits_behind", false)),
			}
	return {}


func _resolve_one(attack: Dictionary, attacker: RefCounted, defender: RefCounted, check_geometry: bool) -> Dictionary:
	if attack.is_empty() or str(attack.get("kind", "")) == "flourish" or str(attack.get("kind", "")) == "projectile_spawn":
		return {}
	if check_geometry and not geometry.connects(attacker, defender, attack):
		return {}
	if not defender.can_receive_hit():
		return {}
	var context: Dictionary = defender.resolver_context(defender.shield.strength if defender.shield.active else 0)
	context["combo_index"] = defender.combo_index_for_hit()
	context["attacker_weakened_percent"] = attacker.current_weaken_percent()
	return resolver.resolve_hit(attack, context)
