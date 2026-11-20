import CoreLocation
import HealthKit
import RunSteadyKit
import WatchKit

/// Logs the watch app lifecycle (Phase 0 spike).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Diag.phase = WKApplication.shared().applicationState.label
        Diag.log("App", "Launch \(Connectivity.ownVersion.label) on watchOS \(WKInterfaceDevice.current().systemVersion): state=\(Diag.phase)")
        Connectivity.shared.onTestAck = { id, kind, path in
            WatchSpike.shared.receiveAck(id, kind: kind, path: path)
        }
        Connectivity.shared.activate()
        // Scripted checks (paired Simulators): -fakeRunOnLaunch YES sends a fake run a few seconds after launch.
        if UserDefaults.standard.bool(forKey: "fakeRunOnLaunch") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                await WatchSpike.shared.fakeRun()
            }
        }
    }

    func applicationDidBecomeActive() {
        Diag.phase = "foreground"
        Diag.log("App", "→ foreground")
        WatchSpike.shared.deleteOverdueTestWorkouts()
    }

    func applicationWillResignActive() { Diag.log("App", "→ inactive") }

    func applicationDidEnterBackground() {
        Diag.phase = "background"
        Diag.log("App", "→ background")
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            Diag.log("App", "Background task: \(type(of: task))")
            task.setTaskCompletedWithSnapshot(false)
        }
    }
}

extension WKApplicationState {
    var label: String {
        switch self {
        case .active: "foreground"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}

/// Watch side of the device checks: F1 permission status, F10 fake run and its test workout.
@MainActor
final class WatchSpike: ObservableObject {
    static let shared = WatchSpike()
    static let testKey = "RunSteadyTest"
    /// How long a test workout may stay in Health when the phone never confirms seeing it.
    static let workoutTimeout: TimeInterval = 10 * 60

    private let store = HKHealthStore()
    private let pendingKey = "spikePendingTestWorkouts" // runID → [workoutUUID, savedAt]
    private var acked: Set<String> = []

    /// Types not requested by the run itself yet (needed by F9 and F11), so their status shows
    /// whether a grant on the phone carries over to the watch.
    private var shareTypes: Set<HKSampleType> {
        if #available(watchOS 11.0, *) { return [HKQuantityType(.workoutEffortScore)] }
        return []
    }
    private let readTypes: Set<HKObjectType> = [HKCharacteristicType(.dateOfBirth)]

    // MARK: F1 permissions

    func checkPermissions() {
        if #unavailable(watchOS 11.0) {
            Diag.log("HealthKit", "Effort score type needs watchOS 11 (this watch: \(WKInterfaceDevice.current().systemVersion)); checking date of birth only")
        }
        store.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { status, error in
            Diag.log("HealthKit", "Request status (watch) for birth date\(self.shareTypesLabel): \(status.label)"
                     + (error.map { " – \($0.localizedDescription)" } ?? ""))
        }
        let runShare: [HKObjectType] = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()] + Array(shareTypes)
        for type in runShare {
            Diag.log("HealthKit", "Share \(type.identifier): \(store.authorizationStatus(for: type).label)")
        }
        Diag.log("Location", "Authorization: \(CLLocationManager().authorizationStatus.label)")
    }

    private nonisolated var shareTypesLabel: String {
        if #available(watchOS 11.0, *) { return " + effort score" }
        return ""
    }

