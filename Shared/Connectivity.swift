import Foundation
import RunSteadyKit
import WatchConnectivity

/// Phone ↔ watch sync. Sessions travel watch → phone twice: as a live message when the phone is
/// reachable (wakes the phone app even after a force-quit) and as a queued user-info transfer
/// (delivered whenever the watch is back in range). The phone dedupes by id. The active plan
/// (plus `PlanInfo`: gap clock, decision, heart rate zones) travels phone → watch as application
/// context (latest value wins). The phone re-sends its latest
/// plan whenever the session (re)activates or the watch state changes, so one failed send
/// does not leave the watch on a stale schedule.
/// The watch publishes its `AppVersion` the same way (watch → phone application context), so the
/// phone always has the version of the watch app that last ran, even when it is out of range.
///
/// Every event is written to the diagnostics log (`Diag`), with the delivery path and, for
/// sessions, the delay since the watch sent it.
final class Connectivity: NSObject, WCSessionDelegate {
    static let shared = Connectivity()
    private let lock = NSLock()
    private var latestPlan: ActivePlan?
    private var latestInfo: PlanInfo?
    private var activationRequested = false

    /// Real sessions that arrived before anyone listened (e.g. a background launch before the
    /// UI exists). Handed over as soon as `onSession` is set. Main actor only.
    private var pendingSessions: [SessionRecord] = []
    var onSession: (@MainActor (SessionRecord) -> Void)? {
        didSet { Task { @MainActor in self.flushPendingSessions() } }
    }
    var onPlan: (@MainActor (ActivePlan, PlanInfo?) -> Void)?
    /// Phone only: the watch app reported its version, or its install state changed.
    var onWatchState: (@MainActor (_ watch: AppVersion?, _ installed: Bool) -> Void)?
    /// A diagnostics test run (`SessionRecord.isTest`), with the path it came by and when it was sent.
    var onTestRun: (@MainActor (_ record: SessionRecord, _ path: String, _ sentAt: Date?) -> Void)?
    /// Watch only: the phone acknowledged a test run. `kind` is "received" (WatchConnectivity) or "healthKit".
    var onTestAck: (@MainActor (_ runID: UUID, _ kind: String, _ path: String) -> Void)?

    /// This binary's own version, from its Info.plist.
    static let ownVersion = AppVersion(infoDictionary: Bundle.main.infoDictionary)
    private var lastWatchVersion: AppVersion?

    /// Safe to call more than once (app delegate and app model both do).
    func activate() {
        guard WCSession.isSupported() else {
            Diag.log("WC", "WatchConnectivity not supported")
            return
        }
        let first = lock.withLock { () -> Bool in
            defer { activationRequested = true }
            return !activationRequested
        }
        guard first else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        Diag.log("WC", "Activating")
    }

