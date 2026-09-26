extends SceneTree

const CombatantStateScript := preload("res://src/sim/combatant_state.gd")
const CombatExchangeScript := preload("res://src/sim/combat_exchange.gd")

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