    /// Only after the phone test: asking here would hide whether the phone's grant covers the watch.
    func requestHere() async {
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            Diag.log("HealthKit", "Request finished (watch)")
        } catch {
            Diag.log("HealthKit", "Request failed (watch): \(error.localizedDescription)")
        }
        checkPermissions()
    }

    func readDateOfBirth() {
        do {
            let c = try store.dateOfBirthComponents()
            Diag.log("HealthKit", "Date of birth (watch): \(c.year == nil ? "not set" : "present")")
        } catch {
            Diag.log("HealthKit", "Date of birth (watch) failed: \(error.localizedDescription)")
        }
    }

    // MARK: F10 fake run

    /// A short synthetic run, sent by message (if reachable) and userInfo, plus a 1-minute test
    /// workout in Health for the phone's HealthKit observer.
    func fakeRun() async {
        let end = Date()
        let start = end.addingTimeInterval(-60)
        let segments = [
            SegmentRecord(kind: .warmUp, round: 0, target: 20, actual: 20),
            SegmentRecord(kind: .run, round: 1, target: 20, actual: 20),
            SegmentRecord(kind: .walk, round: 1, target: 10, actual: 10),
            SegmentRecord(kind: .coolDown, round: 0, target: 10, actual: 10),
        ]
        let record = SessionRecord(startedAt: start, schedule: Schedule(name: "Test", warmUp: 20, run: 20, walk: 10, rounds: 1, coolDown: 10),
                                   stageIndex: nil, sessionInStage: nil, segments: segments, distanceMeters: 150,
                                   averageHeartRate: 110, isTest: true)
        Diag.log("Spike", "Fake run \(record.shortID): sending")
        Connectivity.shared.send(record, viaMessage: true)
        await saveTestWorkout(runID: record.id, start: start, end: end)
    }

    private func saveTestWorkout(runID: UUID, start: Date, end: Date) async {
        #if targetEnvironment(simulator)
        guard UserDefaults.standard.bool(forKey: "useHealthKit") else {
            Diag.log("Spike", "Test workout skipped in the Simulator (launch with -useHealthKit YES)")
            return
        }
        #endif
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            let config = HKWorkoutConfiguration()
            config.activityType = .running
            config.locationType = .outdoor
            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([Self.testKey: runID.uuidString])
            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                Diag.log("Spike", "Test workout: finishWorkout returned nothing")
                return
            }
            var pending = self.pending
            pending[runID.uuidString] = [workout.uuid.uuidString, String(Date().timeIntervalSince1970)]
            self.pending = pending
            Diag.log("Spike", "Test workout \(workout.uuid.short) saved for run \(runID.short)")
            Task {
                try? await Task.sleep(for: .seconds(Self.workoutTimeout))
                self.deleteTestWorkout(for: runID, reason: "timeout")
            }
        } catch {
            Diag.log("Spike", "Test workout failed: \(error.localizedDescription)")
        }
    }

    func receiveAck(_ runID: UUID, kind: String, path: String) {
        let key = "\(runID)-\(kind)"
        guard !acked.contains(key) else {
            Diag.log("Spike", "Ack \(kind) for \(runID.short) again via \(path)")
            return
        }
        acked.insert(key)
        Diag.log("Spike", "Phone confirmed \(kind == "healthKit" ? "seeing the test workout" : "receiving the run") "
                 + "\(runID.short) via \(path)")
        // Only delete once the phone saw the workout through HealthKit; deleting earlier would hide it.
        if kind == "healthKit" { deleteTestWorkout(for: runID, reason: "phone saw it") }
    }

    func deleteOverdueTestWorkouts() {
        let now = Date().timeIntervalSince1970
        for (runID, value) in pending {
            if let saved = value.last.flatMap(Double.init), now - saved > Self.workoutTimeout, let id = UUID(uuidString: runID) {
                deleteTestWorkout(for: id, reason: "overdue")
            }
        }
    }

    private func deleteTestWorkout(for runID: UUID, reason: String) {
        guard let workoutID = pending[runID.uuidString]?.first.flatMap(UUID.init(uuidString:)) else { return }
        var pending = self.pending
        pending.removeValue(forKey: runID.uuidString)
        self.pending = pending
        store.deleteObjects(of: .workoutType(), predicate: HKQuery.predicateForObject(with: workoutID)) { ok, count, error in
            Diag.log("Spike", "Delete test workout \(workoutID.short) (\(reason)): "
                     + (ok ? "\(count) deleted" : "failed: \(error?.localizedDescription ?? "unknown")"))
        }
    }

    /// Cleans up every test workout this app saved, in case one was left behind.
    func deleteAllTestWorkouts() {
        pending = [:]
        store.deleteObjects(of: .workoutType(), predicate: HKQuery.predicateForObjects(withMetadataKey: Self.testKey)) { ok, count, error in
            Diag.log("Spike", "Delete all test workouts: " + (ok ? "\(count) deleted" : "failed: \(error?.localizedDescription ?? "unknown")"))
        }
    }

    private var pending: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }
}

extension HKAuthorizationRequestStatus {
    var label: String {
        switch self {
        case .shouldRequest: "should request"
        case .unnecessary: "unnecessary"
        case .unknown: "unknown"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}

extension HKAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: "not determined"
        case .sharingDenied: "denied"
        case .sharingAuthorized: "authorized"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}

extension CLAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: "not determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "when in use"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}
