# Run-Walk App Plan

Run Steady is an iPhone and Apple Watch app for a slow, steady run-walk progression, built around a standalone watch app and a phone app for planning, history and check-ins. A tortoise serves as its avatar and mascot, standing for slow, steady progress.

## Goals

- Build up gently to a steady 5 km, maybe 10 km later. No marathon ambitions.
- Avoid the pattern of progressing too fast and getting knee or muscle trouble.
- Base the default progression on established run-walk practice, suited to a 50-year-old.
- The user is always in control: manual schedules override automatic ones.

## Default progression and gap handling

Schedule recommendations follow common run-walk practice for beginners: small, gradual steps up from short run intervals, about three sessions a week with rest days, building towards a continuous 5K in roughly eight weeks. A 10K would be a later phase.

After missed sessions or a longer break, the app repeats or steps back to an easier session, again following common practice, and holds or backs off when pain is reported.

## Watch app (fully standalone, no phone needed)

- Behaves like a timer app, not an automatic sequencer.
- When a segment's target time is up, it gives haptic and sound feedback, then keeps counting past the target until the user taps next segment. Only then does the next segment start counting.
- Actions: next segment (main action), pause and finish workout. No separate add-a-round action; continuing is just tapping next.
- Live round counter, for example round 3 of 5, with extra rounds counted as they happen.
- Every session includes a warm-up and cool-down, editable per schedule, with the same timer behaviour, and an extra action to start the run, if I feel I warmed-up enough.
- Tracks heart rate and GPS route in a proper HealthKit workout session, and saves the workout to Apple Health at the end, which also avoids Apple's exercise prompts.
- Pace in minutes per kilometre is always shown on screen.
- A toggle on the watch enables or disables a spoken announcement every kilometre, giving pace and total distance so far.
- Plays the user's own audio while running. When a cue fires, the audio dips in volume rather than muting, then recovers after the tap.
- Stores the schedule and finished sessions locally, since the phone stays at home.

## Phone app

- Schedule editor: full manual control, for example exactly 3 minutes walking and 1 minute running, with repeats, warm-up and cool-down. Manual schedules always override the automatic progression.
- After a run, the app suggests the next schedule, which the user can accept or ignore.
- Session history, including actual segment durations and overruns.
- Post-run check-in on the phone: how did it go, was it comfortable, any knee issues. Answers are logged.
- When the watch comes back in range of the phone, the phone sends a notification prompting the check-in. The ping may arrive slightly after reconnecting.

## How the language model fits in

- Call an existing language model through an API, with no training needed.
- The model handles the check-in conversation and explains suggestions.
- Schedule rules stay deterministic in code: a rule layer decides whether to hold, repeat or step back, based on logged answers and gaps.
- Check-in happens after the run only, not during it.

## Open items for later

- Week-by-week progression table for 5K, then 10K phase.
- Exact step-back rules by gap length and by reported discomfort.
- Data sync design between watch and phone, and how schedules reach the watch.
- Which language model and how its conversation data is handled.
