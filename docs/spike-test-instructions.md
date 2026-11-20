# Phase 0 device spike: install and test

One install on both devices, then a round of checks from the hidden diagnostics screens. Nothing lands in History. Write what you see into [spike-results.md](spike-results.md).

Time needed: about 45 minutes after the install.

## 0. Before you start

- **Xcode account:** the command-line build failed with "login details … were rejected" and "No iOS Development signing certificate". Open Xcode → Settings → Accounts and sign in to your Apple ID again.
- **New phone capability:** the iPhone app now has HealthKit with background delivery (`Config/RunSteady.entitlements`). The first build from Xcode regenerates the Personal Team profile. If Xcode says the profile doesn't support HealthKit, open the RunSteady target → Signing & Capabilities and click "Try Again". If background delivery can't be signed with a Personal Team, remove the `healthkit.background-delivery` key from `Config/RunSteady.entitlements`, build again, and note this in the results (it would mean F10b can't work on a Personal Team).
- Personal Team profiles expire after 7 days. Re-sign if the apps stop launching.

## 1. Install

### iPhone

1. Plug in the iPhone (or use Wi-Fi), unlocked.
2. Xcode → scheme **RunSteady** → target your iPhone → Run (⌘R).
3. Allow notifications when asked.

### Watch (the method that works)

1. Restart the watch and the iPhone, and quit and reopen Xcode.
2. iPhone: turn **Bluetooth off in Settings** (Control Center is not enough), so the watch stays on Wi-Fi.
3. Watch: at least 80% battery. Start a 30-second timer that repeats, to keep it awake.
4. Xcode → Window → Devices and Simulators: wait for the watch to connect.
5. Choose scheme **RunSteadyWatch** → target your watch → Run.
6. **Turn iPhone Bluetooth back on** afterwards. The sync checks below need it.

### Check the install

- Phone, Today screen: the watch status line at the bottom shows the same build on both devices.
- Watch, start screen: the version under the Km voice toggle.

## 2. Open the diagnostics screens

- **Phone:** long-press the "Run Steady" title on Today.
- **Watch:** long-press the tortoise on the start screen.

Every action writes to the log there (newest first). The log is also in Console.app (subsystem `RunSteady`) when the device is connected to the Mac.

## 3. F1: does the phone's Health grant cover the watch?

Do these in order. Asking on the watch first would spoil the test.

1. **Watch** → Check status. Note the line `Request status (watch) for birth date: …`. Expected: *should request*.
   - On your Series 5 (watchOS 10) the log also says the effort score type needs watchOS 11. That's expected: see Findings in spike-results.
2. **Phone** → Request Health. iOS shows the Health sheet. Allow everything (workouts, date of birth, effort).
   - The log should then say `Request status (phone): unnecessary` and `Date of birth (phone): present`.
3. **Watch** → Check status again.
   - *unnecessary* = the phone's grant covers the watch app.
   - *should request* = the watch must ask itself (F1 needs its own prompt on the watch).
4. **Watch** → Read birth date. Note whether it reads (`present`) or fails (`… failed: <error>`).
5. Only if step 3 said *should request*: **Watch** → Request here, then Read birth date again.

## 4. F5: voice lab (watch)

1. Watch diagnostics → Voice lab. The footer shows how many English voices there are. All of them are written to the log.
2. Connect AirPods or use the watch speaker. Play some music if you want to hear the ducking.
3. Tap voices to hear the cue "Walk. 2 kilometres. 8 minutes 15 per kilometre." Try **Rate** 0.50 / 0.45 and **Volume** 1.0 / 0.7.
4. Note which female en-GB voices exist and which one you like (name and identifier, both shown in the log).

## 5. F10: fake run, five ways (watch → phone)

Each **Fake run** tap on the watch:
- sends a test run by message (if the phone is reachable) and as userInfo,
- saves a 1-minute test workout in Health (metadata `RunSteadyTest`).

On the phone you should get up to two notifications:
- "Test run received via message / userInfo": from WatchConnectivity. The body says the delay and the phone app's state.
- "Test workout seen via HealthKit": from the HealthKit observer, after Health syncs from the watch.

The watch deletes the test workout once the phone has seen it through HealthKit, or after 10 minutes.

Do one fake run per state. Wait about 2 minutes between runs (HealthKit sync can be slow). Fill in the S6 table in spike-results as you go.

| # | Phone app state | How |
|---|---|---|
| a | Foreground | Run Steady open on the phone, screen on |
| b | Background | Open Run Steady, then go to the home screen |
| c | Force-quit | Swipe Run Steady away in the app switcher |
| d | Locked | Open Run Steady, then lock the phone (side button) |
| e | Out of reach | Phone in Airplane mode (Bluetooth and Wi-Fi off). Tap Fake run on the watch, wait 2 min, then turn Airplane mode off and wait up to 5 min |

For each, note:
- Did each notification appear? Write the path and delay from its text.
- Did the watch log say `Phone confirmed receiving the run …` and `Phone confirmed seeing the test workout …`?
- Did the watch log say `Delete test workout …: 1 deleted` (or `failed: …`)?

## 6. Collect the logs

1. Watch diagnostics → Send log to phone. The phone log says `Watch log received: N entries`.
2. Phone diagnostics → share button (top right) → AirDrop to the Mac. This sends both logs (`.jsonl`).
3. Put them in `docs/spike-logs/` (or attach them in the chat) and I'll read them into spike-results.

## 7. Clean up

- Watch diagnostics → Delete test workouts (this deletes every workout this app saved with the test marker).
- Check Fitness / Health on the phone for leftover 1-minute "Running" workouts and delete them by hand if needed. Note in spike-results whether any were left.
