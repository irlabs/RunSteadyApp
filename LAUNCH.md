# Launch

What has to happen before Run Steady goes live for real, paying users. Development steps stay in [TASKS.md](TASKS.md); this file covers the high-level, business and organisational work. Items marked *(verify)* are assumptions to check, not facts.

## Order

1. Developer account and entity decision (O1, O2).
2. Coach proxy, API key out of the app (C1).
3. SwiftData schema versioning (E1).
4. External TestFlight for a full 8 weeks (B1). In parallel: onboarding, subscription, eval harness, legal docs, website.
5. App Store submission (S1–S6).

## Organisation

- [ ] O1. **Individual or company?** Decide before enrolling. Under the EU Digital Services Act, traders' address, phone and email are shown publicly on the EU App Store. A company (KvK) also keeps the seller name separate from a personal name.
- [ ] O2. **Apple Developer Program** (€99/year). Then the Paid Apps Agreement, bank and tax details in App Store Connect.
- [ ] O3. **App Store Small Business Program**: 15% commission instead of 30%. Apply once enrolled.
- [ ] O4. **Name check**: trademark search for "Run Steady", and whether the App Store name is free.
- [ ] O5. **Domain + support email** (also needed for the website and App Store URLs).

## Coach model and harness

- [ ] C1. **Proxy backend** hosted in the EU. The API key lives only there; `Secrets.plist` in the app bundle can be extracted, so it must be gone before any external TestFlight. Logs leave out message content. Monitoring and cost alerts.
- [ ] C2. **Eval harness first**, before switching models: a scenario set (sore knee, long gap, step-back, early step-up, off-topic question, prompt injection, Dutch input, rude user, very long input). Run it on every prompt or model change; grade some answers in code and some with a model. No fine-tuning.
- [ ] C3. **EU-hosted model.** Compare with C2: Claude via Bedrock or Vertex in an EU region (keeps current prompts; which models are available there *(verify)*), Mistral (EU company), others. Data processing agreement and zero data retention if offered.
- [ ] C4. **Prompt hardening**: keep the coach on topic, never diagnose, refer to a physio or doctor on pain. The schedule is already safe from the model by design (rules are deterministic).

## Abuse and cost safeguards

- [ ] A1. **App Attest** in the proxy: only real installs of the app can call it.
- [ ] A2. **Entitlement check** in the proxy: verify the StoreKit signed transaction (App Store Server API). App Attest alone doesn't prove the user pays. Together they make user accounts unnecessary.
- [ ] A3. **Limits**: monthly token cap per user (fair use), max message length, max turns per check-in, rate limit, global kill switch that falls back to the scripted coach.
- [ ] A4. **Measure cost** per check-in from real token logs before setting the price.

## Subscription

- [ ] P1. **StoreKit 2** subscription: yearly + monthly, free trial (introductory offer). Prefer this over token packs; they're confusing for users.
- [ ] P2. **Paywall** placement: the core (rules, watch app, scripted check-in) stays free; the AI coach is the paid part.
- [ ] P3. **Restore purchases**, handle expired, billing-retry and refunded states.
- [ ] P4. **Free tier check**: injury notes from free text come only from the AI. Make sure the tap-based knee answers alone keep the free plan careful (they already open injury notes).

## Onboarding

- [ ] N1. **Welcome flow** on the phone: what Steady is, then the permission prompts (Health, notifications) with a reason before each. The watch flow exists (F1).
- [ ] N2. **Health screening + disclaimer**: a short PAR-Q-style check ("heart condition, chest pain, dizziness? → see a doctor first"); "not medical advice".
- [ ] N3. **Starting level**: "Do you already run?" → place in a week. Reuse `ProgressionPlan.level(of:)`. Starts gently, even for experienced runners.
- [ ] N4. **Heart rate zones**: age or date of birth, optional manual max HR.
- [ ] N5. **Coach style slider** (cautious ↔ adventurous). Maps to rule parameters in RunSteadyKit (TDD), never to the LLM. Default cautious. "Adventurous" may offer occasional harder sessions or segments as a card (like `.advanceEarly`), never applied automatically; the safety net still applies. Design in an interview first.
- [ ] N6. **AI consent** step (see L3), skipped for users without a subscription.

## Legal and privacy

Not legal advice; get the medical-device question (L4) checked by someone who knows it.

- [ ] L1. **Privacy policy** and **terms of use** at a URL (subscriptions need terms; Apple's standard EULA may do *(verify)*).
- [ ] L2. **GDPR**: health data is a special category → explicit consent, data minimisation, data deletion (and export) for the coach data on the proxy side, processing agreement with the model provider.
- [ ] L3. **App Store 5.1.2**: clearly disclose and get explicit permission before sending personal data to a third-party AI (added in late 2025, I believe *(verify)*). **5.1.3**: HealthKit data never for ads, not stored in iCloud.
- [ ] L4. **EU medical device rules (MDR)**: position as fitness/wellness, not medical. Check the wording around pain and injury.
- [ ] L5. **EU AI Act transparency**: make clear the Steady chat is an AI.
- [ ] L6. **App privacy labels** in App Store Connect, matching what the proxy actually stores.

## Engineering before 1.0

- [ ] E1. **SwiftData `VersionedSchema` + migration plan** for phone and watch stores. After launch, a schema change without one can lose users' history.
- [ ] E2. **Crash reporting** via Xcode Organizer and MetricKit (no third-party SDK keeps the privacy labels simple).
- [ ] E3. **Fresh-install test** on device (R1 skipped a and b).
- [ ] E4. **Accessibility pass**: Dynamic Type, VoiceOver on phone and watch, contrast (see D1, D9 in TASKS).
- [ ] E5. **In-app feedback** (mail link with app version and, optionally, the diagnostics log).
- [ ] E6. **Demo mode reachable in the app** for App Review (launch arguments like `-demoSeed` aren't available to reviewers).

## Beta

- [ ] B1. **External TestFlight** with about 10–20 real beginners for the **full 8 weeks**: gap, structural-walking and early-step-up rules only show up over weeks. Needs Beta App Review and C1 first. Start as early as possible.
- [ ] B2. **Recruit testers** via the website waitlist (W2) and personal network.
- [ ] B3. **Review coach transcripts** from testers (with consent) and add bad cases to the C2 scenario set.

## Website and marketing

- [ ] W1. **One-page site**: what Run Steady is, screenshots, App Store link. Also hosts the privacy policy, terms and support page.
- [ ] W2. **Waitlist** form (privacy-friendly) for TestFlight testers and the launch.
- [ ] W3. **LinkedIn post**.
- [ ] W4. Short video of the watch timer and the check-in.
- [ ] W5. **Featuring nomination** in App Store Connect.
- [ ] W6. Physios, running clubs and beginner-running communities.

## App Store submission

- [ ] S1. App icon, name, subtitle, description, keywords.
- [ ] S2. Screenshots for iPhone **and** Apple Watch.
- [ ] S3. Age rating questionnaire.
- [ ] S4. Privacy labels (L6), privacy policy URL, support URL.
- [ ] S5. Subscription products, their review screenshot and description.
- [ ] S6. Review notes: how to reach the demo mode (E6), that the watch app works standalone, what the coach does.
