import HealthKit
import RunSteadyKit
import UIKit
import UserNotifications

/// Starts what must exist even when iOS launches the app in the background (a WatchConnectivity
/// message or a HealthKit wake), before any SwiftUI scene, and logs the app lifecycle.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Diag.phase = application.applicationState.label
        let reasons = launchOptions?.keys.map(\.rawValue).sorted().joined(separator: ",") ?? "none"
        Diag.log("App", "Launch \(Connectivity.ownVersion.label): state=\(Diag.phase) options=\(reasons)")

        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Connectivity.shared.onTestRun = { record, path, sentAt in
            TestRunReceiver.shared.receive(record, path: path, sentAt: sentAt)
        }
        Connectivity.shared.activate()
        HealthObserver.shared.start()
        // F11: effort scores waiting for their watch workout to reach Health.
        Task { await EffortWriter.shared.writePending() }
        observeLifecycle()
        return true
    }

    private func observeLifecycle() {
        let events: [(Notification.Name, String)] = [
            (UIApplication.didBecomeActiveNotification, "foreground"),
            (UIApplication.willResignActiveNotification, "inactive"),
            (UIApplication.didEnterBackgroundNotification, "background"),
            (UIApplication.willTerminateNotification, "terminating"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "locked"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "unlocked"),
        ]
        for (name, label) in events {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                if label != "locked" && label != "unlocked" { Diag.phase = label }
                Diag.log("App", "→ \(label)")
            }
        }
    }
}

extension UIApplication.State {
    var label: String {
        switch self {
        case .active: "foreground"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}

/// Shows banners while the app is open too (by default iOS hides them in the foreground).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Diag.log("Notify", "Shown in foreground: \(notification.request.content.title)")
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Diag.log("Notify", "Tapped: \(response.notification.request.content.title)")
        completionHandler()
    }

    /// Posts right away and logs whether iOS accepted it.
    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            Diag.log("Notify", "Post \"\(title)\" (app \(Diag.phase)): \(error.map { "failed: \($0.localizedDescription)" } ?? "ok")")
        }
    }

    static func logSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            Diag.log("Notify", "Settings: authorization=\(s.authorizationStatus.rawValue) alert=\(s.alertSetting.rawValue) "
                     + "lockScreen=\(s.lockScreenSetting.rawValue) (2 = granted/enabled)")
        }
    }
}

/// Phone side of the F10 fake run: never stored (no History, check-in or suggestion), only logged
/// and announced, so the delivery path and delay can be read off the notification.
@MainActor
final class TestRunReceiver {
    static let shared = TestRunReceiver()
    private let key = "spikeSeenTestRuns"

    func receive(_ record: SessionRecord, path: String, sentAt: Date?) {
        var seen = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        let delay = Diag.delay(since: sentAt)
        if let first = seen[record.id.uuidString] {
            Diag.log("Spike", "Test run \(record.shortID) again via \(path) after \(delay) (first via \(first))")
            return
        }
        seen[record.id.uuidString] = path
        UserDefaults.standard.set(seen, forKey: key)
        Diag.log("Spike", "Test run \(record.shortID) FIRST via \(path) after \(delay), app \(Diag.phase)")
        NotificationDelegate.post(id: "test-run-\(record.id.uuidString)", title: "Test run received via \(path)",
                                  body: "\(delay) after the watch sent it · app was \(Diag.phase)")
        Connectivity.shared.sendTestAck(record.id, kind: "received")
    }
}

/// F1 and F10b on the phone: asks for Health access and watches for new workouts with
/// HealthKit background delivery. A new real workout retries pending effort scores (F11);
/// test workouts (metadata `RunSteadyTest`) are only announced.
final class HealthObserver: @unchecked Sendable {
    static let shared = HealthObserver()
    static let testKey = "RunSteadyTest"
    private let store = HKHealthStore()
    private let anchorKey = "spikeWorkoutAnchor"
    private let lock = NSLock()
    private var observing = false
    /// One anchored query at a time (the spike saw two wakes handle the same workout twice).
    private var fetching = false
    private var fetchAgain = false

    var shareTypes: Set<HKSampleType> { [HKObjectType.workoutType(), HKQuantityType(.workoutEffortScore)] }
    var readTypes: Set<HKObjectType> { [HKObjectType.workoutType(), HKCharacteristicType(.dateOfBirth)] }

