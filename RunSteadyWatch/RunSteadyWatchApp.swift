import RunSteadyKit
import SwiftData
import SwiftUI

@main
struct RunSteadyWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var manager = WorkoutManager()
    private let container = Store.container(inMemory: UserDefaults.standard.bool(forKey: "inMemory"))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(manager)
                .fontDesign(.rounded)
                .task { configure() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func configure() {
        let context = container.mainContext
        let stored = Store.storedPlan(in: context)

        // Demo override: -demoStage <index> -demoSession <n>
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "demoStage") != nil {
            let stage = min(max(0, defaults.integer(forKey: "demoStage")), ProgressionPlan.fiveK.count - 1)
            stored.plan = ActivePlan(schedule: ProgressionPlan.fiveK[stage].schedule, stageIndex: stage,
                                     sessionInStage: max(1, defaults.integer(forKey: "demoSession")))
        }
        manager.plan = stored.plan

        manager.onFinish = { record in
            Diag.log("Run", "Finished \(record.shortID): \(record.duration / 60) min, \(record.roundsDone) rounds")
            Store.upsert(record, in: context)
            Connectivity.shared.send(record)
        }
        Connectivity.shared.onPlan = { plan in
            stored.plan = plan
            try? context.save()
            manager.receive(plan)
        }
        Connectivity.shared.activate()
    }
}

struct RootView: View {
    @EnvironmentObject private var manager: WorkoutManager

    var body: some View {
        switch manager.screen {
        case .start: StartView()
        case .active: WorkoutView()
        case .summary: SummaryView()
        }
    }
}
