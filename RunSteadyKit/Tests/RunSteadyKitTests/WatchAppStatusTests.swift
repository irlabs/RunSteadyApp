import Testing
@testable import RunSteadyKit

@Suite struct WatchAppStatusTests {
    private let phone = AppVersion(version: "1.1", build: "261116.1530", syncProtocol: 2)

    @Test func notInstalledWinsOverAnyStaleReport() {
        let watch = AppVersion(version: "1.1", build: "261116.1530", syncProtocol: 2)
        #expect(WatchAppStatus.evaluate(phone: phone, watch: watch, watchAppInstalled: false) == .notInstalled)
        #expect(WatchAppStatus.evaluate(phone: phone, watch: nil, watchAppInstalled: false) == .notInstalled)
    }

    @Test func installedButSilentIsUnknown() {
        #expect(WatchAppStatus.evaluate(phone: phone, watch: nil, watchAppInstalled: true) == .unknown)
    }

    @Test func sameBuildIsUpToDate() {
        let watch = AppVersion(version: "1.1", build: "261116.1530", syncProtocol: 2)
        #expect(WatchAppStatus.evaluate(phone: phone, watch: watch, watchAppInstalled: true) == .upToDate)
    }

    @Test func differentBuildWithCompatibleProtocolIsOutdated() {
        let watch = AppVersion(version: "1.0", build: "261110.0900", syncProtocol: SyncProtocol.minimumWatch)
        #expect(WatchAppStatus.evaluate(phone: phone, watch: watch, watchAppInstalled: true) == .outdated(watch: watch))
    }

    @Test func protocolBelowMinimumIsTooOld() {
        let watch = AppVersion(version: "0.9", build: "261101.0900", syncProtocol: SyncProtocol.minimumWatch - 1)
        #expect(WatchAppStatus.evaluate(phone: phone, watch: watch, watchAppInstalled: true) == .tooOld(watch: watch))
    }
}
