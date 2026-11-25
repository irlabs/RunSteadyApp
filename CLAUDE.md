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
- App targets (each scheme also runs its XCUITest demo walkthrough):
  - `xcodebuild test -project RunSteady.xcodeproj -scheme RunSteady -derivedDataPath build/dd -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.3.1'`
  - `xcodebuild test -project RunSteady.xcodeproj -scheme RunSteadyWatch -derivedDataPath build/dd -destination 'platform=watchOS Simulator,id=18F51A38-41C5-454E-9F08-6A9A7326F0B1'` (Series 10 46mm, watchOS 11.2; by name, xcodebuild also matches the 11.1 one paired to an iPhone 16 Plus and gives up)
- Real devices (from repo root): `scripts/deploy` = `scripts/build` + `scripts/install` (phone via devicectl, then launch; iOS pushes the embedded watch app). `scripts/install-watch` = direct watch install with retries (flaky over Bluetooth). Device ids in `scripts/_env.sh`, override in gitignored `scripts/local.env`.
- Versioning: marketing version in `VERSION`. Every build (Xcode GUI, `scripts/build`, tests) runs the "Stamp Version" phase (`scripts/stamp-version`): the watch app gets `VERSION` + build number `yymmdd.HHMMSS` = time of the newest change to the app sources, and the phone copies both from its embedded watch app. Same code → same number, also when the watch is installed from its own scheme; Today says "Watch app differs from this phone's build" otherwise. `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in the project are overwritten. After `generate_project.py`, restore the Xcode-saved `RunSteadyWatch.xcscheme` (`git checkout` it). Watch reports its `AppVersion` to the phone; Today shows the status. Bump `SyncProtocol.current` (RunSteadyKit/AppVersion.swift) on breaking sync changes, and `minimumWatch` when the phone can't work with older watches (triggers "Watch app too old" alert).
- Project file is generated: `python3 Config/generate_project.py` (only needed when targets/build settings change; source folders are synchronized groups).
- Launch arguments: phone `-demoSeed YES` (in-memory sample history), `-demoOpenRun YES` (with demoSeed: as if the check-in notification was tapped); watch `-timeScale <n>` (fast-forward), `-demoStage <i> -demoSession <n>`, `-inMemory YES`, `-useHealthKit YES` (Simulator defaults to simulated sensors), `-fakeRunOnLaunch YES` (diagnostics fake run 5 s after launch), `-welcomeDone YES|NO` (skip or force the first-launch welcome + permission prompts), `-demoAge <n>` (heart rate zones without a date of birth), `-demoGapDays <n>` (pretend the last run was n days ago: "Welcome back" step-back).
- Hidden diagnostics (device checks, log): phone long-press the title on Today; watch long-press the tortoise. Device test steps: `docs/spike-test-instructions.md`.
- LLM coach: copy `RunSteady/Secrets.example.plist` to `Secrets.plist` (gitignored) and add the key; without it a scripted coach is used.

## Workflow
- Keep overhead low. No GitHub issues needed.
- Track plan and subtasks in Markdown files (e.g. `TASKS.md` checklist), not in a tracker.
