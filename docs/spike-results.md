# Phase 0 spike results

Status: **harness built, device round pending.** Findings from building and the Simulator are below; the device tables still need filling in (steps in [spike-test-instructions.md](spike-test-instructions.md)).

## What the harness is

| Task | Where | Notes |
|---|---|---|
| S1 diagnostics log | `Shared/Diagnostics.swift` | `os.Logger` (subsystem `RunSteady`) + `Application Support/diagnostics-<device>.jsonl`, capped at 2,000 entries. Logs permissions, WatchConnectivity (activation, reachability, path, delay), notification posts, HealthKit observer wakes, app lifecycle. |
| S2 hidden screens | `RunSteady/DiagnosticsView.swift`, `RunSteadyWatch/WatchDiagnosticsView.swift` | Phone: long-press title on Today. Watch: long-press tortoise. Watch → phone log via `transferFile`; phone shares both logs. |
| S3 permission check | `RunSteady/PhoneSpike.swift` (`HealthObserver`), `RunSteadyWatch/WatchSpike.swift` | Types not asked for yet: date of birth (read), workout effort score (share). |
| S4 voice lab | `WatchDiagnosticsView.swift` (`VoiceLabView`), `Cues.preview` | All `en-*` voices, rates 0.45/0.5, volumes 0.7/1.0, same ducking session as a run. |
| S5 fake run | `WatchSpike.fakeRun()`, `TestRunReceiver`, `HealthObserver` | `SessionRecord.isTest`; message + userInfo; 1-min `HKWorkout` with metadata `RunSteadyTest`; phone never stores test records. |

Launch argument for scripted checks: watch `-fakeRunOnLaunch YES` sends a fake run 5 s after launch.

## Findings so far (build and Simulator)

1. **The effort score can't be used on the watch.** `HKQuantityType(.workoutEffortScore)` needs watchOS 11. A Series 5 can't go past watchOS 10, so the watch can neither request nor write it. F11 already plans to write it from the phone, so that stays. F1: the watch's welcome screen must not request the effort type on watchOS 10 (the harness checks with `#available`).
2. **Likely cause of the missing notification after the first real run** (to be confirmed by S6a): the phone app had no `UNUserNotificationCenterDelegate`, and without one iOS doesn't show banners while the app is in the foreground. The run arrived by `transferUserInfo`, which was delivered when you opened the phone app. The app then posted the notification while it was in the foreground, so iOS hid it. The harness adds the delegate (`NotificationDelegate`, banners in the foreground too). F10 should keep it.
3. **Sessions could be lost in a background launch.** WatchConnectivity was only activated inside `AppModel` (a SwiftUI `@StateObject`). When iOS wakes the app in the background, it's not certain SwiftUI builds the scene, and before that `onSession` was nil, so a delivered session was dropped without a trace. The harness now activates in `AppDelegate.didFinishLaunching` and holds sessions until `AppModel` is ready. The log line `App model ready` shows whether the model is built in a background launch. F10 should keep both.
4. **The HealthKit observer needs re-registering after the grant.** On a fresh install the observer query fails with "Authorization not determined" and stops. It's now registered again after "Request Health". For F1/F10b: request Health on the phone's first launch, and register the observer again after the grant.
5. **Simulator limits.**
   - Simulator-to-Simulator WatchConnectivity couldn't be scripted: apps installed with `simctl` aren't registered as companions (`companionInstalled=false` / `watchAppInstalled=false`). The watch still logged `userInfo … delivered`, but the phone never received it. So a "delivered" on the watch side doesn't prove the phone app got it: always check the phone log.
   - In the Simulator the test workout is skipped unless the watch runs with `-useHealthKit YES`.
6. **Signing.** The command-line device build failed: the Xcode account login was rejected, and the old phone profile has no HealthKit. Build once from the Xcode GUI after signing in again (see instructions).
7. **Test workout clean-up after 10 minutes, not 5.** The watch deletes the test workout only after the phone has *seen it through HealthKit*, not when the WatchConnectivity message arrives. Deleting on the WatchConnectivity ack would remove it before Health syncs to the phone, which would hide F10b. The timeout was raised to 10 minutes for the same reason.
8. **Watch Simulator destination.** `name=Apple Watch Series 10 (46mm)` matched two Simulators (watchOS 11.1 and 11.2), and `xcodebuild` refused it. Adding `OS=11.2` did not help (it still matched the paired one through its iPhone), so CLAUDE.md now uses the Simulator id.

## Device results (fill in)

Devices: iPhone ___ (iOS ___), Apple Watch Series 5 (watchOS 10.6.2). Build: ___

### S3 / F1: permissions

| Step | Result |
|---|---|
| Watch status before phone grant | |
| Phone status after Request Health | |
| Watch status after phone grant | |
| Watch reads date of birth | |
| Watch needed its own request? | |

Conclusion for F1: ___

### S4 / F5: voices on the watch

| Voice (name · identifier) | Language | Gender | Quality | Impression |
|---|---|---|---|---|
| | | | | |

Preferred voice / rate / volume: ___. Ducking worked during speech: yes / no.

### S5–S6 / F10: fake run delivery

| # | Phone state | WC notification? | First path | Delay | Second path / delay | HK notification? | HK delay | Watch got HK ack? | Test workout deleted? |
|---|---|---|---|---|---|---|---|---|---|
| a | Foreground | | | | | | | | |
| b | Background | | | | | | | | |
| c | Force-quit | | | | | | | | |
| d | Locked | | | | | | | | |
| e | Out of reach → back | | | | | | | | |

Leftover test workouts in Health/Fitness: ___

`App model ready` logged in background launches: yes / no.

## What this means for Phase 1 (fill in after the device round)

Preliminary, based on the findings above:
- **F1:** watch welcome screen requests location + run types; effort score only `#available(watchOS 11)`. Whether the watch must also request date of birth depends on S3.
- **F5:** pick the voice identifier from S4; keep the fallback to the default en-GB voice.
- **F9:** reading the birth date on the watch depends on S3. If the watch can't read it, the phone sends the age (or max HR) with the plan.
- **F10:** keep the app-delegate activation, the session buffering and the foreground notification delegate. Send real runs by message too. Whether HealthKit background delivery is worth keeping depends on S6 (c) force-quit and (e) out of reach.
- **F11:** write the effort score from the phone only (confirmed by finding 1).
