import RunSteadyKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct RunSteadyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .fontDesign(.rounded)
                .tint(.brand)
        }
        .modelContainer(model.container)
    }
}

@MainActor
final class AppModel: ObservableObject {
    let container: ModelContainer
    let coach: Coach
    let isDemo: Bool
    /// Whether the watch runs the same build as this phone app. `nil` in demo mode.
    @Published private(set) var watchStatus: WatchAppStatus?
    /// G9: the plan the watch reports it holds, and when this app last sent its own.
    @Published private(set) var watchPlan: PlanReceipt?
    @Published private(set) var planSentAt: Date?

    init() {
        isDemo = UserDefaults.standard.bool(forKey: "demoSeed")
        container = Store.container(inMemory: isDemo)
        coach = ClaudeCoach.fromBundledSecrets() ?? ScriptedCoach()
        if isDemo { DemoData.seed(into: container.mainContext) }
        Store.resolveStaleNotes(in: container.mainContext)
        Diag.log("App", "App model ready\(isDemo ? " (demo)" : "")")

        Connectivity.shared.onSession = { [weak self] record in self?.receive(record) }
        if !isDemo {
            Connectivity.shared.onWatchState = { [weak self] watch, installed in
                self?.watchStatus = .evaluate(phone: Connectivity.ownVersion, watch: watch, watchAppInstalled: installed)
            }
            Connectivity.shared.watchPlans.handler = { [weak self] receipt in self?.watchPlan = receipt }
        } else {
            // Demo: the watch holds the seeded plan.
            let stored = storedPlan
            watchPlan = PlanReceipt(plan: stored.plan, decidedAt: stored.updatedAt, reportedAt: .now)
            // -demoOpenRun YES: as if the check-in notification for the latest run was tapped (G4).
            if UserDefaults.standard.bool(forKey: "demoOpenRun"),
               let latest = try? container.mainContext.fetch(
                   FetchDescriptor<StoredSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])).first {
                RunRouter.shared.open(latest.id)
            }
        }
        Connectivity.shared.activate()
        // Push the current plan on every launch; it goes out once the session is active.
        pushPlan()
        if !isDemo { Task { await askPermissions() } }
    }

    /// F1: Health first (workouts, date of birth, effort score), then notifications. Each only asks
    /// once; later launches return at once. The phone's grant doesn't cover the watch, which asks itself.
    private func askPermissions() async {
        await HealthObserver.shared.requestAuthorization() // also registers the observer again
        refreshZones()
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        Diag.log("Notify", "Authorization granted: \(granted)")
        await EffortWriter.shared.writePending()
    }

    func recheckWatch() { Connectivity.shared.refreshWatchState() }

    var storedPlan: StoredPlan { Store.storedPlan(in: container.mainContext) }

    // MARK: Heart rate zones (F9)

    private let zonesKey = "heartRateZones"

    /// Worked out here from the phone's date of birth and sent to the watch with the plan.
    var zones: HeartRateZones? {
        UserDefaults.standard.data(forKey: zonesKey).flatMap { try? JSONDecoder().decode(HeartRateZones.self, from: $0) }
    }

    private func refreshZones() {
        guard let birth = HealthObserver.shared.dateOfBirth(), let zones = HeartRateZones(birth: birth) else { return }
        guard zones != self.zones else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(zones), forKey: zonesKey)
        Diag.log("Zones", "Max heart rate \(zones.maxHeartRate), zones from \(zones.lowerBounds.map(String.init).joined(separator: "/")) bpm")
        pushPlan()
    }

    // MARK: Plan

    /// Sends the active plan with what the watch needs to handle a break on its own (F15) and the zones.
    /// - Parameter viaMessage: also as a live message (the resend button, G9).
    func pushPlan(viaMessage: Bool = false) {
        let stored = storedPlan
        guard !isDemo else {
            // Demo: the watch confirms a moment later.
            let receipt = PlanReceipt(plan: stored.plan, decidedAt: stored.updatedAt, reportedAt: .now)
            planSentAt = .now
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                watchPlan = receipt
            }
            return
        }
        let info = PlanInfo(decidedAt: stored.updatedAt, decision: decision(for: stored.plan), zones: zones)
        planSentAt = .now
        Connectivity.shared.send(stored.plan, info: info, viaMessage: viaMessage)
    }

    /// G9: the watch reported an older plan.
    func resendPlan() {
        Diag.log("Plan", "Resend: watch holds \(watchPlan?.plan.title ?? "?"), phone \(storedPlan.plan.title)")
        pushPlan(viaMessage: true)
    }

    /// Why the rules chose `plan`, when it is today's suggestion; nil lets the watch infer it.
    private func decision(for plan: ActivePlan) -> Decision? {
        guard !plan.isManual else { return nil }
        let context = container.mainContext
        let sessions = (try? context.fetch(FetchDescriptor<StoredSession>())) ?? []
        let injury = Store.openNotes(in: context).contains { $0.kind == .injury }
        let suggestion = sessions.suggestion(structuralDeclinedAt: storedPlan.structuralDeclinedAt, hasOpenInjury: injury)
        return ActivePlan(suggestion) == plan ? suggestion.decision : nil
    }

    /// Make `plan` the active one and push it to the watch.
    func apply(_ plan: ActivePlan) {
        let stored = storedPlan
        stored.plan = plan
        // F14: an ignored suggestion stays ignored while the runner edits their own schedule.
        if !plan.isManual { stored.dismissedSuggestion = nil }
        try? container.mainContext.save()
        pushPlan()
    }

    /// The suggestion still waits for "Use this" / "Keep mine": it differs from the active plan and
    /// wasn't declined. The same test as the offer on Today.
    func needsDecision(_ suggestion: Suggestion) -> Bool {
        ActivePlan(suggestion) != storedPlan.plan && storedPlan.dismissedSuggestion != suggestion.key
    }

    /// "Use this" / "Try it".
    func accept(_ suggestion: Suggestion) {
        apply(ActivePlan(suggestion))
        settleChoice()
    }

    /// "Keep mine" / "Stay steady" / "Ignore". With a schedule of their own, the runner keeps it
    /// even when the offer has a fallback.
    func decline(_ suggestion: Suggestion) {
        keepCurrent(insteadOf: suggestion, staying: storedPlan.plan.isManual)
        settleChoice()
    }

    /// The runner chose their next session (on a card, in the check-in or in the editor): no check-in
    /// waits for that choice any more (G11).
    func settleChoice() {
        let open = (try? container.mainContext.fetch(
            FetchDescriptor<StoredSession>(predicate: #Predicate { $0.openChoice != nil }))) ?? []
        guard !open.isEmpty else { return }
        open.forEach { $0.openChoice = nil }
        try? container.mainContext.save()
    }

    /// - Parameter staying: keep the active plan exactly as it is (e.g. "Keep it easier" after a manual run),
    ///   rather than falling back to the normal plan for an offer.
    func keepCurrent(insteadOf suggestion: Suggestion, staying: Bool = false) {
        // An offer with a fallback: carry on with the normal plan. Declining "Settle in" also restarts its window.
        if !staying, let alternative = suggestion.alternative {
            if suggestion.decision == .stepBackStructural { storedPlan.structuralDeclinedAt = .now }
            if alternative != storedPlan.plan { apply(alternative) }
        }
        storedPlan.dismissedSuggestion = suggestion.key
        // A decision too: the watch's gap clock starts again from here.
        storedPlan.updatedAt = .now
        try? container.mainContext.save()
        pushPlan()
    }

    /// On the automatic plan, moving on with identical intervals needs no decision. For an offer with a
    /// fallback, the fallback is applied quietly, so ignoring the card means "Keep mine" / "Stay steady".
    /// - Returns: whether the suggestion still needs the runner's decision.
    @discardableResult
    func followSilently(_ suggestion: Suggestion) -> Bool {
        let current = storedPlan.plan
        let next = ActivePlan(suggestion)
        guard next != current else { return false }
        guard !current.isManual else { return true }
        if next.schedule == current.schedule {
            apply(next)
            return false
        }
        if let fallback = suggestion.alternative, fallback != current, fallback.schedule == current.schedule {
            apply(fallback)
        }
        return true
    }

    /// A session arrived from the watch: store it and prompt the check-in, once. It usually arrives
    /// twice (message, then userInfo a moment later); the second copy is dropped here (F10).
    private func receive(_ record: SessionRecord) {
        guard !record.isTestRun else { return } // Diagnostics test runs never land in History.
        let id = record.id
        let known = (try? container.mainContext.fetchCount(FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == id }))) ?? 0
        guard known == 0 else {
            Diag.log("Run", "Session \(record.shortID) already stored, no second check-in prompt")
            return
        }
        Store.upsert(record, in: container.mainContext)
        let content = UNMutableNotificationContent()
        content.title = "Welcome back!"
        content.body = "How was your run? Three quick questions from Steady."
        content.sound = .default
        // G4: tapping it opens this run's summary.
        content.userInfo = [RunRouter.sessionKey: record.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil)) { error in
            Diag.log("Notify", "Check-in prompt for \(record.shortID) (app \(Diag.phase)): \(error.map { "failed: \($0.localizedDescription)" } ?? "ok")")
        }
    }
}

/// G4: which run's summary to show full screen, after the check-in notification was tapped.
@MainActor
final class RunRouter: ObservableObject {
    static let shared = RunRouter()
    static let sessionKey = "sessionID"

    struct Request: Identifiable, Equatable { let id: UUID }
    @Published var request: Request?

    func open(_ sessionID: UUID) {
        Diag.log("Notify", "Open run \(sessionID.short)")
        request = Request(id: sessionID)
    }

    /// The session id a check-in notification carries. Older ones only had it as their identifier.
    nonisolated static func sessionID(in request: UNNotificationRequest) -> UUID? {
        if let id = (request.content.userInfo[sessionKey] as? String).flatMap(UUID.init(uuidString:)) { return id }
        return UUID(uuidString: request.identifier)
    }
}

struct RootView: View {
    @ObservedObject private var router = RunRouter.shared

    var body: some View {
        tabs
            .fullScreenCover(item: $router.request) { RunSummaryCover(sessionID: $0.id) }
    }

    private var tabs: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "figure.run") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "flag.checkered") }
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar.fill") }
        }
    }
}
