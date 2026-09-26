extends SceneTree

const CombatantStateScript := preload("res://src/sim/combatant_state.gd")

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
	for ignored in 12:
		fighter.tick()
	_expect(fighter.control_ticks_left == 0 and fighter.control_immunity_ticks_left == 90, "control immunity lasts 1.5 seconds after control")
	var snapshot := fighter.snapshot()
	snapshot["moves"]["jab"]["charges"] = 0
	_expect(fighter.moves["jab"]["charges"] != 0, "rollback snapshot is a deep copy")


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


func _has_error(result: Dictionary, fragment: String) -> bool:
	for error: String in result["errors"]:
		if fragment in error:
			return true
	return false
