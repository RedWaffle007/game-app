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
- Stagger pushback and full combatant reset between rounds
- playable Flourish actions with no combat utility or charge use
- catalog ranges and vertical hitboxes for checked attack attempts
- deterministic Fireball travel, parries, ducking, and projectile cancellation
- fixed-tick walk, jump/double jump, dash, and duck movement with arena spacing
- a single match tick with a six-tick button buffer and deterministic action order
- shared, damage-scaled hit-stop that pauses gameplay timers but retains button presses
- combo scaling after Stagger or Uppercut, with a three-hit airborne limit
- timed-effect replacement and deterministic damage-over-time ticks
- a deterministic build-vs-build smoke simulator that advances timed effects
- a dependency-free headless GDScript test suite

Arena distances are integer simulation units. The current arena bounds and
close/long range targets are tuning defaults in `GameConfig`. The smoke
simulator supplies landed attacks; `CombatExchange.resolve_attempts()` checks
range and hurtboxes for gameplay calls. `MovementRules.advance()` accepts both
fighters' integer directions and jump/dash/duck presses once per tick; a touch
control layer is still pending. `MatchSimulation.advance()` combines movement,
buffered button actions, checked hits, projectiles, and effect timers. Inputs
may include an `action` with kind `basic`, `move` (plus `id`), or `shield`;
new presses replace older buffered presses.
Landed contacts schedule 2–6 shared hit-stop ticks; inputs pressed during the
freeze remain buffered until gameplay resumes.
Uppercut currently uses a 45-tick airborne timer as a balance placeholder.
The match tick advances projectiles after checked actions, so a Fireball can
contact a nearby fighter on its launch tick.

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
