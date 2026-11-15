import Testing
@testable import RunSteadyKit

private let schedule = Schedule(name: "Test", warmUp: 300, run: 60, walk: 120, rounds: 2, coolDown: 300)

@Suite struct WorkoutEngineTests {
    @Test func startsInWarmUp() {
        let engine = WorkoutEngine(schedule: schedule)
        #expect(engine.current.kind == .warmUp)
        #expect(engine.current.target == 300)
        #expect(engine.current.elapsed == 0)
    }

    @Test func keepsCountingPastTargetUntilNext() {
        var engine = WorkoutEngine(schedule: schedule)
        engine.next() // -> run 1
        _ = engine.tick(60)
        _ = engine.tick(25)
        #expect(engine.current.kind == .run)
        #expect(engine.current.elapsed == 85)
        #expect(engine.current.overrun == 25)
        engine.next()
        #expect(engine.current.kind == .walk)
        #expect(engine.current.elapsed == 0)
        #expect(engine.completed.last?.actual == 85)
        #expect(engine.completed.last?.overrun == 25)
    }

    @Test func targetReachedFiresExactlyOnce() {
        var engine = WorkoutEngine(schedule: schedule)
        engine.next()
        #expect(engine.tick(59) == [])
        #expect(engine.tick(1) == [.targetReached(.run)])
        #expect(engine.tick(10) == [])
    }

    @Test func pauseStopsTheClock() {
        var engine = WorkoutEngine(schedule: schedule)
        _ = engine.tick(10)
        engine.pause()
        _ = engine.tick(100)
        #expect(engine.current.elapsed == 10)
        engine.resume()
        _ = engine.tick(5)
        #expect(engine.current.elapsed == 15)
    }

    @Test func startRunEarlyRecordsShortWarmUp() {
        var engine = WorkoutEngine(schedule: schedule)
        _ = engine.tick(120)
        engine.next()
        #expect(engine.current.kind == .run)
        #expect(engine.current.round == 1)
        #expect(engine.completed == [SegmentRecord(kind: .warmUp, round: 0, target: 300, actual: 120)])
    }

    @Test func roundsAlternateAndExtraRoundsAreCounted() {
        var engine = WorkoutEngine(schedule: schedule)
        engine.next() // run 1
        engine.next() // walk 1
        engine.next() // run 2
        #expect(engine.current.round == 2)
        #expect(engine.isInFinalPlannedRoundOrBeyond)
        engine.next() // walk 2
        engine.next() // run 3 (extra)
        #expect(engine.current.kind == .run)
        #expect(engine.current.round == 3)
        #expect(engine.extraRounds == 1)
    }

    @Test func coolDownThenNextFinishes() {
        var engine = WorkoutEngine(schedule: schedule)
        _ = engine.tick(300)
        engine.next()
        _ = engine.tick(60)
        engine.beginCoolDown()
        #expect(engine.current.kind == .coolDown)
        _ = engine.tick(300)
        engine.next()
        #expect(engine.isFinished)
        #expect(engine.completed.map(\.kind) == [.warmUp, .run, .coolDown])
    }

    @Test func finishAnytimeRecordsCurrentSegment() {
        var engine = WorkoutEngine(schedule: schedule)
        engine.next()
        _ = engine.tick(30)
        engine.finish()
        #expect(engine.isFinished)
        #expect(engine.completed.last == SegmentRecord(kind: .run, round: 1, target: 60, actual: 30))
        _ = engine.tick(30)
        #expect(engine.totalElapsed == 30)
    }

    @Test func continuousRunSkipsZeroLengthWalk() {
        let continuous = Schedule(name: "30", warmUp: 300, run: 1800, walk: 0, rounds: 1, coolDown: 300)
        var engine = WorkoutEngine(schedule: continuous)
        engine.next() // run 1
        engine.next() // no walk -> run 2 (extra)
        #expect(engine.current.kind == .run)
        #expect(engine.current.round == 2)
    }

    @Test func scheduleTotals() {
        #expect(schedule.totalSeconds == 300 + 2 * 180 + 300)
        #expect(schedule.plannedSegments.map(\.kind) == [.warmUp, .run, .walk, .run, .walk, .coolDown])
    }

    @Test func formatting() {
        #expect(Format.clock(65) == "1:05")
        #expect(Format.clock(3725) == "1:02:05")
        #expect(Format.pace(secondsPerKm: 462) == "7:42")
        #expect(Format.pace(secondsPerKm: nil) == "–:––")
        #expect(Format.km(meters: 2340) == "2.34")
        #expect(Format.minutes(90) == "1:30 min")
        #expect(Format.minutes(120) == "2 min")
    }
}
