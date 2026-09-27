extends SceneTree

const CombatantStateScript := preload("res://src/sim/combatant_state.gd")
const CombatExchangeScript := preload("res://src/sim/combat_exchange.gd")
const MovementRulesScript := preload("res://src/sim/movement_rules.gd")
const MatchSimulationScript := preload("res://src/sim/match_simulation.gd")
const MatchSessionScript := preload("res://src/sim/match_session.gd")
const TouchControlsScript := preload("res://src/ui/touch_controls.gd")

var catalog: FighterCatalog
var validator: BuildValidator
var resolver: CombatResolver
var failures := 0
var checks := 0


func _init() -> void:
	catalog = FighterCatalog.new()
	validator = BuildValidator.new(catalog)
	resolver = CombatResolver.new(catalog)
	_test_catalog_and_costs()
	_test_build_validation()
	_test_charges()
	_test_hit_resolution()
	_test_shield_runtime()
	_test_effects()
	_test_timed_effect_replacement()
	_test_combatant_state()
	_test_combat_exchange()
	_test_spatial_effects()
	_test_stagger_push_and_round_reset()
	_test_combo_flow()
	_test_hit_geometry()
	_test_projectiles()
	_test_movement()
	_test_match_ticks_and_buffer()
	_test_hit_stop()
	_test_match_session()
	_test_snapshot_restore()
	_test_touch_controls()
	_test_android_export_config()
	_test_example_builds_and_simulation()
	if failures == 0:
		print("PASS: %d checks" % checks)
	else:
		push_error("FAIL: %d of %d checks failed" % [failures, checks])
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _test_catalog_and_costs() -> void:
	_expect(catalog.moves.size() == 10, "the MVP catalog has ten moves")
	for move_id: String in catalog.moves:
		var move: Dictionary = catalog.moves[move_id]
		_expect(int(move.get("range", 0)) > 0 and int(move.get("hitbox_max_y", 0)) > int(move.get("hitbox_min_y", 0)), "%s has a physical range and hitbox" % move_id)
	_expect(catalog.effects.size() == 10, "the effect catalog hard cap is ten")
	_expect(catalog.move_damage("jab", 100) == 80, "damage rate uses integer hundredths")
	_expect(catalog.move_damage("heavy_smash", 385) == 500, "damage is capped at 500")
	_expect(catalog.move_cost("front_kick", 100) == 110, "base cost is included")
	_expect(catalog.move_cost("dash_strike", 100, "poison") == 200, "effect cost is included")
	_expect(catalog.move_cost("spinning_slash", 0) == 0, "Flourish waives base cost")
	_expect(catalog.move_damage("straight_punch", 0) == 0, "Flourish has no damage")


func _test_build_validation() -> void:
	var json_shaped := {"shield": 400.0, "moves": [
		{"id": "jab", "power": 25.0}, {"id": "straight_punch", "power": 25.0},
		{"id": "front_kick", "power": 25.0}, {"id": "low_sweep", "power": 5.0},
	]}
	var result := validator.validate(json_shaped)
	_expect(not _has_error(result, "must be an integer"), "integral JSON numbers are normalized at the boundary")
	json_shaped["moves"][0]["power"] = 25.5
	_expect(_has_error(validator.validate(json_shaped), "must be an integer"), "fractional JSON numbers are rejected")

	var duplicate := {"shield": 400, "moves": [
		{"id": "jab", "power": 25}, {"id": "jab", "power": 25},
		{"id": "front_kick", "power": 25}, {"id": "low_sweep", "power": 5},
	]}
	result = validator.validate(duplicate)
	_expect(not result["valid"], "duplicate moves and sub-minimum power are rejected")
	_expect(_has_error(result, "only be selected once"), "duplicate move error is reported")
	_expect(_has_error(result, "at least 25 power"), "minimum attack power error is reported")

	var bad_effects := {"shield": 40, "moves": [
		{"id": "jab", "power": 100, "effect": "burn"},
		{"id": "straight_punch", "power": 100, "effect": "burn"},
		{"id": "front_kick", "power": 100, "effect": "poison"},
		{"id": "low_sweep", "power": 25, "effect": "pull"},
	]}
	result = validator.validate(bad_effects)
	_expect(_has_error(result, "only be used once"), "effects must be different")
	_expect(_has_error(result, "at most 2 effects"), "only two effects are allowed")

	var flourish_effect := {"shield": 500, "moves": [
		{"id": "jab", "power": 0, "effect": "burn"}, {"id": "front_kick", "power": 0},
		{"id": "low_sweep", "power": 0}, {"id": "sword_slash", "power": 0},
	]}
	_expect(_has_error(validator.validate(flourish_effect), "Flourish cannot carry"), "Flourishes reject effects")
	var air_rules := validator.validate({"shield": 380, "moves": [
		{"id": "low_sweep", "power": 25}, {"id": "jab", "power": 25},
		{"id": "straight_punch", "power": 25}, {"id": "front_kick", "power": 25},
	]})
	_expect(air_rules["valid"] and not air_rules["moves"][0]["air_allowed"] and air_rules["moves"][1]["air_allowed"], "air use restriction comes from catalog data")


func _test_charges() -> void:
	_expect(catalog.charges_for_cost(75) == 8, "75 cost gives 8 charges")
	_expect(catalog.charges_for_cost(150) == 4, "150 cost gives 4 charges")
	_expect(catalog.charges_for_cost(300) == 2, "300 cost gives 2 charges")
	_expect(catalog.charges_for_cost(500) == 1, "500 cost gives 1 charge")
	_expect(catalog.charges_for_cost(10) == 8, "charges are capped at 8")
	_expect(catalog.charges_for_cost(0) == 0, "Flourishes do not use charges")


func _test_hit_resolution() -> void:
	var hit := resolver.resolve_hit({"damage": 200}, {"active_shield": 75})
	_expect(hit["damage"] == 125, "active shield subtracts from damage")
	_expect(hit["penetration_percent"] == 62, "penetration rounds down")
	hit = resolver.resolve_hit({"damage": 200}, {"combo_index": 3, "attacker_weakened_percent": 20})
	_expect(hit["combo_percent"] == 70 and hit["damage"] == 112, "combo then Weaken order is fixed")
	hit = resolver.resolve_hit({"damage": 200}, {"combo_index": 99})
	_expect(hit["damage"] == 100, "combo scaling floors at 50 percent")
	hit = resolver.resolve_hit({"damage": 100, "effect": "guard_break"}, {"active_shield": 80})
	_expect(hit["shield_value"] == 40 and hit["damage"] == 60, "Guard Break halves shield first")


func _test_shield_runtime() -> void:
	var disabled := ShieldRuntime.new(0)
	_expect(not disabled.activate(), "zero-strength shield is disabled")
	var shield := ShieldRuntime.new(120)
	_expect(shield.activate() and shield.absorb_hit() == 120, "shield absorbs exactly one hit")
	for ignored in ShieldRuntime.COOLDOWN_TICKS:
		shield.tick()
	_expect(not shield.is_ready(), "elapsed time alone does not recharge shield")
	shield.record_contact_action()
	shield.record_contact_action()
	_expect(shield.is_ready(), "shield needs three seconds and two contacts")
	_expect(shield.activate(), "recharged shield can activate")
	shield.whiff()
	_expect(not shield.is_ready(), "a whiff starts punishable recharge")
	var window := ShieldRuntime.new(100)
	_expect(window.activate(), "shield can open its active window")
	for ignored in GameConfig.SHIELD_ACTIVE_TICKS:
		window.tick()
	_expect(not window.active and window.recovery_ticks_left == GameConfig.SHIELD_WHIFF_RECOVERY_TICKS, "parry window expires into fixed whiff recovery")


