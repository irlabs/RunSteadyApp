import Foundation

/// Timer-style workout state machine. It never advances on its own: when a segment's target
/// is reached it reports `.targetReached` once and keeps counting until `next()` is called.
/// Time is fed in through `tick(_:)`, so the engine is deterministic and platform-free.
public struct WorkoutEngine: Sendable {
    public struct ActiveSegment: Hashable, Sendable {
        public var kind: SegmentKind
        public var round: Int
        public var target: Int
        public var elapsedExact: TimeInterval = 0

        public var elapsed: Int { Int(elapsedExact) }
        public var overrun: Int { max(0, elapsed - target) }
        public var remaining: Int { max(0, target - elapsed) }
        public var isOverTarget: Bool { elapsed >= target }
        public var progress: Double { target > 0 ? min(1, elapsedExact / Double(target)) : 1 }
    }

    public enum Event: Hashable, Sendable {
        case targetReached(SegmentKind)
    }

    public let schedule: Schedule
    public private(set) var current: ActiveSegment
    public private(set) var completed: [SegmentRecord] = []
    public private(set) var isPaused = false
    public private(set) var isFinished = false
    private var targetAnnounced = false

    public init(schedule: Schedule) {
        self.schedule = schedule
        current = schedule.warmUp > 0
            ? ActiveSegment(kind: .warmUp, round: 0, target: schedule.warmUp)
            : ActiveSegment(kind: .run, round: 1, target: schedule.run)
    }

    public var totalElapsed: Int {
        completed.reduce(0) { $0 + $1.actual } + (isFinished ? 0 : current.elapsed)
    }

    public var extraRounds: Int { max(0, current.round - schedule.rounds) }

    /// True once the planned rounds are (about to be) done, i.e. when cool-down makes sense.
    public var isInFinalPlannedRoundOrBeyond: Bool {
        (current.kind == .run || current.kind == .walk) && current.round >= schedule.rounds
    }

    @discardableResult
    public mutating func tick(_ dt: TimeInterval) -> [Event] {
        guard !isPaused, !isFinished, dt > 0 else { return [] }
        current.elapsedExact += dt
        if !targetAnnounced, current.isOverTarget {
            targetAnnounced = true
            return [.targetReached(current.kind)]
        }
        return []
    }

    /// The main action: close the current segment and start counting the following one.
    /// Warm-up → run 1 → walk 1 → run 2 → … (extra rounds just keep coming) ; cool-down → finished.
    public mutating func next() {
        guard !isFinished else { return }
        switch current.kind {
        case .warmUp:
            start(.run, round: 1)
        case .run:
            if schedule.walk > 0 { start(.walk, round: current.round) } else { start(.run, round: current.round + 1) }
        case .walk:
            start(.run, round: current.round + 1)
        case .coolDown:
            finish()
        }
    }

    public mutating func beginCoolDown() {
        guard !isFinished, current.kind != .coolDown else { return }
        if schedule.coolDown > 0 { start(.coolDown, round: 0) } else { finish() }
    }

    public mutating func pause() { isPaused = true }
    public mutating func resume() { isPaused = false }

    public mutating func finish() {
        guard !isFinished else { return }
        closeCurrent()
        isFinished = true
        isPaused = false
    }

    private mutating func start(_ kind: SegmentKind, round: Int) {
        closeCurrent()
        let target: Int
        switch kind {
        case .warmUp: target = schedule.warmUp
        case .run: target = schedule.run
        case .walk: target = schedule.walk
        case .coolDown: target = schedule.coolDown
        }
        current = ActiveSegment(kind: kind, round: round, target: target)
        targetAnnounced = false
    }

    private mutating func closeCurrent() {
        guard current.elapsed > 0 else { return }
        completed.append(SegmentRecord(kind: current.kind, round: current.round, target: current.target, actual: current.elapsed))
    }
}
