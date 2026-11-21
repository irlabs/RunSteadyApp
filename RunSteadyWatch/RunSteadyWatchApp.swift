import RunSteadyKit
import SwiftData
import SwiftUI

@main
struct RunSteadyWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.manager)
                .fontDesign(.rounded)
                .task { model.configure() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refreshPlan() }
                }
        }
        .modelContainer(model.container)
    }
}

/// Owns the store and decides which plan the start screen offers: the phone's plan, adjusted on
/// the watch after a break (F15), with heart rate zones from the phone or the watch itself (F9).
@MainActor
final class WatchModel: ObservableObject {
    let container = Store.container(inMemory: UserDefaults.standard.bool(forKey: "inMemory"))
    let manager = WorkoutManager()
    private let defaults = UserDefaults.standard
    private let infoKey = "planInfo"
    private var configured = false
    /// The stored plan a break adjustment started from, while that adjustment is on offer.
    private var adjustedBase: ActivePlan?

    /// Demo override: -demoStage <index> -demoSession <n>. Ignores what the phone sent.
    private var isDemo: Bool { defaults.object(forKey: "demoStage") != nil }

    func configure() {
        guard !configured else { return }
        configured = true
        let context = container.mainContext
        let stored = Store.storedPlan(in: context)
        if isDemo {
            let stage = min(max(0, defaults.integer(forKey: "demoStage")), ProgressionPlan.fiveK.count - 1)
            stored.plan = ActivePlan(schedule: ProgressionPlan.fiveK[stage].schedule, stageIndex: stage,
                                     sessionInStage: max(1, defaults.integer(forKey: "demoSession")))
        }

        manager.onFinish = { [unowned self] record in
            Diag.log("Run", "Finished \(record.shortID): \(record.duration / 60) min, \(record.roundsDone) rounds")
            Store.upsert(record, in: context)
            // A stepped-back run becomes the plan to build on until the phone sends a new one,
            // so the next run without the phone doesn't jump back up.
            if let base = self.adjustedBase, stored.plan == base {
                stored.plan = ActivePlan(schedule: record.schedule, stageIndex: record.stageIndex,
                                         sessionInStage: record.sessionInStage)
                try? context.save()
            }
            self.adjustedBase = nil
            // F10: a message wakes the phone app right away when it's reachable; the queued userInfo
            // arrives in every other case. The phone dedupes by id. Never resend based on the reply.
            Connectivity.shared.send(record, viaMessage: true)
        }
        Connectivity.shared.onPlan = { [weak self] plan, info in
            guard let self, !self.isDemo else { return }
            stored.plan = plan
            try? context.save()
            self.planInfo = info
            self.refreshPlan()
            self.refreshZones()
        }
        manager.onBackToStart = { [weak self] in self?.refreshPlan() }
        Connectivity.shared.activate()
        refreshPlan()
        refreshZones()
    }

    /// The stored plan, or a repeat / step-back when the last run (or the phone's last decision)
    /// is long enough ago. Runs on launch, on every return to the foreground and on a new plan.
    func refreshPlan() {
        guard configured else { return }
        let base = Store.storedPlan(in: container.mainContext).plan
        let info = isDemo ? nil : planInfo
        var since = GapRule.clockStart(lastSession: lastSessionDate, planDecidedAt: info?.decidedAt)
        // Demo: -demoGapDays <n> pretends the last run was n days ago.
        if defaults.object(forKey: "demoGapDays") != nil {
            since = Date().addingTimeInterval(-Double(defaults.integer(forKey: "demoGapDays")) * 86_400)
        }
        let adjustment = GapRule.adjust(base, decision: info?.decision, since: since, now: .now)
        if let adjustment {
            Diag.log("Plan", "Gap of \(adjustment.gapDays) days: \(base.title) → \(adjustment.plan.title)")
        }
        if manager.screen == .start { adjustedBase = adjustment == nil ? nil : base }
        manager.receive(adjustment?.plan ?? base, welcomeBack: adjustment)
    }

    /// Zones from the phone win; otherwise the watch's own date of birth (after its own Health grant).
    func refreshZones() {
        if let zones = planInfo?.zones {
            manager.zones = zones
        } else if defaults.integer(forKey: "demoAge") > 0 {
            manager.zones = HeartRateZones(age: defaults.integer(forKey: "demoAge"))
        } else if defaults.bool(forKey: "welcomeDone") {
            manager.zones = WatchHealth.zonesFromDateOfBirth()
        }
    }

    private var lastSessionDate: Date? {
        var descriptor = FetchDescriptor<StoredSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? container.mainContext.fetch(descriptor))?.first?.startedAt
    }

    private var planInfo: PlanInfo? {
        get { defaults.data(forKey: infoKey).flatMap { try? JSONDecoder().decode(PlanInfo.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: infoKey) }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: WatchModel
    @EnvironmentObject private var manager: WorkoutManager
    @AppStorage("welcomeDone") private var welcomeDone = false

    var body: some View {
        if !welcomeDone {
            WelcomeView {
                welcomeDone = true
                model.refreshZones()
            }
        } else {
            switch manager.screen {
            case .start: StartView()
            case .active: WorkoutView()
            case .summary: SummaryView()
            }
        }
    }
}