func _test_effects() -> void:
	var hit := resolver.resolve_hit({"damage": 100, "effect": "burn"}, {"active_shield": 50})
	_expect(hit["effect"]["total_damage"] == 15 and hit["effect"]["duration_ticks"] == 180, "Burn strength scales but duration does not")
	hit = resolver.resolve_hit({"damage": 100, "effect": "poison"})
	_expect(hit["effect"]["total_damage"] == 40 and hit["effect"]["duration_ticks"] == 480, "Poison applies at full strength")
	hit = resolver.resolve_hit({"damage": 100, "effect": "knockback"}, {"active_shield": 25})
	_expect(hit["effect"]["strength_percent"] == 75 and not hit["effect"]["cancels_action"], "Knockback scales and does not cancel")
	hit = resolver.resolve_hit({"damage": 100, "effect": "pull"}, {"active_shield": 50})
	_expect(hit["effect"]["direction"] == -1 and hit["effect"]["strength_percent"] == 50, "Pull scales toward attacker")
	hit = resolver.resolve_hit({"damage": 100, "effect": "weaken"}, {"active_shield": 50})
	_expect(hit["effect"]["percent"] == 10 and hit["effect"]["duration_ticks"] == 180, "Weaken magnitude scales")
	hit = resolver.resolve_hit({"damage": 99, "effect": "lifesteal"})
	_expect(hit["heal"] == 29, "Lifesteal rounds down and is based on damage through")
	hit = resolver.resolve_hit({"damage": 100, "effect": "stagger"}, {"active_shield": 50})
	_expect(hit["effect"]["duration_ticks"] == 18 and hit["effect"]["pauses_windup"], "Stagger scales and pauses wind-up")
	_expect(hit["effect"]["grants_control_immunity"], "control lasting at least 0.2 seconds grants immunity")
	hit = resolver.resolve_hit({"damage": 100, "effect": "charge_drain"}, {"active_shield": 51})
	_expect(not hit["drain_charge"], "Charge Drain needs 50 percent penetration")
	hit = resolver.resolve_hit({"damage": 100, "effect": "charge_drain"}, {"active_shield": 50})
	_expect(hit["drain_charge"], "Charge Drain triggers at exactly 50 percent")
	hit = resolver.resolve_hit({"damage": 100, "effect": "shock"}, {"active_shield": 50, "defender_in_windup": true})
	_expect(hit["cancel_windup"] and hit["refund_charge"], "Shock cancels and refunds wind-up at threshold")
	_expect(hit["effect"]["duration_ticks"] == 15, "Shock freeze scales with penetration")
	hit = resolver.resolve_hit({"damage": 100, "effect": "shock"}, {"active_shield": 51, "defender_in_windup": true})
	_expect(not hit["cancel_windup"], "Shock below threshold does not reset wind-up")
	hit = resolver.resolve_hit({"damage": 100, "effect": "stagger"}, {"defender_control_immunity_ticks": 1})
	_expect(hit["effect"].is_empty(), "shared immunity blocks Stagger")
	hit = resolver.resolve_hit({"damage": 100, "effect": "shock"}, {"defender_control_immunity_ticks": 1, "defender_in_windup": true})
	_expect(hit["effect"].is_empty() and not hit["cancel_windup"], "shared immunity blocks Shock and its reset")


func _test_timed_effect_replacement() -> void:
	var active := {}
	EffectRuntime.replace_timed(active, {"id": "poison", "total_damage": 40, "duration_ticks": 480})
	for ignored in 240:
		EffectRuntime.tick_timed_damage(active, "poison")
	EffectRuntime.replace_timed(active, {"id": "poison", "total_damage": 4, "duration_ticks": 480})
	_expect(active["poison"]["total_damage"] == 4 and active["poison"]["elapsed_ticks"] == 0, "new timed effect replaces and resets old one")
	EffectRuntime.replace_timed(active, {"id": "poison", "total_damage": 0, "duration_ticks": 480})
	_expect(not active.has("poison"), "fully blocked timed effect cleanses the old effect")
	EffectRuntime.replace_timed(active, {"id": "burn", "total_damage": 30, "duration_ticks": 180})
	var delivered := 0
	for ignored in 180:
		delivered += EffectRuntime.tick_timed_damage(active, "burn")
	_expect(delivered == 30 and not active.has("burn"), "integer tick distribution delivers exact total")


func _test_combatant_state() -> void:
	var build := validator.validate({"shield": 300, "moves": [
		{"id": "jab", "power": 100}, {"id": "straight_punch", "power": 100},
		{"id": "front_kick", "power": 0}, {"id": "sword_slash", "power": 0},
	]})
	var fighter := CombatantStateScript.new("test", build["moves"])
	var jab_max: int = fighter.moves["jab"]["max_charges"]
	_expect(fighter.begin_move("jab"), "a charged move can begin")
	_expect(fighter.moves["jab"]["charges"] == jab_max - 1, "beginning a move spends one charge")
	fighter.apply_incoming_hit({"damage": 0, "effect": {}, "drain_charge": true})
	_expect(fighter.moves["jab"]["charges"] == jab_max - 2, "Charge Drain removes one charge from the most recently used move")
	fighter.apply_incoming_hit({"damage": 0, "effect": {}, "cancel_windup": true})
	_expect(fighter.moves["jab"]["charges"] == jab_max - 1 and fighter.windup_move_id == "", "Shock cancellation refunds the wind-up charge")

	fighter.hp = 990
	fighter.apply_heal(30)
	_expect(fighter.hp == GameConfig.MAX_HP, "healing never exceeds max HP")
	fighter.apply_incoming_hit({"damage": 100, "effect": {"id": "poison", "total_damage": 40, "duration_ticks": 480}})
	var poison_damage := 0
	for ignored in 480:
		poison_damage += fighter.tick()
	_expect(fighter.hp == 860 and poison_damage == 40, "direct and timed damage update HP deterministically")

	fighter.apply_incoming_hit({"damage": 0, "effect": {"id": "weaken", "percent": 20, "duration_ticks": 3}})
	_expect(fighter.current_weaken_percent() == 20, "Weaken is exposed to outgoing hit resolution")
	fighter.tick()
	fighter.tick()
	fighter.tick()
	_expect(fighter.current_weaken_percent() == 0, "Weaken expires on its exact tick")

	fighter.apply_incoming_hit({"damage": 0, "effect": {
		"id": "stagger", "duration_ticks": 12, "grants_control_immunity": true,
		"immunity_ticks": GameConfig.CONTROL_IMMUNITY_TICKS,
	}})
	_expect(fighter.control_ticks_left == 12, "Stagger prevents actions for its scaled duration")
	_expect(not fighter.begin_move("straight_punch"), "a controlled fighter cannot begin a move")
	fighter.apply_incoming_hit({"damage": 0, "effect": {"id": "stagger", "duration_ticks": 0}})
	_expect(fighter.control_ticks_left == 12, "zero-duration control does not erase an active control timer")
	for ignored in 12:
		fighter.tick()
	_expect(fighter.control_ticks_left == 0 and fighter.control_immunity_ticks_left == 90, "control immunity lasts 1.5 seconds after control")
	var snapshot := fighter.snapshot()
	snapshot["moves"]["jab"]["charges"] = 0
	_expect(fighter.moves["jab"]["charges"] != 0, "rollback snapshot is a deep copy")


