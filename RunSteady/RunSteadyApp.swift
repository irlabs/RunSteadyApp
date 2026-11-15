import RunSteadyKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct RunSteadyApp: App {
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

    init() {
        isDemo = UserDefaults.standard.bool(forKey: "demoSeed")
        container = Store.container(inMemory: isDemo)
        coach = ClaudeCoach.fromBundledSecrets() ?? ScriptedCoach()
        if isDemo { DemoData.seed(into: container.mainContext) }
        Store.resolveStaleNotes(in: container.mainContext)

        Connectivity.shared.onSession = { [weak self] record in self?.receive(record) }
        Connectivity.shared.activate()
        if !isDemo {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    var storedPlan: StoredPlan { Store.storedPlan(in: container.mainContext) }

    /// Make `plan` the active one and push it to the watch.
    func apply(_ plan: ActivePlan) {
        let stored = storedPlan
        stored.plan = plan
        stored.dismissedSuggestion = nil
        try? container.mainContext.save()
        Connectivity.shared.send(plan)
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
        try? container.mainContext.save()
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

    /// A session arrived from the watch (it is back in range): store it and prompt the check-in.
    private func receive(_ record: SessionRecord) {
        Store.upsert(record, in: container.mainContext)
        let content = UNMutableNotificationContent()
        content.title = "Welcome back!"
        content.body = "How was your run? Three quick questions from Steady."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil))
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
