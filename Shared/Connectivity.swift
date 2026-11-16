import Foundation
import os
import RunSteadyKit
import WatchConnectivity

/// Phone ↔ watch sync. Sessions travel watch → phone as queued user-info transfers
/// (delivered whenever the watch is back in range); the active plan travels
/// phone → watch as application context (latest value wins). The phone re-sends its latest
/// plan whenever the session (re)activates or the watch state changes, so one failed send
/// does not leave the watch on a stale schedule.
/// The watch publishes its `AppVersion` the same way (watch → phone application context), so the
/// phone always has the version of the watch app that last ran, even when it is out of range.
final class Connectivity: NSObject, WCSessionDelegate {
    static let shared = Connectivity()
    private let log = Logger(subsystem: "RunSteady", category: "Connectivity")
    private let lock = NSLock()
    private var latestPlan: ActivePlan?

    var onSession: (@MainActor (SessionRecord) -> Void)?
    var onPlan: (@MainActor (ActivePlan) -> Void)?
    /// Phone only: the watch app reported its version, or its install state changed.
    var onWatchState: (@MainActor (_ watch: AppVersion?, _ installed: Bool) -> Void)?

    /// This binary's own version, from its Info.plist.
    static let ownVersion = AppVersion(infoDictionary: Bundle.main.infoDictionary)
    private var lastWatchVersion: AppVersion?

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

    /// Remembers `plan` and pushes it now if possible; otherwise it goes out on the next activation.
    func send(_ plan: ActivePlan) {
        lock.withLock { latestPlan = plan }
        pushLatestPlan()
    }

    private func pushLatestPlan() {
        guard let plan = lock.withLock({ latestPlan }), WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            log.info("Plan send deferred: session not activated")
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else {
            log.info("Plan send deferred: paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled)")
            return
        }
        #endif
        do {
            try session.updateApplicationContext(["plan": try JSONEncoder().encode(plan)])
        } catch {
            log.error("Plan send failed: \(error.localizedDescription)")
        }
    }

    #if os(watchOS)
    private func publishVersion() {
        guard WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(Self.ownVersion) else { return }
        do {
            try WCSession.default.updateApplicationContext(["appVersion": data])
        } catch {
            log.error("Version publish failed: \(error.localizedDescription)")
        }
    }
    #endif

    #if os(iOS)
    /// Ask a reachable watch app for its version right now (e.g. "Try again"). Without a reply the
    /// last published version stays in place.
    func refreshWatchState() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let session = WCSession.default
        reportWatchState(session)
        guard session.isReachable else { return }
        session.sendMessage(["request": "appVersion"], replyHandler: { [weak self] reply in
            self?.handle(reply)
        }, errorHandler: { [weak self] error in
            self?.log.info("Version request failed: \(error.localizedDescription)")
        })
    }

    private func reportWatchState(_ session: WCSession) {
        let installed = session.isPaired && session.isWatchAppInstalled
        let watch = lock.withLock { lastWatchVersion }
        Task { @MainActor in self.onWatchState?(watch, installed) }
    }
    #endif

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { log.error("Activation failed: \(error.localizedDescription)") }
        handle(session.receivedApplicationContext)
        pushLatestPlan()
        #if os(watchOS)
        publishVersion()
        #else
        refreshWatchState()
        #endif
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? String == "appVersion", let data = try? JSONEncoder().encode(Self.ownVersion) {
            replyHandler(["appVersion": data])
        } else {
            replyHandler([:])
        }
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
        #if os(iOS)
        if let data = message["appVersion"] as? Data, let version = try? JSONDecoder().decode(AppVersion.self, from: data) {
            lock.withLock { lastWatchVersion = version }
            reportWatchState(.default)
        }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    /// Pairing or watch-app install changed (e.g. the watch app was just installed): resend.
    func sessionWatchStateDidChange(_ session: WCSession) {
        pushLatestPlan()
        reportWatchState(session)
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { refreshWatchState() }
    }
    #endif
}