func _test_combat_exchange() -> void:
	var strong := [{"id": "heavy_smash", "charges": 1, "damage": 500, "effect": "", "flourish": false}]
	var first := CombatantStateScript.new("first", strong)
	var second := CombatantStateScript.new("second", strong)
	first.hp = 500
	second.hp = 500
	var exchange := CombatExchangeScript.new(catalog)
	var trade: Dictionary = exchange.resolve(first, second, {"kind": "move", "id": "heavy_smash"}, {"kind": "move", "id": "heavy_smash"})
	_expect(first.hp == 0 and second.hp == 0, "simultaneous lethal attacks both deal damage")
	_expect(trade["first_hit"]["damage"] == 500 and trade["second_hit"]["damage"] == 500, "both sides of a trade resolve from pre-hit state")
	_expect(first.moves["heavy_smash"]["charges"] == 0 and second.moves["heavy_smash"]["charges"] == 0, "both trading moves spend charges")

	var shielded := CombatantStateScript.new("shielded", [], 100)
	var striker := CombatantStateScript.new("striker", [])
	_expect(shielded.activate_shield(), "combatant can activate an allocated shield")
	var blocked: Dictionary = exchange.resolve(striker, shielded, {"kind": "basic"}, {})
	_expect(blocked["first_hit"]["damage"] == 0 and shielded.hp == GameConfig.MAX_HP, "basic attack is fully absorbed by active shield")
	_expect(not shielded.shield.active and shielded.shield.cooldown_ticks_left == 180, "first contact consumes the parry")
	_expect(striker.shield.contacts_left == 0, "contact accounting does not create a cooldown for unused shields")
	blocked = exchange.resolve(striker, shielded, {"kind": "basic"}, {})
	_expect(blocked["first_hit"]["damage"] == 20 and shielded.hp == 980, "later hits bypass spent shield")

	var recharger := CombatantStateScript.new("recharger", [], 100)
	var target := CombatantStateScript.new("target", [])
	_expect(recharger.activate_shield(), "shield starts ready")
	recharger.shield.whiff()
	for ignored in ShieldRuntime.COOLDOWN_TICKS:
		recharger.tick()
	_expect(not recharger.shield.is_ready(), "time alone cannot recharge a whiffed shield")
	exchange.resolve(recharger, target, {"kind": "basic"}, {})
	exchange.resolve(recharger, target, {"kind": "basic"}, {})
	_expect(recharger.shield.is_ready(), "two basic attack contacts complete shield recharge")

	var toxic := CombatantStateScript.new("toxic", [{"id": "jab", "charges": 1, "damage": 100, "effect": "poison", "flourish": false}])
	var victim := CombatantStateScript.new("victim", [])
	exchange.resolve(toxic, victim, {"kind": "basic"}, {})
	_expect(not victim.active_effects.has("poison"), "basic attack never triggers a move effect")
	exchange.resolve(toxic, victim, {"kind": "move", "id": "jab"}, {})
	_expect(victim.active_effects.has("poison"), "charged move triggers its effect")

	var draining_shield := CombatantStateScript.new("draining_shield", [], 100)
	var poison_move := CombatantStateScript.new("poison_move", [{"id": "jab", "charges": 1, "damage": 100, "effect": "poison", "flourish": false}])
	draining_shield.active_effects["poison"] = {"id": "poison", "total_damage": 40, "duration_ticks": 480, "elapsed_ticks": 200}
	_expect(draining_shield.activate_shield(), "active parry can protect a poisoned fighter")
	exchange.resolve(poison_move, draining_shield, {"kind": "move", "id": "jab"}, {})
	_expect(not draining_shield.active_effects.has("poison"), "fully blocked Poison application cleanses existing Poison")

	var life_fighter := CombatantStateScript.new("life", [{"id": "jab", "charges": 1, "damage": 100, "effect": "lifesteal", "flourish": false}])
	var lethal_fighter := CombatantStateScript.new("lethal", [{"id": "heavy_smash", "charges": 1, "damage": 100, "effect": "", "flourish": false}])
	life_fighter.hp = 50
	lethal_fighter.hp = 50
	exchange.resolve(lethal_fighter, life_fighter, {"kind": "move", "id": "heavy_smash"}, {"kind": "move", "id": "jab"})
	_expect(life_fighter.hp == 0 and lethal_fighter.hp == 0, "simultaneous Lifesteal does not revive after net lethal damage")

	var flourisher := CombatantStateScript.new("flourisher", [{"id": "front_kick", "charges": 0, "damage": 0, "effect": "", "flourish": true}], 100, -100)
	var spectator := CombatantStateScript.new("spectator", [], 0, 100)
	_expect(flourisher.activate_shield(), "flourisher can enter shield cooldown")
	flourisher.shield.whiff()
	for ignored in ShieldRuntime.COOLDOWN_TICKS:
		flourisher.tick()
	var flourish_result: Dictionary = exchange.resolve(flourisher, spectator, {"kind": "move", "id": "front_kick"}, {})
	_expect(flourish_result["first_hit"].is_empty() and spectator.hp == GameConfig.MAX_HP, "Flourish produces no hit or damage")
	_expect(flourisher.x == -100 and spectator.x == 100 and flourisher.shield.contacts_left == 2, "Flourish has no movement or shield contact")
	_expect(flourisher.moves["front_kick"]["charges"] == 0 and flourisher.windup_move_id == "", "Flourish spends no charge and completes its action")
	flourish_result = exchange.resolve(flourisher, spectator, {"kind": "move", "id": "front_kick"}, {})
	_expect(flourish_result["first_hit"].is_empty(), "Flourish remains usable without charges")


func _test_spatial_effects() -> void:
	var exchange := CombatExchangeScript.new(catalog)
	var knockback_move := [{"id": "jab", "charges": 1, "damage": 100, "effect": "knockback", "flourish": false}]
	var attacker := CombatantStateScript.new("attacker", knockback_move, 0, -100)
	var defender := CombatantStateScript.new("defender", [], 0, 100)
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(attacker.x == -100 and defender.x == 400, "full Knockback reaches long range without moving the attacker")

	attacker = CombatantStateScript.new("attacker", knockback_move, 0, -100)
	defender = CombatantStateScript.new("defender", [], 50, 100)
	_expect(defender.activate_shield(), "partial Knockback test has an active parry")
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(defender.x == 250, "half-penetrating Knockback moves half the distance")

	attacker = CombatantStateScript.new("attacker", knockback_move, 0, 700)
	defender = CombatantStateScript.new("defender", [], 0, 900)
	var wall_hit: Dictionary = exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(defender.x == 800 and wall_hit["positions"]["second_bounced"], "Knockback reflects once at the arena wall")

	var pull_move := [{"id": "jab", "charges": 1, "damage": 100, "effect": "pull", "flourish": false}]
	attacker = CombatantStateScript.new("attacker", pull_move, 0, -250)
	defender = CombatantStateScript.new("defender", [], 0, 250)
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(defender.x == -150, "full Pull stops at close range")

	attacker = CombatantStateScript.new("attacker", knockback_move, 0, -100)
	defender = CombatantStateScript.new("defender", [], 100, 100)
	_expect(defender.activate_shield(), "fully blocked displacement test has an active parry")
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(defender.x == 100, "fully blocked Knockback causes no displacement")

	attacker = CombatantStateScript.new("attacker", knockback_move, 0, -100)
	defender = CombatantStateScript.new("defender", [{"id": "straight_punch", "charges": 2, "damage": 50, "effect": "", "flourish": false}], 0, 100)
	_expect(defender.begin_move("straight_punch"), "defender begins a wind-up")
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(defender.x == 400 and defender.windup_move_id == "straight_punch", "Knockback moves without cancelling wind-up")

	var first := CombatantStateScript.new("first", pull_move, 0, -250)
	var second := CombatantStateScript.new("second", pull_move, 0, 250)
	exchange.resolve(first, second, {"kind": "move", "id": "jab"}, {"kind": "move", "id": "jab"})
	_expect(first.x == -20 and second.x == 20, "simultaneous Pull settles without overlap or order bias")


func _test_stagger_push_and_round_reset() -> void:
	var exchange := CombatExchangeScript.new(catalog)
	var stagger_move := [{"id": "jab", "charges": 1, "damage": 100, "effect": "stagger", "flourish": false}]
	var attacker := CombatantStateScript.new("attacker", stagger_move, 0, -100)
	var defender := CombatantStateScript.new("defender", [{"id": "straight_punch", "charges": 2, "damage": 50, "effect": "", "flourish": false}], 0, 100)
	_expect(defender.begin_move("straight_punch"), "defender begins a wind-up before Stagger")
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(defender.x == 160 and defender.control_ticks_left == 36, "full Stagger pushes slightly and applies its control duration")
	_expect(defender.windup_move_id == "straight_punch", "Stagger keeps the defender's wind-up paused")

	attacker = CombatantStateScript.new("attacker", stagger_move, 0, -100)
	defender = CombatantStateScript.new("defender", [], 50, 100)
	_expect(defender.activate_shield(), "partial Stagger test starts with an active parry")
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(defender.x == 130 and defender.control_ticks_left == 18, "partial Stagger scales push and duration")

	attacker = CombatantStateScript.new("attacker", stagger_move, 0, -100)
	defender = CombatantStateScript.new("defender", [], 100, 100)
	_expect(defender.activate_shield(), "full Stagger block starts with an active parry")
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(defender.x == 100 and defender.control_ticks_left == 0, "fully blocked Stagger neither moves nor controls")

	var round_fighter := CombatantStateScript.new("round", [{"id": "jab", "charges": 3, "damage": 100, "effect": "", "flourish": false}], 100, 250)
	var starting_snapshot: Dictionary = round_fighter.snapshot()
	_expect(round_fighter.begin_move("jab"), "round fighter spends a charge")
	round_fighter.finish_windup()
	_expect(round_fighter.activate_shield(), "round fighter opens its shield")
	round_fighter.shield.absorb_hit()
	round_fighter.apply_incoming_hit({"damage": 200, "effect": {"id": "burn", "total_damage": 30, "duration_ticks": 180}})
	round_fighter.apply_incoming_hit({"damage": 0, "effect": {"id": "stagger", "duration_ticks": 36, "grants_control_immunity": true, "immunity_ticks": 90}})
	round_fighter.x = 777
	_expect(round_fighter.snapshot() != starting_snapshot, "round state changed before reset")
	round_fighter.reset_round()
	_expect(round_fighter.snapshot() == starting_snapshot, "new round restores HP, position, charges, effects, controls, and shield")


