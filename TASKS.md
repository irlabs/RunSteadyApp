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
- **Extended run, "felt good":** feeds the early step-up (`.advanceEarly`) below. It never speeds up the plan on its own.
- **Early step-up (`.advanceEarly`):**
  - **Trigger:** a run extended with "felt good" in 2 of the last 3 planned sessions; none of those runs had knee issues, an uncomfortable pace or a "Tough" rating; no open injury note; no step-back in the last 2 weeks.
  - **Effect:** step up after 2 comfortable sessions instead of 3. Offered on the card (Try it / Stay steady, default Stay steady).
  - **Limits:** at most once per week of the plan, never skips a week, never early into week 8.
  - **Safety net:** if the run after an early step-up is Tough, uncomfortable or sore, repeat the session and allow no early step-ups for about 2 weeks.
- **Manual sessions** (an easier run with a friend, for example):
  - Reset the gap clock.
  - Don't count toward progress or change the week.
  - Pain reported on them still counts.
  - Afterwards the coach asks "One-off or keep it easier?"; the default is back to the plan.
- **Coach notes:** shown in the check-in only, not on the Today screen.

## Steps

- [ ] 1. `RunSteady/Coach.swift`: drop `fallbacks` and the `server-side-fallback` beta header. Haiku 5.5 has no server-side fallback.
- [ ] 2. Rule fixes in `Progression.swift` (TDD): the gap clock counts from the last session of any kind; manual sessions don't count toward progress or move the week; pain on any session counts.
- [ ] 3. Run analysis in RunSteadyKit (TDD): per-run deviations from `SegmentRecord`s (run extended, walk extended, extra rounds, stopped early, easier than plan), each with a stable id. Apply the noise threshold.
- [ ] 4. `DeviationReason` enum, plus reasons stored on `CheckIn` as an optional field so existing stored check-ins still load. Mark each reason incidental or physical.
- [ ] 5. Structural walking rule (TDD). **The core function is for Dirk to write.** Scaffold and tests first.
- [ ] 6. Early step-up `.advanceEarly` (TDD). Give `suggestion(...)` a `hasOpenInjury` input. Treat `.advanceEarly` like `.advance` in the gap handling. Track the dates of the last step-back and the last early step-up for the cooldown.
- [ ] 7. Check-in UI (`CheckInView.swift`): after the three fixed questions, ask about at most 2 notable deviations with reason buttons; after an easier manual run, ask "One-off or keep it easier?".
- [ ] 8. `CoachNote` SwiftData model (text, kind, open/resolved, follow-up flag, date, session id). A mild or painful knee answer opens an injury note automatically. Notes resolve after about 3 weeks without a mention.
- [ ] 9. Note extraction: after each user chat message, a second Haiku call returns `output_config.format` JSON `{new_notes, resolve_ids}`. It's given the open notes with their ids so it resolves rather than duplicates.
- [ ] 10. Coach prompt: open notes with their age, a short code-written summary of recent runs, today's deviations with reasons, early step-up eligibility. Ask about follow-up notes once; never invent bigger jumps.
- [ ] 11. History: show and delete coach notes.
- [ ] 12. Verify: `swift test` in RunSteadyKit, plus both `xcodebuild test` schemes.
