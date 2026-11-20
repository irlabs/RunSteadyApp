# Coach memory and run analysis

Goal: the coach remembers what you told it (e.g. a sore knee) and asks about it later, asks why a run differed from the schedule, and tells one-off deviations (traffic, a hill, running with a friend) apart from patterns (needing longer walks). Model stays `claude-haiku-5-5` at default settings.

Principle: code computes the facts, taps give the reasons, Haiku asks and talks. Anything that changes the schedule comes from a tap or from deterministic code, never from the model's reading of free text. The one exception: injury notes the model extracts may make the plan more careful (block an early step-up), never less careful.

## Decisions

- **Ignored differences:** under about 20 s or 10% of a segment target.
- **Reasons (tap buttons):**
  - Incidental, never counted: traffic, terrain/hill, with someone, felt good.
  - Physical, counted: needed the rest, discomfort.
- **Skipped reason:** a single deviation is ignored. If it's part of a pattern, it counts toward "structural".
- **Structural walking:** a walk extended (physical or unanswered reason) in 3 of the last 5 planned sessions → step back one week. Offered on the suggestion card, never applied automatically. Count only sessions since the last step-back, so it can't trigger twice in a row.
  - **Walk extended (per session, planned rounds only):** (long walks — over the noise threshold — in at least min(2, ⌈rounds/3⌉) rounds **and** total walk overrun ≥ max(60 s, 10% of planned walk time)) **or** one walk > 75% over target **or** total walk overrun > 25% of planned walk time. The total counts every walk's overrun, small ones included. This is the only definition: the check-in only asks about walks that pass it.
  - **Reasons:** physical counts, incidental never. Skipped reason and no check-in at all both count. The tapped reason decides even with soreness or "Tough".
  - **Window:** 3 of the last 5, or 3 of fewer if fewer exist. Spans step-ups. Restarts on any drop in week (pain, accepted offer, gap, "Welcome back" undoing a step-up) and on a declined offer.
  - **Effect:** the week below the week actually run, session 1 (also on a run that earned a step-up). Wins over repeat and "Welcome back". Never in week 1; never on top of a pain or gap step-back.
  - **Keep mine:** applies the normal plan (step-ups included) and stores the decline date, which restarts the window.
  - **Card:** chip "Settle in"; reason "Your walk breaks ran long in 3 of your last 5 runs (or: in your last 3 runs). A week back lets the running catch up. Prefer to carry on with week N? Tap Keep mine."
- **Extended run, "felt good":** feeds the early step-up (`.advanceEarly`) below. It never speeds up the plan on its own.
- **Early step-up (`.advanceEarly`):**
  - **Trigger:** a run extended with "felt good" in 2 of the last 3 planned sessions; none of those runs had knee issues, an uncomfortable pace or a "Tough" rating; no open injury note; no step-back in the last 2 weeks.
  - **Effect:** step up after 2 comfortable sessions instead of 3. Offered on the card (Try it / Stay steady, default Stay steady).
  - **Limits:** at most once per week of the plan, never skips a week, never early into week 8.
  - **Safety net:** if the run after an early step-up is Tough, uncomfortable or sore, repeat the session and allow no early step-ups for about 2 weeks.
- **Manual sessions** (an easier run with a friend, for example):
  - Reset the gap clock.
  - Never bank sessions. A checked-in, completed, comfortable, not-Tough, pain-free manual run **above** the plan moves the plan up one week (`.advanceFromManual`, "Catching up"), never past the run's own level. Tough/incomplete ones are ignored.
  - Level of a manual schedule (`ProgressionPlan.level(of:)`): midpoint of the week matched by total running time and the week matched by run-block length, rounded toward the block-length week.
  - The card then offers Use this / Keep mine. Treated like `.advance` in the gap handling.
  - Pain reported on them still counts.
  - Afterwards the coach asks "One-off or keep it easier?"; the default is back to the plan.