func _test_combo_flow() -> void:
	var exchange := CombatExchangeScript.new(catalog)
	var attacker := CombatantStateScript.new("attacker", [
		{"id": "jab", "charges": 1, "damage": 100, "effect": "stagger", "flourish": false},
		{"id": "straight_punch", "charges": 1, "damage": 100, "effect": "", "flourish": false},
	])
	var defender := CombatantStateScript.new("defender", [])
	var opener: Dictionary = exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(opener["first_hit"]["damage"] == 100 and defender.combo_source == "stagger", "Stagger opener deals full damage and starts a combo")
	var followup: Dictionary = exchange.resolve(attacker, defender, {"kind": "move", "id": "straight_punch"}, {})
	_expect(followup["first_hit"]["damage"] == 90 and followup["first_hit"]["combo_percent"] == 90, "first Stagger follow-up is scaled by ten percent")
	followup = exchange.resolve(attacker, defender, {"kind": "basic"}, {})
	_expect(followup["first_hit"]["damage"] == 16 and followup["first_hit"]["combo_percent"] == 80, "subsequent combo hits continue scaling")
	for ignored in 36:
		defender.tick()
	followup = exchange.resolve(attacker, defender, {"kind": "basic"}, {})
	_expect(followup["first_hit"]["damage"] == 20 and defender.combo_source == "", "Stagger combo resets when control ends")

	attacker = CombatantStateScript.new("attacker", [{"id": "uppercut", "charges": 1, "damage": 100, "effect": "", "flourish": false}])
	defender = CombatantStateScript.new("defender", [
		{"id": "low_sweep", "charges": 1, "damage": 50, "effect": "", "flourish": false, "air_allowed": false},
		{"id": "jab", "charges": 1, "damage": 50, "effect": "", "flourish": false, "air_allowed": true},
	])
	opener = exchange.resolve(attacker, defender, {"kind": "move", "id": "uppercut"}, {})
	_expect(opener["first_hit"]["damage"] == 100 and defender.airborne_ticks_left == GameConfig.UPPERCUT_AIRBORNE_TICKS, "Uppercut opens an airborne combo")
	_expect(defender.control_ticks_left == 0 and defender.begin_move("jab"), "launched fighter keeps air control and can use an air move")
	defender.finish_windup()
	_expect(not defender.begin_move("low_sweep"), "ground-only move cannot start while airborne")
	for expected_damage in [18, 16, 14]:
		followup = exchange.resolve(attacker, defender, {"kind": "basic"}, {})
		_expect(followup["first_hit"]["damage"] == expected_damage, "airborne combo follow-up uses the next scaling step")
	followup = exchange.resolve(attacker, defender, {"kind": "basic"}, {})
	_expect(followup["first_hit"].is_empty() and defender.airborne_hits_taken == 3, "fourth airborne follow-up cannot connect")
	defender.land()
	followup = exchange.resolve(attacker, defender, {"kind": "basic"}, {})
	_expect(followup["first_hit"]["damage"] == 20 and defender.combo_source == "", "landing restores normal damage and hit eligibility")

	attacker = CombatantStateScript.new("attacker", [{"id": "uppercut", "charges": 1, "damage": 100, "effect": "", "flourish": false}])
	defender = CombatantStateScript.new("defender", [])
	exchange.resolve(attacker, defender, {"kind": "move", "id": "uppercut"}, {})
	for ignored in GameConfig.UPPERCUT_AIRBORNE_TICKS:
		defender.tick()
	_expect(defender.airborne_ticks_left == 0 and defender.combo_source == "", "airborne combo also expires after its tick duration")

	attacker = CombatantStateScript.new("attacker", [
		{"id": "uppercut", "charges": 1, "damage": 100, "effect": "", "flourish": false},
		{"id": "jab", "charges": 1, "damage": 100, "effect": "stagger", "flourish": false},
	])
	defender = CombatantStateScript.new("defender", [])
	exchange.resolve(attacker, defender, {"kind": "move", "id": "uppercut"}, {})
	exchange.resolve(attacker, defender, {"kind": "move", "id": "jab"}, {})
	defender.land()
	followup = exchange.resolve(attacker, defender, {"kind": "basic"}, {})
	_expect(defender.combo_source == "stagger" and followup["first_hit"]["damage"] == 16, "Stagger continues an Uppercut combo after landing")

	attacker = CombatantStateScript.new("attacker", [])
	defender = CombatantStateScript.new("defender", [])
	exchange.resolve(attacker, defender, {"kind": "basic"}, {})
	followup = exchange.resolve(attacker, defender, {"kind": "basic"}, {})
	_expect(followup["first_hit"]["damage"] == 20 and defender.combo_source == "", "ordinary hits never start a combo")


func _test_hit_geometry() -> void:
	var exchange := CombatExchangeScript.new(catalog)
	var jab := [{"id": "jab", "charges": 1, "damage": 100, "effect": "", "flourish": false}]
	var attacker := CombatantStateScript.new("attacker", jab, 0, -250)
	var defender := CombatantStateScript.new("defender", [], 100, 250)
	_expect(defender.activate_shield(), "distant defender has an active parry")
	var attempt: Dictionary = exchange.resolve_attempts(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(attempt["first_hit"].is_empty() and attacker.moves["jab"]["charges"] == 0, "out-of-range move whiffs and still spends its charge")
	_expect(defender.shield.active and defender.hp == GameConfig.MAX_HP, "a whiff does not consume shield or deal damage")

	attacker = CombatantStateScript.new("attacker", jab, 0, -60)
	defender = CombatantStateScript.new("defender", [], 0, 0)
	_expect(defender.set_ducking(true), "grounded defender can duck")
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(attempt["first_hit"].is_empty(), "ducking hurtbox avoids a physically high Jab")

	var sweep := [{"id": "low_sweep", "charges": 1, "damage": 100, "effect": "", "flourish": false, "air_allowed": false}]
	attacker = CombatantStateScript.new("attacker", sweep, 0, -60)
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "move", "id": "low_sweep"}, {})
	_expect(attempt["first_hit"]["damage"] == 100, "Low Sweep reaches a ducking hurtbox")

	var overhead := [{"id": "heavy_smash", "charges": 1, "damage": 100, "effect": "", "flourish": false}]
	attacker = CombatantStateScript.new("attacker", overhead, 0, -60)
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "move", "id": "heavy_smash"}, {})
	_expect(attempt["first_hit"]["damage"] == 100, "Mid overhead reaches a ducking hurtbox")

	attacker = CombatantStateScript.new("attacker", sweep, 0, -60)
	_expect(attacker.set_ducking(true), "attacker can crouch for a low basic poke")
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "basic"}, {})
	_expect(attempt["first_hit"]["damage"] == GameConfig.BASIC_ATTACK_DAMAGE, "ducking basic attack becomes a low poke")
	_expect(not attacker.begin_move("low_sweep") and attacker.can_basic_attack(), "ducking permits basic attack but not a catalog move")

	attacker = CombatantStateScript.new("attacker", sweep, 0, -60)
	defender = CombatantStateScript.new("defender", [], 0, 0)
	defender.y = GameConfig.LAUNCH_HURTBOX_BOTTOM_Y
	defender.airborne_ticks_left = 10
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "move", "id": "low_sweep"}, {})
	_expect(attempt["first_hit"].is_empty(), "airborne hurtbox passes above Low Sweep")
	_expect(not defender.set_ducking(true), "airborne fighter cannot duck")

	attacker = CombatantStateScript.new("attacker", jab, 0, -60)
	defender = CombatantStateScript.new("defender", [], 100, 0)
	defender.y = GameConfig.LAUNCH_HURTBOX_BOTTOM_Y
	defender.airborne_ticks_left = 10
	_expect(defender.activate_shield(), "airborne fighter can parry")
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "move", "id": "jab"}, {})
	_expect(attempt["first_hit"]["damage"] == 0 and not defender.shield.active, "airborne parry absorbs a high attack")

	attacker = CombatantStateScript.new("attacker", [{"id": "straight_punch", "charges": 1, "damage": 100, "effect": "", "flourish": false}], 0, 0)
	defender = CombatantStateScript.new("defender", [], 0, -60)
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "move", "id": "straight_punch"}, {})
	_expect(attempt["first_hit"].is_empty(), "forward punch does not hit a fighter behind its facing")
	attacker = CombatantStateScript.new("attacker", [{"id": "spinning_slash", "charges": 1, "damage": 100, "effect": "", "flourish": false}], 0, 0)
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "move", "id": "spinning_slash"}, {})
	_expect(attempt["first_hit"]["damage"] == 100, "Spinning Slash hitbox reaches behind")

	attacker = CombatantStateScript.new("attacker", [], 0, -60)
	defender = CombatantStateScript.new("defender", [{"id": "jab", "charges": 1, "damage": 50, "effect": "", "flourish": false}], 0, 0)
	_expect(defender.begin_move("jab"), "defender starts a wind-up before a normal hit")
	attempt = exchange.resolve_attempts(attacker, defender, {"kind": "basic"}, {})
	_expect(attempt["first_hit"]["damage"] == 20 and defender.windup_move_id == "jab", "normal hit deals damage without cancelling wind-up")


