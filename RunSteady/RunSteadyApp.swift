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

    func keepCurrent(insteadOf suggestion: Suggestion) {
        // An offer with a fallback (structural step-back): carry on with the normal plan and restart its window.
        if let alternative = suggestion.alternative {
            storedPlan.structuralDeclinedAt = .now
            apply(alternative)
            return
        }
        storedPlan.dismissedSuggestion = suggestion.key
        try? container.mainContext.save()
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
