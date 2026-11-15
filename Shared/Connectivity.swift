import Foundation
import RunSteadyKit
import WatchConnectivity

/// Phone ↔ watch sync. Sessions travel watch → phone as queued user-info transfers
/// (delivered whenever the watch is back in range); the active plan travels
/// phone → watch as application context (latest value wins).
final class Connectivity: NSObject, WCSessionDelegate {
    static let shared = Connectivity()

    var onSession: (@MainActor (SessionRecord) -> Void)?
    var onPlan: (@MainActor (ActivePlan) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ record: SessionRecord) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(record) else { return }
        WCSession.default.transferUserInfo(["session": data])
    }

    func send(_ plan: ActivePlan) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(plan) else { return }
        try? WCSession.default.updateApplicationContext(["plan": data])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        handle(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    private func handle(_ message: [String: Any]) {
        if let data = message["session"] as? Data, let record = try? JSONDecoder().decode(SessionRecord.self, from: data) {
            Task { @MainActor in self.onSession?(record) }
        }
        if let data = message["plan"] as? Data, let plan = try? JSONDecoder().decode(ActivePlan.self, from: data) {
            Task { @MainActor in self.onPlan?(plan) }
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
