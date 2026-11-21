import Foundation

/// The version an app reports about itself: the marketing version from `VERSION`, the build stamp
/// the build script adds, and the phone ↔ watch sync protocol the binary speaks.
public struct AppVersion: Codable, Equatable, Sendable {
    public var version: String
    public var build: String
    public var syncProtocol: Int

    public init(version: String, build: String, syncProtocol: Int = SyncProtocol.current) {
        self.version = version
        self.build = build
        self.syncProtocol = syncProtocol
    }

    /// Reads `CFBundleShortVersionString` / `CFBundleVersion` from an Info.plist dictionary.
    public init(infoDictionary info: [String: Any]?) {
        self.init(version: info?["CFBundleShortVersionString"] as? String ?? "?",
                  build: info?["CFBundleVersion"] as? String ?? "?")
    }

    /// "v1.0 (261116.1530)"
    public var label: String { "v\(version) (\(build))" }
}

/// Version of the messages phone and watch exchange (`SessionRecord`, `ActivePlan` payloads and
/// their keys). Bump `current` whenever a change would break an older counterpart; raise
/// `minimumWatch` when the phone can no longer work with watches below it.
public enum SyncProtocol {
    public static let current = 1
    public static let minimumWatch = 1
}

/// What the Today screen says about the watch app.
public enum WatchAppStatus: Equatable, Sendable {
    /// No paired watch, or the watch app is not installed on it.
    case notInstalled
    /// Installed, but it has not reported its version yet (never opened since this check existed).
    case unknown
    case upToDate
    /// Built from different code than this phone app (older or newer), but it still speaks a
    /// protocol the phone accepts. Build numbers name the code they were built from.
    case differs(watch: AppVersion)
    /// Speaks a sync protocol below `SyncProtocol.minimumWatch`: runs and plans won't sync correctly.
    case tooOld(watch: AppVersion)

    public static func evaluate(phone: AppVersion, watch: AppVersion?, watchAppInstalled: Bool) -> WatchAppStatus {
        // A stale report from an uninstalled watch app means nothing.
        guard watchAppInstalled else { return .notInstalled }
        guard let watch else { return .unknown }
        // Compatibility first: a too-old protocol is a problem whatever the build.
        if watch.syncProtocol < SyncProtocol.minimumWatch { return .tooOld(watch: watch) }
        // Same build number = built from the same code (scripts/stamp-version: time of the newest source change).
        return watch.build == phone.build ? .upToDate : .differs(watch: watch)
    }
}