func _test_projectiles() -> void:
	var exchange := CombatExchangeScript.new(catalog)
	var fireball := [{"id": "fireball", "charges": 2, "damage": 100, "effect": "", "flourish": false}]
	var first := CombatantStateScript.new("first", fireball, 0, -250)
	var second := CombatantStateScript.new("second", [], 0, 250)
	var launched: Dictionary = exchange.resolve_attempts(first, second, {"kind": "move", "id": "fireball"}, {})
	_expect(launched["first_hit"].is_empty() and second.hp == GameConfig.MAX_HP, "Fireball launch deals no immediate damage")
	_expect(first.moves["fireball"]["charges"] == 1 and not first.active_projectile.is_empty(), "launch spends one charge and creates one projectile")
	exchange.resolve_attempts(first, second, {"kind": "move", "id": "fireball"}, {})
	_expect(first.moves["fireball"]["charges"] == 1, "one-active-Fireball limit rejects another launch without charge loss")
	var projectile_x: int = first.active_projectile["x"]
	exchange.advance_projectiles(first, second)
	_expect(first.active_projectile["x"] == projectile_x + int(catalog.moves["fireball"]["projectile_speed"]), "Fireball advances an integer distance each tick")
	first.reset_round()
	_expect(first.active_projectile.is_empty() and first.moves["fireball"]["charges"] == 2, "round reset clears projectile and restores its charges")

	first = CombatantStateScript.new("first", [{"id": "fireball", "charges": 1, "damage": 100, "effect": "poison", "flourish": false}], 0, -40)
	second = CombatantStateScript.new("second", [], 0, 40)
	exchange.resolve_attempts(first, second, {"kind": "move", "id": "fireball"}, {})
	var impact: Dictionary = exchange.advance_projectiles(first, second)
	_expect(impact["first_hit"]["damage"] == 100 and first.active_projectile.is_empty(), "Fireball damages a fighter only on contact")
	_expect(second.active_effects.has("poison"), "projectile contact applies its attached effect")

	first = CombatantStateScript.new("first", fireball, 0, -40)
	second = CombatantStateScript.new("second", [], 100, 40)
	_expect(second.activate_shield(), "projectile target activates its shield")
	exchange.resolve_attempts(first, second, {"kind": "move", "id": "fireball"}, {})
	impact = exchange.advance_projectiles(first, second)
	_expect(impact["first_hit"]["damage"] == 0 and not second.shield.active, "active shield parries a Fireball on contact")
	_expect(second.hp == GameConfig.MAX_HP, "parried Fireball deals no damage")

	first = CombatantStateScript.new("first", fireball, 0, -40)
	second = CombatantStateScript.new("second", [], 0, 40)
	_expect(second.set_ducking(true), "projectile target ducks")
	exchange.resolve_attempts(first, second, {"kind": "move", "id": "fireball"}, {})
	for ignored in 40:
		exchange.advance_projectiles(first, second)
	_expect(second.hp == GameConfig.MAX_HP and first.active_projectile.is_empty(), "high Fireball passes over ducking target and expires")

	first = CombatantStateScript.new("first", fireball, 0, -250)
	second = CombatantStateScript.new("second", fireball, 0, 250)
	exchange.resolve_attempts(first, second, {"kind": "move", "id": "fireball"}, {"kind": "move", "id": "fireball"})
	var cancelled := false
	for ignored in 10:
		var step: Dictionary = exchange.advance_projectiles(first, second)
		if step["projectiles_cancelled"]:
			cancelled = true
			break
	_expect(cancelled and first.active_projectile.is_empty() and second.active_projectile.is_empty(), "opposing Fireballs cancel when their paths meet")
	_expect(first.hp == GameConfig.MAX_HP and second.hp == GameConfig.MAX_HP, "projectile cancellation damages neither fighter")