    /// Registers the observer. Must run on every launch, background launches included. Before Health
    /// access is granted the query fails and stops, so `requestAuthorization()` registers it again.
    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let first = lock.withLock { () -> Bool in
            defer { observing = true }
            return !observing
        }
        guard first else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] query, completion, error in
            if let error {
                Diag.log("HealthKit", "Observer stopped: \(error.localizedDescription)")
                self?.store.stop(query)
                self?.lock.withLock { self?.observing = false }
                completion()
                return
            }
            Diag.log("HealthKit", "Observer woke, app \(Diag.phase)")
            self?.fetchNewWorkouts(completion)
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { ok, error in
            Diag.log("HealthKit", "Background delivery: \(ok ? "on" : "off")\(error.map { " (\($0.localizedDescription))" } ?? "")")
        }
    }

    func logStatus() {
        store.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { status, error in
            Diag.log("HealthKit", "Request status (phone): \(status.label)\(error.map { " – \($0.localizedDescription)" } ?? "")")
        }
        for type in shareTypes {
            Diag.log("HealthKit", "Share \(type.identifier): \(store.authorizationStatus(for: type).label)")
        }
    }

    func requestAuthorization() async {
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            Diag.log("HealthKit", "Request finished (phone)")
            start()
        } catch {
            Diag.log("HealthKit", "Request failed (phone): \(error.localizedDescription)")
        }
        logStatus()
        readDateOfBirth()
    }

    /// nil without a grant or without a birth year in Health.
    func dateOfBirth() -> DateComponents? {
        guard let c = try? store.dateOfBirthComponents(), c.year != nil else { return nil }
        return c
    }

    func readDateOfBirth() {
        do {
            let c = try store.dateOfBirthComponents()
            Diag.log("HealthKit", "Date of birth (phone): \(c.year == nil ? "not set" : "present")")
        } catch {
            Diag.log("HealthKit", "Date of birth (phone) failed: \(error.localizedDescription)")
        }
    }

    private func fetchNewWorkouts(_ completion: @escaping () -> Void) {
        let busy = lock.withLock { () -> Bool in
            if fetching { fetchAgain = true; return true }
            fetching = true
            return false
        }
        // A query is running already; it runs once more when done, so this wake is covered.
        if busy { completion(); return }
        runAnchoredQuery {
            completion()
            Task { await EffortWriter.shared.writePending() }
        }
    }

    private func runAnchoredQuery(_ done: @escaping () -> Void) {
        let anchor = UserDefaults.standard.data(forKey: anchorKey)
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        // First run: only the last two days, not the whole Health history.
        let predicate = anchor == nil ? HKQuery.predicateForSamples(withStart: .now.addingTimeInterval(-2 * 86_400), end: nil) : nil
        let query = HKAnchoredObjectQuery(type: .workoutType(), predicate: predicate, anchor: anchor,
                                          limit: HKObjectQueryNoLimit) { [weak self] _, added, deleted, newAnchor, error in
            guard let self else { return done() }
            defer {
                let again = self.lock.withLock { () -> Bool in
                    let again = self.fetchAgain
                    self.fetchAgain = false
                    if !again { self.fetching = false }
                    return again
                }
                if again { self.runAnchoredQuery(done) } else { done() }
            }
            if let error {
                Diag.log("HealthKit", "Workout query failed: \(error.localizedDescription)")
                return
            }
            if let newAnchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: self.anchorKey)
            }
            for case let workout as HKWorkout in added ?? [] { self.seen(workout) }
            if let deleted, !deleted.isEmpty {
                Diag.log("HealthKit", "\(deleted.count) workout(s) deleted: \(deleted.map(\.uuid.short).joined(separator: ","))")
            }
        }
        store.execute(query)
    }

    private func seen(_ workout: HKWorkout) {
        let source = workout.sourceRevision.source.name
        let minutes = Int(workout.duration / 60)
        let late = Diag.delay(since: workout.endDate)
        guard let runID = workout.metadata?[Self.testKey] as? String else {
            Diag.log("HealthKit", "Workout \(workout.uuid.short) from \(source), \(minutes) min, ended \(late) ago")
            return
        }
        Diag.log("HealthKit", "TEST workout \(workout.uuid.short) from \(source), \(late) after it ended, app \(Diag.phase)")
        NotificationDelegate.post(id: "test-workout-\(workout.uuid.uuidString)", title: "Test workout seen via HealthKit",
                                  body: "\(late) after it ended · app was \(Diag.phase)")
        if let id = UUID(uuidString: runID) { Connectivity.shared.sendTestAck(id, kind: "healthKit") }
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