- **Coach notes:** shown in the check-in only, not on the Today screen.
- **Settled while building steps 6–11:**
  - Early step-up "none of those runs" = none of the last 3 planned sessions. Only a run extended with "Felt good" counts (not extra rounds).
  - "Once per week of the plan" = each plan week can be left early once. An early step-up, the last step-back and the safety-net run are all derived from history in the fold (a session at a higher week than the fold reached = accepted early step-up), so nothing extra is stored.
  - Offers with a fallback quietly apply the fallback when its intervals equal the current ones, so ignoring the card means Stay steady / Keep mine. Plan and Today show the stay-steady position until "Try it".
  - Check-in asks at most 2 of: walk breaks, runs extended, stopped early, extra rounds (that order), with a Skip button. Reasons offered per kind; "Felt good" never for walks, physical reasons never for longer runs.
  - "Keep it easier" keeps the manual schedule and dismisses the suggestion; "One-off" applies the plan.
  - Extractor schema adds `mentioned_ids` (needed for "3 weeks without a mention"). The model can't resolve an injury note (that would loosen the plan); it counts as a mention and ages out, or the runner deletes it in History → Coach notes.
  - Follow-up notes are asked about once in the wrap-up, never for a note from the same check-in.

## Steps

- [x] 1. `RunSteady/Coach.swift`: drop `fallbacks` and the `server-side-fallback` beta header. Haiku 5.5 has no server-side fallback.
- [x] 2. Rule fixes in `Progression.swift` (TDD): the gap clock counts from the last session of any kind; manual sessions don't count toward progress or move the week; pain on any session counts.
- [x] 3. Run analysis in RunSteadyKit (TDD): per-run deviations from `SegmentRecord`s (run extended, walk extended, extra rounds, stopped early, easier than plan), each with a stable id. Apply the noise threshold.
- [x] 4. `DeviationReason` enum, plus reasons stored on `CheckIn` as an optional field so existing stored check-ins still load. Mark each reason incidental or physical.
- [x] 5. Structural walking rule (TDD). Decisions settled in an interview; see Decisions above.
- [x] 6. Early step-up `.advanceEarly` (TDD). Give `suggestion(...)` a `hasOpenInjury` input. Treat `.advanceEarly` like `.advance` in the gap handling. Track the dates of the last step-back and the last early step-up for the cooldown.
- [x] 7. Check-in UI (`CheckInView.swift`): after the three fixed questions, ask about at most 2 notable deviations with reason buttons; after an easier manual run, ask "One-off or keep it easier?".
- [x] 8. `CoachNote` SwiftData model (text, kind, open/resolved, follow-up flag, date, session id). A mild or painful knee answer opens an injury note automatically. Notes resolve after about 3 weeks without a mention.
- [x] 9. Note extraction: after each user chat message, a second Haiku call returns `output_config.format` JSON `{new_notes, resolve_ids}`. It's given the open notes with their ids so it resolves rather than duplicates.
- [x] 10. Coach prompt: open notes with their age, a short code-written summary of recent runs, today's deviations with reasons, early step-up eligibility. Ask about follow-up notes once; never invent bigger jumps.
- [x] 11. History: show and delete coach notes.
- [x] 12. Verify: `swift test` in RunSteadyKit, plus both `xcodebuild test` schemes.
- [x] 13. Phone re-sends the active plan on launch, activation and watch-state changes; watch queues a plan received mid-run.
- [x] 14. Plan tab shows the active manual schedule.
- [x] 15. Manual runs above the plan step it up one week at a time (TDD).
- [ ] 16. (See F10.) Check on device that a run synced from the watch triggers the check-in notification with the phone app closed.

## Design ideas v1

From [docs/design-ideas-v1.md](docs/design-ideas-v1.md).

- [ ] D1. Add darker text colours (`brandText`, `runText`, `walkText`, `warmText`, `coolText`, `heartText`) to `Shared/Theme.swift`; use them for chip and label text on light backgrounds.
- [ ] D2. Watch buttons: ink label on warm-up yellow (and consider it on walk blue).
- [ ] D3. Add an emotion setting to `TortoiseView` (happy, proud, focused, thinking, encouraging, concerned, resting) plus mono-white and mono-ink versions; connect each to its moment.
- [ ] D4. Fixed schedule strip sizes (18 / 14 / 8 pt) and a live strip state (done solid, current outlined, upcoming 30%).
- [ ] D5. PAUSED pill on the watch, replacing the phase pill while paused.
- [ ] D6. Empty state for History (resting Steady, one line, primary button).
- [ ] D7. Run-in-progress card on Today while the watch is running.
- [ ] D8. Inline notice card for watch-version and sync alerts instead of a pop-up.
- [ ] D9. Dark mode check of brand tints on #1C1C1E.

## First-run feedback (2026-11-20)

