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
    func pushPlan() {
        guard !isDemo else { return }
        let stored = storedPlan
        let info = PlanInfo(decidedAt: stored.updatedAt, decision: decision(for: stored.plan), zones: zones)
        Connectivity.shared.send(stored.plan, info: info)
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
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil)) { error in
            Diag.log("Notify", "Check-in prompt for \(record.shortID) (app \(Diag.phase)): \(error.map { "failed: \($0.localizedDescription)" } ?? "ok")")
        }
    }
}

struct RootView: View {
    var body: some View {
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
