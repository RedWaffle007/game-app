# Budget Fighter

Godot 4 prototype for a deterministic, mobile-first 2.5D fighting game. The design source of truth is [`system_plan.md`](system_plan.md).

## Current milestone

Phase 0 has started with a pure-logic simulation foundation:

- JSON move, effect, and example-build catalogs
- exact 500 PP build validation with recomputed costs
- integer-only damage, charge, shield, combo, and effect resolution
- shield recharge gated by both 180 ticks and two contact actions
- timed-effect replacement and deterministic damage-over-time ticks
- a basic deterministic build-vs-build smoke simulator
- a dependency-free headless GDScript test suite

Run the tests with Godot 4:

```sh
godot --headless --path . --script res://tests/test_runner.gd
```

If the executable is named `godot4`, substitute that name. No editor plugin is required.

## Data shape

A build stores only player choices; computed totals are never trusted:

```json
{
  "shield": 200,
  "moves": [
    {"id": "dash_strike", "power": 100, "effect": "poison"},
    {"id": "jab", "power": 100},
    {"id": "front_kick", "power": 0},
    {"id": "sword_slash", "power": 0}
  ]
}
```

Power `0` means Flourish: zero cost, zero damage, zero charges, and no effect.
