# Run Steady — Styleguide v1: ideas to adopt

2026-11-17

## Context

The first styleguide pass documented the current iPhone and Watch screens and suggested about a dozen improvements, collected below. Full specs are in the [styleguide canvas](https://claude.ai/artifact/5kdaAVK3GDTjwsLFcPEiTx). Nothing has been built in code yet.

## Colour and accessibility

Chip and label text fails contrast today: each colour on its own 15% tint is only 2.2–2.6:1. The fix is a darker text shade per colour, used only for text and icons on light backgrounds.

| Token | Hex | Contrast on white |
| --- | --- | --- |
| brandText | #0E7A4A | 5.4:1 |
| runText | #C43E1F | 5.2:1 |
| walkText | #0A7F9C | 4.6:1 |
| warmText | #8F5B00 | 5.7:1 |
| coolText | #5B4BE0 | 6.0:1 |
| heartText | #D42A47 | 5.0:1 |

- The bright colours stay for fills, the schedule strip and the watch.
- Write the tint rule down: 13–15% on the phone, 18–20% on the watch, 22% for empty tracks.
- Watch buttons: use dark (ink) text on the yellow warm-up colour, where white is only 1.9:1. Consider dark text on walk blue for bright sunlight.

## Steady's emotions

Steady gets 7 new faces on the same body, each tied to a moment in the app. Only the face and one accessory change, so it still reads at small sizes.

| Emotion | When it appears | Accessory |
| --- | --- | --- |
| Neutral (exists) | Header, chat, progress track | — |
| Happy | Check-in answered "Great", session logged | Blush |
| Proud | "Steady does it!", step up, plan complete | Sparkles |
| Focused | Watch Start screen, run in progress | Speed lines |
| Thinking | Coach is typing | Thought dots |
| Encouraging | "Tough", repeat session, back after a gap | Heart |
| Concerned | Pain reported, step back (body signals only) | Sweat drop |
| Resting | Rest day | Zz |

- Also add 2 single-colour versions: white for coloured backgrounds, ink for complications.
- Rules: always faces right; the sweatband is always coral; no accessory below 34 pt; no animation during a run.

## Schedule strip and watch

- **Live strip:** finished segments solid, the current one outlined, upcoming ones at 30%. Good for the watch between rounds and for a run-in-progress card on the phone.
- **Fixed strip sizes:** large 18 pt, medium 14 pt, small 8 pt. Below 8 pt, use a plain progress bar instead.
- **PAUSED pill on the watch:** yellow, replaces the phase pill while paused.
- **Rule to keep:** the big watch button shows what comes next, in the colour of the next segment.

## New phone components

- **Empty state:** resting Steady, one line of text and a primary button. History has none yet.
- **Run-in-progress card:** live strip plus elapsed time on Today while the watch is running.
- **Inline notice:** show the watch-version and sync alerts as a yellow-tinted card instead of a pop-up.
- **Dark mode check:** test the brand tints at 20% on the dark card colour (#1C1C1E).

## Next steps

Tracked in [TASKS.md](../TASKS.md) under "Design ideas v1".
