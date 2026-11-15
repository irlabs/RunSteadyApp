# CLAUDE.md

Run Steady: iPhone + standalone Apple Watch app for run-walk progression. Product plan: [PLAN.md](PLAN.md).

## Stack
- Swift, SwiftUI (UIKit only where SwiftUI falls short)
- Targets: iOS 18+, watchOS 10+
- Persistence: SwiftData
- HealthKit (workout sessions, HR, GPS route), WatchConnectivity for phone ↔ watch
- LLM via external API, post-run check-in only

## Structure
- One Xcode project, iOS app target + watchOS app target
- Shared local Swift package for models and the schedule rule layer (no UI, no platform APIs) — used by both apps
- Watch app must work fully without the phone

## Rules
- Schedule/progression logic is deterministic code in the shared package. LLM never decides schedules; it only talks and explains.
- Manual schedules always override automatic progression.
- Units always metric (km, min/km).
- UI strings in English.
- Never commit API keys or secrets. Keep them in a gitignored config file.

## Testing
- Swift Testing (`@Test`, `#expect`) for unit tests; XCTest only for UI tests.
- TDD where practical, always for the rule layer and other shared-package logic.

## Build & test
- Claude builds and runs tests via `xcodebuild` CLI.
- Shared package: `swift test` from the package directory.
- App targets: `xcodebuild test -scheme <Scheme> -destination '<simulator>'` — fill in exact schemes/destinations once the project exists.

## Workflow
- Keep overhead low. No GitHub issues needed.
- Track plan and subtasks in Markdown files (e.g. `TASKS.md` checklist), not in a tracker.