    /// Sends a finished session as a queued user-info transfer. With `viaMessage`, it also goes out as
    /// a live message when the counterpart is reachable (that path wakes the iPhone app in the background).
    func send(_ record: SessionRecord, viaMessage: Bool = false) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              let data = try? JSONEncoder().encode(record) else {
            Diag.log("WC", "Session \(record.shortID) not sent: session not activated")
            return
        }
        let payload: [String: Any] = ["session": data, "sentAt": Date().timeIntervalSince1970]
        if viaMessage {
            if session.isReachable {
                session.sendMessage(payload, replyHandler: { reply in
                    Diag.log("WC", "Session \(record.shortID): message reply \(reply.keys.sorted())")
                    self.handle(reply, path: "message reply")
                }, errorHandler: { error in
                    Diag.log("WC", "Session \(record.shortID): message failed: \(error.localizedDescription)")
                })
                Diag.log("WC", "Session \(record.shortID) sent as message")
            } else {
                Diag.log("WC", "Session \(record.shortID): not reachable, no message")
            }
        }
        session.transferUserInfo(payload)
        Diag.log("WC", "Session \(record.shortID) queued as userInfo (\(session.outstandingUserInfoTransfers.count) outstanding)")
    }

    /// Phone → watch: confirms a test run. Sent both ways, the watch ignores repeats.
    func sendTestAck(_ runID: UUID, kind: String) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        let payload: [String: Any] = ["testAck": runID.uuidString, "ackKind": kind]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                Diag.log("WC", "Ack \(kind) message failed: \(error.localizedDescription)")
            }
        }
        session.transferUserInfo(payload)
        Diag.log("WC", "Ack \(kind) for \(runID.short) sent (reachable: \(session.isReachable))")
    }

    #if os(watchOS)
    /// Watch → phone: the diagnostics log file.
    func sendLog(_ url: URL) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated else {
            Diag.log("WC", "Log not sent: session not activated")
            return
        }
        session.transferFile(url, metadata: ["kind": "diagnosticsLog"])
        Diag.log("WC", "Log file queued (\(session.outstandingFileTransfers.count) outstanding)")
    }
    #endif

    /// Remembers `plan` and pushes it now if possible; otherwise it goes out on the next activation.
    func send(_ plan: ActivePlan, info: PlanInfo? = nil) {
        lock.withLock {
            latestPlan = plan
            latestInfo = info
        }
        pushLatestPlan()
    }

    private func pushLatestPlan() {
        let (latest, info) = lock.withLock { (latestPlan, latestInfo) }
        guard let plan = latest, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            Diag.log("WC", "Plan send deferred: session not activated")
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else {
            Diag.log("WC", "Plan send deferred: paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled)")
            return
        }
        #endif
        do {
            var context: [String: Any] = ["plan": try JSONEncoder().encode(plan)]
            if let info { context["planInfo"] = try JSONEncoder().encode(info) }
            try session.updateApplicationContext(context)
        } catch {
            Diag.log("WC", "Plan send failed: \(error.localizedDescription)")
        }
    }

    #if os(watchOS)
    private func publishVersion() {
        guard WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(Self.ownVersion) else { return }
        do {
            try WCSession.default.updateApplicationContext(["appVersion": data])
        } catch {
            Diag.log("WC", "Version publish failed: \(error.localizedDescription)")
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
            self?.handle(reply, path: "version reply")
        }, errorHandler: { error in
            Diag.log("WC", "Version request failed: \(error.localizedDescription)")
        })
    }

    private func reportWatchState(_ session: WCSession) {
        let installed = session.isPaired && session.isWatchAppInstalled
        let watch = lock.withLock { lastWatchVersion }
        Task { @MainActor in self.onWatchState?(watch, installed) }
    }
    #endif

    /// One line describing the session, for the log.
    static func describe(_ session: WCSession) -> String {
        var parts = ["state=\(session.activationState.rawValue)", "reachable=\(session.isReachable)"]
        #if os(iOS)
        parts += ["paired=\(session.isPaired)", "watchAppInstalled=\(session.isWatchAppInstalled)"]
        #else
        parts += ["companionInstalled=\(session.isCompanionAppInstalled)"]
        #endif
        parts.append("outstandingUserInfo=\(session.outstandingUserInfoTransfers.count)")
        return parts.joined(separator: " ")
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { Diag.log("WC", "Activation failed: \(error.localizedDescription)") }
        Diag.log("WC", "Activated: \(Self.describe(session))")
        handle(session.receivedApplicationContext, path: "context (on activation)")
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
            return
        }
        handle(message, path: "message")
        replyHandler(["received": true])
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message, path: "message")
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo, path: "userInfo")
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let what = userInfoTransfer.userInfo.keys.sorted().joined(separator: ",")
        Diag.log("WC", "userInfo [\(what)] delivered\(error.map { " with error: \($0.localizedDescription)" } ?? "")")
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext, path: "context")
    }

    #if os(watchOS)
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Diag.log("WC", "Log file transfer \(error.map { "failed: \($0.localizedDescription)" } ?? "delivered")")
    }
    #endif

    #if os(iOS)
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted once this returns, so read it now.
        let count = DiagStore.shared.importWatchLog(from: file.fileURL)
        Diag.log("WC", "Watch log received: \(count) entries")
    }
    #endif

    private func handle(_ message: [String: Any], path: String) {
        let sentAt = (message["sentAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        if let data = message["session"] as? Data {
            if let record = try? JSONDecoder().decode(SessionRecord.self, from: data) {
                Diag.log("WC", "Session \(record.shortID)\(record.isTestRun ? " (test)" : "") via \(path), "
                         + "\(Diag.delay(since: sentAt)) after send, app \(Diag.phase)")
                if record.isTestRun {
                    Task { @MainActor in self.onTestRun?(record, path, sentAt) }
                } else {
                    Task { @MainActor in self.deliver(record) }
                }
            } else {
                Diag.log("WC", "Session via \(path) could not be decoded")
            }
        }
        if let id = (message["testAck"] as? String).flatMap(UUID.init(uuidString:)) {
            let kind = message["ackKind"] as? String ?? "received"
            Task { @MainActor in self.onTestAck?(id, kind, path) }
        }
        if let data = message["plan"] as? Data, let plan = try? JSONDecoder().decode(ActivePlan.self, from: data) {
            let info = (message["planInfo"] as? Data).flatMap { try? JSONDecoder().decode(PlanInfo.self, from: $0) }
            Diag.log("WC", "Plan via \(path): \(plan.title)\(info?.zones == nil ? "" : ", with zones")")
            Task { @MainActor in self.onPlan?(plan, info) }
        }
        #if os(iOS)
        if let data = message["appVersion"] as? Data, let version = try? JSONDecoder().decode(AppVersion.self, from: data) {
            Diag.log("WC", "Watch version via \(path): \(version.label)")
            lock.withLock { lastWatchVersion = version }
            reportWatchState(.default)
        }
        #endif
    }

    @MainActor
    private func deliver(_ record: SessionRecord) {
        if let onSession {
            onSession(record)
        } else {
            pendingSessions.append(record)
            Diag.log("WC", "Session \(record.shortID) held until the app model is ready")
        }
    }

    @MainActor
    private func flushPendingSessions() {
        guard let onSession, !pendingSessions.isEmpty else { return }
        let held = pendingSessions
        pendingSessions = []
        held.forEach(onSession)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { Diag.log("WC", "Became inactive") }
    func sessionDidDeactivate(_ session: WCSession) {
        Diag.log("WC", "Deactivated, reactivating")
        session.activate()
    }
    /// Pairing or watch-app install changed (e.g. the watch app was just installed): resend.
    func sessionWatchStateDidChange(_ session: WCSession) {
        Diag.log("WC", "Watch state changed: \(Self.describe(session))")
        pushLatestPlan()
        reportWatchState(session)
    }
    #endif

    func sessionReachabilityDidChange(_ session: WCSession) {
        Diag.log("WC", "Reachable: \(session.isReachable)")
        #if os(iOS)
        if session.isReachable { refreshWatchState() }
        #endif
    }
}

extension UUID {
    /// First 8 hex digits, for log lines.
    var short: String { String(uuidString.prefix(8)).lowercased() }
}

extension SessionRecord {
    var shortID: String { id.short }
}