From the first real run. Decisions settled in an interview.

- [ ] F1. **Permissions up front.** Watch: a one-time welcome screen on first launch ("Steady tracks your runs with Health + GPS" → Continue) that triggers the HealthKit and location prompts (now in `HealthKitSensor.start()`, `RunSteadyWatch/Sensors.swift`). Phone: ask for Health in its own first launch (needed for F11). Spike: check on device whether the phone's HealthKit permission also covers the independent watch app. Location is per device, so the watch always has to ask for it itself.
- [ ] F2. **Big time counts down** to `0:00` for the segment target, then counts up from `+0:01` in the segment colour until next is tapped.
- [ ] F3. **Arc progress** instead of the flat bar: a 270° arc along the screen edge, filling clockwise from 7:30 to 4:30 (25% open at the bottom); time and phase pill inside. Overtime: the full arc pulses or changes tint.
- [ ] F4. **Repeating cue:** chime + haptic every 8 s after the target is reached, until next is tapped (`Cues.targetReached`). Keep other audio ducked while it repeats.
- [ ] F5. **Softer voice:** a female British (en-GB) voice chosen by identifier, slightly slower and quieter, with a fallback to the default en-GB voice. Check which voices exist on watchOS (Series 5).
- [ ] F6. **Km announcement = split pace** of the last km (store clock and distance at each km boundary; now `clock / distance` since start, which includes the warm-up). Speech: "8 minutes" instead of "8 minutes 0". Possible "0 minutes" bug: no bug found in code yet; unit-test the formatting for edge cases (pace < 60 s, whole minutes, first km right after GPS lock). Listen carefully on the next run.
- [ ] F7. **Watch start summary on one line** (drop "with warm-up and cool-down") so the start button fits without scrolling.
- [ ] F8. **Small values while running:** 1st = total exercise time; 2nd = heart rate (F9); 3rd = pace (min/km) during run and warm-up, total km during walk and cool-down.
- [ ] F9. **Heart rate zone colour:** 5 zones as % of max HR (220 − age, age from the HealthKit birth date; needs read permission for date of birth). Shown as a small coloured dot or ring next to the bpm value. Zone maths in RunSteadyKit (TDD).
- [ ] F10. **Push notification after a run** (supersedes step 16). Do both: (a) the watch sends the finished session with `sendMessage` when the phone is reachable (wakes the iOS app), with `transferUserInfo` as backup; (b) the phone registers HealthKit background delivery for workouts, and on wake posts the check-in notification (or waits for the session). Run was received fine (orange card showed on opening); only the notification was missing. Verify on device with the phone app in the background and with it force-quit.
- [ ] F11. **Effort slider** as the first check-in question, 1–10, starting at 5. Mapping to `Feeling`: 1–4 Great, 5–7 Okay, 8–10 Tough (TDD in RunSteadyKit). Store the score on `CheckIn` (optional field). Phone writes it to Apple Health as the workout's effort score (`workoutEffortScore`, related to the watch workout found by date); if the workout hasn't synced to the phone's Health yet, retry later.
- [ ] F12. **Free text on the other check-in questions**, next to the suggested-answer buttons. Typed text counts as no tap for the rules (it never changes the schedule); it goes to the coach and the note extractor, so an injury note can still make the plan more careful.
- [ ] F13. **"Keep mine" looks disabled:** give the secondary button a clearly enabled style (`SuggestionCard`, `RunSteady/TodayView.swift`).
- [ ] F14. **Suggestion with a manual schedule:** on Today, show the suggestion card *below* the manual next session, collapsed: "Steady suggests" line + chip, title, schedule bar, buttons "Ignore" / "Use this". The reason line is hidden and shown on tap. After Ignore, the card stays hidden until a new suggestion appears; editing the manual schedule must not bring it back (now `apply()` clears `dismissedSuggestion`). Elsewhere the buttons stay "Keep mine" / "Use this".
- [ ] F15. **Gap rules on the watch:** when the watch app opens, apply the existing gap rules (6 days → repeat, 12 → back 1 week, 24 → back 2 weeks) using the days since the last session of any kind, with the shared RunSteadyKit rule code, so the plan is right without the phone. Start screen shows "Welcome back, it's been N weeks → Week X". The phone and the watch must reach the same result (deterministic, same inputs); the phone's plan wins once it syncs. TDD for the shared part.
