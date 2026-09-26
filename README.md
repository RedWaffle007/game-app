# Budget Fighter

Godot 4 prototype for a deterministic, mobile-first 2.5D fighting game. The design source of truth is [`system_plan.md`](system_plan.md).

## Current milestone

Phase 0 has started with a pure-logic simulation foundation:

- JSON move, effect, and example-build catalogs
- exact 500 PP build validation with recomputed costs
- integer-only damage, charge, shield, combo, and effect resolution
- shield recharge gated by both 180 ticks and two contact actions
- one exchange path for basic attacks, shields, move effects, and simultaneous hits
- integer arena positions with walled Knockback and Pull resolution
- combo scaling after Stagger or Uppercut, with a three-hit airborne limit
- timed-effect replacement and deterministic damage-over-time ticks
- a deterministic build-vs-build smoke simulator that advances timed effects
- a dependency-free headless GDScript test suite

Arena distances are integer simulation units. The current arena bounds and
close/long range targets are tuning defaults in `GameConfig`. The smoke
simulator supplies landed attacks; move range, hurtboxes, and movement input
will be added with the grey-box gameplay phase.
Uppercut currently uses a 45-tick airborne timer as a balance placeholder.

Run the tests with Godot 4. The wrapper first performs a compile-only pass so
parser errors cannot be mistaken for a successful assertion run:

```sh
./tests/run_tests.sh
```

It automatically uses `godot`, `godot4`, or the standard Godot Flatpak. No
editor plugin is required.

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
