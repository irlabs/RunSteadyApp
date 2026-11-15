import CoreLocation
import Foundation
import HealthKit
import RunSteadyKit

/// Source of live workout metrics. The HealthKit implementation runs a real workout session;
/// the simulated one produces plausible numbers so the app can be exercised in the Simulator.
@MainActor
protocol WorkoutSensor: AnyObject {
    var distance: Double { get }
    var heartRate: Double? { get }
    var savesToHealth: Bool { get }
    func start() async
    func pause()
    func resume()
    func end() async
    /// Workout time moved forward by `dt` seconds (only the simulated sensor cares).
    func advance(by dt: TimeInterval, kind: SegmentKind)
}

@MainActor
final class HealthKitSensor: NSObject, WorkoutSensor {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()

    private(set) var distance = 0.0
    private(set) var heartRate: Double?
    let savesToHealth = true

    func start() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)

            let config = HKWorkoutConfiguration()
            config.activityType = .running
            config.locationType = .outdoor

            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            builder.delegate = self
            self.session = session
            self.builder = builder

            routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            locationManager.delegate = self
            locationManager.activityType = .fitness
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()

            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
        } catch {
            print("HealthKit workout could not start: \(error)")
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func advance(by dt: TimeInterval, kind: SegmentKind) {}

    func end() async {
        locationManager.stopUpdatingLocation()
        guard let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            if let workout = try await builder.finishWorkout() {
                try await routeBuilder?.finishRoute(with: workout, metadata: nil)
            }
        } catch {
            print("HealthKit workout could not be saved: \(error)")
        }
    }
}

extension HealthKitSensor: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: bpm)
        let meters = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
        Task { @MainActor in
            if let hr { self.heartRate = hr }
            if let meters { self.distance = meters }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension HealthKitSensor: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let usable = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard !usable.isEmpty else { return }
        Task { @MainActor in
            self.routeBuilder?.insertRouteData(usable) { _, _ in }
        }
    }
}

/// Fake metrics for the Simulator: jogging and walking speeds with a heart rate that follows effort.
@MainActor
final class SimulatedSensor: WorkoutSensor {
    private(set) var distance = 0.0
    private(set) var heartRate: Double? = 88
    let savesToHealth = false
    private var clock = 0.0

    func start() async {}
    func pause() {}
    func resume() {}
    func end() async {}

    func advance(by dt: TimeInterval, kind: SegmentKind) {
        clock += dt
        let wobble = sin(clock / 17) * 0.08
        let speed: Double
        let targetHR: Double
        switch kind {
        case .warmUp: (speed, targetHR) = (1.45, 104)
        case .run: (speed, targetHR) = (2.35, 146)
        case .walk: (speed, targetHR) = (1.55, 121)
        case .coolDown: (speed, targetHR) = (1.35, 108)
        }
        distance += (speed + wobble) * dt
        let current = heartRate ?? 88
        heartRate = current + (targetHR - current) * min(1, dt / 28)
    }
}
