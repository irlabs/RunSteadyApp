# Phase 0 spike results

Status: **device round done (2026-11-20/21).** Build and Simulator findings first, then the device results and what they mean for Phase 1. Raw logs: `docs/spike-logs/`. Steps: [spike-test-instructions.md](spike-test-instructions.md).

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
2. **Cause of the missing notification after the first real run** (confirmed by S6a: with the delegate, the foreground notification shows): the phone app had no `UNUserNotificationCenterDelegate`, and without one iOS doesn't show banners while the app is in the foreground. The run arrived by `transferUserInfo`, which was delivered when you opened the phone app. The app then posted the notification while it was in the foreground, so iOS hid it. The harness adds the delegate (`NotificationDelegate`, banners in the foreground too). F10 should keep it.
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
Run 2026-11-20, 23:34–23:37. Earlier grants already on the watch: workout and route share *authorized*, location *when in use*.

| Step | Result |
|---|---|
| Watch status before phone grant | *should request* (effort score skipped: needs watchOS 11, watch is 10.6.2) |
| Phone status after Request Health | *unnecessary*, date of birth *present* (as expected) |
| Watch status after phone grant | still *should request* |
| Watch reads date of birth | failed: "Authorization is not determined" |
| Watch needed its own request? | yes: "Request here" showed the watch's own Health prompt (Review → Read Access); after allowing, date of birth *present* |

Conclusion for F1: **the phone's Health grant does not cover the independent watch app.** Each device keeps its own HealthKit authorization, as with location. The watch must ask for every type it uses itself, so its welcome screen asks for Health (run types + date of birth) and location. The phone asks for its own types (workouts, date of birth, effort score) on its own first launch. Once the watch has its own grant, it can read the date of birth.

### S4 / F5: voices on the watch

| Voice (name · identifier) | Language | Gender | Quality | Impression |
|---|---|---|---|---|
| Daniel · `com.apple.voice.compact.en-GB.Daniel` | en-GB | male | default (compact) | chosen |

Full voice list: in the watch log (`Voice` lines), not copied here yet.

**Decision (2026-11-20): Daniel, rate 0.45, volume 1.0.** This replaces the female voice in the original F5 plan. Ducking during speech: worked.

### S5–S6 / F10: fake run delivery

Run 2026-11-21, 00:27–00:36. Delays are from the notification text (WC: since the watch sent it; HK: since the test workout ended).

| # | Phone state | WC notification | Path | WC delay | HK notification | HK delay | Sound |
|---|---|---|---|---|---|---|---|
| a | Foreground | yes | message | 0.0 s | yes | 0.7 s | yes |
| b | Background | yes | message | 0.0 s | yes | 1.2 s | yes |
| c | Force-quit | yes (app woken, state "background") | message | 0.3 s | yes | 25.4 s | yes |
| d | Locked | yes | message | 0.1 s | yes | 3.9 s | **no** (silent) |
| e | Out of reach → back | yes | userInfo | 167.2 s (incl. ~2 min in Airplane mode) | yes | not noted | — |

From the logs (`docs/spike-logs/`, times there are UTC):
- **Every run arrived twice:** by message, then by userInfo 0.2–0.6 s later (in (e) only by userInfo). The dedupe by id worked every time: one notification per run.
- **(c) force-quit:** the phone app launched with `state=background`, and `App model ready` was logged in that background launch, so SwiftUI does build the app model there. The phone received the message after 0.2 s and replied, but on the watch `sendMessage` failed with "Transfer timed out" after 15 s: the reply never got back. The userInfo copy and the acks still arrived.
- **(e) out of reach:** the watch lost reachability right after sending, so the message failed and the userInfo stayed queued. The phone got it on reconnecting (167 s); the test workout came through HealthKit at the same moment. The acks reached the watch only when its app was next opened (23:54), and the watch's own "delivered" line also came only then, long after the phone had it.
- **The watch wakes in the background for incoming userInfo** (`WKWatchConnectivityRefreshBackgroundTask`, in (c)).
- **Deleting test workouts works:** all five were deleted (`1 deleted` each), four after the phone confirmed and one, from (e), by the overdue sweep. The phone's observer saw each deletion. No leftovers expected in Fitness.
- **(d) duplicate HealthKit handling:** the observer woke twice at the same moment, both wakes ran the anchored query, and the same test workout was handled twice (two notifications, two acks). Real code must run one query at a time or dedupe by workout id.
- Phone notification permission: granted (alert, lock screen); every post returned ok.

Conclusions:
- **Both paths work in every state, including force-quit.** A `sendMessage` from the watch wakes a force-quit iPhone app in the background (c). When the phone is out of reach, the queued `transferUserInfo` arrives after reconnecting (e).
- **Foreground notifications now show** (a), which confirms finding 2: the delegate was the missing piece.
- **HealthKit background delivery is fast too** (0.7–25 s), also after force-quit. It's not needed to trigger the check-in notification (WatchConnectivity already does), but it's the way to find the watch workout on the phone for F11 (effort score).
- **Silent while locked (d):** cause unknown. Maybe a Focus mode was on (it was 00:31), or iOS chose quiet delivery. Recheck once at daytime with no Focus.

`App model ready` logged in background launches: **yes** (force-quit run (c)).

## What this means for Phase 1 (fill in after the device round)

Preliminary, based on the findings above:
- **F1 (settled by S3):** the watch welcome screen requests Health itself: run types (workout, route, heart rate, distance, energy) **plus date of birth** for F9, and location. Effort score only `#available(watchOS 11)`. The phone's grant does not carry over, so both first launches ask.
- **F5 (settled by S4):** `com.apple.voice.compact.en-GB.Daniel`, rate 0.45, volume 1.0. Fall back to the default en-GB voice if that identifier is missing.
- **F9 (decided after S3):** the phone owns the heart rate zones. It works out the zones from its own date of birth grant and sends them to the watch with the plan, so the runner can later edit zones on the phone. The watch falls back to its own date of birth (it can read it after its own grant) only when the phone sent no zones (phone not allowed or no birth date set). With neither, show heart rate without zones.
- **F10 (settled by S6):** send real runs with `sendMessage` (when reachable) plus `transferUserInfo`, deduplicated by id. Treat the message as a fast extra: its reply can time out even though the phone got it, so the watch must never resend or mark a run unsent based on the reply. Keep the app-delegate activation, the session buffering and the foreground notification delegate. That covers every phone state, including force-quit. F10b (HealthKit observer posting the notification) isn't needed for the notification; keep the observer only to find the workout for F11, and run its anchored query one at a time.
- **F11:** write the effort score from the phone only (confirmed by finding 1).
