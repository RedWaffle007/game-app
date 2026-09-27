# Phone regression checks

These checks use a freshly exported APK from the current source. Run the automated suite first with `./tests/run_tests.sh`, then build with `./scripts/export_android_debug.sh`.

## One phone: local play

1. Install `builds/game-debug.apk` and open it in landscape. Expected: the arena and HUD appear without an error or clipped controls.
2. Tap **BUILD** through all five presets. Expected: the counter advances through `1/5` to `5/5` and wraps to `1/5`; move charge labels update for the selected build, including `∞` for any Flourish.
3. Tap **BOT** to select **DUMMY**. Expected: the opponent stops initiating attacks; tapping again restores the bot. Attack with all four move buttons and confirm charge labels decrease. A depleted move shows `×0`.
4. Activate **SHIELD** and let it expire. Expected: the button shows `ACTIVE`, then a cooldown in seconds, then the remaining contact hits. Complete two contact attacks after cooldown; the shield becomes ready again.
5. Land and receive hits with Burn, Poison, or Weaken equipped. Expected: the HUD shows the active effect and a decreasing timer; fighter color/flash feedback appears for attacks and damage. Confirm the FPS counter stays visible during play.
6. Play through a round and a full match. Expected: result and next-round/rematch controls work, and HP, charges, shield, effects, and positions reset for the next round.

## Two phones: LAN play

Both phones must run the same fresh APK and use the same Wi-Fi network. The host uses UDP port 27185. Keep the app open on both phones.

1. Select different **BUILD** presets before connecting. On phone A, open **LAN** and tap **HOST**. On phone B, open **LAN**, enter phone A's displayed local IP, and tap **JOIN**. Expected: both phones show the selected host and guest builds and the three-second reveal countdown, then start the same match.
2. Move, duck, jump, dash in both directions, attack, and shield from each phone. Expected: both displays agree on position, HP, charges, effects, and round clock after snapshots arrive. A quick joystick flick must dash in the flick direction even after the finger is lifted.
3. Finish a round, then tap **NEXT** on each phone in turn. Expected: the host controls the transition and both phones reach the same next-round state. Repeat through match end and test **REMATCH**.
4. During a match, disconnect phone B or turn off its Wi-Fi. Expected: phone A reports the disconnect and does not keep moving the guest from stale held input. Rejoin or return to **OFFLINE** and confirm local play controls work again.
5. Confirm **BOT/DUMMY** and **BUILD** setup buttons are hidden during LAN play and visible again after returning to **OFFLINE**.

Record any failed step, both devices' Android versions, and the displayed FPS. For a performance check, play for ten minutes and note sustained FPS and whether either phone becomes uncomfortably hot.
