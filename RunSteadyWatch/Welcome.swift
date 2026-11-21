import CoreLocation
import HealthKit
import RunSteadyKit
import SwiftUI

/// Everything the watch asks Health for. The phone's grant does not cover the watch (spike S3),
/// so the watch asks for itself, once, on the welcome screen.
enum WatchHealth {
    static let store = HKHealthStore()

    static var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        // Effort score needs watchOS 11; the Series 5 stays on 10 (the phone writes it instead).
        if #available(watchOS 11.0, *) { types.insert(HKQuantityType(.workoutEffortScore)) }
        return types
    }

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.activeEnergyBurned),
        HKCharacteristicType(.dateOfBirth),
    ]

    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            Diag.log("HealthKit", "Request finished (watch)")
        } catch {
            Diag.log("HealthKit", "Request failed (watch): \(error.localizedDescription)")
        }
    }

    /// F9 fallback when the phone sent no zones: the watch's own date of birth (needs its own grant).
    static func zonesFromDateOfBirth() -> HeartRateZones? {
        do {
            return HeartRateZones(birth: try store.dateOfBirthComponents())
        } catch {
            Diag.log("HealthKit", "Date of birth (watch) unavailable: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Asks for location once and waits for the answer.
@MainActor
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    func request() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.delegate = self
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            Diag.log("Location", "Authorization: \(status.label)")
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}

/// F1: shown once, on the first launch. Asks for Health and location before the first run,
/// so no permission sheet pops up at the start line.
struct WelcomeView: View {
    var onDone: () -> Void
    @State private var asking = false
    @State private var location = LocationPermission()

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TortoiseView().frame(width: 58)
                Text("Hi, I'm Steady").font(.headline)
                Text("Steady tracks your runs with Health + GPS: heart rate, distance and your route.")
                    .font(.footnote).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await continueTapped() }
                } label: {
                    Text(asking ? "One moment…" : "Continue").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(color: .brand))
                .disabled(asking)
                .accessibilityIdentifier("welcomeContinue")
            }
            .padding(.horizontal, 4)
        }
    }

    private func continueTapped() async {
        asking = true
        await WatchHealth.requestAuthorization()
        await location.request()
        asking = false
        onDone()
    }
}
