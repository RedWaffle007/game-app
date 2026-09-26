# System Plan: Budget Fighter (working title)

A 2.5D online 1v1 fighting game where every player builds their own fighter from a curated move catalog under the same fixed power budget. Damage, defense, special effects and move availability all compete for that one budget.

**Core principle:** freedom within a fixed economy. Any legal build may be weak, but no legal build may be unbeatable.

All numbers in this document are starting values for playtesting. The structure is the design; the numbers are dials.

---

## 1. Project context (for anyone implementing this, including Claude Code)

| Area | Decision |
|---|---|
| Engine | Godot 4.x (latest stable), GDScript |
| Art | Blender → glTF/GLB → Godot; stylized low/mid-poly 3D |
| View | 3D world, gameplay locked to one 2D plane (X/Y); side-on dynamic camera (follow, zoom, shake) |
| Platform | **Android first**, tested on real phones from day one; PC build kept for fast development iteration |
| Renderer | Decide in week 1 by testing on the weakest target phone: Mobile renderer (Vulkan) or Compatibility renderer (OpenGL ES 3, widest device support) |
| Orientation | Landscape only |
| Multiplayer | Two phones on the same Wi-Fi early (Phase 2), connecting to a LAN server on the dev PC; internet play later. Simulation must allow rollback netcode later |
| Backend | Deferred (Nakama + PostgreSQL later) |
| Version control | Git + GitHub |

### Implementation rules that must hold from day one

The combat simulation runs on a **fixed 60 ticks per second**, independent of frame rate. All durations are stored in ticks (0.5 s = 30 ticks). All gameplay math uses **integers only** (no floats in the simulation) so results are identical on every machine, which keeps rollback netcode possible later. Division always rounds down.

The simulation contains **no randomness**. Rendering, VFX, sound and camera read the simulation state but never write to it.

All moves, effects and prices live in **data files** (Godot Resources or JSON), never hard-coded. Game rules such as `MAX_MOVES = 4` and `BUDGET = 500` are constants in one config file, so special modes can change them without code changes.

Builds are data. A build is validated by recomputing every cost from the catalog; a build's stored totals are never trusted.

### Mobile-first requirements

The game must hold a steady 60 fps on the weakest phone in the test pool, including after 10 minutes of play (phones slow down when they heat up). Budgets are set early and checked every phase: low-poly models, few materials, capped particle counts, and no real-time shadows unless the frame rate allows them.

All UI is touch-first, sized for thumbs, and respects notches and rounded corners (safe areas). The build creator in particular must be comfortable to use on a small phone screen.

Touch input has no physical feedback and slightly more delay than a controller, so the simulation includes a **6-tick input buffer** (a press slightly early still counts), and the shield parry window should be tuned on phones, not on PC.

### Touch controls (baseline layout)

| Area | Control |
|---|---|
| Left thumb | Virtual joystick: left/right to move, push up to jump, quick flick to dash |
| Right thumb | Large basic-attack button; 4 move buttons in an arc around it, each showing remaining charges; separate shield button |

Buttons must show cooldowns and charges directly on the button. Controls are remappable and resizable later.

### Build and deploy workflow

