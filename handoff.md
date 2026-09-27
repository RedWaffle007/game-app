# Budget Fighter — next-session handoff

Updated 2026-09-27. The design source of truth is `system_plan.md`; `README.md` explains the current prototype and controls.

## Current state

- Godot 4.7.2 Flatpak project at `/home/smbilal/game-app` on branch `main`.
- Phase 0 deterministic combat simulation is implemented: build validation, costs/charges, effects, shields, physical hits, projectiles, movement, input buffering, hit-stop, and best-of-three round flow.
- Phase 1 has a local 3D capsule arena (`src/main.tscn`, `src/main.gd`) with five selectable player presets versus a deterministic Poisoner bot or a passive training dummy. Keyboard and safe-area-aware multi-touch controls are available (`src/ui/touch_controls.gd`), including joystick flick to dash. The user tested the earlier controls on a phone and reported they are all fine; the newly added buttons have not been tried there.
- An experimental Phase 2 LAN path is in source: the host phone validates the guest's preset build, reveals both builds for three seconds, runs the match, and sends state snapshots; the guest phone sends inputs and renders host state. A LAN menu accepts the host's local IP address. No LAN build or two-device run has been performed under the user's test deferral.
- The latest completed test run was `./tests/run_tests.sh`: **PASS: 268 checks**, plus the main-scene startup smoke check, before the recent UI and LAN changes. The user asked to run the new tests themselves. `tests/test_runner.gd` now has additional regression checks, and `tests/manual_phone.md` has a device checklist; neither has been run on current source.
- The previously built landscape, arm64 Android debug APK is at `builds/game-debug.apk` (ignored by Git). It is signed and includes the runtime JSON catalogs. It was installed on a connected phone on 2026-09-27; the user reported that the controls are all fine. Frame rate and heat have not been measured. This APK predates the new button status, visual feedback, FPS readout, effect timers, BOT/DUMMY toggle, BUILD selector, and experimental LAN path. The current source has not been built under the user's test deferral.

## Working tree

The Android export, joystick controls, LAN prototype, and regression coverage were committed as `01c4724 Add LAN prototype and regression coverage`. The working tree was clean immediately before this handoff edit. No implementation changes were made in the interrupted continuation. Recheck Git status at the start of the next session because the user may commit or push in between.

The export preset is debug-only, landscape, arm64, and includes `*.json` because the game loads catalog and preset-build JSON at runtime. It now enables Android's INTERNET permission for LAN play. APKs go to the ignored `builds/` directory; no release keystore or password belongs in Git.

## Android export status

The matching `4.7.2.stable` Android export templates are now installed in the Flatpak's template directory. The official archive was checked against its published SHA-512 hash. `./scripts/export_android_debug.sh` successfully builds `builds/game-debug.apk`; Android's `apksigner verify` passes. Android texture compression is enabled in `project.godot`, and a prototype app icon was added to clear the export error.

The machine has an Android SDK at `/home/smbilal/Android`. Godot's Flatpak can see it and has an OpenJDK 17 extension at `/usr/lib/sdk/openjdk17/jvm/openjdk-17`; the export script sets these paths for Flatpak runs. The host OpenJDK 25 is not a working substitute inside that sandbox.

The connected arm64 phone (Android API 36) appeared in `/home/smbilal/Android/platform-tools/adb devices -l`, and `/home/smbilal/Android/platform-tools/adb install -r builds/game-debug.apk` returned `Success`. The APK size is 28,413,614 bytes (27.1 MiB). The user reported that the controls feel fine on the phone. Frame rate and heat remain unmeasured.

## Useful entry points

- `src/sim/match_session.gd`: rounds, clock, timeout, sudden death.
- `src/sim/match_simulation.gd`: one fixed tick, action buffer, hit-stop, combat/projectile order.
- `src/sim/combat_exchange.gd`: checked attacks and hit resolution.
- `src/sim/combatant_state.gd`: fighter state and round reset.
- `src/ui/touch_controls.gd`: multitouch controls and safe-area layout.
- `src/network/lan_link.gd`: ENet host/client transport, input RPCs, and authoritative snapshots.
- `src/main.gd`: arena, HUD, keyboard controls, and training bot.
- `tests/test_runner.gd`: pure-logic regression tests; `tests/run_tests.sh` also checks main-scene startup.
- `tests/manual_phone.md`: local and two-phone LAN regression checks for the current APK.

## Working agreement

- Every new feature update must include its own regression tests. Add checks for the behavior changed by that update before considering the feature complete. When the user defers test execution, still write the tests and clearly mark them unrun for the user to execute.
- Always give the user the exact Git commands to review, stage, and commit the work. Do not create a commit unless the user asks you to.

The latest regression additions cover snapshot restoration and continued simulation, touch-control status and LAN setup lock, and the Android INTERNET export permission. The phone checklist covers local UI, visual feedback, FPS, LAN inputs, round transitions, and disconnects. These tests have been written but not run, per the user's request to run tests themselves.

## Suggested next work

The user asked to stop feature work and update this handoff. When they resume, have them run `./tests/run_tests.sh`, build with `./scripts/export_android_debug.sh`, and follow `tests/manual_phone.md` on the fresh APK. The user has reported that the previously installed touch controls feel fine. The new UI, capsule feedback, dummy mode, preset selector, and LAN path have not been exercised. The LAN path uses a host phone as authority on UDP port 27185 and needs two phones on the same Wi-Fi; it currently sends full reliable state snapshots every three ticks, so bandwidth and visual smoothness need device checks. During code review, note that `LanLink._receive_press()` keeps only the latest action before a host tick consumes it; multiple arrivals in one tick may drop an earlier press. This has not been observed on a device or changed. Preserve the project's integer-only, deterministic, 60-tick simulation when changing gameplay.
