import Foundation
import RunSteadyKit
import SwiftUI

/// Drives the pure `WorkoutEngine` with wall-clock time and glues it to sensors and cues.
@MainActor
final class WorkoutManager: ObservableObject {
    enum Screen { case start, active, summary }

    @Published var screen = Screen.start
    @Published var plan = ActivePlan.initial
    @Published private(set) var engine: WorkoutEngine?
    @Published private(set) var distance = 0.0
    @Published private(set) var heartRate: Double?
    @Published private(set) var pace: Double?
    @Published private(set) var lastRecord: SessionRecord?
    @Published private(set) var savedToHealth = false

    var onFinish: ((SessionRecord) -> Void)?

    /// > 1 fast-forwards workout time (Simulator demos only).
    private let timeScale: Double
    private var sensor: WorkoutSensor
    private let cues = Cues()
    private var timer: Timer?
    private var lastTick = Date()
    private var startedAt = Date()
    private var clock = 0.0
    private var paceSamples: [(time: Double, distance: Double)] = []
    private var heartRateSum = 0.0
    private var heartRateTime = 0.0
    private var nextKilometre = 1

    init() {
        let scale = UserDefaults.standard.double(forKey: "timeScale")
        timeScale = scale > 0 ? scale : 1
        sensor = Self.makeSensor()
    }

    private static func makeSensor() -> WorkoutSensor {
        #if targetEnvironment(simulator)
        if !UserDefaults.standard.bool(forKey: "useHealthKit") { return SimulatedSensor() }
        #endif
        return HealthKitSensor()
    }

    var announceKilometres: Bool {
        UserDefaults.standard.object(forKey: "announceKm") as? Bool ?? true
    }

    func start() {
        sensor = Self.makeSensor()
        engine = WorkoutEngine(schedule: plan.schedule)
        distance = 0; heartRate = nil; pace = nil
        clock = 0; paceSamples = []; heartRateSum = 0; heartRateTime = 0; nextKilometre = 1
        startedAt = Date()
        lastTick = Date()
        screen = .active
        Task { await sensor.start() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func next() {
        cues.acknowledged()
        engine?.next()
        finishIfNeeded()
    }

    func beginCoolDown() {
        cues.acknowledged()
        engine?.beginCoolDown()
        finishIfNeeded()
    }

    func togglePause() {
        guard var engine else { return }
        if engine.isPaused { engine.resume(); sensor.resume() } else { engine.pause(); sensor.pause() }
        self.engine = engine
    }

    func finish() {
        cues.acknowledged()
        engine?.finish()
        finishIfNeeded()
    }

    func dismissSummary() {
        engine = nil
        screen = .start
    }

    private func tick() {
        guard var engine, !engine.isFinished else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick) * timeScale
        lastTick = now
        guard !engine.isPaused else { return }

        let events = engine.tick(dt)
        clock += dt
        sensor.advance(by: dt, kind: engine.current.kind)
        distance = sensor.distance
        heartRate = sensor.heartRate
        if let hr = sensor.heartRate { heartRateSum += hr * dt; heartRateTime += dt }
        updatePace()
        self.engine = engine

        if events.contains(where: { if case .targetReached = $0 { true } else { false } }) {
            cues.targetReached()
        }
        if distance >= Double(nextKilometre) * 1000 {
            if announceKilometres {
                cues.announce(kilometre: nextKilometre, paceSecondsPerKm: clock / (distance / 1000))
            }
            nextKilometre += 1
        }
    }

    /// Rolling pace over roughly the last 45 seconds of workout time.
    private func updatePace() {
        paceSamples.append((clock, distance))
        while let first = paceSamples.first, clock - first.time > 45, paceSamples.count > 2 { paceSamples.removeFirst() }
        guard let first = paceSamples.first, distance - first.distance > 8 else { return }
        pace = (clock - first.time) / ((distance - first.distance) / 1000)
    }

    private func finishIfNeeded() {
        guard let engine, engine.isFinished, screen == .active else { return }
        timer?.invalidate()
        timer = nil
        let record = SessionRecord(
            startedAt: startedAt, schedule: plan.schedule, stageIndex: plan.stageIndex, sessionInStage: plan.sessionInStage,
            segments: engine.completed, distanceMeters: distance,
            averageHeartRate: heartRateTime > 0 ? heartRateSum / heartRateTime : nil)
        lastRecord = record
        savedToHealth = sensor.savesToHealth
        let sensor = sensor
        Task { await sensor.end() }
        onFinish?(record)
        screen = .summary
    }
}