func _test_movement() -> void:
	var movement := MovementRulesScript.new()
	var first := CombatantStateScript.new("first", [], 0, -100)
	var second := CombatantStateScript.new("second", [], 0, 100)
	movement.advance(first, second, {"horizontal": 1}, {"horizontal": -1})
	_expect(first.x == -95 and second.x == 95, "fighters walk at fixed integer speed on the same tick")
	movement.advance(first, second, {"horizontal": 1, "duck": true}, {})
	_expect(first.ducking and first.x == -95, "ducking lowers the hurtbox and prevents walking")
	movement.advance(first, second, {"horizontal": 1}, {})
	_expect(not first.ducking and first.x == -90, "releasing duck restores walking")
	movement.advance(first, second, {"jump": true}, {})
	_expect(first.y == GameConfig.JUMP_SPEED and first.jumps_used == 1, "jump rises on the input tick")
	for ignored in 5:
		movement.advance(first, second, {}, {})
	var before_double: int = first.y
	movement.advance(first, second, {"jump": true}, {})
	_expect(first.y > before_double and first.jumps_used == 2, "one airborne double jump restarts upward speed")
	var before_third_speed: int = first.vertical_speed
	movement.advance(first, second, {"jump": true}, {})
	_expect(first.jumps_used == 2 and first.vertical_speed == before_third_speed - GameConfig.GRAVITY_PER_TICK, "a third jump is ignored")
	for ignored in 50:
		movement.advance(first, second, {}, {})
	_expect(first.y == 0 and first.jumps_used == 0, "landing resets the jump count")
	var sweep := [{"id": "low_sweep", "charges": 1, "damage": 50, "effect": "", "flourish": false, "air_allowed": false}]
	first = CombatantStateScript.new("first", sweep, 0, -100)
	second = CombatantStateScript.new("second", [], 0, 100)
	movement.advance(first, second, {"jump": true}, {})
	_expect(not first.begin_move("low_sweep") and not first.set_ducking(true), "ground-only moves and ducking are blocked during a normal jump")
	first = CombatantStateScript.new("first", sweep, 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	movement.advance(second, first, {"jump": true}, {})
	for ignored in 5:
		movement.advance(second, first, {}, {})
	var exchange := CombatExchangeScript.new(catalog)
	var whiff: Dictionary = exchange.resolve_attempts(first, second, {"kind": "move", "id": "low_sweep"}, {})
	_expect(whiff["first_hit"].is_empty() and second.y > int(catalog.moves["low_sweep"]["hitbox_max_y"]), "jump height physically avoids a low sweep")
	first = CombatantStateScript.new("first", [], 0, -100)
	second = CombatantStateScript.new("second", [], 0, 100)
	movement.advance(first, second, {"horizontal": 1, "dash": true}, {})
	_expect(first.x == -100 + GameConfig.DASH_SPEED and first.dash_ticks_left == GameConfig.DASH_TICKS - 1, "dash starts its short fixed-speed burst")
	movement.advance(first, second, {"horizontal": -1}, {})
	_expect(first.x == -100 + 2 * GameConfig.DASH_SPEED, "dash keeps its chosen direction until the burst ends")
	first.control_ticks_left = 3
	movement.advance(first, second, {"horizontal": 1, "dash": true}, {})
	_expect(first.x == -100 + 2 * GameConfig.DASH_SPEED and first.dash_ticks_left == 0, "control effects stop movement and active dashes")
	first = CombatantStateScript.new("first", [], 0, -GameConfig.ARENA_HALF_WIDTH)
	second = CombatantStateScript.new("second", [], 0, GameConfig.ARENA_HALF_WIDTH)
	movement.advance(first, second, {"horizontal": -1}, {"horizontal": 1})
	_expect(first.x == -GameConfig.ARENA_HALF_WIDTH and second.x == GameConfig.ARENA_HALF_WIDTH, "walk inputs cannot cross arena walls")
	first.x = -GameConfig.MIN_FIGHTER_SPACING / 2
	second.x = GameConfig.MIN_FIGHTER_SPACING / 2
	movement.advance(first, second, {"horizontal": 1}, {"horizontal": -1})
	_expect(second.x - first.x == GameConfig.MIN_FIGHTER_SPACING and first.x < second.x, "opposing walks keep the minimum fighter spacing")
	first.y = GameConfig.LAUNCH_HURTBOX_BOTTOM_Y
	first.airborne_ticks_left = GameConfig.UPPERCUT_AIRBORNE_TICKS
	first.jumps_used = 1
	movement.advance(first, second, {"jump": true}, {})
	_expect(first.jumps_used == 2 and first.y > GameConfig.LAUNCH_HURTBOX_BOTTOM_Y, "launched fighter retains its double jump")
	first.reset_round()
	_expect(first.vertical_speed == 0 and first.jumps_used == 0 and first.dash_ticks_left == 0, "round reset clears movement state")


func _test_match_ticks_and_buffer() -> void:
	var first := CombatantStateScript.new("first", [], 0, -60)
	var second := CombatantStateScript.new("second", [], 100, 0)
	var match_state := MatchSimulationScript.new(first, second, catalog)
	var step: Dictionary = match_state.advance({"action": {"kind": "basic"}}, {"action": {"kind": "shield"}})
	_expect(step["tick"] == 1 and step["second_shield"], "match tick opens a shield before simultaneous attacks")
	_expect(step["attacks"]["first_hit"]["damage"] == 0 and second.hp == GameConfig.MAX_HP, "same-tick parry blocks a basic hit")
	_expect(not second.shield.active and second.shield.cooldown_ticks_left == GameConfig.SHIELD_COOLDOWN_TICKS - 1, "match tick advances shield timers after contact")
	var fireball := [{"id": "fireball", "charges": 1, "damage": 100, "effect": "", "flourish": false}]
	first = CombatantStateScript.new("first", fireball, 0, -40)
	second = CombatantStateScript.new("second", [], 0, 40)
	match_state = MatchSimulationScript.new(first, second, catalog)
	step = match_state.advance({"action": {"kind": "move", "id": "fireball"}}, {})
	_expect(step["attacks"]["first_hit"].is_empty() and step["projectiles"]["first_hit"]["damage"] == 100, "match tick launches then advances a nearby Fireball")
	_expect(first.active_projectile.is_empty() and second.hp == GameConfig.MAX_HP - 100, "same-tick projectile contact is committed once")

	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	match_state = MatchSimulationScript.new(first, second, catalog)
	first.control_ticks_left = 2
	step = match_state.advance({"action": {"kind": "basic"}}, {})
	_expect(step["attacks"]["first_hit"].is_empty() and match_state.remaining[0] == 5, "early basic press waits in the six-tick buffer")
	match_state.advance()
	step = match_state.advance()
	_expect(step["attacks"]["first_hit"]["damage"] == GameConfig.BASIC_ATTACK_DAMAGE and match_state.pending[0].is_empty(), "buffered attack fires when control ends")
	_expect(second.hp == GameConfig.MAX_HP - GameConfig.BASIC_ATTACK_DAMAGE, "buffered hit commits exactly once")
	match_state.advance()
	_expect(second.hp == GameConfig.MAX_HP - GameConfig.BASIC_ATTACK_DAMAGE, "consumed buffer does not repeat the attack")

	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	match_state = MatchSimulationScript.new(first, second, catalog)
	first.control_ticks_left = 7
	match_state.advance({"action": {"kind": "basic"}}, {})
	for ignored in 5:
		match_state.advance()
	_expect(match_state.pending[0].is_empty() and match_state.remaining[0] == 0, "unavailable input expires after exactly six ticks")
	match_state.advance()
	match_state.advance()
	_expect(second.hp == GameConfig.MAX_HP, "expired input does not fire after control ends")

	var jab := [{"id": "jab", "charges": 1, "damage": 100, "effect": "", "flourish": false}]
	first = CombatantStateScript.new("first", jab, 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	match_state = MatchSimulationScript.new(first, second, catalog)
	first.control_ticks_left = 2
	match_state.advance({"action": {"kind": "basic"}}, {})
	match_state.advance({"action": {"kind": "move", "id": "jab"}}, {})
	step = match_state.advance()
	_expect(step["attacks"]["first_hit"]["damage"] == 100 and first.moves["jab"]["charges"] == 0, "new button press replaces an older buffered press")

	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	match_state = MatchSimulationScript.new(first, second, catalog)
	match_state.advance({"horizontal": 1, "action": {"kind": "basic"}}, {})
	var expected: Dictionary = match_state.snapshot()
	var replay := MatchSimulationScript.new(CombatantStateScript.new("first", [], 0, -60), CombatantStateScript.new("second", [], 0, 0), catalog)
	replay.advance({"horizontal": 1, "action": {"kind": "basic"}}, {})
	_expect(replay.snapshot() == expected, "same tick inputs produce identical match snapshots")
	match_state.reset_round()
	_expect(match_state.tick_index == 0 and match_state.pending[0].is_empty() and match_state.first.hp == GameConfig.MAX_HP, "round reset clears tick count, buffer, and fighter state")


func _test_hit_stop() -> void:
	var first := CombatantStateScript.new("first", [], 0, -60)
	var second := CombatantStateScript.new("second", [], 0, 0)
	var match_state := MatchSimulationScript.new(first, second, catalog)
	var step: Dictionary = match_state.advance({"action": {"kind": "basic"}}, {"action": {"kind": "basic"}})
	_expect(step["attacks"]["first_hit"]["damage"] == 20 and step["attacks"]["second_hit"]["damage"] == 20, "simultaneous hits still trade before hit-stop")
	_expect(step["hit_stop_ticks_left"] == GameConfig.HIT_STOP_BASE_TICKS, "a basic contact freezes both fighters for the base duration")
	var before_freeze: Dictionary = first.snapshot()
	step = match_state.advance({"horizontal": 1, "action": {"kind": "basic"}}, {"horizontal": -1})
	_expect(step["hit_stop"] and first.snapshot() == before_freeze and second.x == 0, "hit-stop freezes movement and combat state symmetrically")
	_expect(match_state.remaining[0] == GameConfig.INPUT_BUFFER_TICKS, "button presses during hit-stop are buffered without aging")
	match_state.advance()
	_expect(match_state.hit_stop_ticks_left == 0 and match_state.remaining[0] == GameConfig.INPUT_BUFFER_TICKS, "hit-stop lasts exactly its scheduled ticks")
	step = match_state.advance()
	_expect(not step["hit_stop"] and step["attacks"]["first_hit"]["damage"] == 20, "buffered attack executes when hit-stop ends")

	var heavy := [{"id": "heavy_smash", "charges": 1, "damage": 500, "effect": "", "flourish": false}]
	first = CombatantStateScript.new("first", heavy, 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	match_state = MatchSimulationScript.new(first, second, catalog)
	step = match_state.advance({"action": {"kind": "move", "id": "heavy_smash"}}, {})
	_expect(step["hit_stop_ticks_left"] == GameConfig.HIT_STOP_MAX_TICKS, "large hits reach the capped hit-stop duration")
	var frozen_hp: int = second.hp
	second.apply_incoming_hit({"effect": {"id": "burn", "total_damage": 30, "duration_ticks": 180}})
	var effect_before: Dictionary = second.active_effects.duplicate(true)
	step = match_state.advance()
	_expect(step["second_timed_damage"] == 0 and second.hp == frozen_hp and second.active_effects == effect_before, "damage-over-time and its timer pause during hit-stop")
	match_state.reset_round()
	_expect(match_state.hit_stop_ticks_left == 0 and match_state.snapshot()["hit_stop_ticks_left"] == 0, "round reset clears hit-stop")

	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 100, 0)
	match_state = MatchSimulationScript.new(first, second, catalog)
	step = match_state.advance({"action": {"kind": "basic"}}, {"action": {"kind": "shield"}})
	_expect(step["attacks"]["first_hit"]["damage"] == 0 and step["hit_stop_ticks_left"] == GameConfig.HIT_STOP_BASE_TICKS, "a fully parried contact still causes base hit-stop")


func _test_match_session() -> void:
	_expect(GameConfig.ROUND_TICKS == 90 * GameConfig.TICKS_PER_SECOND, "round clock is ninety seconds at fixed tick rate")
	var jab := [{"id": "jab", "charges": 1, "damage": 100, "effect": "", "flourish": false}]
	var first := CombatantStateScript.new("first", jab, 0, -60)
	var second := CombatantStateScript.new("second", [], 0, 0)
	var session := MatchSessionScript.new(first, second, catalog)
	second.hp = 100
	var result: Dictionary = session.advance({"action": {"kind": "move", "id": "jab"}}, {})
	_expect(result["phase"] == "round_over" and session.first_rounds_won == 1, "KO awards a round but leaves an explicit result phase")
	_expect(session.round_ticks_left == GameConfig.ROUND_TICKS - 1, "round clock advances on a played tick")
	var frozen_result: Dictionary = session.snapshot()
	result = session.advance({"action": {"kind": "basic"}}, {})
	_expect(not result["accepted"] and session.snapshot() == frozen_result, "round-over phase ignores gameplay input until transition")
	_expect(session.start_next_round(), "next round can start after the result phase")
	_expect(second.hp == GameConfig.MAX_HP and first.moves["jab"]["charges"] == 1 and session.round_ticks_left == GameConfig.ROUND_TICKS, "new round restores HP, charges, and clock")
	first.hp = 20
	result = session.advance({}, {"action": {"kind": "basic"}})
	_expect(result["round_winner"] == "second" and session.second_rounds_won == 1, "second fighter can tie the match at one round each")
	_expect(session.start_next_round() and session.round_number == 3, "third round starts at one-one")
	second.hp = 100
	result = session.advance({"action": {"kind": "move", "id": "jab"}}, {})
	_expect(result["phase"] == "match_over" and result["match_winner"] == "first", "second round win ends a best-of-three match")
	_expect(not session.start_next_round() and not session.advance()["accepted"], "completed match cannot start or advance another round")

	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	session = MatchSessionScript.new(first, second, catalog)
	second.hp = 900
	session.round_ticks_left = 1
	result = session.advance()
	_expect(result["phase"] == "round_over" and result["round_winner"] == "first", "timeout awards the round to the fighter with more HP")
	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	session = MatchSessionScript.new(first, second, catalog)
	session.advance({"action": {"kind": "basic"}}, {})
	var clock_before_freeze: int = session.round_ticks_left
	result = session.advance()
	_expect(result["step"]["hit_stop"] and session.round_ticks_left == clock_before_freeze - 1, "round clock counts real ticks even during hit-stop")

	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 100, 0)
	session = MatchSessionScript.new(first, second, catalog)
	session.round_ticks_left = 1
	result = session.advance()
	_expect(result["phase"] == "sudden_death" and session.round_ticks_left == 0, "equal HP at timeout enters sudden death")
	result = session.advance({"action": {"kind": "basic"}}, {"action": {"kind": "shield"}})
	_expect(result["phase"] == "sudden_death" and result["step"]["attacks"]["first_hit"]["damage"] == 0, "a parried hit cannot win sudden death")
	for ignored in GameConfig.HIT_STOP_BASE_TICKS:
		session.advance()
	result = session.advance({"action": {"kind": "basic"}}, {})
	_expect(result["phase"] == "round_over" and result["round_winner"] == "first" and second.hp > 0, "first damaging hit wins sudden death without requiring KO")
	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	session = MatchSessionScript.new(first, second, catalog)
	session.round_ticks_left = 1
	session.advance()
	result = session.advance({"action": {"kind": "basic"}}, {"action": {"kind": "basic"}})
	_expect(result["round_winner"] == "draw" and session.first_rounds_won == 0 and session.second_rounds_won == 0, "simultaneous damaging sudden-death hits count as a draw")

	first = CombatantStateScript.new("first", [], 0, -60)
	second = CombatantStateScript.new("second", [], 0, 0)
	session = MatchSessionScript.new(first, second, catalog)
	first.hp = 20
	second.hp = 20
	result = session.advance({"action": {"kind": "basic"}}, {"action": {"kind": "basic"}})
	_expect(result["round_winner"] == "draw" and session.first_rounds_won == 0 and session.second_rounds_won == 0, "simultaneous KO replays the round without a win")
	_expect(session.start_next_round() and first.hp == GameConfig.MAX_HP and second.hp == GameConfig.MAX_HP, "drawn round resets both fighters")


func _test_snapshot_restore() -> void:
	var jab := [{"id": "jab", "charges": 2, "damage": 100, "effect": "", "flourish": false}]
	var first := CombatantStateScript.new("first", jab, 0, -60)
	var second := CombatantStateScript.new("second", [], 100, 0)
	var original := MatchSessionScript.new(first, second, catalog)
	original.advance({"action": {"kind": "move", "id": "jab"}}, {"action": {"kind": "shield"}})
	original.advance({"action": {"kind": "basic"}}, {})
	var saved: Dictionary = original.snapshot()
	var restored := MatchSessionScript.new(CombatantStateScript.new("first", jab, 0, -60), CombatantStateScript.new("second", [], 100, 0), catalog)
	restored.restore_snapshot(saved)
	_expect(restored.snapshot() == saved, "LAN snapshot restores match, fighter, shield, hit-stop, and buffered input state")
	restored.simulation.first.moves["jab"]["charges"] = 0
	restored.simulation.pending[0]["kind"] = "shield"
	_expect(original.snapshot() == saved, "restored move and buffered input dictionaries do not alias the source snapshot")
	restored.restore_snapshot(saved)
	for ignored in 12:
		original.advance({"horizontal": 1}, {"horizontal": -1})
		restored.advance({"horizontal": 1}, {"horizontal": -1})
	_expect(restored.snapshot() == original.snapshot(), "restored match continues deterministically under the same inputs")

	var ended := MatchSessionScript.new(CombatantStateScript.new("first", jab, 0, -60), CombatantStateScript.new("second", [], 0, 0), catalog)
	ended.simulation.second.hp = 100
	ended.advance({"action": {"kind": "move", "id": "jab"}}, {})
	restored.restore_snapshot(ended.snapshot())
	_expect(restored.snapshot() == ended.snapshot() and restored.phase == "round_over", "LAN snapshot preserves a completed round and its score")
	_expect(restored.start_next_round() and ended.start_next_round() and restored.snapshot() == ended.snapshot(), "restored round transitions match the host")


func _test_touch_controls() -> void:
	var controls := TouchControlsScript.new()
	var safe := Rect2(50, 30, 1180, 660)
	controls.configure(Vector2(1280, 720), safe)
	for slot_name: String in controls.slots:
		var slot: Dictionary = controls.slots[slot_name]
		var center: Vector2 = slot["center"]
		var radius: float = slot["radius"]
		_expect(center.x - radius >= safe.position.x and center.x + radius <= safe.end.x and center.y - radius >= safe.position.y and center.y + radius <= safe.end.y, "%s touch target stays inside safe area" % slot_name)
	var pad: Vector2 = controls.slots["pad"]["center"]
	var radius: float = controls.slots["pad"]["radius"]
	controls.press_at(1, pad + Vector2(-radius * 0.6, 0), 1000)
	controls.press_at(2, controls.slots["basic"]["center"])
	var pressed: Dictionary = controls.consume_presses()
	_expect(controls.horizontal() == -1 and pressed["action"]["kind"] == "basic", "one finger moves while another presses basic attack")
	_expect(controls.consume_presses()["action"].is_empty() and controls.horizontal() == -1, "button press is one-shot while movement remains held")
	controls.drag_to(1, pad + Vector2(radius * 0.6, 0), 1300)
	_expect(controls.horizontal() == 1, "dragging across the pad changes held direction")
	_expect(not controls.consume_presses()["dash"], "slow direction changes do not dash")
	controls.release(1)
	controls.release(2)
	_expect(controls.horizontal() == 0, "lifting movement finger stops walking")
	controls.press_at(3, controls.slots["move_2"]["center"])
	controls.press_at(4, pad + Vector2(0, radius * 0.6), 2000)
	pressed = controls.consume_presses()
	_expect(pressed["action"]["kind"] == "move_slot" and pressed["action"]["slot"] == 2 and controls.ducking(), "move buttons and duck can use separate fingers")
	controls.release(3)
	controls.release(4)
	controls.press_at(5, pad + Vector2(0, -radius * 0.6), 3000)
	pressed = controls.consume_presses()
	_expect(pressed["jump"] and not pressed["dash"], "pushing the joystick up jumps without dashing")
	controls.drag_to(5, pad, 3050)
	controls.drag_to(5, pad + Vector2(0, -radius * 0.6), 3100)
	_expect(controls.consume_presses()["jump"], "a second upward push queues double jump")
	controls.release(5)
	controls.press_at(6, pad, 4000)
	controls.drag_to(6, pad + Vector2(-radius * 0.85, 0), 4100)
	pressed = controls.consume_presses()
	_expect(pressed["dash"] and pressed["dash_direction"] == -1, "quick left flick queues a left dash")
	controls.drag_to(6, pad + Vector2(radius * 0.85, 0), 4150)
	_expect(not controls.consume_presses()["dash"], "one touch cannot queue multiple dashes")
	controls.release(6)
	controls.press_at(10, pad, 5000)
	controls.drag_to(10, pad + Vector2(radius * 0.85, radius * 0.7), 5070)
	_expect(not controls.consume_presses()["dash"] and controls.ducking(), "a diagonal downward push ducks without dashing")
	controls.release(10)
	controls.press_at(11, pad, 6000)
	controls.drag_to(11, pad + Vector2(radius * 0.85, 0), 6250)
	_expect(not controls.consume_presses()["dash"], "a late horizontal drag does not dash")
	controls.release(11)
	controls.press_at(12, pad, 7000)
	controls.drag_to(12, pad + Vector2(radius * 0.85, 0), 7060)
	controls.release(12)
	pressed = controls.consume_presses()
	_expect(pressed["dash"] and pressed["dash_direction"] == 1 and controls.horizontal() == 0, "a released right flick retains dash direction until consumed")
	controls.clear_all()
	controls.set_continue_mode("NEXT")
	controls.press_at(7, controls.slots["basic"]["center"])
	_expect(controls.consume_presses()["action"].is_empty(), "combat buttons are inactive on a round result")
	controls.press_at(8, controls.slots["continue"]["center"])
	_expect(controls.consume_presses()["continue"], "result screen has a touch next-round button")
	controls.set_continue_mode("")
	controls.clear_all()
	var screen_touch := InputEventScreenTouch.new()
	screen_touch.index = 9
	screen_touch.position = controls.slots["shield"]["center"]
	screen_touch.pressed = true
	controls._input(screen_touch)
	_expect(controls.consume_presses()["action"]["kind"] == "shield", "Godot screen-touch events reach the shield control")
	screen_touch.pressed = false
	controls._input(screen_touch)
	_expect(controls.fingers.is_empty(), "screen-touch release clears the held finger")
	var charges: Array[int] = [2, 0, -1, 1]
	var shield := ShieldRuntime.new(120)
	controls.set_combat_status(charges, shield)
	_expect(controls.labels["move_0"].text == "1\n×2" and controls.labels["move_1"].text == "2\n×0" and controls.labels["move_2"].text == "3\n∞", "move buttons show finite, empty, and Flourish charges")
	_expect(controls.labels["shield"].text == "SHIELD" and controls.shield_ready, "ready shield is shown as available")
	shield.activate()
	controls.set_combat_status(charges, shield)
	_expect(controls.labels["shield"].text == "SHIELD\nACTIVE" and not controls.shield_ready, "active shield has a distinct status")
	shield.whiff()
	controls.set_combat_status(charges, shield)
	_expect(controls.labels["shield"].text.begins_with("SHIELD\n3s") and not controls.shield_ready, "shield cooldown is displayed after a whiff")
	for ignored in ShieldRuntime.COOLDOWN_TICKS:
		shield.tick()
	controls.set_combat_status(charges, shield)
	_expect(controls.labels["shield"].text == "SHIELD\n2 HIT", "shield shows required contacts after cooldown")
	controls.set_training_mode(true)
	controls.set_build_index(3, 5)
	_expect(controls.labels["training"].text == "DUMMY" and controls.labels["build"].text == "BUILD\n3/5", "training and build selections appear on their buttons")
	controls.press_at(13, controls.slots["training"]["center"])
	controls.press_at(14, controls.slots["build"]["center"])
	pressed = controls.consume_presses()
	_expect(pressed["training_toggle"] and pressed["cycle_build"], "training and build buttons each emit a one-shot press")
	controls.release(13)
	controls.release(14)
	controls.set_lan_locked(true)
	controls.press_at(15, controls.slots["training"]["center"])
	controls.press_at(16, controls.slots["build"]["center"])
	pressed = controls.consume_presses()
	_expect(not pressed["training_toggle"] and not pressed["cycle_build"] and not controls.labels["training"].visible and not controls.labels["build"].visible, "LAN lock hides and disables local setup buttons")
	controls.release(15)
	controls.release(16)
	controls.set_lan_locked(false)
	_expect(controls.labels["training"].visible and controls.labels["build"].visible, "leaving LAN restores local setup buttons")
	controls.free()


func _test_android_export_config() -> void:
	var preset := ConfigFile.new()
	_expect(preset.load("res://export_presets.cfg") == OK, "Android export preset can be parsed")
	_expect(preset.get_value("preset.0", "platform", "") == "Android" and preset.get_value("preset.0", "runnable", false), "Android debug preset is available for one-click deploy")
	_expect(preset.get_value("preset.0", "include_filter", "").contains("*.json"), "Android export includes runtime JSON catalogs and builds")
	_expect(preset.get_value("preset.0.options", "architectures/arm64-v8a", false) and not preset.get_value("preset.0.options", "architectures/x86", true), "debug APK targets arm64 phones")
	_expect(preset.get_value("preset.0.options", "permissions/internet", false), "Android APK requests INTERNET permission for LAN play")
	_expect(preset.get_value("preset.0.options", "keystore/release", "missing") == "" and preset.get_value("preset.0.options", "keystore/release_password", "missing") == "", "release signing secrets are absent from tracked preset")
	_expect(ProjectSettings.get_setting("display/window/handheld/orientation") == 0 and ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "mobile display stays landscape and fills wide screens")


func _test_example_builds_and_simulation() -> void:
	var file := FileAccess.open("res://data/example_builds.json", FileAccess.READ)
	var builds: Dictionary = JSON.parse_string(file.get_as_text())
	for build_name: String in builds:
		var result := validator.validate(builds[build_name])
		_expect(result["valid"], "example build '%s' is valid: %s" % [build_name, result["errors"]])
		_expect(result["total_cost"] == 500, "example build '%s' recomputes to 500" % build_name)
	var duel := DuelSimulator.new(catalog).simulate(builds["balanced"], builds["glass_cannon"])
	_expect(duel["valid"] and duel["turns"] > 0 and not duel["log"].is_empty(), "example builds can be deterministically simulated")
	duel = DuelSimulator.new(catalog).simulate(builds["poisoner"], builds["turtle"], 4)
	var dealt_timed_damage := false
	for entry: Dictionary in duel["log"]:
		if int(entry["timed_damage"]) > 0:
			dealt_timed_damage = true
	_expect(dealt_timed_damage, "the Poisoner example applies damage over time in simulation")
	duel = DuelSimulator.new(catalog).simulate(builds["pure_nuke"], builds["turtle"], 20)
	var used_basic := false
	for entry: Dictionary in duel["log"]:
		if entry["move"] == "basic" and entry["damage"] == GameConfig.BASIC_ATTACK_DAMAGE:
			used_basic = true
	_expect(used_basic, "simulation continues with basic attacks after charged moves are spent")


func _has_error(result: Dictionary, fragment: String) -> bool:
	for error: String in result["errors"]:
		if fragment in error:
			return true
	return false