Godot exports an APK and installs it on a phone connected by USB or wireless debugging (Godot's one-click deploy, or from the terminal with `godot --headless --export-debug "Android" builds/game.apk` followed by `adb install -r builds/game.apk`). The terminal route lets Claude Code build and install without the editor. Required once per machine: the Android SDK tools (adb), a JDK, and Godot's export templates matching the exact Godot version. Keep the release signing keystore backed up outside the repo; losing it means you can never update the Play Store app.

The Android emulator is not used: it is heavy on 8 GB RAM and not representative of real touch feel.

---

## 2. Fixed for every character

| Property | Value |
|---|---|
| Max HP | 1,000 |
| Movement | Identical for everyone: walk, jump, double jump, dash, duck (section 2a) |
| Hurtbox | Identical for everyone; appearance and size sliders are visual only |
| Basic attack | 20 damage, unlimited, no effect, not customizable. While ducking it becomes a low poke (same damage) |
| Shield | Universal action; only its strength (PP) varies |

### 2a. Basic movement

| Action | Rule |
|---|---|
| Walk | Left/right at a fixed speed. No movement while ducking |
| Jump | Fixed height |
| Double jump | One extra jump in the air; resets on landing |
| Dash | Short burst of speed; no invincibility |
| Duck | Ground only. Lowers the hurtbox so high attacks pass over. Cannot walk while ducking; can shield and basic-attack |

Touch mapping: joystick up = jump (up again in the air = double jump), joystick down = duck, quick flick = dash.

Attack height is physical, not a special rule: each move's hitbox sits at a fixed height. Ducking lowers your hurtbox under high attacks; jumping lifts you over low attacks. The catalog lists each move's height (section 4) so every option has a counter.

### 2b. Getting hit (no default hitstun)

A normal hit deals damage and **never stops the defender**. They keep moving, and a move in wind-up continues. This prevents "whoever lands first wins": trading hits is normal, and avoiding damage comes from movement, ducking, jumping and the shield parry.

For impact feel, every hit triggers a short **hit-stop** (both players freeze for the same few ticks, scaled by damage). Because both freeze equally, it gives no advantage.

Only two things interrupt a player, and both are effects: **Stagger** (hitstun) and **Shock** (wind-up reset). Knockback and Pull move a player but do not cancel what they are doing.

---

## 3. The budget

Every build has **500 PP** to split across its 4 chosen moves and its shield. There are no minimums and no maximums per slot, apart from the per-move rules in section 4.

> **Naming flag:** "PP" means *uses* in Pokémon. Consider renaming (e.g. "Power Budget" / "Forge Points"). This document keeps "PP" for now.

---

## 4. The move catalog

Players pick **4 different moves** from a curated catalog. Each move has **one hand-made animation** and fixed speed, range, height and hitbox. Players choose power (PP into damage) and cosmetics (e.g. VFX colour) per move, and may attach an effect to **at most 2 of the 4 moves** (section 7).

**Move cost = base cost + power + effect cost**

**Damage per hit = power × the move's damage rate** (rounded down, capped at 500).

### Starting catalog (MVP: 8–10 moves)

| Move | Base cost | Damage rate | Height | Air? | Character |
|---|---:|---:|---|---|---|
| Jab | 0 | 0.8× | High | Yes | Very fast, short range |
| Straight Punch | 0 | 1.0× | High | Yes | The standard move |
| Front Kick | 10 | 1.0× | Mid | Yes | Slightly longer range, slower |
| Low Sweep | 10 | 0.9× | Low | No | Hits ducking players; can be jumped over |
| Sword Slash | 15 | 1.0× | Mid | Yes | Wide arc |
| Uppercut | 30 | 0.9× | Mid | Yes | Launches the opponent upward (they can still act) |
| Heavy Smash | 0 | 1.3× | Mid (overhead) | No | Slow, obvious wind-up, punishable on whiff; hits ducking players |
| Dash Strike | 40 | 0.9× | Mid | Yes | Moves you forward as it hits |
| Fireball | 40 | 0.8× | High | Yes | Projectile; one on screen at a time; can be ducked |
| Spinning Slash | 50 | 0.8× | Mid | Yes | Hits all around you |

Implementation note: store damage rates as integers out of 100 (0.8× = 80).

### Move rules

| Rule | Purpose |
|---|---|
| Each move may be picked only once per build | With one animation per move, duplicates at different power would be undetectable decoys |
| A move that can hit needs at least 25 power | Stops near-free pokes that exist only to interrupt or pressure |
| Damage per hit is capped at 500 (50% HP); the builder warns when extra power is wasted | Prevents one-hit kills |
| A move set to 0 power becomes a **Flourish**: total cost 0 (base cost waived), no hitbox, no movement, no effect, restrained VFX | Keeps the "free flashy move" idea without free utility |

### Readability without animation tiers

Each move has one animation. Its strength is communicated by code-driven layers that scale with move cost: particle count, glow and trail size, shader brightness, impact sound weight, hit-stop length and camera shake. Opponents identify the move by its unique animation and already know its power from the pre-match reveal (section 9).

---

## 5. Charges

**Charges = 600 ÷ move cost**, rounded down, minimum 1, maximum 8.

| Move cost | Charges | Lifetime damage (approx.) |
|---:|---:|---:|
| 75 | 8 | 600 |
| 150 | 4 | 600 |
| 300 | 2 | 600 |
| 500 | 1 | 500 |

Effect cost counts toward move cost, so effects reduce charges. Charges reset every round. Flourishes, the basic attack and the shield do not use charges.

Because charges are whole numbers, some costs are slightly more efficient than others. This is accepted as normal build optimization; the formula keeps the gap small.

---

## 6. Shield

| Rule | Value |
|---|---|
| Strength | Equal to the PP allocated (0–500). At 0 the action is disabled |
| Where | Usable standing, ducking and in the air |
| Type | Timed parry with a short fixed active window; absorbs one hit |
| Whiff | Fixed, punishable recovery |
| Cooldown | At least 3 s **and** 2 contact actions (hits or blocked hits). Basic attacks count; Flourishes and whiffs do not |
| Visibility | Shown in the pre-match reveal |

---

## 7. Effects

The game has **10 effects in total** (a hard cap of 10). Each build may use **up to 2 effects**, on **2 different moves**, and the 2 effects must be **different**. A move carries at most one effect. Its cost is part of the move cost, so it reduces that move's charges.

| Effect | Cost | Full-strength behaviour |
|---|---:|---|
| Burn | 40 | 30 damage over 3 s |
| Poison | 60 | 40 damage over 8 s |
| Knockback | 40 | Pushes opponent to long range; max one wall bounce; does not cancel their action |
| Pull | 40 | Drags opponent to close range; does not cancel their action |
| Guard Break | 70 | Defender's shield counts as half its PP against this move |
| Weaken | 70 | Opponent's hits deal 20% less damage for 3 s |
| Lifesteal | 80 | Heal 30% of damage actually dealt, never above max HP |
| Stagger | 80 | Hitstun: opponent cannot act for 0.6 s and is pushed back slightly; a move in wind-up is **paused**, not cancelled |
| Charge Drain | 90 | Opponent loses 1 charge of the move they used most recently |
| Shock | 100 | 0.5 s freeze and **cancels** the opponent's current wind-up |

### Control effects (Stagger and Shock)

These are the only two effects that stop a player. Stagger delays; Shock resets. After being Staggered or Shocked for at least 0.2 s, a player is immune to **both** for 1.5 s, so one can't be chained into the other.

### Shock (modelled on Clash Royale's Electro Wizard)

The freeze is short; the real value is the reset. If the opponent is in a move's wind-up, that move is cancelled, its charge is refunded, and its wind-up must start again from the beginning. The shared control immunity above prevents stunlock. Shock is the intended counter to slow, heavy, glass-cannon moves.

### Timed effects (Burn, Poison, Weaken)

The newest application of the same effect always **replaces** the current one: a fresh timer at the new application's strength. A fully blocked hit applies at 0%, which replaces the effect with nothing (a full cleanse). Active effects and their remaining time are shown on the health bar so re-applying is always an informed gamble.

Example, Poison at 40 over 8 s (5 per second), re-applied after 4 s:

| Second hit | Result | Poison left |
|---|---|---:|
| None | Old poison finishes | 20 over 4 s |
| Clean (100%) | Fresh full poison | 40 over 8 s |
| 11.8% penetrates | Weak poison replaces strong | 4 over 8 s |
| Fully blocked (0%) | Cleansed | 0 |

Effects never trigger from basic attacks or Flourishes. The same effect never stacks with itself.

---

## 8. Hit resolution order

The server (or local simulation) always resolves a landed hit in this order.

| Step | Action |
|---:|---|
| 1 | Apply combo scaling: each hit in an unbroken combo (possible only after Stagger or Uppercut) does 10% less, to a floor of 50%. Apply the attacker's Weaken reduction, if any |
| 2 | If the attack has Guard Break, halve the defender's active shield value |
| 3 | Damage through = attack damage − shield (minimum 0); shield counts only if the parry is active |
| 4 | Penetration % = damage through ÷ attack damage before the shield (100% if no shield) |
| 5 | Deal the damage through |
| 6 | Apply the effect at the penetration %: Burn/Poison scale total damage and keep duration; Knockback and Pull scale distance; Weaken scales its % reduction; Stagger scales duration; Shock's freeze scales and its reset needs ≥ 50%; Charge Drain needs ≥ 50%; Lifesteal is 30% of damage through and is not scaled again |
| 7 | Round every result down |

---

## 9. Match rules

| Rule | Value |
|---|---|
| Format | Best of 3 rounds, 90 s each |
| Reset | Charges and cooldowns reset each round |
| Pre-match reveal | Both players see the full opposing build: 4 moves, power, effects, charges, shield strength |
| In-fight info | Remaining charges and active effects are visible |
| Timeout | Higher HP % wins the round; if exactly tied, sudden death: first damaging hit wins, shields still work |
| Build lock | Builds lock before matchmaking; no swapping after the reveal |

---

## 10. Server and data rules

The server recomputes every build cost from the catalog and rejects anything invalid. When a price changes, any build pushed over 500 PP is flagged and cannot enter matches until re-saved. In online play the server decides all hits, damage, effects, charges and cooldowns; clients only send inputs. Every match is logged (builds, moves used, hits, effects, result) so pick rates and win rates can guide price changes.

---

## 11. Flagged: decisions still missing

These are gaps the design does not answer yet. Recommended defaults are given so development is never blocked, but each needs a conscious decision and playtesting.

| # | Missing piece | Why it matters | Recommended default |
|---:|---|---|---|
| 1 | **Trading feel** | With no default hitstun, both players may just trade hits. Hit-stop, parry timing and movement must make avoiding damage feel better than mashing | Playtest early in Phase 1; tune parry window and move recovery first |
| 2 | **Stagger follow-ups** | Stagger is the only hitstun, so it defines combos | 0.6 s should allow exactly one fast follow-up; tune on phones |
| 3 | **Uppercut launch** | Launched players can double jump and act; check it isn't useless or too strong | Keep the launch, allow full air control; max 3 hits while airborne |
| 4 | **Stage edges** | Knockback means different things with or without ring-outs | Walled arenas, no ring-outs |
| 5 | **Projectile interactions** | Two Fireballs meeting, shielding projectiles | Projectiles cancel each other; the shield can parry projectiles |
| 6 | **Simultaneous hits** | Both players connecting on the same tick | Both hits resolve (a trade) |
| 7 | **Attack heights balance** | If too many good moves are High, ducking becomes dominant | Keep at least one strong Mid and one Low option in the catalog at all times |
| 8 | **Invincibility** | Jump, double jump, dash and duck are the evasion tools | No invincibility frames anywhere in the MVP |
| 9 | **Controls** | Touch is now the primary input | Baseline layout in section 1; playtest button size and placement on the smallest test phone in Phase 1 |
| 10 | **Round start** | Positions and spacing | Fixed mirrored start positions at mid range |
| 11 | **Target round length / time-to-kill** | Needed to tune HP and damage | Aim for 30–60 s rounds between equal players |
| 12 | **Disconnects** | Ranked integrity | Disconnect = round loss after a short reconnect window |
| 13 | **New-player onboarding** | A blank 500 PP budget is intimidating | Ship 6–8 preset builds players can copy and edit |
| 14 | **Cosmetic customization scope** | Character creator size | Body, head, hair, outfit, weapon skin, colours; hurtbox unaffected |
| 15 | **Name moderation** | Build and character names are user text | Basic filter + report system before any public sharing |
| 16 | **Netcode choice** | Rollback vs server-authoritative with delay | Keep the simulation deterministic now; decide when online work starts |
| 17 | **Monetization** | Affects what's cosmetic vs gameplay | Cosmetics only; never sell PP, moves' power or effects |
| 18 | **Catalog growth rules** | New moves can break balance | Every new move gets a base cost + damage rate reviewed against logged data before release |

---

## 12. Development roadmap

Each phase must be fun or correct before the next starts.

| Phase | Goal | Done when |
|---:|---|---|
| 0 | **Balance simulator** (pure logic, no graphics): build validation, costs, charges, hit resolution, effects, combo scaling | Unit tests cover every rule in sections 4–8; example builds can be simulated against each other |
| 1 | **Grey-box on phone**: capsule characters, one walled arena, touch controls, movement, basic attack, shield, 4 moves from preset builds; opponent is a training dummy plus a simple bot | Installs on a phone and holds 60 fps; controls feel good against the bot |
| 2 | **Two phones, same Wi-Fi**: LAN server on the dev PC (or one phone hosting), both phones play a full best-of-3 | No desyncs over a full match; balanced, glass-cannon and poison builds all win sometimes |
| 3 | **Build creator UI (touch)**: pick 4 moves, set power, pick effects, set shield, live cost and charge display | A new build can be made and saved on a phone in under 2 minutes |
| 4 | **Online 1v1 over the internet**: hosted server, phones on mobile data and different Wi-Fi networks | Playable at typical mobile latency without desyncs |
| 5 | **Art and feel**: Blender models, one animation per move, VFX scaling, hit-stop, camera | Moves are readable at a glance on a small screen, still at 60 fps |
| 6 | **Accounts, build sharing, matchmaking, logging** | Strangers can play ranked matches |

### Example builds for testing

| Build | Moves | Shield |
|---|---|---:|
| Balanced | Straight Punch 125 / Front Kick (10 + 115) / Sword Slash (15 + 110) / Jab 125 | 0 |
| Glass cannon | Heavy Smash 385 (500 dmg, 1 use) + Straight Punch 115 | 0 |
| Poisoner | Dash Strike (40 + 100 power + 60 Poison = 200) + Jab 100 | 200 |
| Pure nuke | Heavy Smash 385 + 3 Flourishes | 115 |
| Turtle | Jab 100 + Straight Punch 100 | 300 |

Every build above totals exactly 500 PP. Phase 0's validator should confirm this automatically.

---

## 13. Notes to remember

**Watch for hit-trading in playtesting.** Because normal hits don't cause hitstun (section 2b), players may simply trade hits back and forth instead of playing carefully. If that happens, the first things to tune are the shield parry window and each move's recovery time, so that dodging, ducking, jumping and parrying feel more rewarding than mashing. This is also flag #1 in section 11.
